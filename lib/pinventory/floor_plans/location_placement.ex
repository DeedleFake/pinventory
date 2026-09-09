defmodule Pinventory.FloorPlans.LocationPlacement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "location_placements" do
    field :points, {:array, :map}, default: []

    belongs_to :location, Pinventory.Locations.Location
    belongs_to :floor, Pinventory.FloorPlans.Floor

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(placement, attrs) do
    placement
    |> cast(attrs, [:location_id, :floor_id, :points])
    |> validate_required([:location_id, :floor_id, :points])
    |> validate_points()
    |> unique_constraint(:location_id)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:floor_id)
  end

  defp validate_points(changeset) do
    validate_change(changeset, :points, fn :points, points ->
      cond do
        not is_list(points) ->
          [points: "must be a list of points"]

        length(points) < 3 ->
          [points: "must have at least 3 points"]

        not Enum.all?(points, &valid_point?/1) ->
          [points: "each point needs x and y in 0.0–1.0"]

        true ->
          []
      end
    end)
  end

  defp valid_point?(%{"x" => x, "y" => y}), do: unit_coord?(x) and unit_coord?(y)
  defp valid_point?(%{x: x, y: y}), do: unit_coord?(x) and unit_coord?(y)
  defp valid_point?(_), do: false

  defp unit_coord?(n) when is_number(n), do: n >= 0.0 and n <= 1.0
  defp unit_coord?(_), do: false
end
