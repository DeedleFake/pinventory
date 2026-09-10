defmodule Pinventory.Repo.Migrations.CreateImpassableAreas do
  use Ecto.Migration

  def change do
    create table(:impassable_areas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :floor_id, references(:floors, type: :binary_id, on_delete: :delete_all), null: false

      # Closed polygon on the floor canvas. ≥3 points of %{"x","y"}.
      add :points, :json, null: false, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create index(:impassable_areas, [:floor_id])
  end
end
