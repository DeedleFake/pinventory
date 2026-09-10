defmodule Pinventory.FloorPlans do
  @moduledoc """
  Optional multi-floor floor plans for the household.

  Absence of any `Floor` row means the feature is off. Locations stay when the
  plan is deleted; placements and walls are removed with floors via FK cascades.

  Location placements are closed polygons in unbounded world coords (not pins).
  Walls are stored as rows with finite world-coordinate endpoints.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.FloorPlans.{Floor, Geometry, LocationPlacement, Wall}
  alias Pinventory.Locations.Location
  alias Pinventory.Repo

  @default_floor_name "Floor 1"
  @undo_limit 50

  @doc """
  Returns all floors ordered by position, with walls and placements (+ location) preloaded.
  """
  def list_floors do
    Floor
    |> order_by([f], asc: f.position)
    |> Repo.all()
    |> Repo.preload(floor_preloads())
  end

  @doc """
  Returns true when at least one floor exists (feature on).
  """
  def floor_plan_exists? do
    Repo.exists?(from(f in Floor))
  end

  @doc """
  Creates the first floor named "#{@default_floor_name}" when none exist.

  Returns `{:error, :already_exists}` when any floor is already present.
  On success returns `{:ok, floors}` (same shape as `list_floors/0`).
  """
  def create_floor_plan do
    if floor_plan_exists?() do
      {:error, :already_exists}
    else
      %Floor{}
      |> Floor.changeset(%{name: @default_floor_name, position: 0})
      |> Repo.insert()
      |> case do
        {:ok, _floor} -> {:ok, list_floors()}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  Deletes every floor (walls and placements cascade). Locations remain.
  """
  def delete_floor_plan do
    if floor_plan_exists?() do
      {_count, _} = Repo.delete_all(Floor)
      {:ok, :deleted}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Gets a floor by id with walls and placements (+ location) preloaded, or `nil`.
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
  Adds a floor. Name defaults to "Floor N".
  """
  def add_floor(attrs \\ %{}) do
    next_position =
      Repo.one(from f in Floor, select: coalesce(max(f.position), -1))
      |> Kernel.+(1)

    name =
      Map.get(attrs, :name) ||
        Map.get(attrs, "name") ||
        "Floor #{next_position + 1}"

    %Floor{}
    |> Floor.changeset(%{name: name, position: next_position})
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
              where: f.position > ^floor.position,
              order_by: [asc: f.position],
              limit: 1
          )

        :lower ->
          Repo.one(
            from f in Floor,
              where: f.position < ^floor.position,
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
  def reorder_floors(floor_ids) when is_list(floor_ids) do
    floors = Repo.all(Floor)
    floor_by_id = Map.new(floors, &{&1.id, &1})
    known_ids = MapSet.new(Map.keys(floor_by_id))
    given_ids = Enum.uniq(floor_ids)

    cond do
      given_ids == [] ->
        {:error, :invalid_order}

      MapSet.new(given_ids) != known_ids ->
        {:error, :invalid_order}

      true ->
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
          {:ok, _} -> {:ok, list_floors()}
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  @doc """
  Deletes a floor and its placements/walls. Refuses when it is the last floor.
  """
  def delete_floor(%Floor{} = floor) do
    count = Repo.aggregate(Floor, :count)

    if count <= 1 do
      {:error, :last_floor}
    else
      Repo.delete(floor)
    end
  end

  @doc """
  Inserts one wall segment for a floor.

  When the new segment shares an endpoint with an existing wall and the two are
  collinear (same line within a small epsilon), they are merged into a single
  wall spanning the outermost endpoints. Multiple connecting collinear walls
  may be absorbed in one insert.
  """
  def add_wall(%Floor{} = floor, wall) do
    coords = wall_coords(wall)
    floor = preload_floor(floor)
    {merged_coords, walls_to_delete} = Geometry.merge_wall_into_existing(floor.walls, coords)
    attrs = Map.put(merged_coords, :floor_id, floor.id)

    Multi.new()
    |> Multi.run(:delete_merged, fn _repo, _ ->
      Enum.each(walls_to_delete, &Repo.delete!/1)
      {:ok, length(walls_to_delete)}
    end)
    |> Multi.insert(:wall, Wall.changeset(%Wall{}, attrs))
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, get_floor!(floor.id)}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Removes a wall by id. Accepts a floor struct or floor id.
  """
  def remove_wall(%Floor{} = floor, wall_id), do: remove_wall(floor.id, wall_id)

  def remove_wall(floor_id, wall_id)
      when is_binary(floor_id) and is_binary(wall_id) do
    case Repo.get_by(Wall, id: wall_id, floor_id: floor_id) do
      nil ->
        {:error, :not_found}

      wall ->
        case Repo.delete(wall) do
          {:ok, _} -> {:ok, get_floor!(floor_id)}
          error -> error
        end
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
  def plan_geometry_snapshot(floors) when is_list(floors) do
    Enum.map(floors, fn floor ->
      %{
        id: floor.id,
        name: floor.name,
        position: floor.position,
        walls:
          Enum.map(floor.walls, fn wall ->
            %{
              id: wall.id,
              x1: wall.x1,
              y1: wall.y1,
              x2: wall.x2,
              y2: wall.y2
            }
          end),
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
    if floor_plan_exists?() or snapshot != [] do
      Repo.transaction(fn ->
        snapshot_ids =
          snapshot
          |> Enum.map(&snapshot_get(&1, :id))
          |> MapSet.new()

        existing = Repo.all(Floor)

        for floor <- existing, not MapSet.member?(snapshot_ids, floor.id) do
          Repo.delete!(floor)
        end

        for floor_snap <- snapshot do
          floor_id = snapshot_get(floor_snap, :id)
          walls = snapshot_get(floor_snap, :walls) || []
          name = snapshot_get(floor_snap, :name) || "Floor"
          position = snapshot_get(floor_snap, :position) || 0

          case Repo.get(Floor, floor_id) do
            nil ->
              %Floor{id: floor_id}
              |> Floor.changeset(%{name: name, position: position})
              |> Repo.insert!()

            floor ->
              floor
              |> Floor.changeset(%{name: name, position: position})
              |> Repo.update!()
          end

          replace_walls_for_floor(floor_id, walls)
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
        {:ok, :ok} -> {:ok, list_floors()}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
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
    normalize_coord(Map.get(point, "x") || Map.get(point, :x))
  end

  defp point_coord(point, "y") when is_map(point) do
    normalize_coord(Map.get(point, "y") || Map.get(point, :y))
  end

  # Undo restore: drop current walls and re-insert snapshot rows (including ids).
  defp replace_walls_for_floor(floor_id, walls) when is_list(walls) do
    from(w in Wall, where: w.floor_id == ^floor_id) |> Repo.delete_all()

    for wall_snap <- walls do
      coords = wall_coords(wall_snap)
      wall_id = snapshot_get(wall_snap, :id)

      wall =
        if is_binary(wall_id) do
          %Wall{id: wall_id}
        else
          %Wall{}
        end

      wall
      |> Wall.changeset(Map.put(coords, :floor_id, floor_id))
      |> Repo.insert!()
    end

    :ok
  end

  defp floor_preloads do
    [:walls, location_placements: :location]
  end

  defp maybe_preload_floor(nil), do: nil
  defp maybe_preload_floor(floor), do: preload_floor(floor)

  defp preload_floor(floor) do
    Repo.preload(floor, floor_preloads())
  end

  defp swap_floor_positions(%Floor{} = a, %Floor{} = b) do
    pos_a = a.position
    pos_b = b.position

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
    points
    |> Enum.map(&normalize_point/1)
    |> Geometry.drop_collinear_polygon_vertices()
  end

  defp normalize_point(%{"x" => x, "y" => y}), do: %{"x" => normalize_coord(x), "y" => normalize_coord(y)}

  defp normalize_point(%{x: x, y: y}), do: normalize_point(%{"x" => x, "y" => y})

  defp normalize_point(other) when is_map(other) do
    normalize_point(%{
      "x" => Map.get(other, "x") || Map.get(other, :x),
      "y" => Map.get(other, "y") || Map.get(other, :y)
    })
  end

  defp wall_coords(wall) when is_map(wall) do
    %{
      x1: normalize_coord(coord(wall, :x1)),
      y1: normalize_coord(coord(wall, :y1)),
      x2: normalize_coord(coord(wall, :x2)),
      y2: normalize_coord(coord(wall, :y2))
    }
  end

  defp coord(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_coord(n) when is_number(n), do: n * 1.0
  defp normalize_coord(_), do: 0.0
end
