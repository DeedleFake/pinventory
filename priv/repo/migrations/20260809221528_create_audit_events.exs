defmodule Pinventory.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :edit_id, :binary_id, null: false
      add :edit_seq, :integer, null: false, default: 0
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false
      add :item_id, :binary_id
      add :location_id, :binary_id
      add :changes, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:edit_id])
    create index(:audit_events, [:item_id, :inserted_at])
    create index(:audit_events, [:location_id, :inserted_at])
    create index(:audit_events, [:user_id, :inserted_at])
    create index(:audit_events, [:entity_type, :entity_id])
    create index(:audit_events, [:action, :item_id, :inserted_at])
  end
end
