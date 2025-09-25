defmodule Pinventory.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:items, [:name])
  end
end
