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
    |> validate_required([:quantity, :item_id, :location_id])
    |> validate_number(:quantity, greater_than: 0)
    |> unique_constraint([:item_id, :location_id])
    |> foreign_key_constraint(:item_id)
    |> foreign_key_constraint(:location_id)
    |> check_constraint(:quantity, name: :quantity_must_be_positive)
  end
end
