defmodule Pinventory.Items do
  @moduledoc """
  The Items context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.Repo

  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation

  def suggest_items(partial_name, opts \\ []) do
    opts = Keyword.validate!(opts, limit: 10)

    q =
      from item in Item,
        where:
          ilike(item.name, ^"#{partial_name}%") or
            ilike(item.name, ^"%#{partial_name}%") or
            fragment("? % ?", item.name, ^partial_name),
        order_by: [
          desc:
            fragment(
              """
              CASE
                WHEN ? ILIKE ? THEN 3.0
                WHEN ? ILIKE ? THEN 2.0
                ELSE similarity(?, ?)
              END
              """,
              item.name,
              ^"#{partial_name}%",
              item.name,
              ^"%#{partial_name}%",
              item.name,
              ^partial_name
            ),
          asc: item.name
        ],
        limit: ^opts[:limit]

    Repo.all(q)
  end

  def list_items(opts \\ []) do
    opts = Keyword.validate!(opts, [:filter, limit: 100])

    filter =
      if opts[:filter] do
        dynamic([item], ilike(item.name, ^"%#{opts[:filter]}%"))
      else
        true
      end

    q =
      from item in Item,
        where: ^filter,
        limit: ^opts[:limit],
        order_by: [asc: item.name]

    Repo.all(q)
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
        {to_string(location_id), normalize_quantity(quantity)}
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

    Enum.each(desired, fn {location_id, quantity} ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %ItemLocation{}
      |> ItemLocation.changeset(%{
        item_id: item_id,
        location_id: location_id,
        quantity: quantity
      })
      |> repo.insert!(
        on_conflict: [set: [quantity: quantity, updated_at: now]],
        conflict_target: [:item_id, :location_id]
      )
    end)

    {:ok, desired}
  end

  defp normalize_quantity(quantity) when is_integer(quantity), do: max(quantity, 0)

  defp normalize_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(String.trim(quantity)) do
      {int, _} -> max(int, 0)
      :error -> 0
    end
  end

  defp normalize_quantity(_), do: 0
end
