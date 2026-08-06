defmodule Pinventory.ItemsTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.Items
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations
  alias Pinventory.Repo

  describe "create_item/2" do
    test "creates an item with a name only" do
      assert {:ok, %Item{name: "Hammer"}} = Items.create_item(%{name: "Hammer"})
    end

    test "returns an ItemLocation changeset when stock references a missing location" do
      fake_location_id = Ecto.UUID.generate()

      assert {:error, changeset} =
               Items.create_item(%{name: "Orphan"}, %{fake_location_id => 1})

      assert %Ecto.Changeset{
               data: %ItemLocation{item_id: item_id, location_id: ^fake_location_id}
             } = changeset

      assert is_binary(item_id)
      assert errors_on(changeset) == %{location_id: ["does not exist"]}

      assert Items.list_items() == []
    end

    test "stores only positive stock rows" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, shelf} = Locations.create(%{name: "Shelf"})

      assert {:ok, item} =
               Items.create_item(%{name: "Screws"}, %{
                 garage.id => 5,
                 shelf.id => 0
               })

      stock = Items.stock_map(item)

      assert stock == %{garage.id => 5}
      assert Repo.aggregate(ItemLocation, :count) == 1
    end

    test "rejects a blank name" do
      assert {:error, changeset} = Items.create_item(%{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects a duplicate name" do
      assert {:ok, _} = Items.create_item(%{name: "Drill"})
      assert {:error, changeset} = Items.create_item(%{name: "Drill"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update_item/3" do
    test "renames an item and syncs stock" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, shelf} = Locations.create(%{name: "Shelf"})
      {:ok, item} = Items.create_item(%{name: "Nails"}, %{garage.id => 10})

      assert {:ok, updated} =
               Items.update_item(item, %{name: "Box Nails"}, %{
                 garage.id => 0,
                 shelf.id => 4
               })

      assert updated.name == "Box Nails"
      assert Items.stock_map(updated) == %{shelf.id => 4}
      assert Repo.aggregate(ItemLocation, :count) == 1
    end

    test "clears all stock when every quantity is zero" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, item} = Items.create_item(%{name: "Tape"}, %{garage.id => 2})

      assert {:ok, updated} = Items.update_item(item, %{name: "Tape"}, %{garage.id => 0})

      assert Items.stock_map(updated) == %{}
      assert Repo.aggregate(ItemLocation, :count) == 0
    end

    test "returns an ItemLocation changeset when stock references a missing location" do
      {:ok, item} = Items.create_item(%{name: "Kept"})
      fake_location_id = Ecto.UUID.generate()

      assert {:error, changeset} =
               Items.update_item(item, %{name: "Kept"}, %{fake_location_id => 1})

      assert %Ecto.Changeset{
               data: %ItemLocation{item_id: item_id, location_id: ^fake_location_id}
             } = changeset

      assert item_id == item.id
      assert errors_on(changeset) == %{location_id: ["does not exist"]}
      assert Items.get_item!(item.id).name == "Kept"
      assert Items.stock_map(Items.get_item!(item.id)) == %{}
    end
  end

  describe "get_item!/1" do
    test "preloads item_locations" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, item} = Items.create_item(%{name: "Level"}, %{garage.id => 1})

      loaded = Items.get_item!(item.id)

      assert Ecto.assoc_loaded?(loaded.item_locations)
      assert hd(loaded.item_locations).quantity == 1
    end
  end

  describe "suggest_items/1" do
    test "returns empty list for blank or whitespace-only queries" do
      assert {:ok, _} = Items.create_item(%{name: "Hammer"})

      assert Items.suggest_items("") == []
      assert Items.suggest_items("   ") == []
      assert Items.suggest_items("\t\n") == []
    end

    test "returns matching items by prefix" do
      assert {:ok, _} = Items.create_item(%{name: "Phillips screwdriver"})
      assert {:ok, _} = Items.create_item(%{name: "Flat screwdriver"})
      assert {:ok, _} = Items.create_item(%{name: "Hammer"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert "Phillips screwdriver" in names
      assert "Flat screwdriver" in names
      refute "Hammer" in names
    end

    test "treats LIKE/FTS special characters in the query as literals" do
      assert {:ok, _} = Items.create_item(%{name: "100% wool"})
      assert {:ok, _} = Items.create_item(%{name: "100x wool"})
      assert {:ok, _} = Items.create_item(%{name: "under_score"})
      assert {:ok, _} = Items.create_item(%{name: "path\\to"})
      assert {:ok, _} = Items.create_item(%{name: "plain item"})
      assert {:ok, _} = Items.create_item(%{name: "quote\"mark"})

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

    test "matches short prefixes with LIKE fallback" do
      assert {:ok, _} = Items.create_item(%{name: "Saw"})
      assert {:ok, _} = Items.create_item(%{name: "Sandpaper"})
      assert {:ok, _} = Items.create_item(%{name: "Hammer"})

      names = Enum.map(Items.suggest_items("sa"), & &1.name)

      assert "Sandpaper" in names
      assert "Saw" in names
      refute "Hammer" in names
    end

    test "ranks prefix matches above non-prefix contains" do
      assert {:ok, _} = Items.create_item(%{name: "Phillips screwdriver set"})
      assert {:ok, _} = Items.create_item(%{name: "Screwdriver"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert names == ["Screwdriver", "Phillips screwdriver set"]
    end

    test "ranks prefix matches above non-prefix contains for short LIKE queries" do
      assert {:ok, _} = Items.create_item(%{name: "Saw"})
      assert {:ok, _} = Items.create_item(%{name: "Handsaw"})

      names = Enum.map(Items.suggest_items("sa"), & &1.name)

      assert names == ["Saw", "Handsaw"]
    end

    test "matches mixed-case queries case-insensitively for ASCII" do
      assert {:ok, _} = Items.create_item(%{name: "Hex Bolt"})
      assert {:ok, _} = Items.create_item(%{name: "Hammer"})

      names = Enum.map(Items.suggest_items("HEX"), & &1.name)

      assert names == ["Hex Bolt"]
    end

    test "rename updates FTS so old name no longer matches" do
      assert {:ok, item} = Items.create_item(%{name: "Old Widget"})

      assert Enum.map(Items.suggest_items("old"), & &1.name) == ["Old Widget"]

      assert {:ok, _} = Items.update_item(item, %{name: "New Gadget"}, %{})

      refute "Old Widget" in Enum.map(Items.suggest_items("old"), & &1.name)
      assert Enum.map(Items.suggest_items("new"), & &1.name) == ["New Gadget"]
      assert Enum.map(Items.suggest_items("gadget"), & &1.name) == ["New Gadget"]
    end

    test "delete removes the item from FTS results" do
      assert {:ok, item} = Items.create_item(%{name: "Disposable Widget"})

      assert Enum.map(Items.suggest_items("disposable"), & &1.name) == ["Disposable Widget"]

      assert {:ok, _} = Items.delete_item(item)

      assert Items.suggest_items("disposable") == []
    end
  end

  describe "list_items/1" do
    test "returns stock totals and location counts" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, shelf} = Locations.create(%{name: "Shelf"})

      assert {:ok, _} =
               Items.create_item(%{name: "Screws"}, %{garage.id => 5, shelf.id => 3})

      assert {:ok, _} = Items.create_item(%{name: "Empty Box"})

      by_name = Map.new(Items.list_items(), &{&1.name, &1})

      assert by_name["Screws"].total_quantity == 8
      assert by_name["Screws"].location_count == 2
      assert by_name["Empty Box"].total_quantity == 0
      assert by_name["Empty Box"].location_count == 0
    end

    test "filters by name substring" do
      assert {:ok, _} = Items.create_item(%{name: "Box Nails"})
      assert {:ok, _} = Items.create_item(%{name: "Hammer"})

      names = Enum.map(Items.list_items(filter: "nail"), & &1.name)

      assert names == ["Box Nails"]
    end

    test "trims whitespace-only filter to no filter" do
      assert {:ok, _} = Items.create_item(%{name: "Alpha"})
      assert {:ok, _} = Items.create_item(%{name: "Beta"})

      names = Enum.map(Items.list_items(filter: "   "), & &1.name)

      assert names == ["Alpha", "Beta"]
    end

    test "filters by location with stock" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, shelf} = Locations.create(%{name: "Shelf"})

      assert {:ok, _} = Items.create_item(%{name: "Drill"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(%{name: "Tape"}, %{shelf.id => 2})
      assert {:ok, _} = Items.create_item(%{name: "Empty"})

      names = Enum.map(Items.list_items(location_id: garage.id), & &1.name)

      assert names == ["Drill"]
    end

    test "orders items by name" do
      assert {:ok, _} = Items.create_item(%{name: "Zebra"})
      assert {:ok, _} = Items.create_item(%{name: "Apple"})

      assert Enum.map(Items.list_items(), & &1.name) == ["Apple", "Zebra"]
    end
  end
end
