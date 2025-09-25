defmodule Pinventory.Items do
  @moduledoc """
  The Items context.
  """

  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Items.Item

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

  def create_item(attrs) do
    %Item{}
    |> Item.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_item_quantity(%Item{} = item, quantity) do
    item
    |> Item.update_quantity_changeset(quantity: quantity)
    |> Repo.update()
  end

  def delete_item(%Item{} = item) do
    Repo.delete(item)
  end
end
