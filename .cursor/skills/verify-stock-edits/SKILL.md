---
name: verify-stock-edits
description: Model-check how Pinventory saves an item's stock when edit pages, the MCP agent tools, and item or location deletes race each other, using a TLA+ model whose guard settings are read from the code. Use when a change touches Items.update_item, the Item section versions, change_stock, move_stock, delete_item, Locations.delete, DraftStock, the edit page's save, live-notice, or stale handling, item_locations constraints, or the repo's transaction mode, or when running /verify-stock-edits.
---

# Verify stock edits

The model in `model/StockEdits.tla` checks that racing writes to one item's stock never lose a change, never store a bad count, and never break the edit page. TLC, the TLA+ model checker, tries every order of the steps below within the bounds. Tests only cover the orders someone wrote down.

## Run it

From the repo root:

```bash
./.cursor/skills/verify-stock-edits/scripts/check-stock-edits
```

It needs Java 11 or newer, `perl`, and `curl`. The first run downloads `tla2tools.jar` 1.8.0 to `~/.cache/pinventory/` and checks its sha256. Set `TLA2TOOLS_JAR` to use another copy. A run takes about 20 seconds on 8 cores and 35 on 4. `TLC_WORKERS=2` limits the cores it uses.

To check one property alone, ignoring the known findings list:

```bash
./.cursor/skills/verify-stock-edits/scripts/check-stock-edits --only MoveKeepsTotal
```

Output and counterexamples go to `tmp/verify-stock-edits/`. CI runs the same command in the `Stock edits model` job.

## What it checks

Each property is an invariant in the model:

| Property | Plain meaning | Harm when broken |
|---|---|---|
| `NoLostUpdate` | No save overwrites a change its writer never saw. | Someone's stock or name change silently disappears. |
| `StockNeverNegative` | No stored count is below 0. | Impossible counts in lists and totals. |
| `AgentNeverStoresOverMax` | `change_stock` and `move_stock` never store a count above 1,000,000. | The agent writes counts the UI refuses to accept. |
| `EditPageNeverStoresOverMax` | An edit-page save never stores a count above 1,000,000. | Same, from the browser. |
| `MoveKeepsTotal` | `move_stock` never changes the item's total. | A move creates or destroys stock. |
| `LocationDeleteKeepsStock` | Deleting a location never throws stock away. | Stock vanishes with the location. |
| `StaleSaveNeverCrashes` | A save that loses a race never crashes the edit page. | The page dies and the user loses their unsaved edits. |

## Read the result

- `PASS` lists every property that held in every reachable state.
- `FAIL <property>` means a new break. Open the `.out` file it names. Its `State N:` lines are the steps, and the variables under each step show what changed.
- `KNOWN FINDING still present` is expected for the findings below. The check exits 0 when only those fail.
- `FIXED? <property> now passes` means the model no longer finds that break. Confirm the fix in the code with a test, since a code fact can flip without the bug being gone. Then remove the property from `KNOWN_FINDINGS` in the script and from Findings below. The check exits 1 until you do.
- `TOOL ERROR` means TLC did not finish. Read the `.out` file. It is usually a model syntax or type error.

Read every result with the `/statechart` skill. It turns a violation into its shortest path in plain words and shows which violations a change fixes. On a pass it draws how the system moves between states.

## Real bug or modeling error

The script prints `code facts` first. Each is a model constant read from the code by one regex in `scripts/check-stock-edits`:

| Constant | TRUE when the code has |
|---|---|
| `StockLock` | `stock: {:item_locations, :stock_version}` in `Item`'s section table, `:stock -> stock_changed?` in `edited_sections/2`, and `save_item/4` passing the edited sections to `lock_sections/2`, which calls `optimistic_lock(field)`. A save that changes stock checks `stock_version` |
| `ForceVersionBump` | `force_change(field, Map.fetch!(changeset.data, field))` in `lock_sections/2`, so stock-only saves also update the row and check the version |
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

Some properties have two guards, so removing only one of them passes:

- `AgentNeverStoresOverMax` fails only when `SaveChecksMax` and `ChangeStockChecksMax` (or `MoveStockChecksMax`) are both FALSE.
- `EditPageNeverStoresOverMax` fails only when `SaveChecksMax` and `AdjustCapsAtMax` are both FALSE.
- `StockNeverNegative` fails only when `QuantityMustBePositive` and `ChangeStockChecksBelowZero` (or `MoveStockChecksEnough`) are both FALSE.

When a check fails, compare the facts with a run on `master`:

1. A fact flipped, and the change meant to remove or move that guard. If the guard is gone, the failure is real. Report the counterexample. If the guard moved or was renamed, update its regex and rerun.
2. A fact flipped by accident, for example after a reformat. Fix the regex so it matches the same guard.
3. No fact changed, but the property fails. The change altered behavior the model describes as fixed. Find the action in the table below, compare it with the new code, and update the model to match the code. Never loosen a property to make it pass.

## Where the model comes from

Each action is one SQLite transaction. The repo runs immediate transactions, so a transaction holds the write lock from its first read, and one transaction is one atomic step.

| Model action | Code |
|---|---|
| `Open`, `Close` | `EditItemLive` `load_item/2`, `show_item/2`, navigating away |
| `Type` | `handle_event("set_quantity")` with `DraftStock.parse_quantity/1` |
| `Adjust` | `handle_event("adjust")` with `DraftStock.adjust/3` |
| `EditFields` | typing a new name or notes |
| `Save`, `Outcome`, `Commit` | `handle_event("save")` calling `Items.update_item/4`: Multi.update with the lock, `sync_stock/3`, `validate_locations_exist/3`, `ItemLocation.changeset/2` |
| `Save` with a stale outcome | `reconcile/2` after `{:error, :stale}`: the stock warning, or the items list when the item is gone |
| `Notice` | `handle_info` for a `Pinventory.LiveEdits` notice, then `reconcile/2`: unedited stock reloads, edited stock shows the warning, a deleted item leaves for the list |
| `KeepMyEdits`, `LoadLatest` | `handle_event("keep_my_edits")`, `handle_event("load_latest")` with `"section" => "stock"` |
| `ChangeStock`, `ChangeCounts` | `Items.change_stock/4`, `changed_count/3`, `write_stock/4` |
| `MoveStock`, `MoveCounts` | `Items.move_stock/5`, `moved_counts/4`, `write_stock/4` |
| `AgentRead` | only when `AgentReadsInTx` is FALSE: the read runs in its own transaction |
| `DeleteItem` | `Items.delete_item/2` with the `on_delete: :delete_all` cascade |
| `DeleteLocation` | `Locations.delete/2` with the cascade |

Two ghost variables exist only to state properties. `writes` counts committed writes to the stock, and each reader remembers the count it saw. `bad` records which properties a step broke.

## Bounds and assumptions

- Two edit pages, one agent, one item, and two locations. Pages are interchangeable, and so are locations.
- `Max = 1` stands for 1,000,000. Counts range over 0 to 2, so one past the limit is reachable.
- At most 2 committed writes to the item. Page opens, drafts, stale banners, and failed saves are not limited.
- The agent may call `change_stock` with any add from -2 to 2 and any set from 0 to 2, and `move_stock` with any quantity from 1 to 2.
- Writes to other items are left out. Each save locks only its own item's row and stock.
- A save on a deleted item that issues no item UPDATE is modeled as an error with no change. In the code it fails on the item_locations foreign key, or does nothing when every count is 0.
- If `AgentReadsInTx` turns FALSE because the transaction mode is no longer immediate, the model lets the stale write through the lock rules. SQLite in WAL mode would reject some of those writes as busy instead, so the model is stricter than the database there.

## Not covered

- `create_item/3`, name and notes contents, their section versions, and audit events. The model only tracks whether a save changed the name or notes. A name or notes save that loses to another save of the same section is a test case in `test/pinventory/items_test.exs`, not a model property.
- `delete_item/2` deletes without checking any section version. The model treats a delete as intended, not as a lost update.
- Floor plans, accounts, API tokens, search, and the LiveView's other events.
- Anything beyond 2 writes, 2 pages, or 2 locations.

## Findings

None. Every property holds for the current code, and `KNOWN_FINDINGS` in the script is empty. When the check finds a break that can't be fixed in the same change, add the property to `KNOWN_FINDINGS` and describe its shortest path here.

## Coverage

Sync commit: `32f109f9b861c8b1c66ec8096e0972572a2ad78c`

Move the sync commit forward only after you confirm, at the new commit, that the model and the code facts still describe the code below. The script lists covered files changed since the sync commit.

- `lib/pinventory/items.ex`: `update_item/4`, `save_item/4`, `edited_sections/2`, `lock_sections/2`, `change_stock/4`, `move_stock/5`, `changed_count/3`, `moved_counts/4`, `write_stock/4`, `fetch_item_for_stock/1`, `check_locations/1`, `delete_item/2`, `sync_stock/3`, `validate_locations_exist/3`, `normalize_desired_stock/1`, `unwrap_item_transaction/1`
- `lib/pinventory/items/item.ex`: the section table
- `lib/pinventory/items/draft_stock.ex`: `put/3`, `adjust/3`, `parse_quantity/1`, `max_quantity/0`
- `lib/pinventory/items/item_location.ex`: `changeset/2`
- `lib/pinventory/locations.ex`: `delete/2`
- `lib/pinventory_web/live/edit_item_live.ex`: `handle_event/3` for `save`, `adjust`, `set_quantity`, `keep_my_edits`, `load_latest`, `handle_info/2` for `Pinventory.LiveEdits` notices, `reconcile/2`, and `load_section/3`
- `lib/pinventory_web/mcp_router.ex`: the `change_stock` and `move_stock` tools
- `config/config.exs`: `default_transaction_mode`
- `priv/repo/migrations/20260223042150_create_locations_and_item_locations.exs`: the cascades and the quantity CHECK
