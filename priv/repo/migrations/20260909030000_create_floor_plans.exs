defmodule Pinventory.Repo.Migrations.CreateFloorPlans do
  use Ecto.Migration

  def change do
    create table(:floors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:floors, [:position])

    create table(:walls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :floor_id, references(:floors, type: :binary_id, on_delete: :delete_all), null: false

      add :x1, :float, null: false
      add :y1, :float, null: false
      add :x2, :float, null: false
      add :y2, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:walls, [:floor_id])

    create table(:location_placements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :floor_id, references(:floors, type: :binary_id, on_delete: :delete_all), null: false

      # Closed polygon on the floor canvas (unit square). ≥3 points of %{"x","y"}.
      add :points, :json, null: false, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:location_placements, [:location_id])
    create index(:location_placements, [:floor_id])
  end
end
