defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.FloorPlans
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
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h1 class="text-xl font-semibold tracking-tight">Locations</h1>

          <.link
            :if={@floor_plan}
            navigate={~p"/locations/floor-plan"}
            id="floor-plan-edit"
            class="btn btn-ghost btn-sm border border-base-300"
          >
            <.icon name="hero-map" class="size-4" /> Edit floor plan
          </.link>

          <button
            :if={is_nil(@floor_plan)}
            type="button"
            id="floor-plan-add"
            class="btn btn-primary btn-sm"
            phx-click="add_floor_plan"
          >
            <.icon name="hero-map" class="size-4" /> Add Floor Plan
          </button>
        </div>

        <div
          :if={@floor_plan && @preview_floor}
          id="floor-plan-preview"
          class={[
            "overflow-hidden rounded-2xl border border-base-300 bg-base-100",
            "transition-all"
          ]}
        >
          <div class="flex items-center justify-between gap-3 border-b border-base-300 px-3 py-2">
            <div class="min-w-0">
              <p class="text-sm font-medium tracking-tight">Floor plan</p>
              <p class="truncate text-xs opacity-60">
                {@preview_floor.name}
                <span :if={length(@floor_plan.floors) > 1}>
                  · {length(@floor_plan.floors)} floors
                </span>
                · hover a location to highlight its area
              </p>
            </div>
            <.link
              navigate={~p"/locations/floor-plan"}
              id="floor-plan-preview-edit"
              class="btn btn-ghost btn-xs border border-base-300"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.link>
          </div>
          <div class="w-full bg-base-200/40 p-2 sm:p-3 min-h-[45vh] h-[50vh]">
            <svg
              id="floor-plan-preview-svg"
              viewBox="0 0 1 1"
              preserveAspectRatio="none"
              class="h-full w-full rounded-lg text-base-content"
            >
              <rect x="0" y="0" width="1" height="1" class="fill-base-100" />
              <g :for={placement <- @preview_floor.location_placements}>
                <polygon
                  id={"preview-placement-#{placement.location_id}"}
                  data-placement-location-id={placement.location_id}
                  points={FloorPlans.polygon_points_attr(placement.points)}
                  class={[
                    "stroke-primary transition-all duration-150",
                    @highlighted_location_id == placement.location_id &&
                      "fill-primary/45 opacity-100",
                    @highlighted_location_id != placement.location_id &&
                      @highlighted_location_id != nil && "fill-primary/10 opacity-40",
                    @highlighted_location_id == nil && "fill-primary/25 opacity-90"
                  ]}
                  stroke-width={
                    if(@highlighted_location_id == placement.location_id, do: "0.01", else: "0.006")
                  }
                />
                <text
                  x={placement_label_x(placement.points)}
                  y={placement_label_y(placement.points)}
                  text-anchor="middle"
                  dominant-baseline="middle"
                  font-size="0.035"
                  class={[
                    "fill-base-content pointer-events-none",
                    @highlighted_location_id != nil &&
                      @highlighted_location_id != placement.location_id && "opacity-30"
                  ]}
                  style="paint-order: stroke; stroke: var(--color-base-100, #fff); stroke-width: 0.01px;"
                >
                  {placement.location && placement.location.name}
                </text>
              </g>
              <line
                :for={wall <- @preview_floor.walls}
                x1={wall["x1"]}
                y1={wall["y1"]}
                x2={wall["x2"]}
                y2={wall["y2"]}
                stroke="currentColor"
                stroke-width="0.014"
                stroke-linecap="round"
                class="opacity-70"
              />
            </svg>
          </div>
        </div>

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
            phx-mouseover={if(@floor_plan && location.on_plan?, do: "highlight_placement")}
            phx-value-id={location.id}
            phx-mouseout={if(@floor_plan, do: "clear_highlight")}
            phx-focus={if(@floor_plan && location.on_plan?, do: "highlight_placement")}
            phx-blur={if(@floor_plan, do: "clear_highlight")}
            class={[
              "flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-3",
              "transition-all hover:border-base-content/20 hover:bg-base-200/40",
              @highlighted_location_id == location.id &&
                "border-primary/50 bg-primary/5 ring-1 ring-primary/20"
            ]}
          >
            <div class="min-w-0 flex-1">
              <div class="truncate font-medium">{location.name}</div>
              <div
                :if={@floor_plan}
                class="mt-0.5 flex flex-wrap items-center gap-1.5"
              >
                <span
                  :if={location.on_plan?}
                  id={"#{id}-floor"}
                  class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-medium text-primary"
                >
                  <.icon name="hero-map" class="size-3" />
                  {location.floor_name}
                </span>
                <span
                  :if={not location.on_plan?}
                  id={"#{id}-not-on-plan"}
                  class="inline-flex items-center gap-1 rounded-full bg-warning/15 px-2 py-0.5 text-[11px] font-medium text-warning"
                >
                  <.icon name="hero-exclamation-triangle" class="size-3" /> Not on plan
                </span>
              </div>
            </div>
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
    floor_plan = FloorPlans.get_floor_plan()
    locations = Locations.list_with_item_counts_and_placements()
    preview_floor = floor_plan && List.first(floor_plan.floors)

    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(:new_form, empty_new_form())
      |> assign(:dirty?, false)
      |> assign(:floor_plan, floor_plan)
      |> assign(:preview_floor, preview_floor)
      |> assign(:highlighted_location_id, nil)
      |> assign(
        :placement_by_location,
        if(floor_plan, do: FloorPlans.placement_index(), else: %{})
      )
      |> stream_configure(:locations, dom_id: &"location-#{&1.id}")
      |> stream(:locations, locations)

    {:ok, socket}
  end

  @impl true
  def handle_event("add_floor_plan", _params, socket) do
    case FloorPlans.create_floor_plan() do
      {:ok, _plan} ->
        {:noreply, push_navigate(socket, to: ~p"/locations/floor-plan")}

      {:error, :already_exists} ->
        {:noreply, push_navigate(socket, to: ~p"/locations/floor-plan")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("highlight_placement", %{"id" => location_id}, socket) do
    case Map.get(socket.assigns.placement_by_location, location_id) do
      %{floor_id: floor_id} ->
        preview =
          case Enum.find(socket.assigns.floor_plan.floors, &(&1.id == floor_id)) do
            nil -> socket.assigns.preview_floor
            floor -> FloorPlans.get_floor!(floor.id)
          end

        {:noreply,
         socket
         |> assign(:highlighted_location_id, location_id)
         |> assign(:preview_floor, preview)}

      nil ->
        {:noreply, assign(socket, :highlighted_location_id, nil)}
    end
  end

  def handle_event("clear_highlight", _params, socket) do
    {:noreply, assign(socket, :highlighted_location_id, nil)}
  end

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
        location = %{location | item_count: 0, on_plan?: false, floor_name: nil}

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

  defp placement_label_x(points), do: elem(FloorPlans.polygon_centroid(points), 0)
  defp placement_label_y(points), do: elem(FloorPlans.polygon_centroid(points), 1)
end
