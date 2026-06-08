# Pinventory

Pinventory is a small Phoenix LiveView app for tracking simple household inventory. The goal is minimal friction: name the thing the way you think about it, put it in a location, and adjust the count when it changes.

Examples of good item names are `Cans of tuna`, `Rolls of paper towels`, and `Bags of rice`. Pinventory intentionally does not split those into separate unit fields.

## Project Status

Pinventory is early in development. The core data model has started to take shape, but several user flows are still incomplete.

Currently, the app has the beginnings of:

- Items
- Locations
- Per-location item quantities
- Item search support
- Phoenix LiveView screens for inventory, item editing, and location management

The item create/edit flow, location save handling, search filtering, and quantity operations still need more work before the app is broadly usable.

## Product Idea

Pinventory is meant to answer basic home-inventory questions quickly:

- What do I have?
- Where is it?
- How many are there?
- Can I add, remove, or move some without fighting the UI?

The intended workflow is:

1. Find an item.
2. Choose a location.
3. Add or remove quantity at that location.
4. Move quantity between locations when needed.

The product should stay intentionally small. Pinventory is not trying to be a pantry analytics tool, shopping-list manager, barcode catalog, or photo database.

## Current Database Model

The app currently uses PostgreSQL through Ecto. IDs are UUIDs.

Current tables:

- `items` stores item names and timestamps.
- `locations` stores location names and timestamps.
- `item_locations` joins items to locations and stores the quantity for each item at each location.

Important current constraints and indexes:

- `items.name` is globally unique.
- `locations.name` is globally unique.
- Each `item_locations` row is unique by `item_id` and `location_id`.
- Item search has PostgreSQL trigram support through `pg_trgm` and a GIN index on item names.

The first migration created item-level quantity. The later location migration moved quantity into `item_locations`, so quantity now belongs to a specific item/location pair instead of directly to an item.

## Future Data Model Direction

The next major data-model direction is `inventory_spaces`.

Today, item and location names are globally unique because the app has no users, accounts, or ownership model. Long term, uniqueness should be scoped to an inventory space:

- Item names should be unique within an inventory space.
- Location names should be unique within an inventory space.
- Quantities should belong to item/location pairs inside the same inventory space.

Until authentication and multiple spaces exist, the app should use one default inventory space behind the scenes. Users should not have to choose an inventory space when there is only one meaningful choice.

Future ownership may allow users to own or join inventory spaces, but multi-space switching should stay hidden until it is actually useful.

## Planned Features

Near-term planned work:

- Complete the item create/edit flow.
- Complete location creation and editing.
- Fully wire item search and filtering in the inventory screen.
- Add safe add/remove quantity operations that never allow quantity to go below zero.
- Add a dedicated transactional move operation for moving quantity between locations.
- Improve duplicate-name handling so users are guided to the existing item or location.
- Add context tests for duplicate names, quantity changes, moves, and insufficient stock.
- Add LiveView tests for search, location filtering, item creation, quantity adjustment, and move flows.

Not planned right now:

- Separate unit fields
- Brands
- Photos
- Categories
- Statistics
- Shopping lists
- Collaboration
- Visible multi-space switching

Those may be useful later, but the current priority is a small, reliable inventory workflow.

## Running Locally

Install dependencies, set up the database, and build assets:

```sh
mix setup
```

Start the Phoenix server:

```sh
mix phx.server
```

Or start it inside IEx:

```sh
iex -S mix phx.server
```

Then visit [localhost:4000](http://localhost:4000) in your browser.

## Development Checks

Run the test suite:

```sh
mix test
```

Run the project precommit check:

```sh
mix precommit
```

`mix precommit` compiles with warnings as errors, checks for unused dependencies, formats the project, and runs tests.

## Tech Stack

- Elixir
- Phoenix 1.8
- Phoenix LiveView
- Ecto with PostgreSQL
- Tailwind CSS
- esbuild
