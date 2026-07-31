defmodule PinventoryWeb.UserLive.Settings do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="settings-page" class="space-y-6">
        <div class="text-center">
          <.header>
            Settings
            <:subtitle>Manage your account and who can use this app</:subtitle>
          </.header>
        </div>

        <nav
          id="settings-tabs"
          class="flex gap-1 rounded-xl border border-base-300 bg-base-200/50 p-1"
          aria-label="Settings sections"
        >
          <.link
            id="settings-tab-account"
            patch={~p"/user/settings"}
            class={[
              "flex-1 rounded-lg px-3 py-2 text-center text-sm font-medium transition-colors duration-150",
              @live_action == :edit && "bg-base-100 text-base-content shadow-sm",
              @live_action != :edit && "text-base-content/70 hover:text-base-content"
            ]}
          >
            Account
          </.link>
          <.link
            id="settings-tab-users"
            patch={~p"/user/settings/users"}
            class={[
              "flex-1 rounded-lg px-3 py-2 text-center text-sm font-medium transition-colors duration-150",
              @live_action == :users && "bg-base-100 text-base-content shadow-sm",
              @live_action != :users && "text-base-content/70 hover:text-base-content"
            ]}
          >
            Users
          </.link>
        </nav>

        <div :if={@live_action == :edit} id="settings-account" class="space-y-4">
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
          </.form>

          <div class="divider" />

          <.form
            for={@password_form}
            id="password_form"
            action={~p"/user/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              spellcheck="false"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
              spellcheck="false"
            />
            <.button variant="primary" phx-disable-with="Saving...">
              Save Password
            </.button>
          </.form>
        </div>

        <div :if={@live_action == :users} id="settings-users" class="space-y-8">
          <section id="invites-section" class="space-y-4" aria-labelledby="invites-heading">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 id="invites-heading" class="text-lg font-semibold tracking-tight">Invites</h2>
                <p class="mt-1 text-sm opacity-70">
                  One-time registration links. Share them out of band.
                </p>
              </div>
              <button
                id="generate-invite"
                type="button"
                phx-click="generate"
                class="btn btn-primary"
                phx-disable-with="Creating..."
              >
                <.icon name="hero-plus" class="size-4" /> Generate invite
              </button>
            </div>

            <div
              :if={@latest_url}
              id="latest-invite"
              class="rounded-xl border border-primary/30 bg-primary/5 p-4 space-y-3"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="text-sm font-medium">New invite ready</p>
                  <p class="text-xs opacity-70 mt-0.5">
                    Copy this link now. It cannot be shown again after you leave this page.
                  </p>
                </div>
                <button
                  type="button"
                  id="copy-latest-invite"
                  class="btn btn-sm btn-primary"
                  phx-hook=".ClipboardCopy"
                  data-copy={@latest_url}
                >
                  <.icon name="hero-clipboard-document" class="size-4" /> Copy
                </button>
              </div>
              <input
                id="latest-invite-url"
                type="text"
                readonly
                value={@latest_url}
                class="input input-bordered w-full font-mono text-xs"
              />
            </div>

            <div id="invites" phx-update="stream" class="flex flex-col gap-2">
              <div
                id="invites-empty"
                class="hidden only:block rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
              >
                No pending invites.
              </div>

              <div
                :for={{id, invite} <- @streams.invites}
                id={id}
                class={[
                  "rounded-xl border border-base-300 bg-base-100 p-4",
                  "flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
                ]}
              >
                <div class="min-w-0 space-y-1 flex-1">
                  <p class="text-sm font-medium">Pending invite</p>
                  <p class="text-xs opacity-70">
                    Created {Calendar.strftime(invite.inserted_at, "%Y-%m-%d %H:%M UTC")}
                  </p>
                  <p class="text-xs opacity-70">
                    Expires {Calendar.strftime(invite.expires_at, "%Y-%m-%d %H:%M UTC")}
                  </p>
                </div>
                <div class="flex flex-wrap items-center gap-2 shrink-0">
                  <button
                    type="button"
                    id={"revoke-invite-#{invite.id}"}
                    class="btn btn-sm btn-error btn-soft"
                    phx-click="revoke"
                    phx-value-id={invite.id}
                    data-confirm="Revoke this invite? It can no longer be used."
                  >
                    <.icon name="hero-x-mark" class="size-4" /> Revoke
                  </button>
                </div>
              </div>
            </div>
          </section>

          <div class="divider" />

          <section id="users-section" class="space-y-4" aria-labelledby="users-heading">
            <div>
              <h2 id="users-heading" class="text-lg font-semibold tracking-tight">Users</h2>
              <p class="mt-1 text-sm opacity-70">People who can log in to this app.</p>
            </div>

            <div id="users" phx-update="stream" class="flex flex-col gap-2">
              <div
                id="users-empty"
                class="hidden only:block rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
              >
                No users yet.
              </div>

              <div
                :for={{id, user} <- @streams.users}
                id={id}
                class="rounded-xl border border-base-300 bg-base-100 px-4 py-3 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between"
              >
                <div class="min-w-0">
                  <p class="text-sm font-medium truncate">{user.email}</p>
                  <p class="text-xs opacity-70">
                    Joined {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
                  </p>
                </div>
                <span
                  :if={@current_scope.user.id == user.id}
                  class="text-xs font-medium opacity-60 shrink-0"
                >
                  You
                </span>
              </div>
            </div>
          </section>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ClipboardCopy">
        export default {
          mounted() {
            this.el.addEventListener("click", (e) => {
              e.preventDefault()
              const value = this.el.dataset.copy
              if (value && navigator.clipboard) {
                navigator.clipboard.writeText(value)
              }
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/user/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    {:ok,
     socket
     |> assign(:current_email, user.email)
     |> assign(:email_form, to_form(email_changeset))
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:trigger_submit, false)
     |> assign(:latest_url, nil)
     |> assign(:latest_invite_id, nil)
     |> stream(:invites, [])
     |> stream(:users, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, prepare_tab(socket)}
  end

  defp prepare_tab(%{assigns: %{live_action: :users}} = socket) do
    socket
    |> assign(:page_title, "Users")
    |> stream(:invites, Accounts.list_pending_invites(), reset: true)
    |> stream(:users, Accounts.list_users(), reset: true)
  end

  defp prepare_tab(%{assigns: %{live_action: :edit}} = socket) do
    if Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      assign(socket, :page_title, "Settings")
    else
      socket
      |> put_flash(:error, "You must re-authenticate to access this page.")
      |> redirect(to: ~p"/user/log-in")
    end
  end

  defp prepare_tab(socket), do: socket

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/user/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("generate", _params, socket) do
    case Accounts.create_invite(socket.assigns.current_scope) do
      {:ok, invite, plain_token} ->
        invite_url = url(~p"/user/invite/#{plain_token}")

        {:noreply,
         socket
         |> assign(:latest_url, invite_url)
         |> assign(:latest_invite_id, invite.id)
         |> stream_insert(:invites, invite, at: 0)
         |> put_flash(:info, "Invite created. Copy the link now — it will not be shown again.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create invite.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Accounts.revoke_invite(id) do
      {:ok, invite} ->
        socket =
          socket
          |> stream_delete(:invites, invite)
          |> put_flash(:info, "Invite revoked.")

        socket =
          if socket.assigns.latest_invite_id == invite.id do
            socket
            |> assign(:latest_url, nil)
            |> assign(:latest_invite_id, nil)
          else
            socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revoke invite.")}
    end
  end
end
