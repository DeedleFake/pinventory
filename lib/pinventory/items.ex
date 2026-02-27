defmodule Pinventory.Items do
  @moduledoc """
  The Items context.
  """

  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations.Location

  def suggest_items(partial_name, opts \\ []) do
    opts = Keyword.validate!(opts, limit: 10)

    q =
      from item in Item,
        where:
          ilike(item.name, ^"#{partial_name}%") or fragment("? % ?", item.name, ^partial_name),
        order_by: [
          desc:
            fragment(
              "CASE WHEN ? ILIKE ? THEN 2.0 ELSE similarity(?, ?) END",
              item.name,
              ^"#{partial_name}%",
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

  def get_item!(id), do: Repo.get!(Item, id)

  def change_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def update_quantity(item, location, quantity) do
    item_id = get_id(item)
    location_id = get_id(location)

    %ItemLocation{}
    |> ItemLocation.changeset(item_id: item_id, location_id: location_id, quantity: quantity)
    |> Repo.insert(
      on_conflict: [
        set: [
          quantity: quantity
        ]
      ],
      conflict_target: [:item_id, :location_id],
      returning: true
    )
  end

  def delete_item(%Item{} = item) do
    Repo.delete(item)
  end

  defp get_id(%Item{id: id}), do: id
  defp get_id(%Location{id: id}), do: id
  defp get_id(id) when is_binary(id), do: id
end
