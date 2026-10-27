# Settings

Settings holds account, agent API tokens, user invites, and the global activity feed. Opening it requires a recent login (sudo mode, 20 minutes).

## Sub-features

- `settings-account` shows email and password forms on `/user/settings`.
- `settings-passkeys` shows `#passkeys-section`, `#passkeys-empty`, and `#add-passkey-button` on Account. Presence only.
- `settings-agent-access` is the `Agent access` section on Account (`#agent-access-section`), with the MCP server URL and API tokens. See [Agent access](./agent-access.md).
- `settings-users` lists users and pending invites on `/user/settings/users`.
- `settings-invite` mints a URL in `#latest-invite-url` and shows flash `#flash-info` (`Invite created. Copy the link now`). `#copy-latest-invite` copies it and shows `Copied` (`data-state="copied"`) for 2 seconds. The pending invite shows in `#invites` with `#revoke-invite-<id>`. Revoke asks with a native confirm dialog, then flashes `Invite revoked.` and the row leaves `#invites`. `#invites-empty` (`No pending invites.`) is the empty state.
- `settings-invite-register` opens `/user/invite/<token>` after logout (`#invite_registration_form`, heading `Accept invite`) and creates the invited account.
- `settings-activity` lists recent edits on `/user/settings/activity`.
- `settings-activity-link` opens an item or location page from a card that still has a live row.

## How to get to it (user POV)

- Choose `Settings` in the header (`#nav-settings`).
- Open `/user/settings`, `/user/settings/users`, or `/user/settings/activity`.
- Open an invite URL from `#latest-invite-url` while logged out.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded inside the last 20 minutes.
- For activity cards, at least one item or location change exists (run a save from [Items](./items.md) or [Locations](./locations.md) first).

- **Account tab.** Run `verify-pinventory browser goto /user/settings`. Wait for `#settings-page`. `#settings-tab-account` is visible. `#email_form` and `#password_form` are visible. If the heading is `Confirm your password`, sudo expired. Log in again, then retry. `#passkeys-section` is visible. It shows `#passkeys-empty` (`No passkeys yet.`) or `This browser does not support passkeys.` Do not click `#add-passkey-button`.
- **Users tab.** Run `verify-pinventory browser click '#settings-tab-users'`. Wait for `#settings-users`. `#users-section` lists `verify@example.com`.
- **Invite.** Fill the invite email and generate. Run `verify-pinventory browser fill '#invite_email' 'guest@example.com'` and `verify-pinventory browser click '#generate-invite'`. Wait for `#latest-invite-url` and `#flash-info`. The value includes `/user/invite/`. Copy the path (`/user/invite/<token>`). The printed host may be `localhost` even when the instance is `127.0.0.1`; use an origin-relative `goto`.
- **Invite revoke.** Generate a second invite for `nobody@example.com`. Read its id with `verify-pinventory sqlite "select id from invites where email = 'nobody@example.com';"`. Dismiss `#flash-info`, then run `verify-pinventory browser click-confirm '#revoke-invite-<id>'`. Flash `Invite revoked.` `#invites-empty` reads `No pending invites.` if it was the only one. Sqlite `revoked_at` is set; the row is kept.
- **Invite accept.** Dismiss the toast first. Click `#flash-info`. It sits over the header and `Log out` times out under it. Click `a[aria-label="Log out"]`. Wait for `#login_form_password`. Run `verify-pinventory browser goto /user/invite/<token>`. Wait for `#invite_registration_form`. Heading is `Accept invite`. Fill `#user_email` with the invited address, `#user_password` and `#user_password_confirmation` (min 12). Click `#invite_registration_form button`. Wait for `#items-page`. Sqlite `users` includes the guest email.
- **Activity.** Run `verify-pinventory browser click '#settings-tab-activity'`. Wait for `#settings-activity`. If edits exist, `#activity-edits` has cards. A live item edit is a link `a#activity-edit-<edit-id>`. A deleted-only edit is `article#activity-edit-<edit-id>`.
- **Follow a card.** Click a link card for a live item or location. The destination is `#item-page` or `#location-page`.
- **Proof.** Run `verify-pinventory browser screenshot settings/activity.png` and `verify-pinventory browser html settings/activity.html` on the activity tab. For invite accept, also keep `settings/invite-accepted.png`.

## Gotchas

- Sudo window is 20 minutes from `authenticated_at`. A long pause in Settings sends the browser to `/user/log-in` with heading `Confirm your password`. `#user_email` is disabled. Submit password only.
- Invite URLs are one-time. Copy from `#latest-invite-url`. The Mix task `mix pinventory.invite` is ops, not this UI.
- The Users list marks the current account with a `You` badge. `#users-empty` stays in the DOM although a user is listed.
- Activity cards prefer an item id when the edit has one. Location-only create/rename go to `/location/<id>`. The `item.deleted` / `location.deleted` event groups are articles, not links. A create or stock card for an item that was deleted later can still be a link; following it lands on Items with flash `Item not found.` A created card for a deleted location is also a link and lands on `/locations` (its `Location not found.` flash shows only without a floor plan).
- The Generate flash is `#flash-info`, not `#flash-error`. It does not clear on its own within 15 s and blocks the `Log out` click. Dismiss whichever flash is present before logging out.
- Do not use `/dev/mailbox` as proof that an invite was shared. The UI prints the URL. Swoosh local adapter is incidental.
- `/user/settings/confirm-email/:token` is the email-change continuation. Do not drive it on the seeded `verify@example.com` account.
- The sudo reauth page offers `Confirm with a passkey` beside the password form. Use the password: fill `#user_password`, click `#login_form_password button` (`Confirm`). The browser lands on `/user/settings`. See [Log in](./log-in.md).
- A logged-in visit of `/user/invite/<token>` redirects to `/`. A used or expired token sends a logged-out browser to `/user/log-in` with flash `This invite is invalid or has expired.`
- Revoking a passkey signs out other sessions. Do not drive revoke. No authenticator means no passkey to revoke.
