------------------------- MODULE FloorPlanSession -------------------------
(***************************************************************************)
(* Several people editing the floor plan at once in PinventoryWeb.         *)
(* FloorPlanLive, with undo and redo, deleting the whole plan, and the     *)
(* "deleted the floor plan" banner with Restore.                           *)
(*                                                                         *)
(* The plan is abstract: whether it exists, and which elements it has.     *)
(* An element stands for a wall, an impassable area, or a placement, which *)
(* undo snapshots and restores alike (FloorPlans.plan_geometry_snapshot/1).*)
(*                                                                         *)
(* Each page is one LiveView process. It handles one message at a time:    *)
(* a user event or a {:floor_plan_changed, by} notice. Each FloorPlans     *)
(* write is one step. A notice carries no data: the page refetches         *)
(* (apply_remote_change/2). A write's notice reaches the other pages       *)
(* later, so a page can act on a stale view while one is in flight.        *)
(*                                                                         *)
(* The boolean constants are code facts that scripts/check-floor-plan-     *)
(* session reads from the code.                                            *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Pages,      \* open floor plan pages
    Elems,      \* element ids; each is drawn at most once
    UndoMax,    \* undo and redo depth (FloorPlans.undo_limit/0 is 50)
    MaxWrites,  \* bound on committed writes, for a finite state space
    \* A user can act while a notice to their page is in flight. FALSE
    \* assumes every notice is handled before the user's next event.
    Racing,
    \* apply_remote_change/2 clears undo and redo when the refetched
    \* geometry differs from what the page showed (drop_stale_history/3).
    HistoryDropsOnRemoteChange,
    \* track_deletions/2 keeps a banner only while still_deleted?/2.
    DeletionsFilterStillDeleted,
    \* A remote change that leaves no plan closes this page's
    \* delete-plan confirm (:delete_plan? back to false).
    RemoteDeleteClosesConfirm

VARIABLES
    exists,   \* any Floor row exists
    plan,     \* elements stored now, {} when the plan is gone
    used,     \* element ids drawn so far
    removed,  \* ghost: what the last plan delete removed
    pg,       \* per page socket assigns
    writes,   \* ghost: committed writes, to bound the state space
    bad       \* ghost: which rules a step broke

vars == <<exists, plan, used, removed, pg, writes, bad>>

\* state:   "open" or "closed" (never opened, or navigated away)
\* viewEx:  @floors != [], the plan as this page last loaded it
\* view:    the elements in @floors
\* undo, redo: @undo_stack, @redo_stack, each entry a snapshot of view
\* expect:  ghost: the elements as this page's own history last left them.
\*          Undo and redo must find the plan that way in what they change.
\* pending: a notice to this page is in flight
\* confirm: @delete_plan?, the delete-plan confirm shows
\* banner:  the "plan" entry of @deletions shows; snap is what Restore
\*          puts back (its restore.floors)
ClosedPage == [state |-> "closed", viewEx |-> FALSE, view |-> {}, undo |-> <<>>,
               redo |-> <<>>, expect |-> {}, pending |-> FALSE, confirm |-> FALSE,
               banner |-> FALSE, snap |-> {}]

NoBad == [undoRevertsOther |-> FALSE, restoreIncomplete |-> FALSE]

Init ==
    /\ exists = TRUE
    /\ plan = {}
    /\ used = {}
    /\ removed = {}
    /\ pg = [p \in Pages |-> ClosedPage]
    /\ writes = 0
    /\ bad = NoBad

Push(stack, s) == IF Len(stack) < UndoMax THEN <<s>> \o stack
                  ELSE <<s>> \o SubSeq(stack, 1, UndoMax - 1)   \* trim_stack/1

\* broadcast_from: every page but the writer hears of the write.
Notify(pages, p) ==
    [q \in Pages |-> IF q # p /\ pages[q].state = "open"
                     THEN [pages[q] EXCEPT !.pending = TRUE] ELSE pages[q]]

\* The user can act on page p now.
CanAct(p) == pg[p].state = "open" /\ (Racing \/ ~pg[p].pending)

-----------------------------------------------------------------------------
(* Page events                                                             *)

\* mount/3: needs a plan, else the page navigates to /locations.
Open(p) ==
    /\ pg[p].state = "closed" /\ exists
    /\ pg' = [pg EXCEPT ![p] = [ClosedPage EXCEPT !.state = "open",
                                  !.viewEx = TRUE, !.view = plan, !.expect = plan]]
    /\ UNCHANGED <<exists, plan, used, removed, writes, bad>>

\* Navigating away.
Close(p) ==
    /\ pg[p].state = "open"
    /\ pg' = [pg EXCEPT ![p] = ClosedPage]
    /\ UNCHANGED <<exists, plan, used, removed, writes, bad>>

\* wall_drawn, impassable_placed, polygon_placed: push_undo_snapshot/1 of
\* the page's @floors, then the write, then refresh_selected_floor/2
\* reloads every floor. On a deleted plan the write fails and
\* pop_failed_undo/1 pops the snapshot; the redo stack stays cleared.
Draw(p, e) ==
    LET me == pg[p] IN
    /\ CanAct(p) /\ me.viewEx /\ e \notin used
    /\ IF exists THEN
          /\ plan' = plan \cup {e}
          /\ used' = used \cup {e}
          /\ writes' = writes + 1
          /\ pg' = Notify([pg EXCEPT ![p] = [me EXCEPT !.view = plan \cup {e},
                              !.expect = me.view \cup {e},
                              !.undo = Push(me.undo, me.view), !.redo = <<>>]], p)
       ELSE
          /\ pg' = [pg EXCEPT ![p].redo = <<>>]
          /\ UNCHANGED <<plan, used, writes>>
    /\ UNCHANGED <<exists, removed, bad>>

\* wall_erased, impassable_erased: the same, removing one element. A
\* missing element returns {:error, :not_found}.
Erase(p, e) ==
    LET me == pg[p] IN
    /\ CanAct(p) /\ me.viewEx /\ e \in me.view
    /\ IF exists /\ e \in plan THEN
          /\ plan' = plan \ {e}
          /\ writes' = writes + 1
          /\ pg' = Notify([pg EXCEPT ![p] = [me EXCEPT !.view = plan \ {e},
                              !.expect = me.view \ {e},
                              !.undo = Push(me.undo, me.view), !.redo = <<>>]], p)
       ELSE
          /\ pg' = [pg EXCEPT ![p].redo = <<>>]
          /\ UNCHANGED <<plan, writes>>
    /\ UNCHANGED <<exists, used, removed, bad>>

\* restore_plan_geometry/2 writes snapshot h over the whole plan, creating
\* the plan if it is gone. Breaks the rule when the plan is gone, or when
\* it changes an element that is not as this page's history left it:
\* someone else changed it since.
Revert(p, h) ==
    LET changed == {x \in Elems : (x \in plan) # (x \in h)}
    IN /\ plan' = h /\ exists' = TRUE
       /\ writes' = writes + 1
       /\ bad' = [bad EXCEPT !.undoRevertsOther =
                     @ \/ ~exists
                       \/ \E x \in changed : (x \in plan) # (x \in pg[p].expect)]

\* handle_event("undo"): history_entry/2 of @floors goes on the redo stack.
Undo(p) ==
    LET me == pg[p] IN
    /\ CanAct(p) /\ me.undo # <<>>
    /\ Revert(p, Head(me.undo))
    /\ pg' = Notify([pg EXCEPT ![p] = [me EXCEPT !.viewEx = TRUE, !.view = Head(me.undo),
                        !.expect = Head(me.undo), !.undo = Tail(me.undo), !.redo = Push(me.redo, me.view)]], p)
    /\ UNCHANGED <<used, removed>>

\* handle_event("redo")
Redo(p) ==
    LET me == pg[p] IN
    /\ CanAct(p) /\ me.redo # <<>>
    /\ Revert(p, Head(me.redo))
    /\ pg' = Notify([pg EXCEPT ![p] = [me EXCEPT !.viewEx = TRUE, !.view = Head(me.redo),
                        !.expect = Head(me.redo), !.redo = Tail(me.redo), !.undo = Push(me.undo, me.view)]], p)
    /\ UNCHANGED <<used, removed>>

\* open_delete_plan, cancel_delete_plan. The Delete plan button shows only
\* while @floors != [].
OpenConfirm(p) ==
    /\ CanAct(p) /\ pg[p].viewEx /\ ~pg[p].confirm
    /\ pg' = [pg EXCEPT ![p].confirm = TRUE]
    /\ UNCHANGED <<exists, plan, used, removed, writes, bad>>

CancelConfirm(p) ==
    /\ CanAct(p) /\ pg[p].confirm
    /\ pg' = [pg EXCEPT ![p].confirm = FALSE]
    /\ UNCHANGED <<exists, plan, used, removed, writes, bad>>

\* confirm_delete_plan: FloorPlans.delete_floor_plan/1, then the page
\* navigates to /locations. With no plan it returns {:error, :not_found}
\* and the page stays as it is.
ConfirmDelete(p) ==
    /\ CanAct(p) /\ pg[p].confirm
    /\ IF exists THEN
          /\ exists' = FALSE /\ plan' = {} /\ removed' = plan
          /\ writes' = writes + 1
          /\ pg' = Notify([pg EXCEPT ![p] = ClosedPage], p)
       ELSE UNCHANGED <<exists, plan, removed, writes, pg>>
    /\ UNCHANGED <<used, bad>>

\* restore_deleted: FloorPlans.restore_deleted/2 puts back the floors in
\* the banner's snapshot that are missing now, and leaves existing floors
\* alone. Breaks the rule when the plan comes back without something the
\* delete removed.
Restore(p) ==
    LET me == pg[p] IN
    /\ CanAct(p) /\ me.banner
    /\ IF exists THEN UNCHANGED <<exists, plan, writes, bad>>
       ELSE /\ exists' = TRUE /\ plan' = me.snap
            /\ writes' = writes + 1
            /\ bad' = [bad EXCEPT !.restoreIncomplete = @ \/ ~(removed \subseteq me.snap)]
    /\ pg' = Notify([pg EXCEPT ![p] = [me EXCEPT !.viewEx = TRUE,
                        !.view = IF exists THEN plan ELSE me.snap, !.banner = FALSE]], p)
    /\ UNCHANGED <<used, removed>>

\* dismiss_deleted: "Leave" navigates away when there is no plan.
Dismiss(p) ==
    /\ CanAct(p) /\ pg[p].banner
    /\ pg' = [pg EXCEPT ![p] = IF pg[p].viewEx THEN [pg[p] EXCEPT !.banner = FALSE]
                               ELSE ClosedPage]
    /\ UNCHANGED <<exists, plan, used, removed, writes, bad>>

\* handle_info({:floor_plan_changed, by}) -> apply_remote_change/2.
\* deleted_in_use/3 adds the plan banner, with the page's old @floors as
\* its snapshot, when the page had a plan and now has none.
Notice(p) ==
    LET me == pg[p]
        lost == me.viewEx /\ ~exists
        geometryChanged == me.viewEx # exists \/ me.view # plan
    IN /\ me.state = "open" /\ me.pending
       /\ pg' = [pg EXCEPT ![p] = [me EXCEPT
              !.pending = FALSE, !.viewEx = exists, !.view = plan,
              !.banner = IF lost THEN TRUE
                         ELSE me.banner /\ (~exists \/ ~DeletionsFilterStillDeleted),
              !.snap = IF lost THEN me.view ELSE me.snap,
              !.undo = IF HistoryDropsOnRemoteChange /\ geometryChanged THEN <<>> ELSE me.undo,
              !.redo = IF HistoryDropsOnRemoteChange /\ geometryChanged THEN <<>> ELSE me.redo,
              !.confirm = me.confirm /\ ~(RemoteDeleteClosesConfirm /\ ~exists)]]
       /\ UNCHANGED <<exists, plan, used, removed, writes, bad>>

-----------------------------------------------------------------------------
Next ==
    \/ \E p \in Pages :
        \/ Open(p) \/ Close(p) \/ Undo(p) \/ Redo(p) \/ OpenConfirm(p)
        \/ CancelConfirm(p) \/ ConfirmDelete(p) \/ Restore(p) \/ Dismiss(p)
        \/ Notice(p)
        \/ \E e \in Elems : Draw(p, e) \/ Erase(p, e)

Spec == Init /\ [][Next]_vars

Symmetry == Permutations(Pages) \cup Permutations(Elems)

StateBound == writes <= MaxWrites

-----------------------------------------------------------------------------
(* Rules. Each is checked by scripts/check-floor-plan-session.             *)

TypeOK ==
    /\ exists \in BOOLEAN /\ plan \subseteq Elems /\ used \subseteq Elems
    /\ (~exists => plan = {})

\* Undo and redo never take back a change someone else made.
UndoKeepsOthersChanges == ~bad.undoRevertsOther

\* Restore after someone deletes the plan brings back everything the
\* delete removed.
RestoreBringsBackAll == ~bad.restoreIncomplete

\* The delete-plan confirm shows only while the page shows a plan.
ConfirmOnlyWithPlan == \A p \in Pages : pg[p].state = "open" /\ pg[p].confirm => pg[p].viewEx

\* Once a page has caught up, it shows the "deleted the floor plan" banner
\* exactly when the plan is gone.
BannerMatchesPlan ==
    \A p \in Pages : pg[p].state = "open" /\ ~pg[p].pending => (pg[p].banner <=> ~exists)
=============================================================================
