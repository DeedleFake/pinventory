# Basic Working Inventory Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the README's near-term core workflow: hidden inventory spaces, scoped item/location uniqueness, item and location create/edit, inventory search/filtering, and safe add/remove/move quantity operations.

**Architecture:** Add `inventory_spaces` as an internal ownership boundary before finishing the visible workflow. Keep database invariants in migrations/constraints, business rules in contexts, and LiveViews as thin UI coordinators that pass the hidden default space into context calls.

**Tech Stack:** Elixir, Phoenix 1.8, Phoenix LiveView, Ecto, PostgreSQL, Tailwind v4, ExUnit, Phoenix.LiveViewTest.

---

## Important Execution Rules

- Do not run Git write operations unless the user explicitly asks. The task checkpoints below say “review checkpoint” instead of commit.
- Use TDD for behavior changes: write focused tests first, run them to see the expected failure, then implement the smallest passing code.
- Run `mix format` after each task that edits Elixir files.
- Run the task-specific tests after each task.
- Run `mix precommit` only at the end unless a task needs a broader check.
- After each task/phase, run the relevant code-review skills required by `AGENTS.md`, including `thermo-nuclear-code-review` when the change is structural.
- Do not let public form params set `inventory_space_id`. Schema changesets should validate public fields; contexts should attach the hidden space with `Ecto.Changeset.put_change/3`.
- Enforce same-space item/location quantity rows in the database, not just in context code.
- Keep `ItemsLive` from becoming a giant mixed UI/controller file. Extract inventory row and quantity form markup into a focused function-component module if the render path starts to sprawl.

## File Map

- Create `priv/repo/migrations/*_create_inventory_spaces_and_scope_inventory.exs`: create `inventory_spaces`, backfill existing inventory records, and replace global uniqueness with scoped uniqueness.
- Create `lib/pinventory/inventory_spaces/inventory_space.ex`: Ecto schema for the hidden inventory-space table.
- Create `lib/pinventory/inventory_spaces.ex`: context for default-space lookup/creation.
- Modify `lib/pinventory/items/item.ex`: add `inventory_space_id`, association, and scoped unique constraint.
- Modify `lib/pinventory/locations/location.ex`: add `inventory_space_id`, association, and scoped unique constraint.
- Modify `lib/pinventory/items/item_location.ex`: add `inventory_space_id`, associations/foreign keys in changeset helpers, and scoped row uniqueness.
- Modify `lib/pinventory/items.ex`: add scoped item lookup/list/create/update and safe quantity operations.
- Modify `lib/pinventory/locations.ex`: add scoped location lookup/list/create/update.
- Modify `lib/pinventory_web/live/items_live.ex`: make the inventory screen useful: search, location filter, item rows, per-location quantities, add/remove/move actions.
- Create `lib/pinventory_web/live/items_live/inventory_components.ex`: focused function components for item rows and quantity controls if the inventory render grows beyond a small page shell.
- Modify `lib/pinventory_web/live/edit_item_live.ex`: complete item create/edit flow.
- Modify `lib/pinventory_web/live/locations_live.ex`: complete location create/edit flow.
- Modify `lib/pinventory_web/components/layouts.ex`: adjust app navigation if needed for inventory and locations access.
- Create `test/pinventory/inventory_spaces_test.exs`: default-space behavior.
- Create `test/pinventory/items_test.exs`: duplicate names, search/filtering, quantity add/remove/move, insufficient stock.
- Create `test/pinventory/locations_test.exs`: duplicate names and update behavior.
- Create `test/pinventory_web/live/items_live_test.exs`: inventory UI workflow coverage.
- Create `test/pinventory_web/live/edit_item_live_test.exs`: item form UI coverage.
- Create `test/pinventory_web/live/locations_live_test.exs`: location form UI coverage.
- Optional modify `test/support/data_case.ex`: add tiny fixture helpers only if repeated setup becomes noisy.

## Task 1: Hidden Inventory Spaces Foundation

**Files:**
- Create: `priv/repo/migrations/*_create_inventory_spaces_and_scope_inventory.exs`
- Create: `lib/pinventory/inventory_spaces/inventory_space.ex`
- Create: `lib/pinventory/inventory_spaces.ex`
- Modify: `lib/pinventory/items/item.ex`
- Modify: `lib/pinventory/locations/location.ex`
- Modify: `lib/pinventory/items/item_location.ex`
- Test: `test/pinventory/inventory_spaces_test.exs`

- [ ] **Step 1: Write failing default-space tests**

Create `test/pinventory/inventory_spaces_test.exs`:

```elixir
defmodule Pinventory.InventorySpacesTest do
  use Pinventory.DataCase, async: true

  alias Pinventory.InventorySpaces

  describe "get_default_space!/0" do
    test "returns the same hidden default space every time" do
      first = InventorySpaces.get_default_space!()
      second = InventorySpaces.get_default_space!()

      assert first.id == second.id
      assert first.slug == "default"
      assert first.name == "Default"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/pinventory/inventory_spaces_test.exs`

Expected: fail because `Pinventory.InventorySpaces` does not exist.

- [ ] **Step 3: Add migration for scoped inventory**

Create a migration with the current timestamp in `priv/repo/migrations/`:

```elixir
defmodule Pinventory.Repo.Migrations.CreateInventorySpacesAndScopeInventory do
  use Ecto.Migration

  def up do
    default_space_id = Ecto.UUID.generate()

    create table(:inventory_spaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inventory_spaces, [:slug])

    execute """
    INSERT INTO inventory_spaces (id, slug, name, inserted_at, updated_at)
    VALUES ('#{default_space_id}', 'default', 'Default', now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc')
    ON CONFLICT (slug) DO NOTHING
    """

    alter table(:items) do
      add :inventory_space_id, references(:inventory_spaces, type: :binary_id, on_delete: :restrict)
    end

    alter table(:locations) do
      add :inventory_space_id, references(:inventory_spaces, type: :binary_id, on_delete: :restrict)
    end

    alter table(:item_locations) do
      add :inventory_space_id, references(:inventory_spaces, type: :binary_id, on_delete: :restrict)
    end

    execute "UPDATE items SET inventory_space_id = (SELECT id FROM inventory_spaces WHERE slug = 'default')"
    execute "UPDATE locations SET inventory_space_id = (SELECT id FROM inventory_spaces WHERE slug = 'default')"
    execute "UPDATE item_locations SET inventory_space_id = (SELECT id FROM inventory_spaces WHERE slug = 'default')"

    alter table(:items) do
      modify :inventory_space_id, references(:inventory_spaces, type: :binary_id, on_delete: :restrict), null: false
    end

    alter table(:locations) do
      modify :inventory_space_id, references(:inventory_spaces, type: :binary_id, on_delete: :restrict), null: false
    end

    alter table(:item_locations) do
      modify :inventory_space_id, references(:inventory_spaces, type: :binary_id, on_delete: :restrict), null: false
    end

    drop unique_index(:items, [:name])
    drop unique_index(:locations, [:name])
    drop unique_index(:item_locations, [:item_id, :location_id])

    create unique_index(:items, [:inventory_space_id, :name], name: :items_inventory_space_id_name_index)
    create unique_index(:locations, [:inventory_space_id, :name], name: :locations_inventory_space_id_name_index)
    create unique_index(:items, [:inventory_space_id, :id], name: :items_inventory_space_id_id_index)
    create unique_index(:locations, [:inventory_space_id, :id], name: :locations_inventory_space_id_id_index)

    create unique_index(:item_locations, [:inventory_space_id, :item_id, :location_id],
             name: :item_locations_inventory_space_item_location_index
           )

    create index(:items, [:inventory_space_id])
    create index(:locations, [:inventory_space_id])
    create index(:item_locations, [:inventory_space_id])

    execute """
    ALTER TABLE item_locations
    ADD CONSTRAINT item_locations_space_item_fk
    FOREIGN KEY (inventory_space_id, item_id)
    REFERENCES items (inventory_space_id, id)
    ON DELETE CASCADE
    """

    execute """
    ALTER TABLE item_locations
    ADD CONSTRAINT item_locations_space_location_fk
    FOREIGN KEY (inventory_space_id, location_id)
    REFERENCES locations (inventory_space_id, id)
    ON DELETE CASCADE
    """
  end

  def down do
    execute "ALTER TABLE item_locations DROP CONSTRAINT IF EXISTS item_locations_space_location_fk"
    execute "ALTER TABLE item_locations DROP CONSTRAINT IF EXISTS item_locations_space_item_fk"

    drop unique_index(:item_locations, [:inventory_space_id, :item_id, :location_id],
           name: :item_locations_inventory_space_item_location_index
         )

    drop unique_index(:locations, [:inventory_space_id, :id], name: :locations_inventory_space_id_id_index)
    drop unique_index(:items, [:inventory_space_id, :id], name: :items_inventory_space_id_id_index)
    drop unique_index(:locations, [:inventory_space_id, :name], name: :locations_inventory_space_id_name_index)
    drop unique_index(:items, [:inventory_space_id, :name], name: :items_inventory_space_id_name_index)
    drop index(:item_locations, [:inventory_space_id])
    drop index(:locations, [:inventory_space_id])
    drop index(:items, [:inventory_space_id])

    create unique_index(:items, [:name])
    create unique_index(:locations, [:name])
    create unique_index(:item_locations, [:item_id, :location_id])

    alter table(:item_locations), do: remove :inventory_space_id
    alter table(:locations), do: remove :inventory_space_id
    alter table(:items), do: remove :inventory_space_id

    drop table(:inventory_spaces)
  end
end
```

- [ ] **Step 4: Add schema and context**

Create `lib/pinventory/inventory_spaces/inventory_space.ex`:

```elixir
defmodule Pinventory.InventorySpaces.InventorySpace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "inventory_spaces" do
    field :slug, :string
    field :name, :string

    has_many :items, Pinventory.Items.Item
    has_many :locations, Pinventory.Locations.Location
    has_many :item_locations, Pinventory.Items.ItemLocation

    timestamps(type: :utc_datetime)
  end

  def changeset(inventory_space, attrs) do
    inventory_space
    |> cast(attrs, [:slug, :name])
    |> validate_required([:slug, :name])
    |> unique_constraint(:slug)
  end
end
```

Create `lib/pinventory/inventory_spaces.ex`:

```elixir
defmodule Pinventory.InventorySpaces do
  @moduledoc """
  Internal inventory-space ownership boundary.
  """

  alias Pinventory.InventorySpaces.InventorySpace
  alias Pinventory.Repo

  @default_attrs %{slug: "default", name: "Default"}

  def get_default_space! do
    case Repo.get_by(InventorySpace, slug: @default_attrs.slug) do
      nil -> create_default_space!()
      space -> space
    end
  end

  defp create_default_space! do
    %InventorySpace{}
    |> InventorySpace.changeset(@default_attrs)
    |> Repo.insert!(on_conflict: [set: [name: @default_attrs.name]], conflict_target: :slug, returning: true)
  end
end
```

- [ ] **Step 5: Add associations to existing schemas**

In `lib/pinventory/items/item.ex`, add the `belongs_to` and scoped unique constraint:

```elixir
belongs_to :inventory_space, Pinventory.InventorySpaces.InventorySpace
```

Keep the public item changeset limited to user-editable fields, then add a small internal helper for context-owned scoping:

```elixir
def changeset(item, attrs) do
  item
  |> cast(attrs, [:name])
  |> validate_required([:name])
  |> validate_length(:name, min: 2)
  |> unique_constraint(:name, name: :items_inventory_space_id_name_index)
end

def put_inventory_space(changeset, inventory_space) do
  changeset
  |> put_change(:inventory_space_id, inventory_space.id)
  |> validate_required([:inventory_space_id])
end
```

In `lib/pinventory/locations/location.ex`, make the same association and add `put_inventory_space/2`. Keep `changeset/2` limited to `:name` and use `unique_constraint(:name, name: :locations_inventory_space_id_name_index)`.

In `lib/pinventory/items/item_location.ex`, add:

```elixir
belongs_to :inventory_space, Pinventory.InventorySpaces.InventorySpace
```

Update its changeset to cast and require `:inventory_space_id`, `:item_id`, and `:location_id` directly. This changeset is internal-only and should only be called from `Pinventory.Items`:

```elixir
|> cast(attrs, [:inventory_space_id, :item_id, :location_id, :quantity])
|> validate_required([:inventory_space_id, :item_id, :location_id, :quantity])
|> validate_number(:quantity, greater_than_or_equal_to: 0)
|> foreign_key_constraint(:item_id, name: :item_locations_space_item_fk)
|> foreign_key_constraint(:location_id, name: :item_locations_space_location_fk)
|> unique_constraint(:item_id, name: :item_locations_inventory_space_item_location_index)
```

- [ ] **Step 6: Run migration and tests**

Run: `mix ecto.migrate`

Expected: migration succeeds.

Run: `mix test test/pinventory/inventory_spaces_test.exs`
Expected: pass.

- [ ] **Step 7: Review checkpoint**

Run: `mix format`

Run: `mix test test/pinventory/inventory_spaces_test.exs`
Run relevant code-review skills before continuing.

## Task 2: Scoped Item And Location Contexts

**Files:**
- Modify: `lib/pinventory/items.ex`
- Modify: `lib/pinventory/locations.ex`
- Test: `test/pinventory/items_test.exs`
- Test: `test/pinventory/locations_test.exs`

- [ ] **Step 1: Write failing item context tests**

Create `test/pinventory/items_test.exs`:

```elixir
defmodule Pinventory.ItemsTest do
  use Pinventory.DataCase, async: true

  alias Pinventory.InventorySpaces
  alias Pinventory.Items

  setup do
    %{space: InventorySpaces.get_default_space!()}
  end

  test "creates and lists items within a space", %{space: space} do
    assert {:ok, item} = Items.create_item(space, %{name: "Cans of tuna"})
    assert item.inventory_space_id == space.id
    assert [%{id: item_id, name: "Cans of tuna"}] = Items.list_items(space)
    assert item_id == item.id
  end

  test "rejects duplicate item names within the same space", %{space: space} do
    assert {:ok, _item} = Items.create_item(space, %{name: "Cans of tuna"})
    assert {:error, changeset} = Items.create_item(space, %{name: "Cans of tuna"})
    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end

  test "filters item names", %{space: space} do
    assert {:ok, _} = Items.create_item(space, %{name: "Cans of tuna"})
    assert {:ok, _} = Items.create_item(space, %{name: "Paper towels"})

    assert [%{name: "Cans of tuna"}] = Items.list_items(space, filter: "tuna")
  end
end
```

- [ ] **Step 2: Write failing location context tests**

Create `test/pinventory/locations_test.exs`:

```elixir
defmodule Pinventory.LocationsTest do
  use Pinventory.DataCase, async: true

  alias Pinventory.InventorySpaces
  alias Pinventory.Locations

  setup do
    %{space: InventorySpaces.get_default_space!()}
  end

  test "creates and lists locations within a space", %{space: space} do
    assert {:ok, location} = Locations.create_location(space, %{name: "Pantry"})
    assert location.inventory_space_id == space.id
    assert [%{id: location_id, name: "Pantry"}] = Locations.list_locations(space)
    assert location_id == location.id
  end

  test "rejects duplicate location names within the same space", %{space: space} do
    assert {:ok, _location} = Locations.create_location(space, %{name: "Pantry"})
    assert {:error, changeset} = Locations.create_location(space, %{name: "Pantry"})
    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end
end
```

- [ ] **Step 3: Run tests to verify failures**

Run: `mix test test/pinventory/items_test.exs test/pinventory/locations_test.exs`
Expected: fail because scoped context functions do not exist.

- [ ] **Step 4: Implement scoped context functions**

In `lib/pinventory/items.ex`, replace global APIs with scoped APIs while keeping only compatibility wrappers if needed by unfinished LiveViews during this task:

```elixir
def list_items(space, opts \\ []) do
  opts = Keyword.validate!(opts, [:filter, :location_id, limit: 100])

  base = from item in Item, where: item.inventory_space_id == ^space.id

  filtered =
    if opts[:filter] do
      from item in base, where: ilike(item.name, ^"%#{opts[:filter]}%")
    else
      base
    end

  located =
    if opts[:location_id] do
      from item in filtered,
        join: item_location in assoc(item, :item_locations),
        where: item_location.location_id == ^opts[:location_id]
    else
      filtered
    end

  located
  |> order_by([item], asc: item.name)
  |> limit(^opts[:limit])
  |> preload(item_locations: :location)
  |> Repo.all()
end

def get_item!(space, id) do
  Item
  |> Repo.get_by!(id: id, inventory_space_id: space.id)
  |> Repo.preload(item_locations: :location)
end

def change_item(space, item \\ %Item{}, attrs \\ %{}) do
  item
  |> Item.changeset(attrs)
  |> Item.put_inventory_space(space)
end

def create_item(space, attrs) do
  space
  |> change_item(%Item{}, attrs)
  |> Repo.insert()
end

def update_item(space, %Item{} = item, attrs) do
  space
  |> change_item(item, attrs)
  |> Repo.update()
end
```

In `lib/pinventory/locations.ex`, add:

```elixir
def list_locations(space) do
  Location
  |> where([location], location.inventory_space_id == ^space.id)
  |> order_by([location], asc: location.name)
  |> Repo.all()
end

def get_location!(space, id) do
  Repo.get_by!(Location, id: id, inventory_space_id: space.id)
end

def change_location(space, location \\ %Location{}, attrs \\ %{}) do
  location
  |> Location.changeset(attrs)
  |> Location.put_inventory_space(space)
end

def create_location(space, attrs) do
  space
  |> change_location(%Location{}, attrs)
  |> Repo.insert(returning: true)
end

def update_location(space, %Location{} = location, attrs) do
  space
  |> change_location(location, attrs)
  |> Repo.update()
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/pinventory/items_test.exs test/pinventory/locations_test.exs`
Expected: pass.

- [ ] **Step 6: Review checkpoint**

Run: `mix format`
Run: `mix test test/pinventory/items_test.exs test/pinventory/locations_test.exs`
Run relevant code-review skills before continuing.

## Task 3: Safe Quantity Operations

**Files:**
- Modify: `lib/pinventory/items.ex`
- Test: `test/pinventory/items_test.exs`

- [ ] **Step 1: Add failing quantity tests**

Append to `test/pinventory/items_test.exs`:

```elixir
alias Pinventory.Locations

test "adds and removes quantity without going below zero", %{space: space} do
  assert {:ok, item} = Items.create_item(space, %{name: "Bags of rice"})
  assert {:ok, location} = Locations.create_location(space, %{name: "Pantry"})

  assert {:ok, item_location} = Items.add_quantity(space, item, location, 5)
  assert item_location.quantity == 5

  assert {:ok, item_location} = Items.remove_quantity(space, item, location, 2)
  assert item_location.quantity == 3

  assert {:error, :insufficient_stock} = Items.remove_quantity(space, item, location, 4)
end

test "moves quantity transactionally", %{space: space} do
  assert {:ok, item} = Items.create_item(space, %{name: "Paper towels"})
  assert {:ok, pantry} = Locations.create_location(space, %{name: "Pantry"})
  assert {:ok, closet} = Locations.create_location(space, %{name: "Closet"})
  assert {:ok, _} = Items.add_quantity(space, item, pantry, 7)

  assert {:ok, %{from: from_row, to: to_row}} = Items.move_quantity(space, item, pantry, closet, 3)
  assert from_row.quantity == 4
  assert to_row.quantity == 3

  assert {:error, :insufficient_stock} = Items.move_quantity(space, item, pantry, closet, 5)
end
```

- [ ] **Step 2: Run tests to verify failures**

Run: `mix test test/pinventory/items_test.exs`
Expected: fail because quantity functions do not exist.

- [ ] **Step 3: Implement quantity functions**

In `lib/pinventory/items.ex`, add functions with row locking for stock checks:

```elixir
def add_quantity(space, item, location, amount) when amount > 0 do
  Repo.transaction(fn ->
    row = get_or_create_item_location!(space, item, location)
    update_item_location_quantity!(row, row.quantity + amount)
  end)
end

def remove_quantity(space, item, location, amount) when amount > 0 do
  Repo.transaction(fn ->
    row = get_or_create_item_location!(space, item, location)

    if row.quantity >= amount do
      update_item_location_quantity!(row, row.quantity - amount)
    else
      Repo.rollback(:insufficient_stock)
    end
  end)
end

def move_quantity(space, item, from_location, to_location, amount) when amount > 0 do
  Repo.transaction(fn ->
    from_row = get_or_create_item_location!(space, item, from_location)

    if from_row.quantity >= amount do
      to_row = get_or_create_item_location!(space, item, to_location)

      %{
        from: update_item_location_quantity!(from_row, from_row.quantity - amount),
        to: update_item_location_quantity!(to_row, to_row.quantity + amount)
      }
    else
      Repo.rollback(:insufficient_stock)
    end
  end)
end

defp get_or_create_item_location!(space, item, location) do
  item_id = get_id(item)
  location_id = get_id(location)

  %ItemLocation{}
  |> ItemLocation.changeset(%{
    inventory_space_id: space.id,
    item_id: item_id,
    location_id: location_id,
    quantity: 0
  })
  |> Repo.insert!(
    on_conflict: [set: [updated_at: fragment("now() AT TIME ZONE 'utc'")]],
    conflict_target: [:inventory_space_id, :item_id, :location_id]
  )

  query =
    from item_location in ItemLocation,
      where:
        item_location.inventory_space_id == ^space.id and
          item_location.item_id == ^item_id and
          item_location.location_id == ^location_id,
      lock: "FOR UPDATE"

  Repo.one!(query)
end

defp update_item_location_quantity!(item_location, quantity) do
  item_location
  |> ItemLocation.changeset(%{quantity: quantity})
  |> Repo.update!()
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/pinventory/items_test.exs`
Expected: pass.

- [ ] **Step 5: Review checkpoint**

Run: `mix format`
Run: `mix test test/pinventory/items_test.exs`
Run relevant code-review skills before continuing.

## Task 4: Complete Item Create/Edit LiveView

**Files:**
- Modify: `lib/pinventory_web/live/edit_item_live.ex`
- Test: `test/pinventory_web/live/edit_item_live_test.exs`

- [ ] **Step 1: Write failing LiveView tests**

Create `test/pinventory_web/live/edit_item_live_test.exs`:

```elixir
defmodule PinventoryWeb.EditItemLiveTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Pinventory.InventorySpaces
  alias Pinventory.Items

  test "creates an item", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/item")

    view
    |> form("#item-form", item: %{name: "Cans of tuna"})
    |> render_submit()

    assert_redirected(view, ~p"/")
  end

  test "shows duplicate item errors", %{conn: conn} do
    space = InventorySpaces.get_default_space!()
    assert {:ok, _item} = Items.create_item(space, %{name: "Cans of tuna"})

    {:ok, view, _html} = live(conn, ~p"/item")

    html =
      view
      |> form("#item-form", item: %{name: "Cans of tuna"})
      |> render_submit()

    assert html =~ "already exists"
  end
end
```

- [ ] **Step 2: Run tests to verify failures**

Run: `mix test test/pinventory_web/live/edit_item_live_test.exs`
Expected: fail because the LiveView is a placeholder.

- [ ] **Step 3: Implement form render and events**

Update `lib/pinventory_web/live/edit_item_live.ex` to load default space, render a form, validate, and save through `Items`:

```elixir
alias Pinventory.InventorySpaces
alias Pinventory.Items.Item

def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash}>
    <.header>
      {@page_title}
      <:subtitle>Name the item the way you think about it, including any unit wording.</:subtitle>
    </.header>

    <.form id="item-form" for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
      <.input field={@form[:name]} label="Item name" placeholder="Cans of tuna" autocomplete="off" />
      <div :if={@duplicate_item} id="duplicate-item" class="rounded-lg border border-warning/30 bg-warning/10 p-3 text-sm">
        An item named {@duplicate_item.name} already exists.
        <.link navigate={~p"/item/#{@duplicate_item.id}"} class="font-semibold underline">Open it</.link>
      </div>
      <div class="flex flex-col gap-2 sm:flex-row sm:justify-end">
        <.button navigate={~p"/"}>Cancel</.button>
        <.button variant="primary" type="submit">Save item</.button>
      </div>
    </.form>
  </Layouts.app>
  """
end
```

Implement `mount/3`, scoped `handle_params/3`, `handle_event("validate", ...)`, and `handle_event("save", ...)` using `InventorySpaces.get_default_space!/0`, `Items.change_item/3`, `Items.create_item/2`, and `Items.update_item/3`.

- [ ] **Step 4: Run tests**

Run: `mix test test/pinventory_web/live/edit_item_live_test.exs`
Expected: pass after selectors and duplicate wording match implementation.

- [ ] **Step 5: Review checkpoint**

Run: `mix format`
Run: `mix test test/pinventory_web/live/edit_item_live_test.exs`
Run relevant code-review skills before continuing.

## Task 5: Complete Locations LiveView

**Files:**
- Modify: `lib/pinventory_web/live/locations_live.ex`
- Test: `test/pinventory_web/live/locations_live_test.exs`

- [ ] **Step 1: Write failing LiveView tests**

Create `test/pinventory_web/live/locations_live_test.exs`:

```elixir
defmodule PinventoryWeb.LocationsLiveTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "creates a location", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    html =
      view
      |> form("#location-new", location: %{name: "Pantry"})
      |> render_submit()

    assert html =~ "Pantry"
    assert has_element?(view, "#locations")
  end

  test "shows duplicate location errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    view |> form("#location-new", location: %{name: "Pantry"}) |> render_submit()

    html =
      view
      |> form("#location-new", location: %{name: "Pantry"})
      |> render_submit()

    assert html =~ "has already been taken"
  end
end
```

- [ ] **Step 2: Run tests to verify failures**

Run: `mix test test/pinventory_web/live/locations_live_test.exs`
Expected: fail because save handling is commented out and unscoped.

- [ ] **Step 3: Implement scoped location save handling**

Update `LocationsLive` to fetch `@space`, use `Locations.list_locations(@space)`, render stable form IDs such as `location-new` and `location-<id>`, and implement `save` for create/update through `Locations.create_location/2` and `Locations.update_location/3`.

Use this row shape:

```elixir
<.form
  for={@location}
  id={@id}
  class="grid gap-2 rounded-lg border border-base-300 bg-base-100 p-3 sm:grid-cols-[1fr_auto] sm:items-start"
  phx-change="validate"
  phx-submit="save"
  phx-value-id={@location.data.id || "new"}
>
  <.input type="text" field={@location[:name]} placeholder="Pantry" wrapperclass="mb-0" />
  <.button variant="primary" type="submit">
    <%= if @location.data.id == nil do %>Add<% else %>Save<% end %>
  </.button>
</.form>
```

- [ ] **Step 4: Run tests**

Run: `mix test test/pinventory_web/live/locations_live_test.exs`
Expected: pass.

- [ ] **Step 5: Review checkpoint**

Run: `mix format`
Run: `mix test test/pinventory_web/live/locations_live_test.exs`
Run relevant code-review skills before continuing.

## Task 6: Inventory Search, Location Filter, And Quantity UI

**Files:**
- Modify: `lib/pinventory_web/live/items_live.ex`
- Create: `lib/pinventory_web/live/items_live/inventory_components.ex`
- Test: `test/pinventory_web/live/items_live_test.exs`

- [ ] **Step 1: Write failing inventory UI tests**

Create `test/pinventory_web/live/items_live_test.exs`:

```elixir
defmodule PinventoryWeb.ItemsLiveTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Pinventory.InventorySpaces
  alias Pinventory.Items
  alias Pinventory.Locations

  setup do
    space = InventorySpaces.get_default_space!()
    {:ok, pantry} = Locations.create_location(space, %{name: "Pantry"})
    {:ok, closet} = Locations.create_location(space, %{name: "Closet"})
    {:ok, tuna} = Items.create_item(space, %{name: "Cans of tuna"})
    {:ok, towels} = Items.create_item(space, %{name: "Paper towels"})
    {:ok, _} = Items.add_quantity(space, tuna, pantry, 4)
    {:ok, _} = Items.add_quantity(space, towels, closet, 2)

    %{pantry: pantry, closet: closet, tuna: tuna, towels: towels}
  end

  test "filters inventory by search", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_change(view, "search", %{"q" => "tuna", "location" => ""})

    assert html =~ "Cans of tuna"
    refute html =~ "Paper towels"
  end

  test "adds and removes quantity from a row", %{conn: conn, tuna: tuna, pantry: pantry} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#quantity-add-#{tuna.id}-#{pantry.id}", quantity: %{amount: "2"})
    |> render_submit()

    assert render(view) =~ "6"

    view
    |> form("#quantity-remove-#{tuna.id}-#{pantry.id}", quantity: %{amount: "1"})
    |> render_submit()

    assert render(view) =~ "5"
  end

  test "moves quantity between locations", %{conn: conn, tuna: tuna, pantry: pantry, closet: closet} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#quantity-move-#{tuna.id}-#{pantry.id}", move: %{to_location_id: closet.id, amount: "3"})
    |> render_submit()

    html = render(view)
    assert html =~ "Pantry"
    assert html =~ "Closet"
  end
end
```

- [ ] **Step 2: Run tests to verify failures**

Run: `mix test test/pinventory_web/live/items_live_test.exs`
Expected: fail because the inventory screen does not render these forms or apply filters.

- [ ] **Step 3: Implement inventory screen assigns and filtering**

In `ItemsLive`, fetch the default space, locations, query params, and stream reset on params:

```elixir
def handle_params(params, _uri, socket) do
  space = socket.assigns[:space] || InventorySpaces.get_default_space!()
  opts = query_opts(params)
  items = Items.list_items(space, opts)
  locations = Locations.list_locations(space)

  socket =
    socket
    |> assign(:space, space)
    |> assign(:locations, locations)
    |> assign(:query, to_form(params))
    |> assign(:empty_items?, items == [])
    |> stream(:items, items, reset: true)

  {:noreply, socket}
end
```

- [ ] **Step 4: Create focused inventory function components**

Create `lib/pinventory_web/live/items_live/inventory_components.ex` for markup-heavy inventory pieces. Keep event names and form IDs owned by `ItemsLive`; the component module should only render data and forms.

```elixir
defmodule PinventoryWeb.ItemsLive.InventoryComponents do
  use PinventoryWeb, :html

  attr :id, :string, required: true
  attr :item, :any, required: true
  attr :locations, :list, required: true

  def item_card(assigns) do
    ~H"""
    <article id={@id} class="rounded-xl border border-base-300 bg-base-100 p-3 shadow-sm">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.link navigate={~p"/item/#{@item.id}"} class="font-semibold hover:underline">{@item.name}</.link>
          <p class="text-sm text-base-content/60">{total_quantity(@item)} total</p>
        </div>
        <div class="grid gap-2 sm:min-w-80">
          <%= for item_location <- @item.item_locations do %>
            <.quantity_row item={@item} item_location={item_location} locations={@locations} />
          <% end %>
        </div>
      </div>
    </article>
    """
  end

  attr :item, :any, required: true
  attr :item_location, :any, required: true
  attr :locations, :list, required: true

  def quantity_row(assigns) do
    ~H"""
    <div class="grid gap-2 rounded-lg bg-base-200 p-2 sm:grid-cols-[1fr_auto] sm:items-center">
      <div class="text-sm">
        <span class="font-medium">{@item_location.location.name}</span>: {@item_location.quantity}
      </div>
      <div class="flex flex-wrap gap-2 sm:justify-end">
        <.quantity_form id={"quantity-add-#{@item.id}-#{@item_location.location_id}"} event="add_quantity" />
        <.quantity_form id={"quantity-remove-#{@item.id}-#{@item_location.location_id}"} event="remove_quantity" />
        <.move_form item={@item} item_location={@item_location} locations={@locations} />
      </div>
    </div>
    """
  end
end
```

Add private helpers in the same module for `quantity_form/1`, `move_form/1`, and `total_quantity/1` rather than putting that markup into `ItemsLive`. Import this component module in `ItemsLive` with `import PinventoryWeb.ItemsLive.InventoryComponents`.

- [ ] **Step 5: Implement responsive render**

Use compact desktop rows and stacked mobile controls. Keep desktop controls proportional; do not make all buttons oversized.

Key page-shell structure in `ItemsLive`:

```elixir
<.form id="inventory-filter" for={@query} class="grid gap-2 sm:grid-cols-[1fr_14rem]" phx-change="search" phx-submit="search">
  <.input type="search" field={@query[:q]} wrapperclass="mb-0" placeholder="Search items" />
  <.input type="select" field={@query[:location]} wrapperclass="mb-0" prompt="All locations" options={Enum.map(@locations, &{&1.name, &1.id})} />
</.form>

<div id="items" class="space-y-2" phx-update="stream">
  <.item_card :for={{id, item} <- @streams.items} id={id} item={item} locations={@locations} />
</div>
```

- [ ] **Step 6: Implement quantity event handlers**

Add `handle_event("add_quantity", ...)`, `handle_event("remove_quantity", ...)`, and `handle_event("move_quantity", ...)` that parse positive integer amounts, call the `Items` context, put clear flash errors on invalid or insufficient stock, and refresh the stream.

- [ ] **Step 7: Run tests**

Run: `mix test test/pinventory_web/live/items_live_test.exs`
Expected: pass.

- [ ] **Step 8: Review checkpoint**

Run: `mix format`
Run: `mix test test/pinventory_web/live/items_live_test.exs`
Run relevant code-review skills before continuing.

## Task 7: Full Regression And Polish

**Files:**
- Modify only files needed to fix failures found by checks.

- [ ] **Step 1: Run all tests**

Run: `mix test`
Expected: pass.

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: compile with warnings as errors, unused dependency check, formatting, and tests all pass.

- [ ] **Step 3: Run code-review skills**

Run `thermo-nuclear-code-quality-review` on pending changes, plus a focused code review for correctness. Fix only high-confidence findings that directly affect this feature.

- [ ] **Step 4: Manual UI smoke test**

Run: `mix phx.server`

In the browser:
- Visit `/locations`, create `Pantry` and `Closet`, verify duplicate `Pantry` shows an error.
- Visit `/item`, create `Cans of tuna`, verify duplicate creation guides to the existing item.
- Visit `/`, verify search filters by `tuna`.
- Add quantity to `Pantry`, remove part of it, try removing too much, and verify quantity never goes below zero.
- Move quantity from `Pantry` to `Closet`, verify both displayed quantities update.
- Check desktop width for compact controls and mobile width for stacked usable controls.

- [ ] **Step 5: Final status**

Report changed files, tests run, review findings fixed, and any residual risks. Do not commit, stage, push, or create a PR unless the user explicitly asks.

## Self-Review Notes

- Spec coverage: hidden inventory spaces, scoped uniqueness, item create/edit, location create/edit, search/filtering, add/remove quantity, move quantity, duplicate handling, and tests are all covered.
- Placeholder scan: no deferred implementation sections. The inventory render step intentionally leaves form markup placement as a local implementation detail, but stable form IDs and required handlers are specified.
- Type consistency: context APIs consistently pass `space` first and use `create_item`, `update_item`, `list_items`, `create_location`, `update_location`, `list_locations`, `add_quantity`, `remove_quantity`, and `move_quantity`.
