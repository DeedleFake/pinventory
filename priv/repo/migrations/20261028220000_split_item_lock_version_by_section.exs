defmodule Pinventory.Repo.Migrations.SplitItemLockVersionBySection do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :name_version, :integer, null: false, default: 1
      add :notes_version, :integer, null: false, default: 1
      add :stock_version, :integer, null: false, default: 1
      remove :lock_version, :integer, null: false, default: 1
    end
  end
end
