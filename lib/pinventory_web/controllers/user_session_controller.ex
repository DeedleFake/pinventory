defmodule PinventoryWeb.UserSessionController do
  use PinventoryWeb, :controller

  alias Pinventory.Accounts
  alias PinventoryWeb.UserAuth

  def create(conn, params) do
    create(conn, params, nil)
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    # When already logged in (sudo re-auth), do not trust form email. A client can
    # rewrite the read-only field and switch sessions; lock to the session user.
    user_params =
      case conn.assigns do
        %{current_scope: %{user: %{email: session_email}}} when is_binary(session_email) ->
          Map.put(user_params, "email", session_email)

        _ ->
          user_params
      end

    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> maybe_put_info_flash(info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/user/log-in")
    end
  end

  defp maybe_put_info_flash(conn, nil), do: conn
  defp maybe_put_info_flash(conn, info), do: put_flash(conn, :info, info)

  def update_password(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user

    cond do
      not Accounts.sudo_mode?(user) ->
        # Expected reauth when sudo mode expired. Login page copy explains.
        redirect(conn, to: ~p"/user/log-in")

      true ->
        case Accounts.update_user_password(user, user_params) do
          {:ok, {_user, expired_tokens}} ->
            UserAuth.disconnect_sessions(expired_tokens)

            # Re-login as the session user only. Do not trust form email
            # (hidden field for password managers can be rewritten by the client).
            login_params = %{"user" => Map.put(user_params, "email", user.email)}

            conn
            |> put_session(:user_return_to, ~p"/user/settings")
            |> create(login_params, "Password updated successfully!")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Unable to update password.")
            |> redirect(to: ~p"/user/settings")
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
