defmodule PinventoryWeb.FloorPlanLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pinventory.FloorPlans
  alias Pinventory.Locations

  setup :register_and_log_in_user

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
    assert has_element?(view, "#floor-tab-#{floor.id}", "Floor 1")
    assert has_element?(view, "#place-location-#{garage.id}")
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

  test "places a location pin", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _} = FloorPlans.create_floor_plan()
    {:ok, view, _html} = live(conn, ~p"/locations/floor-plan")

    view
    |> element("#place-location-#{garage.id}")
    |> render_click()

    view
    |> element("#floor-plan-canvas")
    |> render_hook("pin_placed", %{
      "location_id" => garage.id,
      "x" => 0.4,
      "y" => 0.6
    })

    garage_id = garage.id

    assert %{^garage_id => %{x: 0.4, y: 0.6, floor_name: "Floor 1"}} =
             FloorPlans.placement_index()
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
