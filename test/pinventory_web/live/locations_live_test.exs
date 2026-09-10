defmodule PinventoryWeb.LocationsLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pinventory.FloorPlans
  alias Pinventory.Items
  alias Pinventory.Locations

  setup :register_and_log_in_user

  defp triangle do
    [
      %{"x" => 0.1, "y" => 0.1},
      %{"x" => 0.3, "y" => 0.1},
      %{"x" => 0.3, "y" => 0.3}
    ]
  end

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

  test "shows Add Floor Plan when no plan exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, "#floor-plan-add", "Add Floor Plan")
    refute has_element?(view, "#locations-floor-canvas")
    refute has_element?(view, "#locations-floor-rail")
  end

  test "creates a floor plan and navigates to the editor", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    view |> element("#floor-plan-add") |> render_click()

    floor = hd(FloorPlans.get_floor_plan().floors)
    assert_redirect(view, "/locations/floor-plan/#{floor.id}")
  end

  test "shows editor-like browse layout with placement badges", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shed} = Locations.create(scope, %{name: "Shed"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)

    assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

    {:ok, view, html} = live(conn, ~p"/locations")
    assert_patch(view, ~p"/locations/#{floor.id}")

    assert has_element?(view, "#locations-workspace")
    assert has_element?(view, "#locations-list-pane")
    assert has_element?(view, "#locations-floor-canvas[data-mode=browse]")
    assert has_element?(view, "#locations-floor-rail")
    assert has_element?(view, "#locations-floor-tab-#{floor.id}", "Floor 1")
    assert has_element?(view, "#floor-plan-edit")
    refute has_element?(view, "#floor-plan-add")
    refute has_element?(view, "#floor-plan-preview")
    refute has_element?(view, "#floor-add")
    refute has_element?(view, "#floor-remove-#{floor.id}")

    assert html =~
             ~r/id="locations-list-pane"[\s\S]*id="locations-floor-canvas"[\s\S]*id="locations-floor-rail"/

    assert has_element?(view, "#location-#{garage.id}-floor", "Floor 1")
    assert has_element?(view, "#location-#{shed.id}-not-on-plan", "Not on plan")
    assert has_element?(view, "#placement-group-#{garage.id}")
  end

  test "mount with floor_id selects that floor and reload keeps it", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor1 = hd(plan.floors)
    {:ok, floor2} = FloorPlans.add_floor(FloorPlans.get_floor_plan())
    assert {:ok, _} = FloorPlans.place_location(floor2, garage.id, triangle())

    {:ok, view, _html} = live(conn, ~p"/locations/#{floor2.id}")

    assert has_element?(view, "#locations-floor-svg-#{floor2.id}")
    refute has_element?(view, "#locations-floor-svg-#{floor1.id}")
    assert has_element?(view, "#placement-group-#{garage.id}")

    {:ok, view, _html} = live(conn, ~p"/locations/#{floor2.id}")
    assert has_element?(view, "#locations-floor-svg-#{floor2.id}")
  end

  test "select_floor patches the locations URL", %{conn: conn} do
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor1 = hd(plan.floors)
    {:ok, floor2} = FloorPlans.add_floor(FloorPlans.get_floor_plan())

    {:ok, view, _html} = live(conn, ~p"/locations")
    assert_patch(view, ~p"/locations/#{floor1.id}")

    view |> element("#locations-floor-tab-#{floor2.id}") |> render_click()

    assert_patch(view, ~p"/locations/#{floor2.id}")
    assert has_element?(view, "#locations-floor-svg-#{floor2.id}")
  end

  test "list rows link to location edit, not floors", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor1 = hd(plan.floors)
    {:ok, floor2} = FloorPlans.add_floor(FloorPlans.get_floor_plan())
    assert {:ok, _} = FloorPlans.place_location(floor1, garage.id, triangle())

    {:ok, view, _html} = live(conn, ~p"/locations/#{floor2.id}")

    assert has_element?(
             view,
             ~s|a#location-#{garage.id}[href="/location/#{garage.id}"]|
           )

    refute has_element?(view, ~s|a#location-#{garage.id}[phx-click="select_floor"]|)
    assert has_element?(view, "#location-#{garage.id}-floor", "Floor 1")
    # Still on floor 2 — list does not jump floors.
    assert has_element?(view, "#locations-floor-svg-#{floor2.id}")
  end

  test "clicking a canvas placement opens the location page", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)
    assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

    {:ok, view, _html} = live(conn, ~p"/locations/#{floor.id}")

    view
    |> element("#placement-group-#{garage.id}")
    |> render_click()

    assert_redirect(view, "/location/#{garage.id}")
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

  test "list hover targets placement on the current floor only", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)
    assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

    {:ok, view, html} = live(conn, ~p"/locations/#{floor.id}")

    assert html =~ ~s|id="location-#{garage.id}"|
    assert html =~ ~s|data-location-id="#{garage.id}"|
    assert has_element?(view, ~s|#locations-list-hover[phx-hook="PlacementListHover"]|)
    assert has_element?(view, "#placement-group-#{garage.id}")
    assert has_element?(view, ~s|#placement-group-#{garage.id}[phx-click]|)
    refute html =~ "foreignObject"
    assert html =~ ~s|font-size="0.018"|
    assert html =~ "placement-label-text"
  end
end
