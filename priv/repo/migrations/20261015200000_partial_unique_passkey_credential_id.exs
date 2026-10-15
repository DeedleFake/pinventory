defmodule Pinventory.Repo.Migrations.PartialUniquePasskeyCredentialId do
  use Ecto.Migration

  # Only active passkeys need unique credential ids. Revoked rows stay as
  # history, and the same authenticator can be registered again.
  def change do
    drop unique_index(:users_passkeys, [:credential_id])
    create unique_index(:users_passkeys, [:credential_id], where: "revoked_at IS NULL")
  end
end
