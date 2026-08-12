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
        <h1 class="text-xl font-semibold tracking-tight">Edit location</h1>

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
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:name_dirty?, false)
     |> assign(:dirty?, false)
     |> assign(:total_quantity, 0)
     |> stream_configure(:items, dom_id: &"location-item-#{&1.id}")}
  end

  @impl true
  def handle_params(%{"location_id" => location_id}, _uri, socket) do
    location = Locations.get!(location_id)
    items = Items.list_items_at_location(location.id)

    {:noreply,
     socket
     |> assign(:page_title, location.name)
     |> assign(:location, location)
     |> assign(:baseline_name, location.name)
     |> assign(:form, to_location_form(Locations.change_location(location)))
     |> assign(:total_quantity, total_quantity(items))
     |> stream(:items, items, reset: true)
     |> sync_dirty()}
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

  defp to_location_form(changeset, opts \\ []) do
    to_form(changeset, Keyword.merge([as: :location, id: "location"], opts))
  end

  defp sync_dirty(socket) do
    name = current_name(socket)
    name_dirty? = name != socket.assigns.baseline_name

    socket
    |> assign(:name_dirty?, name_dirty?)
    |> assign_dirty(name_dirty?)
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
