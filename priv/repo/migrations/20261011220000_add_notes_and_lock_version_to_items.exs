defmodule Pinventory.Repo.Migrations.AddNotesAndLockVersionToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :notes, :text, null: false, default: ""
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
