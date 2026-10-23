# Items

Items is the home list. A user creates a named item, sets quantities per location, keeps notes, filters the list, and reopens the same item from the row.

## Sub-features

- `items-empty` shows `No items yet. Add an item` on a fresh database.
- `items-new` opens `/item` from `#new-item`.
- `items-save` persists a name of at least two characters.
- `items-stock` changes quantity at a location and updates `#item-total-value`.
- `items-notes` saves free text in `#item_notes`. Dirty notes show `#item-notes-hint` with `Unsaved note change`.
- `items-notes-history` shows `#note-edited-menu` once an item has saved notes (`edited 1 time` right after create with notes, `edited 2 times` after the next note save). A version link (`#note-edited-<n>`) opens `#note-history`, which has `#note-history-restore`, `#note-view-inline` / `#note-view-split`, and `#note-history-close`.
- `items-list` shows the saved row with a stock label (`#items-<id>-stock`) and the last stock change (`#items-<id>-last-stock`).
- `items-filter` narrows the list by name substring (`#q`) and by location (`#location`, option `All locations`). The two combine.

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
- **Open editor.** Choose New Item. Run `verify-pinventory browser click '#new-item'`. Wait for `#item-page`. Heading is `New item`. `browser enabled '#item-save'` prints `disabled`. `#item-delete` count is 0.
- **Name.** Type the name. Run `verify-pinventory browser fill '#item_name' 'Verify Hammer'`. Run `verify-pinventory browser wait-enabled '#item-save'`.
- **Stock.** Read the location id. Run `verify-pinventory sqlite "select id from locations where name = '<your location>';"`. Click plus. Run `verify-pinventory browser click '#quantity-inc-<location-id>'` with that id. `#item-total-value` reads `1`. `#item-total` has `data-stock-dirty="true"`.
- **Notes.** Run `verify-pinventory browser fill '#item_notes' 'Top shelf'`. `#item-notes-hint` contains `Unsaved note change`.
- **Save.** Choose Save. Run `verify-pinventory browser click '#item-save'`. Wait for `#flash-info` with `Item created` and `#item-activity`. Heading is `Edit item`. `#note-edited-menu` already reads `edited 1 time` because the create saved notes.
- **Note history.** Run `verify-pinventory browser fill '#item_notes' 'Bottom shelf'`. Wait for `#item-save` to enable, then click it. Wait for `#flash-info` `Item saved`. `#note-edited-menu` now reads `edited 2 times`. Click it, click `#note-edited-1`, and wait for `#note-history`. It lists v0 (empty), v1 and v2. Click `#note-history-restore`. The panel closes and `#item-notes-hint` reads `Unsaved note change · restored from v1`. Do not save. Leave with `verify-pinventory browser goto /`.
- **List.** On `/`, wait for `#items-page`. A link contains `Verify Hammer`. Stock text includes `1 total in 1 location`.
- **Filter match.** Type in the filter. Run `verify-pinventory browser fill '#q' 'hammer'`. Wait until `#items a` still contains `Verify Hammer`. `#q` value is `hammer`.
- **Filter by location.** The harness cannot pick a `<select>` option. Run `verify-pinventory browser goto '/?location=<location-id>&q=ham'`. The hammer row shows only for the location that holds stock, and `No items match.` for an empty one.
- **Filter miss.** Replace the query. Run `verify-pinventory browser fill '#q' 'no-such-item'`. `#items-empty` contains `No items match.`
- **Persistence.** Clear the filter (`goto /`) and reopen the row. The editor `#item_name` value is `Verify Hammer`. Run `verify-pinventory sqlite "select name from items where name = 'Verify Hammer';"`. One row.
- **Proof.** Run `verify-pinventory browser screenshot items/list.png` and `verify-pinventory browser html items/list.html` on `/` with the hammer row visible. Also keep the sqlite output.

## Gotchas

- Save enables when the name, stock, or notes are dirty. Otherwise it stays disabled. Wait for enabled. Do not click a disabled `#item-save`. Use `browser enabled`, not `attr disabled` (boolean attributes print blank either way).
- `#items-empty` stays in the DOM (`hidden only:block`) when rows exist. Assert row text or empty copy, not that the node is gone.
- `#item_name` debounces 300ms. `wait-enabled '#item-save'` is the signal, not a sleep.
- Stock plus/minus ids include the location uuid, not the name. Query sqlite first.
- Item names are unique and trimmed. Min length is 2. Save still enables for a one-character name. The server then shows `should be at least 2 character(s)` under the name and stays on `New item`.
- Typing at least two characters in the name of a new item shows `#item-suggestions` (`Similar items already exist`, one `#item-suggestion-<id>` row per match, each with an `Open` link). Click `#item_name` before typing.
- New item has no delete button. Delete is edit-only. See [Delete](./delete.md).
- Unsaved stock does not block delete later. The modal totals come from saved stock.
- Filter `#location` is the location select on the items list. It is not the location editor `#location_name`.
- `#new-item` exists only on `#items-page`. From Locations, run `goto /item` or click `#nav-items` first.
