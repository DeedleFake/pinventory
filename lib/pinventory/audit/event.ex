defmodule Pinventory.Audit.Event do
  @moduledoc """
  Append-only audit event. One row per individual change; rows that share
  `edit_id` come from the same user action.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(
    item.created
    item.updated
    item.deleted
    location.created
    location.updated
    stock.changed
  )

  @entity_types ~w(item location item_location)

  schema "audit_events" do
    field :edit_id, :binary_id
    field :edit_seq, :integer, default: 0
    field :action, :string
    field :entity_type, :string
    field :entity_id, :binary_id
    field :item_id, :binary_id
    field :location_id, :binary_id
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :user, Pinventory.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def actions, do: @actions
  def entity_types, do: @entity_types

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :edit_id,
      :edit_seq,
      :user_id,
      :action,
      :entity_type,
      :entity_id,
      :item_id,
      :location_id,
      :changes,
      :metadata
    ])
    |> validate_required([
      :edit_id,
      :edit_seq,
      :action,
      :entity_type,
      :entity_id
    ])
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:entity_type, @entity_types)
    |> foreign_key_constraint(:user_id)
  end
end
