defmodule PinventoryWeb.FloorPlanLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pinventory.FloorPlans
  alias Pinventory.Locations

  setup :register_and_log_in_user

  defp triangle do
    [
      %{"x" => 0.1, "y" => 0.1},
      %{"x" => 0.4, "y" => 0.1},
      %{"x" => 0.4, "y" => 0.4}
    ]
  end

  test "redirects to locations when no plan exists", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/locations"}}} =
             live(conn, ~p"/locations/floor-plan")
  end

  test "renders the editor when a plan exists", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)

    {:ok, view, html} = live(conn, ~p"/locations/floor-plan")

    assert html =~ "Floor plan"
    assert has_element?(view, "#floor-plan-page")
    assert has_element?(view, "#floor-plan-canvas")
    assert has_element?(view, "#floor-plan-sidebar")
    assert has_element?(view, "#floor-plan-wall-tools")
    assert has_element?(view, "#tool-wall")
    assert has_element?(view, "#tool-erase")
    refute has_element?(view, "#tool-place")
    assert has_element?(view, "#history-undo")
    assert has_element?(view, "#history-redo")
    assert has_element?(view, "#polygon-finish")
    assert has_element?(view, "#floor-tab-#{floor.id}", "Floor 1")
    assert has_element?(view, "#place-location-#{garage.id}")
  end

  test "clicking a location selects place mode for that location", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    assert has_element?(view, "#floor-plan-canvas[data-mode=wall]")

    view |> element("#place-location-#{garage.id}") |> render_click()

    assert has_element?(view, "#floor-plan-canvas[data-mode=place]")
    assert has_element?(view, ~s|#floor-plan-canvas[data-location-id="#{garage.id}"]|)
    assert has_element?(view, ~s|#floor-plan-canvas[data-place-mode="new"]|)

    view |> element("#tool-wall") |> render_click()

    assert has_element?(view, "#floor-plan-canvas[data-mode=wall]")
    html = render(view)
    assert html =~ ~s|data-location-id=""|
  end

  test "selecting a placed location defaults to extend", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)
    assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

    {:ok, view, html} = live(conn, ~p"/locations/floor-plan")
    assert html =~ "data-snap-vertex"
    assert html =~ "data-snap-edge"
    refute has_element?(view, "#redraw-location-#{garage.id}")

    view |> element("#place-location-#{garage.id}") |> render_click()

    assert has_element?(view, ~s|#floor-plan-canvas[data-place-mode="extend"]|)
    assert has_element?(view, ~s|#floor-plan-canvas[data-location-id="#{garage.id}"]|)
    canvas = view |> element("#floor-plan-canvas") |> render()
    assert canvas =~ "0.1"
    assert canvas =~ "data-existing-points"
  end

  test "polygon_placed replaces points when extending via merged client list", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)
    assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    extended = [
      %{"x" => 0.1, "y" => 0.1},
      %{"x" => 0.2, "y" => 0.05},
      %{"x" => 0.4, "y" => 0.1},
      %{"x" => 0.4, "y" => 0.4}
    ]

    view
    |> element("#floor-plan-canvas")
    |> render_hook("polygon_placed", %{
      "location_id" => garage.id,
      "points" => extended
    })

    garage_id = garage.id
    assert %{^garage_id => %{points: ^extended}} = FloorPlans.placement_index()
  end

  test "draws a wall from the canvas hook event", %{conn: conn} do
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view
    |> element("#floor-plan-canvas")
    |> render_hook("wall_drawn", %{"x1" => 0.1, "y1" => 0.2, "x2" => 0.8, "y2" => 0.2})

    plan = FloorPlans.get_floor_plan()
    assert [%{"x1" => 0.1, "y1" => 0.2, "x2" => 0.8, "y2" => 0.2}] = hd(plan.floors).walls
  end

  test "erases a wall by index", %{conn: conn} do
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)

    assert {:ok, _} =
             FloorPlans.add_wall(floor, %{"x1" => 0.1, "y1" => 0.1, "x2" => 0.9, "y2" => 0.1})

    assert {:ok, _} =
             FloorPlans.add_wall(FloorPlans.get_floor!(floor.id), %{
               "x1" => 0.1,
               "y1" => 0.9,
               "x2" => 0.9,
               "y2" => 0.9
             })

    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view
    |> element("#floor-plan-canvas")
    |> render_hook("wall_erased", %{"index" => 0})

    walls = hd(FloorPlans.get_floor_plan().floors).walls
    assert length(walls) == 1
    assert hd(walls)["y1"] == 0.9
  end

  test "places a location polygon", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view
    |> element("#place-location-#{garage.id}")
    |> render_click()

    points = triangle()

    view
    |> element("#floor-plan-canvas")
    |> render_hook("polygon_placed", %{
      "location_id" => garage.id,
      "points" => points
    })

    garage_id = garage.id

    assert %{^garage_id => %{points: ^points, floor_name: "Floor 1"}} =
             FloorPlans.placement_index()

    html = render(view)
    assert html =~ "polygon"
    assert html =~ "0.1,0.1"
  end

  test "undo and redo wall edits", %{conn: conn} do
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view
    |> element("#floor-plan-canvas")
    |> render_hook("wall_drawn", %{"x1" => 0.1, "y1" => 0.2, "x2" => 0.8, "y2" => 0.2})

    assert length(hd(FloorPlans.get_floor_plan().floors).walls) == 1

    view |> element("#history-undo") |> render_click()
    assert hd(FloorPlans.get_floor_plan().floors).walls == []

    view |> element("#history-redo") |> render_click()
    assert length(hd(FloorPlans.get_floor_plan().floors).walls) == 1
  end

  test "undo restores a removed placement", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, plan} = FloorPlans.create_floor_plan()
    floor = hd(plan.floors)
    assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view |> element("#place-location-#{garage.id}") |> render_click()
    view |> element("#unplace-location-#{garage.id}") |> render_click()
    assert FloorPlans.placement_index() == %{}

    view |> element("#history-undo") |> render_click()
    garage_id = garage.id
    assert %{^garage_id => %{floor_name: "Floor 1"}} = FloorPlans.placement_index()
  end

  test "adds and renames floors", %{conn: conn} do
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view |> element("#floor-add") |> render_click()
    assert render(view) =~ "Floor 2"

    view
    |> form("#floor-rename-form", %{name: "Basement"})
    |> render_submit()

    assert has_element?(view, "#floor-tabs", "Basement")
  end

  test "deletes the floor plan and returns to locations", %{conn: conn, scope: scope} do
    {:ok, _} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view |> element("#floor-plan-delete") |> render_click()
    assert has_element?(view, "#floor-plan-delete-confirm")

    view |> element("#floor-plan-delete-confirm-button") |> render_click()

    assert_redirect(view, "/locations")
    refute FloorPlans.floor_plan_exists?()
    assert [%{name: "Garage"}] = Locations.list()
  end
end
