# Floor plan

Optional multi-floor editor for drawing walls and marking location **areas** as polygons. Absence of a floor plan means the feature is off.

## Sub-features

- `floor-plan-add` creates the plan from `#floor-plan-add` on `/locations`.
- `floor-plan-preview` shows `#floor-plan-preview` (uses available list width, tall viewport) at the top of the locations list when a plan exists. Hover/focus a placed location row to highlight its polygon and switch the preview to that floor.
- `floor-plan-edit` opens `/locations/floor-plan` (`#floor-plan-page`) in a wide `Layouts.app` content column.
- `floor-plan-layout` is a drafting workspace: thin top bar → floor rename bar → flex row with `#floor-plan-sidebar` (~17rem) + `#floor-plan-canvas` (`flex-1`, `h-[calc(100vh-12rem)]`).
- `floor-plan-walls` draws segments from the sidebar Walls tools (`#tool-wall`). **Click once** for the start (snap), **click again** for the end to commit; a draft line follows the cursor between clicks. Escape cancels the pending start. Endpoints snap to wall vertices/segments **and** location polygon vertices/edges; a snap dot shows while snapping.
- `floor-plan-erase` deletes a wall segment with `#tool-erase` (click the segment hit target). Draw wall / Erase clear any selected location drawing tool.
- `floor-plan-floors` adds, renames, and removes floors via `#floor-tabs` / `#floor-rename-row`.
- `floor-plan-place` selects a location row in `#placeable-locations` as the drawing tool (`mode=place` for that id; no `#tool-place`). Click vertices; finish by closing near the first point, **double-click**, or `#polygon-finish` Done. Escape cancels the draft. Uses the same bidirectional snap helpers as walls.
- `floor-plan-extend` is the default when the selected location already has a polygon on this floor (`data-place-mode=extend`). Click near an existing vertex to attach, add points, then close by clicking any existing vertex of that polygon (or Done to close back to the attach). The client merges the chain and sends the full `points` list via `polygon_placed`.
- `floor-plan-redraw` replaces an area from scratch via `#redraw-location-<id>` on a placed row (`data-place-mode=redraw`).
- `floor-plan-unplace` removes a placement from the location row (`#unplace-location-<id>`).
- `floor-plan-undo-redo` uses `#history-undo` / `#history-redo` in the top bar and Ctrl/Meta+Z, Ctrl/Meta+Shift+Z, Ctrl/Meta+Y.
- `floor-plan-list-badges` shows floor name or `Not on plan` on location rows when a plan exists.
- `floor-plan-delete` removes the whole plan via `#floor-plan-delete`; locations remain.
- Floor-plan success actions are silent (no info flash); navigation and UI updates are the feedback.

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
- **Draw wall.** Click `#tool-wall` in the sidebar. Click once on `#floor-plan-canvas`, move, click again to commit. Watch for the snap dot near walls and location corners. Escape cancels a pending start.
- **Erase wall.** Click `#tool-erase`, then click a wall segment.
- **Add floor.** Click `#floor-add`. A second tab appears.
- **Place area.** Create a location first if needed. Click `#place-location-<id>` (that selects place mode). Click three or more points on the canvas, then close near the first point, double-click, or click `#polygon-finish`. A filled labeled polygon appears. Snap matches wall drawing (walls ↔ location vertices/edges).
- **Extend area.** Select a placed location again. Click near a corner to attach, add points, then click a **different** corner to close (or Done to close on an adjacent edge). Merged outline must stay a simple polygon (no hourglass). Use `#redraw-location-<id>` to replace from scratch instead.
- **Unplace.** Click `#unplace-location-<id>` on a placed row.
- **Undo/redo.** Click `#history-undo` / `#history-redo`, or use Ctrl+Z / Ctrl+Shift+Z while not typing in an input.
- **List badges + highlight.** Run `verify-pinventory browser goto /locations`. Preview uses list width (`#floor-plan-preview`). Placed rows show a floor chip (`#location-<id>-floor`). Unplaced rows show `#location-<id>-not-on-plan` with `Not on plan`. Hover a placed row; `#preview-placement-<id>` strengthens on the preview.
- **Delete plan.** Open the editor. Click `#floor-plan-delete`, then `#floor-plan-delete-confirm-button`. Wait for `#locations-page` and `#floor-plan-add`. Locations still list.
- **Proof.** Screenshot `floor-plan/editor.png` and `floor-plan/list.png`. Run `verify-pinventory sqlite "select name from floors;"`.

## Gotchas

- The plan is optional and singleton. Deleting it does not delete locations.
- Placement is one floor per location. Drawing again on another floor moves the polygon.
- Coordinates are normalized 0.0–1.0. Placements store `points` JSON (≥3 `{x,y}`), not pin x/y.
- Keep at least one floor; `#floor-remove` is disabled for the last floor.
- Editor canvas should be wide and tall (`flex-1` beside the sidebar, `h-[calc(100vh-12rem)]`). List preview stays tall within the locations column.
- There is no separate Place area palette button; location rows are the place tool.
- SVG exposes `data-snap-vertex` / `data-snap-edge` on placement geometry so the hook can snap walls and polygons both ways.
