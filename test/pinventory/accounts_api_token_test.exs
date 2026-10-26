defmodule Pinventory.AccountsApiTokenTest do
  use Pinventory.DataCase, async: true

  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts
  alias Pinventory.Accounts.ApiToken

  defp set_token(token, fields) do
    Repo.update_all(from(t in ApiToken, where: t.id == ^token.id), set: fields)
  end

  describe "create_api_token/2" do
    test "returns a secret that looks up to the user's scope" do
      user = user_fixture()
      assert {:ok, {secret, token}} = Accounts.create_api_token(user, "  Claude on phone ")

      assert token.name == "Claude on phone"
      assert "pinv_" <> _ = secret
      refute token.token_hash == secret

      assert {:ok, scope} = Accounts.fetch_scope_for_api_token(secret)
      assert scope.user.id == user.id
      assert scope.api_token.id == token.id
    end

    test "expires 6 calendar months after creation" do
      {:ok, {_secret, token}} = Accounts.create_api_token(user_fixture(), "agent")
      assert token.expires_at == DateTime.shift(token.inserted_at, month: 6)
    end

    test "requires a name" do
      assert {:error, changeset} = Accounts.create_api_token(user_fixture(), "   ")
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "fetch_scope_for_api_token/1" do
    test "records when the token was last used" do
      user = user_fixture()
      {:ok, {secret, _}} = Accounts.create_api_token(user, "agent")
      assert [%{last_used_at: nil}] = Accounts.list_api_tokens(user)

      assert {:ok, _} = Accounts.fetch_scope_for_api_token(secret)
      assert [%{last_used_at: %DateTime{}}] = Accounts.list_api_tokens(user)
    end

    test "rejects unknown, revoked, and expired tokens" do
      user = user_fixture()
      assert :error = Accounts.fetch_scope_for_api_token("pinv_nope")

      {:ok, {revoked, revoked_token}} = Accounts.create_api_token(user, "revoked")
      {:ok, _} = Accounts.revoke_api_token(user, revoked_token.id)
      assert :error = Accounts.fetch_scope_for_api_token(revoked)

      {:ok, {expired, expired_token}} = Accounts.create_api_token(user, "expired")
      set_token(expired_token, expires_at: DateTime.add(DateTime.utc_now(:second), -1))
      assert :error = Accounts.fetch_scope_for_api_token(expired)
    end

    test "keeps working after a password change" do
      user = user_fixture()
      {:ok, {secret, _}} = Accounts.create_api_token(user, "agent")

      {:ok, _} = Accounts.update_user_password(user, %{password: "a brand new password"})

      assert {:ok, _} = Accounts.fetch_scope_for_api_token(secret)
    end
  end

  describe "revoke_api_token/2" do
    test "keeps the row and the first revocation time" do
      user = user_fixture()
      {:ok, {_, token}} = Accounts.create_api_token(user, "agent")

      {:ok, revoked} = Accounts.revoke_api_token(user, token.id)
      assert ApiToken.status(revoked, DateTime.utc_now()) == :revoked

      set_token(token, revoked_at: ~U[2026-01-01 00:00:00Z])

      assert {:ok, %{revoked_at: ~U[2026-01-01 00:00:00Z]}} =
               Accounts.revoke_api_token(user, token.id)

      assert [%{id: id}] = Accounts.list_api_tokens(user)
      assert id == token.id
    end

    test "does not touch another user's token" do
      {:ok, {secret, token}} = Accounts.create_api_token(user_fixture(), "agent")

      assert {:error, :not_found} = Accounts.revoke_api_token(user_fixture(), token.id)
      assert {:error, :not_found} = Accounts.revoke_api_token(user_fixture(), "not-a-uuid")
      assert {:ok, _} = Accounts.fetch_scope_for_api_token(secret)
    end
  end

  describe "revoke_all_api_tokens/1" do
    test "revokes only the user's unrevoked tokens" do
      user = user_fixture()
      {:ok, {a, _}} = Accounts.create_api_token(user, "a")
      {:ok, {b, _}} = Accounts.create_api_token(user, "b")
      {:ok, {_, c}} = Accounts.create_api_token(user, "c")
      {:ok, _} = Accounts.revoke_api_token(user, c.id)
      {:ok, {other, _}} = Accounts.create_api_token(user_fixture(), "other")

      assert Accounts.revoke_all_api_tokens(user) == 2

      assert :error = Accounts.fetch_scope_for_api_token(a)
      assert :error = Accounts.fetch_scope_for_api_token(b)
      assert {:ok, _} = Accounts.fetch_scope_for_api_token(other)
      assert length(Accounts.list_api_tokens(user)) == 3
    end
  end

  describe "replace_api_token/2" do
    test "makes a new working token with the same name, even from a revoked one" do
      user = user_fixture()
      {:ok, {old_secret, old}} = Accounts.create_api_token(user, "Claude on phone")
      {:ok, _} = Accounts.revoke_api_token(user, old.id)

      assert {:ok, {new_secret, new}} = Accounts.replace_api_token(user, old.id)

      assert new.name == "Claude on phone"
      refute new.id == old.id
      refute new_secret == old_secret
      assert {:ok, %{api_token: %{id: id}}} = Accounts.fetch_scope_for_api_token(new_secret)
      assert id == new.id
      assert :error = Accounts.fetch_scope_for_api_token(old_secret)
    end

    test "rolls an active token: the old secret stops working and the new one works" do
      user = user_fixture()
      {:ok, {old_secret, old}} = Accounts.create_api_token(user, "agent")

      assert {:ok, {new_secret, new}} = Accounts.replace_api_token(user, old.id)

      assert new.name == "agent"
      assert :error = Accounts.fetch_scope_for_api_token(old_secret)
      assert {:ok, %{api_token: %{id: id}}} = Accounts.fetch_scope_for_api_token(new_secret)
      assert id == new.id
      assert %ApiToken{revoked_at: %DateTime{}} = Repo.get!(ApiToken, old.id)
    end

    test "leaves a revoked or expired original as it is" do
      user = user_fixture()
      {:ok, {_, revoked}} = Accounts.create_api_token(user, "revoked")
      {:ok, revoked} = Accounts.revoke_api_token(user, revoked.id)
      {:ok, {_, expired}} = Accounts.create_api_token(user, "expired")
      set_token(expired, expires_at: DateTime.add(DateTime.utc_now(:second), -60))

      {:ok, _} = Accounts.replace_api_token(user, revoked.id)
      {:ok, _} = Accounts.replace_api_token(user, expired.id)

      assert Repo.get!(ApiToken, revoked.id).revoked_at == revoked.revoked_at
      assert Repo.get!(ApiToken, expired.id).revoked_at == nil
    end

    test "does not replace another user's token" do
      {:ok, {_, token}} = Accounts.create_api_token(user_fixture(), "agent")
      assert {:error, :not_found} = Accounts.replace_api_token(user_fixture(), token.id)
    end
  end
end
