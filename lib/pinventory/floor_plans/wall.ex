defmodule Pinventory.FloorPlans.Wall do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "walls" do
    field :x1, :float
    field :y1, :float
    field :x2, :float
    field :y2, :float

    belongs_to :floor, Pinventory.FloorPlans.Floor

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(wall, attrs) do
    wall
    |> cast(attrs, [:floor_id, :x1, :y1, :x2, :y2])
    |> validate_required([:floor_id, :x1, :y1, :x2, :y2])
    |> validate_number(:x1, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:y1, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:x2, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:y2, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:floor_id)
  end
end
