defmodule Pinventory.Items.Item do
  @moduledoc """
  An item has three sections that people edit and save independently: its
  name, its notes, and its stock at every location. A save conflicts only
  with saves that changed the same section.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type section :: :name | :notes | :stock

  # Each section's data field.
  @sections [name: :name, notes: :notes, stock: :item_locations]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "items" do
    field :name, :string
    field :notes, :string, default: ""
    field :total_quantity, :integer, virtual: true, default: 0
    field :location_count, :integer, virtual: true, default: 0
    # Stock at one location. Set by list_items_at_location/1 only.
    field :quantity, :integer, virtual: true, default: 0

    has_many :item_locations, Pinventory.Items.ItemLocation
    has_many :locations, through: [:item_locations, :location]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name])
    |> cast(attrs, [:notes], empty_values: [nil])
    |> update_change(:notes, &normalize_newlines/1)
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2)
    |> unique_constraint(:name)
  end

  @doc "Every section, in page order."
  @spec sections() :: [section()]
  def sections, do: Keyword.keys(@sections)

  @doc """
  Sections whose saved values differ between `base` and `latest`, in page
  order. Both need `item_locations` loaded. A section changed and then
  changed back counts as unchanged.
  """
  @spec changed_sections(t, t) :: [section()] when t: %__MODULE__{}
  def changed_sections(%__MODULE__{} = base, %__MODULE__{} = latest) do
    Enum.reject(sections(), &(value(base, &1) == value(latest, &1)))
  end

  @doc """
  Copies one section from `latest` into `base`, leaving the other sections
  as `base` had them.
  """
  @spec put_section(t, t, section()) :: t when t: %__MODULE__{}
  def put_section(%__MODULE__{} = base, %__MODULE__{} = latest, section) do
    field = Keyword.fetch!(@sections, section)
    Map.put(base, field, Map.fetch!(latest, field))
  end

  defp value(%__MODULE__{item_locations: item_locations}, :stock),
    do: Map.new(item_locations, &{&1.location_id, &1.quantity})

  defp value(%__MODULE__{} = item, section),
    do: Map.fetch!(item, Keyword.fetch!(@sections, section))

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  defp normalize_newlines(notes) when is_binary(notes), do: String.replace(notes, "\r\n", "\n")
  defp normalize_newlines(nil), do: ""
end
