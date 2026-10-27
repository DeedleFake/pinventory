# Agent access

Agent access lets an AI agent act as a user. The user makes an API token under Settings, Account. The agent sends it as a Bearer token to the MCP endpoint at `/mcp`, where it can list locations and items, create and rename items, rename locations, change stock counts, and read and edit the item naming convention. Every change the agent makes shows in Activity as `<email> via <token name>`.

## Sub-features

- `agent-token-create` makes a token from `#api-token-form` (`#api_token_name`, `#create-api-token`). Flash `Token created. Copy it now. It will not be shown again.` The secret shows once in `#latest-api-token-value` (starts with `pinv_`) with `#copy-latest-api-token`. The name field clears.
- `agent-token-list` shows active tokens in `#api-tokens` as `#api-token-<id>` with created, expires, and `never used` or `last used` dates. `#api-tokens-empty` reads `No active tokens.`. `#show-inactive-api-tokens` also lists revoked and expired tokens, with a `#api-token-<id>-status` badge.
- `agent-token-roll` is `Roll` (`#replace-api-token-<id>`) on an active token. A confirm dialog asks first. The old secret stops working and a new one shows once. Flash starts `Token rolled.`
- `agent-token-replace` is `Make replacement` on a revoked or expired token. No confirm dialog. Flash `Replacement created. Copy it now. It will not be shown again.`
- `agent-token-revoke` is `#revoke-api-token-<id>` (confirm dialog, flash `Token revoked.`). `#revoke-all-api-tokens` (confirm dialog, flash `Revoked <n> token(s).`) shows only while a token is active.
- `mcp-auth` answers 401 with `www-authenticate: Bearer realm="pinventory"` for a missing, wrong, revoked, or expired token.
- `mcp-tools` lists nine tools: `list_locations`, `list_items`, `create_item`, `rename_item`, `rename_location`, `change_stock`, `move_stock`, `get_naming_convention`, `edit_naming_convention`. `initialize` returns `serverInfo.name` `Pinventory` and agent instructions.
- `mcp-list-items` matches each term like the Items filter (letters in order, gaps allowed). Any one term matching is enough. No match returns `items: []` plus a hint to try other wordings. `location_id` limits results to items with stock there, with or without terms. Neither lists every item. An unknown or malformed `location_id` is a tool error `No location has that id.…`.
- `mcp-create-rename` covers `create_item` (`name`, optional `notes`, no stock), `rename_item` (`item_id`, `name`), and `rename_location` (`location_id`, `name`). Each goes through the same save as the web UI, so the item or location Activity shows the edit. Bad names are tool errors starting `Nothing was changed:`. Item name uniqueness is case-sensitive, so `paper towels` is allowed next to `Paper towels`.
- `mcp-change-stock` takes exactly one of `add` or `set`. `move_stock` moves between two locations in one change. Refusals are tool errors that change nothing: `below zero: …`, `not enough: …`, `Send exactly one of add or set.`, `No location has that id.…`, `No item has that id.…`.
- `mcp-naming-convention` covers `get_naming_convention` (returns `text`, `version`, `edited_by`, `edited_at`, `url`; the seeded version 0 has null `edited_by`) and `edit_naming_convention` (`text`, `version`). An edit from an older version is a tool error `The naming convention is now at version <n>, not <m>. Nothing was changed.…`. The instructions and the `create_item` and `rename_item` descriptions point to `get_naming_convention`. The editor at `/items/naming-convention` shows the agent's edit as `<email> via <token name>` in `#convention-last-edit` and the history. Sqlite `select number, via_token_name from naming_convention_versions;` is the second view.
- `mcp-activity` marks agent changes. The Items row `#items-<id>-last-stock` and the Activity card heading read `verify@example.com via <token name>`.

## How to get to it (user POV)

- Choose `Settings` in the header. `Agent access` is the last section of the Account tab.
- An agent's MCP client posts JSON-RPC to `/mcp` with `Authorization: Bearer <token>`.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` succeeded inside the last 20 minutes (token actions need sudo mode, like the rest of Settings).
- For stock tools, an item with stock and two locations exist (from [Items](./items.md) and [Locations](./locations.md)).

- **Create.** Run `verify-pinventory browser goto /user/settings` and wait for `#agent-access-section`. `#api-tokens-empty` reads `No active tokens.` Fill `#api_token_name` with `Verify Agent` and click `#create-api-token`. Wait for `#latest-api-token`. Save the secret with `verify-pinventory browser attr '#latest-api-token-value' value > /tmp/verify-token`. Sqlite `select name, revoked_at from api_tokens;` has one row with no `revoked_at`.
- **MCP calls.** Use curl. The reply is an SSE body; the JSON is on the `data:` line.

  ```bash
  T=$(cat /tmp/verify-token)
  mcp() { curl -s -X POST http://127.0.0.1:4010/mcp -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' -H "authorization: Bearer $T" -d "$1" | sed -n 's/^data: //p' | head -1; }
  mcp '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
  mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_items","arguments":{"terms":["vrfy hmr"]}}}'
  mcp '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"change_stock","arguments":{"item_id":"<item-id>","location_id":"<location-id>","add":4}}}'
  ```

  `list_items` with `vrfy hmr` returns `Verify Hammer` with its stock per location. `change_stock` returns `from` and `to`. An `add` that goes below zero returns `isError: true` and sqlite `item_locations` is unchanged. `move_stock` with `quantity` above the source count returns `not enough: …`.
- **No token.** Run the same curl without the `authorization` header. It is HTTP 401 with `www-authenticate: Bearer realm="pinventory"`.
- **Marked as the agent.** Run `verify-pinventory browser goto /`. `#items-<item-id>-last-stock` includes `via Verify Agent`. On `/user/settings/activity`, the newest card heading includes `verify@example.com via Verify Agent`. After a reload of `/user/settings`, the token row reads `last used <date>`.
- **Roll.** Run `verify-pinventory browser click-confirm '#replace-api-token-<token-id>'`. It prints the dialog text `Roll this token? The old secret stops working right away.` Wait for `#latest-api-token`. The old secret now gets 401 and the new one 200. Sqlite has the old row revoked and a new row with the same name.
- **Revoke.** Run `verify-pinventory browser click-confirm '#revoke-api-token-<token-id>'`. Flash `Token revoked.` `#latest-api-token` is gone and the secret gets 401. Create a second token, then `click-confirm '#revoke-all-api-tokens'`. Flash `Revoked 1 token.` `#revoke-all-api-tokens` is gone.
- **Inactive list.** Click `#show-inactive-api-tokens`. Revoked rows show `#api-token-<id>-status` (`Revoked <date>`) and a `Make replacement` button. Click it on a revoked row. Flash `Replacement created. …`.
- **Proof.** Run `verify-pinventory browser screenshot settings/agent-access.png` and `verify-pinventory browser html settings/agent-access.html` on the Account tab. Keep the curl output and the sqlite `api_tokens` rows.

## Gotchas

- Roll, Revoke, and Revoke all ask with a native confirm dialog. Plain `browser click` dismisses it and nothing changes. Use `browser click-confirm`, which accepts the dialog and fails if none appears.
- Use the port you launched with in the curl URL. `url` fields in MCP replies use the endpoint host `localhost`, not `127.0.0.1`.
- The token list does not refresh on its own. `never used` and `last used` update only after a reload of `/user/settings`.
- A secret is shown once. Leaving the page loses it. Sqlite stores only a hash, so save it from `#latest-api-token-value` before navigating.
- Create with a blank name does nothing. The browser's `required` check blocks the submit, so no flash or error shows.
- Dates on the token rows are UTC.
- The agent cannot create or delete locations, delete items, or edit notes of existing items. Those tools do not exist.
