# Items

Items is the home list. A user creates a named item, sets quantities per location, filters the list, and reopens the same item from the row.

## Sub-features

- `items-empty` shows `No items yet. Add an item` on a fresh database.
- `items-new` opens `/item` from `#new-item`.
- `items-save` persists a name of at least two characters.
- `items-stock` changes quantity at a location and updates `#item-total-value`.
- `items-list` shows the saved row with a stock label.
- `items-filter` narrows the list by name substring (`#q`).

## How to get to it (user POV)

- After login, the app opens `/` (Items).
- Choose `Items` in the header (`#nav-items`).
- Choose `New Item` (`#new-item`).
- Choose an item row (`#items-<id>`).

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` has landed on `#items-page`.
- A location named `Verify Garage` exists. If not, run the add step from [Locations](./locations.md) first (`goto /locations`, fill `#location-new_name`, click `#location-add-button`).
- No item is named `Verify Hammer`.

- **Empty or list chrome.** On `/`, run `verify-pinventory browser wait '#items-page'`. `#new-item` is visible. `#nav-items` is current. `#items-empty` text includes `No items yet`.
- **Open editor.** Choose New Item. Run `verify-pinventory browser click '#new-item'`. Wait for `#item-page`. Heading is `New item`. `browser enabled '#item-save'` prints `disabled`. `#item-delete` count is 0.
- **Name.** Type the name. Run `verify-pinventory browser fill '#item_name' 'Verify Hammer'`. Run `verify-pinventory browser wait-enabled '#item-save'`.
- **Stock.** Read the location id. Run `verify-pinventory sqlite "select id from locations where name = 'Verify Garage';"`. Click plus. Run `verify-pinventory browser click '#quantity-inc-<location-id>'` with that id. `#item-total-value` reads `1`. `#item-total` has `data-stock-dirty="true"`.
- **Save.** Choose Save. Run `verify-pinventory browser click '#item-save'`. Wait for `#flash-info` with `Item created` and `#item-activity`. Heading is `Edit item`.
- **List.** Return home. Run `verify-pinventory browser click '#nav-items'`. Wait for `#items-page`. A link contains `Verify Hammer`. Stock text includes `1 total in 1 location`.
- **Filter match.** Type in the filter. Run `verify-pinventory browser fill '#q' 'hammer'`. Wait until `#items a` still contains `Verify Hammer`. `#q` value is `hammer`.
- **Filter miss.** Replace the query. Run `verify-pinventory browser fill '#q' 'no-such-item'`. `#items-empty` contains `No items match.`
- **Persistence.** Clear the filter (`goto /`) and reopen the row. The editor `#item_name` value is `Verify Hammer`. Run `verify-pinventory sqlite "select name from items where name = 'Verify Hammer';"`. One row.
- **Proof.** Run `verify-pinventory browser screenshot items/list.png` and `verify-pinventory browser html items/list.html` on `/` with the hammer row visible. Also keep the sqlite output.

## Gotchas

- Save stays disabled until the name or stock is dirty. Wait for enabled. Do not click a disabled `#item-save`. Use `browser enabled`, not `attr disabled` (boolean attributes print blank either way).
- `#items-empty` stays in the DOM (`hidden only:block`) when rows exist. Assert row text or empty copy, not that the node is gone.
- `#item_name` debounces 300ms. `wait-enabled '#item-save'` is the signal, not a sleep.
- Stock plus/minus ids include the location uuid, not the name. Query sqlite first.
- Item names are unique and trimmed. Min length is 2.
- New item has no delete button. Delete is edit-only. See [Delete](./delete.md).
- Unsaved stock does not block delete later. The modal totals come from saved stock.
- Filter `#location` is the location select on the items list. It is not the location editor `#location_name`.
- `#new-item` exists only on `#items-page`. From Locations, run `goto /item` or click `#nav-items` first.
