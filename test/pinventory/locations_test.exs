defmodule Pinventory.LocationsTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.Items
  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  describe "list/0" do
    test "returns locations ordered by name" do
      {:ok, _} = Locations.create(%{name: "Zebra"})
      {:ok, _} = Locations.create(%{name: "Alpha"})

      assert Enum.map(Locations.list(), & &1.name) == ["Alpha", "Zebra"]
    end
  end

  describe "list_with_item_counts/0" do
    test "returns item_count as distinct item types per location" do
      {:ok, garage} = Locations.create(%{name: "Garage"})
      {:ok, shelf} = Locations.create(%{name: "Shelf"})

      {:ok, _} = Items.create_item(%{name: "Hammer"}, %{garage.id => 2, shelf.id => 1})
      {:ok, _} = Items.create_item(%{name: "Nails"}, %{garage.id => 10})

      counts =
        Locations.list_with_item_counts()
        |> Map.new(&{&1.name, &1.item_count})

      assert counts == %{"Garage" => 2, "Shelf" => 1}
    end

    test "returns zero when a location has no items" do
      {:ok, empty} = Locations.create(%{name: "Empty"})

      [location] = Locations.list_with_item_counts()

      assert location.id == empty.id
      assert location.item_count == 0
    end

    test "orders by name" do
      {:ok, _} = Locations.create(%{name: "Zeta"})
      {:ok, _} = Locations.create(%{name: "Beta"})

      assert Enum.map(Locations.list_with_item_counts(), & &1.name) == ["Beta", "Zeta"]
    end
  end

  describe "create/1" do
    test "creates a location with a valid name" do
      assert {:ok, %Location{name: "Workshop"}} = Locations.create(%{name: "Workshop"})
    end

    test "rejects a blank name" do
      assert {:error, changeset} = Locations.create(%{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects a duplicate name" do
      assert {:ok, _} = Locations.create(%{name: "Garage"})
      assert {:error, changeset} = Locations.create(%{name: "Garage"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update/2" do
    test "renames a location" do
      {:ok, location} = Locations.create(%{name: "Old"})

      assert {:ok, %Location{name: "New"}} = Locations.update(location, %{name: "New"})
    end

    test "rejects a duplicate name on update" do
      {:ok, _} = Locations.create(%{name: "Taken"})
      {:ok, location} = Locations.create(%{name: "Free"})

      assert {:error, changeset} = Locations.update(location, %{name: "Taken"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end
end
