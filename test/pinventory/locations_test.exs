defmodule Pinventory.LocationsTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.Items
  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  import Pinventory.AccountsFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "list/0" do
    test "returns locations ordered by name", %{scope: scope} do
      {:ok, _} = Locations.create(scope, %{name: "Zebra"})
      {:ok, _} = Locations.create(scope, %{name: "Alpha"})

      assert Enum.map(Locations.list(), & &1.name) == ["Alpha", "Zebra"]
    end
  end

  describe "list_with_item_counts/0" do
    test "returns item_count as distinct item types per location", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      {:ok, _} = Items.create_item(scope, %{name: "Hammer"}, %{garage.id => 2, shelf.id => 1})
      {:ok, _} = Items.create_item(scope, %{name: "Nails"}, %{garage.id => 10})

      counts =
        Locations.list_with_item_counts()
        |> Map.new(&{&1.name, &1.item_count})

      assert counts == %{"Garage" => 2, "Shelf" => 1}
    end

    test "returns zero when a location has no items", %{scope: scope} do
      {:ok, empty} = Locations.create(scope, %{name: "Empty"})

      [location] = Locations.list_with_item_counts()

      assert location.id == empty.id
      assert location.item_count == 0
    end

    test "orders by name", %{scope: scope} do
      {:ok, _} = Locations.create(scope, %{name: "Zeta"})
      {:ok, _} = Locations.create(scope, %{name: "Beta"})

      assert Enum.map(Locations.list_with_item_counts(), & &1.name) == ["Beta", "Zeta"]
    end
  end

  describe "create/2" do
    test "creates a location with a valid name", %{scope: scope} do
      assert {:ok, %Location{name: "Workshop"}} = Locations.create(scope, %{name: "Workshop"})
    end

    test "rejects a blank name", %{scope: scope} do
      assert {:error, changeset} = Locations.create(scope, %{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects a duplicate name", %{scope: scope} do
      assert {:ok, _} = Locations.create(scope, %{name: "Garage"})
      assert {:error, changeset} = Locations.create(scope, %{name: "Garage"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update/2" do
    test "renames a location", %{scope: scope} do
      {:ok, location} = Locations.create(scope, %{name: "Old"})

      assert {:ok, %Location{name: "New"}} = Locations.update(scope, location, %{name: "New"})
    end

    test "rejects a duplicate name on update", %{scope: scope} do
      {:ok, _} = Locations.create(scope, %{name: "Taken"})
      {:ok, location} = Locations.create(scope, %{name: "Free"})

      assert {:error, changeset} = Locations.update(scope, location, %{name: "Taken"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end
end
