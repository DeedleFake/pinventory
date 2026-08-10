defmodule Pinventory.AccountsTest do
  use Pinventory.DataCase

  alias Pinventory.Accounts
  alias Pinventory.Repo

  import Ecto.Query
  import Pinventory.AccountsFixtures
  alias Pinventory.Accounts.{Invite, User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "any_users?/0" do
    test "is false when empty" do
      refute Accounts.any_users?()
    end

    test "is true when a user exists" do
      _user = user_fixture()
      assert Accounts.any_users?()
    end
  end

  describe "register_bootstrap_user/1" do
    test "creates confirmed user with password when no users exist" do
      email = unique_user_email()
      password = valid_user_password()

      assert {:ok, user} =
               Accounts.register_bootstrap_user(%{
                 email: email,
                 password: password,
                 password_confirmation: password
               })

      assert user.email == email
      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(email, password)
    end

    test "fails when users already exist" do
      _existing = user_fixture()

      assert {:error, :registration_closed} =
               Accounts.register_bootstrap_user(%{
                 email: unique_user_email(),
                 password: valid_user_password(),
                 password_confirmation: valid_user_password()
               })
    end

    test "validates password" do
      assert {:error, changeset} =
               Accounts.register_bootstrap_user(%{
                 email: unique_user_email(),
                 password: "short",
                 password_confirmation: "short"
               })

      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end
  end

  describe "create_user/1" do
    test "creates a confirmed user with password" do
      email = unique_user_email()
      password = valid_user_password()

      assert {:ok, user} =
               Accounts.create_user(%{
                 email: email,
                 password: password,
                 password_confirmation: password
               })

      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(email, password)
    end
  end

  describe "list_users/0" do
    test "returns users ordered by email" do
      b = user_fixture(%{email: "b-#{System.unique_integer()}@example.com"})
      a = user_fixture(%{email: "a-#{System.unique_integer()}@example.com"})

      emails = Accounts.list_users() |> Enum.map(& &1.email)
      assert emails == Enum.sort(emails)
      assert a.email in emails
      assert b.email in emails
    end
  end

  describe "invites" do
    test "create_invite requires email and returns invite and plain token" do
      user = user_fixture()
      email = unique_user_email()
      assert {:ok, invite, plain_token} = Accounts.create_invite(email, user)
      assert is_binary(plain_token)
      assert is_binary(invite.token_hash)
      assert invite.email == email
      # Schema has no plain token field; only hash is persisted
      refute Map.has_key?(invite, :token)
      assert invite.created_by_id == user.id
      assert is_nil(invite.used_at)
      assert is_nil(invite.revoked_at)
      assert {:ok, fetched} = Accounts.get_pending_invite_by_token(plain_token)
      assert fetched.id == invite.id
    end

    test "create_invite rejects blank or invalid email" do
      assert {:error, changeset} = Accounts.create_invite("")
      assert %{email: _} = errors_on(changeset)

      assert {:error, changeset} = Accounts.create_invite("not-an-email")
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "list_pending_invites excludes used and revoked" do
      user = user_fixture()
      pending_email = unique_user_email()
      used_email = unique_user_email()
      revoked_email = unique_user_email()

      {:ok, pending, token} = Accounts.create_invite(pending_email, user)
      {:ok, used_invite, used_token} = Accounts.create_invite(used_email, user)
      {:ok, revoked, _} = Accounts.create_invite(revoked_email, user)

      assert {:ok, _} =
               Accounts.register_user_with_invite(used_token, %{
                 email: used_email,
                 password: valid_user_password(),
                 password_confirmation: valid_user_password()
               })

      assert {:ok, _} = Accounts.revoke_invite(revoked)

      pending_ids = Accounts.list_pending_invites() |> Enum.map(& &1.id)
      assert pending.id in pending_ids
      refute used_invite.id in pending_ids
      refute revoked.id in pending_ids
      assert {:ok, _} = Accounts.get_pending_invite_by_token(token)
    end

    test "register_user_with_invite creates confirmed user and consumes token" do
      _admin = user_fixture()
      {invite, token} = invite_fixture()
      password = valid_user_password()

      assert {:ok, user} =
               Accounts.register_user_with_invite(token, %{
                 email: invite.email,
                 password: password,
                 password_confirmation: password
               })

      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(invite.email, password)
      assert {:error, :invalid_or_expired} = Accounts.get_pending_invite_by_token(token)

      # Reuse attempt with a free email still fails: invite is already consumed.
      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite(token, %{
                 email: unique_user_email(),
                 password: password,
                 password_confirmation: password
               })
    end

    test "register_user_with_invite accepts case-insensitive email match" do
      _admin = user_fixture()
      {_invite, token} = invite_fixture(email: "Bound.User@Example.com")
      password = valid_user_password()

      assert {:ok, user} =
               Accounts.register_user_with_invite(token, %{
                 email: "bound.user@example.com",
                 password: password,
                 password_confirmation: password
               })

      assert Accounts.get_user_by_email_and_password("bound.user@example.com", password)
      assert user.email == "bound.user@example.com"
    end

    test "register_user_with_invite rejects email mismatch as invalid_or_expired" do
      _admin = user_fixture()
      {invite, token} = invite_fixture()
      password = valid_user_password()

      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite(token, %{
                 email: unique_user_email(),
                 password: password,
                 password_confirmation: password
               })

      # Invite stays pending so the intended recipient can still register
      assert {:ok, still_pending} = Accounts.get_pending_invite_by_token(token)
      assert still_pending.id == invite.id
    end

    test "register_user_with_invite rejects taken wrong email as invalid_or_expired" do
      existing = user_fixture()
      {invite, token} = invite_fixture()
      password = valid_user_password()

      # Wrong email that already belongs to a user must not leak uniqueness
      # ("has already been taken") — same generic error as a free wrong email.
      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite(token, %{
                 email: existing.email,
                 password: password,
                 password_confirmation: password
               })

      assert {:ok, still_pending} = Accounts.get_pending_invite_by_token(token)
      assert still_pending.id == invite.id
    end

    test "register_user_with_invite success stores hashed password once without password field" do
      _admin = user_fixture()
      {invite, token} = invite_fixture()
      password = valid_user_password()

      assert {:ok, user} =
               Accounts.register_user_with_invite(token, %{
                 email: invite.email,
                 password: password,
                 password_confirmation: password
               })

      reloaded = Accounts.get_user!(user.id)
      assert is_binary(reloaded.hashed_password)
      assert reloaded.hashed_password != password
      assert is_nil(reloaded.password)
      assert Accounts.get_user_by_email_and_password(invite.email, password)
    end

    test "register_user_with_invite rejects invalid token even when email is taken" do
      existing = user_fixture()
      password = valid_user_password()

      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite("bad-token", %{
                 email: existing.email,
                 password: password,
                 password_confirmation: password
               })
    end

    test "register_user_with_invite rejects invalid token" do
      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite("bad-token", %{
                 email: unique_user_email(),
                 password: valid_user_password(),
                 password_confirmation: valid_user_password()
               })
    end

    test "register_user_with_invite rejects expired invite" do
      {invite, token} = invite_fixture()
      {:ok, pending} = Accounts.get_pending_invite_by_token(token)

      past = DateTime.utc_now(:second) |> DateTime.add(-1, :day)

      {1, _} =
        Repo.update_all(from(i in Invite, where: i.id == ^pending.id), set: [expires_at: past])

      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite(token, %{
                 email: invite.email,
                 password: valid_user_password(),
                 password_confirmation: valid_user_password()
               })
    end

    test "failed registration does not consume invite" do
      existing = user_fixture()
      {_invite, token} = invite_fixture(email: existing.email)
      password = valid_user_password()

      assert {:error, %Ecto.Changeset{}} =
               Accounts.register_user_with_invite(token, %{
                 email: existing.email,
                 password: password,
                 password_confirmation: password
               })

      assert {:ok, _invite} = Accounts.get_pending_invite_by_token(token)
    end

    test "revoke_invite prevents registration" do
      {invite, token} = invite_fixture()
      pending = Accounts.get_pending_invite_by_token(token) |> then(fn {:ok, i} -> i end)
      assert {:ok, _} = Accounts.revoke_invite(pending)

      assert {:error, :invalid_or_expired} =
               Accounts.register_user_with_invite(token, %{
                 email: invite.email,
                 password: valid_user_password(),
                 password_confirmation: valid_user_password()
               })
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()
      assert Accounts.sudo_mode_minutes() == -20

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # custom shorter window still works
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
