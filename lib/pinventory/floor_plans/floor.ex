defmodule Pinventory.FloorPlans.Floor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "floors" do
    field :name, :string
    field :position, :integer, default: 0
    field :walls, {:array, :map}, default: []

    belongs_to :floor_plan, Pinventory.FloorPlans.FloorPlan
    has_many :location_placements, Pinventory.FloorPlans.LocationPlacement

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(floor, attrs) do
    floor
    |> cast(attrs, [:name, :position, :walls, :floor_plan_id])
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name, :position, :floor_plan_id])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_walls()
    |> foreign_key_constraint(:floor_plan_id)
  end

  @doc false
  def walls_changeset(floor, walls) when is_list(walls) do
    floor
    |> change(%{walls: walls})
    |> validate_walls()
  end

  defp validate_walls(changeset) do
    validate_change(changeset, :walls, fn :walls, walls ->
      if Enum.all?(walls, &valid_wall?/1) do
        []
      else
        [walls: "must be a list of segments with x1, y1, x2, y2 in 0.0–1.0"]
      end
    end)
  end

  defp valid_wall?(%{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}) do
    Enum.all?([x1, y1, x2, y2], &unit_coord?/1)
  end

  defp valid_wall?(%{x1: x1, y1: y1, x2: x2, y2: y2}) do
    Enum.all?([x1, y1, x2, y2], &unit_coord?/1)
  end

  defp valid_wall?(_), do: false

  defp unit_coord?(n) when is_number(n), do: n >= 0.0 and n <= 1.0
  defp unit_coord?(_), do: false

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name
end
