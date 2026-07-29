defmodule Pinventory.Items.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "items" do
    field :name, :string
    field :total_quantity, :integer, virtual: true, default: 0
    field :location_count, :integer, virtual: true, default: 0

    has_many :item_locations, Pinventory.Items.ItemLocation
    has_many :locations, through: [:item_locations, :location]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2)
    |> unique_constraint(:name)
  end
end
