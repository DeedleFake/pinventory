# Settings

Settings holds account, user invites, and the global activity feed. Opening it requires a recent login (sudo mode, 20 minutes).

## Sub-features

- `settings-account` shows email and password forms on `/user/settings`.
- `settings-users` lists users and pending invites on `/user/settings/users`.
- `settings-invite` mints a URL in `#latest-invite-url`.
- `settings-activity` lists recent edits on `/user/settings/activity`.
- `settings-activity-link` opens an item or location page from a card that still has a live row.

## How to get to it (user POV)

- Choose `Settings` in the header (`#nav-settings`).
- Open `/user/settings`, `/user/settings/users`, or `/user/settings/activity`.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded inside the last 20 minutes.
- For activity cards, at least one item or location change exists (run a save from [Items](./items.md) or [Locations](./locations.md) first).

- **Account tab.** Run `verify-pinventory browser goto /user/settings`. Wait for `#settings-page`. `#settings-tab-account` is visible. `#email_form` and `#password_form` are visible. If the heading is `Confirm your password`, sudo expired. Log in again, then retry.
- **Users tab.** Run `verify-pinventory browser click '#settings-tab-users'`. Wait for `#settings-users`. `#users-section` lists `verify@example.com`.
- **Invite.** Fill the invite email and generate. Run `verify-pinventory browser fill '#invite_email' 'guest@example.com'` and `verify-pinventory browser click '#generate-invite'`. Wait for `#latest-invite-url`. The text includes `/user/invite/`. Do not open that URL in this recipe unless proving invite registration on a second browser profile.
- **Activity.** Run `verify-pinventory browser click '#settings-tab-activity'`. Wait for `#settings-activity`. If edits exist, `#activity-edits` has cards. A live item edit is a link `a#activity-edit-<edit-id>`. A deleted-only edit is `article#activity-edit-<edit-id>`.
- **Follow a card.** Click a link card for an item. The destination is `#item-page` or `#location-page`.
- **Proof.** Run `verify-pinventory browser screenshot settings/activity.png` and `verify-pinventory browser html settings/activity.html` on the activity tab.

## Gotchas

- Sudo window is 20 minutes from `authenticated_at`. A long pause in Settings sends the browser to `/user/log-in` with heading `Confirm your password`. `#user_email` is disabled. Submit password only.
- Invite URLs are one-time. Copy from `#latest-invite-url`. The Mix task `mix pinventory.invite` is ops, not this UI.
- Activity cards prefer an item id when the edit has one. Location-only create/rename go to `/location/<id>`. Deleted item/location cards are not links.
- Do not use `/dev/mailbox` as proof that an invite was shared. The UI prints the URL. Swoosh local adapter is incidental.
