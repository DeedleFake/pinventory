defmodule PinventoryWeb.UserLive.LoginTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  describe "login page" do
    test "renders login page when users exist", %{conn: conn} do
      _user = user_fixture()
      {:ok, lv, html} = live(conn, ~p"/user/log-in")

      assert html =~ "Log in"
      assert html =~ "Password"
      assert has_element?(lv, ~s|#user_remember_me[type="checkbox"][checked]|)
      assert html =~ "Keep me logged in for 14 days"
      refute html =~ "Sign up"
      refute html =~ "Log in with email"
      refute html =~ "local mail adapter"

      # Email is editable and focused on normal login; password is not focused.
      assert has_element?(lv, ~s|#user_email|)
      refute has_element?(lv, ~s|#user_email[disabled]|)
      assert has_element?(lv, ~s|#user_email[phx-mounted]|)
      refute has_element?(lv, ~s|#user_password[phx-mounted]|)
      assert has_element?(lv, "#login_form_password button", "Log in")
      refute has_element?(lv, "#app-nav")
    end

    test "redirects to bootstrap registration when no users exist", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/user/log-in")
      assert path == ~p"/user/register"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/user/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      _user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/user/log-in"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows confirm password page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/user/log-in")

      assert has_element?(lv, "#login_form_password")
      assert html =~ "Confirm your password"
      assert html =~ "Enter your password again"
      assert has_element?(lv, "#login_form_password button", "Confirm")
      refute has_element?(lv, "#login_form_password button", "Log in")
      refute html =~ "Keep me logged in for 14 days"
      refute has_element?(lv, ~s|#user_remember_me|)
      refute html =~ "Register"
      refute html =~ "Log in with email"

      # Email is disabled (display only); password is focused for reauth.
      assert has_element?(lv, ~s|#user_email[disabled]|)
      assert has_element?(lv, ~s|#user_email[value="#{user.email}"]|)
      assert has_element?(lv, ~s|#user_password[phx-mounted]|)
      refute has_element?(lv, ~s|#user_email[phx-mounted]|)
    end

    test "re-authenticates with password only and redirects to settings", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password()}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/user/settings"
      assert get_session(conn, :user_token)
      refute conn.resp_cookies["_pinventory_web_user_remember_me"]
    end
  end

  describe "user login - passkey" do
    alias Pinventory.SoftAuthenticator

    # The browser pipeline would add this on the first request; set it up
    # front so follow_trigger_action posts from the same session.
    setup %{conn: conn}, do: %{conn: init_test_session(conn, %{passkey_binding: "b"})}

    defp passkey_login(lv, auth, opts \\ []) do
      lv |> element("#passkey-login-button") |> render_click()
      assert_push_event lv, "passkey:authenticate", %{options: options}

      lv
      |> element("#passkey-login")
      |> render_hook("passkey_assertion", %{
        credential: SoftAuthenticator.get(auth, options, opts)
      })
    end

    test "logs in with a discoverable passkey and no email", %{conn: conn} do
      user = user_fixture()
      {auth, _} = passkey_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")

      passkey_login(lv, auth, user_handle: Ecto.UUID.dump!(user.id))

      conn = follow_trigger_action(form(lv, "#passkey_login_form"), conn)
      assert redirected_to(conn) == ~p"/"
      assert conn.resp_cookies["_pinventory_web_user_remember_me"]

      {session_user, _} =
        Pinventory.Accounts.get_user_by_session_token(get_session(conn, :user_token))

      assert session_user.id == user.id
    end

    test "shows one generic error for unknown and invalid passkeys", %{conn: conn} do
      user = user_fixture()
      {auth, _} = passkey_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")

      unknown = passkey_login(lv, SoftAuthenticator.new())
      bad_origin = passkey_login(lv, auth, origin: "https://evil.example")

      for html <- [unknown, bad_origin] do
        assert html =~ "Passkey sign-in failed"
        refute html =~ user.email
      end

      refute has_element?(lv, ~s|#passkey_login_form[phx-trigger-action]|)
    end

    test "an assertion cannot be replayed after the ceremony is consumed", %{conn: conn} do
      user = user_fixture()
      {auth, _} = passkey_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")

      lv |> element("#passkey-login-button") |> render_click()
      assert_push_event lv, "passkey:authenticate", %{options: options}
      credential = SoftAuthenticator.get(auth, options, sign_count: 0)

      lv |> element("#passkey-login") |> render_hook("passkey_cancel", %{})

      html =
        lv
        |> element("#passkey-login")
        |> render_hook("passkey_assertion", %{credential: credential})

      assert html =~ "Passkey sign-in failed"
    end

    test "rejects malformed payloads", %{conn: conn} do
      _user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")
      lv |> element("#passkey-login-button") |> render_click()

      html =
        lv
        |> element("#passkey-login")
        |> render_hook("passkey_assertion", %{credential: %{"rawId" => "!!"}})

      assert html =~ "Passkey sign-in failed"
    end

    test "reauth only accepts the session user's passkey", %{conn: conn} do
      user = user_fixture()
      {auth, _} = passkey_fixture(user)
      {other_auth, _} = passkey_fixture(user_fixture())
      conn = log_in_user(conn, user)
      {:ok, lv, html} = live(conn, ~p"/user/log-in")
      assert html =~ "Confirm with a passkey"

      assert passkey_login(lv, other_auth) =~ "Passkey sign-in failed"

      passkey_login(lv, auth)
      conn = follow_trigger_action(form(lv, "#passkey_login_form"), conn)
      assert redirected_to(conn) == ~p"/user/settings"
    end

    test "hides the button when the browser has no WebAuthn", %{conn: conn} do
      _user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/user/log-in")
      lv |> element("#passkey-login") |> render_hook("passkey_unsupported", %{})
      refute has_element?(lv, "#passkey-login-button")
    end
  end
end
