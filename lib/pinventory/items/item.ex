defmodule Pinventory.Items.Item do
  @moduledoc """
  An item has three sections that people edit and save independently: its
  name, its notes, and its stock at every location. Each section has its own
  version, bumped by every save that changes it, so a save conflicts only
  with saves to the same section.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type section :: :name | :notes | :stock

  # Each section's data field and version field.
  @sections [
    name: {:name, :name_version},
    notes: {:notes, :notes_version},
    stock: {:item_locations, :stock_version}
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "items" do
    field :name, :string
    field :notes, :string, default: ""
    field :name_version, :integer, default: 1
    field :notes_version, :integer, default: 1
    field :stock_version, :integer, default: 1
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

  @doc "The field holding `section`'s version."
  @spec version_field(section()) :: atom()
  def version_field(section), do: elem(Keyword.fetch!(@sections, section), 1)

  @doc """
  Sections that `latest` saved after `base` was read, in page order.
  """
  @spec changed_sections(t, t) :: [section()] when t: %__MODULE__{}
  def changed_sections(%__MODULE__{} = base, %__MODULE__{} = latest) do
    Enum.filter(sections(), fn section ->
      field = version_field(section)
      Map.fetch!(base, field) != Map.fetch!(latest, field)
    end)
  end

  @doc """
  Copies one section's data and version from `latest` into `base`, leaving
  the other sections as `base` had them.
  """
  @spec put_section(t, t, section()) :: t when t: %__MODULE__{}
  def put_section(%__MODULE__{} = base, %__MODULE__{} = latest, section) do
    {data, version} = Keyword.fetch!(@sections, section)
    Map.merge(base, Map.take(latest, [data, version]))
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  defp normalize_newlines(notes) when is_binary(notes), do: String.replace(notes, "\r\n", "\n")
  defp normalize_newlines(nil), do: ""
end
