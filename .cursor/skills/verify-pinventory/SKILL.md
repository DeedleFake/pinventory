---
name: verify-pinventory
description: Drive the Pinventory Phoenix LiveView web UI in a real Chromium session against an isolated local server. Use when proving a Pinventory UI change, running /verify-pinventory, or checking login, items, locations, delete, or settings as a user would.
---

# Verify Pinventory

Pinventory is a private household inventory app. The user-facing surface is a Phoenix LiveView browser UI. Ops Mix tasks exist (`mix pinventory.user`, `mix pinventory.invite`) but they are not the product.

This skill is for the next agent. Read `features/README.md`, then the matching feature file. Drive only an instance this skill launched.

`mix test` is the Elixir unit harness. It does not replace this skill.

Harness path, from the repo root:

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory <command>
```

First run installs `playwright-core` into `scripts/node_modules/` if it is missing.

## Launch

Default bind is `127.0.0.1:4010` with SQLite at `tmp/verify-pinventory/run/pinventory.db`. That avoids the developer's `mix phx.server` on `:4000` and `priv/repo/pinventory_dev.db`.

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory launch
```

Ready when stdout includes `ok url=http://127.0.0.1:4010` and `GET /user/log-in` returns 200. The helper waits up to 120s for compile, assets, and Bandit.

What launch does:

1. Refuses if `:4010` is already taken, or if a healthy verification run already exists. Run `cleanup` first.
2. Creates a fresh SQLite file. Migrates it. Inserts `verify@example.com` / `verify-pass-12` (password min 12).
3. Starts `mix phx.server` with `PORT=4010` and `DATABASE_PATH` pointing at that file.
4. Starts headless Chromium with a CDP port on `5010`.

Never pass `PORT=4000`. Never point `DATABASE_PATH` at `priv/repo/pinventory_dev.db`.

Override only when 4010/5010 are busy:

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory launch --port 4011 --cdp-port 5011
```

Two verification instances can share `_build/dev`. Do not run two at once. Code reload and the asset watchers will fight.

Teardown is `cleanup` below. It kills the PIDs recorded in `tmp/verify-pinventory/run/state.json`, not processes by name.

## Doctor

Run before the first drive, after any failed drive, and whenever the UI looks wrong.

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory doctor
```

It must print `ok` for all of:

- `mix phx.server` PID still alive
- Chromium PID still alive
- `GET http://127.0.0.1:4010/user/log-in` → 200
- CDP `GET http://127.0.0.1:5010/json/version` → 200
- SQLite file exists and contains `verify@example.com`
- port 4010 is listening
- port is not 4000

Exit code 1 means stop driving. Read `tmp/verify-pinventory/run/server.log` and `browser.log`. Relaunch only after `cleanup`.

## Drive

Use the harness. CSS/ARIA ids below are from the LiveView templates.

```bash
H=./.cursor/skills/verify-pinventory/scripts/verify-pinventory
$H browser login
$H browser goto /
$H browser click '#new-item'
$H browser fill '#item_name' 'Verify Hammer'
$H browser wait-enabled '#item-save'
$H browser click '#item-save'
$H browser wait '#item-page'
$H browser screenshot items/after-save.png
$H browser html items/after-save.html
$H sqlite "select name from items;"
```

`browser login` opens `/user/log-in`, fills `#user_email` / `#user_password`, submits `#login_form_password`, and waits for `#items-page`.

`goto` paths are origin-relative (`/locations`, `/item`, `/user/settings`). After LiveView clicks, `wait` the destination root id. Do not sleep a fixed number of seconds except for documented debounce (name/filter `phx-debounce="300"`). After those fills, wait 400ms by running `browser wait-enabled` or `browser wait` on the result.

Stable handles:

| Surface | Handle |
|---|---|
| Login form | `#login_form_password`, `#user_email`, `#user_password`, `#user_remember_me` |
| First-account register | `#registration_form` (only when `users` is empty; launch seeds a user, so this path is closed) |
| Header | `#nav-items`, `#nav-locations`, `#nav-settings`, `#app-nav` |
| Items list | `#items-page`, `#new-item`, `#items-empty`, `#items-filter-form`, `#q`, `#location`, `#items-<item-id>` |
| Item editor | `#item-page`, `#item_name`, `#item-save`, `#item-stock-form`, `#quantity-<location-id>`, `#quantity-inc-<location-id>`, `#item-delete` |
| Locations list | `#locations-page`, `#location-new-form`, `#location-new_name`, `#location-add-button`, `#location-<location-id>` |
| Location editor | `#location-page`, `#location_name`, `#location-save`, `#location-delete`, `#location-item-<item-id>` |
| Delete modals | `#item-delete-modal`, `#item-delete-confirm`, `#item-delete-confirm-submit`, `#location-delete-modal`, `#location-delete-confirm`, `#location-delete-confirm-submit` |
| Flash | `#flash-info`, `#flash-error` |
| Settings | `#settings-page`, `#settings-tab-account`, `#settings-tab-users`, `#settings-tab-activity`, `#generate-invite-form` |

Stream ids:

- Items list row: `#items-<uuid>`
- Locations list row: `#location-<uuid>`
- Location page item row: `#location-item-<uuid>`

Look up uuids with `sqlite`.

`mix test` and LiveViewTest `render_click` are not a user path. Do not cite them as UI proof.

## Evidence

Put proof under `tmp/verify-pinventory/artifacts/` (gitignored via `/tmp/`). Relative screenshot/html paths are joined onto that directory.

A proof is incomplete unless it includes:

1. The action (command + selector).
2. The resulting UI (screenshot and HTML, with Pinventory chrome visible: heading plus `#app-nav` or `#login_form_password`).
3. A second view of the same fact. Re-open the row from the list, or `sqlite` the row.

`sqlite` talks to the isolated file, not `pinventory_dev.db`.

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory sqlite "select id, name from items;"
./.cursor/skills/verify-pinventory/scripts/verify-pinventory sqlite "select i.name, l.name, il.quantity from item_locations il join items i on i.id = il.item_id join locations l on l.id = il.location_id;"
```

Do not call context functions from IEx as proof. Do not hit `/dev/dashboard`. Mailbox at `/dev/mailbox` is only for invite email if a recipe says so; launch does not send mail.

## Cleanup

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory cleanup
```

Kills the recorded server process group and Chromium process group. Deletes `tmp/verify-pinventory/run/`. Leaves `tmp/verify-pinventory/artifacts/` in place.

After cleanup, confirm artifacts still exist before declaring the run done. A cleanup that removes proof has failed.

If a drive fails, run `cleanup` before the next `launch` so `:4010` and `:5010` are free.

## Helpers

Executable: `.cursor/skills/verify-pinventory/scripts/verify-pinventory`

It wraps `verify-pinventory.mjs`. `npm install --omit=dev` runs automatically when `scripts/node_modules/playwright-core` is missing.

Chromium binary order: `PINVENTORY_CHROME`, then `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome`, then `/usr/bin/chromium`.

State file: `tmp/verify-pinventory/run/state.json` (PID, URL, DB path, seeded password). Scratch. Not evidence.
