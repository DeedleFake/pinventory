defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:locations}>
      <div
        id="locations-page"
        class="space-y-4"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <h1 class="text-xl font-semibold tracking-tight">Locations</h1>

        <.form
          for={@new_form}
          id="location-new-form"
          class={[
            "space-y-1.5 rounded-xl border border-dashed p-2 transition-colors",
            "border-base-300 bg-base-200/50",
            "focus-within:border-primary/40 focus-within:bg-base-200"
          ]}
          phx-change="validate_new"
          phx-submit="save_new"
        >
          <div class="join w-full">
            <input
              type="text"
              id={@new_form[:name].id}
              name={@new_form[:name].name}
              value={Phoenix.HTML.Form.normalize_value("text", @new_form[:name].value)}
              placeholder="New location name..."
              autocomplete="off"
              class={[
                "input join-item min-w-0 grow",
                @new_form[:name].errors != [] &&
                  Phoenix.Component.used_input?(@new_form[:name]) && "input-error"
              ]}
            />
            <button
              type="submit"
              id="location-add-button"
              class="btn btn-primary join-item shrink-0"
            >
              Add
            </button>
          </div>
          <p
            :for={msg <- field_errors(@new_form[:name])}
            class="flex items-center gap-2 text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5" />
            {msg}
          </p>
        </.form>

        <div id="locations" class="flex flex-col gap-1" phx-update="stream">
          <div
            id="locations-empty"
            class="hidden only:block rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
          >
            No locations yet. Add one above.
          </div>

          <.link
            :for={{id, location} <- @streams.locations}
            navigate={~p"/location/#{location.id}"}
            id={id}
            class={[
              "flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-3",
              "transition-all hover:border-base-content/20 hover:bg-base-200/40"
            ]}
          >
            <div class="min-w-0 flex-1 truncate font-medium">{location.name}</div>
            <div
              id={"#{id}-item-count"}
              class="shrink-0 text-sm tabular-nums opacity-70"
            >
              {item_count_label(location.item_count || 0)}
            </div>
            <.icon name="hero-chevron-right" class="size-4 shrink-0 opacity-40" />
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    locations = Locations.list_with_item_counts()

    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(:new_form, empty_new_form())
      |> assign(:dirty?, false)
      |> stream_configure(:locations, dom_id: &"location-#{&1.id}")
      |> stream(:locations, locations)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_new", %{"location" => params}, socket) do
    form =
      %Location{}
      |> Locations.change_location(params)
      |> Map.put(:action, :validate)
      |> to_new_form()

    {:noreply,
     socket
     |> assign(:new_form, form)
     |> sync_dirty()}
  end

  def handle_event("save_new", %{"location" => params}, socket) do
    %Location{}
    |> Locations.change_location(params)
    |> then(&Locations.create(socket.assigns.current_scope, &1))
    |> case do
      {:ok, location} ->
        location = %{location | item_count: 0}

        socket =
          socket
          |> assign(:new_form, empty_new_form())
          |> stream_insert(:locations, location, at: 0)
          |> put_flash(:info, "Location created")
          |> sync_dirty()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:new_form, to_new_form(changeset, action: :validate))
         |> sync_dirty()}
    end
  end

  defp empty_new_form do
    %Location{}
    |> Locations.change_location()
    |> to_new_form()
  end

  defp to_new_form(changeset_or_location, opts \\ [])

  defp to_new_form(%Ecto.Changeset{} = changeset, opts) do
    to_form(changeset, Keyword.merge([as: :location, id: "location-new"], opts))
  end

  defp sync_dirty(socket) do
    assign_dirty(socket, row_dirty?(socket.assigns.new_form))
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

  defp row_dirty?(%Phoenix.HTML.Form{source: source}), do: row_dirty?(source)
  defp row_dirty?(%Ecto.Changeset{changes: changes}) when map_size(changes) > 0, do: true
  defp row_dirty?(_), do: false

  defp item_count_label(1), do: "1 item"
  defp item_count_label(count), do: "#{count} items"

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field) do
      Enum.map(field.errors, &translate_error/1)
    else
      []
    end
  end
end
