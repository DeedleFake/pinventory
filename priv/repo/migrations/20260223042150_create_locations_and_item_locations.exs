defmodule Pinventory.Repo.Migrations.CreateLocationsAndItemLocations do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:locations, [:name])

    create table(:item_locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      add :location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      # SQLite only supports CHECK constraints on column definitions via Ecto.
      add :quantity, :integer,
        null: false,
        check: %{name: "quantity_must_be_positive", expr: "quantity > 0"}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:item_locations, [:item_id, :location_id])
    create index(:item_locations, [:item_id])
    create index(:item_locations, [:location_id])
  end
end
