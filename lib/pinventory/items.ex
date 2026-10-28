defmodule Pinventory.Items do
  @moduledoc """
  The Items context.

  Name search matches typed letters in order, like fzf (see
  `Pinventory.Items.NameSearch`). Case folding is ASCII A–Z only, so non-ASCII
  letters match only in the same case.

  Mutating APIs take an authenticated `Pinventory.Accounts.Scope` as the first
  argument and write audit events in the same transaction as the change.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.Accounts.Scope
  alias Pinventory.Audit
  alias Pinventory.Audit.Event
  alias Pinventory.Repo

  alias Pinventory.Items.DraftStock
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Items.NameSearch
  alias Pinventory.Items.NoteVersion
  alias Pinventory.Locations.Location

  @doc """
  Suggests items whose names match the typed text, best match first.

  Matching and ranking follow `Pinventory.Items.NameSearch`. Blank input
  returns `[]`.
  """
  def suggest_items(text, opts \\ []) do
    opts = Keyword.validate!(opts, limit: 10)

    case text |> to_string() |> NameSearch.parse() do
      nil ->
        []

      terms ->
        Item
        |> from(as: :item)
        |> NameSearch.where_matches(terms)
        |> NameSearch.order_by_rank(terms)
        |> limit(^opts[:limit])
        |> Repo.all()
    end
  end

  @doc """
  Lists items ordered by name, or best match first when filtered by name.

  Each item includes virtual `total_quantity` (sum of stock) and
  `location_count` (number of locations with stock).

  Options:

    * `:filter` - typed text matched against names by
      `Pinventory.Items.NameSearch` (blank means no filter). Results come
      best match first, ranked like `suggest_items/2`.
    * `:location_id` - only items with stock at this location
    * `:limit` - max rows (default 100)
  """
  def list_items(opts \\ []) do
    opts = Keyword.validate!(opts, [:filter, :location_id, limit: 100])

    Item
    |> from(as: :item)
    |> join(:left, [item: item], il in assoc(item, :item_locations), as: :item_location)
    |> maybe_filter_name(opts[:filter])
    |> maybe_filter_location(opts[:location_id])
    |> group_by([item: item], item.id)
    |> order_by([item: item], asc: item.name)
    |> limit(^opts[:limit])
    |> select_merge([item_location: il], %{
      total_quantity: coalesce(sum(il.quantity), 0),
      location_count: count(il.id)
    })
    |> Repo.all()
  end

  @doc """
  Finds items whose names match any of `terms`, best match first.

  Each term is typed text matched by `Pinventory.Items.NameSearch`, the same
  loose matching as the Items page filter, so "towel" finds "Paper Towels" and
  also "Tool wheel". Notes are not searched. Items that match more terms come
  first, then better matches.

  Blank terms are ignored, so `[]` or only blank terms return `[]`.

  Options:

    * `:location_id` - only items with stock at this location
    * `:limit` - max items returned (default 50)
  """
  def search_items(terms, opts \\ []) when is_list(terms) do
    opts = Keyword.validate!(opts, [:location_id, limit: 50])

    case terms |> Enum.map(&NameSearch.parse(to_string(&1))) |> Enum.reject(&is_nil/1) do
      [] ->
        []

      groups ->
        Item
        |> from(as: :item)
        |> NameSearch.where_matches_any(groups)
        |> maybe_filter_location(opts[:location_id])
        |> NameSearch.order_by_groups(groups)
        |> limit(^opts[:limit])
        |> Repo.all()
    end
  end

  @doc """
  Lists items stored at one location, ordered by name.

  Each item includes virtual `quantity` for **this location only**.
  Unlike `list_items/1` with `:location_id`, this does not sum stock
  across other locations.
  """
  def list_items_at_location(location_id)
      when is_binary(location_id) and location_id != "" do
    Item
    |> from(as: :item)
    |> join(:inner, [item: item], il in assoc(item, :item_locations), as: :item_location)
    |> where([item_location: il], il.location_id == ^location_id)
    |> order_by([item: item], asc: item.name)
    |> select_merge([item_location: il], %{quantity: il.quantity})
    |> Repo.all()
  end

  def list_items_at_location(_), do: []

  defp maybe_filter_name(query, filter) when is_binary(filter) do
    case NameSearch.parse(filter) do
      nil -> query
      terms -> query |> NameSearch.where_matches(terms) |> NameSearch.order_by_rank(terms)
    end
  end

  defp maybe_filter_name(query, _), do: query

  defp maybe_filter_location(query, location_id)
       when is_binary(location_id) and location_id != "" do
    where(
      query,
      [item: item],
      exists(
        from il in ItemLocation,
          where: il.item_id == parent_as(:item).id and il.location_id == ^location_id
      )
    )
  end

  defp maybe_filter_location(query, _), do: query

  def get_item(id) do
    case Repo.get(Item, id) do
      nil -> nil
      item -> Repo.preload(item, :item_locations)
    end
  end

  def get_item!(id) do
    Item
    |> Repo.get!(id)
    |> Repo.preload(:item_locations)
  end

  def change_item(%Item{} = item, attrs \\ %{}) do
    Item.changeset(item, attrs)
  end

  @doc """
  Creates an item and stores stock for locations with quantity greater than zero.

  Writes audit events (`item.created` and any `stock.changed`) under one
  `edit_id`.

  `quantities` is a **full replacement** map of `location_id => quantity`.
  Only positive quantities are stored; omitted locations and zeros are not.
  Defaults to `%{}` (create with no stock rows).
  """
  def create_item(%Scope{} = scope, attrs, quantities \\ %{}) do
    user_id = Audit.actor_id(scope)
    edit_id = Audit.new_edit_id()
    desired = normalize_desired_stock(quantities)

    Multi.new()
    |> Multi.insert(:item, change_item(%Item{}, attrs))
    |> Multi.run(:stock, fn repo, %{item: item} ->
      sync_stock(repo, item.id, desired)
    end)
    |> Multi.run(:audit_events, fn repo, %{item: item} ->
      location_names = location_names(repo, Map.keys(desired))

      events =
        [
          Audit.item_event_attrs(
            action: "item.created",
            edit_id: edit_id,
            user_id: user_id,
            item: item,
            changes: %{"name" => %{"from" => nil, "to" => item.name}},
            edit_seq: 0
          )
        ] ++
          initial_notes_events(item, edit_id, user_id)

      events =
        events ++
          Audit.stock_change_attrs(
            edit_id: edit_id,
            user_id: user_id,
            item_id: item.id,
            item_name: item.name,
            before: %{},
            after: desired,
            location_names: location_names,
            start_seq: length(events)
          )

      Audit.insert_events(repo, Audit.with_actor(events, scope))
    end)
    |> Multi.run(:result, fn repo, %{item: item} ->
      {:ok, repo.preload(item, :item_locations)}
    end)
    |> Repo.transaction()
    |> unwrap_item_transaction()
  end

  @doc """
  Updates an item's name and notes and replaces stock so only positive
  quantities remain.

  Skips the write (and audit) when the name, notes, and stock are unchanged.
  All events for a successful save share one `edit_id`. A notes change is its
  own `item.notes_changed` event with the full old and new text, so the audit
  log is the note's version history (see `note_versions/1`).

  `item` must be the copy the user started editing. If another save changed
  the item since then, nothing is written and `{:error, :stale}` is returned.

  `quantities` is a **full replacement** map of `location_id => quantity`.
  Locations omitted from the map or set to 0 are cleared (and audited as
  quantity → 0 when they previously had stock). Defaults to `%{}`, which
  clears all stock. Always pass the complete desired stock map when updating.
  """
  def update_item(%Scope{} = scope, %Item{} = item, attrs, quantities \\ %{}) do
    user_id = Audit.actor_id(scope)
    edit_id = Audit.new_edit_id()
    item = ensure_item_locations(item)
    before_stock = stock_map(item)
    desired = normalize_desired_stock(quantities)
    changeset = change_item(item, attrs)
    field_events = item_field_events(changeset)

    cond do
      not changeset.valid? ->
        {:error, changeset}

      field_events == [] and not stock_changed?(before_stock, desired) ->
        {:ok, item}

      true ->
        # Stock-only saves leave the item row unchanged, and optimistic_lock
        # skips unchanged rows, so force the version bump to check every save.
        changeset =
          changeset
          |> Ecto.Changeset.force_change(:lock_version, item.lock_version)
          |> Ecto.Changeset.optimistic_lock(:lock_version)

        Multi.new()
        |> Multi.update(:item, changeset, stale_error_field: :lock_version)
        |> Multi.run(:stock, fn repo, %{item: updated} ->
          sync_stock(repo, updated.id, desired)
        end)
        |> Multi.run(:audit_events, fn repo, %{item: updated} ->
          location_names = location_names(repo, Map.keys(before_stock) ++ Map.keys(desired))

          item_events =
            field_events
            |> Enum.with_index()
            |> Enum.map(fn {{action, changes}, seq} ->
              Audit.item_event_attrs(
                action: action,
                edit_id: edit_id,
                user_id: user_id,
                item: updated,
                changes: changes,
                edit_seq: seq
              )
            end)

          stock_events =
            Audit.stock_change_attrs(
              edit_id: edit_id,
              user_id: user_id,
              item_id: updated.id,
              item_name: updated.name,
              before: before_stock,
              after: desired,
              location_names: location_names,
              start_seq: length(item_events)
            )

          Audit.insert_events(repo, Audit.with_actor(item_events ++ stock_events, scope))
        end)
        |> Multi.run(:result, fn repo, %{item: updated} ->
          {:ok, repo.preload(updated, :item_locations, force: true)}
        end)
        |> Repo.transaction()
        |> unwrap_item_transaction()
    end
  end

  @type stock_error ::
          :item_not_found
          | :location_not_found
          | :same_location
          | :too_many
          | {:below_zero, non_neg_integer()}
          | {:not_enough, non_neg_integer()}

  @doc """
  Changes one item's count at one location, leaving its other locations as
  they are.

  `{:add, n}` adds `n`, which may be negative. `{:set, n}` replaces the count.
  The count is read fresh inside the write transaction, so a concurrent save
  can't land between the read and the write. The change goes through
  `update_item/4`, so it records in Activity like an edit-page save.

  Returns the updated item and the count before and after. Nothing is
  written when the result would be below 0 or above
  `Pinventory.Items.DraftStock.max_quantity/0`.
  """
  @spec change_stock(Scope.t(), binary(), binary(), {:add, integer()} | {:set, integer()}) ::
          {:ok, %{item: %Item{}, from: non_neg_integer(), to: non_neg_integer()}}
          | {:error, stock_error()}
  def change_stock(%Scope{} = scope, item_id, location_id, {op, n} = change)
      when op in [:add, :set] and is_integer(n) do
    with {:ok, %{item: item, counts: %{^location_id => counts}}} <-
           write_stock(scope, item_id, [location_id], &changed_count(&1, location_id, change)) do
      {:ok, Map.put(counts, :item, item)}
    end
  end

  @doc """
  Moves `quantity` of one item from one location to another as one edit.

  Both counts change in one transaction, so either both apply or neither
  does. Activity shows one edit with a line per location.
  """
  @spec move_stock(Scope.t(), binary(), binary(), binary(), pos_integer()) ::
          {:ok, %{item: %Item{}, from: map(), to: map()}} | {:error, stock_error()}
  def move_stock(%Scope{}, _item_id, location_id, location_id, _quantity),
    do: {:error, :same_location}

  def move_stock(%Scope{} = scope, item_id, from_id, to_id, quantity)
      when is_integer(quantity) and quantity > 0 do
    with {:ok, %{item: item, counts: counts}} <-
           write_stock(
             scope,
             item_id,
             [from_id, to_id],
             &moved_counts(&1, from_id, to_id, quantity)
           ) do
      {:ok, %{item: item, from: counts[from_id], to: counts[to_id]}}
    end
  end

  defp changed_count(stock, location_id, change) do
    current = Map.get(stock, location_id, 0)

    new =
      case change do
        {:add, delta} -> current + delta
        {:set, count} -> count
      end

    cond do
      new < 0 -> {:error, {:below_zero, current}}
      new > DraftStock.max_quantity() -> {:error, :too_many}
      true -> {:ok, %{location_id => new}}
    end
  end

  defp moved_counts(stock, from_id, to_id, quantity) do
    from = Map.get(stock, from_id, 0)
    to = Map.get(stock, to_id, 0)

    cond do
      quantity > from -> {:error, {:not_enough, from}}
      to + quantity > DraftStock.max_quantity() -> {:error, :too_many}
      true -> {:ok, %{from_id => from - quantity, to_id => to + quantity}}
    end
  end

  # Reads the item and computes the new counts inside the write transaction.
  # The repo uses immediate transactions, so SQLite holds the write lock from
  # the read on and no other save can change the counts in between.
  defp write_stock(scope, item_id, location_ids, compute) do
    Repo.transact(fn ->
      with {:ok, item} <- fetch_item_for_stock(item_id),
           :ok <- check_locations(location_ids),
           before = stock_map(item),
           {:ok, updates} <- compute.(before),
           {:ok, updated} <- update_item(scope, item, %{}, Map.merge(before, updates)) do
        counts =
          Map.new(updates, fn {id, to} -> {id, %{from: Map.get(before, id, 0), to: to}} end)

        {:ok, %{item: updated, counts: counts}}
      end
    end)
  end

  defp fetch_item_for_stock(item_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(item_id),
         %Item{} = item <- get_item(uuid) do
      {:ok, item}
    else
      _ -> {:error, :item_not_found}
    end
  end

  defp check_locations(location_ids) do
    with {:ok, uuids} <- cast_uuids(location_ids),
         count when count == length(uuids) <-
           Repo.aggregate(from(l in Location, where: l.id in ^uuids), :count) do
      :ok
    else
      _ -> {:error, :location_not_found}
    end
  end

  defp cast_uuids(ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        :error -> {:halt, :error}
      end
    end)
  end

  @doc """
  Returns every saved version of an item's notes, oldest first.

  Version 0 is the empty note every item starts with. Each later version
  comes from one `item.notes_changed` audit event.
  """
  def note_versions(item_id) when is_binary(item_id) do
    events =
      from(e in Event,
        where: e.item_id == ^item_id and e.action == "item.notes_changed",
        order_by: [asc: e.inserted_at, asc: fragment("rowid")],
        preload: [:user]
      )
      |> Repo.all()

    edits =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {event, number} ->
        %NoteVersion{
          number: number,
          text: event.changes["notes"]["to"],
          user: event.user,
          inserted_at: event.inserted_at,
          event_id: event.id
        }
      end)

    [%NoteVersion{number: 0, text: ""} | edits]
  end

  @doc """
  Deletes an item and records an `item.deleted` audit event in the same
  transaction.
  """
  def delete_item(%Scope{} = scope, %Item{} = item) do
    user_id = Audit.actor_id(scope)
    edit_id = Audit.new_edit_id()

    Multi.new()
    |> Multi.run(:audit_events, fn repo, _ ->
      Audit.insert_events(repo, [
        Audit.item_event_attrs(
          action: "item.deleted",
          edit_id: edit_id,
          user_id: user_id,
          item: item,
          changes: %{"name" => %{"from" => item.name, "to" => nil}},
          edit_seq: 0
        )
      ])
    end)
    |> Multi.delete(:item, item)
    |> Multi.run(:result, fn _repo, %{item: deleted} -> {:ok, deleted} end)
    |> Repo.transaction()
    |> unwrap_item_transaction()
  end

  @doc """
  Returns a map of `location_id => quantity` for the given item.
  Locations with no stored row are omitted (treat missing as zero in the UI).
  """
  def stock_map(%Item{item_locations: item_locations}) when is_list(item_locations) do
    Map.new(item_locations, &{&1.location_id, &1.quantity})
  end

  def stock_map(%Item{} = item) do
    item
    |> Repo.preload(:item_locations)
    |> stock_map()
  end

  defp ensure_item_locations(%Item{item_locations: item_locations} = item)
       when is_list(item_locations),
       do: item

  defp ensure_item_locations(%Item{} = item) do
    Repo.preload(item, :item_locations)
  end

  defp unwrap_item_transaction(result) do
    case result do
      {:ok, %{result: item}} -> {:ok, item}
      {:error, :item, %Ecto.Changeset{errors: [{:lock_version, _} | _]}, _} -> {:error, :stale}
      {:error, :item, changeset, _} -> {:error, changeset}
      {:error, :stock, reason, _} -> {:error, reason}
      {:error, :audit_events, reason, _} -> {:error, reason}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp initial_notes_events(%Item{notes: ""}, _edit_id, _user_id), do: []

  defp initial_notes_events(%Item{} = item, edit_id, user_id) do
    [
      Audit.item_event_attrs(
        action: "item.notes_changed",
        edit_id: edit_id,
        user_id: user_id,
        item: item,
        changes: %{"notes" => %{"from" => "", "to" => item.notes}},
        edit_seq: 1
      )
    ]
  end

  defp item_field_events(%Ecto.Changeset{} = changeset) do
    [
      {"item.updated", :name},
      {"item.notes_changed", :notes}
    ]
    |> Enum.flat_map(fn {action, field} ->
      case field_change(changeset, field) do
        nil -> []
        change -> [{action, %{Atom.to_string(field) => change}}]
      end
    end)
  end

  defp field_change(%Ecto.Changeset{} = changeset, field) do
    old = Map.fetch!(changeset.data, field)

    case Ecto.Changeset.fetch_change(changeset, field) do
      {:ok, new} when new != old -> %{"from" => old, "to" => new}
      _ -> nil
    end
  end

  defp stock_changed?(before_map, after_map) do
    keys = MapSet.new(Map.keys(before_map) ++ Map.keys(after_map))

    Enum.any?(keys, fn location_id ->
      Audit.quantity_at(before_map, location_id) != Audit.quantity_at(after_map, location_id)
    end)
  end

  defp normalize_desired_stock(quantities) do
    quantities
    |> Enum.reject(fn {_location_id, quantity} -> quantity == 0 end)
    |> Map.new(fn {location_id, quantity} -> {to_string(location_id), quantity} end)
  end

  defp location_names(_repo, []), do: %{}

  defp location_names(repo, location_ids) do
    location_ids = location_ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    from(l in Location, where: l.id in ^location_ids, select: {l.id, l.name})
    |> repo.all()
    |> Map.new()
  end

  defp sync_stock(repo, item_id, desired) when is_map(desired) do
    desired_ids = Map.keys(desired)

    # SQLite does not reliably surface foreign-key constraint names to Ecto, so
    # validate location ids before insert and return a normal changeset error.
    with :ok <- validate_locations_exist(repo, item_id, desired_ids) do
      delete_query =
        if desired_ids == [] do
          from il in ItemLocation, where: il.item_id == ^item_id
        else
          from il in ItemLocation,
            where: il.item_id == ^item_id and il.location_id not in ^desired_ids
        end

      repo.delete_all(delete_query)

      Enum.reduce_while(desired, {:ok, desired}, fn {location_id, quantity}, {:ok, _} = acc ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        result =
          %ItemLocation{item_id: item_id, location_id: location_id}
          |> ItemLocation.changeset(%{quantity: quantity})
          |> repo.insert(
            on_conflict: [set: [quantity: quantity, updated_at: now]],
            conflict_target: [:item_id, :location_id]
          )

        case result do
          {:ok, _} -> {:cont, acc}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp validate_locations_exist(_repo, _item_id, []), do: :ok

  defp validate_locations_exist(repo, item_id, location_ids) do
    existing =
      from(l in Location, where: l.id in ^location_ids, select: l.id)
      |> repo.all()
      |> MapSet.new()

    case Enum.find(location_ids, &(not MapSet.member?(existing, &1))) do
      nil ->
        :ok

      missing_id ->
        changeset =
          %ItemLocation{item_id: item_id, location_id: missing_id}
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:location_id, "does not exist")

        {:error, changeset}
    end
  end
end
