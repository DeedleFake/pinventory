defmodule Pinventory.Items.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "items" do
    field :name, :string
    field :quantity, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :quantity])
    |> validate_required([:name])
    |> validate_length(:name, min: 2)
    |> unique_constraint(:name)
    |> validate_quantity()
  end

  @doc false
  def update_quantity_changeset(item, attrs) do
    item
    |> cast(attrs, [:quantity])
    |> validate_quantity()
  end

  defp validate_quantity(changeset) do
    changeset
    |> validate_required([:quantity])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
  end
end
