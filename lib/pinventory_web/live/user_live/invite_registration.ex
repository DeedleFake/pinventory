defmodule PinventoryWeb.UserLive.InviteRegistration do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts
  alias Pinventory.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <h1 class="text-xl font-semibold tracking-tight">Accept invite</h1>

        <.form
          for={@form}
          id="invite_registration_form"
          action={~p"/user/log-in"}
          method="post"
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
        >
          <.input
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
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            spellcheck="false"
            required
          />

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create account and log in
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => _token}, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: PinventoryWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_pending_invite_by_token(token) do
      {:ok, _invite} ->
        changeset = Accounts.change_user_registration(%User{}, %{}, hash_password: false)

        {:ok,
         assign(socket,
           token: token,
           form: to_form(changeset, as: "user"),
           trigger_submit: false
         ), temporary_assigns: [form: nil]}

      {:error, :invalid_or_expired} ->
        {:ok,
         socket
         |> put_flash(:error, "This invite is invalid or has expired.")
         |> redirect(to: ~p"/user/log-in")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user_with_invite(socket.assigns.token, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome! Your account is ready.")
         |> assign(trigger_submit: true, form: to_form(user_params, as: "user"))}

      {:error, :invalid_or_expired} ->
        {:noreply,
         socket
         |> put_flash(:error, "This invite is invalid or has expired.")
         |> push_navigate(to: ~p"/user/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end
end
