# Pinventory verification map

This directory is the maintained source for verifying Pinventory's user-facing LiveView UI. Read this index, then the matching feature file.

## Baseline preconditions

- Launch with `./.cursor/skills/verify-pinventory/scripts/verify-pinventory launch`.
- Doctor must pass. URL is `http://127.0.0.1:4010`. Database is `tmp/verify-pinventory/run/pinventory.db`.
- Seeded account is `verify@example.com` / `verify-pass-12`.
- Inventory starts empty (no items, no locations).
- Run `browser login` before any authenticated recipe.
- Never drive `:4000` or `priv/repo/pinventory_dev.db`.
- Never drive an instance this run did not start.

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise.
- Prefer the DOM ids in the skill Drive table. Floor-plan drawing is the exception: use `click-at` / `click-box`, not a center `click`.
- Treat harness commands as literal.
- After a mutating click, wait for the destination root (`#items-page`, `#item-page`, `#locations-page`, `#location-page`, `#settings-page`) or a flash.
- Name and filter inputs debounce at 300ms. Wait for `#item-save` / `#location-save` to enable, or for the list to update. Do not assert on the draft value alone.
- Restore nothing on the server; launch already used a disposable database. Keep proof artifacts.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen.
- UI proof is a screenshot plus an HTML dump under `tmp/verify-pinventory/artifacts/`.
- Mutation proof includes a list reopen or a `sqlite` read of the same row.
- Record the feature file and entry point with every artifact path.
- An unreachable path is only proven unreachable with the command you ran and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 and one paragraph. Then exactly four H2 sections in this order:

1. `Sub-features`
2. `How to get to it (user POV)`
3. `Driving it with verify-pinventory`
4. `Gotchas`

## Features

- [Log in](./log-in.md) covers password login, closed registration, and failed credentials.
- [Items](./items.md) covers list, create, stock, filter, and persistence.
- [Locations](./locations.md) covers add, open, rename, and the per-location item list.
- [Floor plan](./floor-plan.md) covers optional multi-floor walls, gaps, impassable areas, pins, list badges, and delete-plan.
- [Delete](./delete.md) covers type-the-name item delete and empty-only location delete.
- [Settings](./settings.md) covers sudo settings tabs, invite minting, invite accept, and the activity feed.
