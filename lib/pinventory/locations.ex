defmodule Pinventory.Locations do
  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Locations.Location

  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  def create(%Ecto.Changeset{} = changeset) do
    changeset
    |> Repo.insert(returning: true)
  end

  def create(attrs) do
    %Location{}
    |> change_location(attrs)
    |> create()
  end

  def list() do
    query =
      from location in Location,
        order_by: [asc: location.name]

    Repo.all(query)
  end
end
