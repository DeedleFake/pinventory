defmodule Pinventory.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Pinventory.Accounts` context.
  """

  import Ecto.Query

  alias Pinventory.Accounts
  alias Pinventory.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def valid_user_password_attributes(attrs \\ %{}) do
    attrs
    |> valid_user_attributes()
    |> Map.put_new(:password, valid_user_password())
    |> Map.put_new(:password_confirmation, Map.get(attrs, :password) || valid_user_password())
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_password_attributes()
      |> Accounts.create_user()

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Pinventory.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Pinventory.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  Creates a pending invite.

  ## Options

    * `:email` — bound registration email (default: unique fixture email)
    * `:created_by` — `%User{}`, `%Scope{}`, or `nil`

  ## Examples

      invite_fixture()
      invite_fixture(email: "user@example.com")
      invite_fixture(created_by: user, email: "user@example.com")
  """
  def invite_fixture(opts \\ [])

  def invite_fixture(opts) when is_list(opts) do
    email = Keyword.get_lazy(opts, :email, &unique_user_email/0)
    created_by = Keyword.get(opts, :created_by)
    {:ok, invite, plain_token} = Accounts.create_invite(email, created_by)
    {invite, plain_token}
  end

  # Back-compat: invite_fixture(user) where user is a %User{} or similar struct
  def invite_fixture(%_{} = created_by) do
    invite_fixture(created_by: created_by)
  end
end
