# Pinventory Agent Instructions

Pinventory is a Phoenix LiveView app for simple home inventory tracking. The product goal is minimal friction: item names include any unit wording, quantities are plain numbers, and locations are simple named buckets.

## Non-Negotiable Workflow Rules

- Never run Git write operations unless the user explicitly asks for that exact operation.
- Do not run `git add`, `git commit`, `git commit --amend`, `git rebase`, `git reset`, `git checkout --`, `git push`, or other mutating Git commands on your own initiative.
- Read-only Git commands such as `git status`, `git diff`, and `git log` are allowed when useful.
- Do not revert, overwrite, or remove user changes unless the user explicitly asks.
- Use the smallest correct change. Avoid broad refactors unless they directly serve the requested work.
- When working from a plan broken into tasks or phases, run code review after each task/phase, including `thermo-nuclear-code-review` when relevant, fix the findings, and only then move to the next task/phase.
- Run `mix precommit` and any relevant code-review skills (such as `thermo-nuclear-code-review`) before claiming code changes are complete, unless the user asks you not to or the environment prevents it.

## Common Commands

- `mix setup` - install dependencies, set up the database, and build assets.
- `mix phx.server` - start the Phoenix server.
- `iex -S mix phx.server` - start the server inside IEx.
- `mix test` - run the test suite.
- `mix test test/path/to_test.exs` - run one test file.
- `mix test --failed` - rerun previously failed tests.
- `mix format` - format Elixir code.
- `mix precommit` - compile with warnings as errors, check unused deps, format, and test.
- Use `mix help task_name` before running unfamiliar Mix tasks.
- `mix deps.clean --all` is almost never needed; avoid it unless there is a specific dependency corruption issue.

## Architecture

- `lib/pinventory/items.ex` is the Items context. Put item lookup, creation, duplicate handling, and quantity operations here.
- `lib/pinventory/locations.ex` is the Locations context. Put location lookup, creation, and duplicate handling here.
- `lib/pinventory_web/live/items_live.ex` is the primary inventory screen.
- `lib/pinventory_web/live/edit_item_live.ex` is the item create/edit flow.
- `lib/pinventory_web/live/locations_live.ex` is the location management UI.
- `lib/pinventory/items/item.ex`, `lib/pinventory/items/item_location.ex`, and `lib/pinventory/locations/location.ex` are the core schemas.
- `priv/repo/migrations` contains the database history. Prefer migrations over ad-hoc schema assumptions.
- Future ownership should be modeled through `inventory_spaces`: items and locations should be unique within an inventory space, not globally. Until auth exists, use a single default inventory space and keep it hidden from users.

## Product Constraints

- Keep the app simple. The core workflow is: find item, choose location, add/remove quantity, move quantity.
- Do not add separate units. Users should write names like `Cans of tuna`, `Rolls of paper towels`, or `Bags of rice`.
- Do not add brands, pictures, categories, statistics, shopping lists, collaboration, or multi-space switching unless specifically requested.
- Item names must not conflict within an inventory space. A duplicate item name should warn and direct the user to the existing item.
- Location names must not conflict within an inventory space.
- Inventory spaces are an internal scope until there is more than one meaningful choice for the user.
- Quantity must never go below zero.
- Moving quantity between locations should be a dedicated operation and should be transactional.

## Elixir Style

- Keep domain logic in contexts, not LiveViews.
- Prefer clear function names such as `list_items/1`, `create_item/2`, `add_quantity/4`, `remove_quantity/4`, and `move_quantity/5`.
- Predicate function names should end in `?`; reserve `is_` names for guards.
- Do not use `String.to_atom/1` on user input.
- Do not access lists with bracket syntax. Use pattern matching, `Enum.at/2`, or `List` functions.
- Do not access struct fields with map access syntax such as `changeset[:field]`. Use direct fields or `Ecto.Changeset.get_field/2`.
- Bind the result of `if`, `case`, `cond`, and similar expressions instead of rebinding variables only inside the block.
- Do not nest multiple modules in the same file.
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure when concurrency is needed.

## Ecto Style

- Use schemas and changesets for validation; use contexts for persistence workflows.
- Fields set by the system, such as future `inventory_space_id` or `user_id`, should not be accepted directly from public form params.
- Preload associations in queries when templates access associated data.
- Use database constraints for uniqueness and important invariants, then surface changeset errors clearly.
- Use transactions for multi-row inventory operations, especially moving quantity between locations.
- `Ecto.Changeset.validate_number/2` does not support `:allow_nil`; do not add that option.
- Ecto schema fields use `:string` for text-like columns.
- Use `Req` for HTTP requests if external calls are needed. Do not add HTTPoison, Tesla, or `:httpc`.

## Phoenix And LiveView Style

- Begin LiveView templates with `<Layouts.app flash={@flash}>` unless the route explicitly needs additional assigns.
- `Layouts` is already aliased through `PinventoryWeb`; do not alias it again.
- Do not call `<.flash_group>` outside `layouts.ex`.
- Do not introduce `Phoenix.View`; Phoenix 1.8 apps do not need it.
- Router `scope` blocks already provide an alias, so avoid double-prefixing LiveView modules in routes.
- Use the imported `<.input>` component for form inputs when available.
- Build forms with `to_form/2` and `<.form for={@form}>`; do not pass changesets directly to templates.
- Give key forms, buttons, controls, and row containers stable DOM IDs for tests.
- Use `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate/2`, and `push_patch/2`; do not use deprecated LiveView navigation helpers.
- Avoid LiveComponents unless there is a strong reason.
- Use LiveView streams for rendered collections. When filtering or sorting a stream, refetch data and stream with `reset: true`.
- Stream containers need a stable DOM ID and `phx-update="stream"`; stream children should use the DOM IDs from `@streams.name` tuples.
- LiveView streams are not enumerable. Track counts and empty states with separate assigns when needed.
- If a JS hook manages its own DOM, set `phx-update="ignore"` on that element.

## HEEx Style

- Use `~H` or `.html.heex`; never use `~E`.
- Use `{...}` interpolation in attributes and simple tag bodies.
- Use `<%= ... %>` for block constructs inside tag bodies.
- Use HEEx class list syntax (`class={[...]}`) for conditional or multi-part classes.
- Wrap inline `if` expressions in class lists with parentheses.
- Use `<%= for item <- @items do %>` for generated template content; do not use `<% Enum.each %>`.
- Use HEEx comments (`<%!-- comment --%>`) for template comments.
- For literal braces in code examples, annotate the parent with `phx-no-curly-interpolation`.
- Elixir has no `else if`; use `cond` or `case` for multiple branches.

## Assets And UI

- Preserve the Tailwind v4 import/source syntax in `assets/css/app.css`.
- Only the `app.js` and `app.css` bundles are supported by default.
- Do not put inline `<script>` tags in HEEx templates. Add JS to `assets/js/app.js` or hooks imported from there.
- Do not use `@apply` in raw CSS.
- Prefer custom Tailwind UI for new work. DaisyUI is currently scaffolded into the app, but do not expand its use unless requested.
- Use `<.icon>` for icons; do not call Heroicons modules directly.
- Keep UI interactions large, obvious, and mobile-friendly. Inventory actions should be easy to perform without precise clicking.

## Testing

- Prefer context tests for business rules: duplicate names, add quantity, remove quantity, move quantity, and insufficient stock.
- Use LiveView tests for UI behavior: search, location filter, item creation, quantity adjustment, and move flows.
- Use `Phoenix.LiveViewTest` helpers such as `element/2`, `has_element?/2`, `render_change/2`, and `render_submit/2`.
- Do not assert against raw full HTML when a selector assertion is sufficient.
- Test outcomes and invariants, not implementation details.
- If selector debugging is needed, use `LazyHTML` to inspect focused fragments rather than dumping whole pages.

## Known Current Gaps

- The item create/edit LiveView is currently a placeholder.
- Location save handling is incomplete.
- Item search UI patches the URL but filtering still needs to be fully wired.
- Quantity-by-location operations need careful changeset and transaction coverage.
- `inventory_spaces` are planned but not implemented yet.
