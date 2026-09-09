defmodule Pinventory.ItemsTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.Items
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations
  alias Pinventory.Repo

  import Pinventory.AccountsFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "create_item/3" do
    test "creates an item with a name only", %{scope: scope} do
      assert {:ok, %Item{name: "Hammer"}} = Items.create_item(scope, %{name: "Hammer"})
    end

    test "returns an ItemLocation changeset when stock references a missing location", %{
      scope: scope
    } do
      fake_location_id = Ecto.UUID.generate()

      assert {:error, changeset} =
               Items.create_item(scope, %{name: "Orphan"}, %{fake_location_id => 1})

      assert %Ecto.Changeset{
               data: %ItemLocation{item_id: item_id, location_id: ^fake_location_id}
             } = changeset

      assert is_binary(item_id)
      assert errors_on(changeset) == %{location_id: ["does not exist"]}

      assert Items.list_items() == []
    end

    test "stores only positive stock rows", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, item} =
               Items.create_item(scope, %{name: "Screws"}, %{
                 garage.id => 5,
                 shelf.id => 0
               })

      stock = Items.stock_map(item)

      assert stock == %{garage.id => 5}
      assert Repo.aggregate(ItemLocation, :count) == 1
    end

    test "rejects a blank name", %{scope: scope} do
      assert {:error, changeset} = Items.create_item(scope, %{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects a duplicate name", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"})
      assert {:error, changeset} = Items.create_item(scope, %{name: "Drill"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "trims name padding on create", %{scope: scope} do
      assert {:ok, %Item{name: "Hammer"}} = Items.create_item(scope, %{name: "  Hammer  "})
    end

    test "rejects a duplicate name after trim", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"})
      assert {:error, changeset} = Items.create_item(scope, %{name: "  Drill  "})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update_item/4" do
    test "renames an item and syncs stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
      {:ok, item} = Items.create_item(scope, %{name: "Nails"}, %{garage.id => 10})

      assert {:ok, updated} =
               Items.update_item(scope, item, %{name: "Box Nails"}, %{
                 garage.id => 0,
                 shelf.id => 4
               })

      assert updated.name == "Box Nails"
      assert Items.stock_map(updated) == %{shelf.id => 4}
      assert Repo.aggregate(ItemLocation, :count) == 1
    end

    test "clears all stock when every quantity is zero", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 2})

      assert {:ok, updated} = Items.update_item(scope, item, %{name: "Tape"}, %{garage.id => 0})

      assert Items.stock_map(updated) == %{}
      assert Repo.aggregate(ItemLocation, :count) == 0
    end

    test "returns an ItemLocation changeset when stock references a missing location", %{
      scope: scope
    } do
      {:ok, item} = Items.create_item(scope, %{name: "Kept"})
      fake_location_id = Ecto.UUID.generate()

      assert {:error, changeset} =
               Items.update_item(scope, item, %{name: "Kept"}, %{fake_location_id => 1})

      assert %Ecto.Changeset{
               data: %ItemLocation{item_id: item_id, location_id: ^fake_location_id}
             } = changeset

      assert item_id == item.id
      assert errors_on(changeset) == %{location_id: ["does not exist"]}
      assert Items.get_item!(item.id).name == "Kept"
      assert Items.stock_map(Items.get_item!(item.id)) == %{}
    end
  end

  describe "get_item/1" do
    test "returns nil when the item does not exist" do
      assert Items.get_item(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_item!/1" do
    test "preloads item_locations", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Level"}, %{garage.id => 1})

      loaded = Items.get_item!(item.id)

      assert Ecto.assoc_loaded?(loaded.item_locations)
      assert hd(loaded.item_locations).quantity == 1
    end
  end

  describe "suggest_items/1" do
    test "returns empty list for blank or whitespace-only queries", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      assert Items.suggest_items("") == []
      assert Items.suggest_items("   ") == []
      assert Items.suggest_items("\t\n") == []
    end

    test "returns matching items by prefix", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Phillips screwdriver"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Flat screwdriver"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert "Phillips screwdriver" in names
      assert "Flat screwdriver" in names
      refute "Hammer" in names
    end

    test "treats LIKE/FTS special characters in the query as literals", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "100% wool"})
      assert {:ok, _} = Items.create_item(scope, %{name: "100x wool"})
      assert {:ok, _} = Items.create_item(scope, %{name: "under_score"})
      assert {:ok, _} = Items.create_item(scope, %{name: "path\\to"})
      assert {:ok, _} = Items.create_item(scope, %{name: "plain item"})
      assert {:ok, _} = Items.create_item(scope, %{name: "quote\"mark"})

      # Short query (< 3 chars) uses LIKE with escaping; "%" is not a wildcard.
      percent_only = Enum.map(Items.suggest_items("%"), & &1.name)
      assert percent_only == ["100% wool"]

      # Longer query uses FTS5; special chars are phrase-escaped, not wildcards.
      percent_names = Enum.map(Items.suggest_items("100%"), & &1.name)
      assert "100% wool" in percent_names
      refute "100x wool" in percent_names

      underscore_names = Enum.map(Items.suggest_items("under_score"), & &1.name)
      assert "under_score" in underscore_names

      slash_names = Enum.map(Items.suggest_items("path\\t"), & &1.name)
      assert "path\\to" in slash_names
      refute "plain item" in slash_names

      quote_names = Enum.map(Items.suggest_items("quote\"m"), & &1.name)
      assert "quote\"mark" in quote_names
    end

    test "matches short prefixes with LIKE fallback", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Saw"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Sandpaper"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.suggest_items("sa"), & &1.name)

      assert "Sandpaper" in names
      assert "Saw" in names
      refute "Hammer" in names
    end

    test "ranks prefix matches above non-prefix contains", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Phillips screwdriver set"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Screwdriver"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert names == ["Screwdriver", "Phillips screwdriver set"]
    end

    test "ranks prefix matches above non-prefix contains for short LIKE queries", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Saw"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Handsaw"})

      names = Enum.map(Items.suggest_items("sa"), & &1.name)

      assert names == ["Saw", "Handsaw"]
    end

    test "matches mixed-case queries case-insensitively for ASCII", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Hex Bolt"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.suggest_items("HEX"), & &1.name)

      assert names == ["Hex Bolt"]
    end

    test "rename updates FTS so old name no longer matches", %{scope: scope} do
      assert {:ok, item} = Items.create_item(scope, %{name: "Old Widget"})

      assert Enum.map(Items.suggest_items("old"), & &1.name) == ["Old Widget"]

      assert {:ok, _} = Items.update_item(scope, item, %{name: "New Gadget"}, %{})

      refute "Old Widget" in Enum.map(Items.suggest_items("old"), & &1.name)
      assert Enum.map(Items.suggest_items("new"), & &1.name) == ["New Gadget"]
      assert Enum.map(Items.suggest_items("gadget"), & &1.name) == ["New Gadget"]
    end

    test "delete removes the item from FTS results", %{scope: scope} do
      assert {:ok, item} = Items.create_item(scope, %{name: "Disposable Widget"})

      assert Enum.map(Items.suggest_items("disposable"), & &1.name) == ["Disposable Widget"]

      assert {:ok, _} = Items.delete_item(scope, item)

      assert Items.suggest_items("disposable") == []
    end
  end

  describe "delete_item/2" do
    test "deletes the item and cascaded stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Disposable"}, %{garage.id => 4})

      assert {:ok, _} = Items.delete_item(scope, item)
      assert_raise Ecto.NoResultsError, fn -> Items.get_item!(item.id) end
      assert Repo.get_by(ItemLocation, item_id: item.id) == nil
    end
  end

  describe "list_items/1" do
    test "returns stock totals and location counts", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, _} =
               Items.create_item(scope, %{name: "Screws"}, %{garage.id => 5, shelf.id => 3})

      assert {:ok, _} = Items.create_item(scope, %{name: "Empty Box"})

      by_name = Map.new(Items.list_items(), &{&1.name, &1})

      assert by_name["Screws"].total_quantity == 8
      assert by_name["Screws"].location_count == 2
      assert by_name["Empty Box"].total_quantity == 0
      assert by_name["Empty Box"].location_count == 0
    end

    test "filters by name substring", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Box Nails"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.list_items(filter: "nail"), & &1.name)

      assert names == ["Box Nails"]
    end

    test "trims whitespace-only filter to no filter", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Alpha"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Beta"})

      names = Enum.map(Items.list_items(filter: "   "), & &1.name)

      assert names == ["Alpha", "Beta"]
    end

    test "filters by location with stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(scope, %{name: "Tape"}, %{shelf.id => 2})
      assert {:ok, _} = Items.create_item(scope, %{name: "Empty"})

      names = Enum.map(Items.list_items(location_id: garage.id), & &1.name)

      assert names == ["Drill"]
    end

    test "orders items by name", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Zebra"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Apple"})

      assert Enum.map(Items.list_items(), & &1.name) == ["Apple", "Zebra"]
    end
  end

  describe "list_items_at_location/1" do
    test "returns quantity at this location only", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, item} =
               Items.create_item(scope, %{name: "Screws"}, %{garage.id => 2, shelf.id => 5})

      [at_garage] = Items.list_items_at_location(garage.id)

      assert at_garage.id == item.id
      assert at_garage.quantity == 2

      [filtered] = Items.list_items(location_id: garage.id)
      assert filtered.total_quantity == 7
    end

    test "excludes items with no stock at the location", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(scope, %{name: "Tape"}, %{shelf.id => 2})
      assert {:ok, _} = Items.create_item(scope, %{name: "Empty"})

      names = Enum.map(Items.list_items_at_location(garage.id), & &1.name)

      assert names == ["Drill"]
    end

    test "orders items by name", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})

      assert {:ok, _} = Items.create_item(scope, %{name: "Zebra"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(scope, %{name: "Apple"}, %{garage.id => 1})

      assert Enum.map(Items.list_items_at_location(garage.id), & &1.name) == [
               "Apple",
               "Zebra"
             ]
    end

    test "returns an empty list for a location with no stock", %{scope: scope} do
      {:ok, empty} = Locations.create(scope, %{name: "Empty"})

      assert Items.list_items_at_location(empty.id) == []
    end
  end
end
