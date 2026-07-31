defmodule PinventoryWeb.UserLive.LoginTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  describe "login page" do
    test "renders login page when users exist", %{conn: conn} do
      _user = user_fixture()
      {:ok, _lv, html} = live(conn, ~p"/user/log-in")

      assert html =~ "Log in"
      assert html =~ "Password"
      refute html =~ "Sign up"
      refute html =~ "Log in with email"
      refute html =~ "local mail adapter"
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

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/user/log-in")

      assert has_element?(lv, "#login_form_password")
      refute html =~ "Register"
      refute html =~ "Log in with email"

      assert html =~ ~s(value="#{user.email}")
    end
  end
end
