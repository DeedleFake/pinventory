defmodule Pinventory.Repo.Migrations.RemoveLockVersionFromItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      remove :lock_version, :integer, null: false, default: 1
    end
  end
end
