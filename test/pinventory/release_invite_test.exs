defmodule Pinventory.ReleaseInviteTest do
  use Pinventory.DataCase, async: false

  import ExUnit.CaptureIO

  alias Pinventory.Accounts
  alias Pinventory.Release

  test "create_invite/1 requires a valid email and mints a pending invite" do
    email = "release-invite@example.com"

    output =
      capture_io(fn ->
        assert {:ok, invite, url} = Release.create_invite(email)
        assert invite.email == email
        assert url =~ "/user/invite/"
      end)

    assert output =~ "Email: #{email}"
    assert output =~ "Registration URL:"

    [pending] = Accounts.list_pending_invites()
    assert pending.email == email
  end

  test "create_invite/1 raises on invalid email" do
    assert_raise RuntimeError, ~r/failed to create invite/, fn ->
      Release.create_invite("not-an-email")
    end

    assert Accounts.list_pending_invites() == []
  end
end
