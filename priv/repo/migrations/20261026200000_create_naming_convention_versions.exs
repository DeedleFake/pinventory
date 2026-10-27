defmodule Pinventory.Repo.Migrations.CreateNamingConventionVersions do
  use Ecto.Migration

  @initial_text """
  # Item names

  - Include the unit in the name, so the count says what you have. Write **Boxes of Tissues**, not **Tissues**.
  - Leave the location out. Each item already has counts per location. Put details like "bottom shelf" in the item's notes.
  - Leave quantities out. Write **Boxes of Tissues**, not **3 Boxes of Tissues**, because the count changes.
  - Leave the brand out unless it matters. When it does, keep the generic word too, as in **Bounty Paper Towels**, so a search for "paper towels" finds it.
  - Leave out temporary states like "opened", "expired", or "for the party". Put those in the item's notes.\
  """

  def up do
    create table(:naming_convention_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :text, :text, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :via_token_name, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:naming_convention_versions, [:number])

    flush()

    repo().insert_all("naming_convention_versions", [
      %{
        id: Ecto.UUID.generate(),
        number: 0,
        text: @initial_text,
        inserted_at: DateTime.utc_now(:second)
      }
    ])
  end

  def down do
    drop table(:naming_convention_versions)
  end
end
