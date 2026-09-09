defmodule Pinventory.Locations.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "locations" do
    field :name, :string
    field :item_count, :integer, virtual: true, default: 0
    # Populated by list helpers when a floor plan exists; nil means not loaded / not placed.
    field :floor_name, :string, virtual: true
    field :on_plan?, :boolean, virtual: true, default: false

    has_many :item_locations, Pinventory.Items.ItemLocation
    has_many :items, through: [:item_locations, :item]
    has_one :placement, Pinventory.FloorPlans.LocationPlacement

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name])
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1)
    |> unique_constraint(:name)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name
end
