defmodule Pinventory.ItemsTest do
  use Pinventory.DataCase, async: true

  alias Pinventory.Items
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations
  alias Pinventory.Repo

  describe "create_item/2" do
    test "creates an item with a name only" do
      assert {:ok, %Item{name: "Hammer"}} = Items.create_item(%{name: "Hammer"})
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
    test "returns matching items by prefix" do
      assert {:ok, _} = Items.create_item(%{name: "Phillips screwdriver"})
      assert {:ok, _} = Items.create_item(%{name: "Flat screwdriver"})
      assert {:ok, _} = Items.create_item(%{name: "Hammer"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert "Phillips screwdriver" in names
      assert "Flat screwdriver" in names
      refute "Hammer" in names
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
