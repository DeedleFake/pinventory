defmodule PinventoryWeb.UserSessionControllerTest do
  use PinventoryWeb.ConnCase, async: false

  alias Pinventory.Accounts
  import Pinventory.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "POST /user/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/user/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/user/settings"
      assert response =~ ~p"/user/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/user/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_pinventory_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in without remember me cookie when unchecked", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/user/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "false"
          }
        })

      assert get_session(conn, :user_token)
      refute conn.resp_cookies["_pinventory_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/user/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == nil
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/user/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/user/log-in"
    end
  end

  describe "POST /user/update-password" do
    test "updates password and re-logs in when in sudo mode", %{conn: conn, user: user} do
      new_password = "a brand new password"

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/user/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert redirected_to(conn) == ~p"/user/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "redirects to log in when not in sudo mode", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -21, :minute)
        )
        |> post(~p"/user/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => "a brand new password",
            "password_confirmation" => "a brand new password"
          }
        })

      assert redirected_to(conn) == ~p"/user/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must re-authenticate to access this page."

      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "redirects with error on invalid password data", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/user/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => "short",
            "password_confirmation" => "short"
          }
        })

      assert redirected_to(conn) == ~p"/user/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Unable to update password."
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "re-logs in as the session user when form email is rewritten", %{conn: conn, user: user} do
      other = user_fixture()
      new_password = "a brand new password"

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/user/update-password", %{
          "user" => %{
            "email" => other.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert redirected_to(conn) == ~p"/user/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
      assert get_session(conn, :user_token)

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
      refute Accounts.get_user_by_email_and_password(other.email, new_password)
      assert Accounts.get_user_by_email_and_password(other.email, valid_user_password())

      # Session belongs to the original user, not the form email victim.
      {session_user, _} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert session_user.id == user.id
    end
  end

  describe "DELETE /user/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/user/log-out")
      assert redirected_to(conn) == ~p"/user/log-in"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/user/log-out")
      assert redirected_to(conn) == ~p"/user/log-in"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
