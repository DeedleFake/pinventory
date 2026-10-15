defmodule PinventoryWeb.UserLive.Login do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts
  alias PinventoryWeb.Passkey.Wire

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <h1 class="text-xl font-semibold tracking-tight">
          {if @reauth?, do: "Confirm your password", else: "Log in"}
        </h1>

        <p :if={@reauth?} class="text-sm text-base-content/70">
          Enter your password again to open Settings and other sensitive actions.
        </p>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/user/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            disabled={@reauth?}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={!@reauth? && JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
            required
            phx-mounted={@reauth? && JS.focus()}
          />
          <.input
            :if={!@reauth?}
            field={@form[:remember_me]}
            type="checkbox"
            label="Keep me logged in for 14 days"
          />
          <.button class="btn btn-primary w-full">
            {if @reauth?, do: "Confirm", else: "Log in"}
          </.button>
        </.form>

        <div
          :if={@passkey_supported?}
          id="passkey-login"
          phx-hook="Passkey"
          class="space-y-2"
        >
          <div class="divider text-xs opacity-60">or</div>
          <.button
            id="passkey-login-button"
            type="button"
            class="btn w-full"
            phx-click="passkey_start"
            disabled={@passkey_ceremony != nil}
          >
            <.icon name="hero-finger-print" class="size-4" />
            {if @reauth?, do: "Confirm with a passkey", else: "Log in with a passkey"}
          </.button>
          <.form
            for={%{}}
            as={:passkey}
            id="passkey_login_form"
            action={~p"/user/log-in/passkey"}
            phx-trigger-action={@passkey_login_token != nil}
          >
            <input type="hidden" name="token" value={@passkey_login_token} />
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    cond do
      not Accounts.any_users?() ->
        # Bootstrap register page heading explains the first-account flow.
        {:ok, redirect(socket, to: ~p"/user/register")}

      true ->
        reauth? = match?(%{user: %{id: _}}, socket.assigns.current_scope)

        # Prefer the session user email when re-authenticating so a failed login
        # flash cannot show a different address in the disabled field.
        email =
          if reauth? do
            socket.assigns.current_scope.user.email
          else
            Phoenix.Flash.get(socket.assigns.flash, :email) ||
              get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
          end

        form_params =
          if reauth? do
            %{"email" => email}
          else
            %{"email" => email, "remember_me" => "true"}
          end

        form = to_form(form_params, as: "user")

        {:ok,
         assign(socket,
           form: form,
           trigger_submit: false,
           reauth?: reauth?,
           passkey_supported?: true,
           passkey_ceremony: nil,
           passkey_login_token: nil
         )}
    end
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  # Passkey ceremony. The challenge lives in this LiveView process: a
  # reconnect drops it and the user just presses the button again.
  def handle_event("passkey_start", _params, socket) do
    begin_opts =
      if socket.assigns.reauth?, do: [user: socket.assigns.current_scope.user], else: []

    {options, ceremony} = Accounts.begin_passkey_authentication(begin_opts)

    {:noreply,
     socket
     |> assign(:passkey_ceremony, ceremony)
     |> push_event("passkey:authenticate", %{options: options})}
  end

  def handle_event("passkey_assertion", %{"credential" => raw}, socket) do
    # Consume the ceremony on every attempt, success or not.
    ceremony = socket.assigns.passkey_ceremony
    socket = assign(socket, :passkey_ceremony, nil)

    with %Accounts.Passkey.Ceremony{} <- ceremony,
         {:ok, assertion} <- Wire.assertion(raw),
         {:ok, user} <- Accounts.finish_passkey_authentication(ceremony, assertion) do
      {:noreply, assign(socket, :passkey_login_token, Accounts.mint_passkey_login_token(user))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Passkey sign-in failed")}
    end
  end

  def handle_event("passkey_assertion", _params, socket) do
    {:noreply,
     socket |> assign(:passkey_ceremony, nil) |> put_flash(:error, "Passkey sign-in failed")}
  end

  def handle_event("passkey_cancel", _params, socket) do
    {:noreply, assign(socket, :passkey_ceremony, nil)}
  end

  def handle_event("passkey_unsupported", _params, socket) do
    {:noreply, assign(socket, passkey_supported?: false, passkey_ceremony: nil)}
  end
end
