defmodule Pinventory.Accounts.PasskeyCredential do
  @moduledoc """
  A WebAuthn credential (passkey) registered to a user.

  Lifecycle is a single field: `revoked_at` is `nil` while the passkey is
  active and set once it is revoked. Revoked rows are kept so a revoked
  credential id can never be re-registered or used again.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_passkeys" do
    field :credential_id, :binary
    # COSE key map as an Erlang term (Wax.CoseKey.t()).
    field :public_key, :binary, redact: true
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :transports, {:array, :string}, default: []
    field :label, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :user, Pinventory.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(user_id, attrs) do
    %__MODULE__{user_id: user_id}
    |> cast(attrs, [:credential_id, :public_key, :sign_count, :aaguid, :transports, :label])
    |> validate_required([:credential_id, :public_key, :sign_count])
    |> validate_length(:label, max: 80)
    |> unique_constraint(:credential_id)
  end

  def active?(%__MODULE__{revoked_at: revoked_at}), do: is_nil(revoked_at)

  @doc "Decoded COSE public key for Wax."
  def cose_key(%__MODULE__{public_key: bin}), do: :erlang.binary_to_term(bin, [:safe])

  def encode_cose_key(cose_key), do: :erlang.term_to_binary(cose_key)
end
