defmodule Pinventory.Repo.Migrations.RemoveInvitePlainToken do
  use Ecto.Migration

  def change do
    # Early invite tables stored a plain `token` column. The app now keeps only
    # `token_hash`. Fresh installs never create `token`; older DBs still have it.
    alter table(:invites) do
      remove_if_exists :token, :string
    end
  end
end
