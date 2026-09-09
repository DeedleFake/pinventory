defmodule Pinventory.FloorPlans.FloorPlan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "floor_plans" do
    field :singleton_key, :string, default: "default"

    has_many :floors, Pinventory.FloorPlans.Floor, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(floor_plan, attrs) do
    floor_plan
    |> cast(attrs, [:singleton_key])
    |> validate_required([:singleton_key])
    |> unique_constraint(:singleton_key)
  end
end
