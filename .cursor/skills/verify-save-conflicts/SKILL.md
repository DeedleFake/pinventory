---
name: verify-save-conflicts
description: Model-check what happens when people and the MCP agent tools save, reload, and delete the same Pinventory record at once, on the item, location, and naming convention edit pages, using TLA+ models whose guard settings are read from the code. Use when a change touches Items.update_item, the Item section comparison, change_stock, move_stock, delete_item, Locations.update, Locations.delete, NamingConvention.save, DraftStock, an edit page's save, reconcile, keep_my_edits, load_latest, live-notice, or stale handling, the MCP rename or convention tools, item_locations constraints, or the repo's transaction mode, or when running /verify-save-conflicts.
---

# Verify save conflicts

Two TLA+ models check that racing saves never lose a change, never refuse a save for no reason, never throw away someone's unsaved edits, and never crash a page. TLC, the TLA+ model checker, tries every order of the steps below within the bounds. Tests only cover the orders someone wrote down.

- `model/StockEdits.tla` checks an item's stock counts: the edit page, `change_stock`, `move_stock`, and item and location deletes. This is the `stock` run.
- `model/SectionSaves.tla` checks the save, reconcile, and warning logic that every edit page shares. It runs three times, once per page:
  - `item`: `EditItemLive` with its three sections (name, notes, stock), MCP `rename_item`, and `change_stock` and `move_stock` as one-step stock writes.
  - `location`: `LocationLive` with its name, and MCP `rename_location`.
  - `convention`: `NamingConventionLive` with its text, and MCP `edit_naming_convention`.

The floor plan is not covered. It has no save step to conflict: each change there is written as it happens and shown live, which is a different design.

## Run it

From the repo root:

```bash
./.cursor/skills/verify-save-conflicts/scripts/check-save-conflicts
```

It needs Java 11 or newer, `perl`, and `curl`. The first run downloads `tla2tools.jar` 1.7.4 to `~/.cache/pinventory/` and checks its sha256. Use a full release here. The v1.8.0 tag is a pre-release that upstream's nightly build re-uploads, so its hash changes. Set `TLA2TOOLS_JAR` to use another copy. A run takes about 30 seconds on 8 cores, most of it the `item` run. `TLC_WORKERS=2` limits the cores it uses.

To check one property of one run alone, ignoring the known findings list:

```bash
./.cursor/skills/verify-save-conflicts/scripts/check-save-conflicts --only location:WarningsMatchSaved
```

Output and counterexamples go to `tmp/verify-save-conflicts/`, one `.out` file per run. CI runs the same command in the `Save conflicts model` job.

## What it checks

`SectionSaves.tla`, in the `item`, `location`, and `convention` runs:

| Property | Plain meaning | Harm when broken |
|---|---|---|
| `NoLostUpdate` | No save overwrites a saved value its writer never saw. | Someone's rename, notes, or convention edit silently disappears. |
| `NoFalseConflict` | A save is refused only when a section it edits changed, or the record is gone. | A quantity save is refused after someone else's rename, or a change that was undone still blocks the save. |
| `UnsavedEditsSurvive` | Someone else's save never replaces edits the user has not saved. | The user's typing vanishes without a warning. |
| `WarningsMatchSaved` | After a notice or a stale save, a section warns exactly when it has unsaved edits and someone else's save changed it. | A warning about a change that no longer exists, with Save disabled, or a conflict with no warning. |
| `PagesNeverCrash` | No race crashes a page, including a stale save on a deleted record and two people deleting the same record. | The page dies and the user loses their place. |

`StockEdits.tla`, in the `stock` run:

| Property | Plain meaning | Harm when broken |
|---|---|---|
| `NoLostUpdate` | No save overwrites a change its writer never saw. | Someone's stock or name change silently disappears. |
| `StockNeverNegative` | No stored count is below 0. | Impossible counts in lists and totals. |
| `AgentNeverStoresOverMax` | `change_stock` and `move_stock` never store a count above 1,000,000. | The agent writes counts the UI refuses to accept. |
| `EditPageNeverStoresOverMax` | An edit-page save never stores a count above 1,000,000. | Same, from the browser. |
| `MoveKeepsTotal` | `move_stock` never changes the item's total. | A move creates or destroys stock. |
| `LocationDeleteKeepsStock` | Deleting a location never throws stock away. | Stock vanishes with the location. |
| `StaleSaveNeverCrashes` | A save that loses a race never crashes the edit page. | The page dies and the user loses their unsaved edits. |
| `UnsavedStockSurvives` | Someone else's save, seen live or after a stale save, never replaces stock the user is still editing. | The user's unsaved counts vanish without a warning. |

## Read the result

- `PASS <run>: ...` lists every property that held in every reachable state of that run.
- `FAIL <run>:<property>` means a new break. Open the `.out` file it names. Its `State N:` lines are the steps, and the variables under each step show what changed.
- `KNOWN FINDING still present` is expected for the findings below. The check exits 0 when only those fail.
- `FIXED? <run>:<property> now passes` means the model no longer finds that break. Confirm the fix in the code with a test, since a code fact can flip without the bug being gone. Then remove it from `KNOWN_FINDINGS` in the script and from Findings below. The check exits 1 until you do.
- `TOOL ERROR` means TLC did not finish. Read the `.out` file. It is usually a model syntax or type error.

Read every result with the `/statechart` skill. It turns a violation into its shortest path in plain words and shows which violations a change fixes. On a pass it draws how the system moves between states.

## Real bug or modeling error

The script prints `code facts` first, per run. Each is a model constant read from the code by one regex in `scripts/check-save-conflicts`. A regex that stops matching turns its fact FALSE, or turns a mode to `"none"`.

`SectionSaves.tla`:

| Constant | item | location | convention |
|---|---|---|---|
| `CheckMode` | `"value"` when `check_sections/3` compares `Item.changed_sections(base, current)` | `"value"` when `update/2` runs `check_name/2` first and it matches `%Location{name: ^name}` | `"revision"` when `save/3` rolls back on `newest.number != base` |
| `CheckOnlyEdited` | `edited_sections/2` lists stock only when it changed and a field only when the changeset changes it, and `check_sections/3` filters with `&(&1 in sections)` | TRUE, one section | TRUE, one section |
| `WritesOnlyEdited` | `Multi.update(:item, changeset)` with `changeset = change_item(item, attrs)`, and the stock fact `SyncOnlyChangedStock` | TRUE, one section | TRUE, one section |
| `ReconcileMode` | `"value"` when `reconcile/2` pipes into `Item.changed_sections(latest)` | `"value"` when `reconcile/2` tests `latest.name == location.name` | `"revision"` when `reconcile/2` tests `newest.number == socket.assigns.base.number` |
| `ReconcileKeepsDirty` | the stock fact `ReconcileKeepsEditedStock`, and `section_dirty?/2` for `:name` and `:notes` reading `name_dirty?` and `notes_dirty?` | `reconcile/2` reloading only when `not socket.assigns.name_dirty?`, and otherwise assigning `:latest` | `reconcile/2` assigning `:stale` when `socket.assigns.dirty?` |
| `ReconcileClearsWarning` | `reconcile/2` assigning `:conflicts` fresh each time | the `latest.name == location.name` branch assigning `:latest` to nil | FALSE: the unchanged branch returns the socket as it is |
| `StaleNilSafe` | the `{:error, :stale}` branch calling `reconcile(Items.get_item(...))`, with a `reconcile(socket, nil)` clause | the same with `Locations.get` | TRUE, never deleted |
| `DeleteToleratesMissing` | `Multi.delete(:item, item, stale_error_field: :id)` in `delete_item/2` | `Multi.delete(:location, location, stale_error_field: :id)` in `delete/2` | TRUE, never deleted |

`CheckMode` and the `stock` fact `StockLock` also need `default_transaction_mode: :immediate` in `config/config.exs`, so the check and the write are one step.

`StockEdits.tla`:

| Constant | TRUE when the code has |
|---|---|
| `StockLock` | `stock: :item_locations` in `Item`'s section table, `:stock -> stock_changed?` in `edited_sections/2`, `save_item/4` starting its Multi with `check_sections/3`, which rejects the save when `Item.changed_sections/2` lists an edited section, and `default_transaction_mode: :immediate` so the read and the write are one step. A save that changes stock compares the stored stock with the stock it started from |
| `SyncOnlyChangedStock` | `if stock_changed?, do: sync_stock(...)` in `save_item/4`, so a name or notes save never writes back the stock it started from |
| `AgentReadsInTx` | `write_stock/4` calling `fetch_item_for_stock/1` inside `Repo.transact`, and `default_transaction_mode: :immediate` in `config/config.exs` |
| `ChangeStockChecksBelowZero` | `new < 0 -> {:error, {:below_zero, current}}` in `changed_count/3` |
| `ChangeStockChecksMax` | `new > DraftStock.max_quantity() -> {:error, :too_many}` in `changed_count/3` |
| `MoveStockChecksMax` | `to + quantity > DraftStock.max_quantity() -> {:error, :too_many}` in `moved_counts/4` |
| `MoveStockChecksEnough` | `quantity > from -> {:error, {:not_enough, from}}` in `moved_counts/4` |
| `QuantityMustBePositive` | `validate_number(:quantity, greater_than: 0, ...)` in `ItemLocation.changeset/2`, or the `quantity_must_be_positive` CHECK in the item_locations migration |
| `SaveChecksMax` | `less_than_or_equal_to: DraftStock.max_quantity()` in the same `validate_number(:quantity, ...)`, so `update_item/4` refuses any count above the max |
| `AdjustCapsAtMax` | `max_quantity` inside `DraftStock.put/3` |
| `LocationDeleteChecksStock` | the `:empty?` step calling `location_has_items?` in `Locations.delete/2` |
| `StaleReloadRaises` | `Items.get_item!(` anywhere in the `{:error, :stale} ->` branch of `EditItemLive`'s save handler. FALSE means the branch uses `Items.get_item/1`, and `reconcile/2` sends a deleted item's page to the items list |
| `ReconcileKeepsEditedStock` | `Enum.split_with(&section_dirty?(socket.assigns, &1))` in `EditItemLive.reconcile/2` with only the clean sections passed to `load_section/3`, and `section_dirty?(assigns, :stock)` checking `stock_total_mode != :clean`. Edited stock keeps its draft and shows the warning |

Some properties have two guards, so removing only one of them passes:

- `AgentNeverStoresOverMax` fails only when `SaveChecksMax` and `ChangeStockChecksMax` (or `MoveStockChecksMax`) are both FALSE.
- `EditPageNeverStoresOverMax` fails only when `SaveChecksMax` and `AdjustCapsAtMax` are both FALSE.
- `StockNeverNegative` fails only when `QuantityMustBePositive` and `ChangeStockChecksBelowZero` (or `MoveStockChecksEnough`) are both FALSE.
- In `item`, `NoLostUpdate` fails only when `CheckMode` is `"none"` or `WritesOnlyEdited` is FALSE.

When a check fails, compare the facts with a run on `master`:

1. A fact flipped, and the change meant to remove or move that guard. If the guard is gone, the failure is real. Report the counterexample. If the guard moved or was renamed, update its regex and rerun.
2. A fact flipped by accident, for example after a reformat. Fix the regex so it matches the same guard.
3. No fact changed, but the property fails. The change altered behavior a model describes as fixed. Find the action in the tables below, compare it with the new code, and update the model to match the code. Never loosen a property to make it pass.

## Where SectionSaves comes from

A section's value is abstract, 0 or 1. Typing a value and typing it back reaches every case the checks care about, including a change that someone undoes before another person saves.

| Model action | item | location | convention |
|---|---|---|---|
| `Open`, `Close` | `load_item/2`, `show_item/2`, navigating away | `handle_params/3`, `show_location/2` | `mount/3`, `show_version/2` |
| `Type` | `handle_event("validate")`, `set_quantity`, `adjust`, `restore_version` | `handle_event("validate")` | `handle_event("validate")`, `format`, `restore_version` |
| `Save` | `handle_event("save")` calling `Items.update_item/4` | `handle_event("save")` calling `Locations.update/2` | `handle_event("save")` calling `NamingConvention.save/3` |
| `Save` with a stale outcome | `put_drafts/3`, then `reconcile/2` with `Items.get_item/1` | `reconcile/2` with `Locations.get/1` | `put_text/3`, then `reconcile/2` with the newest version |
| `Notice` | `handle_info` for a `Pinventory.LiveEdits` `:saved` or `:deleted` notice | the same | the same, `:saved` only |
| `KeepMyEdits`, `LoadLatest` | `handle_event("keep_my_edits")`, `handle_event("load_latest")` for one section, from `socket.assigns.latest` | the same, from `socket.assigns.latest` | the same, from `socket.assigns.stale` |
| `Delete` | `handle_event("confirm_delete")` calling `Items.delete_item/2` | `handle_event("confirm_delete")` calling `Locations.delete/2` | none |
| `AgentRead`, `AgentWrite` | MCP `rename_item`: `Items.get_item/1`, then a name-only `update_item/4` | MCP `rename_location`: `Locations.get/1`, then `Locations.update/3` | MCP `get_naming_convention`, then `edit_naming_convention` with its version |
| `AtomicWrite` | `change_stock/4`, `move_stock/5` through `write_stock/4` | none | none |

The Save button is disabled while a warning shows, but the server does not check, so the model lets a client save anyway. A save that edits nothing returns the base without writing, so the model leaves it out. Two ghost variables exist only for checking. `writes` counts committed writes, to bound the state space. `bad` records which properties a step broke.

## Where StockEdits comes from

Each action is one SQLite transaction. The repo runs immediate transactions, so a transaction holds the write lock from its first read, and one transaction is one atomic step.

| Model action | Code |
|---|---|
| `Open`, `Close` | `EditItemLive` `load_item/2`, `show_item/2`, navigating away |
| `Type` | `handle_event("set_quantity")` with `DraftStock.parse_quantity/1` |
| `Adjust` | `handle_event("adjust")` with `DraftStock.adjust/3` |
| `EditFields` | typing a new name or notes |
| `Save`, `Outcome`, `Commit` | `handle_event("save")` calling `Items.update_item/4`: `check_sections/3`, Multi.update, `sync_stock/3`, `validate_locations_exist/3`, `ItemLocation.changeset/2` |
| `Reconcile` | `reconcile/2`: compares the page's base item with the latest one by section value. Edited stock keeps its draft and shows the warning. Unedited stock reloads in place, which also clears a stock warning whose draft was typed back to the baseline. Stock changed back to the baseline clears the warning too |
| `Save` with a stale outcome | `reconcile/2` after `{:error, :stale}`, or the items list when the item is gone |
| `Notice` | `handle_info` for a `Pinventory.LiveEdits` `:saved` or `:deleted` notice, then `reconcile/2`, or the items list when the item is gone |
| `KeepMyEdits`, `LoadLatest` | `handle_event("keep_my_edits")`, `handle_event("load_latest")` with `"section" => "stock"`. Both use the item the last `reconcile/2` fetched, and neither touches name or notes edits |
| `ChangeStock`, `ChangeCounts` | `Items.change_stock/4`, `changed_count/3`, `write_stock/4` |
| `MoveStock`, `MoveCounts` | `Items.move_stock/5`, `moved_counts/4`, `write_stock/4` |
| `AgentRead` | only when `AgentReadsInTx` is FALSE: the read runs in its own transaction |
| `DeleteItem` | `Items.delete_item/2` with the `on_delete: :delete_all` cascade |
| `DeleteLocation` | `Locations.delete/2` with the cascade |

The MCP `rename_item` tool is a name-only `update_item/4` that reads the item in its own transaction first. Under `SyncOnlyChangedStock` it writes no stock, and otherwise it behaves like a page that opens, edits the name, and saves.

The MCP `rename_item` tool is a name-only `update_item/4` that reads the item in its own transaction first. Under `SyncOnlyChangedStock` it writes no stock, and otherwise it behaves like a page that opens, edits the name, and saves.

Two ghost variables exist only for checking. `writes` counts committed writes to the stock, to bound the state space. `bad` records which properties a step broke. A save breaks `NoLostUpdate` when it writes stock while the stored stock differs from the stock its writer started from, so a change that was undone before the save is not a lost update.

## Bounds and assumptions

`SectionSaves.tla`:

- Two edit pages and one MCP agent per run. Pages are interchangeable.
- At most 2 committed writes in `item` and 3 in `location` and `convention`, deletes included. Page opens, drafts, warnings, and refused saves are not limited. Two writes are enough for a change and its undo before a third person saves.
- A page counts a section as edited when its draft differs from its base. The item page's name is trimmed before the save compares it, so typing only trailing spaces looks edited on the page and unedited to the save. The model leaves that out.
- Notices can arrive at any time and in any order. The model lets a page reconcile at any moment, and does not track the PubSub message itself.
- Deletes compare nothing. Deleting is a confirmed action, so the model treats it as intended, not as a lost update. The other editor is sent to the list with a message.

`StockEdits.tla`:

- Two edit pages, one agent, one item, and two locations. Pages are interchangeable, and so are locations.
- `Max = 1` stands for 1,000,000. Counts range over 0 to 2, so one past the limit is reachable.
- At most 2 committed writes to the item. Page opens, drafts, stale banners, and failed saves are not limited.
- The agent may call `change_stock` with any add from -2 to 2 and any set from 0 to 2, and `move_stock` with any quantity from 1 to 2.
- Writes to other items are left out. Each save locks only its own item's row and stock.
- A save on a deleted item is stale, because `check_sections/3` finds no row. Without that check it is modeled as an error with no change.
- If `AgentReadsInTx` turns FALSE, the agent's write still goes through `check_sections/3`, which rejects a snapshot that no longer matches. If the transaction mode is no longer immediate, `StockLock` turns FALSE too, since the comparison and the write could be split. SQLite in WAL mode would reject some of those writes as busy instead, so the model is stricter than the database there.

## Not covered

- The floor plan. Its changes are written and shown live, with no save to conflict.
- `create_item/3`, `Locations.create/2`, `Locations.restore/2`, and audit events.
- What a warning shows. The model checks whether a section warns, not the names, counts, or diff in it.
- "Also editing" presence, accounts, API tokens, and search.
- Anything beyond the bounds above.

## Findings

Each finding below is in `KNOWN_FINDINGS` in the script, as `run:property`.

- `convention:NoFalseConflict` and `convention:WarningsMatchSaved`. The naming convention checks version numbers, not text. Someone saves a change and then saves the old text back. A person who started before both saves is refused, and their page warns, although the saved text is the text they started from. This is the documented contract of `NamingConvention.save/3` and the MCP `edit_naming_convention` tool, which both take a version. Changing it changes that tool, so it stays a known finding.

## Coverage

Sync commit: `8477f7c3bfd9e69986e7e3a64c34f088c9c33979`

Move the sync commit forward only after you confirm, at the new commit, that the models and the code facts still describe the code below. The script lists covered files changed since the sync commit.

- `lib/pinventory/items.ex`: `update_item/4`, `save_item/4`, `edited_sections/2`, `check_sections/3`, `change_stock/4`, `move_stock/5`, `changed_count/3`, `moved_counts/4`, `write_stock/4`, `fetch_item_for_stock/1`, `check_locations/1`, `delete_item/2`, `sync_stock/3`, `validate_locations_exist/3`, `normalize_desired_stock/1`, `unwrap_item_transaction/1`
- `lib/pinventory/items/item.ex`: the section table, `changed_sections/2`, `put_section/3`
- `lib/pinventory/items/draft_stock.ex`: `put/3`, `adjust/3`, `parse_quantity/1`, `max_quantity/0`
- `lib/pinventory/items/item_location.ex`: `changeset/2`
- `lib/pinventory/locations.ex`: `update/2`, `check_name/2`, `delete/2`, `unwrap_location_transaction/2`
- `lib/pinventory/naming_convention.ex`: `save/3`, `current/0`
- `lib/pinventory_web/live/edit_item_live.ex`: `handle_event/3` for `save`, `adjust`, `set_quantity`, `keep_my_edits`, `load_latest`, `confirm_delete`, `handle_info/2` for `Pinventory.LiveEdits` notices, `reconcile/2`, `section_dirty?/2`, `load_section/3`, `show_item/2`, `assign_base/2`
- `lib/pinventory_web/live/location_live.ex`: `handle_event/3` for `save`, `keep_my_edits`, `load_latest`, `confirm_delete`, `handle_info/2` for `Pinventory.LiveEdits` notices, `reconcile/2`, `show_location/2`, `sync_dirty/1`
- `lib/pinventory_web/live/naming_convention_live.ex`: `handle_event/3` for `save`, `keep_my_edits`, `load_latest`, `handle_info/2` for `Pinventory.LiveEdits` notices, `reconcile/2`, `show_version/2`, `put_text/3`
- `lib/pinventory_web/mcp_router.ex`: the `change_stock`, `move_stock`, `rename_item`, `rename_location`, and `edit_naming_convention` tools
- `config/config.exs`: `default_transaction_mode`
- `priv/repo/migrations/20260223042150_create_locations_and_item_locations.exs`: the cascades and the quantity CHECK
