defmodule PinventoryWeb.UserLive.RegistrationTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts

  describe "Registration page (bootstrap, zero users)" do
    test "renders registration page when no users exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/user/register")

      assert html =~ "Create the first account"
      assert html =~ "Password"
      refute html =~ "Sign up"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/user/register")

      assert path == ~p"/"
    end

    test "redirects to log in when users already exist", %{conn: conn} do
      _user = user_fixture()

      assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/user/register")
      assert path == ~p"/user/log-in"
      assert flash["error"] =~ "Registration is closed"
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/user/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          user: %{"email" => "with spaces", "password" => "short", "password_confirmation" => "x"}
        )

      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 12 character"
    end
  end

  describe "bootstrap register user" do
    test "creates confirmed account and logs in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/user/register")

      email = unique_user_email()
      password = valid_user_password()

      form =
        form(lv, "#registration_form",
          user: %{
            email: email,
            password: password,
            password_confirmation: password
          }
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_email_and_password(email, password)
      user = Accounts.get_user_by_email(email)
      assert user.confirmed_at
    end

    test "fails when a user already exists (closed registration)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/user/register")

      # Race: another process creates the first user
      _existing = user_fixture()

      form =
        form(lv, "#registration_form",
          user: %{
            email: unique_user_email(),
            password: valid_user_password(),
            password_confirmation: valid_user_password()
          }
        )

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/user/log-in")

      assert html =~ "Log in"
    end
  end
end
