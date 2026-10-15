defmodule Pinventory.AccountsPasskeyTest do
  use Pinventory.DataCase, async: false

  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts
  alias Pinventory.Accounts.{PasskeyCredential, UserToken}
  alias Pinventory.SoftAuthenticator
  alias PinventoryWeb.Passkey.Wire

  defp register(user, auth \\ SoftAuthenticator.new()) do
    {options, ceremony} = Accounts.begin_passkey_registration(user)
    {:ok, att} = auth |> SoftAuthenticator.create(options) |> Wire.attestation()
    {:ok, cred} = Accounts.finish_passkey_registration(user, ceremony, att)
    {%{auth | user_handle: Ecto.UUID.dump!(user.id)}, cred}
  end

  defp assert_with(auth, opts \\ [], begin_opts \\ []) do
    {options, ceremony} = Accounts.begin_passkey_authentication(begin_opts)
    {:ok, assertion} = auth |> SoftAuthenticator.get(options, opts) |> Wire.assertion()
    Accounts.finish_passkey_authentication(ceremony, assertion)
  end

  describe "registration" do
    test "stores an active credential for the user" do
      user = user_fixture()
      {auth, cred} = register(user)

      assert cred.user_id == user.id
      assert cred.credential_id == auth.credential_id
      assert cred.transports == ["internal"]
      assert PasskeyCredential.active?(cred)
      assert [%{id: id}] = Accounts.list_passkey_credentials(user)
      assert id == cred.id
    end

    test "creation options request discoverable credentials and exclude existing ones" do
      user = user_fixture()
      {auth, _} = register(user)
      {options, _} = Accounts.begin_passkey_registration(user)

      assert options.rp.id == "localhost"
      assert options.authenticatorSelection.residentKey == "required"
      assert [%{id: excluded}] = options.excludeCredentials
      assert Base.url_decode64!(excluded, padding: false) == auth.credential_id
    end

    test "rejects a ceremony bound to another user" do
      user = user_fixture()
      other = user_fixture()
      {options, ceremony} = Accounts.begin_passkey_registration(other)

      {:ok, att} =
        SoftAuthenticator.new() |> SoftAuthenticator.create(options) |> Wire.attestation()

      assert {:error, :invalid} = Accounts.finish_passkey_registration(user, ceremony, att)
    end

    test "rejects an authentication ceremony (kind mismatch)" do
      user = user_fixture()
      {options, _} = Accounts.begin_passkey_registration(user)
      {_, auth_ceremony} = Accounts.begin_passkey_authentication()

      {:ok, att} =
        SoftAuthenticator.new() |> SoftAuthenticator.create(options) |> Wire.attestation()

      assert {:error, :invalid} =
               Accounts.finish_passkey_registration(
                 user,
                 %{auth_ceremony | user_id: user.id},
                 att
               )
    end

    test "rejects a wrong origin" do
      user = user_fixture()
      {options, ceremony} = Accounts.begin_passkey_registration(user)

      {:ok, att} =
        SoftAuthenticator.new()
        |> SoftAuthenticator.create(options, origin: "https://evil.example")
        |> Wire.attestation()

      assert {:error, :invalid} = Accounts.finish_passkey_registration(user, ceremony, att)
    end

    test "rejects registering the same credential twice" do
      user = user_fixture()
      {auth, _} = register(user)
      {options, ceremony} = Accounts.begin_passkey_registration(user)
      {:ok, att} = auth |> SoftAuthenticator.create(options) |> Wire.attestation()

      assert {:error, :duplicate} = Accounts.finish_passkey_registration(user, ceremony, att)
    end

    test "a revoked passkey can be registered again" do
      user = user_fixture()
      {auth, old} = register(user)
      {:ok, _} = Accounts.revoke_passkey_credential(user, old.id)

      {options, ceremony} = Accounts.begin_passkey_registration(user)
      assert options.excludeCredentials == []
      {:ok, att} = auth |> SoftAuthenticator.create(options) |> Wire.attestation()

      assert {:ok, new} = Accounts.finish_passkey_registration(user, ceremony, att)
      assert new.id != old.id
      assert [%{id: id}] = Accounts.list_passkey_credentials(user)
      assert id == new.id
      assert {:ok, _} = assert_with(auth)
    end

    test "non-constraint insert failures are :invalid, not :duplicate" do
      user = user_fixture()
      {options, ceremony} = Accounts.begin_passkey_registration(user)

      {:ok, att} =
        SoftAuthenticator.new() |> SoftAuthenticator.create(options) |> Wire.attestation()

      assert {:error, :invalid} =
               Accounts.finish_passkey_registration(user, ceremony, att,
                 label: String.duplicate("x", 81)
               )
    end
  end

  describe "authentication" do
    test "discoverable login returns the user with no email" do
      user = user_fixture()
      {auth, _} = register(user)

      {options, _} = Accounts.begin_passkey_authentication()
      assert options.allowCredentials == []

      assert {:ok, %{id: id}} = assert_with(auth, user_handle: Ecto.UUID.dump!(user.id))
      assert id == user.id
    end

    test "updates sign_count and last_used_at" do
      user = user_fixture()
      {auth, cred} = register(user)
      assert {:ok, _} = assert_with(auth, sign_count: 5)

      reloaded = Repo.get!(PasskeyCredential, cred.id)
      assert reloaded.sign_count == 5
      assert reloaded.last_used_at
    end

    test "rejects a counter that does not increase" do
      user = user_fixture()
      {auth, _} = register(user)
      assert {:ok, _} = assert_with(auth, sign_count: 5)
      assert {:error, :invalid} = assert_with(auth, sign_count: 5)
      assert {:error, :invalid} = assert_with(auth, sign_count: 4)
      assert {:ok, _} = assert_with(auth, sign_count: 6)
    end

    test "allows authenticators that always report 0" do
      user = user_fixture()
      {auth, _} = register(user)
      assert {:ok, _} = assert_with(auth, sign_count: 0)
      assert {:ok, _} = assert_with(auth, sign_count: 0)
    end

    test "rejects a counter reset to 0 after it advanced" do
      user = user_fixture()
      {auth, _} = register(user)
      assert {:ok, _} = assert_with(auth, sign_count: 3)
      assert {:error, :invalid} = assert_with(auth, sign_count: 0)
    end

    test "rejects revoked passkeys" do
      user = user_fixture()
      {auth, cred} = register(user)
      assert {:ok, _} = Accounts.revoke_passkey_credential(user, cred.id)
      assert {:error, :invalid} = assert_with(auth)
    end

    test "rejects unknown credentials and bad signatures" do
      user = user_fixture()
      {auth, _} = register(user)
      assert {:error, :invalid} = assert_with(SoftAuthenticator.new())

      imposter = %{SoftAuthenticator.new() | credential_id: auth.credential_id}
      assert {:error, :invalid} = assert_with(imposter)
    end

    test "rejects a mismatched user handle" do
      user = user_fixture()
      {auth, _} = register(user)
      assert {:error, :invalid} = assert_with(auth, user_handle: Ecto.UUID.bingenerate())
      assert {:error, :invalid} = assert_with(auth, user_handle: nil)
    end

    test "rejects a signature over a different challenge" do
      user = user_fixture()
      {auth, _} = register(user)
      other = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :invalid} = assert_with(auth, challenge: other)
    end

    test "rejects a registration ceremony (kind mismatch)" do
      user = user_fixture()
      {auth, _} = register(user)
      {options, _} = Accounts.begin_passkey_authentication()
      {_, reg} = Accounts.begin_passkey_registration(user)
      {:ok, assertion} = auth |> SoftAuthenticator.get(options) |> Wire.assertion()

      assert {:error, :invalid} = Accounts.finish_passkey_authentication(reg, assertion)
    end

    test "rejects an expired challenge" do
      user = user_fixture()
      {auth, _} = register(user)
      {options, ceremony} = Accounts.begin_passkey_authentication()

      expired = %{
        ceremony
        | challenge: %{ceremony.challenge | issued_at: ceremony.challenge.issued_at - 121}
      }

      {:ok, assertion} = auth |> SoftAuthenticator.get(options) |> Wire.assertion()

      assert {:error, :invalid} = Accounts.finish_passkey_authentication(expired, assertion)
    end

    test "a user-bound ceremony only allows that user's passkeys" do
      user = user_fixture()
      other = user_fixture()
      {auth, cred} = register(user)
      {other_auth, _} = register(other)

      {options, _} = Accounts.begin_passkey_authentication(user: user)
      assert [%{id: id}] = options.allowCredentials
      assert Base.url_decode64!(id, padding: false) == cred.credential_id

      assert {:ok, _} = assert_with(auth, [], user: user)
      assert {:error, :invalid} = assert_with(other_auth, [], user: user)
    end

    test "sudo (user-bound) ceremonies require user verification" do
      user = user_fixture()
      {auth, _} = register(user)

      {options, _} = Accounts.begin_passkey_authentication(user: user)
      assert options.userVerification == "required"
      assert {:error, :invalid} = assert_with(auth, [flags: 0x01], user: user)
      assert {:ok, _} = assert_with(auth, [sign_count: 2], user: user)
    end

    test "bound ceremonies reject missing UV even if the challenge did not require it" do
      user = user_fixture()
      {auth, _} = register(user)
      {options, ceremony} = Accounts.begin_passkey_authentication()
      ceremony = %{ceremony | user_id: user.id}

      {:ok, assertion} =
        auth |> SoftAuthenticator.get(options, flags: 0x01) |> Wire.assertion()

      assert {:error, :invalid} = Accounts.finish_passkey_authentication(ceremony, assertion)
    end

    test "discoverable login prefers but does not require user verification" do
      user = user_fixture()
      {auth, _} = register(user)

      {options, _} = Accounts.begin_passkey_authentication()
      assert options.userVerification == "preferred"
      assert {:ok, _} = assert_with(auth, flags: 0x01)
    end
  end

  describe "revoke_passkey_credential/2" do
    test "is idempotent and hides the credential from the list" do
      user = user_fixture()
      {_, cred} = register(user)

      assert {:ok, {%{revoked_at: %DateTime{} = at}, _}} =
               Accounts.revoke_passkey_credential(user, cred.id)

      assert {:ok, {%{revoked_at: ^at}, []}} = Accounts.revoke_passkey_credential(user, cred.id)
      assert Accounts.list_passkey_credentials(user) == []
    end

    test "cannot revoke another user's passkey" do
      user = user_fixture()
      {_, cred} = register(user_fixture())
      assert {:error, :not_found} = Accounts.revoke_passkey_credential(user, cred.id)
      assert {:error, :not_found} = Accounts.revoke_passkey_credential(user, "not-a-uuid")
      assert Repo.get!(PasskeyCredential, cred.id).revoked_at == nil
    end

    test "signs out every other session but keeps the given one" do
      user = user_fixture()
      {_, cred} = register(user)
      keep = Accounts.generate_user_session_token(user)
      other = Accounts.generate_user_session_token(user)

      assert {:ok, {_, expired}} =
               Accounts.revoke_passkey_credential(user, cred.id, keep_session_token: keep)

      assert Enum.any?(expired, &(&1.token == other))
      refute Enum.any?(expired, &(&1.token == keep))
      assert Accounts.get_user_by_session_token(keep)
      refute Accounts.get_user_by_session_token(other)
    end
  end

  describe "update_user_password/2 and passkeys" do
    test "revokes every passkey of the user" do
      user = user_fixture()
      {auth, _} = register(user)
      {_, _} = register(user)
      {_, theirs} = register(user_fixture())

      assert {:ok, _} = Accounts.update_user_password(user, %{password: "a new valid password"})

      assert Accounts.list_passkey_credentials(user) == []
      assert Repo.get!(PasskeyCredential, theirs.id).revoked_at == nil
      assert {:error, :invalid} = assert_with(auth)
    end

    test "leaves passkeys alone when the password is invalid" do
      user = user_fixture()
      register(user)

      assert {:error, _} = Accounts.update_user_password(user, %{password: "short"})
      assert [_] = Accounts.list_passkey_credentials(user)
    end
  end

  describe "passkey login tokens" do
    test "are single use" do
      user = user_fixture()
      token = Accounts.mint_passkey_login_token(user, "b")
      assert %{id: id} = Accounts.consume_passkey_login_token(token, "b")
      assert id == user.id
      assert Accounts.consume_passkey_login_token(token, "b") == nil
    end

    test "expire after 60 seconds" do
      user = user_fixture()
      token = Accounts.mint_passkey_login_token(user, "b")

      Repo.update_all(from(t in UserToken, where: t.context == "passkey_login"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -61)]
      )

      assert Accounts.consume_passkey_login_token(token, "b") == nil
    end

    test "reject garbage" do
      assert Accounts.consume_passkey_login_token("nope!", "b") == nil
      assert Accounts.consume_passkey_login_token(nil, "b") == nil
    end

    test "only work with the binding they were minted with" do
      user = user_fixture()
      token = Accounts.mint_passkey_login_token(user, "b")
      assert Accounts.consume_passkey_login_token(token, "other") == nil
      assert Accounts.consume_passkey_login_token(token, nil) == nil
      assert %{} = Accounts.consume_passkey_login_token(token, "b")
    end
  end
end
