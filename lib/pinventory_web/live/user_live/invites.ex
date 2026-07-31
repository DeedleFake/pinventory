defmodule PinventoryWeb.UserLive.Invites do
  use PinventoryWeb, :live_view

  alias Pinventory.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="invites-page" class="space-y-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 class="text-xl font-semibold tracking-tight">Invites</h1>
            <p class="mt-1 text-sm opacity-70">
              Create one-time registration links. Share them out of band. No email is sent.
              The link is shown once when you generate it.
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
              <p class="text-xs opacity-60 mt-1">
                Link was shown once at creation. Revoke if it should not be used.
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
  def mount(_params, _session, socket) do
    invites = Accounts.list_pending_invites()

    {:ok,
     socket
     |> assign(:page_title, "Invites")
     |> assign(:latest_url, nil)
     |> assign(:latest_invite_id, nil)
     |> stream(:invites, invites)}
  end

  @impl true
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
