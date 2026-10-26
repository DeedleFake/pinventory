----------------------------- MODULE StockEdits -----------------------------
(***************************************************************************)
(* Concurrent writes to one item's stock in Pinventory.                    *)
(*                                                                         *)
(* Actors: edit pages (PinventoryWeb.EditItemLive), the MCP agent tools    *)
(* (Items.change_stock/4, Items.move_stock/5), item delete                 *)
(* (Items.delete_item/2) and location delete (Locations.delete/2).         *)
(*                                                                         *)
(* Each action is one SQLite transaction. The repo runs immediate          *)
(* transactions (config/config.exs), so a transaction holds the write      *)
(* lock from its first read and is one atomic step here.                   *)
(*                                                                         *)
(* A stock map is a function Locs -> Int where 0 means no item_locations   *)
(* row, matching Items.stock_map/1 and normalize_desired_stock/1.          *)
(*                                                                         *)
(* The boolean constants are code facts. scripts/check-stock-edits derives *)
(* each one from the code, so a change that removes a guard flips its      *)
(* constant and the checker shows the consequence.                         *)
(***************************************************************************)
EXTENDS Integers, TLC

CONSTANTS
    Pages,      \* open edit-page sessions
    Locs,       \* locations
    Max,        \* stands for DraftStock.max_quantity() (1_000_000)
    MaxWrites,  \* bound on committed writes, for a finite state space

    \* Items.update_item/4 calls optimistic_lock(:lock_version).
    OptimisticLock,
    \* Items.update_item/4 calls force_change(:lock_version, ...), so a
    \* stock-only save still updates the item row and checks the version.
    ForceVersionBump,
    \* Items.write_stock/4 reads the item inside Repo.transact under
    \* immediate transactions, so change_stock/move_stock read and write
    \* in one step.
    AgentReadsInTx,
    \* changed_count/3 rejects a count below 0 with {:below_zero, current}.
    ChangeStockChecksBelowZero,
    \* changed_count/3 rejects a count above max_quantity with :too_many.
    ChangeStockChecksMax,
    \* moved_counts/4 rejects a move that pushes the target above max.
    MoveStockChecksMax,
    \* moved_counts/4 rejects moving more than the source holds.
    MoveStockChecksEnough,
    \* DraftStock.put/3 (used by the edit page's + and - buttons through
    \* DraftStock.adjust/3) caps a draft count at max_quantity.
    AdjustCapsAtMax,
    \* item_locations.quantity must be positive: ItemLocation.changeset/2
    \* validates it and the migration adds a CHECK constraint. TRUE when
    \* either guard is present.
    QuantityMustBePositive,
    \* Locations.delete/2 refuses when any item has stock there.
    LocationDeleteChecksStock,
    \* EditItemLive's {:error, :stale} branch reloads with Items.get_item!/1,
    \* which raises when the item is gone.
    StaleReloadRaises

ASSUME Max \in Nat /\ Max >= 1 /\ MaxWrites \in Nat

Zero == [l \in Locs |-> 0]

RECURSIVE SumOver(_, _)
SumOver(f, S) ==
    IF S = {} THEN 0
    ELSE LET l == CHOOSE x \in S : TRUE IN f[l] + SumOver(f, S \ {l})
Total(f) == SumOver(f, Locs)

VARIABLES
    itemExists,  \* the items row exists
    version,     \* items.lock_version
    stock,       \* item_locations quantities, 0 = no row
    locExists,   \* locations rows
    page,        \* per edit-page session state (socket assigns)
    agent,       \* MCP read snapshot, used only when ~AgentReadsInTx
    writes,      \* ghost: number of committed changes to the item
    bad          \* ghost: which properties some step has broken

vars == <<itemExists, version, stock, locExists, page, agent, writes, bad>>

ClosedPage == [state |-> "closed", base |-> 0, seen |-> 0, baseStock |-> Zero,
               draft |-> Zero, fields |-> FALSE,
               stale |-> FALSE, staleBase |-> 0, staleSeen |-> 0, staleStock |-> Zero]

NoBad == [lostUpdate |-> FALSE, pageOverMax |-> FALSE, agentOverMax |-> FALSE,
          moveTotal |-> FALSE, stockDiscarded |-> FALSE]

Init ==
    /\ itemExists = TRUE
    /\ version = 1
    /\ stock \in [Locs -> 0..Max]
    /\ locExists = [l \in Locs |-> TRUE]
    /\ page = [p \in Pages |-> ClosedPage]
    /\ agent = [phase |-> "idle", base |-> 0, seen |-> 0, snap |-> Zero]
    /\ writes = 0
    /\ bad = NoBad

(***************************************************************************)
(* The write half of Items.update_item/4, one Multi in one transaction.    *)
(*   issued: Multi.update sends an UPDATE for the items row. Ecto skips    *)
(*           the UPDATE when the changeset has no changes, so a            *)
(*           stock-only save issues it only with ForceVersionBump.         *)
(*   base:   lock_version of the copy the caller started from.             *)
(*   seen:   ghost writes count when the caller read that copy.            *)
(* Outcome is "ok", "stale" ({:error, :stale}) or "error" (any other       *)
(* error; the transaction rolls back).                                     *)
(***************************************************************************)
Outcome(newStock, issued, base) ==
    IF issued /\ ~itemExists THEN "stale"   \* UPDATE hits 0 rows
    ELSE IF ~itemExists THEN "error"        \* item_locations insert fails its FK
    ELSE IF OptimisticLock /\ issued /\ base # version THEN "stale"
    ELSE IF \E l \in Locs : newStock[l] > 0 /\ ~locExists[l] THEN "error"
                                            \* validate_locations_exist/3
    ELSE IF QuantityMustBePositive /\ \E l \in Locs : newStock[l] < 0 THEN "error"
                                            \* ItemLocation quantity > 0
    ELSE "ok"

OverMaxChange(newStock) == \E l \in Locs : newStock[l] # stock[l] /\ newStock[l] > Max

Commit(newStock, issued, seen) ==
    /\ stock' = newStock
    /\ version' = IF OptimisticLock /\ issued THEN version + 1 ELSE version
    /\ writes' = writes + 1
    /\ itemExists' = itemExists
    /\ locExists' = locExists

-----------------------------------------------------------------------------
(* Edit page: PinventoryWeb.EditItemLive                                   *)

\* load_item/2 then show_item/2: the page keeps the item it loaded.
Open(p) ==
    /\ page[p].state = "closed"
    /\ itemExists
    /\ page' = [page EXCEPT ![p] = [ClosedPage EXCEPT
                   !.state = "editing", !.base = version, !.seen = writes,
                   !.baseStock = stock, !.draft = stock]]
    /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

Close(p) ==
    /\ page[p].state = "editing"
    /\ page' = [page EXCEPT ![p] = ClosedPage]
    /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

\* handle_event("set_quantity"): DraftStock.parse_quantity/1 accepts 0..max.
Type(p, l, n) ==
    /\ page[p].state = "editing"
    /\ page' = [page EXCEPT ![p].draft[l] = n]
    /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

\* handle_event("adjust"): DraftStock.adjust/3 clamps at 0.
Adjust(p, l, d) ==
    LET raw == page[p].draft[l] + d
        lo == IF raw < 0 THEN 0 ELSE raw
        n == IF AdjustCapsAtMax /\ lo > Max THEN Max ELSE lo
    IN /\ page[p].state = "editing"
       /\ page' = [page EXCEPT ![p].draft[l] = n]
       /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

\* Typing a new name or notes.
EditFields(p) ==
    /\ page[p].state = "editing"
    /\ ~page[p].fields
    /\ page' = [page EXCEPT ![p].fields = TRUE]
    /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

\* handle_event("save") -> Items.update_item(scope, socket.assigns.item, ...)
Save(p) ==
    LET pg == page[p]
        newStock == pg.draft
        issued == pg.fields \/ ForceVersionBump
        out == Outcome(newStock, issued, pg.base)
    IN /\ pg.state = "editing"
       /\ (pg.fields \/ newStock # pg.baseStock)  \* else update_item returns {:ok, item} unwritten
       /\ \/ /\ out = "ok"
             /\ Commit(newStock, issued, pg.seen)
             /\ bad' = [bad EXCEPT !.lostUpdate = @ \/ pg.seen # writes,
                                   !.pageOverMax = @ \/ OverMaxChange(newStock)]
             \* show_item/2 with the saved item
             /\ page' = [page EXCEPT ![p] = [ClosedPage EXCEPT
                            !.state = "editing", !.base = version', !.seen = writes',
                            !.baseStock = newStock, !.draft = newStock]]
          \/ /\ out = "stale"
             /\ page' = [page EXCEPT ![p] =
                   IF ~itemExists /\ StaleReloadRaises
                   THEN [ClosedPage EXCEPT !.state = "crashed"]
                   ELSE [pg EXCEPT !.stale = TRUE, !.staleBase = version,
                                   !.staleSeen = writes, !.staleStock = stock]]
             /\ UNCHANGED <<itemExists, version, stock, locExists, writes, bad>>
          \/ /\ out = "error"
             /\ UNCHANGED <<itemExists, version, stock, locExists, page, writes, bad>>
       /\ UNCHANGED agent

\* handle_event("keep_my_edits"): the stale_item fetched at the stale error
\* becomes the baseline; the draft stays.
KeepMyEdits(p) ==
    /\ page[p].state = "editing" /\ page[p].stale
    /\ page' = [page EXCEPT ![p] = [@ EXCEPT !.stale = FALSE, !.base = page[p].staleBase,
                   !.seen = page[p].staleSeen, !.baseStock = page[p].staleStock]]
    /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

\* handle_event("load_latest"): show_item/2 with stale_item.
LoadLatest(p) ==
    /\ page[p].state = "editing" /\ page[p].stale
    /\ page' = [page EXCEPT ![p] = [ClosedPage EXCEPT
                   !.state = "editing", !.base = page[p].staleBase,
                   !.seen = page[p].staleSeen, !.baseStock = page[p].staleStock,
                   !.draft = page[p].staleStock]]
    /\ UNCHANGED <<itemExists, version, stock, locExists, agent, writes, bad>>

-----------------------------------------------------------------------------
(* MCP agent: Items.change_stock/4 and Items.move_stock/5 via write_stock/4 *)
(* write_stock/4 reads the item, computes counts, then calls               *)
(* update_item(scope, item, %{}, Map.merge(before, updates)).              *)

\* One agent write from snapshot (snap, base, seen). updates is the new
\* counts at the touched locations.
AgentWrite(snap, base, seen, touched, updates, isMove) ==
    LET newStock == [l \in Locs |-> IF l \in touched THEN updates[l] ELSE snap[l]]
        out == Outcome(newStock, ForceVersionBump, base)
    IN /\ itemExists /\ \A l \in touched : locExists[l]  \* fetch_item_for_stock, check_locations
       /\ newStock # snap                                  \* else update_item is a no-op
       /\ \/ /\ out = "ok"
             /\ Commit(newStock, ForceVersionBump, seen)
             /\ bad' = [bad EXCEPT !.lostUpdate = @ \/ seen # writes,
                                   !.agentOverMax = @ \/ OverMaxChange(newStock),
                                   !.moveTotal = @ \/ (isMove /\ Total(newStock) # Total(stock))]
          \/ /\ out # "ok"
             /\ UNCHANGED <<itemExists, version, stock, locExists, writes, bad>>
       /\ UNCHANGED page

\* The compute step returns {:ok, updates} or {:error, reason}.
Rejected == [ok |-> FALSE, counts |-> Zero]
Accepted(u) == [ok |-> TRUE, counts |-> u]

\* changed_count/3
ChangeCounts(snap, l, op, n) ==
    LET new == IF op = "add" THEN snap[l] + n ELSE n
    IN IF ChangeStockChecksBelowZero /\ new < 0 THEN Rejected
       ELSE IF ChangeStockChecksMax /\ new > Max THEN Rejected
       ELSE Accepted([x \in {l} |-> new])

\* moved_counts/4
MoveCounts(snap, f, t, q) ==
    IF MoveStockChecksEnough /\ q > snap[f] THEN Rejected
    ELSE IF MoveStockChecksMax /\ snap[t] + q > Max THEN Rejected
    ELSE Accepted([x \in {f, t} |-> IF x = f THEN snap[f] - q ELSE snap[t] + q])

Snap == IF AgentReadsInTx THEN [snap |-> stock, base |-> version, seen |-> writes]
        ELSE agent

AgentReady == IF AgentReadsInTx THEN agent.phase = "idle" ELSE agent.phase = "read"
AgentDone == agent' = [phase |-> "idle", base |-> 0, seen |-> 0, snap |-> Zero]

\* Only reachable when ~AgentReadsInTx: the read is its own transaction.
AgentRead ==
    /\ ~AgentReadsInTx /\ agent.phase = "idle" /\ itemExists
    /\ agent' = [phase |-> "read", base |-> version, seen |-> writes, snap |-> stock]
    /\ UNCHANGED <<itemExists, version, stock, locExists, page, writes, bad>>

ChangeStock(l, op, n) ==
    LET s == Snap
        u == ChangeCounts(s.snap, l, op, n)
    IN /\ AgentReady
       /\ u.ok
       /\ AgentWrite(s.snap, s.base, s.seen, {l}, u.counts, FALSE)
       /\ AgentDone

MoveStock(f, t, q) ==
    LET s == Snap
        u == MoveCounts(s.snap, f, t, q)
    IN /\ AgentReady /\ f # t
       /\ u.ok
       /\ AgentWrite(s.snap, s.base, s.seen, {f, t}, u.counts, TRUE)
       /\ AgentDone

-----------------------------------------------------------------------------
(* Deletes                                                                 *)

\* Items.delete_item/2: deletes regardless of lock_version; item_locations
\* cascade (on_delete: :delete_all).
DeleteItem ==
    /\ itemExists
    /\ itemExists' = FALSE
    /\ stock' = Zero
    /\ writes' = writes + 1
    /\ UNCHANGED <<version, locExists, page, agent, bad>>

\* Locations.delete/2: location_has_items?/2 runs in the same transaction.
DeleteLocation(l) ==
    /\ locExists[l]
    /\ ~LocationDeleteChecksStock \/ stock[l] = 0
    /\ locExists' = [locExists EXCEPT ![l] = FALSE]
    /\ stock' = [stock EXCEPT ![l] = 0]
    /\ bad' = [bad EXCEPT !.stockDiscarded = @ \/ stock[l] > 0]
    /\ writes' = IF stock[l] > 0 THEN writes + 1 ELSE writes
    /\ UNCHANGED <<itemExists, version, page, agent>>

-----------------------------------------------------------------------------
Next ==
    \/ \E p \in Pages :
        \/ Open(p) \/ Close(p) \/ EditFields(p) \/ Save(p)
        \/ KeepMyEdits(p) \/ LoadLatest(p)
        \/ \E l \in Locs : \/ \E n \in 0..Max : Type(p, l, n)
                           \/ \E d \in {-1, 1} : Adjust(p, l, d)
    \/ AgentRead
    \/ \E l \in Locs : \E n \in -(Max + 1)..(Max + 1) : ChangeStock(l, "add", n)
    \/ \E l \in Locs : \E n \in 0..(Max + 1) : ChangeStock(l, "set", n)
    \/ \E f, t \in Locs : \E q \in 1..(Max + 1) : MoveStock(f, t, q)
    \/ DeleteItem
    \/ \E l \in Locs : DeleteLocation(l)

Spec == Init /\ [][Next]_vars

\* Pages are interchangeable, and so are locations.
Symmetry == Permutations(Pages) \cup Permutations(Locs)

\* Bounds the state space: writes, and draft counts the + button can raise.
StateBound ==
    /\ writes <= MaxWrites
    /\ \A p \in Pages, l \in Locs : page[p].draft[l] <= Max + 1

-----------------------------------------------------------------------------
(* Properties. Each is checked on its own by scripts/check-stock-edits.    *)

TypeOK ==
    /\ itemExists \in BOOLEAN
    /\ version \in Nat
    /\ stock \in [Locs -> Int]
    /\ locExists \in [Locs -> BOOLEAN]
    /\ page \in [Pages -> [state : {"closed", "editing", "crashed"},
                           base : Nat, seen : Nat, baseStock : [Locs -> Int],
                           draft : [Locs -> Int], fields : BOOLEAN,
                           stale : BOOLEAN, staleBase : Nat, staleSeen : Nat,
                           staleStock : [Locs -> Int]]]

\* No save overwrites a change its writer never saw.
NoLostUpdate == ~bad.lostUpdate

\* No stored count is ever negative.
StockNeverNegative == \A l \in Locs : stock[l] >= 0

\* The agent tools never store a count above max_quantity.
AgentNeverStoresOverMax == ~bad.agentOverMax

\* An edit-page save never stores a count above max_quantity.
EditPageNeverStoresOverMax == ~bad.pageOverMax

\* move_stock never changes the item's total.
MoveKeepsTotal == ~bad.moveTotal

\* Deleting a location never throws stock away.
LocationDeleteKeepsStock == ~bad.stockDiscarded

\* A save that loses a race never crashes the edit page.
StaleSaveNeverCrashes == \A p \in Pages : page[p].state # "crashed"
=============================================================================
