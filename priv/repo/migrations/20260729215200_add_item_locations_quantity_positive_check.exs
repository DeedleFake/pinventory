defmodule Pinventory.Repo.Migrations.AddItemLocationsQuantityPositiveCheck do
  use Ecto.Migration

  def change do
    create constraint(:item_locations, :quantity_must_be_positive, check: "quantity > 0")
  end
end
