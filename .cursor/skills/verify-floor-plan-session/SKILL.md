---
name: verify-floor-plan-session
description: Model-check what happens when several people edit the Pinventory floor plan at once, with undo and redo, deleting the whole plan, and the "deleted the floor plan" banner with Restore, using a TLA+ model whose guard settings are read from the code. Use when a change touches FloorPlanLive's undo, redo, push_undo_snapshot, history_entry, apply_remote_change, drop_stale_history, deleted_in_use, track_deletions, restore_deleted, the delete-plan confirm, or FloorPlans.restore_plan_geometry, restore_deleted, delete_floor_plan, plan_geometry_snapshot, the wall, impassable area, or placement writes, or announce, or when running /verify-floor-plan-session.
---

# Verify floor plan session

A TLA+ model checks that, with several people on the floor plan at once, undo never takes back someone else's change, Restore brings back everything a plan delete removed, and the delete confirm and the deleted banner match the plan. TLC, the TLA+ model checker, tries every order of the steps below within the bounds.

Every floor plan change is written as it happens and announced to the other pages with `{:floor_plan_changed, by}`. The notice carries no data. Each page refetches when it handles the notice, in `apply_remote_change/2`. A page handles one message at a time, so a user's event can run before a notice that is already on its way.

## Run it

From the repo root:

```bash
./.cursor/skills/verify-floor-plan-session/scripts/check-floor-plan-session
```

It needs Java 11 or newer, `perl`, and `curl`. It shares `tla2tools.jar` 1.7.4 in `~/.cache/pinventory/` with `verify-save-conflicts`, and downloads and checks it the same way. A run takes about 15 seconds with `TLC_WORKERS=2`. Output and counterexamples go to `tmp/verify-floor-plan-session/`.

To check one rule of one run alone, ignoring the known findings list:

```bash
./.cursor/skills/verify-floor-plan-session/scripts/check-floor-plan-session --only prompt:UndoKeepsOthersChanges
```

There are two runs:

- `race`: a user can act while a notice to their page is still on its way. This is how the code runs.
- `prompt`: every notice is handled before the user's next event. This shows what the guards give when notices are on time, so a broken guard fails here even though `race` already fails.

## What it checks

| Rule | Plain meaning | Harm when broken |
|---|---|---|
| `UndoKeepsOthersChanges` | Undo and redo never take back a change someone else made. | Someone's wall, area, or placement silently disappears, or a deleted plan comes back. |
| `RestoreBringsBackAll` | Restore after someone deletes the plan brings back everything the delete removed. | The restored plan is missing recent walls, and nobody can get them back. |
| `ConfirmOnlyWithPlan` | The delete-plan confirm shows only while the page shows a plan. | The page shows "Delete the whole floor plan?" under "Someone deleted the floor plan", and its Delete does nothing. |
| `BannerMatchesPlan` | Once a page has handled its notices, it shows the "deleted the floor plan" banner exactly when the plan is gone. | A Restore banner for a plan that is back, or no way to restore a deleted plan. |

## Read the result

- `PASS <run>: ...` lists every rule that held in every reachable state of that run.
- `FAIL <run>:<rule>` means a new break. Open the `.out` file it names. Its `State N:` lines are the steps.
- `KNOWN FINDING still present` is expected for the findings below. The check exits 0 when only those fail.
- `FIXED? <run>:<rule> now passes` means the model no longer finds that break. Confirm the fix with a test, then remove it from `KNOWN_FINDINGS` in the script and from Findings below. The check exits 1 until you do.
- `TOOL ERROR` means TLC did not finish. Read the `.out` file.

Read every result with the `/statechart` skill. It turns a violation into its shortest path in plain words. On a pass it draws how the session moves between states.

## Real bug or modeling error

The script prints `code facts` first. Each is a model constant read from `lib/pinventory_web/live/floor_plan_live.ex` by a regex in the script. A regex that stops matching turns its fact FALSE.

| Constant | TRUE when the code has |
|---|---|
| `HistoryDropsOnRemoteChange` | `apply_remote_change/2` piping into `drop_stale_history(before.floors, floors)`, which clears `:undo_stack` and `:redo_stack` when `FloorPlans.plan_geometry_snapshot/1` of the old and new floors differ |
| `DeletionsFilterStillDeleted` | `track_deletions/2` keeping only entries for which `still_deleted?/2` holds |
| `RemoteDeleteClosesConfirm` | a function other than `mount/3` and the `cancel_delete_plan` handler setting `:delete_plan?` to false. FALSE today. When it turns TRUE, read that code and confirm it runs on a remote change that leaves no plan |

When a rule fails:

1. A fact flipped, and the change meant to remove or move that guard. If the guard is gone, the failure is real. If it moved or was renamed, update its regex and rerun.
2. A fact flipped by accident, for example after a reformat. Fix the regex.
3. No fact changed, but a rule fails. The change altered behavior that the model describes as fixed. Find the action in the table below, compare it with the code, and update the model to match the code. Never loosen a rule to make it pass.

Replay a counterexample against the real code before calling it a bug. A LiveView test can hold a page's notice by suspending that page's process (`:sys.suspend(view.pid)`) while another page writes, or by writing a row with `Repo.insert!` and sending `{:floor_plan_changed, nil}` to the page afterwards.

## Where the model comes from

The plan is abstract: whether it exists, and which elements it has. An element stands for a wall, an impassable area, or a location placement. Undo snapshots and restores all three the same way, in `FloorPlans.plan_geometry_snapshot/1` and `restore_plan_geometry/2`.

| Model action | Code |
|---|---|
| `Open`, `Close` | `mount/3`, which needs a plan and otherwise navigates to `/locations`; navigating away |
| `Draw`, `Erase` | `handle_event` for `wall_drawn`, `impassable_placed`, `polygon_placed` (`place_polygon/3`), `wall_erased`, `impassable_erased`: `push_undo_snapshot/1` of the page's `@floors`, the `FloorPlans` write, then `refresh_selected_floor/2`, which reloads every floor. On a failed write, `pop_failed_undo/1` |
| `Undo`, `Redo` | `handle_event("undo")`, `handle_event("redo")`: `history_entry/2` of `@floors` onto the other stack, then `FloorPlans.restore_plan_geometry/2`, which writes the snapshot over the whole plan and creates it if it is gone |
| `OpenConfirm`, `CancelConfirm` | `open_delete_plan`, `cancel_delete_plan`. The Delete plan button shows only while `@floors != []` |
| `ConfirmDelete` | `confirm_delete_plan`: `FloorPlans.delete_floor_plan/1`, then navigating to `/locations`. With no plan it returns `{:error, :not_found}` and the page stays |
| `Notice` | `handle_info({:floor_plan_changed, by})`: `apply_remote_change/2` with `deleted_in_use/3`, `track_deletions/2`, `drop_stale_history/3` |
| `Restore` | `restore_deleted`: `FloorPlans.restore_deleted/2`, which puts back missing floors from the banner's snapshot and leaves existing floors alone |
| `Dismiss` | `dismiss_deleted`, which navigates away ("Leave") when there is no plan |

Each `FloorPlans` write is one step and notifies every other open page (`announce/2` uses `broadcast_from`). Ghost variables exist only for checking: `writes` bounds the state space, `removed` is what the last plan delete removed, each page's `expect` is the plan as that page's own history last left it, and `bad` records which rule a step broke. Undo and redo break `UndoKeepsOthersChanges` when the plan is gone or when they change an element that is not as `expect` has it.

## Bounds and assumptions

- Three pages and two elements, each element drawn at most once. Pages are interchangeable, and so are elements. Three pages let one delete the plan while a second restores it and a third watches.
- Undo and redo hold one entry each, not `FloorPlans.undo_limit/0` (50). One is enough for every break found. Deeper stacks only lengthen the paths.
- At most 4 committed writes. Opens, notices, confirms, and failed writes are not limited.
- Notices to one page are handled in order, and several notices act as one: the page refetches the current plan either way.
- A write on a deleted plan fails without crashing the page.

## Not covered

- Floors: adding, removing, renaming, reordering, which floor is selected, and the floor rail's rename form and remove confirm (`editing_floor_id`, `removing_floor_id`).
- Placing locations (`mode`, `placing_location_id`, `place_mode`), location deletes and renames from other pages, and the per-floor and per-location deletion banners.
- `add_wall/2` merging collinear walls, `cut_wall_gap/4`, `unplace_location/2`, and any page crash, for example `FloorPlans.get_floor!/1` on a floor deleted by someone else.
- A new plan made with `create_floor_plan/0` while a page shows the old plan's banner.
- The canvas hooks in `assets/js/hooks/`.
- Anything beyond the bounds above.

## Findings

Each finding is in `KNOWN_FINDINGS` in the script, as `run:rule`.

- `race:UndoKeepsOthersChanges`. Page A draws a wall. Page B draws a wall. A presses Undo before A handles B's notice. `restore_plan_geometry/2` writes A's snapshot, which does not have B's wall, so B's wall is deleted. The same happens later when A draws while B's notice is on its way: `refresh_selected_floor/2` loads B's wall into A's `@floors`, so `drop_stale_history/3` sees no change when the notice lands, and A's next Undo deletes B's wall. Since 87c7528 (#7), narrowed by e99fd2a (#40).
- `race:RestoreBringsBackAll`. Page B draws a wall and deletes the plan before page A handles the first notice. A refetches once, finds no plan, and builds the banner's snapshot from its old `@floors`, without the wall. A presses Restore, and the plan comes back without B's wall. Any other banner for the plan disappears, because its floors exist again. Since e99fd2a (#40).
- `race:ConfirmOnlyWithPlan`. Page A opens the delete confirm. Someone else deletes the plan. A shows the confirm under the deleted banner, and its Delete returns `{:error, :not_found}` and does nothing. Nothing clears `:delete_plan?` on a remote change. Since e99fd2a (#40), which added the banner.

## Coverage

Sync commit: `f2154b6fd6e95309198b2a5aa338521208772306`

Move the sync commit forward only after you confirm, at the new commit, that the model and the code facts still describe the code below. The script lists covered files changed since the sync commit.

- `lib/pinventory_web/live/floor_plan_live.ex`: `mount/3`, `handle_event/3` for `wall_drawn`, `wall_erased`, `impassable_placed`, `impassable_erased`, `polygon_placed`, `undo`, `redo`, `open_delete_plan`, `cancel_delete_plan`, `confirm_delete_plan`, `restore_deleted`, `dismiss_deleted`, `handle_info/2` for `:floor_plan_changed`, `place_polygon/3`, `push_undo_snapshot/1`, `history_entry/2`, `pop_failed_undo/1`, `trim_stack/1`, `refresh_selected_floor/2`, `apply_remote_change/2`, `deleted_in_use/3`, `track_deletions/2`, `still_deleted?/2`, `drop_deletion/2`, `restore_deleted/2`, `drop_stale_history/3`
- `lib/pinventory/floor_plans.ex`: `add_wall/2`, `remove_wall/2`, `add_impassable_area/2`, `remove_impassable_area/2`, `place_location/3`, `delete_floor_plan/1`, `plan_geometry_snapshot/1`, `restore_plan_geometry/2`, `restore_deleted/2`, `announce/2`
