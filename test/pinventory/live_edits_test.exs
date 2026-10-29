defmodule Pinventory.LiveEditsTest do
  use Pinventory.DataCase, async: false

  import Pinventory.AccountsFixtures

  alias Pinventory.Items
  alias Pinventory.LiveEdits
  alias Pinventory.Locations
  alias Pinventory.NamingConvention

  setup do
    scope = user_scope_fixture()
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shed} = Locations.create(scope, %{name: "Shed"})
    {:ok, item} = Items.create_item(scope, %{name: "Milk"}, %{garage.id => 2})
    %{scope: scope, garage: garage, shed: shed, item: item}
  end

  test "every committed item write notifies the item's subscribers", %{
    scope: scope,
    garage: garage,
    shed: shed,
    item: item
  } do
    :ok = LiveEdits.subscribe({:item, item.id})
    record = {:item, item.id}

    {:ok, item} = Items.update_item(scope, item, %{name: "Oat milk"}, Items.stock_map(item))
    assert_received {LiveEdits, ^record, :saved}

    {:ok, _} = Items.change_stock(scope, item.id, garage.id, {:add, 1})
    assert_received {LiveEdits, ^record, :saved}

    {:ok, _} = Items.move_stock(scope, item.id, garage.id, shed.id, 1)
    assert_received {LiveEdits, ^record, :saved}

    {:ok, _} = Items.delete_item(scope, item)
    assert_received {LiveEdits, ^record, :deleted}
  end

  test "a refused write notifies no one", %{scope: scope, garage: garage, item: item} do
    :ok = LiveEdits.subscribe({:item, item.id})

    stock = Items.stock_map(item)
    {:ok, _} = Items.update_item(scope, item, %{notes: "Theirs"}, stock)
    assert_received {LiveEdits, _, :saved}

    assert Items.update_item(scope, item, %{notes: "Mine"}, stock) == {:error, :stale}
    assert {:error, {:below_zero, 2}} = Items.change_stock(scope, item.id, garage.id, {:add, -3})
    refute_received {LiveEdits, _, _}
  end

  test "other items' subscribers hear nothing", %{scope: scope, item: item} do
    {:ok, other} = Items.create_item(scope, %{name: "Eggs"})
    :ok = LiveEdits.subscribe({:item, other.id})

    {:ok, _} = Items.update_item(scope, item, %{notes: "Fridge"}, Items.stock_map(item))
    refute_received {LiveEdits, _, _}
  end

  test "location renames and deletes notify the location's subscribers", %{scope: scope} do
    {:ok, attic} = Locations.create(scope, %{name: "Attic"})
    :ok = LiveEdits.subscribe({:location, attic.id})
    record = {:location, attic.id}

    {:ok, renamed} = Locations.update(scope, attic, %{name: "Loft"})
    assert_received {LiveEdits, ^record, :saved}

    assert Locations.update(scope, attic, %{name: "Roof"}) == {:error, :stale}
    refute_received {LiveEdits, _, _}

    {:ok, _} = Locations.delete(scope, renamed)
    assert_received {LiveEdits, ^record, :deleted}
  end

  test "a naming convention save notifies its subscribers", %{scope: scope} do
    :ok = LiveEdits.subscribe(:naming_convention)

    {:ok, _} = NamingConvention.save(scope, NamingConvention.current().number, "New rules")
    assert_received {LiveEdits, :naming_convention, :saved}

    assert {:error, :stale, _} = NamingConvention.save(scope, 0, "Old rules")
    refute_received {LiveEdits, _, _}
  end
end
