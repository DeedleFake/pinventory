# Delete

Delete removes an item or an empty location after the user types the saved name. Location delete refuses when stock still exists.

## Sub-features

- `delete-item-modal` opens from `#item-delete` on an edit item page.
- `delete-item-confirm` enables submit only when the typed name matches.
- `delete-item-gone` removes the item and returns to `/`.
- `delete-location-blocked` disables `#location-delete` when the location has items.
- `delete-location-empty` deletes an empty location after name confirm and returns to `/locations`.

## How to get to it (user POV)

- On an item edit page, choose `Delete`.
- On a location page, choose `Delete`.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded.
- For item delete, an item named `Verify Disposable` exists (create it from [Items](./items.md) if needed).
- For blocked location delete, a location named `Verify Full` has at least one item with quantity > 0.
- For empty location delete, a location named `Verify Empty` has no `item_locations` rows.

- **Item modal.** Open the item. Run `verify-pinventory browser click '#item-delete'`. Wait for `#item-delete-modal`. `browser enabled '#item-delete-confirm-submit'` prints `disabled`.
- **Wrong name.** Type a mismatch. Run `verify-pinventory browser fill '#item-delete-confirm' 'nope'`. Submit stays `disabled`.
- **Confirm.** Type the saved name. Run `verify-pinventory browser fill '#item-delete-confirm' 'Verify Disposable'`. Run `verify-pinventory browser wait-enabled '#item-delete-confirm-submit'`. Click it. Wait for `#items-page` and `#flash-info` `Item deleted`.
- **Item gone.** Run `verify-pinventory browser exists '#items-empty'` or confirm the list has no `Verify Disposable`. Run `verify-pinventory sqlite "select count(*) as n from items where name = 'Verify Disposable';"`. `n` is `0`.
- **Location blocked.** Open `Verify Full`. `browser enabled '#location-delete'` prints `disabled`. `#location-delete-reason` is `Remove items from this location first.` Run `verify-pinventory sqlite "select count(*) as n from item_locations il join locations l on l.id = il.location_id where l.name = 'Verify Full';"`. `n` is > 0. Do not click the disabled button.
- **Location empty delete.** Open `Verify Empty`. `#location-delete` is enabled. Click it. Wait for `#location-delete-modal`. Fill `#location-delete-confirm` with `Verify Empty`. Click `#location-delete-confirm-submit`. Wait for `#locations-page` and flash `Location deleted`. Sqlite has no row named `Verify Empty`.
- **Proof.** Screenshot the items list after item delete (`delete/items-after.png`) and the locations list after location delete (`delete/locations-after.png`). Keep the sqlite counts.

## Gotchas

- Confirm match is exact or both sides trimmed. Case is sensitive. `keep me` does not match `Keep Me`.
- Unsaved name blocks delete (`Save or revert the name first.`). Save or reload before opening the modal.
- Item delete removes stock rows with the item. It does not write `stock.changed` events for those quantities.
- Location delete does not move stock. Zero the quantities on each item, or delete the items, then delete the location.
- The location delete button is disabled when blocked. Do not treat a disabled click as a proof of refusal. Read `#location-delete-reason`.
- After delete, Settings activity may still show the event. See [Settings](./settings.md) for which cards stay links.
