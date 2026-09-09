defmodule Pinventory.FloorPlans do
  @moduledoc """
  Optional multi-floor floor plans for the household.

  Absence of a `FloorPlan` row means the feature is off. At most one plan exists
  per install (`singleton_key`). Locations stay when the plan is deleted;
  placements are removed with the plan/floors via FK cascades.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Pinventory.FloorPlans.{Floor, FloorPlan, LocationPlacement}
  alias Pinventory.Locations.Location
  alias Pinventory.Repo

  @singleton_key "default"
  @default_floor_name "Floor 1"

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
  Places or moves a location pin on a floor. A location may sit on only one floor.
  """
  def place_location(%Floor{} = floor, location_id, x, y)
      when is_binary(location_id) and is_number(x) and is_number(y) do
    attrs = %{
      location_id: location_id,
      floor_id: floor.id,
      x: clamp_unit(x),
      y: clamp_unit(y)
    }

    case Repo.get_by(LocationPlacement, location_id: location_id) do
      nil ->
        %LocationPlacement{}
        |> LocationPlacement.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> LocationPlacement.changeset(attrs)
        |> Repo.update()
    end
    |> case do
      {:ok, placement} ->
        {:ok, Repo.preload(placement, [:location, :floor])}

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
  Returns a map of `location_id => %{floor_id, floor_name, x, y}` for all placements.
  """
  def placement_index do
    from(p in LocationPlacement,
      join: f in assoc(p, :floor),
      select: {p.location_id, %{floor_id: f.id, floor_name: f.name, x: p.x, y: p.y}}
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
