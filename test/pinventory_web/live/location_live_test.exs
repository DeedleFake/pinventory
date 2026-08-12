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
end
