defmodule Pinventory.Items do
  @moduledoc """
  The Items context.

  Name search uses SQLite FTS5 trigram matching for longer queries and `LIKE`
  for short ones. Case folding for both paths follows SQLite defaults: ASCII
  A–Z only. Non-ASCII letters are case-sensitive unless you add a normalized
  search column later.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.Repo

  alias Pinventory.Items.DraftStock
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations.Location

  # FTS5 trigram needs at least 3 characters for MATCH; shorter queries use LIKE.
  @fts_min_length 3

  @doc """
  Suggests items by partial name.

  Uses FTS5 trigram MATCH for queries of three or more characters, with a
  case-insensitive (ASCII) LIKE fallback for shorter queries. Ranking prefers
  prefix matches, then substring matches, then FTS rank when available.

  Empty or whitespace-only input returns `[]`.
  """
  def suggest_items(partial_name, opts \\ []) do
    opts = Keyword.validate!(opts, limit: 10)
    query = partial_name |> to_string() |> String.trim()

    cond do
      query == "" ->
        []

      String.length(query) < @fts_min_length ->
        suggest_items_like(query, opts[:limit])

      true ->
        suggest_items_fts(query, opts[:limit])
    end
  end

  @doc """
  Lists items ordered by name.

  Each item includes virtual `total_quantity` (sum of stock) and
  `location_count` (number of locations with stock).

  Options:

    * `:filter` - ASCII case-insensitive name substring match (trimmed; blank
      means no filter)
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

  defp suggest_items_like(query, limit) do
    escaped = escape_like(query)
    pattern = "%#{escaped}%"
    prefix = "#{escaped}%"

    from(item in Item,
      where: fragment("? LIKE ? ESCAPE '\\'", item.name, ^pattern),
      order_by: [
        desc:
          fragment(
            """
            CASE
              WHEN ? LIKE ? ESCAPE '\\' THEN 3
              WHEN ? LIKE ? ESCAPE '\\' THEN 2
              ELSE 1
            END
            """,
            item.name,
            ^prefix,
            item.name,
            ^pattern
          ),
        asc: item.name
      ],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp suggest_items_fts(query, limit) do
    fts_query = escape_fts(query)
    escaped = escape_like(query)
    pattern = "%#{escaped}%"
    prefix = "#{escaped}%"

    # One MATCH: join FTS hits (with bm25) to items by stable item_id.
    from(item in Item,
      join:
        fts in fragment(
          """
          (
            SELECT item_id AS item_id, bm25(items_fts) AS rank
            FROM items_fts
            WHERE items_fts MATCH ?
          )
          """,
          ^fts_query
        ),
      on: item.id == fragment("?.item_id", fts),
      order_by: [
        desc:
          fragment(
            """
            CASE
              WHEN ? LIKE ? ESCAPE '\\' THEN 3
              WHEN ? LIKE ? ESCAPE '\\' THEN 2
              ELSE 1
            END
            """,
            item.name,
            ^prefix,
            item.name,
            ^pattern
          ),
        # Lower bm25 is a better match.
        asc: fragment("?.rank", fts),
        asc: item.name
      ],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp maybe_filter_name(query, filter) when is_binary(filter) do
    case String.trim(filter) do
      "" ->
        query

      trimmed ->
        pattern = "%#{escape_like(trimmed)}%"

        where(
          query,
          [item: item],
          fragment("? LIKE ? ESCAPE '\\'", item.name, ^pattern)
        )
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

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  # Quote the string as an FTS5 phrase so operators and punctuation are literal.
  defp escape_fts(value) do
    "\"" <> String.replace(value, "\"", "\"\"") <> "\""
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
  `quantities` is a map of `location_id => quantity`.
  """
  def create_item(attrs, quantities \\ %{}) do
    Multi.new()
    |> Multi.insert(:item, change_item(%Item{}, attrs))
    |> Multi.run(:stock, fn repo, %{item: item} ->
      sync_stock(repo, item.id, quantities)
    end)
    |> Multi.run(:result, fn repo, %{item: item} ->
      {:ok, repo.preload(item, :item_locations)}
    end)
    |> Repo.transaction()
    |> unwrap_item_transaction()
  end

  @doc """
  Updates an item name and replaces stock so only positive quantities remain.
  `quantities` is a map of `location_id => quantity`.
  """
  def update_item(%Item{} = item, attrs, quantities \\ %{}) do
    Multi.new()
    |> Multi.update(:item, change_item(item, attrs))
    |> Multi.run(:stock, fn repo, %{item: item} ->
      sync_stock(repo, item.id, quantities)
    end)
    |> Multi.run(:result, fn repo, %{item: item} ->
      {:ok, repo.preload(item, :item_locations, force: true)}
    end)
    |> Repo.transaction()
    |> unwrap_item_transaction()
  end

  def delete_item(%Item{} = item) do
    Repo.delete(item)
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

  defp unwrap_item_transaction(result) do
    case result do
      {:ok, %{result: item}} -> {:ok, item}
      {:error, :item, changeset, _} -> {:error, changeset}
      {:error, :stock, reason, _} -> {:error, reason}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp sync_stock(repo, item_id, quantities) do
    desired =
      quantities
      |> Enum.map(fn {location_id, quantity} ->
        {to_string(location_id), DraftStock.parse_non_neg_int(quantity)}
      end)
      |> Enum.filter(fn {_location_id, quantity} -> quantity > 0 end)
      |> Map.new()

    desired_ids = Map.keys(desired)

    # SQLite does not reliably surface foreign-key constraint names to Ecto, so
    # validate location ids before insert and return a normal changeset error.
    with :ok <- validate_locations_exist(repo, desired_ids) do
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

  defp validate_locations_exist(_repo, []), do: :ok

  defp validate_locations_exist(repo, location_ids) do
    existing =
      from(l in Location, where: l.id in ^location_ids, select: l.id)
      |> repo.all()
      |> MapSet.new()

    case Enum.find(location_ids, &(not MapSet.member?(existing, &1))) do
      nil ->
        :ok

      missing_id ->
        changeset =
          %ItemLocation{location_id: missing_id}
          |> ItemLocation.changeset(%{quantity: 1})
          |> Ecto.Changeset.add_error(:location_id, "does not exist")

        {:error, changeset}
    end
  end
end
