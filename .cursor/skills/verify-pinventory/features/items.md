# Items

Items is the home list. A user creates a named item, sets quantities per location, keeps notes, filters the list, and reopens the same item from the row.

## Sub-features

- `items-empty` shows `No items yet. Add an item` on a fresh database.
- `items-new` opens `/item` from `#new-item`.
- `items-save` persists a name of at least two characters.
- `items-stock` changes quantity at a location and updates `#item-total-value`.
- `items-stock-invalid` rejects a typed quantity that is not a whole number from 0 to 1000000 (`-1`, `2.5`). The input gets `aria-invalid="true"`, `#quantity-error-<location-id>` reads `Enter a whole number from 0 to 1000000.`, the total keeps the last valid count, and `#item-save` is disabled until the value is fixed or plus/minus is used.
- `items-notes` saves free text in `#item_notes`. Dirty notes show `#item-notes-hint` with `Unsaved note change`.
- `items-notes-history` shows `#note-edited-menu` once an item has saved notes (`edited 1 time` right after create with notes, `edited 2 times` after the next note save). A version link (`#note-edited-<n>`) opens `#note-history`, which has `#note-history-restore`, `#note-view-inline` / `#note-view-split`, and `#note-history-close`.
- `items-naming-panel` shows the shared naming convention in a closed `#item-naming-convention` panel under the name, with an `Edit` link that opens the editor in a new tab. See [Naming convention](./naming-convention.md).
- `items-stale` refuses a save when someone else saved the item since the page loaded. `#item-stale-warning` reads `<email> saved this item while you were editing.`, `#item-stale-their-edit` names their save (`<email> via <token name>` for an agent), and `#item-stale-notes` diffs the notes when they differ. `#item-stale-keep` keeps the form on top of their version; `#item-stale-load` loads theirs.
- `items-list` shows the saved row with a stock label (`#items-<id>-stock`) and the last stock change (`#items-<id>-last-stock`).
- `items-filter` narrows the list by name (`#q`) and by location (`#location`, option `All locations`). The two combine. The name filter works like fzf: each space-separated word must have all its letters in the name in order, with gaps allowed, in any word order (`vrfhmr` and `hammer verify` both find `Verify Hammer`). Case folding is ASCII only. A name filter lists the best match first: an exact word (`salmon` puts `Salmon` above `Bags of Almonds`), then a word start, then looser matches, with ties going to the shorter name.

## How to get to it (user POV)

- After login, the app opens `/` (Items).
- Choose `Items` in the header (`#nav-items`).
- Choose `New Item` (`#new-item`).
- Choose an item row (`#items-<id>`).

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` has landed on `#items-page`.
- A location from [Locations](./locations.md) exists. Its name is `Verify Garage`, or `Verify Shed` after the rename step. Use the name you created in the sqlite lookup below. If none exists, run the add step from [Locations](./locations.md) first (`goto /locations`, fill `#location-new_name`, click `#location-add-button`).
- No item is named `Verify Hammer`.

- **Empty or list chrome.** On `/`, run `verify-pinventory browser wait '#items-page'`. `#new-item` is visible. `#nav-items` is current. `#items-empty` text includes `No items yet`.
- **Open editor.** Choose New Item. Run `verify-pinventory browser click '#new-item'`. Wait for `#item-page`. `browser text '#item-page h1 >> nth=0'` prints `New item`. `browser enabled '#item-save'` prints `disabled`. `#item-delete` count is 0.
- **Name.** Type the name. Run `verify-pinventory browser fill '#item_name' 'Verify Hammer'`. Run `verify-pinventory browser wait-enabled '#item-save'`.
- **Stock.** Read the location id. Run `verify-pinventory sqlite "select id from locations where name = '<your location>';"`. Click plus. Run `verify-pinventory browser click '#quantity-inc-<location-id>'` with that id. `#item-total-value` reads `1`. `#item-total` has `data-stock-dirty="true"`.
- **Bad quantity.** Run `verify-pinventory browser fill '#quantity-<location-id>' '-1'`, then `verify-pinventory browser wait '#quantity-error-<location-id>'`. It reads `Enter a whole number from 0 to 1000000.` `browser enabled '#item-save'` prints `disabled` and `#item-total-value` still reads `1`. Fill `1` again. `#quantity-error-<location-id>` count is 0 and Save is enabled.
- **Notes.** Run `verify-pinventory browser fill '#item_notes' 'Top shelf'`. `#item-notes-hint` contains `Unsaved note change`.
- **Save.** Choose Save. Run `verify-pinventory browser click '#item-save'`. Wait for `#flash-info` with `Item created` and `#item-activity`. The page heading is `Edit item`. `#note-edited-menu` already reads `edited 1 time` because the create saved notes.
- **Note history.** Run `verify-pinventory browser fill '#item_notes' 'Bottom shelf'`. Wait for `#item-save` to enable, then click it. Wait for `#flash-info` `Item saved`. `#note-edited-menu` now reads `edited 2 times`. Click it, click `#note-edited-1`, and wait for `#note-history`. It lists v0 (empty), v1 and v2. Click `#note-history-restore`. The panel closes and `#item-notes-hint` reads `Unsaved note change · restored from v1`. Do not save. Leave with `verify-pinventory browser goto /`.
- **List.** On `/`, wait for `#items-page`. A link contains `Verify Hammer`. Stock text includes `1 total in 1 location`.
- **Filter match.** Type in the filter. Run `verify-pinventory browser fill '#q' 'hammer'`. Wait until `#items a` still contains `Verify Hammer`. `#q` value is `hammer`. Then fill `vrfhmr` and `hammer verify`. Both still show the hammer row. `hmrx` shows `No items match.` because `x` is not in the name.
- **Filter by location.** The harness cannot pick a `<select>` option. Run `verify-pinventory browser goto '/?location=<location-id>&q=ham'`. The hammer row shows only for the location that holds stock, and `No items match.` for an empty one.
- **Filter miss.** Replace the query. Run `verify-pinventory browser fill '#q' 'no-such-item'`. `#items-empty` contains `No items match.`
- **Persistence.** Clear the filter (`goto /`) and reopen the row. The editor `#item_name` value is `Verify Hammer`. Run `verify-pinventory sqlite "select name from items where name = 'Verify Hammer';"`. One row.
- **Stale save.** Needs an API token and the `mcp` function from [Agent access](./agent-access.md). On the hammer's edit page, fill `#item_notes` with `Garage shelf` and wait for Save to enable. With `mcp`, call `rename_item` on the hammer with `Verify Claw Hammer`. Click `#item-save`. Wait for `#item-stale-warning`. `#item-stale-their-edit` reads `Their save: verify@example.com via Verify Agent · Verify Claw Hammer — renamed`. Click `#item-stale-keep`. `#item-name-hint` reads `Unsaved name change · was Verify Claw Hammer` and `browser value '#item_notes'` prints `Garage shelf`. Save. Sqlite has the name `Verify Hammer` and the notes `Garage shelf`.
- **Proof.** Run `verify-pinventory browser screenshot items/list.png` and `verify-pinventory browser html items/list.html` on `/` with the hammer row visible. Also keep the sqlite output.

## Gotchas

- Save and Delete sit in the header row at the top of the page (`#item-actions`), not under the form.
- Save enables when the name, stock, or notes are dirty. Otherwise it stays disabled. Wait for enabled. Do not click a disabled `#item-save`. Use `browser enabled`, not `attr disabled` (boolean attributes print blank either way).
- `#items-empty` stays in the DOM (`hidden only:block`) when rows exist. Assert row text or empty copy, not that the node is gone.
- `#item_name` debounces 300ms. `wait-enabled '#item-save'` is the signal, not a sleep.
- Stock plus/minus ids include the location uuid, not the name. Query sqlite first.
- Item names are unique and trimmed. Min length is 2. Save still enables for a one-character name. The server then shows `should be at least 2 character(s)` under the name and stays on `New item`.
- Typing at least two characters in the name of a new item shows `#item-suggestions` (same letters-in-order matching as the filter, best match first, so `vrfy hmr` suggests `Verify Hammer`). It has `Similar items already exist`, one `#item-suggestion-<id>` row per match, each with an `Open` link. Click `#item_name` before typing.
- New item has no delete button. Delete is edit-only. See [Delete](./delete.md).
- Unsaved stock does not block delete later. The modal totals come from saved stock.
- Filter `#location` is the location select on the items list. It is not the location editor `#location_name`.
- `#new-item` exists only on `#items-page`. From Locations, run `goto /item` or click `#nav-items` first.
