defmodule Mix.Tasks.Pinventory.InviteTest do
  use Pinventory.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pinventory.Invite, as: InviteTask
  alias Pinventory.Accounts

  test "requires an email argument" do
    assert_raise Mix.Error, ~r/usage: mix pinventory.invite/, fn ->
      InviteTask.run([])
    end
  end

  test "rejects invalid email with a short message" do
    assert_raise Mix.Error, ~r/failed to create invite: email/, fn ->
      InviteTask.run(["not-an-email"])
    end

    assert Accounts.list_pending_invites() == []
  end

  test "mints an invite and prints the registration URL" do
    email = "ops-invite@example.com"

    output =
      capture_io(fn ->
        InviteTask.run([email])
      end)

    assert output =~ "Email: #{email}"
    assert output =~ "Registration URL:"
    assert output =~ "/user/invite/"

    [invite] = Accounts.list_pending_invites()
    assert invite.email == email
  end
end
