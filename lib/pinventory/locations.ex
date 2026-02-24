defmodule Pinventory.Locations do
  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Locations.Location

  def create(name) do
    %Location{}
    |> Location.changeset(%{name: name})
    |> Repo.insert(returning: true)
  end

  def list() do
    query =
      from location in Location,
        order_by: [asc: location.name]

    Repo.all(query)
  end
end
