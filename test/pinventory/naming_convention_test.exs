defmodule Pinventory.NamingConventionTest do
  use Pinventory.DataCase, async: false

  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts
  alias Pinventory.Accounts.Scope
  alias Pinventory.NamingConvention

  test "starts at the seeded version 0 with no author" do
    assert %{number: 0, user: nil, text: text} = NamingConvention.current()
    assert text =~ "**Boxes of Tissues**, not **Tissues**"
    assert [%{number: 0}] = NamingConvention.versions()
  end

  test "each save appends a version with its author" do
    scope = user_scope_fixture()

    assert {:ok, v1} = NamingConvention.save(scope, 0, "Use plurals.\r\nInclude units.")
    assert v1.number == 1
    assert v1.text == "Use plurals.\nInclude units."
    assert v1.user.id == scope.user.id
    assert v1.via_token_name == nil

    assert {:ok, %{number: 2}} = NamingConvention.save(scope, 1, "Include units.")
    assert NamingConvention.current().text == "Include units."
    assert Enum.map(NamingConvention.versions(), & &1.number) == [0, 1, 2]
  end

  test "refuses a save on top of an older version and writes nothing" do
    scope = user_scope_fixture()
    {:ok, v1} = NamingConvention.save(scope, 0, "First")

    assert {:error, :stale, newest} = NamingConvention.save(scope, 0, "Second")
    assert newest.id == v1.id
    assert {:error, :stale, _} = NamingConvention.save(scope, 5, "Ahead")
    assert length(NamingConvention.versions()) == 2
  end

  test "saving the same text writes nothing" do
    scope = user_scope_fixture()
    base = NamingConvention.current()

    assert {:ok, same} = NamingConvention.save(scope, 0, base.text)
    assert same.id == base.id
    assert length(NamingConvention.versions()) == 1
  end

  test "an agent's save records the API token's name" do
    user = user_fixture()
    {:ok, {_secret, token}} = Accounts.create_api_token(user, "Claude on phone")

    assert {:ok, version} =
             NamingConvention.save(Scope.for_api_token(user, token), 0, "Agent edit")

    assert version.via_token_name == "Claude on phone"
  end

  test "refuses text over the length limit" do
    scope = user_scope_fixture()

    assert {:error, %Ecto.Changeset{errors: [text: _]}} =
             NamingConvention.save(scope, 0, String.duplicate("a", 20_001))
  end
end
