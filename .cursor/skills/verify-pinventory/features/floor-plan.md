# Floor plan

Optional multi-floor editor for drawing walls and marking location **areas** as polygons. Absence of a floor plan means the feature is off.

## Sub-features

- `floor-plan-add` creates the plan from `#floor-plan-add` on `/locations`.
- `floor-plan-preview` shows `#floor-plan-preview` (large viewport) at the top of the locations list when a plan exists. Hover/focus a placed location row to highlight its polygon and switch the preview to that floor.
- `floor-plan-edit` opens `/locations/floor-plan` (`#floor-plan-page`).
- `floor-plan-walls` draws segments on `#floor-plan-canvas` in Draw wall mode (`#tool-wall`).
- `floor-plan-erase` deletes a wall segment with `#tool-erase` (click the segment hit target).
- `floor-plan-floors` adds, renames, and removes floors via `#floor-tabs`.
- `floor-plan-place` draws a location polygon from `#placeable-locations` (click vertices; double-click / Enter / close to first point to finish). Replaces an existing placement for that location.
- `floor-plan-undo-redo` uses `#history-undo` / `#history-redo` and Ctrl/Meta+Z, Ctrl/Meta+Shift+Z, Ctrl/Meta+Y.
- `floor-plan-list-badges` shows floor name or `Not on plan` on location rows when a plan exists.
- `floor-plan-delete` removes the whole plan via `#floor-plan-delete`; locations remain.

## How to get to it (user POV)

- Open `/locations`.
- With no plan, choose `Add Floor Plan`.
- With a plan, choose `Edit floor plan` (or the preview Edit control).
- Editor path is `/locations/floor-plan`.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded.
- Inventory may already have locations from the Locations recipe.

- **Add plan.** Run `verify-pinventory browser goto /locations`. Wait for `#locations-page`. Click `#floor-plan-add`. Wait for `#floor-plan-page`.
- **Draw wall.** Click `#tool-wall`. Drag on `#floor-plan-canvas`.
- **Erase wall.** Click `#tool-erase`, then click a wall segment.
- **Add floor.** Click `#floor-add`. A second tab appears.
- **Place area.** Create a location first if needed. Click `#place-location-<id>`, click three or more points on the canvas, then double-click or press Enter. A filled labeled polygon appears. Endpoints snap to nearby wall vertices.
- **Undo/redo.** Click `#history-undo` / `#history-redo`, or use Ctrl+Z / Ctrl+Shift+Z while not typing in an input.
- **List badges + highlight.** Run `verify-pinventory browser goto /locations`. Preview is tall (`#floor-plan-preview`). Placed rows show a floor chip (`#location-<id>-floor`). Unplaced rows show `#location-<id>-not-on-plan` with `Not on plan`. Hover a placed row; `#preview-placement-<id>` strengthens on the preview.
- **Delete plan.** Open the editor. Click `#floor-plan-delete`, then `#floor-plan-delete-confirm-button`. Wait for `#locations-page` and `#floor-plan-add`. Locations still list.
- **Proof.** Screenshot `floor-plan/editor.png` and `floor-plan/list.png`. Run `verify-pinventory sqlite "select name from floors;"`.

## Gotchas

- The plan is optional and singleton. Deleting it does not delete locations.
- Placement is one floor per location. Drawing again on another floor moves the polygon.
- Coordinates are normalized 0.0–1.0. Placements store `points` JSON (≥3 `{x,y}`), not pin x/y.
- Keep at least one floor; `#floor-remove` is disabled for the last floor.
- Canvas should be large (`min-h` ~65vh editor, ~45–50vh list preview).
