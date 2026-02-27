defmodule Pinventory.Locations do
  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Locations.Location

  def create_changeset(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
  end

  def create(changeset) do
    changeset
    |> Repo.insert(returning: true)
  end

  def list() do
    query =
      from location in Location,
        order_by: [asc: location.name]

    Repo.all(query)
  end
end
