defmodule Pinventory.FloorPlans.LocationPlacement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "location_placements" do
    field :x, :float
    field :y, :float

    belongs_to :location, Pinventory.Locations.Location
    belongs_to :floor, Pinventory.FloorPlans.Floor

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(placement, attrs) do
    placement
    |> cast(attrs, [:location_id, :floor_id, :x, :y])
    |> validate_required([:location_id, :floor_id, :x, :y])
    |> validate_number(:x, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:y, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint(:location_id)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:floor_id)
  end
end
