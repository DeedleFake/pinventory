defmodule PinventoryWeb.LocationLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pinventory.Items
  alias Pinventory.Locations

  setup :register_and_log_in_user

  test "redirects unauthenticated users to log in" do
    conn = build_conn()
    location_id = Ecto.UUID.generate()

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/location/#{location_id}")
    assert path == ~p"/user/log-in"
  end

  test "renders the location name, total, and items", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

    {:ok, drill} =
      Items.create_item(scope, %{name: "Drill"}, %{garage.id => 3, shelf.id => 7})

    {:ok, nails} = Items.create_item(scope, %{name: "Nails"}, %{garage.id => 10})

    {:ok, view, html} = live(conn, ~p"/location/#{garage.id}")

    assert html =~ "Edit location"
    assert has_element?(view, "#location-form")
    assert has_element?(view, "#location-name-section #location-save")
    assert has_element?(view, ~s(#location_name[value="Garage"]))
    assert has_element?(view, "#location-total-value", "13")
    assert has_element?(view, "#location-item-#{drill.id}", "Drill")
    assert has_element?(view, "#location-item-#{drill.id}-quantity", "3")
    assert has_element?(view, "#location-item-#{nails.id}", "Nails")
    assert has_element?(view, "#location-item-#{nails.id}-quantity", "10")
    refute has_element?(view, "#location-item-#{drill.id}-quantity", "10")
    refute has_element?(view, "#quantity-#{garage.id}")
    refute has_element?(view, "#back-to-locations")
    assert has_element?(view, ~s|#nav-locations[aria-current="page"]|)
  end

  test "shows per-location quantity, not stock in all locations", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

    {:ok, item} =
      Items.create_item(scope, %{name: "Screws"}, %{garage.id => 2, shelf.id => 5})

    {:ok, view, _html} = live(conn, ~p"/location/#{garage.id}")

    assert has_element?(view, "#location-total-value", "2")
    assert has_element?(view, "#location-item-#{item.id}-quantity", "2")
    refute has_element?(view, "#location-item-#{item.id}-quantity", "7")
  end

  test "shows empty state when the location has no items", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Empty"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    assert has_element?(view, "#location-items-empty", "No items at this location")
    assert has_element?(view, "#location-total-value", "0")
  end

  test "item rows link to the item page", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, item} = Items.create_item(scope, %{name: "Hammer"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/location/#{garage.id}")

    assert has_element?(
             view,
             ~s|a#location-item-#{item.id}[href="/item/#{item.id}"]|,
             "Hammer"
           )

    view
    |> element("#location-item-#{item.id}")
    |> render_click()

    assert_redirect(view, "/item/#{item.id}")
  end

  test "renames a location", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Old Name"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    view
    |> form("#location-form", location: %{name: "New Name"})
    |> render_submit()

    html = render(view)
    assert html =~ "Location saved"
    assert has_element?(view, ~s(#location_name[value="New Name"]))
    assert has_element?(view, "#location-save:disabled")
    assert Locations.get!(location.id).name == "New Name"
  end

  test "shows validation errors for a blank name", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Shelf"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    html =
      view
      |> form("#location-form", location: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    assert Locations.get!(location.id).name == "Shelf"
  end

  test "shows validation errors for a duplicate name", %{conn: conn, scope: scope} do
    {:ok, _} = Locations.create(scope, %{name: "Taken"})
    {:ok, location} = Locations.create(scope, %{name: "Free"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    html =
      view
      |> form("#location-form", location: %{name: "Taken"})
      |> render_submit()

    assert html =~ "has already been taken"
    assert Locations.get!(location.id).name == "Free"
  end

  test "disables save until the name changes", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Bin"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    assert has_element?(view, "#location-save:disabled")
    assert has_element?(view, ~s(#location-name-section[data-name-dirty="false"]))

    view
    |> form("#location-form", location: %{name: "Bin A"})
    |> render_change()

    refute has_element?(view, "#location-save:disabled")
    assert has_element?(view, ~s(#location-name-section[data-name-dirty="true"]))

    view
    |> form("#location-form", location: %{name: "Bin"})
    |> render_change()

    assert has_element?(view, "#location-save:disabled")
    assert has_element?(view, ~s(#location-name-section[data-name-dirty="false"]))
  end

  test "highlights an unsaved name change", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Crate"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    refute has_element?(view, "#location-name-hint")

    view
    |> form("#location-form", location: %{name: "Crate 2"})
    |> render_change()

    assert has_element?(view, "#location-name-hint", "Unsaved name change")
    assert has_element?(view, "#location-name-hint", "Crate")
    assert has_element?(view, "#location-name-section.border-primary")
  end

  test "marks the form dirty and pushes unsaved-changes events", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Drawer"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    assert has_element?(view, ~s(#location-page[phx-hook="UnsavedChanges"][data-dirty="false"]))

    view
    |> form("#location-form", location: %{name: "Drawer 2"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})
    assert has_element?(view, ~s(#location-page[data-dirty="true"]))
    refute has_element?(view, "#location-save:disabled")

    view
    |> form("#location-form", location: %{name: "Drawer"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
    assert has_element?(view, ~s(#location-page[data-dirty="false"]))
    assert has_element?(view, "#location-save:disabled")
  end

  test "redirects when the location does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/location/#{Ecto.UUID.generate()}")

    assert path == "/locations"
    assert flash["error"] == "Location not found."
  end

  test "disables delete when the location has items", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 2})

    {:ok, view, _html} = live(conn, ~p"/location/#{garage.id}")

    assert has_element?(view, "#location-delete:disabled")
    assert has_element?(view, "#location-delete-reason", "Remove items from this location first.")
    refute has_element?(view, "#location-delete-modal")
    assert Locations.get!(garage.id).name == "Garage"
  end

  test "enables delete when the location is empty", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Empty"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    assert has_element?(view, "#location-delete")
    refute has_element?(view, "#location-delete:disabled")
    refute has_element?(view, "#location-delete-reason")
  end

  test "disables delete when the name is unsaved, even if the location has items", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/location/#{garage.id}")

    view
    |> form("#location-form", location: %{name: "Shop"})
    |> render_change()

    assert has_element?(view, "#location-delete:disabled")
    assert has_element?(view, "#location-delete-reason", "Save or revert the name first.")
    refute has_element?(view, "#location-delete-reason", "Remove items from this location first.")
  end

  test "disables delete when an empty location name is unsaved", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Bin"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> form("#location-form", location: %{name: "Bin 2"})
    |> render_change()

    assert has_element?(view, "#location-delete:disabled")
    assert has_element?(view, "#location-delete-reason", "Save or revert the name first.")
    refute has_element?(view, "#location-delete-modal")
  end

  test "opens a name-confirm modal and deletes an empty location", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Spare Room"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> element("#location-delete")
    |> render_click()

    assert has_element?(view, "#location-delete-modal")
    assert has_element?(view, "#location-delete-form")
    assert has_element?(view, "#location-delete-impact", "Spare Room")
    assert has_element?(view, ~s(#location-delete-confirm[autocomplete="off"]))
    assert has_element?(view, ~s(#location-delete-confirm[spellcheck="false"]))
    assert has_element?(view, "#location-delete-confirm-submit:disabled")

    view
    |> form("#location-delete-form", delete: %{name: "Spare"})
    |> render_change()

    assert has_element?(view, "#location-delete-confirm-submit:disabled")

    view
    |> form("#location-delete-form", delete: %{name: "Spare Room"})
    |> render_change()

    refute has_element?(view, "#location-delete-confirm-submit:disabled")

    view
    |> form("#location-delete-form", delete: %{name: "Spare Room"})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/locations"
    assert flash["info"] == "Location deleted"

    assert_raise Ecto.NoResultsError, fn -> Locations.get!(empty.id) end

    deleted =
      Pinventory.Audit.list_recent_edits(limit: 20)
      |> Enum.find(fn edit ->
        Enum.any?(
          edit.events,
          &(&1.action == "location.deleted" and &1.location_id == empty.id)
        )
      end)

    assert deleted
  end

  test "does not delete when the confirm name does not match", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Keep Bin"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> element("#location-delete")
    |> render_click()

    view
    |> form("#location-delete-form", delete: %{name: "keep bin"})
    |> render_submit()

    assert has_element?(view, "#location-delete-modal")
    assert Locations.get!(empty.id).name == "Keep Bin"
  end

  test "trims confirm name spaces and deletes the location", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Spare"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> element("#location-delete")
    |> render_click()

    view
    |> form("#location-delete-form", delete: %{name: "  Spare  "})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/locations"
    assert flash["info"] == "Location deleted"
    assert_raise Ecto.NoResultsError, fn -> Locations.get!(empty.id) end
  end

  test "clears the confirm name when the delete modal closes", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Bin"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> element("#location-delete")
    |> render_click()

    view
    |> form("#location-delete-form", delete: %{name: "Bi"})
    |> render_change()

    view
    |> element("#location-delete-cancel")
    |> render_click()

    refute has_element?(view, "#location-delete-modal")

    view
    |> element("#location-delete")
    |> render_click()

    refute has_element?(view, ~s(#location-delete-confirm[value="Bi"]))
    assert has_element?(view, "#location-delete-confirm-submit:disabled")
  end

  test "server refuses delete when the name is unsaved", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Keep"})

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> element("#location-delete")
    |> render_click()

    view
    |> form("#location-form", location: %{name: "Changed"})
    |> render_change()

    html =
      view
      |> form("#location-delete-form", delete: %{name: "Keep"})
      |> render_submit()

    assert html =~ "Save or revert the name first."
    assert Locations.get!(empty.id).name == "Keep"
  end

  test "deletes a location when the saved name has padding", %{conn: conn, scope: scope} do
    {:ok, empty} = Locations.create(scope, %{name: "Keep"})

    empty
    |> Ecto.Changeset.change(%{name: "Keep "})
    |> Pinventory.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/location/#{empty.id}")

    view
    |> element("#location-delete")
    |> render_click()

    view
    |> form("#location-delete-form", delete: %{name: "Keep"})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/locations"
    assert flash["info"] == "Location deleted"
  end

  test "server refuses delete when the location still has items", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/location/#{garage.id}")

    html =
      view
      |> element("#location-page")
      |> render_hook("confirm_delete", %{"delete" => %{"name" => "Garage"}})

    assert html =~ "Remove items from this location first."
    assert Locations.get!(garage.id).name == "Garage"
    assert Items.list_items_at_location(garage.id) != []
  end

  test "clears unsaved-changes after a successful save", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Attic"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    view
    |> form("#location-form", location: %{name: "Attic 2"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})

    view
    |> form("#location-form", location: %{name: "Attic 2"})
    |> render_submit()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
    assert has_element?(view, ~s(#location-page[data-dirty="false"]))
    assert has_element?(view, "#location-save:disabled")
  end

  test "shows location activity grouped by edit with actor and events", %{
    conn: conn,
    scope: scope,
    user: user
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

    {:ok, item} =
      Items.create_item(scope, %{name: "Level"}, %{garage.id => 1, shelf.id => 2})

    {:ok, view, _html} = live(conn, ~p"/location/#{garage.id}")

    assert has_element?(view, "#location-activity")
    assert has_element?(view, "#location-activity-list")
    refute has_element?(view, "#location-activity-empty")

    edits = Pinventory.Audit.list_edits_for_location(garage.id)
    assert length(edits) == 2

    create_edit =
      Enum.find(edits, fn edit ->
        Enum.any?(edit.events, &(&1.action == "location.created"))
      end)

    stock_edit =
      Enum.find(edits, fn edit ->
        Enum.any?(edit.events, &(&1.action == "stock.changed"))
      end)

    assert create_edit
    assert stock_edit
    assert length(stock_edit.events) == 1

    assert has_element?(view, "#location-edit-#{create_edit.edit_id}", user.email)
    assert has_element?(view, "#location-edit-#{create_edit.edit_id}", "location created")
    assert has_element?(view, "#location-event-#{hd(create_edit.events).id}", "Created location")

    [stock_event] = stock_edit.events
    assert stock_event.item_id == item.id
    assert has_element?(view, "#location-event-#{stock_event.id}", "Stock at")
    refute has_element?(view, "#location-event-#{stock_event.id}", "Shelf")
  end

  test "adds a rename to location activity after save", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Old Name"})

    {:ok, view, _html} = live(conn, ~p"/location/#{location.id}")

    view
    |> form("#location-form", location: %{name: "New Name"})
    |> render_submit()

    edits = Pinventory.Audit.list_edits_for_location(location.id)

    rename_edit =
      Enum.find(edits, fn edit ->
        Enum.any?(edit.events, &(&1.action == "location.updated"))
      end)

    assert rename_edit
    assert has_element?(view, "#location-edit-#{rename_edit.edit_id}", "location renamed")
    assert has_element?(view, "#location-event-#{hd(rename_edit.events).id}", "Renamed location")
  end
end
