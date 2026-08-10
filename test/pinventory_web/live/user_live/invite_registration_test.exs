defmodule PinventoryWeb.UserLive.InviteRegistrationTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts

  setup do
    # App is closed after first user; invite is required for further registration.
    user = user_fixture()
    {invite, token} = invite_fixture(user)
    %{user: user, invite: invite, token: token}
  end

  test "renders registration form for a valid invite without revealing bound email", %{
    conn: conn,
    invite: invite,
    token: token
  } do
    {:ok, _lv, html} = live(conn, ~p"/user/invite/#{token}")

    assert html =~ "Accept invite"
    assert html =~ "Password"
    # Bound email must not be pre-filled or shown (URL holders must not learn it)
    refute html =~ invite.email
  end

  test "rejects invalid invite token", %{conn: conn} do
    assert {:error, {:redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/user/invite/not-a-valid-token")

    assert path == ~p"/user/log-in"
    assert flash["error"] =~ "invalid or has expired"
  end

  test "rejects used invite", %{conn: conn, invite: invite, token: token} do
    password = valid_user_password()

    assert {:ok, _} =
             Accounts.register_user_with_invite(token, %{
               email: invite.email,
               password: password,
               password_confirmation: password
             })

    assert {:error, {:redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/user/invite/#{token}")

    assert path == ~p"/user/log-in"
    assert flash["error"] =~ "invalid or has expired"
  end

  test "creates user, consumes invite, and logs in", %{conn: conn, invite: invite, token: token} do
    {:ok, lv, _html} = live(conn, ~p"/user/invite/#{token}")

    password = valid_user_password()

    form =
      form(lv, "#invite_registration_form",
        user: %{
          email: invite.email,
          password: password,
          password_confirmation: password
        }
      )

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/"
    assert Accounts.get_user_by_email_and_password(invite.email, password)

    assert {:error, :invalid_or_expired} = Accounts.get_pending_invite_by_token(token)
  end

  test "wrong email fails with same generic error as invalid invite", %{
    conn: conn,
    invite: invite,
    token: token
  } do
    {:ok, lv, _html} = live(conn, ~p"/user/invite/#{token}")

    password = valid_user_password()

    lv
    |> form("#invite_registration_form",
      user: %{
        email: unique_user_email(),
        password: password,
        password_confirmation: password
      }
    )
    |> render_submit()

    flash = assert_redirect(lv, ~p"/user/log-in")
    assert flash["error"] =~ "invalid or has expired"
    # Must not leak that the token was valid or that the email was wrong
    refute flash["error"] =~ invite.email
    refute flash["error"] =~ ~r/wrong email|does not match|email for this invite/i

    assert {:ok, _} = Accounts.get_pending_invite_by_token(token)
  end

  test "renders validation errors", %{conn: conn, token: token} do
    {:ok, lv, _html} = live(conn, ~p"/user/invite/#{token}")

    result =
      lv
      |> element("#invite_registration_form")
      |> render_change(
        user: %{"email" => "bad", "password" => "x", "password_confirmation" => "y"}
      )

    assert result =~ "must have the @ sign"
  end
end
