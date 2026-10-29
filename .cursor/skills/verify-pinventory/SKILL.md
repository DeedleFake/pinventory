---
name: verify-pinventory
description: Drive the Pinventory Phoenix LiveView web UI in a real Chromium session, and its MCP endpoint with curl, against an isolated local server. Use when proving a Pinventory UI or MCP change, running /verify-pinventory, or checking login, items, the item naming convention, locations, floor plan, delete, settings, agent tokens and MCP tools, or install, offline, and theme behavior as a user would.
---

# Verify Pinventory

Pinventory is a private household inventory app. The user-facing surface is a Phoenix LiveView browser UI. AI agents also use it through an MCP endpoint at `/mcp`, authenticated with an API token the user makes in Settings. Drive that with curl; see [Agent access](./features/agent-access.md). Ops Mix tasks exist (`mix pinventory.user`, `mix pinventory.invite`) but they are not the product.

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

Pages must render styled. Doctor cannot see a missing stylesheet, so open one screenshot after launch. If it is unstyled, `mix assets.setup` could not download the Tailwind binary. Copy `tailwind-linux-x64-4.3.3` into `_build/` and relaunch.

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

It reads the ports from `state.json`, so it checks whatever `--port` / `--cdp-port` launch used. The list below shows the defaults. It must print `ok` for all of:

- `mix phx.server` PID still alive
- Chromium PID still alive
- `GET http://127.0.0.1:4010/user/log-in` → 200
- CDP `GET http://127.0.0.1:5010/json/version` → 200
- SQLite file exists and contains `verify@example.com` (needs the `sqlite3` CLI on PATH)
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

Floor-plan drawing needs positioned clicks. `click` hits the element center and does not draw a wall.

```bash
$H browser click '#tool-wall'
$H browser click-at '#floor-plan-canvas [data-floor-plan-svg]' 150 220
$H browser click-at '#floor-plan-canvas [data-floor-plan-svg]' 480 220
$H browser wait-attached '[data-wall-id]'
$H browser click '#tool-gap'
$H browser click-box '[data-wall-id]' 0.3 0.5
$H browser click-box '[data-wall-id]' 0.7 0.5
$H browser hover '#location-<id>'
```

Set `PINVENTORY_TAB=<n>` on any `browser` command to run it in tab `n` (default 1). The harness opens missing tabs and brings the tab to the front, since a background tab cannot take a screenshot. Tabs share the login, so two tabs act as two people on the same page.

```bash
PINVENTORY_TAB=2 $H browser goto /locations/floor-plan
```

`browser login` opens `/user/log-in`, fills `#user_email` / `#user_password`, submits `#login_form_password`, and waits for `#items-page`.

`goto` paths are origin-relative (`/locations`, `/item`, `/user/settings`). After LiveView clicks, `wait` the destination root id. Do not sleep a fixed number of seconds except for documented debounce (name/filter `phx-debounce="300"`). After those fills, wait 400ms by running `browser wait-enabled` or `browser wait` on the result.

`click-at <selector> <x> <y>` clicks CSS pixels from the element's top-left. Prefer `#floor-plan-canvas [data-floor-plan-svg]` and keep y below the Reset view overlay. `click-box <selector> <fx> <fy>` clicks a 0–1 fraction of the bounding box (use this for existing wall/impassable geometry). `wait-attached` is for SVG nodes such as `[data-wall-id]`; Playwright treats a transparent stroke as not visible. `enabled` prints `enabled` or `disabled` (boolean `attr disabled`/`checked` is ambiguous). `click-confirm` clicks, accepts the native confirm dialog that `data-confirm` buttons open, and prints its text. It fails if no dialog appears within 5s. Plain `click` dismisses such a dialog, so the action never happens. `hover` leaves the pointer there so a following `attr class` can see `.is-list-hover`. Flash toasts sit over the header and intercept clicks (the Log out link included); dismiss them first by clicking `#flash-info` / `#flash-error`. `value` prints an input's or textarea's current value; `text` on a textarea prints blank. `scroll <selector> [top]` sets the element's `scrollTop` when given a number, waits 200ms for scroll handlers, and prints `scrollTop=<n> max=<n>`. `exists` counts DOM nodes, hidden ones too (`#polygon-finish` exists while it has the `hidden` class). `click-at` coordinates must stay inside the target's box. Check it with `browser box '#floor-plan-canvas'`.

Stable handles:

| Surface | Handle |
|---|---|
| Login form | `#login_form_password`, `#user_email`, `#user_password`, `#user_remember_me` |
| Passkey login | `#passkey-login`, `#passkey-login-button`, `#passkey_login_form` |
| First-account register | `#registration_form` (only when `users` is empty; launch seeds a user, so this path is closed) |
| Invite accept | `#invite_registration_form` on `/user/invite/<token>` |
| Header | `#nav-items`, `#nav-locations`, `#nav-settings`, `#app-nav`, `a[aria-label="Log out"]` |
| Items list | `#items-page`, `#new-item`, `#naming-convention`, `#items-empty`, `#items-filter-form`, `#q`, `#location`, `#items-<item-id>` |
| Item editor | `#item-page`, `#item_name`, `#item-save`, `#item-stock-form`, `#quantity-<location-id>`, `#quantity-inc-<location-id>`, `#item-delete` |
| Item stale save | `#item-stale-warning`, `#item-stale-their-edit`, `#item-stale-notes`, `#item-stale-keep`, `#item-stale-load` |
| Item notes | `#item-notes-section`, `#item_notes`, `#item-notes-hint`, `#note-edited-menu`, `#note-history` |
| Item naming convention panel | `#item-naming-convention` (a `<details>`; click its `summary`), `#item-naming-convention-body`, `#item-naming-convention-edit` |
| Naming convention editor (`/items/naming-convention`) | `#convention-page`, `#convention-last-edit`, `#convention-hint`, `#convention-text`, `#convention-save`, `#convention-format`, `#convention-format-status`, `#convention-tool-<bold\|italic\|strike\|heading\|bullet\|number\|quote\|code\|link>`, `#convention-preview`, `#convention-preview-body`, `#convention-history-open`, `#convention-history`, `#convention-history-version-<n>`, `#convention-history-restore`, `#convention-view-inline`, `#convention-view-split`, `#convention-stale-warning`, `#convention-stale-keep`, `#convention-stale-load` |
| Locations list | `#locations-page`, `#location-new-form`, `#location-new_name`, `#location-add-button`, `#location-<location-id>` |
| Locations browse (plan on) | `#locations-workspace`, `#locations-floor-canvas`, `#locations-floor-rail`, `#floor-plan-edit` |
| Location editor | `#location-page`, `#location_name`, `#location-save`, `#location-delete`, `#location-item-<item-id>` |
| Floor plan editor | `#floor-plan-page`, `#floor-plan-add`, `#floor-plan-sidebar`, `#floor-plan-canvas`, `#floor-rail`, `#tool-wall`, `#tool-gap`, `#tool-erase`, `#tool-impassable`, `#tool-impassable-erase`, `#polygon-finish`, `#history-undo`, `#history-redo`, `#floor-plan-delete` |
| Delete modals | `#item-delete-modal`, `#item-delete-confirm`, `#item-delete-confirm-submit`, `#location-delete-modal`, `#location-delete-confirm`, `#location-delete-confirm-submit` |
| Flash | `#flash-info`, `#flash-error` |
| Settings | `#settings-page`, `#settings-tab-account`, `#settings-tab-users`, `#settings-tab-activity`, `#generate-invite-form`, `#invite_email`, `#generate-invite`, `#latest-invite-url`, `#invites`, `#revoke-invite-<invite-id>` |
| Agent access | `#agent-access-section`, `#mcp-url`, `#copy-mcp-url`, `#api_token_name`, `#create-api-token`, `#latest-api-token-value`, `#api-tokens`, `#api-token-<token-id>`, `#replace-api-token-<token-id>`, `#revoke-api-token-<token-id>`, `#revoke-all-api-tokens`, `#show-inactive-api-tokens`, `#api-tokens-empty` |
| MCP | `POST /mcp` with `Authorization: Bearer <token>` and `accept: application/json, text/event-stream` |
| Theme toggle | `button[aria-label="System theme"]`, `button[aria-label="Light theme"]`, `button[aria-label="Dark theme"]` (no ids), `meta[data-theme-color=light]`, `meta[data-theme-color=dark]` |
| PWA | `link[rel=manifest]`, `/manifest.webmanifest`, `/sw.js`, `/offline.html`, `#offline-page` |
| Settings passkeys | `#passkeys-section`, `#passkeys`, `#passkeys-empty`, `#add-passkey-button` |

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

For MCP, the curl reply stands in for the screenshot. The second view is the sqlite row or the UI page the change shows on.

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

```bash
./.cursor/skills/verify-pinventory/scripts/verify-pinventory launch
./.cursor/skills/verify-pinventory/scripts/verify-pinventory doctor
./.cursor/skills/verify-pinventory/scripts/verify-pinventory browser login
./.cursor/skills/verify-pinventory/scripts/verify-pinventory browser click-at '#floor-plan-canvas [data-floor-plan-svg]' 150 220
./.cursor/skills/verify-pinventory/scripts/verify-pinventory browser click-confirm '#revoke-api-token-<token-id>'
./.cursor/skills/verify-pinventory/scripts/verify-pinventory browser value '#convention-text'
./.cursor/skills/verify-pinventory/scripts/verify-pinventory browser scroll '#convention-text' 800
./.cursor/skills/verify-pinventory/scripts/verify-pinventory cleanup
```

It wraps `verify-pinventory.mjs`. `npm install --omit=dev` runs automatically when `scripts/node_modules/playwright-core` is missing. `./.cursor/skills/verify-pinventory/scripts/verify-pinventory` with no args prints the command list.

One-off PWA proof (installability, service worker control, cache contents, offline fallback), which `browser` commands cannot do because each command reconnects over CDP and drops offline mode:

```bash
node ./.cursor/skills/verify-pinventory/scripts/pwa-check.mjs
```

It reads `tmp/verify-pinventory/run/state.json`, prints `ok` or `fail` per check, and exits 1 on any failure. It imports `playwright-core` from `scripts/node_modules/`, so run `verify-pinventory` once first if that directory is missing. Run it against a launched instance after `doctor`. See [PWA](./features/pwa.md).

The harness has no select-option, current-URL, or JS-eval command. For the items location filter use `goto '/?location=<location-id>&q=<text>'`.

Chromium binary order: `PINVENTORY_CHROME`, then `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome`, then `/usr/bin/chromium`, `/usr/bin/google-chrome`, `/usr/bin/google-chrome-stable`.

State file: `tmp/verify-pinventory/run/state.json` (PID, URL, DB path, seeded password). Scratch. Not evidence.
