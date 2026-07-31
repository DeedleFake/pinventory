defmodule PinventoryWeb.UserLive.Login do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
          </.header>
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/user/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
            required
          />
          <input type="hidden" name={@form[:remember_me].name} value="true" />
          <.button class="btn btn-primary w-full">
            Log in
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
        {:ok,
         socket
         |> put_flash(:info, "Create the first account to get started.")
         |> redirect(to: ~p"/user/register")}

      true ->
        email =
          Phoenix.Flash.get(socket.assigns.flash, :email) ||
            get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

        form = to_form(%{"email" => email}, as: "user")

        {:ok, assign(socket, form: form, trigger_submit: false)}
    end
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
