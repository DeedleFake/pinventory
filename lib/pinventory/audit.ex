defmodule Pinventory.Audit do
  @moduledoc """
  Append-only audit log. Mutations write events inside the same `Ecto.Multi`
  transaction as the domain change. Events are never updated or deleted by app
  code.
  """

  import Ecto.Query, warn: false

  alias Pinventory.Accounts.Scope
  alias Pinventory.Accounts.User
  alias Pinventory.Audit.Event
  alias Pinventory.Repo

  @doc """
  Returns a new UUID for grouping events from one user action.
  """
  def new_edit_id, do: Ecto.UUID.generate()

  @doc """
  Actor user id from an authenticated scope. Raises if the scope has no user.
  """
  def actor_id(%Scope{user: %User{id: id}}) when is_binary(id), do: id

  def actor_id(_scope) do
    raise ArgumentError, "authenticated scope with a user is required for audited mutations"
  end

  @doc """
  Inserts event attribute maps with the given repo (for use inside Multi.run).

  Each map should already include `edit_id`, `action`, `entity_type`,
  `entity_id`, and any optional fields. `edit_seq` is set from list order
  when missing.
  """
  def insert_events(repo, events) when is_list(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, index}, {:ok, acc} ->
      attrs =
        attrs
        |> stringify_keys()
        |> Map.put_new("edit_seq", index)

      case %Event{} |> Event.changeset(attrs) |> repo.insert() do
        {:ok, event} -> {:cont, {:ok, [event | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists recent user actions grouped by `edit_id` (newest edit first).

  Each group is a map:

      %{edit_id: ..., inserted_at: ..., user: user | nil, events: [Event, ...]}

  Options:

    * `:limit` - max edit groups (default 50)
  """
  def list_recent_edits(opts \\ []) do
    opts = Keyword.validate!(opts, limit: 50)
    load_edit_groups(base_edit_query(), opts[:limit])
  end

  @doc """
  Lists edits that touch an item, grouped by `edit_id` (newest edit first).

  Only events with `item_id` equal to the given id are included in each group
  (so a multi-entity edit would show only this item's lines). Preloads `:user`.

  Options:

    * `:limit` - max edit groups (default 50)
  """
  def list_edits_for_item(item_id, opts \\ []) when is_binary(item_id) do
    opts = Keyword.validate!(opts, limit: 50)

    edit_query =
      from(e in Event,
        where: e.item_id == ^item_id,
        group_by: e.edit_id,
        order_by: [desc: max(e.inserted_at)],
        select: %{edit_id: e.edit_id, inserted_at: max(e.inserted_at)}
      )

    load_edit_groups(edit_query, opts[:limit], item_id: item_id)
  end

  @doc """
  Lists edits that touch a location, grouped by `edit_id` (newest edit first).

  Only events with `location_id` equal to the given id are included in each
  group. Preloads `:user`.

  Options:

    * `:limit` - max edit groups (default 50)
  """
  def list_edits_for_location(location_id, opts \\ []) when is_binary(location_id) do
    opts = Keyword.validate!(opts, limit: 50)

    edit_query =
      from(e in Event,
        where: e.location_id == ^location_id,
        group_by: e.edit_id,
        order_by: [desc: max(e.inserted_at)],
        select: %{edit_id: e.edit_id, inserted_at: max(e.inserted_at)}
      )

    load_edit_groups(edit_query, opts[:limit], location_id: location_id)
  end

  @doc """
  Lists events for an item (item and stock events), newest first.
  With `:limit`, returns the N most recent events. Preloads `:user`.

  Prefer `list_edits_for_item/2` for the item Activity UI (grouped by edit).

  Options:

    * `:limit` - max rows (default 100)
  """
  def list_for_item(item_id, opts \\ []) when is_binary(item_id) do
    opts = Keyword.validate!(opts, limit: 100)

    from(e in Event,
      where: e.item_id == ^item_id,
      order_by: [desc: e.inserted_at, desc: e.edit_seq, desc: e.id],
      limit: ^opts[:limit],
      preload: [:user]
    )
    |> Repo.all()
  end

  defp base_edit_query do
    from(e in Event,
      group_by: e.edit_id,
      order_by: [desc: max(e.inserted_at)],
      select: %{edit_id: e.edit_id, inserted_at: max(e.inserted_at)}
    )
  end

  defp load_edit_groups(edit_query, limit, opts \\ []) do
    item_id = Keyword.get(opts, :item_id)
    location_id = Keyword.get(opts, :location_id)

    edit_rows =
      edit_query
      |> limit(^limit)
      |> Repo.all()

    edit_ids = Enum.map(edit_rows, & &1.edit_id)

    events_by_edit =
      if edit_ids == [] do
        %{}
      else
        events_query =
          from(e in Event,
            where: e.edit_id in ^edit_ids,
            order_by: [asc: e.edit_seq, asc: e.inserted_at, asc: e.id],
            preload: [:user]
          )

        events_query =
          cond do
            item_id ->
              where(events_query, [e], e.item_id == ^item_id)

            location_id ->
              where(events_query, [e], e.location_id == ^location_id)

            true ->
              events_query
          end

        events_query
        |> Repo.all()
        |> Enum.group_by(& &1.edit_id)
      end

    Enum.map(edit_rows, fn %{edit_id: edit_id, inserted_at: inserted_at} ->
      events = Map.get(events_by_edit, edit_id, [])
      user = events |> List.first() |> then(fn e -> e && e.user end)

      %{
        edit_id: edit_id,
        inserted_at: inserted_at,
        user: user,
        events: events
      }
    end)
  end

  @doc """
  Returns a map of `item_id => Event` for the latest `stock.changed` event per
  item. Missing item ids are omitted. Preloads `:user`.
  """
  def latest_stock_changes_for_items([]), do: %{}

  def latest_stock_changes_for_items(item_ids) when is_list(item_ids) do
    item_ids = Enum.uniq(item_ids)

    # Window rank so same-second inserts still resolve to the newest row.
    ranked =
      from(e in Event,
        where: e.action == "stock.changed" and e.item_id in ^item_ids,
        windows: [
          w: [
            partition_by: [e.item_id],
            order_by: [desc: e.inserted_at, desc: fragment("rowid")]
          ]
        ],
        select: %{id: e.id, rn: over(row_number(), :w)}
      )

    from(e in Event,
      join: r in subquery(ranked),
      on: e.id == r.id and r.rn == 1,
      preload: [:user]
    )
    |> Repo.all()
    |> Map.new(&{&1.item_id, &1})
  end

  @doc """
  Builds attribute maps for stock quantity diffs.

  `before_map` and `after_map` are `location_id => quantity` (missing or nil = 0).
  `location_names` is `location_id => name` for metadata.
  """
  def stock_change_attrs(opts) do
    edit_id = Keyword.fetch!(opts, :edit_id)
    user_id = Keyword.get(opts, :user_id)
    item_id = Keyword.fetch!(opts, :item_id)
    item_name = Keyword.get(opts, :item_name)
    before_map = Keyword.get(opts, :before, %{})
    after_map = Keyword.get(opts, :after, %{})
    location_names = Keyword.get(opts, :location_names, %{})
    start_seq = Keyword.get(opts, :start_seq, 0)

    location_ids =
      MapSet.new(Map.keys(before_map) ++ Map.keys(after_map))
      |> MapSet.to_list()
      |> Enum.sort()

    location_ids
    |> Enum.with_index(start_seq)
    |> Enum.flat_map(fn {location_id, seq} ->
      from_qty = quantity_at(before_map, location_id)
      to_qty = quantity_at(after_map, location_id)

      if from_qty == to_qty do
        []
      else
        [
          %{
            edit_id: edit_id,
            edit_seq: seq,
            user_id: user_id,
            action: "stock.changed",
            entity_type: "item_location",
            # Synthetic id: stock rows may be deleted; item_id/location_id carry the link.
            entity_id: Ecto.UUID.generate(),
            item_id: item_id,
            location_id: location_id,
            changes: %{"quantity" => %{"from" => from_qty, "to" => to_qty}},
            metadata: %{
              "item_name" => item_name,
              "location_name" => Map.get(location_names, location_id)
            }
          }
        ]
      end
    end)
  end

  @doc """
  Builds attrs for an item lifecycle event (`item.created` / `updated` / `deleted`).
  """
  def item_event_attrs(opts) do
    action = Keyword.fetch!(opts, :action)
    edit_id = Keyword.fetch!(opts, :edit_id)
    user_id = Keyword.get(opts, :user_id)
    item = Keyword.fetch!(opts, :item)
    changes = Keyword.get(opts, :changes, %{})
    edit_seq = Keyword.get(opts, :edit_seq, 0)

    %{
      edit_id: edit_id,
      edit_seq: edit_seq,
      user_id: user_id,
      action: action,
      entity_type: "item",
      entity_id: item.id,
      item_id: item.id,
      location_id: nil,
      changes: changes,
      metadata: %{"item_name" => item.name}
    }
  end

  @doc """
  Builds attrs for a location lifecycle event.
  """
  def location_event_attrs(opts) do
    action = Keyword.fetch!(opts, :action)
    edit_id = Keyword.fetch!(opts, :edit_id)
    user_id = Keyword.get(opts, :user_id)
    location = Keyword.fetch!(opts, :location)
    changes = Keyword.get(opts, :changes, %{})
    edit_seq = Keyword.get(opts, :edit_seq, 0)

    %{
      edit_id: edit_id,
      edit_seq: edit_seq,
      user_id: user_id,
      action: action,
      entity_type: "location",
      entity_id: location.id,
      item_id: nil,
      location_id: location.id,
      changes: changes,
      metadata: %{"location_name" => location.name}
    }
  end

  @doc false
  def quantity_at(map, location_id) do
    Map.get(map, location_id, 0) || 0
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
