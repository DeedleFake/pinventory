defmodule PinventoryWeb.LocationLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items
  alias Pinventory.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:locations}>
      <div
        id="location-page"
        class="space-y-4"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h1 class="text-xl font-semibold tracking-tight">Edit location</h1>
          <div id="location-delete-actions" class="flex flex-wrap items-center justify-end gap-2">
            <p
              :if={@delete_blocked_reason}
              id="location-delete-reason"
              class="text-sm opacity-70"
            >
              {@delete_blocked_reason}
            </p>
            <button
              type="button"
              id="location-delete"
              class="btn btn-ghost text-error hover:bg-error/10"
              phx-click="open_delete"
              disabled={@delete_blocked_reason != nil}
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </button>
          </div>
        </div>

        <.form
          for={@form}
          id="location-form"
          class="space-y-1"
          phx-change="validate"
          phx-submit="save"
        >
          <div
            id="location-name-section"
            data-name-dirty={to_string(@name_dirty?)}
            class={[
              "relative space-y-1.5 rounded-xl border px-3 py-2 transition-colors duration-200",
              @name_dirty? && "border-primary ring-1 ring-primary/30 bg-primary/5",
              not @name_dirty? && "border-base-300 bg-base-100"
            ]}
          >
            <label class="label mb-1" for={@form[:name].id}>Name</label>
            <div class="join w-full">
              <input
                type="text"
                id={@form[:name].id}
                name={@form[:name].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:name].value)}
                placeholder="Location name..."
                autocomplete="off"
                phx-debounce="300"
                class={[
                  "input join-item min-w-0 grow",
                  @form[:name].errors != [] &&
                    Phoenix.Component.used_input?(@form[:name]) && "input-error"
                ]}
              />
              <button
                type="submit"
                id="location-save"
                class="btn btn-primary join-item shrink-0"
                disabled={not @dirty?}
              >
                Save
              </button>
            </div>
            <p
              :for={msg <- field_errors(@form[:name])}
              class="flex items-center gap-2 text-sm text-error"
            >
              <.icon name="hero-exclamation-circle" class="size-5" />
              {msg}
            </p>
            <p
              :if={@name_dirty?}
              id="location-name-hint"
              class="text-xs text-primary"
            >
              Unsaved name change · was {@baseline_name}
            </p>
          </div>
        </.form>

        <div
          id="location-total"
          class={[
            "flex items-center justify-between gap-4 rounded-xl border px-4 py-2.5",
            "border-base-300 bg-base-100"
          ]}
        >
          <p class="text-xs font-semibold tracking-wide uppercase opacity-50">
            Total quantity
          </p>
          <span
            id="location-total-value"
            class="text-2xl font-semibold tracking-tight tabular-nums opacity-80"
          >
            {@total_quantity}
          </span>
        </div>

        <div class="space-y-2">
          <h2 class="text-sm font-medium opacity-80">Items</h2>

          <div id="location-items" class="flex flex-col gap-1" phx-update="stream">
            <div
              id="location-items-empty"
              class="hidden only:block rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
            >
              No items at this location.
            </div>

            <.link
              :for={{id, item} <- @streams.items}
              navigate={~p"/item/#{item.id}"}
              id={id}
              class={[
                "flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-3",
                "transition-all hover:border-base-content/20 hover:bg-base-200/40"
              ]}
            >
              <div class="min-w-0 flex-1 truncate font-medium">{item.name}</div>
              <div
                id={"#{id}-quantity"}
                class="shrink-0 min-w-8 text-right text-xl font-semibold tabular-nums"
              >
                {item.quantity}
              </div>
              <.icon name="hero-chevron-right" class="size-4 shrink-0 opacity-40" />
            </.link>
          </div>
        </div>

        <.location_delete_modal
          :if={@delete_modal?}
          form={@delete_form}
          location_name={@location.name}
          confirm_ready?={@delete_confirm_ready?}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :location_name, :string, required: true
  attr :confirm_ready?, :boolean, required: true

  defp location_delete_modal(assigns) do
    ~H"""
    <div
      id="location-delete-modal"
      class="fixed inset-0 z-50 flex items-end justify-center bg-neutral/40 p-4 sm:items-center"
      phx-window-keydown="close_delete"
      phx-key="Escape"
    >
      <div
        id="location-delete-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="location-delete-title"
        class="w-full max-w-md rounded-2xl border border-base-300 bg-base-100 p-5 shadow-2xl sm:p-6"
        phx-click-away="close_delete"
      >
        <div class="space-y-1">
          <h2 id="location-delete-title" class="text-lg font-semibold tracking-tight">
            Delete location
          </h2>
          <p id="location-delete-impact" class="text-sm opacity-70">
            This will delete {@location_name}.
          </p>
        </div>

        <.form
          for={@form}
          id="location-delete-form"
          class="mt-4 space-y-4"
          phx-change="validate_delete"
          phx-submit="confirm_delete"
        >
          <.input
            type="text"
            field={@form[:name]}
            id="location-delete-confirm"
            label="Type the location name to confirm"
            placeholder={@location_name}
            autocomplete="off"
            spellcheck="false"
            phx-mounted={JS.focus()}
          />

          <div class="flex justify-end gap-2">
            <button
              type="button"
              id="location-delete-cancel"
              class="btn btn-ghost"
              phx-click="close_delete"
            >
              Cancel
            </button>
            <button
              type="submit"
              id="location-delete-confirm-submit"
              class="btn btn-error"
              disabled={not @confirm_ready?}
            >
              Delete
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:name_dirty?, false)
     |> assign(:dirty?, false)
     |> assign(:total_quantity, 0)
     |> assign(:has_items?, false)
     |> assign(:delete_modal?, false)
     |> assign(:delete_form, delete_form(""))
     |> assign(:delete_confirm_ready?, false)
     |> assign(:delete_blocked_reason, nil)
     |> stream_configure(:items, dom_id: &"location-item-#{&1.id}")}
  end

  @impl true
  def handle_params(%{"location_id" => location_id}, _uri, socket) do
    case Locations.get(location_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Location not found.")
         |> push_navigate(to: ~p"/locations")}

      location ->
        items = Items.list_items_at_location(location.id)

        {:noreply,
         socket
         |> assign(:page_title, location.name)
         |> assign(:location, location)
         |> assign(:baseline_name, location.name)
         |> assign(:form, to_location_form(Locations.change_location(location)))
         |> assign(:total_quantity, total_quantity(items))
         |> assign(:has_items?, items != [])
         |> stream(:items, items, reset: true)
         |> close_delete_modal()
         |> sync_dirty()}
    end
  end

  @impl true
  def handle_event("validate", %{"location" => params}, socket) do
    form =
      socket.assigns.location
      |> Locations.change_location(params)
      |> Map.put(:action, :validate)
      |> to_location_form()

    {:noreply,
     socket
     |> assign(:form, form)
     |> sync_dirty()}
  end

  def handle_event("save", %{"location" => params}, socket) do
    changeset = Locations.change_location(socket.assigns.location, params)

    case Locations.update(socket.assigns.current_scope, changeset) do
      {:ok, location} ->
        {:noreply,
         socket
         |> assign(:location, location)
         |> assign(:baseline_name, location.name)
         |> assign(:page_title, location.name)
         |> assign(:form, to_location_form(Locations.change_location(location)))
         |> put_flash(:info, "Location saved")
         |> sync_dirty()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_location_form(changeset, action: :validate))
         |> sync_dirty()}
    end
  end

  def handle_event("open_delete", _params, socket) do
    {:noreply, open_delete_modal(socket)}
  end

  def handle_event("close_delete", _params, socket) do
    {:noreply, close_delete_modal(socket)}
  end

  def handle_event("validate_delete", params, socket) do
    {:noreply, assign_delete_form(socket, delete_name_from_params(params))}
  end

  def handle_event("confirm_delete", params, socket) do
    raw_name = delete_name_from_params(params)

    cond do
      unsaved_name?(socket) ->
        {:noreply,
         socket
         |> close_delete_modal()
         |> put_flash(:error, "Save or revert the name first.")}

      not confirm_name_matches?(raw_name, saved_name(socket)) ->
        {:noreply, assign_delete_form(socket, raw_name)}

      true ->
        case Locations.delete(socket.assigns.current_scope, socket.assigns.location) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign_dirty(false)
             |> put_flash(:info, "Location deleted")
             |> push_navigate(to: ~p"/locations")}

          {:error, :location_has_items} ->
            {:noreply,
             socket
             |> refresh_location_items()
             |> close_delete_modal()
             |> put_flash(:error, "Remove items from this location first.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete the location")}
        end
    end
  end

  defp to_location_form(changeset, opts \\ []) do
    to_form(changeset, Keyword.merge([as: :location, id: "location"], opts))
  end

  defp sync_dirty(socket) do
    name = current_name(socket)
    name_dirty? = name != socket.assigns.baseline_name

    socket
    |> assign(:name_dirty?, name_dirty?)
    |> assign(:delete_blocked_reason, location_delete_blocked_reason(socket, name_dirty?))
    |> assign_dirty(name_dirty?)
  end

  defp location_delete_blocked_reason(_socket, true), do: "Save or revert the name first."

  defp location_delete_blocked_reason(socket, false) do
    if socket.assigns.has_items? do
      "Remove items from this location first."
    else
      nil
    end
  end

  defp open_delete_modal(socket) do
    if delete_blocked?(socket) do
      socket
    else
      socket
      |> assign(:delete_modal?, true)
      |> assign_delete_form("")
    end
  end

  defp close_delete_modal(socket) do
    socket
    |> assign(:delete_modal?, false)
    |> assign_delete_form("")
  end

  defp assign_delete_form(socket, raw_name) when is_binary(raw_name) do
    socket
    |> assign(:delete_form, delete_form(raw_name))
    |> assign(:delete_confirm_ready?, confirm_name_matches?(raw_name, saved_name(socket)))
  end

  defp delete_form(name) do
    to_form(%{"name" => name}, as: :delete)
  end

  defp delete_name_from_params(%{"delete" => %{"name" => name}}) when is_binary(name), do: name
  defp delete_name_from_params(_), do: ""

  defp confirm_name_matches?(typed, saved) when is_binary(typed) and is_binary(saved) do
    typed == saved or String.trim(typed) == String.trim(saved)
  end

  defp unsaved_name?(socket) do
    current_name(socket) != saved_name(socket)
  end

  defp saved_name(%{assigns: %{location: %{name: name}}}) when is_binary(name), do: name
  defp saved_name(_), do: ""

  defp delete_blocked?(socket) do
    unsaved_name?(socket) or socket.assigns.has_items?
  end

  defp refresh_location_items(socket) do
    items = Items.list_items_at_location(socket.assigns.location.id)

    socket
    |> assign(:has_items?, items != [])
    |> assign(:total_quantity, total_quantity(items))
    |> stream(:items, items, reset: true)
    |> sync_dirty()
  end

  defp assign_dirty(socket, dirty?) do
    if socket.assigns.dirty? == dirty? do
      socket
    else
      socket
      |> assign(:dirty?, dirty?)
      |> push_event("unsaved-changes", %{dirty: dirty?})
    end
  end

  defp current_name(socket) do
    case socket.assigns.form do
      %Phoenix.HTML.Form{source: %Ecto.Changeset{} = changeset} ->
        Ecto.Changeset.get_field(changeset, :name) || ""

      _ ->
        ""
    end
  end

  defp total_quantity(items) do
    Enum.reduce(items, 0, fn item, acc -> acc + (item.quantity || 0) end)
  end

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field) do
      Enum.map(field.errors, &translate_error/1)
    else
      []
    end
  end
end
