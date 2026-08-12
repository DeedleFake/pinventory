defmodule PinventoryWeb.LocationsLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pinventory.Items
  alias Pinventory.Locations

  setup :register_and_log_in_user

  test "renders locations ordered by name with item counts", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _alpha} = Locations.create(scope, %{name: "Alpha"})

    {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 3})

    {:ok, view, html} = live(conn, ~p"/locations")

    assert html =~ "Locations"
    assert has_element?(view, "#location-new-form")
    assert has_element?(view, "#locations")

    # Alphabetical order on load: Alpha before Garage
    assert html =~ ~r/Alpha[\s\S]*Garage/

    assert has_element?(view, "#location-#{garage.id}-item-count", "1 item")
  end

  test "lists locations as links to the location page", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(
             view,
             ~s|a#location-#{garage.id}[href="/location/#{garage.id}"]|,
             "Garage"
           )

    refute has_element?(view, "form#location-#{garage.id}")
    refute has_element?(view, "#location-#{garage.id}-save")
    refute has_element?(view, "#location-delete")
  end

  test "opens the location page from the list", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> element("#location-#{garage.id}")
    |> render_click()

    assert_redirect(view, "/location/#{garage.id}")
  end

  test "adds a new location at the top of the list", %{conn: conn, scope: scope} do
    {:ok, existing} = Locations.create(scope, %{name: "Existing"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-new-form", location: %{name: "Brand New"})
    |> render_submit()

    html = render(view)

    assert html =~ "Brand New"
    assert html =~ "Location created"
    assert has_element?(view, "#location-new-form")

    # New location is first stream row after the empty-state placeholder
    assert html =~ ~r/id="location-[^"]+"[\s\S]*id="location-#{existing.id}"/
  end

  test "shows validation errors for a blank new location", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    html =
      view
      |> form("#location-new-form", location: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "marks typed new location drafts as unsaved", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-new-form", location: %{name: "Draft Place"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})

    view
    |> form("#location-new-form", location: %{name: "Draft Place"})
    |> render_submit()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
  end

  test "shows zero items for a location with no stock", %{conn: conn, scope: scope} do
    {:ok, location} = Locations.create(scope, %{name: "Empty"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, "#location-#{location.id}-item-count", "0 items")
  end

  test "marks locations as the current header section", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(
             view,
             ~s|#nav-locations[href="/locations"][aria-current="page"]|,
             "Locations"
           )

    assert has_element?(view, ~s|#nav-items[href="/"]|, "Items")
    refute has_element?(view, ~s|#nav-items[aria-current="page"]|)
  end
end
