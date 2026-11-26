---
name: verify-passkey-ceremony
description: Model-check Pinventory's passkey ceremonies, passkey sign-in, sudo reauth with a passkey, and adding a passkey in settings, plus the one-time login token that turns a passkey sign-in into a session, using a TLA+ model whose guard settings are read from the code. Use when a change touches UserLive.Login or UserLive.Settings passkey_start, passkey_assertion, passkey_register, passkey_attestation, passkey_cancel, @passkey_ceremony, Accounts begin_passkey_authentication, finish_passkey_authentication, begin_passkey_registration, finish_passkey_registration, mint_passkey_login_token, consume_passkey_login_token, UserToken passkey_login_hash, UserSessionController.create_from_passkey, sudo?, or assets/js/hooks/passkey.js, or when running /verify-passkey-ceremony.
---

# Verify passkey ceremony

A TLA+ model checks that a passkey challenge is accepted at most once, a sudo reauth never switches the signed-in user, a login token works once and only in the browser it was minted for, a passkey is added only in sudo mode, the passkey button never stays stuck, and a passkey prompt the user completes is not refused. TLC, the TLA+ model checker, tries every order of the steps below within the bounds.

The LiveView holds one ceremony in `@passkey_ceremony` and handles one event at a time. The browser and the LiveView each send on the socket without waiting for the other side, so a second click can reach the server before the reply that disables the button reaches the browser. A passkey sign-in ends with a token: the LiveView mints it, the page posts it with `phx-trigger-action`, and `UserSessionController.create_from_passkey/2` turns it into a session.

## Run it

From the repo root:

```bash
./.cursor/skills/verify-passkey-ceremony/scripts/check-passkey-ceremony
```

It needs Java 11 or newer, `perl`, and `curl`. It shares `tla2tools.jar` 1.7.4 in `~/.cache/pinventory/` with `verify-save-conflicts`, and downloads and checks it the same way. A run takes about 10 seconds with `TLC_WORKERS=2`. Output and counterexamples go to `tmp/verify-passkey-ceremony/`.

To check one rule of one run alone, ignoring the known findings list:

```bash
./.cursor/skills/verify-passkey-ceremony/scripts/check-passkey-ceremony --only login:CeremonyUsedOnce
```

There are three runs, one per page:

- `login`: `UserLive.Login` signed out. Any user's passkey may answer.
- `reauth`: `UserLive.Login` while signed in, for sudo mode. Only the session user's passkeys should work.
- `register`: `UserLive.Settings` adding a passkey. The session starts in sudo mode and sudo can run out at any step.

## What it checks

| Rule | Runs | Plain meaning | Harm when broken |
|---|---|---|---|
| `CeremonyUsedOnce` | all | A challenge is accepted at most once, even if the same response arrives twice. | A captured or retried assertion signs in again or adds a passkey again. Synced passkeys report sign count 0, so `advance_sign_count/2` does not stop this. |
| `ReauthStaysSessionUser` | reauth | A sudo reauth never leaves the browser signed in as someone other than the session user. | Reauth on a shared machine swaps the session to another account. |
| `TokenWorksOnce` | login, reauth | A login token makes a session at most once. | A leaked or replayed token posts a second login. |
| `TokenStaysInBrowser` | login, reauth | A login token works only in the browser it was minted for. | A token copied from the page or logs signs in another browser. |
| `PasskeyAddedOnlyInSudo` | register | A passkey is stored only while the session is in sudo mode. | Someone at an unlocked session adds their own passkey to the account without the password. |
| `ButtonNeverStuck` | all | With nothing in flight and no prompt open, the button is enabled and no ceremony is held. | The passkey button stays disabled until reload. |
| `CompletedPromptWorks` | all | When the user completes the prompt with their own passkey, and it arrives once, it is accepted (unless sudo ran out on the register page). | "Passkey sign-in failed" or "Could not add passkey." after the user did everything right. |

## Read the result

- `PASS <run>: ...` lists every rule that held in every reachable state of that run.
- `FAIL <run>:<rule>` means a new break. Open the `.out` file it names. Its `State N:` lines are the steps.
- `KNOWN FINDING still present` is expected for the findings below. The check exits 0 when only those fail.
- `FIXED? <run>:<rule> now passes` means the model no longer finds that break. Confirm the fix with a test, then remove it from `KNOWN_FINDINGS` in the script and from Findings below. The check exits 1 until you do.
- `TOOL ERROR` means TLC did not finish. Read the `.out` file.

TLC stops at the first broken rule of a run. When a run fails, rerun the other rules of that run with `--only` to see whether they hold.

Read every result with the `/statechart` skill. It turns a violation into its shortest path in plain words. On a pass it draws how the ceremony moves between states.

## Real bug or modeling error

The script prints `code facts` first. Each is a model constant read from the code by a regex in the script. A regex that stops matching turns its fact FALSE. Page facts are read per run: `login` and `reauth` from `login.ex` (`passkey_start`, `passkey_assertion`), `register` from `settings.ex` (`passkey_register`, `passkey_attestation`).

| Constant | TRUE when the code has |
|---|---|
| `StartIgnoredWhilePending` | the start handler doing nothing while `@passkey_ceremony` is set. FALSE today: a second start replaces the pending ceremony |
| `ConsumesCeremony` | the response handler setting `@passkey_ceremony` to nil before its `with`, so every attempt uses the ceremony up |
| `CancelClears` | `passkey_cancel` setting `@passkey_ceremony` to nil |
| `ReauthBindsUser` | `passkey_start` passing `[user: current_scope.user]` when `reauth?`, and `finish_passkey_authentication/2` checking `is_nil(bound_user_id) or cred.user_id == bound_user_id` |
| `ControllerChecksSessionUser` | `create_from_passkey/2` calling `passkey_failed/1` when the token's user is not the session user |
| `TokenOneTime` | `consume_passkey_login_token/2` requiring `{1, _}` from the `Repo.delete_all` of the row |
| `TokenBound` | `UserToken.passkey_login_hash/2` hashing the browser binding into the token hash, and the controller passing `get_session(conn, :passkey_binding)` |
| `SudoAtStart` | `passkey_register` checking `sudo?(socket)` before it begins |
| `SudoAtFinish` | `passkey_attestation` starting its `with` on `true <- sudo?(socket) \|\| :sudo` |

`ReauthStaysSessionUser` has two guards, `ReauthBindsUser` and `ControllerChecksSessionUser`. Either one alone keeps it passing, so it fails only when both are gone. A FALSE on one of them is still a lost layer: read the change.

When a rule fails:

1. A fact flipped, and the change meant to remove or move that guard. If the guard is gone, the failure is real. If it moved or was renamed, update its regex and rerun.
2. A fact flipped by accident, for example after a reformat. Fix the regex.
3. No fact changed, but a rule fails. The change altered behavior that the model describes as fixed. Find the action in the table below, compare it with the code, and update the model to match the code. Never loosen a rule to make it pass.

Replay a counterexample against the real code before calling it a bug. `Pinventory.SoftAuthenticator` in `test/support` signs real assertions, so a LiveView test can send `render_hook(view, "passkey_start", %{})` twice and then answer the first challenge with `render_hook(view, "passkey_assertion", ...)`.

## Where the model comes from

A challenge is a number. An assertion passes `Wax` only for the challenge it was signed for. Users are `Me` (the session user on reauth and register) and `Other`.

| Model action | Code |
|---|---|
| `Click` | the passkey button, `phx-click` with `disabled={@passkey_ceremony != nil}`. A click can land before the reply that disables it |
| `Receive` | the browser applying a reply. `assets/js/hooks/passkey.js` runs `navigator.credentials.get` or `create` on `passkey:authenticate` or `passkey:register`. The browser rejects a second request while one is open, and the hook sends `passkey_cancel` |
| `Complete` | the user finishing the prompt: the hook sends `passkey_assertion` or `passkey_attestation` |
| `Dismiss` | the user closing the prompt or it timing out: the hook sends `passkey_cancel` |
| `Resend` | the same response arriving again, for a replay. LiveView does not resend events by itself |
| `Expire` | sudo mode ending (`sudo?/1` turns false after 20 minutes or when the session token goes) |
| `Start` | `handle_event("passkey_start")` with `Accounts.begin_passkey_authentication/1` (bound to the session user on reauth), or `handle_event("passkey_register")` with `sudo?/1`, `require_sudo_redirect/1`, `Accounts.begin_passkey_registration/1` |
| `Respond` | `handle_event("passkey_assertion")`: clear `@passkey_ceremony`, `Accounts.finish_passkey_authentication/2`, `Accounts.mint_passkey_login_token/2`. Or `handle_event("passkey_attestation")`: clear, `sudo?/1`, `Accounts.finish_passkey_registration/4` |
| `Cancel` | `handle_event("passkey_cancel")` |
| `Post` | `phx-trigger-action` posting the token to `UserSessionController.create_from_passkey/2`: `Accounts.consume_passkey_login_token/2`, which checks `UserToken.passkey_login_hash/2`, then the session user check and `UserAuth.log_in_user/3`. `from = "elsewhere"` is a leaked token posted by another browser |

Ghost variables exist only for checking: `accepted` is the challenges already accepted, and `bad` records which rule a step broke. `bad.replayed` notes that a resent response was handled. From then on `CompletedPromptWorks` is not judged, because the handler clears whatever ceremony is pending before it checks the response, so a stale resend uses up the current ceremony. That is fail-closed and needs a duplicate event, which LiveView does not send.

## Bounds and assumptions

- At most 2 challenges per run (`MaxC = 2`), at most 2 messages in flight each way (`MaxMsgs = 2`), at most 2 tokens (`StateBound`).
- One browser tab per run. Another browser appears only as the poster of a leaked token.
- Events and replies each arrive in order.
- `Wax` accepts exactly the right signature for the right challenge, and `advance_sign_count/2` is not modeled, as with a synced passkey (sign count 0).
- A reconnect makes a new LiveView with no ceremony, which is the same as a fresh start.

## Not covered

- The password login form, magic links, `UserAuth` sudo bookkeeping, session renewal, and remember-me cookies.
- `passkey_unsupported`, passkey revoke and rename, and the duplicate-passkey error.
- `Wire.assertion/1` and `Wire.attestation/1` decoding, `passkey_codec.js`, and the WebAuthn checks inside `Wax` (origin, RP ID, user verification).
- Timing: token and challenge expiry.
- Anything beyond the bounds above.

## Findings

Each finding is in `KNOWN_FINDINGS` in the script, as `run:rule`.

- `login:CompletedPromptWorks`, `reauth:CompletedPromptWorks`, `register:CompletedPromptWorks`. The user double-clicks the passkey button. Both `passkey_start` events reach the LiveView before the reply that disables the button. The second start replaces `@passkey_ceremony` with a new challenge. The browser opens the first prompt and rejects the second request, so the hook sends `passkey_cancel`, which clears the ceremony. The user completes the first prompt, and `passkey_assertion` finds no ceremony: "Passkey sign-in failed". Without the browser's rejection, the first prompt's assertion fails against the second challenge. Fails closed, so no security impact, but the user must press the button again. Since dd8083e (#14), on both pages. A scratch LiveView test confirmed the server side. That a fast double click sends two events is inferred from the `disabled` attribute being the only guard.

## Coverage

Sync commit: `f2154b6fd6e95309198b2a5aa338521208772306`

Move the sync commit forward only after you confirm, at the new commit, that the model and the code facts still describe the code below. The script lists covered files changed since the sync commit.

- `lib/pinventory_web/live/user_live/login.ex`: `handle_event/3` for `passkey_start`, `passkey_assertion`, `passkey_cancel`, the passkey button's `disabled` attribute in `render/1`
- `lib/pinventory_web/live/user_live/settings.ex`: `handle_event/3` for `passkey_register`, `passkey_attestation`, `passkey_cancel`, `sudo?/1`, `require_sudo_redirect/1`
- `lib/pinventory/accounts.ex`: `begin_passkey_authentication/1`, `finish_passkey_authentication/2`, `begin_passkey_registration/1`, `finish_passkey_registration/4`, `mint_passkey_login_token/2`, `consume_passkey_login_token/2`
- `lib/pinventory/accounts/user_token.ex`: `build_passkey_login_token/2`, `verify_passkey_login_token_query/2`, `passkey_login_hash/2`
- `lib/pinventory_web/controllers/user_session_controller.ex`: `create_from_passkey/2`
- `assets/js/hooks/passkey.js`: the `passkey:authenticate` and `passkey:register` handlers
