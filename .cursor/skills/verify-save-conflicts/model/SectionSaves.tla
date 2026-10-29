---------------------------- MODULE SectionSaves ----------------------------
(***************************************************************************)
(* Racing saves to one record on a Pinventory edit page.                   *)
(*                                                                         *)
(* One model, three configurations, one per page:                          *)
(*   item:       PinventoryWeb.EditItemLive and Items.update_item/4,       *)
(*               sections name, notes, stock                               *)
(*   location:   PinventoryWeb.LocationLive and Locations.update/2,        *)
(*               section name                                              *)
(*   convention: PinventoryWeb.NamingConventionLive and                    *)
(*               NamingConvention.save/3, section text                     *)
(*                                                                         *)
(* A section's value is abstract: 0 or 1. Typing a value and typing it     *)
(* back is enough to reach every case the save checks care about.          *)
(*                                                                         *)
(* Each save, delete, and MCP write is one SQLite transaction. The repo    *)
(* runs immediate transactions, so each is one atomic step here.           *)
(*                                                                         *)
(* The boolean and string constants are code facts that                    *)
(* scripts/check-save-conflicts reads from the code.                       *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, TLC

CONSTANTS
    Pages,           \* open edit-page sessions
    Sections,        \* the record's independently saved sections
    AgentSections,   \* sections an MCP tool edits from an earlier read
    AtomicSections,  \* sections an MCP tool reads and writes in one step
    Deletable,       \* the page can delete the record
    MaxWrites,       \* bound on committed writes, for a finite state space

    \* How a save decides it is stale. "value": the stored value of a
    \* section differs from the copy the page started from. "revision":
    \* any save landed since that copy. "none": no check.
    CheckMode,
    \* The check looks only at the sections this save edits.
    CheckOnlyEdited,
    \* The save writes only the sections it edits.
    WritesOnlyEdited,
    \* How reconcile decides a section changed: "value" or "revision".
    ReconcileMode,
    \* An edited section that changed keeps its draft and shows a warning.
    \* When FALSE it reloads over the draft.
    ReconcileKeepsDirty,
    \* Reconcile clears the warning on a section whose saved value is back
    \* to what the page started from.
    ReconcileClearsWarning,
    \* A stale save of a deleted record sends the page to the list. When
    \* FALSE the reload raises and the page crashes.
    StaleNilSafe,
    \* Deleting a record that is already gone returns an error. When FALSE
    \* the delete raises Ecto.StaleEntryError and the page crashes.
    DeleteToleratesMissing

Vals == {0, 1}

ASSUME /\ CheckMode \in {"value", "revision", "none"}
       /\ ReconcileMode \in {"value", "revision"}
       /\ AgentSections \subseteq Sections /\ AtomicSections \subseteq Sections

VARIABLES
    exists,  \* the record's row exists
    db,      \* saved value of each section
    rev,     \* number of committed saves (the convention's version number)
    page,    \* per page session state (socket assigns)
    agent,   \* the MCP tool's earlier read
    writes,  \* ghost: committed writes, to bound the state space
    bad      \* ghost: which properties some step has broken

vars == <<exists, db, rev, page, agent, writes, bad>>

NoWarn == [s \in Sections |-> FALSE]
Zero == [s \in Sections |-> 0]

\* base:   the saved copy the page's edits start from (socket.assigns.item,
\*         .location, or .base), with baseRev its version number
\* draft:  the form's values
\* warn:   sections showing the "someone else saved" warning
\* latest: the copy the last reconcile fetched (socket.assigns.latest or
\*         .stale), which "Keep my edits" and "Load their version" use
ClosedPage == [state |-> "closed", base |-> Zero, baseRev |-> 0, draft |-> Zero,
               warn |-> NoWarn, latest |-> Zero, latestRev |-> 0]

NoBad == [lostUpdate |-> FALSE, falseConflict |-> FALSE, draftDropped |-> FALSE,
          warning |-> FALSE]

Init ==
    /\ exists = TRUE
    /\ db \in [Sections -> Vals]
    /\ rev = 0
    /\ page = [p \in Pages |-> ClosedPage]
    /\ agent = [phase |-> "idle", snap |-> Zero, snapRev |-> 0]
    /\ writes = 0
    /\ bad = NoBad

Edited(base, draft) == {s \in Sections : draft[s] # base[s]}

\* The save's check, inside its transaction.
Stale(base, baseRev, edited) ==
    LET checked == IF CheckOnlyEdited THEN edited ELSE Sections
    IN \/ ~exists
       \/ CheckMode = "value" /\ \E s \in checked : db[s] # base[s]
       \/ CheckMode = "revision" /\ rev # baseRev

\* What a committed save stores.
Saved(base, draft, edited) ==
    LET written == IF WritesOnlyEdited THEN edited ELSE Sections
    IN [s \in Sections |-> IF s \in written THEN draft[s] ELSE db[s]]

\* The save overwrote a value its writer never saw.
Overwrites(base, newDb) == \E s \in Sections : newDb[s] # db[s] /\ db[s] # base[s]

\* The save was refused although nothing it edits changed.
FalseConflict(base, edited) == exists /\ \A s \in edited : db[s] = base[s]

-----------------------------------------------------------------------------
(* Reconcile: the page brings itself up to the saved record, one section   *)
(* at a time. EditItemLive.reconcile/2, LocationLive.reconcile/2,          *)
(* NamingConventionLive.reconcile/2.                                       *)

Changed(pg, s) == IF ReconcileMode = "value" THEN db[s] # pg.base[s] ELSE rev # pg.baseRev
Dirty(pg, s) == pg.draft[s] # pg.base[s]
Keeps(pg, s) == Changed(pg, s) /\ Dirty(pg, s) /\ ReconcileKeepsDirty
Reloads(pg, s) == Changed(pg, s) /\ ~Keeps(pg, s)

Reconcile(pg) ==
    [pg EXCEPT
        !.base = [s \in Sections |-> IF Reloads(pg, s) THEN db[s] ELSE pg.base[s]],
        !.draft = [s \in Sections |-> IF Reloads(pg, s) THEN db[s] ELSE pg.draft[s]],
        !.warn = [s \in Sections |->
                    IF Keeps(pg, s) THEN TRUE
                    ELSE IF Reloads(pg, s) \/ ReconcileClearsWarning THEN FALSE
                    ELSE pg.warn[s]],
        !.baseRev = IF \E s \in Sections : Reloads(pg, s) THEN rev ELSE pg.baseRev,
        !.latest = db,
        !.latestRev = rev]

\* Reconcile replaced edits the user had not saved.
DropsDraft(pg) == \E s \in Sections : Reloads(pg, s) /\ Dirty(pg, s) /\ db[s] # pg.draft[s]

\* After reconcile, a section warns exactly when it has unsaved edits and
\* its saved value is no longer the one the page started from.
WarningsWrong(pg) ==
    LET r == Reconcile(pg)
    IN \E s \in Sections : r.warn[s] # (Dirty(r, s) /\ db[s] # r.base[s])

ReconcileBad(pg) ==
    [bad EXCEPT !.draftDropped = @ \/ DropsDraft(pg), !.warning = @ \/ WarningsWrong(pg)]

-----------------------------------------------------------------------------
(* Edit page                                                               *)

Open(p) ==
    /\ page[p].state = "closed" /\ exists
    /\ page' = [page EXCEPT ![p] = [ClosedPage EXCEPT !.state = "editing", !.base = db,
                   !.baseRev = rev, !.draft = db, !.latest = db, !.latestRev = rev]]
    /\ UNCHANGED <<exists, db, rev, agent, writes, bad>>

Close(p) ==
    /\ page[p].state = "editing"
    /\ page' = [page EXCEPT ![p] = ClosedPage]
    /\ UNCHANGED <<exists, db, rev, agent, writes, bad>>

Type(p, s, v) ==
    /\ page[p].state = "editing"
    /\ page' = [page EXCEPT ![p].draft[s] = v]
    /\ UNCHANGED <<exists, db, rev, agent, writes, bad>>

\* handle_event("save"). The Save button is disabled while a warning shows,
\* but the server does not check, so the model lets a client save anyway.
Save(p) ==
    LET pg == page[p]
        edited == Edited(pg.base, pg.draft)
        newDb == Saved(pg.base, pg.draft, edited)
    IN /\ pg.state = "editing"
       /\ edited # {}  \* else the save writes nothing and returns the base
       /\ IF ~Stale(pg.base, pg.baseRev, edited) THEN
             \* committed; the page shows the record as saved
             /\ db' = newDb
             /\ rev' = rev + 1
             /\ writes' = writes + 1
             /\ page' = [page EXCEPT ![p] = [ClosedPage EXCEPT !.state = "editing",
                            !.base = newDb, !.baseRev = rev + 1, !.draft = newDb,
                            !.latest = newDb, !.latestRev = rev + 1]]
             /\ bad' = [bad EXCEPT !.lostUpdate = @ \/ Overwrites(pg.base, newDb)]
             /\ UNCHANGED exists
          ELSE IF CheckMode = "none" /\ ~exists THEN
             \* Multi.update on a missing row raises Ecto.StaleEntryError
             /\ page' = [page EXCEPT ![p].state = "crashed"]
             /\ UNCHANGED <<exists, db, rev, writes, bad>>
          ELSE
             \* {:error, :stale}: refetch, then reconcile, or leave for the list
             /\ page' = [page EXCEPT ![p] =
                   IF exists THEN Reconcile(pg)
                   ELSE IF StaleNilSafe THEN ClosedPage
                   ELSE [ClosedPage EXCEPT !.state = "crashed"]]
             /\ bad' = IF exists
                       THEN [ReconcileBad(pg) EXCEPT
                               !.falseConflict = @ \/ FalseConflict(pg.base, edited)]
                       ELSE bad
             /\ UNCHANGED <<exists, db, rev, writes>>
       /\ UNCHANGED agent

\* handle_info for a Pinventory.LiveEdits notice. The notice carries no
\* data, so the page refetches. Notices can arrive at any time.
Notice(p) ==
    /\ page[p].state = "editing"
    /\ page' = [page EXCEPT ![p] = IF exists THEN Reconcile(page[p]) ELSE ClosedPage]
    /\ bad' = IF exists THEN ReconcileBad(page[p]) ELSE bad
    /\ UNCHANGED <<exists, db, rev, agent, writes>>

\* handle_event("keep_my_edits"): the fetched section becomes the base and
\* the draft stays.
KeepMyEdits(p, s) ==
    /\ page[p].state = "editing" /\ page[p].warn[s]
    /\ page' = [page EXCEPT ![p].base[s] = page[p].latest[s],
                            ![p].baseRev = page[p].latestRev, ![p].warn[s] = FALSE]
    /\ UNCHANGED <<exists, db, rev, agent, writes, bad>>

\* handle_event("load_latest"): the fetched section becomes base and draft.
LoadLatest(p, s) ==
    /\ page[p].state = "editing" /\ page[p].warn[s]
    /\ page' = [page EXCEPT ![p].base[s] = page[p].latest[s],
                            ![p].draft[s] = page[p].latest[s],
                            ![p].baseRev = page[p].latestRev, ![p].warn[s] = FALSE]
    /\ UNCHANGED <<exists, db, rev, agent, writes, bad>>

\* handle_event("confirm_delete"). Deletes compare nothing: deleting is
\* intended, not a lost update. A page whose record is already gone is the
\* delete-racing-delete case.
Delete(p) ==
    /\ Deletable /\ page[p].state = "editing"
    /\ IF exists THEN
          /\ exists' = FALSE
          /\ writes' = writes + 1
          /\ page' = [page EXCEPT ![p] = ClosedPage]
       ELSE
          /\ page' = [page EXCEPT ![p] =
                IF DeleteToleratesMissing THEN ClosedPage
                ELSE [ClosedPage EXCEPT !.state = "crashed"]]
          /\ UNCHANGED <<exists, writes>>
    /\ UNCHANGED <<db, rev, agent, bad>>

-----------------------------------------------------------------------------
(* MCP tools                                                               *)

\* rename_item, rename_location: get the record, then save in a later
\* transaction. edit_naming_convention: the version and text come from an
\* earlier get_naming_convention.
AgentRead ==
    /\ AgentSections # {} /\ agent.phase = "idle" /\ exists
    /\ agent' = [phase |-> "read", snap |-> db, snapRev |-> rev]
    /\ UNCHANGED <<exists, db, rev, page, writes, bad>>

AgentWrite(s, v) ==
    LET base == agent.snap
        draft == [base EXCEPT ![s] = v]
        edited == Edited(base, draft)
        newDb == Saved(base, draft, edited)
    IN /\ agent.phase = "read" /\ s \in AgentSections /\ v # base[s]
       /\ IF ~Stale(base, agent.snapRev, edited) THEN
             /\ db' = newDb /\ rev' = rev + 1 /\ writes' = writes + 1
             /\ bad' = [bad EXCEPT !.lostUpdate = @ \/ Overwrites(base, newDb)]
          ELSE
             /\ bad' = [bad EXCEPT !.falseConflict = @ \/ FalseConflict(base, edited)]
             /\ UNCHANGED <<db, rev, writes>>
       /\ agent' = [phase |-> "idle", snap |-> Zero, snapRev |-> 0]
       /\ UNCHANGED <<exists, page>>

\* change_stock, move_stock: read and write in one transaction. Their counts
\* are checked in StockEdits.tla.
AtomicWrite(s, v) ==
    /\ s \in AtomicSections /\ exists /\ v # db[s]
    /\ db' = [db EXCEPT ![s] = v] /\ rev' = rev + 1 /\ writes' = writes + 1
    /\ UNCHANGED <<exists, page, agent, bad>>

-----------------------------------------------------------------------------
Next ==
    \/ \E p \in Pages :
        \/ Open(p) \/ Close(p) \/ Save(p) \/ Notice(p) \/ Delete(p)
        \/ \E s \in Sections : \/ KeepMyEdits(p, s) \/ LoadLatest(p, s)
                               \/ \E v \in Vals : Type(p, s, v)
    \/ AgentRead
    \/ \E s \in Sections, v \in Vals : AgentWrite(s, v) \/ AtomicWrite(s, v)

Spec == Init /\ [][Next]_vars

Symmetry == Permutations(Pages)

StateBound == writes <= MaxWrites

-----------------------------------------------------------------------------
(* Properties. Each is checked by scripts/check-save-conflicts.            *)

TypeOK ==
    /\ exists \in BOOLEAN
    /\ db \in [Sections -> Vals]
    /\ rev \in Nat
    /\ page \in [Pages -> [state : {"closed", "editing", "crashed"},
                           base : [Sections -> Vals], baseRev : Nat,
                           draft : [Sections -> Vals], warn : [Sections -> BOOLEAN],
                           latest : [Sections -> Vals], latestRev : Nat]]

\* No save overwrites a saved value its writer never saw.
NoLostUpdate == ~bad.lostUpdate

\* A save is refused only when a section it edits changed, or the record is
\* gone. A quantity save goes through after a rename, and a change that was
\* undone before the save does not block it.
NoFalseConflict == ~bad.falseConflict

\* Someone else's save never replaces edits the user has not saved.
UnsavedEditsSurvive == ~bad.draftDropped

\* After a notice or a stale save, a section warns exactly when it has
\* unsaved edits and someone else's save changed it.
WarningsMatchSaved == ~bad.warning

\* No race crashes a page: not a stale save on a deleted record, and not
\* two people deleting the same record.
PagesNeverCrash == \A p \in Pages : page[p].state # "crashed"
=============================================================================
