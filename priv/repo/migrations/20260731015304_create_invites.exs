defmodule Pinventory.Repo.Migrations.CreateInvites do
  use Ecto.Migration

  def change do
    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :used_at, :utc_datetime

      add :created_by_id, references(:user, type: :binary_id, on_delete: :nilify_all)
      add :used_by_id, references(:user, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invites, [:token_hash])
    create index(:invites, [:created_by_id])
    create index(:invites, [:expires_at])
  end
end
