defmodule Pinventory.Items do
  @moduledoc """
  The Items context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.Repo

  alias Pinventory.Items.DraftStock
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation

  # PostgreSQL ILIKE escape character (bound as a query parameter).
  @like_escape "\\"

  def suggest_items(partial_name, opts \\ []) do
    opts = Keyword.validate!(opts, limit: 10)
    pattern = escape_like(partial_name)
    prefix = "#{pattern}%"
    contains = "%#{pattern}%"

    q =
      from item in Item,
        where:
          fragment("? ILIKE ? ESCAPE ?", item.name, ^contains, @like_escape) or
            fragment("? % ?", item.name, ^partial_name),
        order_by: [
          desc:
            fragment(
              """
              CASE
                WHEN ? ILIKE ? ESCAPE ? THEN 3.0
                WHEN ? ILIKE ? ESCAPE ? THEN 2.0
                ELSE similarity(?, ?)
              END
              """,
              item.name,
              ^prefix,
              @like_escape,
              item.name,
              ^contains,
              @like_escape,
              item.name,
              ^partial_name
            ),
          asc: item.name
        ],
        limit: ^opts[:limit]

    Repo.all(q)
  end

  @doc """
  Lists items ordered by name.

  Each item includes virtual `total_quantity` (sum of stock) and
  `location_count` (number of locations with stock).

  Options:

    * `:filter` - case-insensitive name substring match
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

  defp maybe_filter_name(query, filter) when is_binary(filter) and filter != "" do
    pattern = "%#{escape_like(filter)}%"

    where(
      query,
      [item: item],
      fragment("? ILIKE ? ESCAPE ?", item.name, ^pattern, @like_escape)
    )
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
