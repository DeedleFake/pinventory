defmodule PinventoryWeb.UserLive.Settings do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts
  alias Pinventory.Audit

  import PinventoryWeb.AuditHelpers,
    only: [activity_link_target: 1, edit_heading: 1, event_line: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="settings-page" class="space-y-6">
        <h1 class="text-xl font-semibold tracking-tight">Settings</h1>

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
          <.link
            id="settings-tab-activity"
            patch={~p"/user/settings/activity"}
            class={[
              "flex-1 rounded-lg px-3 py-2 text-center text-sm font-medium transition-colors duration-150",
              @live_action == :activity && "bg-base-100 text-base-content shadow-sm",
              @live_action != :activity && "text-base-content/70 hover:text-base-content"
            ]}
          >
            Activity
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
            <div>
              <h2 id="invites-heading" class="text-lg font-semibold tracking-tight">Invites</h2>
              <p class="mt-1 text-sm opacity-70">
                One-time registration links bound to an email. Share them out of band.
              </p>
            </div>

            <.form
              for={@invite_form}
              id="generate-invite-form"
              phx-submit="generate"
              phx-change="validate_invite"
              class="space-y-1.5"
            >
              <label class="label" for={@invite_form[:email].id}>Invite email</label>
              <%!-- join keeps input and button the same height (daisyUI). --%>
              <div class="join w-full">
                <input
                  type="email"
                  id={@invite_form[:email].id}
                  name={@invite_form[:email].name}
                  value={Phoenix.HTML.Form.normalize_value("email", @invite_form[:email].value)}
                  placeholder="user@example.com"
                  autocomplete="off"
                  spellcheck="false"
                  required
                  class={[
                    "input join-item min-w-0 grow",
                    @invite_form[:email].errors != [] &&
                      Phoenix.Component.used_input?(@invite_form[:email]) && "input-error"
                  ]}
                />
                <button
                  id="generate-invite"
                  type="submit"
                  class="btn btn-primary join-item shrink-0"
                  phx-disable-with="Creating..."
                >
                  <.icon name="hero-plus" class="size-4" /> Generate invite
                </button>
              </div>
              <p
                :for={msg <- invite_email_errors(@invite_form)}
                class="mt-1 flex items-center gap-2 text-sm text-error"
              >
                <.icon name="hero-exclamation-circle" class="size-5" />
                {msg}
              </p>
            </.form>

            <div
              :if={@latest_url}
              id="latest-invite"
              class="rounded-xl border border-primary/30 bg-primary/5 p-4 space-y-3"
            >
              <div>
                <p class="text-sm font-medium">New invite ready</p>
                <p :if={@latest_email} class="text-xs opacity-70 mt-0.5">
                  For {@latest_email}
                </p>
                <p class="text-xs opacity-70 mt-0.5">
                  Copy this link now. It cannot be shown again after you leave this page.
                </p>
              </div>
              <div class="join w-full">
                <input
                  id="latest-invite-url"
                  type="text"
                  readonly
                  value={@latest_url}
                  class="input join-item min-w-0 grow font-mono text-xs"
                />
                <button
                  type="button"
                  id="copy-latest-invite"
                  class="btn btn-primary join-item shrink-0"
                  phx-hook=".ClipboardCopy"
                  data-copy={@latest_url}
                >
                  <.icon name="hero-clipboard-document" class="size-4" /> Copy
                </button>
              </div>
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
                  <p class="text-sm font-medium truncate">{invite.email}</p>
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

        <div :if={@live_action == :activity} id="settings-activity" class="space-y-4">
          <div>
            <h2 id="activity-heading" class="text-lg font-semibold tracking-tight">Activity</h2>
            <p class="mt-1 text-sm opacity-70">
              Recent changes across items, locations, and stock.
            </p>
          </div>

          <div
            :if={@activity_edits == []}
            id="activity-empty"
            class="rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
          >
            No activity yet.
          </div>

          <div id="activity-edits" class="flex flex-col gap-1">
            <%= for edit <- @activity_edits do %>
              <% target = activity_link_target(edit) %>
              <.link
                :if={target}
                id={"activity-edit-#{edit.edit_id}"}
                navigate={activity_navigate_path(target)}
                class={[
                  "flex items-start gap-3 rounded-xl border border-base-300 bg-base-100 p-4",
                  "transition-all hover:border-base-content/20 hover:bg-base-200/40"
                ]}
              >
                <.activity_edit_body edit={edit} />
                <.icon name="hero-chevron-right" class="mt-0.5 size-4 shrink-0 opacity-40" />
              </.link>

              <article
                :if={!target}
                id={"activity-edit-#{edit.edit_id}"}
                class="rounded-xl border border-base-300 bg-base-100 p-4 space-y-2"
              >
                <.activity_edit_body edit={edit} />
              </article>
            <% end %>
          </div>
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
     |> assign(:invite_form, to_form(Accounts.change_invite(%{}), as: :invite))
     |> assign(:trigger_submit, false)
     |> assign(:latest_url, nil)
     |> assign(:latest_email, nil)
     |> assign(:latest_invite_id, nil)
     |> assign(:activity_edits, [])
     |> stream(:invites, [])
     |> stream(:users, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, prepare_tab(socket)}
  end

  # Account, Users, and Activity all require a recent password login (sudo mode).
  # confirm-email is handled in mount and does not use this path.
  defp prepare_tab(%{assigns: %{live_action: action}} = socket)
       when action in [:edit, :users, :activity] do
    if Accounts.sudo_mode?(socket.assigns.current_scope.user) do
      load_tab(socket, action)
    else
      require_sudo_redirect(socket)
    end
  end

  defp prepare_tab(socket), do: socket

  defp require_sudo_redirect(socket) do
    socket
    |> put_flash(:error, "You must re-authenticate to access this page.")
    |> redirect(to: ~p"/user/log-in")
  end

  defp invite_email_errors(form) do
    field = form[:email]

    if Phoenix.Component.used_input?(field) do
      Enum.map(field.errors, &translate_error/1)
    else
      []
    end
  end

  defp load_tab(socket, :edit) do
    assign(socket, :page_title, "Settings")
  end

  defp load_tab(socket, :users) do
    socket
    |> assign(:page_title, "Users")
    |> stream(:invites, Accounts.list_pending_invites(), reset: true)
    |> stream(:users, Accounts.list_users(), reset: true)
  end

  defp load_tab(socket, :activity) do
    socket
    |> assign(:page_title, "Activity")
    |> assign(:activity_edits, Audit.list_recent_edits(limit: 50))
  end

  defp activity_navigate_path({:item, item_id}), do: ~p"/item/#{item_id}"

  defp activity_navigate_path({:location, location_id}),
    do: ~p"/locations#location-#{location_id}"

  attr :edit, :map, required: true

  defp activity_edit_body(assigns) do
    ~H"""
    <div class="min-w-0 flex-1 space-y-2">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <p class="text-sm font-medium">{edit_heading(@edit)}</p>
        <time
          class="text-xs tabular-nums opacity-60"
          datetime={DateTime.to_iso8601(@edit.inserted_at)}
        >
          {Calendar.strftime(@edit.inserted_at, "%Y-%m-%d %H:%M UTC")}
        </time>
      </div>
      <ul class="space-y-1 border-t border-base-300/80 pt-2">
        <li
          :for={event <- @edit.events}
          id={"activity-event-#{event.id}"}
          class="text-sm opacity-80"
        >
          {event_line(event)}
        </li>
      </ul>
    </div>
    """
  end

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

    if Accounts.sudo_mode?(user) do
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
    else
      {:noreply, require_sudo_redirect(socket)}
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

    if Accounts.sudo_mode?(user) do
      case Accounts.change_user_password(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    else
      {:noreply, require_sudo_redirect(socket)}
    end
  end

  def handle_event("validate_invite", %{"invite" => invite_params}, socket) do
    invite_form =
      invite_params
      |> Accounts.change_invite()
      |> Map.put(:action, :validate)
      |> to_form(as: :invite)

    {:noreply, assign(socket, invite_form: invite_form)}
  end

  def handle_event("generate", %{"invite" => invite_params}, socket) do
    email = Map.get(invite_params, "email", "")

    case Accounts.create_invite(email, socket.assigns.current_scope) do
      {:ok, invite, plain_token} ->
        invite_url = url(~p"/user/invite/#{plain_token}")

        {:noreply,
         socket
         |> assign(:latest_url, invite_url)
         |> assign(:latest_email, invite.email)
         |> assign(:latest_invite_id, invite.id)
         |> assign(:invite_form, to_form(Accounts.change_invite(%{}), as: :invite))
         |> stream_insert(:invites, invite, at: 0)
         |> put_flash(:info, "Invite created. Copy the link now — it will not be shown again.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, invite_form: to_form(changeset, as: :invite, action: :insert))}
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
            |> assign(:latest_email, nil)
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
