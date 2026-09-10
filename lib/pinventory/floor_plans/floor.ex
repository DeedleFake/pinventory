defmodule Pinventory.FloorPlans.Floor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "floors" do
    field :name, :string
    field :position, :integer, default: 0

    has_many :walls, Pinventory.FloorPlans.Wall, preload_order: [asc: :inserted_at, asc: :id]
    has_many :location_placements, Pinventory.FloorPlans.LocationPlacement

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(floor, attrs) do
    floor
    |> cast(attrs, [:name, :position])
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name, :position])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name
end
