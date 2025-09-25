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

    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
    create index(:items, [~s("name" gin_trgm_ops)], using: "GIN")
  end
end
