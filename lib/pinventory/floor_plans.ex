defmodule Pinventory.FloorPlans do
  @moduledoc """
  Optional multi-floor floor plans for the household.

  Absence of a `FloorPlan` row means the feature is off. At most one plan exists
  per install (`singleton_key`). Locations stay when the plan is deleted;
  placements are removed with the plan/floors via FK cascades.

  Location placements are closed polygons in the unit square (not pins).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.FloorPlans.{Floor, FloorPlan, LocationPlacement}
  alias Pinventory.Locations.Location
  alias Pinventory.Repo

  @singleton_key "default"
  @default_floor_name "Floor 1"
  @undo_limit 50

  @doc """
  Returns the household floor plan with floors (and their placements) preloaded,
  or `nil` when the feature is off.
  """
  def get_floor_plan do
    FloorPlan
    |> Repo.one()
    |> maybe_preload_plan()
  end

  @doc """
  Returns true when a floor plan document exists.
  """
  def floor_plan_exists? do
    Repo.exists?(from(fp in FloorPlan))
  end

  @doc """
  Creates the singleton floor plan with an initial floor named "#{@default_floor_name}".

  Returns `{:error, :already_exists}` when a plan is already present.
  """
  def create_floor_plan do
    if floor_plan_exists?() do
      {:error, :already_exists}
    else
      Multi.new()
      |> Multi.insert(
        :floor_plan,
        FloorPlan.changeset(%FloorPlan{}, %{singleton_key: @singleton_key})
      )
      |> Multi.insert(:floor, fn %{floor_plan: plan} ->
        Floor.changeset(%Floor{}, %{
          name: @default_floor_name,
          position: 0,
          walls: [],
          floor_plan_id: plan.id
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{floor_plan: plan}} -> {:ok, get_floor_plan_by_id!(plan.id)}
        {:error, :floor_plan, changeset, _} -> {:error, changeset}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @doc """
  Deletes the entire floor plan (floors and placements cascade). Locations remain.
  """
  def delete_floor_plan(%FloorPlan{} = plan) do
    case Repo.delete(plan) do
      {:ok, deleted} -> {:ok, deleted}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete_floor_plan do
    case get_floor_plan() do
      nil -> {:error, :not_found}
      plan -> delete_floor_plan(plan)
    end
  end

  @doc """
  Gets a floor by id with placements (+ location) preloaded, or `nil`.
  """
  def get_floor(id) do
    Floor
    |> Repo.get(id)
    |> maybe_preload_floor()
  end

  def get_floor!(id) do
    Floor
    |> Repo.get!(id)
    |> preload_floor()
  end

  @doc """
  Adds a floor to the plan. Name defaults to "Floor N".
  """
  def add_floor(%FloorPlan{} = plan, attrs \\ %{}) do
    next_position =
      Repo.one(
        from f in Floor,
          where: f.floor_plan_id == ^plan.id,
          select: coalesce(max(f.position), -1)
      )
      |> Kernel.+(1)

    name =
      Map.get(attrs, :name) ||
        Map.get(attrs, "name") ||
        "Floor #{next_position + 1}"

    %Floor{}
    |> Floor.changeset(%{
      name: name,
      position: next_position,
      walls: [],
      floor_plan_id: plan.id
    })
    |> Repo.insert()
    |> case do
      {:ok, floor} -> {:ok, preload_floor(floor)}
      error -> error
    end
  end

  @doc """
  Renames a floor.
  """
  def rename_floor(%Floor{} = floor, name) when is_binary(name) do
    floor
    |> Floor.changeset(%{name: name})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, preload_floor(updated)}
      error -> error
    end
  end

  @doc """
  Moves a floor one step higher or lower in the building (by `position`).

  `:higher` raises the floor toward the top of the building; `:lower` lowers it.
  No-ops with `{:ok, floor}` when there is no neighbor in that direction.
  """
  def move_floor(%Floor{} = floor, direction) when direction in [:higher, :lower] do
    neighbor =
      case direction do
        :higher ->
          Repo.one(
            from f in Floor,
              where: f.floor_plan_id == ^floor.floor_plan_id and f.position > ^floor.position,
              order_by: [asc: f.position],
              limit: 1
          )

        :lower ->
          Repo.one(
            from f in Floor,
              where: f.floor_plan_id == ^floor.floor_plan_id and f.position < ^floor.position,
              order_by: [desc: f.position],
              limit: 1
          )
      end

    case neighbor do
      nil ->
        {:ok, preload_floor(floor)}

      other ->
        swap_floor_positions(floor, other)
    end
  end

  @doc """
  Sets floor order from a highest-first list of floor ids.

  Position `length-1` is the top of the building; `0` is the bottom.
  """
  def reorder_floors(%FloorPlan{} = plan, floor_ids) when is_list(floor_ids) do
    floors =
      from(f in Floor, where: f.floor_plan_id == ^plan.id)
      |> Repo.all()

    floor_by_id = Map.new(floors, &{&1.id, &1})
    known_ids = MapSet.new(Map.keys(floor_by_id))
    given_ids = Enum.uniq(floor_ids)

    cond do
      given_ids == [] ->
        {:error, :invalid_order}

      MapSet.new(given_ids) != known_ids ->
        {:error, :invalid_order}

      true ->
        # Highest-first → positions length-1 .. 0
        max_pos = length(given_ids) - 1

        Multi.new()
        |> Multi.run(:reorder, fn _repo, _ ->
          Enum.with_index(given_ids)
          |> Enum.each(fn {id, index} ->
            floor = Map.fetch!(floor_by_id, id)
            position = max_pos - index

            floor
            |> Floor.changeset(%{position: position})
            |> Repo.update!()
          end)

          {:ok, :ok}
        end)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> {:ok, get_floor_plan_by_id!(plan.id)}
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  @doc """
  Deletes a floor and its placements. Refuses when it is the last floor on the plan.
  """
  def delete_floor(%Floor{} = floor) do
    count =
      Repo.aggregate(
        from(f in Floor, where: f.floor_plan_id == ^floor.floor_plan_id),
        :count
      )

    if count <= 1 do
      {:error, :last_floor}
    else
      Repo.delete(floor)
    end
  end

  @doc """
  Replaces the wall segment list for a floor.
  """
  def set_walls(%Floor{} = floor, walls) when is_list(walls) do
    normalized = Enum.map(walls, &normalize_wall/1)

    floor
    |> Floor.walls_changeset(normalized)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, preload_floor(updated)}
      error -> error
    end
  end

  @doc """
  Appends one wall segment to a floor.
  """
  def add_wall(%Floor{} = floor, wall) do
    set_walls(floor, floor.walls ++ [normalize_wall(wall)])
  end

  @doc """
  Removes the wall segment at `index` (0-based).
  """
  def remove_wall(%Floor{} = floor, index) when is_integer(index) and index >= 0 do
    if index < length(floor.walls) do
      set_walls(floor, List.delete_at(floor.walls, index))
    else
      {:error, :invalid_index}
    end
  end

  @doc """
  Places or replaces a location polygon on a floor. A location may sit on only one floor.

  `points` is a list of `%{"x" => float, "y" => float}` with at least three vertices.

  Returns `{:error, :already_placed}` when the location already has a placement on a
  different floor. Same-floor updates (e.g. extend) are allowed.
  """
  def place_location(%Floor{} = floor, location_id, points)
      when is_binary(location_id) and is_list(points) do
    attrs = %{
      location_id: location_id,
      floor_id: floor.id,
      points: normalize_points(points)
    }

    case Repo.get_by(LocationPlacement, location_id: location_id) do
      nil ->
        %LocationPlacement{}
        |> LocationPlacement.changeset(attrs)
        |> Repo.insert()

      %{floor_id: existing_floor_id} when existing_floor_id != floor.id ->
        {:error, :already_placed}

      existing ->
        existing
        |> LocationPlacement.changeset(attrs)
        |> Repo.update()
    end
    |> case do
      {:ok, placement} ->
        {:ok, Repo.preload(placement, [:location, :floor])}

      {:error, :already_placed} = error ->
        error

      error ->
        error
    end
  end

  @doc """
  Removes a location's placement from the plan (location itself is kept).
  """
  def unplace_location(location_id) when is_binary(location_id) do
    case Repo.get_by(LocationPlacement, location_id: location_id) do
      nil -> {:ok, :already_unplaced}
      placement -> Repo.delete(placement)
    end
  end

  @doc """
  Returns a map of `location_id => %{floor_id, floor_name, points}` for all placements.
  """
  def placement_index do
    from(p in LocationPlacement,
      join: f in assoc(p, :floor),
      select: {p.location_id, %{floor_id: f.id, floor_name: f.name, points: p.points}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns locations that are not placed on any floor, ordered by name.
  """
  def unplaced_locations do
    placed_ids = from(p in LocationPlacement, select: p.location_id)

    from(l in Location,
      where: l.id not in subquery(placed_ids),
      order_by: [asc: l.name]
    )
    |> Repo.all()
  end

  @doc """
  Returns all locations ordered by name (for the place picker).
  """
  def list_locations do
    from(l in Location, order_by: [asc: l.name]) |> Repo.all()
  end

  @doc """
  Snapshot of plan geometry for undo/redo: floors (id/name/position), walls, and
  placements. Used to rewind wall/placement edits and floor add/remove.
  """
  def plan_geometry_snapshot(%FloorPlan{} = plan) do
    Enum.map(plan.floors, fn floor ->
      %{
        id: floor.id,
        name: floor.name,
        position: floor.position,
        walls: Enum.map(floor.walls, &normalize_wall/1),
        placements:
          Enum.map(floor.location_placements, fn placement ->
            %{location_id: placement.location_id, points: normalize_points(placement.points)}
          end)
      }
    end)
  end

  @doc """
  Restores floors, walls, and placements from a `plan_geometry_snapshot/1` value.

  Floors missing from the snapshot are deleted; floors present only in the
  snapshot are re-inserted with their original ids so undo can revive a removed
  floor (and its walls/placements).
  """
  def restore_plan_geometry(snapshot) when is_list(snapshot) do
    case get_floor_plan() do
      nil ->
        {:error, :not_found}

      plan ->
        Repo.transaction(fn ->
          snapshot_ids =
            snapshot
            |> Enum.map(&snapshot_get(&1, :id))
            |> MapSet.new()

          existing =
            from(f in Floor, where: f.floor_plan_id == ^plan.id)
            |> Repo.all()

          for floor <- existing, not MapSet.member?(snapshot_ids, floor.id) do
            Repo.delete!(floor)
          end

          for floor_snap <- snapshot do
            floor_id = snapshot_get(floor_snap, :id)
            walls = Enum.map(snapshot_get(floor_snap, :walls) || [], &normalize_wall/1)
            name = snapshot_get(floor_snap, :name) || "Floor"
            position = snapshot_get(floor_snap, :position) || 0

            case Repo.get(Floor, floor_id) do
              nil ->
                %Floor{id: floor_id}
                |> Floor.changeset(%{
                  name: name,
                  position: position,
                  walls: walls,
                  floor_plan_id: plan.id
                })
                |> Repo.insert!()

              floor ->
                floor
                |> Floor.changeset(%{name: name, position: position, walls: walls})
                |> Repo.update!()
            end
          end

          desired =
            Enum.flat_map(snapshot, fn floor_snap ->
              floor_id = snapshot_get(floor_snap, :id)
              placements = snapshot_get(floor_snap, :placements) || []

              Enum.map(placements, fn placement ->
                %{
                  location_id: placement_get(placement, :location_id),
                  floor_id: floor_id,
                  points: normalize_points(placement_get(placement, :points))
                }
              end)
            end)

          desired_by_loc = Map.new(desired, &{&1.location_id, &1})
          desired_ids = Map.keys(desired_by_loc)

          from(p in LocationPlacement, where: p.location_id not in ^desired_ids)
          |> Repo.delete_all()

          for {location_id, attrs} <- desired_by_loc do
            case Repo.get_by(LocationPlacement, location_id: location_id) do
              nil ->
                %LocationPlacement{}
                |> LocationPlacement.changeset(attrs)
                |> Repo.insert!()

              placement ->
                placement
                |> LocationPlacement.changeset(attrs)
                |> Repo.update!()
            end
          end

          :ok
        end)
        |> case do
          {:ok, :ok} -> {:ok, get_floor_plan()}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp snapshot_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @doc """
  Max undo stack depth used by the editor.
  """
  def undo_limit, do: @undo_limit

  @doc """
  SVG `points` attribute string for a placement polygon.
  """
  def polygon_points_attr(points) when is_list(points) do
    points
    |> Enum.map(fn point ->
      "#{point_coord(point, "x")},#{point_coord(point, "y")}"
    end)
    |> Enum.join(" ")
  end

  @doc """
  Average of polygon vertices (label anchor).
  """
  def polygon_centroid(points) when is_list(points) and points != [] do
    n = length(points)

    {sx, sy} =
      Enum.reduce(points, {0.0, 0.0}, fn point, {ax, ay} ->
        {ax + point_coord(point, "x"), ay + point_coord(point, "y")}
      end)

    {sx / n, sy / n}
  end

  def polygon_centroid(_), do: {0.5, 0.5}

  defp placement_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp point_coord(point, "x") when is_map(point) do
    clamp_unit(Map.get(point, "x") || Map.get(point, :x))
  end

  defp point_coord(point, "y") when is_map(point) do
    clamp_unit(Map.get(point, "y") || Map.get(point, :y))
  end

  defp get_floor_plan_by_id!(id) do
    FloorPlan
    |> Repo.get!(id)
    |> preload_plan()
  end

  defp maybe_preload_plan(nil), do: nil
  defp maybe_preload_plan(plan), do: preload_plan(plan)

  defp preload_plan(plan) do
    Repo.preload(plan,
      floors:
        from(f in Floor,
          order_by: [asc: f.position],
          preload: [location_placements: :location]
        )
    )
  end

  defp maybe_preload_floor(nil), do: nil
  defp maybe_preload_floor(floor), do: preload_floor(floor)

  defp preload_floor(floor) do
    Repo.preload(floor, location_placements: :location)
  end

  defp swap_floor_positions(%Floor{} = a, %Floor{} = b) do
    pos_a = a.position
    pos_b = b.position

    # No unique constraint on position, so a direct swap is safe.
    Multi.new()
    |> Multi.update(:a, Floor.changeset(a, %{position: pos_b}))
    |> Multi.update(:b, Floor.changeset(b, %{position: pos_a}))
    |> Repo.transaction()
    |> case do
      {:ok, %{a: floor}} -> {:ok, preload_floor(floor)}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp normalize_points(points) when is_list(points) do
    Enum.map(points, &normalize_point/1)
  end

  defp normalize_point(%{"x" => x, "y" => y}), do: %{"x" => clamp_unit(x), "y" => clamp_unit(y)}

  defp normalize_point(%{x: x, y: y}), do: normalize_point(%{"x" => x, "y" => y})

  defp normalize_point(other) when is_map(other) do
    normalize_point(%{
      "x" => Map.get(other, "x") || Map.get(other, :x),
      "y" => Map.get(other, "y") || Map.get(other, :y)
    })
  end

  defp normalize_wall(%{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}) do
    %{
      "x1" => clamp_unit(x1),
      "y1" => clamp_unit(y1),
      "x2" => clamp_unit(x2),
      "y2" => clamp_unit(y2)
    }
  end

  defp normalize_wall(%{x1: x1, y1: y1, x2: x2, y2: y2}) do
    normalize_wall(%{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2})
  end

  defp normalize_wall(other) when is_map(other) do
    normalize_wall(%{
      "x1" => Map.get(other, "x1") || Map.get(other, :x1),
      "y1" => Map.get(other, "y1") || Map.get(other, :y1),
      "x2" => Map.get(other, "x2") || Map.get(other, :x2),
      "y2" => Map.get(other, "y2") || Map.get(other, :y2)
    })
  end

  defp clamp_unit(n) when is_number(n) do
    n |> max(0.0) |> min(1.0) |> Kernel.*(1.0)
  end

  defp clamp_unit(_), do: 0.0
end
