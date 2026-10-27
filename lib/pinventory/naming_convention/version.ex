defmodule Pinventory.NamingConvention.Version do
  @moduledoc """
  One saved version of the item naming convention. Rows are only inserted,
  never changed. `via_token_name` is set when an agent saved it with an API
  token.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_length 20_000

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "naming_convention_versions" do
    field :number, :integer
    field :text, :string, default: ""
    field :via_token_name, :string
    belongs_to :user, Pinventory.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          text: String.t(),
          via_token_name: String.t() | nil,
          user: Pinventory.Accounts.User.t() | nil
        }

  @doc false
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:number, :user_id, :via_token_name])
    |> cast(attrs, [:text], empty_values: [nil])
    |> update_change(:text, &String.replace(&1, "\r\n", "\n"))
    |> validate_required([:number])
    |> validate_length(:text, max: @max_length)
    |> unique_constraint(:number)
    |> foreign_key_constraint(:user_id)
  end
end
