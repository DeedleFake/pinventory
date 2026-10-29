defmodule Pinventory.Repo.Migrations.AddLockVersionToLocations do
  use Ecto.Migration

  def change do
    alter table(:locations) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
