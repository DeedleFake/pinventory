# Locations

Locations is the list of named storage places. A user adds a location, opens its page, renames it, and sees items stored there.

## Sub-features

- `locations-empty` shows `No locations yet` on a fresh database.
- `locations-add` inserts from `#location-new-form` with flash `Location created`. The new row shows at the top until the list reloads, then rows are in name order. A duplicate name shows `has already been taken` and a blank one `can't be blank`.
- `locations-open` navigates to `/location/<id>`.
- `locations-rename` saves a new name from `#location_name`.
- `locations-live` shows someone else's rename on an open location page as it happens. An unedited name reloads in place. An edited name stays and `#location-name-stale` shows their name next to yours (`#location-name-stale-diff`), with `#location-name-stale-keep` and `#location-name-stale-load`. Save is disabled until one is clicked. A deleted location sends the page to `/locations` with `Someone deleted this location.` `#location-editors` lists anyone else with the page open.
- `locations-items` lists stock at that location only (`#location-item-<item-id>`, with `#location-item-<item-id>-quantity`). `#location-total-value` is the total stock there and `#location-activity-list` lists its edits.
- `locations-floor-plan` shows `#floor-plan-add` when no plan exists. With a plan, `/locations` becomes `/locations/<floor-id>` and the list is a three-pane browse layout (`#locations-workspace`, `#locations-floor-canvas`, `#locations-floor-rail`) plus `#floor-plan-edit`. There is no `#floor-plan-preview`. See [Floor plan](./floor-plan.md).

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
- **Unknown id.** Run `verify-pinventory browser goto /location/00000000-0000-0000-0000-000000000000`. The browser lands on `#locations-page` with flash `Location not found.` (with no floor plan; see Gotchas).
- **Open.** Click the row. Run `verify-pinventory browser click '#location-<id>'`. Wait for `#location-page`. `#location_name` value is `Verify Garage`. `#location-items-empty` is visible. `#location-delete` is enabled.
- **Rename.** Change the name. Run `verify-pinventory browser fill '#location_name' 'Verify Shed'`. Run `verify-pinventory browser wait-enabled '#location-save'`. While the name is dirty, `#location-delete` is disabled and `#location-delete-reason` reads `Save or revert the name first.` Click save. Run `verify-pinventory browser click '#location-save'`. Wait for `#flash-info` `Location saved`. `#location_name` value is `Verify Shed`. `#location-delete` is enabled again.
- **List reflects rename.** Run `verify-pinventory browser click '#nav-locations'`. The row text starts with `Verify Shed` (then `0 items`). There is no `Verify Garage` row.
- **Live rename.** With person 2 logged in as another user (see `PINVENTORY_PERSON` in the skill Drive section), both open the location. `#location-editors` reads `Also editing: sam@example.com`. Person 2 renames and saves; your `#location_name` shows the new name with no warning. Fill `#location_name` yourself, then have person 2 save another name. `#location-name-stale-diff` reads `Their name: <theirs> · Yours: <yours>` and Save is disabled. Click `#location-name-stale-keep`, then save. Sqlite has your name. When person 2 deletes a location you have open, your page lands on `#locations-page` with `#flash-error` `Someone deleted this location.`
- **Proof.** Run `verify-pinventory browser screenshot locations/list.png` and `verify-pinventory browser html locations/list.html`. Run `verify-pinventory sqlite "select name from locations;"`. The name is `Verify Shed`.

## Gotchas

- The add field id is `#location-new_name`. The editor field id is `#location_name`. They are different pages.
- Location list stream ids are `#location-<uuid>`, singular, not `#locations-<uuid>`.
- `#location-save` is disabled until the name is dirty. Debounce is 300ms. Use `browser enabled '#location-save'`, not `attr disabled`.
- Location names are unique and trimmed. Min length is 1.
- A dirty name asks before leaving the page. The harness dismisses the browser dialog, so clicking `#nav-items` with an unsaved `#location_name` leaves you on `#location-page`. Save or revert first.
- Flashes that precede the browse redirect (`Location deleted`, `Location not found.`) are not shown while a floor plan exists. Assert them only on a database with no plan.
- The location page does not change stock. To put an item here, open the item editor. See [Items](./items.md).
- Delete is disabled once any stock row exists. See [Delete](./delete.md).
- Floor-plan badges only appear when a plan exists. Unplaced locations show `Not on plan`. Hover a placed row to highlight its polygon; hover does not switch floors.
- `#locations-empty` stays in the DOM (`hidden only:block`) after the first add. Assert the row text, not that the empty node is gone.
