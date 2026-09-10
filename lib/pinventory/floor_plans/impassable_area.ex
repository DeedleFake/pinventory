defmodule Pinventory.FloorPlans.ImpassableArea do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "impassable_areas" do
    field :points, {:array, :map}, default: []

    belongs_to :floor, Pinventory.FloorPlans.Floor

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(area, attrs) do
    area
    |> cast(attrs, [:floor_id, :points])
    |> validate_required([:floor_id, :points])
    |> validate_points()
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
          [points: "each point needs finite x and y"]

        true ->
          []
      end
    end)
  end

  defp valid_point?(%{"x" => x, "y" => y}), do: finite_coord?(x) and finite_coord?(y)
  defp valid_point?(%{x: x, y: y}), do: finite_coord?(x) and finite_coord?(y)
  defp valid_point?(_), do: false

  defp finite_coord?(n) when is_integer(n), do: true

  defp finite_coord?(n) when is_float(n) do
    # NaN is not equal to itself; ±Inf have all-ones exponent.
    <<_sign::1, exp::11, _mant::52>> = <<n::float>>
    n == n and exp != 0x7FF
  end

  defp finite_coord?(_), do: false
end
