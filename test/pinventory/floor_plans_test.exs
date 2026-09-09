defmodule Pinventory.FloorPlansTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.FloorPlans
  alias Pinventory.FloorPlans.{Floor, FloorPlan, LocationPlacement}
  alias Pinventory.Locations

  import Pinventory.AccountsFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "get_floor_plan/0" do
    test "returns nil when no plan exists" do
      assert FloorPlans.get_floor_plan() == nil
      refute FloorPlans.floor_plan_exists?()
    end
  end

  describe "create_floor_plan/0" do
    test "creates a singleton plan with Floor 1" do
      assert {:ok, %FloorPlan{} = plan} = FloorPlans.create_floor_plan()
      assert FloorPlans.floor_plan_exists?()
      assert [%Floor{name: "Floor 1", position: 0, walls: []}] = plan.floors
    end

    test "refuses a second plan" do
      assert {:ok, _} = FloorPlans.create_floor_plan()
      assert {:error, :already_exists} = FloorPlans.create_floor_plan()
    end
  end

  describe "delete_floor_plan/0" do
    test "removes the plan and keeps locations", %{scope: scope} do
      {:ok, location} = Locations.create(scope, %{name: "Garage"})
      {:ok, plan} = FloorPlans.create_floor_plan()
      floor = hd(plan.floors)

      assert {:ok, _} = FloorPlans.place_location(floor, location.id, 0.4, 0.5)
      assert {:ok, _} = FloorPlans.delete_floor_plan()

      refute FloorPlans.floor_plan_exists?()
      assert Locations.get!(location.id).name == "Garage"
      assert FloorPlans.placement_index() == %{}
    end
  end

  describe "floors" do
    setup do
      {:ok, _plan} = FloorPlans.create_floor_plan()
      %{plan: FloorPlans.get_floor_plan()}
    end

    test "adds, renames, and removes floors", %{plan: plan} do
      assert {:ok, %Floor{name: "Floor 2"} = floor2} = FloorPlans.add_floor(plan)
      assert {:ok, %Floor{name: "Basement"}} = FloorPlans.rename_floor(floor2, "Basement")

      plan = FloorPlans.get_floor_plan()
      assert Enum.map(plan.floors, & &1.name) == ["Floor 1", "Basement"]

      basement = Enum.find(plan.floors, &(&1.name == "Basement"))
      assert {:ok, _} = FloorPlans.delete_floor(basement)
      assert [%Floor{name: "Floor 1"}] = FloorPlans.get_floor_plan().floors
    end

    test "refuses to delete the last floor", %{plan: plan} do
      [floor] = plan.floors
      assert {:error, :last_floor} = FloorPlans.delete_floor(floor)
    end
  end

  describe "walls and placements" do
    setup %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, attic} = Locations.create(scope, %{name: "Attic"})
      {:ok, plan} = FloorPlans.create_floor_plan()
      floor = hd(plan.floors)
      %{garage: garage, attic: attic, floor: floor, plan: plan}
    end

    test "stores wall segments", %{floor: floor} do
      wall = %{"x1" => 0.1, "y1" => 0.1, "x2" => 0.9, "y2" => 0.1}
      assert {:ok, updated} = FloorPlans.add_wall(floor, wall)
      assert updated.walls == [wall]

      assert {:ok, cleared} = FloorPlans.remove_wall(updated, 0)
      assert cleared.walls == []
    end

    test "places a location once and moves it across floors", %{
      garage: garage,
      floor: floor,
      plan: plan
    } do
      assert {:ok, %LocationPlacement{x: 0.25, y: 0.75}} =
               FloorPlans.place_location(floor, garage.id, 0.25, 0.75)

      garage_id = garage.id

      assert %{^garage_id => %{floor_name: "Floor 1", x: 0.25, y: 0.75}} =
               FloorPlans.placement_index()

      assert {:ok, floor2} = FloorPlans.add_floor(plan)

      assert {:ok, moved} = FloorPlans.place_location(floor2, garage.id, 0.5, 0.5)
      assert moved.floor_id == floor2.id
      assert map_size(FloorPlans.placement_index()) == 1
    end

    test "lists unplaced locations", %{garage: garage, attic: attic, floor: floor} do
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, 0.2, 0.2)
      assert [%{id: id, name: "Attic"}] = FloorPlans.unplaced_locations()
      assert id == attic.id
    end

    test "unplace removes pin only", %{garage: garage, floor: floor} do
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, 0.3, 0.3)
      assert {:ok, _} = FloorPlans.unplace_location(garage.id)
      assert FloorPlans.placement_index() == %{}
      assert Locations.get!(garage.id).name == "Garage"
    end
  end

  describe "list_with_item_counts_and_placements/0" do
    test "annotates placed and unplaced locations when a plan exists", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shed} = Locations.create(scope, %{name: "Shed"})
      {:ok, plan} = FloorPlans.create_floor_plan()
      floor = hd(plan.floors)
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, 0.1, 0.2)

      by_name =
        Locations.list_with_item_counts_and_placements()
        |> Map.new(&{&1.name, &1})

      assert by_name["Garage"].on_plan?
      assert by_name["Garage"].floor_name == "Floor 1"
      refute by_name["Shed"].on_plan?
      assert by_name["Shed"].floor_name == nil
      assert shed.id == by_name["Shed"].id
    end
  end
end
