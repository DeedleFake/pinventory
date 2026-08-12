defmodule Pinventory.AuditTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.Audit
  alias Pinventory.Audit.Event
  alias Pinventory.Items
  alias Pinventory.Locations
  alias Pinventory.Repo

  import Pinventory.AccountsFixtures

  setup do
    scope = user_scope_fixture()
    %{scope: scope, user: scope.user}
  end

  describe "item create/update/delete audit" do
    test "create records item.created and stock.changed under one edit_id", %{
      scope: scope,
      user: user
    } do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, item} =
               Items.create_item(scope, %{name: "Hammer"}, %{
                 garage.id => 3,
                 shelf.id => 0
               })

      events =
        Event
        |> where([e], e.item_id == ^item.id)
        |> order_by([e], asc: e.edit_seq)
        |> Repo.all()

      assert length(events) == 2
      assert Enum.map(events, & &1.action) == ["item.created", "stock.changed"]
      assert Enum.uniq(Enum.map(events, & &1.edit_id)) |> length() == 1
      assert Enum.all?(events, &(&1.user_id == user.id))

      [created, stock] = events
      assert created.changes == %{"name" => %{"from" => nil, "to" => "Hammer"}}
      assert created.metadata["item_name"] == "Hammer"

      assert stock.location_id == garage.id
      assert stock.changes == %{"quantity" => %{"from" => 0, "to" => 3}}
      assert stock.metadata["location_name"] == "Garage"
    end

    test "update groups rename and stock diffs under one edit_id", %{scope: scope, user: user} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
      {:ok, item} = Items.create_item(scope, %{name: "Nails"}, %{garage.id => 10})

      assert {:ok, _updated} =
               Items.update_item(scope, item, %{name: "Box Nails"}, %{
                 garage.id => 0,
                 shelf.id => 4
               })

      rename =
        Event
        |> where([e], e.item_id == ^item.id and e.action == "item.updated")
        |> Repo.one!()

      update_events =
        Event
        |> where([e], e.edit_id == ^rename.edit_id)
        |> order_by([e], asc: e.edit_seq)
        |> Repo.all()

      assert Enum.map(update_events, & &1.action) == [
               "item.updated",
               "stock.changed",
               "stock.changed"
             ]

      assert Enum.all?(update_events, &(&1.user_id == user.id))
      assert rename.changes == %{"name" => %{"from" => "Nails", "to" => "Box Nails"}}

      stock_by_loc =
        update_events
        |> Enum.filter(&(&1.action == "stock.changed"))
        |> Map.new(&{&1.location_id, &1.changes})

      assert stock_by_loc[garage.id] == %{"quantity" => %{"from" => 10, "to" => 0}}
      assert stock_by_loc[shelf.id] == %{"quantity" => %{"from" => 0, "to" => 4}}
    end

    test "delete records item.deleted with actor", %{scope: scope, user: user} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Disposable"}, %{garage.id => 2})

      assert {:ok, _} = Items.delete_item(scope, item)

      deleted =
        Event
        |> where([e], e.action == "item.deleted" and e.entity_id == ^item.id)
        |> Repo.one!()

      assert deleted.user_id == user.id
      assert deleted.metadata["item_name"] == "Disposable"
      assert deleted.item_id == item.id

      refute Repo.exists?(
               from e in Event,
                 where: e.edit_id == ^deleted.edit_id and e.action == "stock.changed"
             )
    end

    test "no-op update writes no audit events", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 2})

      count_before = Repo.aggregate(Event, :count)

      assert {:ok, _unchanged} =
               Items.update_item(scope, item, %{name: "Tape"}, %{garage.id => 2})

      assert Repo.aggregate(Event, :count) == count_before
    end

    test "stock-only update emits only stock.changed diffs", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
      {:ok, item} = Items.create_item(scope, %{name: "Bolts"}, %{garage.id => 5})

      assert {:ok, _} =
               Items.update_item(scope, item, %{name: "Bolts"}, %{
                 garage.id => 5,
                 shelf.id => 2
               })

      update_events =
        Event
        |> where([e], e.item_id == ^item.id and e.action == "stock.changed")
        |> where([e], e.location_id == ^shelf.id)
        |> Repo.all()

      assert length(update_events) == 1
      assert hd(update_events).changes == %{"quantity" => %{"from" => 0, "to" => 2}}

      refute Repo.exists?(
               from e in Event,
                 where: e.item_id == ^item.id and e.action == "item.updated"
             )
    end
  end

  describe "location audit" do
    test "create and rename write location events", %{scope: scope, user: user} do
      assert {:ok, location} = Locations.create(scope, %{name: "Workshop"})

      created =
        Event
        |> where([e], e.action == "location.created" and e.location_id == ^location.id)
        |> Repo.one!()

      assert created.user_id == user.id
      assert created.metadata["location_name"] == "Workshop"

      assert {:ok, _} = Locations.update(scope, location, %{name: "Shop"})

      updated =
        Event
        |> where([e], e.action == "location.updated" and e.location_id == ^location.id)
        |> Repo.one!()

      assert updated.changes == %{"name" => %{"from" => "Workshop", "to" => "Shop"}}
    end

    test "no-op location update writes no events", %{scope: scope} do
      {:ok, location} = Locations.create(scope, %{name: "Bin"})
      count_before = Repo.aggregate(Event, :count)

      assert {:ok, _} = Locations.update(scope, location, %{name: "Bin"})
      assert Repo.aggregate(Event, :count) == count_before
    end

    test "delete records location.deleted with actor", %{scope: scope, user: user} do
      {:ok, location} = Locations.create(scope, %{name: "Spare Bin"})

      assert {:ok, _} = Locations.delete(scope, location)

      deleted =
        Event
        |> where([e], e.action == "location.deleted" and e.entity_id == ^location.id)
        |> Repo.one!()

      assert deleted.user_id == user.id
      assert deleted.metadata["location_name"] == "Spare Bin"
      assert deleted.location_id == location.id
      assert deleted.changes == %{"name" => %{"from" => "Spare Bin", "to" => nil}}
    end

    test "refused location delete writes no events", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, _} = Items.create_item(scope, %{name: "Hammer"}, %{garage.id => 1})
      count_before = Repo.aggregate(Event, :count)

      assert {:error, :location_has_items} = Locations.delete(scope, garage)
      assert Repo.aggregate(Event, :count) == count_before
    end
  end

  describe "query helpers" do
    test "list_for_item returns item timeline", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Level"}, %{garage.id => 1})
      {:ok, _} = Items.update_item(scope, item, %{name: "Spirit Level"}, %{garage.id => 1})

      events = Audit.list_for_item(item.id)
      actions = Enum.map(events, & &1.action)

      assert "item.created" in actions
      assert "item.updated" in actions
      assert "stock.changed" in actions
      assert Enum.all?(events, &Ecto.assoc_loaded?(&1.user))
    end

    test "list_edits_for_item groups by edit_id for one item", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      {:ok, item} =
        Items.create_item(scope, %{name: "Level"}, %{garage.id => 1, shelf.id => 2})

      {:ok, other} = Items.create_item(scope, %{name: "Other"}, %{garage.id => 1})

      edits = Audit.list_edits_for_item(item.id)
      assert length(edits) == 1

      [create_edit] = edits
      assert length(create_edit.events) == 3
      assert create_edit.user.id == scope.user.id
      assert Enum.all?(create_edit.events, &(&1.item_id == item.id))
      assert Enum.all?(create_edit.events, &Ecto.assoc_loaded?(&1.user))

      # Other item's create does not appear
      refute Enum.any?(edits, fn edit ->
               Enum.any?(edit.events, &(&1.item_id == other.id))
             end)

      {:ok, item} =
        Items.update_item(scope, item, %{name: "Spirit Level"}, %{garage.id => 1, shelf.id => 2})

      edits = Audit.list_edits_for_item(item.id)
      assert length(edits) == 2

      rename_edit =
        Enum.find(edits, fn edit ->
          Enum.any?(edit.events, &(&1.action == "item.updated"))
        end)

      assert rename_edit
      assert length(rename_edit.events) == 1
    end

    test "list_recent_edits groups by edit_id", %{scope: scope} do
      {:ok, _} = Locations.create(scope, %{name: "A"})
      {:ok, garage} = Locations.create(scope, %{name: "B"})
      {:ok, item} = Items.create_item(scope, %{name: "Widget"}, %{garage.id => 2})

      edits = Audit.list_recent_edits(limit: 10)
      assert length(edits) >= 3

      widget_edit =
        Enum.find(edits, fn edit ->
          Enum.any?(edit.events, &(&1.item_id == item.id and &1.action == "item.created"))
        end)

      assert widget_edit
      assert length(widget_edit.events) == 2
      assert widget_edit.user.id == scope.user.id
    end

    test "latest_stock_changes_for_items batches without N+1 shape", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, a} = Items.create_item(scope, %{name: "Aa"}, %{garage.id => 1})
      {:ok, b} = Items.create_item(scope, %{name: "Bb"}, %{garage.id => 2})
      {:ok, c} = Items.create_item(scope, %{name: "Cc"})

      {:ok, _} = Items.update_item(scope, a, %{name: "Aa"}, %{garage.id => 9})

      map = Audit.latest_stock_changes_for_items([a.id, b.id, c.id])

      assert Map.has_key?(map, a.id)
      assert Map.has_key?(map, b.id)
      refute Map.has_key?(map, c.id)

      assert map[a.id].changes["quantity"]["to"] == 9
      assert map[b.id].changes["quantity"]["to"] == 2
      assert Ecto.assoc_loaded?(map[a.id].user)
    end
  end

  describe "audit failure aborts domain write" do
    test "invalid audit attrs roll back the item insert", %{scope: scope} do
      alias Ecto.Multi
      alias Pinventory.Items.Item
      alias Pinventory.Audit.Event

      assert {:error, :audit_events, %Ecto.Changeset{}, _} =
               Multi.new()
               |> Multi.insert(:item, Items.change_item(%Item{}, %{name: "ShouldNotPersist"}))
               |> Multi.run(:audit_events, fn repo, %{item: item} ->
                 Audit.insert_events(repo, [
                   %{
                     edit_id: Audit.new_edit_id(),
                     edit_seq: 0,
                     user_id: scope.user.id,
                     # Invalid action fails validation before/with insert
                     action: "not.a.real.action",
                     entity_type: "item",
                     entity_id: item.id,
                     item_id: item.id,
                     changes: %{},
                     metadata: %{"item_name" => item.name}
                   }
                 ])
               end)
               |> Repo.transaction()

      refute Enum.any?(Items.list_items(), &(&1.name == "ShouldNotPersist"))
      assert Repo.aggregate(Event, :count) == 0
    end
  end
end
