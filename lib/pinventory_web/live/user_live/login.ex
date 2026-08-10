defmodule PinventoryWeb.UserLive.Login do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts

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

        {:ok, assign(socket, form: form, trigger_submit: false, reauth?: reauth?)}
    end
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
