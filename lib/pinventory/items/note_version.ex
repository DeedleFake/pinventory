defmodule Pinventory.Items.NoteVersion do
  @moduledoc """
  One saved version of an item's notes. `number` 0 is the empty note every
  item starts with and has no author, time, or event.
  """

  @enforce_keys [:number, :text]
  defstruct [:number, :text, :user, :inserted_at, :event_id]

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          text: String.t(),
          user: %Pinventory.Accounts.User{} | nil,
          inserted_at: DateTime.t() | nil,
          event_id: Ecto.UUID.t() | nil
        }
end
