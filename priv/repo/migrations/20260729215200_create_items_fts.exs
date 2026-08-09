defmodule Pinventory.Repo.Migrations.CreateItemsFts do
  use Ecto.Migration

  # FTS5 trigram index over item names.
  #
  # Non-external content table stores `item_id` (UNINDEXED) so joins use the
  # stable binary_id, not SQLite's implicit rowid (which VACUUM can renumber).
  # Triggers keep the FTS copy in sync with `items`.
  #
  # Greenfield only: this file reuses timestamp 20260729215200 from a removed
  # Postgres migration. Deploy with a new SQLite file (`mix ecto.create` and
  # `mix ecto.migrate`). Old Postgres data is not migrated in place.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE VIRTUAL TABLE items_fts USING fts5(
      name,
      item_id UNINDEXED,
      tokenize='trigram'
    )
    """)

    execute("""
    CREATE TRIGGER items_fts_ai AFTER INSERT ON items BEGIN
      INSERT INTO items_fts(name, item_id) VALUES (new.name, new.id);
    END
    """)

    execute("""
    CREATE TRIGGER items_fts_ad AFTER DELETE ON items BEGIN
      DELETE FROM items_fts WHERE item_id = old.id;
    END
    """)

    execute("""
    CREATE TRIGGER items_fts_au AFTER UPDATE OF name ON items BEGIN
      UPDATE items_fts SET name = new.name WHERE item_id = new.id;
    END
    """)

    # Backfill if items already exist when this migration runs.
    execute("""
    INSERT INTO items_fts(name, item_id)
    SELECT name, id FROM items
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS items_fts_au")
    execute("DROP TRIGGER IF EXISTS items_fts_ad")
    execute("DROP TRIGGER IF EXISTS items_fts_ai")
    execute("DROP TABLE IF EXISTS items_fts")
  end
end
