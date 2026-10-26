defmodule Pinventory.Accounts.ApiToken do
  @moduledoc """
  A bearer token an agent uses to reach Pinventory on a user's behalf.

  Only the SHA-256 of the secret is stored; the secret is shown once when the
  token is made. A token lasts a fixed 6 calendar months from creation and
  use never extends it. Revoking sets `revoked_at`; rows are never deleted
  except with their user, so Settings can show the history.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type status :: :active | :revoked | :expired

  @prefix "pinv_"
  @rand_size 32
  @lifetime_months 6

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :last_used_at, :utc_datetime
    belongs_to :user, Pinventory.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a new token for `user_id` named `name`, created at `now`.

  Returns the raw secret and the changeset to insert.
  """
  @spec build(binary(), String.t() | nil, DateTime.t()) :: {String.t(), Ecto.Changeset.t()}
  def build(user_id, name, %DateTime{} = now) do
    secret = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)

    changeset =
      %__MODULE__{
        user_id: user_id,
        token_hash: hash(secret),
        inserted_at: now,
        expires_at: DateTime.shift(now, month: @lifetime_months)
      }
      |> cast(%{name: name}, [:name])
      |> update_change(:name, &String.trim/1)
      |> validate_required([:name])
      |> validate_length(:name, max: 80)
      |> unique_constraint(:token_hash)

    {secret, changeset}
  end

  @spec hash(String.t()) :: binary()
  def hash(secret) when is_binary(secret), do: :crypto.hash(:sha256, secret)

  @doc "Revoked wins over expired, so a revoked token reads as revoked forever."
  @spec status(t(), DateTime.t()) :: status()
  def status(%__MODULE__{revoked_at: %DateTime{}}, _now), do: :revoked

  def status(%__MODULE__{expires_at: expires_at}, now) do
    if DateTime.compare(expires_at, now) == :gt, do: :active, else: :expired
  end
end
