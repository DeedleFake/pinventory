defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.FloorPlans
  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  import PinventoryWeb.FloorPlanComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      nav={:locations}
      wide={not is_nil(@floor_plan)}
    >
      <div
        id="locations-page"
        class="flex flex-col gap-3"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <div class="flex flex-wrap items-center gap-2 border-b border-base-300 pb-2">
          <h1 class="text-xl font-semibold tracking-tight">Locations</h1>

          <div class="ml-auto flex flex-wrap items-center gap-1">
            <.link
              :if={@floor_plan && @selected_floor}
              navigate={~p"/locations/floor-plan/#{@selected_floor.id}"}
              id="floor-plan-edit"
              class="btn btn-ghost btn-sm border border-base-300"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit floor plan
            </.link>

            <.link
              :if={@floor_plan && is_nil(@selected_floor)}
              navigate={~p"/locations/floor-plan"}
              id="floor-plan-edit"
              class="btn btn-ghost btn-sm border border-base-300"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit floor plan
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
        </div>

        <div
          :if={@floor_plan && @selected_floor}
          id="locations-workspace"
          class="flex min-h-0 flex-col gap-3 lg:flex-row lg:items-stretch"
        >
          <aside
            id="locations-list-pane"
            class="flex w-full min-w-0 flex-1 flex-col gap-3 rounded-2xl border border-base-300 bg-base-100 p-3 lg:min-w-[18rem]"
          >
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

            <.locations_list
              streams={@streams}
              floor_plan={@floor_plan}
              selected_floor={@selected_floor}
              placement_by_location={@placement_by_location}
            />
          </aside>

          <div
            id="locations-floor-canvas"
            phx-hook="FloorPlanCanvas"
            data-mode="browse"
            data-location-id=""
            data-place-mode="new"
            data-existing-points="[]"
            tabindex="0"
            class={[
              "relative min-w-0 shrink-0 overflow-hidden rounded-2xl border border-base-300 bg-base-200/40",
              "h-[calc(100vh-12rem)] min-h-[22rem] w-full touch-none select-none outline-none",
              "focus-visible:ring-2 focus-visible:ring-primary/40",
              "lg:w-[28rem] xl:w-[32rem]",
              "cursor-grab"
            ]}
          >
            <div
              id="locations-floor-view-chrome"
              class="pointer-events-none absolute left-3 top-3 z-10 flex items-center gap-2"
            >
              <button
                type="button"
                id="locations-floor-zoom-reset"
                data-zoom-reset
                class="btn btn-sm btn-ghost border border-base-300 bg-base-100/90 pointer-events-auto shadow-md"
                title="Reset zoom (fits floor)"
              >
                <.icon name="hero-arrows-pointing-out" class="size-4" /> Reset view
              </button>
              <span class="hidden rounded-md border border-base-300 bg-base-100/80 px-2 py-1 text-[10px] opacity-70 sm:inline">
                Wheel zoom · Space/middle-drag pan
              </span>
            </div>

            <svg
              data-floor-plan-svg
              id={"locations-floor-svg-#{@selected_floor.id}"}
              viewBox="0 0 1 1"
              preserveAspectRatio="xMidYMid meet"
              class="h-full w-full text-base-content"
            >
              <rect x="0" y="0" width="1" height="1" class="fill-base-100" stroke="none" />

              <.placement_area
                :for={placement <- @selected_floor.location_placements}
                placement={placement}
                navigate={~p"/location/#{placement.location_id}"}
                list_row_id={"location-#{placement.location_id}"}
              />

              <g :for={wall <- @selected_floor.walls}>
                <line
                  data-wall-seg
                  x1={wall["x1"]}
                  y1={wall["y1"]}
                  x2={wall["x2"]}
                  y2={wall["y2"]}
                  stroke="currentColor"
                  stroke-width="0.014"
                  stroke-linecap="round"
                  class="opacity-80 pointer-events-none"
                />
              </g>
            </svg>

            <p
              :if={@selected_floor.walls == [] and @selected_floor.location_placements == []}
              class="pointer-events-none absolute inset-0 flex items-center justify-center p-6 text-center text-sm opacity-50"
            >
              This floor is empty. Edit the floor plan to draw walls and place locations.
            </p>
          </div>

          <aside
            id="locations-floor-rail"
            class="flex w-full shrink-0 flex-col gap-2 rounded-2xl border border-base-300 bg-base-100 p-3 lg:w-52"
          >
            <div class="flex items-center justify-between gap-2 px-0.5">
              <h2 class="text-xs font-semibold uppercase tracking-wide opacity-50">Floors</h2>
              <span class="text-[10px] uppercase tracking-wide opacity-50">View</span>
            </div>

            <ul
              id="locations-floor-rail-list"
              class="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto"
            >
              <li
                :for={floor <- floors_top_first(@floors)}
                id={"locations-floor-rail-item-#{floor.id}"}
                class={[
                  "rounded-lg border",
                  floor.id == @selected_floor.id && "border-primary bg-primary/10",
                  floor.id != @selected_floor.id && "border-transparent hover:border-base-300"
                ]}
              >
                <button
                  type="button"
                  id={"locations-floor-tab-#{floor.id}"}
                  phx-click="select_floor"
                  phx-value-id={floor.id}
                  class={[
                    "w-full truncate rounded-md px-2.5 py-2 text-left text-sm font-medium",
                    floor.id == @selected_floor.id && "text-primary",
                    floor.id != @selected_floor.id && "opacity-80 hover:opacity-100"
                  ]}
                >
                  {floor.name}
                </button>
              </li>
            </ul>
          </aside>
        </div>

        <div :if={is_nil(@floor_plan)} id="locations-no-plan" class="flex flex-col gap-3">
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

          <.locations_list
            streams={@streams}
            floor_plan={nil}
            selected_floor={nil}
            placement_by_location={%{}}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :streams, :map, required: true
  attr :floor_plan, :any, default: nil
  attr :selected_floor, :any, default: nil
  attr :placement_by_location, :map, default: %{}

  defp locations_list(assigns) do
    ~H"""
    <div id="locations-list-hover" phx-hook="PlacementListHover">
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
          data-location-id={location.id}
          class={[
            "flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-3",
            "transition-all hover:border-base-content/20 hover:bg-base-200/40"
          ]}
        >
          <div class="min-w-0 flex-1">
            <div class="truncate font-medium">{location.name}</div>
            <div :if={@floor_plan} class="mt-0.5 flex flex-wrap items-center gap-1.5">
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
          <div id={"#{id}-item-count"} class="shrink-0 text-sm tabular-nums opacity-70">
            {item_count_label(location.item_count || 0)}
          </div>
          <.icon name="hero-chevron-right" class="size-4 shrink-0 opacity-40" />
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    floor_plan = FloorPlans.get_floor_plan()
    floors = if(floor_plan, do: floor_plan.floors, else: [])
    selected = List.first(floors)
    locations = Locations.list_with_item_counts_and_placements()

    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(:new_form, empty_new_form())
      |> assign(:dirty?, false)
      |> assign(:floor_plan, floor_plan)
      |> assign(:floors, floors)
      |> assign(:selected_floor, selected && FloorPlans.get_floor!(selected.id))
      |> assign(
        :placement_by_location,
        if(floor_plan, do: FloorPlans.placement_index(), else: %{})
      )
      |> stream_configure(:locations, dom_id: &"location-#{&1.id}")
      |> stream(:locations, locations)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"floor_id" => floor_id}, _uri, socket) do
    cond do
      is_nil(socket.assigns.floor_plan) ->
        {:noreply, push_patch(socket, to: ~p"/locations")}

      true ->
        case Enum.find(socket.assigns.floors, &(&1.id == floor_id)) do
          nil ->
            first = List.first(socket.assigns.floors)
            {:noreply, fallback_to_floor(socket, first && first.id)}

          floor ->
            {:noreply, apply_selected_floor(socket, floor)}
        end
    end
  end

  def handle_params(_params, _uri, socket) do
    case socket.assigns.floor_plan && List.first(socket.assigns.floors) do
      nil ->
        {:noreply, socket}

      floor ->
        {:noreply, fallback_to_floor(socket, floor.id)}
    end
  end

  @impl true
  def handle_info({:patch_floor_url, floor_id}, socket) do
    {:noreply, push_patch(socket, to: locations_floor_path(floor_id))}
  end

  @impl true
  def handle_event("select_floor", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.floors, &(&1.id == id)) do
      {:noreply, push_patch(socket, to: locations_floor_path(id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_floor_plan", _params, socket) do
    case FloorPlans.create_floor_plan() do
      {:ok, plan} ->
        floor = hd(plan.floors)
        {:noreply, push_navigate(socket, to: ~p"/locations/floor-plan/#{floor.id}")}

      {:error, :already_exists} ->
        plan = FloorPlans.get_floor_plan()
        floor = plan && List.first(plan.floors)

        path =
          if(floor, do: ~p"/locations/floor-plan/#{floor.id}", else: ~p"/locations/floor-plan")

        {:noreply, push_navigate(socket, to: path)}

      {:error, _} ->
        {:noreply, socket}
    end
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

  defp fallback_to_floor(socket, nil), do: socket

  defp fallback_to_floor(socket, floor_id) do
    floor =
      Enum.find(socket.assigns.floors, &(&1.id == floor_id)) || List.first(socket.assigns.floors)

    socket = apply_selected_floor(socket, floor)

    if connected?(socket) do
      send(self(), {:patch_floor_url, floor.id})
    end

    socket
  end

  defp apply_selected_floor(socket, floor) do
    assign(socket, :selected_floor, FloorPlans.get_floor!(floor.id))
  end

  defp locations_floor_path(floor_id), do: ~p"/locations/#{floor_id}"

  defp floors_top_first(floors) when is_list(floors) do
    Enum.sort_by(floors, & &1.position, :desc)
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
