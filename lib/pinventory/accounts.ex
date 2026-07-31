defmodule Pinventory.Accounts do
  @moduledoc """
  The Accounts context.

  Pinventory is a private app:

  * The first user is created via bootstrap registration (email + password).
  * Later users join with one-time invite tickets or ops helpers.
  * Daily login is email + password only.
  """

  import Ecto.Query, warn: false
  alias Pinventory.Repo

  alias Pinventory.Accounts.{Invite, Scope, User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Returns true if at least one user exists.
  """
  def any_users? do
    Repo.exists?(User)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Returns an `%Ecto.Changeset{}` for registration forms (email + password).
  """
  def change_user_registration(user \\ %User{}, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Registers the first user when no users exist yet.

  Creates a confirmed user with email and password. Race-safe: fails with
  `{:error, :registration_closed}` if another user was created concurrently.

  ## Examples

      iex> register_bootstrap_user(%{email: "a@b.c", password: "long password"})
      {:ok, %User{}}

      iex> register_bootstrap_user(%{})
      {:error, %Ecto.Changeset{}}

  """
  def register_bootstrap_user(attrs) do
    # Hash password outside the transaction so Argon2 does not hold table locks.
    changeset = registration_insert_changeset(attrs)

    if changeset.valid? do
      Repo.transact(fn ->
        # Serialize bootstrap so two concurrent first-user attempts cannot both succeed.
        Repo.query!("LOCK TABLE \"user\" IN EXCLUSIVE MODE")

        if any_users?() do
          {:error, :registration_closed}
        else
          Repo.insert(changeset)
        end
      end)
    else
      {:error, changeset}
    end
  end

  @doc """
  Creates a confirmed user with email and password (ops / release helper).

  Does not require an invite and is always available to trusted operators.
  """
  def create_user(attrs) do
    attrs
    |> registration_insert_changeset()
    |> Repo.insert()
  end

  @doc """
  Registers a user with a valid one-time invite token.

  On success the invite is consumed and the user is confirmed.
  Password hashing runs outside the invite lock transaction.
  """
  def register_user_with_invite(plain_token, attrs) when is_binary(plain_token) do
    # Hash password outside the transaction so Argon2 does not hold row locks.
    changeset = registration_insert_changeset(attrs)

    if changeset.valid? do
      Repo.transact(fn ->
        with {:ok, invite} <- fetch_pending_invite_for_update(plain_token),
             {:ok, user} <- Repo.insert(changeset),
             {:ok, _invite} <- Repo.update(Invite.use_changeset(invite, user.id)) do
          {:ok, user}
        else
          {:error, :invalid_or_expired} ->
            {:error, :invalid_or_expired}

          {:error, %Ecto.Changeset{} = err_changeset} ->
            {:error, err_changeset}
        end
      end)
    else
      {:error, changeset}
    end
  end

  defp registration_insert_changeset(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now(:second)})
  end

  @doc """
  Registers a user with email only (legacy magic-link path / tests).

  Prefer `register_bootstrap_user/1`, `register_user_with_invite/2`, or
  `create_user/1` for application flows.
  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Invites

  @doc """
  Creates a blank invite registration ticket.

  Returns `{:ok, invite, plain_token}`. `created_by` may be a `%Scope{}`,
  `%User{}`, or `nil` (ops / bootstrap tooling).
  """
  def create_invite(created_by \\ nil) do
    attrs =
      case created_by do
        %Scope{user: %User{id: id}} -> %{created_by_id: id}
        %User{id: id} -> %{created_by_id: id}
        _ -> %{}
      end

    {changeset, plain_token} = Invite.build(attrs)

    case Repo.insert(changeset) do
      {:ok, invite} -> {:ok, invite, plain_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Lists pending invites (not used, not revoked, not expired), newest first.
  """
  def list_pending_invites do
    now = DateTime.utc_now(:second)

    from(i in Invite,
      where: is_nil(i.revoked_at) and is_nil(i.used_at) and i.expires_at > ^now,
      order_by: [desc: i.inserted_at],
      preload: [:created_by]
    )
    |> Repo.all()
  end

  @doc """
  Gets a pending invite by id, or `nil`.
  """
  def get_pending_invite(id) do
    now = DateTime.utc_now(:second)

    from(i in Invite,
      where: i.id == ^id and is_nil(i.revoked_at) and is_nil(i.used_at) and i.expires_at > ^now
    )
    |> Repo.one()
  end

  @doc """
  Returns `{:ok, invite}` when the plain token is valid and pending.
  """
  def get_pending_invite_by_token(plain_token) when is_binary(plain_token) do
    with {:ok, token_hash} <- Invite.hash_token(plain_token),
         %Invite{} = invite <- Repo.get_by(Invite, token_hash: token_hash),
         true <- Invite.pending?(invite) do
      {:ok, invite}
    else
      _ -> {:error, :invalid_or_expired}
    end
  end

  @doc """
  Revokes a pending invite so it can no longer be used.
  """
  def revoke_invite(invite_or_id)

  def revoke_invite(%Invite{} = invite) do
    if Invite.pending?(invite) do
      Repo.update(Invite.revoke_changeset(invite))
    else
      {:error, :not_pending}
    end
  end

  def revoke_invite(id) when is_binary(id) do
    case Repo.get(Invite, id) do
      nil -> {:error, :not_found}
      invite -> revoke_invite(invite)
    end
  end

  @doc """
  Builds the relative registration path for an invite token.
  """
  def invite_path(plain_token) when is_binary(plain_token) do
    "/user/invite/" <> plain_token
  end

  defp fetch_pending_invite_for_update(plain_token) do
    with {:ok, token_hash} <- Invite.hash_token(plain_token) do
      invite =
        from(i in Invite, where: i.token_hash == ^token_hash, lock: "FOR UPDATE")
        |> Repo.one()

      if invite && Invite.pending?(invite) do
        {:ok, invite}
      else
        {:error, :invalid_or_expired}
      end
    else
      :error -> {:error, :invalid_or_expired}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Pinventory.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Pinventory.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/user/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
