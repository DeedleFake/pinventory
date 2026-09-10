# Floor plan

Optional multi-floor editor for drawing walls, cutting gaps, and marking location **areas** and unlabeled **impassable** polygons. Absence of a floor plan means the feature is off.

## Sub-features

- `floor-plan-add` creates the plan from `#floor-plan-add` on `/locations`.
- `floor-plan-browse` shows a three-pane locations page when a plan exists: list `#locations-list-pane`, browse canvas `#locations-floor-canvas` (`data-mode=browse`), floor rail `#locations-floor-rail`. Edit is `#floor-plan-edit`. There is no `#floor-plan-preview`.
- `floor-plan-list-hover` highlights the matching polygon: hover a placed row and `#placement-group-<id>` gains `.is-list-hover`. Hover does **not** switch floors.
- `floor-plan-edit` opens `/locations/floor-plan` (`#floor-plan-page`) in a wide `Layouts.app` content column.
- `floor-plan-layout` is a three-pane workspace: `#floor-plan-sidebar` (~17rem) + `#floor-plan-canvas` (`flex-1`, `h-[calc(100vh-12rem)]`) + `#floor-rail` (`lg:w-80`). Undo/redo live in sidebar `#floor-plan-history`.
- `floor-plan-walls` draws segments from `#tool-wall`. **Click once** for the start (snap), **click again** for the end to commit; a draft line follows the cursor between clicks. Escape cancels the pending start. Endpoints snap to wall vertices/segments **and** location polygon vertices/edges; a snap dot shows while snapping. Hold **Ctrl/Meta** to place at raw coords (no snap). A second click within the snap radius of the pending start reuses that endpoint (no near-duplicate stub). Center-clicking the canvas twice does not draw.
- `floor-plan-gap` cuts a hole in a wall with `#tool-gap` (“Cut gap”). Click two points on one wall (`wall_gapped`). Remainders stay as wall rows. Escape cancels the pin. Ctrl/Meta still snaps along the wall. Draw wall / Erase / Gap / Impassable all clear place mode.
- `floor-plan-erase` deletes a wall segment with `#tool-erase` (click the segment hit target). Wall erase does not delete impassable polygons.
- `floor-plan-impassable` draws unlabeled hatched polygons with `#tool-impassable` (`Draw area`) and deletes them with `#tool-impassable-erase`. Impassable is a sidebar category between Walls and Locations (`#floor-plan-impassable-tools`). Draw works like a new location polygon (click vertices; close near first, double-click, Enter, or `#polygon-finish` Done; Escape cancels). Snap matches place (walls + placement verts/edges); impassable polygons also expose `data-snap-edge` / `data-snap-vertex`. Impassable erase does not delete walls. Undo restores them. The locations browse canvas paints the same hatch.
- `floor-plan-floors` adds, renames, and removes floors via `#floor-rail` / `#floor-add` / `#floor-tab-<id>` / `#floor-rename-form-<id>` / `#floor-remove-<id>`. There is no `#floor-tabs` or `#floor-rename-row`. Keep at least one floor; remove is disabled for the last floor. Drag `#floor-drag-<id>` reorders.
- `floor-plan-place` selects an unplaced location row in `#placeable-locations` as the drawing tool (`mode=place` for that id; no `#tool-place`). Unplaced rows show an **Open** badge. Click vertices; finish by closing near the first point, **double-click**, or `#polygon-finish` Done. Escape cancels the draft. Uses the same bidirectional snap helpers as walls. Hold **Ctrl/Meta** to skip snap. Clicks within the snap radius of an already-placed draft corner reuse that vertex (no stacked near-duplicates); closing near the first point still finishes the polygon.
- `floor-plan-placed` on this floor replaces the place button with a disabled **Here** div (`#place-location-<id>[aria-disabled]`) plus `#unplace-location-<id>`. Extend (`data-place-mode=extend`) is not reachable from the UI. Placement is one floor per location; drawing again on another floor does not move it (`already_placed`). Other-floor rows switch to that floor instead of placing.
- `floor-plan-unplace` removes a placement from the location row (`#unplace-location-<id>`).
- `floor-plan-undo-redo` uses `#history-undo` / `#history-redo` in the sidebar and Ctrl/Meta+Z, Ctrl/Meta+Shift+Z, Ctrl/Meta+Y.
- `floor-plan-list-badges` shows floor name (`#location-<id>-floor`) or `Not on plan` (`#location-<id>-not-on-plan`) on location rows when a plan exists.
- `floor-plan-delete` removes the whole plan via `#floor-plan-delete` then `#floor-plan-delete-confirm-button`; locations remain.
- Floor-plan success actions are silent (no info flash); navigation and UI updates are the feedback.

## How to get to it (user POV)

- Open `/locations`.
- With no plan, choose `Add Floor Plan`.
- With a plan, choose `Edit floor plan`.
- Editor path is `/locations/floor-plan`.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded.
- Inventory may already have locations from the Locations recipe.

- **Add plan.** Run `verify-pinventory browser goto /locations`. Wait for `#locations-page`. Click `#floor-plan-add`. Wait for `#floor-plan-page`. `#floor-plan-sidebar`, `#floor-plan-canvas`, `#floor-rail`, and `#tool-gap` are present. `#floor-plan-preview` and `#floor-tabs` are absent.
- **Draw wall.** Click `#tool-wall`. Run two `browser click-at '#floor-plan-canvas [data-floor-plan-svg]' <x> <y>` at **distinct** CSS-pixel offsets (for example `150 220` then `480 220`). Keep y below the Reset view overlay. Wait with `browser wait-attached '[data-wall-id]'` (not `wait`; SVG hit targets are not “visible”). Sqlite has a `walls` row.
- **Cut gap.** Click `#tool-gap`. Run `browser click-box '[data-wall-id]' 0.3 0.5` then `0.7 0.5`. Sqlite wall count becomes 2 remainders with a gap between them.
- **Draw impassable.** Click `#tool-impassable`. Three or more `click-at` points on the SVG, then `#polygon-finish`. Wait-attached `[data-impassable-id]`. A hatched unlabeled polygon appears.
- **Place area.** Create a location first if needed. Click `#place-location-<id>` (Open badge; that selects place mode; `data-place-mode` is `new`). Three `click-at` points, then `#polygon-finish`. Wait-attached `#placement-group-<id>`. The row shows **Here** and `#unplace-location-<id>`.
- **Undo/redo.** Click `#history-undo` / `#history-redo`. Sqlite placement count follows.
- **Add floor.** Click `#floor-add`. A second rail item appears. Sqlite `floors` has two names.
- **List badges + highlight.** Run `verify-pinventory browser goto /locations`. Wait for `#locations-workspace` and `#locations-floor-canvas`. Placed rows show `#location-<id>-floor`. Unplaced rows show `#location-<id>-not-on-plan` with `Not on plan`. Hover `#location-<id>`; `#placement-group-<id>` class includes `is-list-hover`.
- **Delete plan.** Open the editor (`#floor-plan-edit`). Click `#floor-plan-delete`, then `#floor-plan-delete-confirm-button`. Wait for `#locations-page` and `#floor-plan-add`. Locations still list. Sqlite `floors` count is 0.
- **Proof.** Screenshot `floor-plan/editor.png` and `floor-plan/list.png`. Run `verify-pinventory sqlite "select name from floors;"`.

## Gotchas

- The plan is optional (any floors ⇒ feature on). Deleting it does not delete locations.
- Placement is one floor per location. The UI does not move a polygon by redrawing on another floor.
- Coordinates are unbounded world floats. Walls are rows (`x1,y1,x2,y2`); placements and impassable areas store `points` JSON (≥3 `{x,y}`). Impassable areas are not locations and have no names.
- Paint order is impassable under locations under walls. Impassable fill is a muted hatch, not `.placement-area` primary.
- Keep at least one floor; last-floor remove is disabled.
- Editor canvas should be wide and tall (`flex-1` beside the sidebar, `h-[calc(100vh-12rem)]`). List browse canvas is the same height beside the list, not a compact top preview.
- There is no separate Place area palette button; unplaced location rows are the place tool. The picker badge is **Open**, not `Not on plan` (`Not on plan` is list-only).
- SVG exposes `data-snap-vertex` / `data-snap-edge` on placement and impassable geometry so the hook can snap walls and polygons both ways.
- Ctrl/Meta bypasses snap for wall and location placement (raw canvas coords); draft-corner dedupe still uses the shared snap radius at commit time.
- `browser click` on `#floor-plan-canvas` hits the center twice and draws nothing. Use `click-at` on the SVG, then `click-box` on existing `[data-wall-id]` / `[data-impassable-id]`.
- Extra chrome (not required for the recipes above): `#floor-plan-zoom-reset`, wheel zoom, Space/middle-drag pan, Shift 22.5° angle snap, floor-rail drag.
