defmodule PinventoryWeb.UserLive.InvitesTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts

  setup :register_and_log_in_user

  test "redirects if user is not logged in", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/user/invites")
    assert path == ~p"/user/log-in"
  end

  test "lists empty state and generates an invite once", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/user/invites")

    assert html =~ "Invites"
    assert has_element?(view, "#invites-empty", "No pending invites")
    assert has_element?(view, "#generate-invite")

    view |> element("#generate-invite") |> render_click()

    html = render(view)
    assert html =~ "Invite created"
    assert has_element?(view, "#latest-invite")
    assert has_element?(view, "#latest-invite-url")
    assert has_element?(view, "#copy-latest-invite")

    [invite] = Accounts.list_pending_invites()
    assert has_element?(view, "#invites-#{invite.id}")
    assert has_element?(view, "#revoke-invite-#{invite.id}")
    # Plain token is not re-exposed on list rows
    refute has_element?(view, "#copy-invite-#{invite.id}")
    refute has_element?(view, "#invite-url-#{invite.id}")
  end

  test "revokes an invite and clears latest panel when matching", %{conn: conn, user: user} do
    {invite, _token} = invite_fixture(user)

    {:ok, view, _html} = live(conn, ~p"/user/invites")
    assert has_element?(view, "#invites-#{invite.id}")

    view |> element("#revoke-invite-#{invite.id}") |> render_click()

    refute has_element?(view, "#invites-#{invite.id}")
    assert Accounts.list_pending_invites() == []
  end

  test "clears latest invite panel when that invite is revoked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/user/invites")

    view |> element("#generate-invite") |> render_click()
    assert has_element?(view, "#latest-invite")

    [invite] = Accounts.list_pending_invites()
    view |> element("#revoke-invite-#{invite.id}") |> render_click()

    refute has_element?(view, "#latest-invite")
  end
end
