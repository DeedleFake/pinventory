defmodule Pinventory.Repo.Migrations.AddEmailToInvites do
  @moduledoc """
  Adds required bound `email` on invites.

  **Ops note:** this migration deletes **all** rows in `invites` (pending,
  used, and revoked). Blank tickets cannot be backfilled with a real email,
  and used/revoked history is not retained.

  Before deploy, optionally inspect outstanding tickets:

      SELECT count(*) FROM invites;
      SELECT id, expires_at, used_at, revoked_at FROM invites WHERE used_at IS NULL AND revoked_at IS NULL;

  Pending invite URLs shared before migrate will stop working. Mint new
  email-bound invites after migrate.
  """
  use Ecto.Migration

  def up do
    # Destructive by design: legacy blank tickets have no email to bind.
    # Also clears used/revoked history (no multi-step nullable backfill).
    execute "DELETE FROM invites"

    alter table(:invites) do
      # Match users.email: SQLite has no citext; COLLATE NOCASE for case-insensitive compare.
      add :email, :string, null: false, collate: :nocase
    end
  end

  def down do
    alter table(:invites) do
      remove :email
    end
  end
end
