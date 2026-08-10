defmodule Pinventory.Accounts.Invite do
  @moduledoc """
  One-time registration invite bound to a single email address.

  Only the token hash is stored. The plain URL token is returned once from
  `build/1` / `Accounts.create_invite/2` and is not persisted.

  The bound email is stored so registration can enforce a match. The accept
  form must not pre-fill or display it (avoids leaking the email to anyone
  with the URL).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @hash_algorithm :sha256
  @rand_size 32
  @default_validity_in_days 7

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invites" do
    field :token_hash, :binary, redact: true
    field :email, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :created_by, Pinventory.Accounts.User
    belongs_to :used_by, Pinventory.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a new invite changeset with a random token, expiry, and bound email.

  Returns `{changeset, plain_token}` where `plain_token` is URL-safe and is
  not stored on the changeset (only `token_hash` is).

  `attrs` must include `:email` (or `"email"`). Optional `:created_by_id`.
  """
  def build(attrs \\ %{}) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    plain_token = Base.url_encode64(raw, padding: false)
    token_hash = :crypto.hash(@hash_algorithm, raw)

    expires_at =
      DateTime.utc_now(:second)
      |> DateTime.add(@default_validity_in_days, :day)

    changeset =
      %__MODULE__{}
      |> cast(attrs, [:created_by_id, :email])
      |> put_change(:token_hash, token_hash)
      |> put_change(:expires_at, expires_at)
      |> validate_email()
      |> validate_required([:token_hash, :expires_at])

    {changeset, plain_token}
  end

  @doc """
  Changeset for invite email input (Settings form validation).
  """
  def email_changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:email])
    |> validate_email()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
  end

  @doc """
  Hashes a plain URL token for lookup.
  """
  def hash_token(plain_token) when is_binary(plain_token) do
    case Base.url_decode64(plain_token, padding: false) do
      {:ok, raw} -> {:ok, :crypto.hash(@hash_algorithm, raw)}
      :error -> :error
    end
  end

  @doc """
  Returns true when the invite can still be used for registration.
  """
  def pending?(%__MODULE__{} = invite, now \\ DateTime.utc_now(:second)) do
    is_nil(invite.revoked_at) and is_nil(invite.used_at) and
      DateTime.compare(invite.expires_at, now) == :gt
  end

  @doc """
  Case-insensitive email match (same spirit as users.email NOCASE uniqueness).
  """
  def email_matches?(%__MODULE__{email: bound}, email)
      when is_binary(bound) and is_binary(email) do
    String.downcase(bound) == String.downcase(email)
  end

  def email_matches?(_, _), do: false

  @doc """
  Marks an invite as revoked.
  """
  def revoke_changeset(%__MODULE__{} = invite) do
    change(invite, revoked_at: DateTime.utc_now(:second))
  end

  @doc """
  Marks an invite as used by the given user.
  """
  def use_changeset(%__MODULE__{} = invite, user_id) do
    change(invite, used_at: DateTime.utc_now(:second), used_by_id: user_id)
  end

  def default_validity_in_days, do: @default_validity_in_days
end
