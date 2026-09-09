# Floor plan

Optional multi-floor editor for drawing simple walls and placing location pins. Absence of a floor plan means the feature is off.

## Sub-features

- `floor-plan-add` creates the plan from `#floor-plan-add` on `/locations`.
- `floor-plan-preview` shows `#floor-plan-preview` at the top of the locations list when a plan exists.
- `floor-plan-edit` opens `/locations/floor-plan` (`#floor-plan-page`).
- `floor-plan-walls` draws segments on `#floor-plan-canvas` in Draw wall mode.
- `floor-plan-floors` adds, renames, and removes floors via `#floor-tabs`.
- `floor-plan-place` places a location pin from `#placeable-locations`.
- `floor-plan-list-badges` shows floor name or `Not on plan` on location rows when a plan exists.
- `floor-plan-delete` removes the whole plan via `#floor-plan-delete`; locations remain.

## How to get to it (user POV)

- Open `/locations`.
- With no plan, choose `Add Floor Plan`.
- With a plan, choose the preview card or `Edit floor plan`.
- Editor path is `/locations/floor-plan`.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded.
- Inventory may already have locations from the Locations recipe.

- **Add plan.** Run `verify-pinventory browser goto /locations`. Wait for `#locations-page`. Click `#floor-plan-add`. Wait for `#floor-plan-page`.
- **Draw wall.** Click `#tool-wall`. Drag on `#floor-plan-canvas` (Playwright drag if available; otherwise push is covered by LiveView tests). Prefer proving walls via `sqlite` after a UI drag when the harness supports it.
- **Add floor.** Click `#floor-add`. A second tab appears.
- **Place.** Create a location first if needed. Click `#place-location-<id>`, then click the canvas. The pin label appears.
- **List badges.** Run `verify-pinventory browser goto /locations`. Placed rows show a floor chip (`#location-<id>-floor`). Unplaced rows show `#location-<id>-not-on-plan` with `Not on plan`.
- **Delete plan.** Open the editor. Click `#floor-plan-delete`, then `#floor-plan-delete-confirm-button`. Wait for `#locations-page` and `#floor-plan-add`. Locations still list.
- **Proof.** Screenshot `floor-plan/editor.png` and `floor-plan/list.png`. Run `verify-pinventory sqlite "select name from floors;"`.

## Gotchas

- The plan is optional and singleton. Deleting it does not delete locations.
- Placement is one floor per location. Moving a pin to another floor updates the same placement row.
- Canvas coordinates are normalized 0.0–1.0.
- Keep at least one floor; `#floor-remove` is disabled for the last floor.
