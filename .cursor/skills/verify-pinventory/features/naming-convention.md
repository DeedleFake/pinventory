# Naming convention

The naming convention is one shared Markdown page that says how to name items. People edit it at `/items/naming-convention` with a toolbar, a Format button, and a live preview that scrolls with the Markdown. Every save adds a numbered version, and the history shows what each version changed. The item editor shows the current text in a read-only panel. Agents read and edit it over MCP; see [Agent access](./agent-access.md).

## Sub-features

- `convention-open` is the `Naming convention` button (`#naming-convention`) on the Items list. It opens `#convention-page` with heading `Naming convention`. `#convention-last-edit` reads `Initial version` for the seeded version 0, else `Last edited by <author> · <time> · v<n>`. An agent's edit reads `<email> via <token name>`.
- `convention-edit` types into `#convention-text`. The preview `#convention-preview-body` re-renders after a 250ms debounce. `#convention-hint` reads `Unsaved changes` and `#convention-save` enables. Save flashes `Naming convention saved`, adds a version, and disables Save again. Save stays disabled while the text matches the current version.
- `convention-toolbar` has `#convention-tool-<bold|italic|strike|heading|bullet|number|quote|code|link>`. Each wraps the selection or prefixes the selected lines. Bold, italic, strike, and code undo themselves when the selection already has them. Link turns the selection into `[text](url)`.
- `convention-format` (`#convention-format`) rewrites the Markdown in one style: `-` bullets, `**bold**`, `*italic*`, `#` headings, fenced code. `#convention-format-status` reads `Formatted`, or `Already tidy` when nothing changed. It does not save.
- `convention-scroll-sync` keeps `#convention-text` and `#convention-preview` showing the same part of the document on wide screens (`lg`, 1024px and up). Scrolling either pane moves the other, and both reach their ends together. Below that width the panes stack and sync does nothing. That path is read from source; the harness window is wide.
- `convention-history` is `#convention-history-open` (`History`, shown once a second version exists). It opens `#convention-history` with one `#convention-history-version-<n>` per version (v0 is `Initial version`), `#convention-history-summary` (`Changes by <author> · v<n-1> → v<n>`), `#convention-history-counts`, `#convention-view-inline` / `#convention-view-split`, and `#convention-history-restore`. Restore fills the editor, closes the window, and sets `#convention-hint` to `Unsaved changes · restored from v<n>`. Save writes it as a new version; nothing is rewritten.
- `convention-stale` shows someone else's save as it happens. Unedited text reloads in place. Edited text stays and `#convention-stale` appears: `#convention-stale-message` reads `<author> saved version <n> while you were editing.` with a `Their version → yours` diff (`#convention-stale-diff`). Save is disabled until `#convention-stale-keep` (keeps the text and makes the newer version the base, so the next Save writes on top of it) or `#convention-stale-load` (loads the newer text and drops the edits). A Save that crosses another save shows the same warning. `#convention-editors` lists anyone else with the page open.
- `convention-item-panel` is `#item-naming-convention` on the new and edit item pages, a closed `<details>`. Its summary opens `#item-naming-convention-body` (the rendered current text). `#item-naming-convention-edit` links to `/items/naming-convention` with `target="_blank"`. The panel stays open while the item form re-renders.

## How to get to it (user POV)

- On Items, choose `Naming convention` next to `New Item`.
- On a new or edit item page, open `Naming convention` under the name, then choose `Edit` to open the editor in a new tab.
- Open `/items/naming-convention` directly. The `Items` link above the heading goes back.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `browser login` has landed on `#items-page`.
- For the agent author and stale steps, an API token secret is in `/tmp/verify-token` and the `mcp` shell function from [Agent access](./agent-access.md) is defined.

- **Open.** Run `verify-pinventory browser click '#naming-convention'` and wait for `#convention-page`. `browser text '#convention-page h1 >> nth=0'` prints `Naming convention`. On a fresh launch, `#convention-last-edit` reads `Initial version`, `browser enabled '#convention-save'` prints `disabled`, and `#convention-history-open` count is 0.
- **Edit and preview.** Run `verify-pinventory browser fill '#convention-text' $'* apple\n* pear\n\nsome __bold__ text'`, then `browser wait-enabled '#convention-save'`. `#convention-hint` reads `Unsaved changes`. `browser count '#convention-preview-body li'` prints `2` and `browser count '#convention-preview-body strong'` prints `1`.
- **Format.** Click `#convention-format` and wait for `#convention-format-status`. It reads `Formatted`. `browser value '#convention-text'` prints `- apple`, `- pear`, and `some **bold** text`. Click it again. The status reads `Already tidy`.
- **Toolbar.** Fill `#convention-text` with `Verify rule`. Click `#convention-text`, run `browser press Control+a`, then click `#convention-tool-bold`. `browser value '#convention-text'` prints `**Verify rule**`. Click `#convention-tool-bold` again. It prints `Verify rule`. Select all again and click `#convention-tool-bullet`. It prints `- Verify rule`.
- **Save.** Fill `#convention-text` with `$'# Item names\n\n- Verify rule two.'`, wait for Save to enable, and click `#convention-save`. Wait for `#flash-info` `Naming convention saved`. `#convention-last-edit` reads `Last edited by verify@example.com · just now · v<n>`. Run `verify-pinventory sqlite "select number, via_token_name from naming_convention_versions;"`. The new number is there with no token name.
- **History and restore.** Dismiss the flash. Click `#convention-history-open` and wait for `#convention-history`. It opens on the newest version: `#convention-history-summary` reads `Changes by verify@example.com · v<n-1> → v<n>` and `browser enabled '#convention-history-restore'` prints `disabled`, because that text is already in the editor. Click `#convention-history-version-<n-1>`. Click `#convention-view-split`. `browser attr '#convention-diff' data-view` prints `split`. Click `#convention-history-restore`. `#convention-history` count is 0 and `#convention-hint` reads `Unsaved changes · restored from v<n-1>`. Leave without saving: `browser goto /items/naming-convention`.
- **Agent author.** Call `get_naming_convention` with `mcp`, then `edit_naming_convention` with its `version`. Reload the editor. `#convention-last-edit` reads `Last edited by verify@example.com via Verify Agent`.
- **Stale.** Fill `#convention-text` with `$'# Item names\n\n- Mine.'` and wait for Save to enable. With `mcp`, call `edit_naming_convention` with other text and the current `version`. Without clicking anything, wait for `#convention-stale`. It names `verify@example.com via Verify Agent`. Click `#convention-stale-keep`. The warning is gone, the text is still `Mine`, and `#convention-last-edit` shows the agent's version. Click `#convention-save` and wait for `Naming convention saved`. For the other path, repeat and click `#convention-stale-load`. `browser value '#convention-text'` prints the agent's text and Save is disabled.
- **Two people.** With person 2 logged in as another user (see `PINVENTORY_PERSON` in the skill Drive section), both open the editor. `#convention-editors` reads `Also editing: sam@example.com`. A save by person 2 reloads your unedited text in place. With your text edited, their save shows `#convention-stale` with `sam@example.com saved version <n> while you were editing.`
- **Scroll sync.** Fill `#convention-text` with a long document, for example `"$(python3 -c 'print("\n\n".join(f"## Section {i}\n\n- rule {i} a\n- rule {i} b" for i in range(1,41)))')"`. Run `verify-pinventory browser scroll '#convention-text' 800`, then `browser scroll '#convention-preview'`. The preview's `scrollTop` is close to, not equal to, 800 (the panes have different heights). A screenshot shows the same `Section` at the top of both panes. `browser scroll '#convention-preview' 99999`, then `browser scroll '#convention-text'`, shows both at their `max`. Leave without saving.
- **Item panel.** Run `verify-pinventory browser goto /item` and wait for `#item-page`. `browser count '#item-naming-convention[open]'` prints `0`. Click `#item-naming-convention summary`. The count is `1` and `#item-naming-convention-body` shows the current text. `browser attr '#item-naming-convention-edit' target` prints `_blank` and `href` prints `/items/naming-convention`. Fill `#item_name`. The count is still `1`.
- **Proof.** Run `verify-pinventory browser screenshot naming-convention/editor.png` and `browser html naming-convention/editor.html` on the editor, and `naming-convention/history.png` with the history open. Keep the sqlite `naming_convention_versions` rows.

## Gotchas

- `browser text '#convention-text'` prints blank, whatever the textarea holds. Use `browser value`.
- The toolbar acts on the textarea selection. Click `#convention-text` and select with `browser press` first. With no selection, Bold inserts `****` at the cursor.
- `browser attr '#item-naming-convention' open` prints blank whether it is open or not. Count `#item-naming-convention[open]` instead.
- Scroll sync needs the wide layout. The launched Chromium window is 1280 wide, which is wide enough.
- `browser goto` away from a dirty editor works; the unsaved-changes prompt does not block it.
- Text is capped at 20,000 characters. A longer save flashes an error starting `Could not save the naming convention`.
- Restore, Format, and the toolbar only change the form. Nothing is saved until Save.
