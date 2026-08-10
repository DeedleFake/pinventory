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
end
