defmodule Pinventory.Repo.Migrations.CreateFloorPlans do
  use Ecto.Migration

  def change do
    create table(:floor_plans, primary_key: false) do
      # Singleton per install: unique singleton_key enforces at most one plan.
      add :id, :binary_id, primary_key: true
      add :singleton_key, :string, null: false, default: "default"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:floor_plans, [:singleton_key])

    create table(:floors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0
      # Wall segments as JSON: [%{"x1"=>0.1,"y1"=>0.2,"x2"=>0.8,"y2"=>0.2}, ...]
      # Coordinates are normalized to the unit square (0.0–1.0).
      add :walls, :json, null: false, default: "[]"

      add :floor_plan_id, references(:floor_plans, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:floors, [:floor_plan_id])
    create index(:floors, [:floor_plan_id, :position])

    create table(:location_placements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :floor_id, references(:floors, type: :binary_id, on_delete: :delete_all), null: false

      # Normalized pin position on the floor canvas (0.0–1.0).
      add :x, :float, null: false
      add :y, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:location_placements, [:location_id])
    create index(:location_placements, [:floor_id])
  end
end
