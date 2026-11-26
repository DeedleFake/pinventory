-------------------------- MODULE PasskeyCeremony --------------------------
(***************************************************************************)
(* One browser tab running a passkey ceremony against one Pinventory      *)
(* LiveView, and the one-time login token that turns a passkey sign-in     *)
(* into a session.                                                         *)
(*                                                                         *)
(* Kind picks the page:                                                    *)
(*   "login":    UserLive.Login, signed out, any passkey                   *)
(*   "reauth":   UserLive.Login while signed in (sudo reauth), bound to    *)
(*               the session user                                          *)
(*   "register": UserLive.Settings, adding a passkey in sudo mode          *)
(*                                                                         *)
(* The LiveView holds one ceremony (@passkey_ceremony) and handles one     *)
(* event at a time. Events from the browser and replies from the server    *)
(* travel in order on the socket, but each side can send before the other  *)
(* side's last message arrives. A challenge is a number; an assertion      *)
(* passes Wax only for the challenge it was signed for.                    *)
(*                                                                         *)
(* The boolean constants are code facts that scripts/check-passkey-        *)
(* ceremony reads from the code.                                           *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Kind,         \* "login", "reauth", or "register"
    Me, Other,    \* the session user (reauth, register), and another user
    MaxC,         \* challenges issued at most
    MaxMsgs,      \* messages in flight each way, at most
    \* passkey_start / passkey_register does nothing while a ceremony is
    \* pending. FALSE: it replaces the pending ceremony.
    StartIgnoredWhilePending,
    \* The handler clears @passkey_ceremony before checking the response,
    \* so every attempt, failed or not, uses the ceremony up.
    ConsumesCeremony,
    \* passkey_cancel clears @passkey_ceremony.
    CancelClears,
    \* A reauth ceremony allows only the session user's passkeys:
    \* begin_passkey_authentication(user: ...) and the bound_user_id check.
    ReauthBindsUser,
    \* create_from_passkey refuses a token for a user other than the
    \* session user.
    ControllerChecksSessionUser,
    \* consume_passkey_login_token deletes the row and needs it to be the
    \* one delete, so a token works once.
    TokenOneTime,
    \* The token hash covers the browser's :passkey_binding, and the
    \* controller passes the posting browser's binding.
    TokenBound,
    \* passkey_register checks sudo before it starts a ceremony.
    SudoAtStart,
    \* passkey_attestation checks sudo before it stores the passkey.
    SudoAtFinish

Users == {Me, Other}
None == "none"

VARIABLES
    slot,      \* @passkey_ceremony: 0 for nil, else its challenge
    issued,    \* challenges issued so far
    up,        \* events in flight from browser to LiveView
    down,      \* replies in flight from LiveView to browser
    enabled,   \* the passkey button as the browser last rendered it
    prompt,    \* the browser's open passkey prompt: 0 or its challenge
    sent,      \* responses the browser has sent, for Resend
    sudo,      \* the session is in sudo mode now
    gone,      \* the page left (sudo redirect)
    tokens,    \* minted login tokens: [user, used]
    session,   \* who this browser is signed in as
    stored,    \* register: passkeys stored
    accepted,  \* ghost: challenges whose response was accepted
    bad        \* ghost: which rules a step broke

vars == <<slot, issued, up, down, enabled, prompt, sent, sudo, gone, tokens,
          session, stored, accepted, bad>>

NoBad == [reused |-> FALSE, wrongUser |-> FALSE, tokenReused |-> FALSE,
          tokenForeign |-> FALSE, noSudo |-> FALSE, refused |-> FALSE,
          replayed |-> FALSE]

Init ==
    /\ slot = 0 /\ issued = 0 /\ up = <<>> /\ down = <<>>
    /\ enabled = TRUE /\ prompt = 0 /\ sent = {}
    /\ sudo = (Kind = "register")
    /\ gone = FALSE /\ tokens = <<>>
    /\ session = IF Kind = "login" THEN None ELSE Me
    /\ stored = 0 /\ accepted = {} /\ bad = NoBad

\* Passkeys that may answer this ceremony.
Allowed(signer) == IF Kind = "reauth" /\ ReauthBindsUser THEN signer = Me ELSE TRUE
\* Passkeys the user means to succeed with.
Rightful(signer) == IF Kind = "login" THEN TRUE ELSE signer = Me

Reply(newSlot, push) == down' = Append(down, [disabled |-> newSlot # 0, push |-> push])

-----------------------------------------------------------------------------
(* Browser                                                                 *)

\* A click on the enabled button. The button is disabled={@passkey_ceremony
\* != nil}, but a second click can land before the reply that disables it.
Click ==
    /\ ~gone /\ enabled /\ Len(up) < MaxMsgs
    /\ up' = Append(up, [t |-> "start"])
    /\ UNCHANGED <<slot, issued, down, enabled, prompt, sent, sudo, gone, tokens,
                   session, stored, accepted, bad>>

\* The browser applies a reply. passkey.js runs navigator.credentials for a
\* pushed ceremony. The browser rejects a second request while one is open
\* (NotAllowedError), and the hook sends passkey_cancel.
Receive ==
    /\ down # <<>> /\ ~gone
    /\ LET m == Head(down) IN
       /\ enabled' = ~m.disabled
       /\ IF m.push = 0 THEN UNCHANGED <<prompt, up>>
          ELSE IF prompt # 0 THEN
               /\ Len(up) < MaxMsgs /\ up' = Append(up, [t |-> "cancel"])
               /\ UNCHANGED prompt
          ELSE /\ prompt' = m.push /\ UNCHANGED up
    /\ down' = Tail(down)
    /\ UNCHANGED <<slot, issued, sent, sudo, gone, tokens, session, stored, accepted, bad>>

\* The user completes the prompt with a passkey: passkey_assertion, or
\* passkey_attestation on the register page.
Complete(signer) ==
    /\ prompt # 0 /\ ~gone /\ Len(up) < MaxMsgs
    /\ Kind = "register" => signer = Me
    /\ LET r == [t |-> "response", c |-> prompt, signer |-> signer, resend |-> FALSE] IN
       /\ up' = Append(up, r) /\ sent' = sent \cup {r}
    /\ prompt' = 0
    /\ UNCHANGED <<slot, issued, down, enabled, sudo, gone, tokens, session, stored, accepted, bad>>

\* The user dismisses the prompt, or it times out: passkey_cancel.
Dismiss ==
    /\ prompt # 0 /\ ~gone /\ Len(up) < MaxMsgs
    /\ up' = Append(up, [t |-> "cancel"]) /\ prompt' = 0
    /\ UNCHANGED <<slot, issued, down, enabled, sent, sudo, gone, tokens, session, stored, accepted, bad>>

\* The same response arrives again, for example a client retry. Synced
\* passkeys report sign count 0, which advance_sign_count/2 accepts every
\* time, so only the ceremony stops this.
Resend ==
    /\ ~gone /\ Len(up) < MaxMsgs /\ sent # {}
    /\ \E r \in sent : up' = Append(up, [r EXCEPT !.resend = TRUE])
    /\ UNCHANGED <<slot, issued, down, enabled, prompt, sent, sudo, gone, tokens,
                   session, stored, accepted, bad>>

\* Sudo mode ends: the 20 minutes pass, or the session token is deleted.
Expire ==
    /\ Kind # "login" /\ sudo
    /\ sudo' = FALSE
    /\ UNCHANGED <<slot, issued, up, down, enabled, prompt, sent, gone, tokens,
                   session, stored, accepted, bad>>

-----------------------------------------------------------------------------
(* LiveView                                                                *)

\* passkey_start (login, reauth) or passkey_register.
Start ==
    /\ up # <<>> /\ Head(up).t = "start" /\ ~gone /\ Len(down) < MaxMsgs
    /\ up' = Tail(up)
    /\ IF Kind = "register" /\ SudoAtStart /\ ~sudo THEN
          /\ gone' = TRUE   \* require_sudo_redirect
          /\ UNCHANGED <<slot, issued, down>>
       ELSE IF StartIgnoredWhilePending /\ slot # 0 THEN
          /\ Reply(slot, 0)
          /\ UNCHANGED <<slot, issued, gone>>
       ELSE
          /\ issued < MaxC
          /\ slot' = issued + 1 /\ issued' = issued + 1
          /\ Reply(issued + 1, issued + 1)
          /\ UNCHANGED gone
    /\ UNCHANGED <<enabled, prompt, sent, sudo, tokens, session, stored, accepted, bad>>

\* passkey_assertion, or passkey_attestation on the register page.
Respond ==
    /\ up # <<>> /\ Head(up).t = "response" /\ ~gone /\ Len(down) < MaxMsgs
    /\ LET r == Head(up)
           sudoFails == Kind = "register" /\ SudoAtFinish /\ ~sudo
           ok == ~sudoFails /\ slot = r.c /\ Allowed(r.signer)
           newSlot == IF ConsumesCeremony THEN 0 ELSE slot
       IN /\ up' = Tail(up)
          /\ slot' = newSlot
          /\ IF sudoFails THEN gone' = TRUE ELSE UNCHANGED gone
          /\ Reply(newSlot, 0)
          /\ IF ok THEN
                /\ accepted' = accepted \cup {r.c}
                /\ IF Kind = "register"
                   THEN /\ stored' = stored + 1 /\ UNCHANGED tokens
                   ELSE /\ tokens' = Append(tokens, [user |-> r.signer, used |-> FALSE])
                        /\ UNCHANGED stored
             ELSE UNCHANGED <<accepted, tokens, stored>>
          /\ bad' = [bad EXCEPT
                !.reused = @ \/ (ok /\ r.c \in accepted),
                !.noSudo = @ \/ (ok /\ Kind = "register" /\ ~sudo),
                \* the user completed the prompt with their own passkey,
                \* it arrived once, and it still failed. A resent response
                \* clears whatever ceremony is pending (the assign to nil runs
                \* before the check), so once one is handled the rule is moot:
                \* LiveView does not resend events, Resend is here for replay.
                !.refused = @ \/ (~ok /\ Rightful(r.signer) /\ ~sudoFails
                                   /\ ~r.resend /\ ~bad.replayed),
                !.replayed = @ \/ r.resend]
    /\ UNCHANGED <<issued, enabled, prompt, sent, sudo, session>>

\* passkey_cancel
Cancel ==
    /\ up # <<>> /\ Head(up).t = "cancel" /\ ~gone /\ Len(down) < MaxMsgs
    /\ up' = Tail(up)
    /\ slot' = IF CancelClears THEN 0 ELSE slot
    /\ Reply(slot', 0)
    /\ UNCHANGED <<issued, enabled, prompt, sent, sudo, gone, tokens, session, stored, accepted, bad>>

-----------------------------------------------------------------------------
(* The login token: phx-trigger-action posts it to UserSessionController   *)

\* consume_passkey_login_token/2, then create_from_passkey/2. from: this
\* browser, or another browser the token leaked to.
Post(i, from) ==
    /\ i \in 1..Len(tokens)
    /\ LET tk == tokens[i]
           works == (~tk.used \/ ~TokenOneTime) /\ (from = "this" \/ ~TokenBound)
           refusedUser == Kind = "reauth" /\ ControllerChecksSessionUser /\ tk.user # Me
       IN /\ tokens' = [tokens EXCEPT ![i].used = tk.used \/ works]
          /\ session' = IF works /\ ~refusedUser /\ from = "this" THEN tk.user ELSE session
          /\ bad' = [bad EXCEPT
                !.tokenReused = @ \/ (works /\ tk.used),
                !.tokenForeign = @ \/ (works /\ from # "this"),
                !.wrongUser = @ \/ (works /\ ~refusedUser /\ from = "this"
                                    /\ Kind = "reauth" /\ tk.user # Me)]
    /\ UNCHANGED <<slot, issued, up, down, enabled, prompt, sent, sudo, gone, stored, accepted>>

-----------------------------------------------------------------------------
Next ==
    \/ Click \/ Receive \/ Dismiss \/ Resend \/ Expire
    \/ \E s \in Users : Complete(s)
    \/ Start \/ Respond \/ Cancel
    \/ \E i \in 1..Len(tokens), from \in {"this", "elsewhere"} : Post(i, from)

Spec == Init /\ [][Next]_vars

StateBound == Len(tokens) <= 2

-----------------------------------------------------------------------------
(* Rules. Each is checked by scripts/check-passkey-ceremony.               *)

TypeOK ==
    /\ slot \in 0..MaxC /\ issued \in 0..MaxC /\ prompt \in 0..MaxC
    /\ session \in Users \cup {None}

\* A ceremony's challenge is accepted at most once.
CeremonyUsedOnce == ~bad.reused

\* A sudo reauth never signs the browser in as anyone but the session user.
ReauthStaysSessionUser == ~bad.wrongUser

\* A login token makes a session at most once.
TokenWorksOnce == ~bad.tokenReused

\* A login token works only from the browser that ran the passkey prompt.
TokenStaysInBrowser == ~bad.tokenForeign

\* A passkey is stored only while the session is in sudo mode.
PasskeyAddedOnlyInSudo == ~bad.noSudo

\* When the user completes the browser's prompt with their own passkey, it
\* works (unless sudo ran out on the register page).
CompletedPromptWorks == ~bad.refused

\* With nothing in flight and no prompt open, the button is usable and no
\* ceremony is held.
ButtonNeverStuck ==
    (~gone /\ up = <<>> /\ down = <<>> /\ prompt = 0) => (enabled /\ slot = 0)
=============================================================================
