defmodule PinventoryWeb.LocationLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items
  alias Pinventory.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="location-page"
        class="space-y-4"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h1 class="text-xl font-semibold tracking-tight">Edit location</h1>
          <.link
            navigate={~p"/locations"}
            id="back-to-locations"
            class="btn btn-ghost btn-soft"
          >
            <.icon name="hero-map-pin" class="size-4" /> Locations
          </.link>
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
              "relative space-y-1 rounded-xl border px-3 py-2 transition-colors duration-200",
              @name_dirty? && "border-primary ring-1 ring-primary/30 bg-primary/5",
              not @name_dirty? && "border-base-300 bg-base-100"
            ]}
          >
            <.input
              type="text"
              field={@form[:name]}
              label="Name"
              placeholder="Location name..."
              autocomplete="off"
              phx-debounce="300"
              wrapperclass="mb-0"
            />

            <p
              :if={@name_dirty?}
              id="location-name-hint"
              class="text-xs text-primary"
            >
              Unsaved name change · was {@baseline_name}
            </p>
          </div>

          <div class="flex justify-end gap-2 pt-2">
            <.button
              type="submit"
              id="location-save"
              variant="primary"
              disabled={not @dirty?}
            >
              Save
            </.button>
          </div>
        </.form>

        <div
          id="location-total"
          class={[
            "flex min-h-20 items-center justify-between gap-4 rounded-2xl border px-4 py-3",
            "border-base-300 bg-base-100"
          ]}
        >
          <p class="text-xs font-semibold tracking-wide uppercase opacity-60">
            Total quantity
          </p>
          <span
            id="location-total-value"
            class="text-3xl font-semibold tracking-tight tabular-nums sm:text-4xl"
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
              <div class="min-w-0 flex-1">
                <div class="truncate font-medium">{item.name}</div>
                <div
                  id={"#{id}-quantity"}
                  class="truncate text-sm tabular-nums opacity-60"
                >
                  {quantity_label(item.quantity)}
                </div>
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

  defp quantity_label(1), do: "1 here"
  defp quantity_label(quantity), do: "#{quantity} here"
end
