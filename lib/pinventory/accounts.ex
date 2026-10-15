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

  alias Pinventory.Accounts.{Invite, PasskeyCredential, Scope, User, UserToken, UserNotifier}
  alias Pinventory.Accounts.Passkey.{Assertion, Attestation, Ceremony, RP}

  ## Database getters

  @doc """
  Returns true if at least one user exists.
  """
  def any_users? do
    Repo.exists?(User)
  end

  @doc """
  Lists all users, ordered by email.
  """
  def list_users do
    from(u in User, order_by: [asc: u.email])
    |> Repo.all()
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
    # Hash outside the transaction so Argon2 does not keep a writer transaction open.
    changeset = registration_insert_changeset(attrs)

    if changeset.valid? do
      # SQLite uses database-level writer locks, not Postgres row locks. With
      # default_transaction_mode: :immediate, writers queue; re-check inside the
      # transaction so two concurrent first-user attempts cannot both succeed.
      Repo.transact(fn ->
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

  The registration email must match the invite's bound email
  (case-insensitive). A mismatch returns `{:error, :invalid_or_expired}`
  with the same shape as a bad, expired, used, or revoked token so the
  UI cannot distinguish those cases.

  Uniqueness errors are only returned after the invite is pending **and**
  the email matches. That way a wrong email that already belongs to a user
  cannot surface "has already been taken" on the accept form.

  When format/password precheck passes, Argon2 runs **once before** the
  invite/email branch so match and mismatch pay equal hash cost (timing
  oracle defense for the bound email when a token URL is known). The hash
  is reused on the success path — no double-hash.

  On success the invite is consumed and the user is confirmed.
  Password hashing runs outside the write transaction.
  """
  def register_user_with_invite(plain_token, attrs) when is_binary(plain_token) do
    # Hash outside the transaction (Argon2 is slow). validate_unique: false so
    # uniqueness cannot leak before invite/email match. When this changeset is
    # valid, Argon2 has already run exactly once.
    changeset =
      %User{}
      |> User.registration_changeset(attrs, hash_password: true, validate_unique: false)
      |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now(:second)})

    if changeset.valid? do
      # Invite/match branching runs *after* hashing so invalid_or_expired paths
      # (wrong email, bad/expired/used/revoked token) pay the same Argon2 cost
      # as a matching free email. Do not re-hash on the success path.
      case get_pending_invite_by_token(plain_token) do
        {:error, :invalid_or_expired} ->
          {:error, :invalid_or_expired}

        {:ok, invite} ->
          if Invite.email_matches?(invite, registration_email(attrs)) do
            # Uniqueness only after match — taken wrong emails stay generic.
            changeset = apply_registration_email_uniqueness(changeset)

            if changeset.valid? do
              # SQLite serializes writers at the database level (immediate transactions).
              # Re-read the invite inside the transaction so two concurrent consumers
              # cannot both consume the same ticket.
              Repo.transact(fn ->
                with {:ok, invite} <- get_pending_invite_by_token(plain_token),
                     :ok <- ensure_invite_email_matches(invite, attrs),
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
          else
            {:error, :invalid_or_expired}
          end
      end
    else
      {:error, changeset}
    end
  end

  defp ensure_invite_email_matches(invite, attrs) do
    email = registration_email(attrs)

    if Invite.email_matches?(invite, email) do
      :ok
    else
      {:error, :invalid_or_expired}
    end
  end

  defp registration_email(%{"email" => email}) when is_binary(email), do: email
  defp registration_email(%{email: email}) when is_binary(email), do: email
  defp registration_email(_), do: nil

  defp apply_registration_email_uniqueness(changeset) do
    changeset
    |> Ecto.Changeset.unsafe_validate_unique(:email, Repo)
    |> Ecto.Changeset.unique_constraint(:email)
  end

  defp registration_insert_changeset(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now(:second)})
  end

  ## Invites

  @doc """
  Creates an email-bound invite registration ticket.

  The invite can only be used to register that email (case-insensitive).
  The invite is not sent by email; the creator shares the URL out of band.

  Returns `{:ok, invite, plain_token}`. `created_by` may be a `%Scope{}`,
  `%User{}`, or `nil` (ops / bootstrap tooling).
  """
  def create_invite(email, created_by \\ nil) when is_binary(email) do
    attrs =
      case created_by do
        %Scope{user: %User{id: id}} -> %{created_by_id: id, email: email}
        %User{id: id} -> %{created_by_id: id, email: email}
        _ -> %{email: email}
      end

    {changeset, plain_token} = Invite.build(attrs)

    case Repo.insert(changeset) do
      {:ok, invite} -> {:ok, invite, plain_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for the invite email form (Settings).
  """
  def change_invite(attrs \\ %{}) do
    Invite.email_changeset(attrs)
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

  ## Settings

  # How recently the user must have entered their password (negative offset
  # from now, in minutes). One value for Settings, password change, and
  # on_mount :require_sudo_mode.
  @sudo_mode_minutes -20

  @doc """
  Default sudo-mode window as a negative minute offset (#{@sudo_mode_minutes}).
  """
  def sudo_mode_minutes, do: @sudo_mode_minutes

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes
  (negative offset from now). Defaults to `sudo_mode_minutes/0`.
  """
  def sudo_mode?(user, minutes \\ @sudo_mode_minutes)

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
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Passkeys

  @doc """
  Starts a passkey registration for `user`.

  Returns the `PublicKeyCredentialCreationOptions` for the browser (binary
  fields base64url-encoded) and the ceremony the caller must hold until
  `finish_passkey_registration/3`. The caller enforces sudo mode.
  """
  @spec begin_passkey_registration(User.t()) :: {map(), Ceremony.t()}
  def begin_passkey_registration(%User{} = user) do
    challenge = Wax.new_registration_challenge(rp_opts())
    existing = Repo.all(from c in PasskeyCredential, where: c.user_id == ^user.id)

    options = %{
      challenge: b64(challenge.bytes),
      rp: %{id: challenge.rp_id, name: RP.name()},
      user: %{id: b64(user_handle(user)), name: user.email, displayName: user.email},
      pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
      timeout: challenge.timeout * 1000,
      attestation: "none",
      authenticatorSelection: %{residentKey: "required", userVerification: "preferred"},
      excludeCredentials: Enum.map(existing, &%{type: "public-key", id: b64(&1.credential_id)})
    }

    {options, %Ceremony{kind: :registration, challenge: challenge, user_id: user.id}}
  end

  @doc """
  Verifies a registration response and stores the new passkey.
  """
  @spec finish_passkey_registration(User.t(), Ceremony.t(), Attestation.t(), keyword()) ::
          {:ok, PasskeyCredential.t()} | {:error, :invalid | :duplicate}
  def finish_passkey_registration(user, ceremony, attestation, opts \\ [])

  def finish_passkey_registration(
        %User{id: user_id},
        %Ceremony{kind: :registration, user_id: user_id, challenge: challenge},
        %Attestation{} = att,
        opts
      ) do
    with {:ok, {auth_data, _attestation_result}} <-
           Wax.register(att.attestation_object, att.client_data_json, challenge) do
      acd = auth_data.attested_credential_data

      PasskeyCredential.create_changeset(user_id, %{
        credential_id: acd.credential_id,
        public_key: PasskeyCredential.encode_cose_key(acd.credential_public_key),
        sign_count: auth_data.sign_count,
        aaguid: acd.aaguid,
        transports: att.transports,
        label: opts[:label]
      })
      |> Repo.insert()
      |> case do
        {:ok, cred} -> {:ok, cred}
        {:error, %Ecto.Changeset{}} -> {:error, :duplicate}
      end
    else
      {:error, _} -> {:error, :invalid}
    end
  end

  def finish_passkey_registration(_user, _ceremony, _attestation, _opts), do: {:error, :invalid}

  @doc """
  Starts a passkey authentication.

  Without `:user`, the browser may offer any discoverable passkey for this
  site (no email needed, nothing to enumerate). With `:user` (sudo reauth),
  only that user's active passkeys are allowed, finishing as anyone else
  fails, and user verification (PIN or biometric) is required: possessing
  the device alone must not grant sudo.
  """
  @spec begin_passkey_authentication(keyword()) :: {map(), Ceremony.t()}
  def begin_passkey_authentication(opts \\ []) do
    user = opts[:user]

    allowed =
      if user,
        do:
          Repo.all(
            from c in PasskeyCredential, where: c.user_id == ^user.id and is_nil(c.revoked_at)
          ),
        else: []

    user_verification = if user, do: "required", else: "preferred"

    challenge =
      Wax.new_authentication_challenge([user_verification: user_verification] ++ rp_opts())

    options = %{
      challenge: b64(challenge.bytes),
      rpId: challenge.rp_id,
      timeout: challenge.timeout * 1000,
      userVerification: user_verification,
      allowCredentials:
        Enum.map(
          allowed,
          &%{type: "public-key", id: b64(&1.credential_id), transports: &1.transports}
        )
    }

    {options, %Ceremony{kind: :authentication, challenge: challenge, user_id: user && user.id}}
  end

  @doc """
  Verifies an authentication response. Returns the user on success.

  Every failure is `{:error, :invalid}` so callers cannot leak which check
  failed. The stored signature counter must increase, except that
  authenticators which always report 0 (synced passkeys) stay at 0. The
  counter update is a compare-and-set, so two concurrent uses of one
  assertion cannot both succeed.
  """
  @spec finish_passkey_authentication(Ceremony.t(), Assertion.t()) ::
          {:ok, User.t()} | {:error, :invalid}
  def finish_passkey_authentication(
        %Ceremony{kind: :authentication, challenge: challenge, user_id: bound_user_id},
        %Assertion{} = assertion
      ) do
    with %PasskeyCredential{} = cred <- active_credential(assertion.credential_id),
         true <- is_nil(bound_user_id) or cred.user_id == bound_user_id,
         true <- user_handle_matches?(assertion.user_handle, cred.user_id),
         {:ok, auth_data} <-
           Wax.authenticate(
             assertion.credential_id,
             assertion.authenticator_data,
             assertion.signature,
             assertion.client_data_json,
             challenge,
             [{cred.credential_id, PasskeyCredential.cose_key(cred)}]
           ),
         # Wax already enforces this from the challenge; checked again so a
         # bound (sudo) ceremony can never pass on presence alone.
         true <- is_nil(bound_user_id) or auth_data.flag_user_verified,
         :ok <- advance_sign_count(cred, auth_data.sign_count) do
      {:ok, Repo.get!(User, cred.user_id)}
    else
      _ -> {:error, :invalid}
    end
  end

  def finish_passkey_authentication(_ceremony, _assertion), do: {:error, :invalid}

  defp active_credential(credential_id) when is_binary(credential_id) do
    Repo.one(
      from c in PasskeyCredential,
        where: c.credential_id == ^credential_id and is_nil(c.revoked_at)
    )
  end

  defp user_handle_matches?(nil, _user_id), do: true

  defp user_handle_matches?(handle, user_id) do
    case Ecto.UUID.load(handle) do
      {:ok, ^user_id} -> true
      _ -> false
    end
  end

  defp advance_sign_count(%PasskeyCredential{id: id}, new_count) when is_integer(new_count) do
    now = DateTime.utc_now(:second)

    {count, _} =
      Repo.update_all(
        from(c in PasskeyCredential,
          where: c.id == ^id and is_nil(c.revoked_at),
          where: c.sign_count < ^new_count or (c.sign_count == 0 and ^new_count == 0)
        ),
        set: [sign_count: new_count, last_used_at: now, updated_at: now]
      )

    if count == 1, do: :ok, else: {:error, :sign_count}
  end

  @doc "Active passkeys for `user`, newest first."
  @spec list_passkey_credentials(User.t()) :: [PasskeyCredential.t()]
  def list_passkey_credentials(%User{id: user_id}) do
    Repo.all(
      from c in PasskeyCredential,
        where: c.user_id == ^user_id and is_nil(c.revoked_at),
        order_by: [desc: c.inserted_at, desc: c.id]
    )
  end

  @doc "Revokes one of `user`'s passkeys. Idempotent; other users' ids are `:not_found`."
  @spec revoke_passkey_credential(User.t(), binary()) ::
          {:ok, PasskeyCredential.t()} | {:error, :not_found}
  def revoke_passkey_credential(%User{id: user_id}, id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %PasskeyCredential{} = cred <- Repo.get_by(PasskeyCredential, id: uuid, user_id: user_id) do
      if PasskeyCredential.active?(cred) do
        cred |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second)) |> Repo.update()
      else
        {:ok, cred}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Mints a one-time token the browser posts to `UserSessionController` to turn
  a verified passkey assertion into a session.
  """
  @spec mint_passkey_login_token(User.t()) :: String.t()
  def mint_passkey_login_token(%User{} = user) do
    {token, user_token} = UserToken.build_passkey_login_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Consumes a passkey login token. Returns the user once, then `nil`."
  @spec consume_passkey_login_token(String.t()) :: User.t() | nil
  def consume_passkey_login_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_passkey_login_token_query(token),
         %UserToken{} = row <- Repo.one(query),
         {1, _} <- Repo.delete_all(from t in UserToken, where: t.id == ^row.id) do
      Repo.get(User, row.user_id)
    else
      _ -> nil
    end
  end

  def consume_passkey_login_token(_), do: nil

  defp rp_opts, do: [origin: RP.origin(), rp_id: RP.id(), attestation: "none"]

  defp user_handle(%User{id: id}) do
    {:ok, bin} = Ecto.UUID.dump(id)
    bin
  end

  defp b64(bin), do: Base.url_encode64(bin, padding: false)

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
