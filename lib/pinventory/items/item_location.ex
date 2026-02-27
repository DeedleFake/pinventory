defmodule Pinventory.Items.ItemLocation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "item_locations" do
    field :quantity, :integer

    belongs_to :item, Pinventory.Items.Item
    belongs_to :location, Pinventory.Locations.Location

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item_location, attrs) do
    item_location
    |> cast(attrs, [:quantity])
    |> cast_assoc(:item, with: &Pinventory.Items.Item.changeset/2)
    |> cast_assoc(:location, with: &Pinventory.Locations.change_location/2)
    |> validate_required([:quantity])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> unique_constraint([:item_id, :location_id])
  end
end
