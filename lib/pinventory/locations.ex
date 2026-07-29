defmodule Pinventory.Locations do
  @moduledoc """
  Context for storage locations and location-level queries.

  Public functions use short names (`create/1`, `update/1`, `list/0`) because
  the module already scopes them as location operations. Compare with
  `Pinventory.Items`, which uses `create_item/2`-style names when the context
  owns multiple related schemas.
  """

  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Locations.Location

  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  def create(%Ecto.Changeset{} = changeset) do
    Repo.insert(changeset)
  end

  def create(attrs) do
    %Location{}
    |> change_location(attrs)
    |> create()
  end

  def update(%Ecto.Changeset{} = changeset) do
    Repo.update(changeset)
  end

  def update(%Location{} = location, attrs) do
    location
    |> change_location(attrs)
    |> update()
  end

  def list do
    query =
      from location in Location,
        order_by: [asc: location.name]

    Repo.all(query)
  end

  @doc """
  Returns locations ordered by name, each with `item_count` set to the number
  of distinct item types stored at that location.
  """
  def list_with_item_counts do
    query =
      from location in Location,
        left_join: item_location in assoc(location, :item_locations),
        group_by: location.id,
        order_by: [asc: location.name],
        select_merge: %{item_count: count(item_location.id)}

    Repo.all(query)
  end
end
