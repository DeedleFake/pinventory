defmodule Pinventory.FloorPlansTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.FloorPlans
  alias Pinventory.FloorPlans.{Floor, LocationPlacement, Wall}
  alias Pinventory.Locations

  import Pinventory.AccountsFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  defp triangle(ox \\ 0.0, oy \\ 0.0) do
    [
      %{"x" => 0.1 + ox, "y" => 0.1 + oy},
      %{"x" => 0.4 + ox, "y" => 0.1 + oy},
      %{"x" => 0.4 + ox, "y" => 0.4 + oy}
    ]
  end

  describe "list_floors/0" do
    test "returns empty when no floors exist" do
      assert FloorPlans.list_floors() == []
      refute FloorPlans.floor_plan_exists?()
    end
  end

  describe "create_floor_plan/0" do
    test "creates Floor 1 when none exist" do
      assert {:ok, [%Floor{name: "Floor 1", position: 0, walls: []}]} =
               FloorPlans.create_floor_plan()

      assert FloorPlans.floor_plan_exists?()
    end

    test "refuses a second plan" do
      assert {:ok, _} = FloorPlans.create_floor_plan()
      assert {:error, :already_exists} = FloorPlans.create_floor_plan()
    end
  end

  describe "delete_floor_plan/0" do
    test "removes all floors and keeps locations", %{scope: scope} do
      {:ok, location} = Locations.create(scope, %{name: "Garage"})
      {:ok, floors} = FloorPlans.create_floor_plan()
      floor = hd(floors)

      assert {:ok, _} = FloorPlans.place_location(floor, location.id, triangle())
      assert {:ok, _} = FloorPlans.delete_floor_plan()

      refute FloorPlans.floor_plan_exists?()
      assert Locations.get!(location.id).name == "Garage"
      assert FloorPlans.placement_index() == %{}
    end
  end

  describe "floors" do
    setup do
      {:ok, _} = FloorPlans.create_floor_plan()
      :ok
    end

    test "adds, renames, and removes floors" do
      assert {:ok, %Floor{name: "Floor 2"} = floor2} = FloorPlans.add_floor()
      assert {:ok, %Floor{name: "Basement"}} = FloorPlans.rename_floor(floor2, "Basement")

      assert Enum.map(FloorPlans.list_floors(), & &1.name) == ["Floor 1", "Basement"]

      basement = Enum.find(FloorPlans.list_floors(), &(&1.name == "Basement"))
      assert {:ok, _} = FloorPlans.delete_floor(basement)
      assert [%Floor{name: "Floor 1"}] = FloorPlans.list_floors()
    end

    test "refuses to delete the last floor" do
      [floor] = FloorPlans.list_floors()
      assert {:error, :last_floor} = FloorPlans.delete_floor(floor)
    end

    test "moves and reorders floors by position" do
      assert {:ok, floor2} = FloorPlans.add_floor()
      assert {:ok, _floor3} = FloorPlans.add_floor()

      assert Enum.map(FloorPlans.list_floors(), & &1.name) == [
               "Floor 1",
               "Floor 2",
               "Floor 3"
             ]

      # Raise Floor 2 above Floor 3.
      assert {:ok, _} = FloorPlans.move_floor(floor2, :higher)

      assert Enum.map(FloorPlans.list_floors(), &{&1.name, &1.position}) == [
               {"Floor 1", 0},
               {"Floor 3", 1},
               {"Floor 2", 2}
             ]

      [f1, f3, f2] = FloorPlans.list_floors()

      # Highest-first list → positions 2,1,0
      assert {:ok, _} = FloorPlans.reorder_floors([f1.id, f3.id, f2.id])

      assert Enum.map(FloorPlans.list_floors(), &{&1.name, &1.position}) == [
               {"Floor 2", 0},
               {"Floor 3", 1},
               {"Floor 1", 2}
             ]

      assert {:error, :invalid_order} = FloorPlans.reorder_floors([f1.id])
    end
  end

  describe "walls and placements" do
    setup %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, attic} = Locations.create(scope, %{name: "Attic"})
      {:ok, floors} = FloorPlans.create_floor_plan()
      floor = hd(floors)
      %{garage: garage, attic: attic, floor: floor}
    end

    test "stores wall segments as rows", %{floor: floor} do
      wall = %{"x1" => 0.1, "y1" => 0.1, "x2" => 0.9, "y2" => 0.1}
      assert {:ok, updated} = FloorPlans.add_wall(floor, wall)
      assert [%Wall{x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.1} = saved] = updated.walls

      assert {:ok, cleared} = FloorPlans.remove_wall(updated, saved.id)
      assert cleared.walls == []
    end

    test "accepts wall and placement coords outside 0..1", %{garage: garage, floor: floor} do
      assert {:ok, updated} =
               FloorPlans.add_wall(floor, %{
                 "x1" => -0.25,
                 "y1" => 0.1,
                 "x2" => 1.5,
                 "y2" => 1.25
               })

      assert [%Wall{x1: -0.25, y1: 0.1, x2: 1.5, y2: 1.25}] = updated.walls

      points = [
        %{"x" => -0.1, "y" => -0.1},
        %{"x" => 1.5, "y" => -0.1},
        %{"x" => 1.5, "y" => 1.2}
      ]

      assert {:ok, %LocationPlacement{points: ^points}} =
               FloorPlans.place_location(updated, garage.id, points)
    end

    test "places a location polygon once and rejects a second floor", %{
      garage: garage,
      floor: floor
    } do
      points = triangle()

      assert {:ok, %LocationPlacement{points: ^points}} =
               FloorPlans.place_location(floor, garage.id, points)

      garage_id = garage.id

      assert %{^garage_id => %{floor_name: "Floor 1", points: ^points}} =
               FloorPlans.placement_index()

      assert {:ok, floor2} = FloorPlans.add_floor()

      assert {:error, :already_placed} =
               FloorPlans.place_location(floor2, garage.id, triangle(0.2, 0.2))

      assert %{^garage_id => %{floor_id: floor_id}} = FloorPlans.placement_index()
      assert floor_id == floor.id
    end

    test "updates points when placing again on the same floor", %{
      garage: garage,
      floor: floor
    } do
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())
      extended = triangle(0.05, 0.05)

      assert {:ok, updated} = FloorPlans.place_location(floor, garage.id, extended)
      assert updated.floor_id == floor.id
      assert updated.points == extended
    end

    test "rejects polygons with fewer than three points", %{garage: garage, floor: floor} do
      assert {:error, changeset} =
               FloorPlans.place_location(floor, garage.id, [
                 %{"x" => 0.1, "y" => 0.1},
                 %{"x" => 0.2, "y" => 0.2}
               ])

      assert changeset.errors[:points]
    end

    test "lists unplaced locations", %{garage: garage, attic: attic, floor: floor} do
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())
      assert [%{id: id, name: "Attic"}] = FloorPlans.unplaced_locations()
      assert id == attic.id
    end

    test "unplace removes polygon only", %{garage: garage, floor: floor} do
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())
      assert {:ok, _} = FloorPlans.unplace_location(garage.id)
      assert FloorPlans.placement_index() == %{}
      assert Locations.get!(garage.id).name == "Garage"
    end

    test "restore_plan_geometry rewinds walls and placements", %{
      garage: garage,
      floor: floor
    } do
      assert {:ok, _} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.0, "x2" => 1.0, "y2" => 0.0})

      before = FloorPlans.plan_geometry_snapshot(FloorPlans.list_floors())

      floor = FloorPlans.get_floor!(floor.id)
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

      assert {:ok, _} =
               FloorPlans.add_wall(FloorPlans.get_floor!(floor.id), %{
                 "x1" => 0.0,
                 "y1" => 1.0,
                 "x2" => 1.0,
                 "y2" => 1.0
               })

      assert {:ok, restored} = FloorPlans.restore_plan_geometry(before)
      restored_floor = hd(restored)
      assert length(restored_floor.walls) == 1
      assert restored_floor.location_placements == []
      assert FloorPlans.placement_index() == %{}
    end

    test "restore_plan_geometry recreates a deleted floor", %{floor: floor} do
      {:ok, extra} = FloorPlans.add_floor()

      assert {:ok, _} =
               FloorPlans.add_wall(FloorPlans.get_floor!(extra.id), %{
                 "x1" => 0.2,
                 "y1" => 0.2,
                 "x2" => 0.8,
                 "y2" => 0.2
               })

      before = FloorPlans.plan_geometry_snapshot(FloorPlans.list_floors())
      assert length(before) == 2
      assert Enum.any?(before, &(&1.id == extra.id and &1.name == "Floor 2"))

      assert {:ok, _} = FloorPlans.delete_floor(FloorPlans.get_floor!(extra.id))
      assert Enum.map(FloorPlans.list_floors(), & &1.id) == [floor.id]

      assert {:ok, restored} = FloorPlans.restore_plan_geometry(before)
      ids = Enum.map(restored, & &1.id)
      assert floor.id in ids
      assert extra.id in ids
      assert length(FloorPlans.get_floor!(extra.id).walls) == 1
    end
  end

  describe "list_with_item_counts_and_placements/0" do
    test "annotates placed and unplaced locations when a plan exists", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shed} = Locations.create(scope, %{name: "Shed"})
      {:ok, floors} = FloorPlans.create_floor_plan()
      floor = hd(floors)
      assert {:ok, _} = FloorPlans.place_location(floor, garage.id, triangle())

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

  describe "collinear wall merge" do
    setup do
      {:ok, floors} = FloorPlans.create_floor_plan()
      %{floor: hd(floors)}
    end

    test "merges two horizontal walls that meet into one", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.1, "y1" => 0.5, "x2" => 0.4, "y2" => 0.5})

      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.4, "y1" => 0.5, "x2" => 0.9, "y2" => 0.5})

      assert [%Wall{x1: 0.1, y1: 0.5, x2: 0.9, y2: 0.5}] = floor.walls
    end

    test "does not merge a T-junction / non-collinear wall", %{floor: floor} do
      # Stem meets at an endpoint of the crossbar but is not collinear.
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.1, "y1" => 0.5, "x2" => 0.5, "y2" => 0.5})

      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.5, "y1" => 0.5, "x2" => 0.5, "y2" => 0.9})

      assert length(floor.walls) == 2
      horizontal = Enum.find(floor.walls, &(&1.y1 == 0.5 and &1.y2 == 0.5))
      vertical = Enum.find(floor.walls, &(&1.x1 == 0.5 and &1.x2 == 0.5))
      assert horizontal
      assert vertical
    end

    test "does not merge parallel non-touching walls", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.1, "y1" => 0.2, "x2" => 0.4, "y2" => 0.2})

      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.5, "y1" => 0.2, "x2" => 0.9, "y2" => 0.2})

      assert length(floor.walls) == 2
    end
  end

  describe "collinear polygon vertices" do
    setup %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, floors} = FloorPlans.create_floor_plan()
      %{garage: garage, floor: hd(floors)}
    end

    test "drops a collinear middle vertex on place", %{garage: garage, floor: floor} do
      # Quad with an extra point on the top edge between (0.1,0.1) and (0.4,0.1)
      points = [
        %{"x" => 0.1, "y" => 0.1},
        %{"x" => 0.25, "y" => 0.1},
        %{"x" => 0.4, "y" => 0.1},
        %{"x" => 0.4, "y" => 0.4}
      ]

      assert {:ok, placement} = FloorPlans.place_location(floor, garage.id, points)

      assert placement.points == [
               %{"x" => 0.1, "y" => 0.1},
               %{"x" => 0.4, "y" => 0.1},
               %{"x" => 0.4, "y" => 0.4}
             ]
    end
  end

  describe "cut wall gap" do
    setup do
      {:ok, floors} = FloorPlans.create_floor_plan()
      %{floor: hd(floors)}
    end

    test "middle cut leaves two remainders and drops the original id", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.5, "x2" => 1.0, "y2" => 0.5})

      [wall] = floor.walls
      original_id = wall.id

      assert {:ok, floor} = FloorPlans.cut_wall_gap(floor, original_id, {0.3, 0.5}, {0.6, 0.5})
      assert length(floor.walls) == 2
      refute Enum.any?(floor.walls, &(&1.id == original_id))
      assert_has_span(floor.walls, {0.0, 0.5}, {0.3, 0.5})
      assert_has_span(floor.walls, {0.6, 0.5}, {1.0, 0.5})
    end

    test "end nibble leaves one wall from the cut to the far end", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.5, "x2" => 1.0, "y2" => 0.5})

      [wall] = floor.walls

      assert {:ok, floor} = FloorPlans.cut_wall_gap(floor, wall.id, {0.0, 0.5}, {0.25, 0.5})
      assert length(floor.walls) == 1
      assert_has_span(floor.walls, {0.25, 0.5}, {1.0, 0.5})
    end

    test "cutting both endpoints removes the wall", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.5, "x2" => 1.0, "y2" => 0.5})

      [wall] = floor.walls

      assert {:ok, floor} = FloorPlans.cut_wall_gap(floor, wall.id, {0.0, 0.5}, {1.0, 0.5})
      assert floor.walls == []
    end

    test "drops a remainder shorter than 0.02", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.5, "x2" => 1.0, "y2" => 0.5})

      [wall] = floor.walls

      assert {:ok, floor} = FloorPlans.cut_wall_gap(floor, wall.id, {0.01, 0.5}, {0.4, 0.5})
      assert length(floor.walls) == 1
      assert_has_span(floor.walls, {0.4, 0.5}, {1.0, 0.5})

      refute Enum.any?(floor.walls, fn w ->
               approx_pt({w.x1, w.y1}, {0.0, 0.5}) or approx_pt({w.x2, w.y2}, {0.0, 0.5})
             end)
    end

    test "missing id is not_found", %{floor: floor} do
      assert {:error, :not_found} =
               FloorPlans.cut_wall_gap(
                 floor,
                 "00000000-0000-0000-0000-000000000000",
                 {0.0, 0.5},
                 {0.3, 0.5}
               )
    end

    test "gapping the crossbar does not delete a T-stem", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.5, "x2" => 1.0, "y2" => 0.5})

      crossbar_id = hd(floor.walls).id

      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.5, "y1" => 0.5, "x2" => 0.5, "y2" => 0.9})

      assert length(floor.walls) == 2

      assert {:ok, floor} = FloorPlans.cut_wall_gap(floor, crossbar_id, {0.2, 0.5}, {0.8, 0.5})
      assert length(floor.walls) == 3
      refute Enum.any?(floor.walls, &(&1.id == crossbar_id))
      assert Enum.any?(floor.walls, &(&1.x1 == 0.5 and &1.x2 == 0.5))
      assert_has_span(floor.walls, {0.0, 0.5}, {0.2, 0.5})
      assert_has_span(floor.walls, {0.8, 0.5}, {1.0, 0.5})
    end

    test "no-op when both points project to the same place", %{floor: floor} do
      assert {:ok, floor} =
               FloorPlans.add_wall(floor, %{"x1" => 0.0, "y1" => 0.5, "x2" => 1.0, "y2" => 0.5})

      [wall] = floor.walls

      assert {:ok, updated} = FloorPlans.cut_wall_gap(floor, wall.id, {0.5, 0.5}, {0.5, 0.51})
      assert length(updated.walls) == 1
      [kept] = updated.walls
      assert kept.id == wall.id
      assert kept.x1 == 0.0
      assert kept.y1 == 0.5
      assert kept.x2 == 1.0
      assert kept.y2 == 0.5
    end
  end

  defp assert_has_span(walls, {x1, y1}, {x2, y2}) do
    found =
      Enum.any?(walls, fn w ->
        (approx_pt({w.x1, w.y1}, {x1, y1}) and approx_pt({w.x2, w.y2}, {x2, y2})) or
          (approx_pt({w.x1, w.y1}, {x2, y2}) and approx_pt({w.x2, w.y2}, {x1, y1}))
      end)

    assert found,
           "expected span #{inspect({x1, y1, x2, y2})} in #{inspect(Enum.map(walls, &{&1.x1, &1.y1, &1.x2, &1.y2}))}"
  end

  defp approx_pt({ax, ay}, {bx, by}) do
    abs(ax - bx) < 1.0e-6 and abs(ay - by) < 1.0e-6
  end

  describe "polygon helpers" do
    test "builds svg points and centroid" do
      points = triangle()
      assert FloorPlans.polygon_points_attr(points) == "0.1,0.1 0.4,0.1 0.4,0.4"
      {cx, cy} = FloorPlans.polygon_centroid(points)
      assert_in_delta cx, 0.3, 0.0001
      assert_in_delta cy, 0.2, 0.0001
    end
  end
end
