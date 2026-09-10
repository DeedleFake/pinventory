# Locations

Locations is the list of named storage places. A user adds a location, opens its page, renames it, and sees items stored there.

## Sub-features

- `locations-empty` shows `No locations yet` on a fresh database.
- `locations-add` inserts from `#location-new-form`.
- `locations-open` navigates to `/location/<id>`.
- `locations-rename` saves a new name from `#location_name`.
- `locations-items` lists stock at that location only (`#location-item-<item-id>`).
- `locations-floor-plan` shows `#floor-plan-add` when no plan exists. With a plan, the list is a three-pane browse layout (`#locations-workspace`, `#locations-floor-canvas`, `#locations-floor-rail`) plus `#floor-plan-edit`. There is no `#floor-plan-preview`. See [Floor plan](./floor-plan.md).

## How to get to it (user POV)

- Choose `Locations` in the header (`#nav-locations`).
- Open `/locations`.
- Choose a row (`#location-<id>`).
- From an item editor, follow `Add locations` when `#item-locations-empty` is shown.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded.
- No location is named `Verify Garage` or `Verify Shed`.

- **Empty chrome.** Run `verify-pinventory browser goto /locations`. Wait for `#locations-page`. `#location-new-form` and `#location-add-button` are visible. `#nav-locations` is current. `#locations-empty` text includes `No locations yet`. `#floor-plan-add` is present. `#floor-plan-preview` is absent.
- **Add.** Type a name and add. Run `verify-pinventory browser fill '#location-new_name' 'Verify Garage'` and `verify-pinventory browser click '#location-add-button'`. A row contains `Verify Garage`.
- **Id.** Run `verify-pinventory sqlite "select id, name from locations where name = 'Verify Garage';"`.
- **Open.** Click the row. Run `verify-pinventory browser click '#location-<id>'`. Wait for `#location-page`. `#location_name` value is `Verify Garage`. `#location-items-empty` is visible. `#location-delete` is enabled.
- **Rename.** Change the name. Run `verify-pinventory browser fill '#location_name' 'Verify Shed'`. Run `verify-pinventory browser wait-enabled '#location-save'`. Click save. Run `verify-pinventory browser click '#location-save'`. Wait for `#flash-info` `Location saved`. `#location_name` value is `Verify Shed`.
- **List reflects rename.** Run `verify-pinventory browser click '#nav-locations'`. The row text is `Verify Shed`. There is no `Verify Garage` row.
- **Proof.** Run `verify-pinventory browser screenshot locations/list.png` and `verify-pinventory browser html locations/list.html`. Run `verify-pinventory sqlite "select name from locations;"`. The name is `Verify Shed`.

## Gotchas

- The add field id is `#location-new_name`. The editor field id is `#location_name`. They are different pages.
- Location list stream ids are `#location-<uuid>`, singular, not `#locations-<uuid>`.
- `#location-save` is disabled until the name is dirty. Debounce is 300ms. Use `browser enabled '#location-save'`, not `attr disabled`.
- Location names are unique and trimmed. Min length is 1.
- The location page does not change stock. To put an item here, open the item editor. See [Items](./items.md).
- Delete is disabled once any stock row exists. See [Delete](./delete.md).
- Floor-plan badges only appear when a plan exists. Unplaced locations show `Not on plan`. Hover a placed row to highlight its polygon; hover does not switch floors.
- `#locations-empty` stays in the DOM (`hidden only:block`) after the first add. Assert the row text, not that the empty node is gone.
