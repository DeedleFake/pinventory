defmodule PinventoryWeb.FloorPlanLive do
  use PinventoryWeb, :live_view

  alias Pinventory.FloorPlans
  alias Pinventory.FloorPlans.Floor

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:locations} wide>
      <div id="floor-plan-page" class="flex flex-col gap-3">
        <div
          id="floor-plan-topbar"
          class="flex flex-wrap items-center gap-2 border-b border-base-300 pb-2"
        >
          <div class="flex min-w-0 flex-wrap items-center gap-1.5 text-sm">
            <.link
              navigate={~p"/locations"}
              id="floor-plan-back"
              class="inline-flex items-center gap-1 opacity-60 transition-opacity hover:opacity-100 hover:underline"
            >
              <.icon name="hero-chevron-left" class="size-3.5" /> Locations
            </.link>
            <.icon name="hero-chevron-right" class="size-3.5 opacity-40" />
            <span class="font-medium tracking-tight">Floor plan</span>
          </div>

          <div class="ml-auto flex flex-wrap items-center gap-1">
            <button
              type="button"
              id="floor-plan-delete"
              class="btn btn-sm btn-ghost text-error hover:bg-error/10"
              phx-click="open_delete_plan"
            >
              <.icon name="hero-trash" class="size-4" /> Delete plan
            </button>
          </div>
        </div>

        <div
          :if={@delete_plan?}
          id="floor-plan-delete-confirm"
          class="rounded-xl border border-error/40 bg-error/5 p-4 space-y-3"
        >
          <p class="text-sm">
            Delete the whole floor plan? Locations stay; placements on the plan are removed.
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              id="floor-plan-delete-confirm-button"
              class="btn btn-error"
              phx-click="confirm_delete_plan"
            >
              Delete floor plan
            </button>
            <button
              type="button"
              id="floor-plan-delete-cancel"
              class="btn btn-ghost"
              phx-click="cancel_delete_plan"
            >
              Cancel
            </button>
          </div>
        </div>

        <div
          id="floor-plan-workspace"
          class="flex min-h-0 flex-col gap-3 lg:flex-row lg:items-stretch"
        >
          <aside
            id="floor-plan-sidebar"
            class="flex w-full shrink-0 flex-col gap-4 rounded-2xl border border-base-300 bg-base-100 p-3 lg:w-[17rem]"
          >
            <section id="floor-plan-history" class="flex flex-wrap items-center gap-1.5">
              <button
                type="button"
                id="history-undo"
                class="btn btn-sm btn-ghost flex-1 justify-start"
                phx-click="undo"
                disabled={@undo_stack == []}
                title="Undo (Ctrl+Z)"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" /> Undo
              </button>
              <button
                type="button"
                id="history-redo"
                class="btn btn-sm btn-ghost flex-1 justify-start"
                phx-click="redo"
                disabled={@redo_stack == []}
                title="Redo (Ctrl+Shift+Z)"
              >
                <.icon name="hero-arrow-uturn-right" class="size-4" /> Redo
              </button>
            </section>

            <section id="floor-plan-wall-tools" class="space-y-2">
              <h2 class="text-xs font-semibold uppercase tracking-wide opacity-50">Walls</h2>
              <div class="flex flex-col gap-1.5">
                <button
                  type="button"
                  id="tool-wall"
                  phx-click="set_mode"
                  phx-value-mode="wall"
                  class={[
                    "btn btn-sm justify-start",
                    @mode == "wall" && "btn-primary",
                    @mode != "wall" && "btn-ghost border border-base-300"
                  ]}
                >
                  <.icon name="hero-pencil" class="size-4" /> Draw wall
                </button>
                <button
                  type="button"
                  id="tool-erase"
                  phx-click="set_mode"
                  phx-value-mode="erase"
                  class={[
                    "btn btn-sm justify-start",
                    @mode == "erase" && "btn-primary",
                    @mode != "erase" && "btn-ghost border border-base-300"
                  ]}
                >
                  <.icon name="hero-trash" class="size-4" /> Erase
                </button>
              </div>
            </section>

            <section id="floor-plan-location-tools" class="flex min-h-0 flex-1 flex-col gap-2">
              <div class="space-y-1">
                <h2 class="text-xs font-semibold uppercase tracking-wide opacity-50">Locations</h2>
                <p class="text-xs opacity-60">
                  Click an unplaced location to draw its area. Locations already on the plan cannot be drawn again; click one to open its floor.
                </p>
              </div>

              <ul
                id="placeable-locations"
                class="flex max-h-[min(32rem,55vh)] flex-col gap-1 overflow-y-auto lg:max-h-none lg:flex-1"
              >
                <li
                  :if={@locations == []}
                  class="rounded-lg px-2 py-6 text-center text-sm opacity-50"
                >
                  No locations yet. Add some on the Locations page.
                </li>
                <li :for={location <- @locations} class="flex items-stretch gap-1">
                  <button
                    :if={not Map.has_key?(@placement_by_location, location.id)}
                    type="button"
                    id={"place-location-#{location.id}"}
                    phx-click="select_location"
                    phx-value-id={location.id}
                    class={[
                      "flex min-w-0 flex-1 items-center gap-2 rounded-lg border px-2.5 py-2 text-left text-sm transition-colors",
                      @mode == "place" && @placing_location_id == location.id &&
                        "border-primary bg-primary/10 ring-1 ring-primary/30",
                      not (@mode == "place" && @placing_location_id == location.id) &&
                        "border-transparent hover:border-base-300 hover:bg-base-200/60"
                    ]}
                  >
                    <span class="min-w-0 flex-1 truncate font-medium">{location.name}</span>
                    <span class="shrink-0 rounded-full bg-warning/15 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-warning">
                      Open
                    </span>
                  </button>
                  <button
                    :if={
                      location_placed_on_other_floor?(
                        location.id,
                        @selected_floor,
                        @placement_by_location
                      )
                    }
                    type="button"
                    id={"place-location-#{location.id}"}
                    phx-click="select_floor"
                    phx-value-id={@placement_by_location[location.id].floor_id}
                    title={"Go to #{@placement_by_location[location.id].floor_name}"}
                    class="flex min-w-0 flex-1 items-center gap-2 rounded-lg border border-transparent px-2.5 py-2 text-left text-sm transition-colors hover:border-base-300 hover:bg-base-200/60"
                  >
                    <span class="min-w-0 flex-1 truncate font-medium">{location.name}</span>
                    <span class="shrink-0 rounded-full bg-base-200 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide opacity-70">
                      {floor_label(@placement_by_location[location.id], @selected_floor.id)}
                    </span>
                  </button>
                  <div
                    :if={location_placed_on_floor?(location.id, @selected_floor)}
                    id={"place-location-#{location.id}"}
                    aria-disabled="true"
                    class="flex min-w-0 flex-1 cursor-not-allowed items-center gap-2 rounded-lg border border-transparent px-2.5 py-2 text-left text-sm opacity-60"
                  >
                    <span class="min-w-0 flex-1 truncate font-medium">{location.name}</span>
                    <span class="shrink-0 rounded-full bg-base-200 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide opacity-70">
                      {floor_label(@placement_by_location[location.id], @selected_floor.id)}
                    </span>
                  </div>
                  <button
                    :if={location_placed_on_floor?(location.id, @selected_floor)}
                    type="button"
                    id={"unplace-location-#{location.id}"}
                    class="btn btn-square btn-sm btn-ghost text-error hover:bg-error/10"
                    phx-click="unplace_location"
                    phx-value-id={location.id}
                    title="Remove from this floor"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </li>
              </ul>
            </section>
          </aside>

          <aside
            id="floor-rail"
            class="flex w-full shrink-0 flex-col gap-2 rounded-2xl border border-base-300 bg-base-100 p-2 sm:w-36 lg:w-40"
          >
            <div class="space-y-1 px-0.5">
              <h2 class="text-[10px] font-semibold uppercase tracking-wide opacity-50">Floors</h2>
              <form id="floor-rename-form" phx-submit="rename_floor" class="flex flex-col gap-1">
                <label class="sr-only" for="floor-name">Floor name</label>
                <input
                  type="text"
                  id="floor-name"
                  name="name"
                  value={@selected_floor.name}
                  autocomplete="off"
                  class="input input-xs w-full min-w-0"
                />
                <button
                  type="submit"
                  id="floor-rename-save"
                  class="btn btn-xs btn-ghost border border-base-300"
                >
                  Rename
                </button>
              </form>
            </div>

            <ul id="floor-rail-list" class="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto">
              <li
                :for={floor <- floors_top_first(@floors)}
                id={"floor-rail-item-#{floor.id}"}
                class={[
                  "flex items-stretch gap-0.5 rounded-lg border px-0.5 py-0.5",
                  floor.id == @selected_floor.id && "border-primary bg-primary/10",
                  floor.id != @selected_floor.id && "border-transparent hover:border-base-300"
                ]}
              >
                <div class="flex flex-col justify-center gap-0">
                  <button
                    type="button"
                    id={"floor-move-up-#{floor.id}"}
                    class="btn btn-ghost btn-xs h-5 min-h-0 w-5 p-0 opacity-70 hover:opacity-100"
                    phx-click="move_floor"
                    phx-value-id={floor.id}
                    phx-value-dir="up"
                    disabled={floor_at_top?(floor, @floors)}
                    title="Move higher"
                  >
                    <.icon name="hero-chevron-up" class="size-3" />
                  </button>
                  <button
                    type="button"
                    id={"floor-move-down-#{floor.id}"}
                    class="btn btn-ghost btn-xs h-5 min-h-0 w-5 p-0 opacity-70 hover:opacity-100"
                    phx-click="move_floor"
                    phx-value-id={floor.id}
                    phx-value-dir="down"
                    disabled={floor_at_bottom?(floor, @floors)}
                    title="Move lower"
                  >
                    <.icon name="hero-chevron-down" class="size-3" />
                  </button>
                </div>
                <button
                  type="button"
                  id={"floor-tab-#{floor.id}"}
                  phx-click="select_floor"
                  phx-value-id={floor.id}
                  class={[
                    "min-w-0 flex-1 truncate rounded-md px-1.5 py-1.5 text-left text-xs font-medium",
                    floor.id == @selected_floor.id && "text-primary",
                    floor.id != @selected_floor.id && "opacity-80 hover:opacity-100"
                  ]}
                >
                  {floor.name}
                </button>
              </li>
            </ul>

            <div class="flex flex-col gap-1 border-t border-base-300 pt-2">
              <button
                type="button"
                id="floor-add"
                class="btn btn-xs btn-ghost justify-start border border-dashed border-base-300"
                phx-click="add_floor"
              >
                <.icon name="hero-plus" class="size-3.5" /> Floor
              </button>
              <button
                type="button"
                id="floor-remove"
                class="btn btn-xs btn-ghost justify-start text-error hover:bg-error/10"
                phx-click="remove_floor"
                disabled={length(@floors) <= 1}
              >
                <.icon name="hero-minus-circle" class="size-3.5" /> Remove
              </button>
            </div>
          </aside>

          <div
            id="floor-plan-canvas"
            phx-hook="FloorPlanCanvas"
            data-mode={@mode}
            data-location-id={@placing_location_id || ""}
            data-place-mode={@place_mode}
            data-existing-points={@existing_points_json}
            tabindex="0"
            class={[
              "relative min-w-0 flex-1 overflow-hidden rounded-2xl border border-base-300 bg-base-200/40",
              "h-[calc(100vh-12rem)] min-h-[28rem] w-full touch-none select-none outline-none",
              "focus-visible:ring-2 focus-visible:ring-primary/40",
              @mode == "wall" && "cursor-crosshair",
              @mode == "erase" && "cursor-pointer",
              @mode == "place" && @placing_location_id && "cursor-cell",
              @mode == "place" && !@placing_location_id && "cursor-not-allowed"
            ]}
          >
            <div
              id="polygon-finish-bar"
              class="pointer-events-none absolute right-3 top-3 z-10 flex items-center gap-2"
            >
              <button
                type="button"
                id="polygon-finish"
                data-polygon-finish
                class="btn btn-sm btn-primary pointer-events-auto shadow-md hidden"
                title="Finish area"
              >
                <.icon name="hero-check" class="size-4" /> Done
              </button>
            </div>

            <svg
              data-floor-plan-svg
              id={"floor-svg-#{@selected_floor.id}"}
              viewBox="0 0 1 1"
              preserveAspectRatio="none"
              class="h-full w-full text-base-content"
            >
              <rect
                x="0"
                y="0"
                width="1"
                height="1"
                class="fill-base-100"
                stroke="none"
              />

              <g :for={placement <- @selected_floor.location_placements}>
                <polygon
                  data-placement-location-id={placement.location_id}
                  points={FloorPlans.polygon_points_attr(placement.points)}
                  class={[
                    "stroke-primary transition-opacity",
                    @selected_placement_id == placement.location_id &&
                      "fill-primary/35 opacity-100",
                    @selected_placement_id != placement.location_id &&
                      "fill-primary/20 opacity-90"
                  ]}
                  stroke-width="0.006"
                />
                <g data-placement-snap={placement.location_id} class="pointer-events-none">
                  <line
                    :for={edge <- placement_edges(placement.points)}
                    data-snap-edge
                    x1={edge.x1}
                    y1={edge.y1}
                    x2={edge.x2}
                    y2={edge.y2}
                    stroke="transparent"
                    stroke-width="0.001"
                  />
                  <circle
                    :for={vertex <- placement.points}
                    data-snap-vertex
                    cx={point_x(vertex)}
                    cy={point_y(vertex)}
                    r="0.001"
                    class="fill-transparent"
                  />
                </g>
                <text
                  x={placement_label_x(placement.points)}
                  y={placement_label_y(placement.points)}
                  text-anchor="middle"
                  dominant-baseline="middle"
                  font-size="0.04"
                  class="fill-base-content pointer-events-none"
                  style="paint-order: stroke; stroke: var(--color-base-100, #fff); stroke-width: 0.012px;"
                >
                  {placement.location && placement.location.name}
                </text>
              </g>

              <g :for={{wall, index} <- Enum.with_index(@selected_floor.walls)}>
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
                <line
                  data-wall-index={index}
                  x1={wall["x1"]}
                  y1={wall["y1"]}
                  x2={wall["x2"]}
                  y2={wall["y2"]}
                  stroke="transparent"
                  stroke-width="0.045"
                  stroke-linecap="round"
                  class={[
                    @mode == "erase" && "cursor-pointer",
                    @mode != "erase" && "pointer-events-none"
                  ]}
                />
              </g>
            </svg>

            <p
              :if={@selected_floor.walls == [] and @selected_floor.location_placements == []}
              class="pointer-events-none absolute inset-0 flex items-center justify-center p-6 text-center text-sm opacity-50"
            >
              <%= cond do %>
                <% @mode == "wall" -> %>
                  Click once for the start, again for the end. Snap to walls and location corners. Escape cancels.
                <% @mode == "erase" -> %>
                  Click a wall segment to erase it.
                <% @mode == "place" && @placing_location_id && @place_mode == "extend" -> %>
                  Click a corner to attach, add points, then click a different corner to close, or Done to close on an adjacent edge. Escape cancels.
                <% @mode == "place" && @placing_location_id -> %>
                  Click points to draw an area. Close near the first point, double-click, or Done. Escape cancels.
                <% true -> %>
                  Choose a location in the sidebar, then click points to draw its area.
              <% end %>
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    case FloorPlans.get_floor_plan() do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/locations")}

      plan ->
        floors = plan.floors
        selected = List.first(floors)

        {:ok,
         socket
         |> assign(:page_title, "Floor plan")
         |> assign(:floor_plan, plan)
         |> assign(:floors, floors)
         |> assign(:selected_floor, selected)
         |> assign(:mode, "wall")
         |> assign(:placing_location_id, nil)
         |> assign(:place_mode, "new")
         |> assign(:existing_points_json, "[]")
         |> assign(:selected_placement_id, nil)
         |> assign(:delete_plan?, false)
         |> assign(:undo_stack, [])
         |> assign(:redo_stack, [])
         |> assign_location_lists()}
    end
  end

  @impl true
  def handle_event("select_floor", %{"id" => id}, socket) do
    floor = Enum.find(socket.assigns.floors, &(&1.id == id)) || socket.assigns.selected_floor

    {:noreply,
     socket
     |> assign(:selected_floor, FloorPlans.get_floor!(floor.id))
     |> assign(:selected_placement_id, nil)}
  end

  def handle_event("add_floor", _params, socket) do
    case FloorPlans.add_floor(socket.assigns.floor_plan) do
      {:ok, floor} ->
        plan = FloorPlans.get_floor_plan()

        {:noreply,
         socket
         |> assign(:floor_plan, plan)
         |> assign(:floors, plan.floors)
         |> assign(:selected_floor, floor)
         |> assign(:selected_placement_id, nil)
         |> clear_history()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("rename_floor", %{"name" => name}, socket) do
    case FloorPlans.rename_floor(socket.assigns.selected_floor, name) do
      {:ok, floor} ->
        plan = FloorPlans.get_floor_plan()

        {:noreply,
         socket
         |> assign(:floor_plan, plan)
         |> assign(:floors, plan.floors)
         |> assign(:selected_floor, floor)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("move_floor", %{"id" => id, "dir" => dir}, socket)
      when dir in ["up", "down"] do
    floor = Enum.find(socket.assigns.floors, &(&1.id == id))

    direction =
      case dir do
        "up" -> :higher
        "down" -> :lower
      end

    case floor && FloorPlans.move_floor(floor, direction) do
      {:ok, _} ->
        plan = FloorPlans.get_floor_plan()
        selected_id = socket.assigns.selected_floor.id
        selected = Enum.find(plan.floors, &(&1.id == selected_id)) || List.first(plan.floors)

        {:noreply,
         socket
         |> assign(:floor_plan, plan)
         |> assign(:floors, plan.floors)
         |> assign(:selected_floor, FloorPlans.get_floor!(selected.id))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_floor", _params, socket) do
    case FloorPlans.delete_floor(socket.assigns.selected_floor) do
      {:ok, _} ->
        plan = FloorPlans.get_floor_plan()
        selected = List.first(plan.floors)

        {:noreply,
         socket
         |> assign(:floor_plan, plan)
         |> assign(:floors, plan.floors)
         |> assign(:selected_floor, selected)
         |> assign(:selected_placement_id, nil)
         |> assign_location_lists()
         |> clear_history()}

      {:error, :last_floor} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in ["wall", "erase"] do
    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:placing_location_id, nil)
     |> assign(:place_mode, "new")
     |> assign(:existing_points_json, "[]")}
  end

  def handle_event("select_location", %{"id" => id}, socket) do
    if Map.has_key?(socket.assigns.placement_by_location, id) do
      {:noreply, socket}
    else
      {place_mode, points_json} = place_mode_for(socket, id)

      {:noreply,
       socket
       |> assign(:mode, "place")
       |> assign(:placing_location_id, id)
       |> assign(:place_mode, place_mode)
       |> assign(:existing_points_json, points_json)
       |> assign(:selected_placement_id, id)}
    end
  end

  def handle_event("wall_drawn", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    wall = %{
      "x1" => to_float(x1),
      "y1" => to_float(y1),
      "x2" => to_float(x2),
      "y2" => to_float(y2)
    }

    socket = push_undo_snapshot(socket)

    case FloorPlans.add_wall(socket.assigns.selected_floor, wall) do
      {:ok, floor} ->
        {:noreply, refresh_selected_floor(socket, floor)}

      {:error, _} ->
        {:noreply, pop_failed_undo(socket)}
    end
  end

  def handle_event("wall_erased", %{"index" => index}, socket) do
    index = parse_index(index)
    floor = socket.assigns.selected_floor
    socket = push_undo_snapshot(socket)

    case FloorPlans.remove_wall(floor, index) do
      {:ok, updated} ->
        {:noreply, refresh_selected_floor(socket, updated)}

      {:error, _} ->
        {:noreply, pop_failed_undo(socket)}
    end
  end

  def handle_event("polygon_placed", %{"location_id" => location_id, "points" => points}, socket) do
    place_polygon(socket, location_id, points)
  end

  def handle_event("unplace_location", %{"id" => location_id}, socket) do
    socket = push_undo_snapshot(socket)
    _ = FloorPlans.unplace_location(location_id)
    floor = FloorPlans.get_floor!(socket.assigns.selected_floor.id)

    selected_placement =
      if socket.assigns.selected_placement_id == location_id,
        do: nil,
        else: socket.assigns.selected_placement_id

    socket =
      socket
      |> refresh_selected_floor(floor)
      |> assign(:selected_placement_id, selected_placement)
      |> assign_location_lists()

    socket =
      if socket.assigns.placing_location_id == location_id do
        socket
        |> assign(:place_mode, "new")
        |> assign(:existing_points_json, "[]")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [] ->
        {:noreply, socket}

      [entry | rest] ->
        # Keep the affected floor id so redo also switches back to that floor.
        current = history_entry(socket, entry.floor_id)

        case FloorPlans.restore_plan_geometry(entry.snapshot) do
          {:ok, plan} ->
            {:noreply,
             socket
             |> assign(:floor_plan, plan)
             |> assign(:floors, plan.floors)
             |> assign(:undo_stack, rest)
             |> assign(:redo_stack, trim_stack([current | socket.assigns.redo_stack]))
             |> select_history_floor(plan, entry.floor_id)
             |> assign_location_lists()}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("redo", _params, socket) do
    case socket.assigns.redo_stack do
      [] ->
        {:noreply, socket}

      [entry | rest] ->
        current = history_entry(socket, entry.floor_id)

        case FloorPlans.restore_plan_geometry(entry.snapshot) do
          {:ok, plan} ->
            {:noreply,
             socket
             |> assign(:floor_plan, plan)
             |> assign(:floors, plan.floors)
             |> assign(:redo_stack, rest)
             |> assign(:undo_stack, trim_stack([current | socket.assigns.undo_stack]))
             |> select_history_floor(plan, entry.floor_id)
             |> assign_location_lists()}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("open_delete_plan", _params, socket) do
    {:noreply, assign(socket, :delete_plan?, true)}
  end

  def handle_event("cancel_delete_plan", _params, socket) do
    {:noreply, assign(socket, :delete_plan?, false)}
  end

  def handle_event("confirm_delete_plan", _params, socket) do
    case FloorPlans.delete_floor_plan(socket.assigns.floor_plan) do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: ~p"/locations")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp place_polygon(socket, location_id, points) do
    normalized = normalize_event_points(points)

    if length(normalized) < 3 do
      {:noreply, socket}
    else
      socket = push_undo_snapshot(socket)

      case FloorPlans.place_location(socket.assigns.selected_floor, location_id, normalized) do
        {:ok, _placement} ->
          floor = FloorPlans.get_floor!(socket.assigns.selected_floor.id)

          {:noreply,
           socket
           |> refresh_selected_floor(floor)
           |> assign(:selected_placement_id, location_id)
           |> assign(:placing_location_id, nil)
           |> assign(:place_mode, "new")
           |> assign(:existing_points_json, "[]")
           |> assign(:mode, "place")
           |> assign_location_lists()}

        {:error, _} ->
          {:noreply, pop_failed_undo(socket)}
      end
    end
  end

  defp push_undo_snapshot(socket) do
    socket
    |> assign(:undo_stack, trim_stack([history_entry(socket) | socket.assigns.undo_stack]))
    |> assign(:redo_stack, [])
  end

  defp history_entry(socket, floor_id \\ nil) do
    %{
      floor_id: floor_id || socket.assigns.selected_floor.id,
      snapshot: FloorPlans.plan_geometry_snapshot(socket.assigns.floor_plan)
    }
  end

  defp select_history_floor(socket, plan, floor_id) do
    selected =
      Enum.find(plan.floors, &(&1.id == floor_id)) ||
        Enum.find(plan.floors, &(&1.id == socket.assigns.selected_floor.id)) ||
        List.first(plan.floors)

    socket
    |> assign(:selected_floor, FloorPlans.get_floor!(selected.id))
    |> assign(:selected_placement_id, nil)
  end

  defp pop_failed_undo(socket) do
    case socket.assigns.undo_stack do
      [_ | rest] -> assign(socket, :undo_stack, rest)
      [] -> socket
    end
  end

  defp clear_history(socket) do
    socket
    |> assign(:undo_stack, [])
    |> assign(:redo_stack, [])
  end

  defp trim_stack(stack) do
    Enum.take(stack, FloorPlans.undo_limit())
  end

  defp refresh_selected_floor(socket, %Floor{} = floor) do
    plan = FloorPlans.get_floor_plan()

    socket
    |> assign(:floor_plan, plan)
    |> assign(:floors, plan.floors)
    |> assign(:selected_floor, floor)
  end

  defp assign_location_lists(socket) do
    placements = FloorPlans.placement_index()

    socket
    |> assign(:locations, FloorPlans.list_locations())
    |> assign(:placement_by_location, placements)
  end

  defp location_placed_on_floor?(location_id, %Floor{} = floor) do
    Enum.any?(floor.location_placements, &(&1.location_id == location_id))
  end

  defp location_placed_on_other_floor?(location_id, %Floor{} = floor, placement_by_location) do
    case Map.get(placement_by_location, location_id) do
      %{floor_id: floor_id} when floor_id != floor.id -> true
      _ -> false
    end
  end

  defp floor_label(%{floor_id: floor_id, floor_name: name}, selected_floor_id) do
    if floor_id == selected_floor_id, do: "Here", else: name
  end

  defp normalize_event_points(points) when is_list(points) do
    Enum.map(points, fn
      %{"x" => x, "y" => y} ->
        %{"x" => to_float(x), "y" => to_float(y)}

      %{x: x, y: y} ->
        %{"x" => to_float(x), "y" => to_float(y)}

      other when is_map(other) ->
        %{
          "x" => to_float(Map.get(other, "x") || Map.get(other, :x)),
          "y" => to_float(Map.get(other, "y") || Map.get(other, :y))
        }
    end)
  end

  defp normalize_event_points(_), do: []

  defp parse_index(index) when is_integer(index), do: index

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {n, _} -> n
      :error -> -1
    end
  end

  defp parse_index(_), do: -1

  defp place_mode_for(socket, location_id) do
    floor = socket.assigns.selected_floor

    case Enum.find(floor.location_placements, &(&1.location_id == location_id)) do
      %{points: points} when is_list(points) and length(points) >= 3 ->
        {"extend", Jason.encode!(normalize_event_points(points))}

      _ ->
        {"new", "[]"}
    end
  end

  defp placement_edges(points) when is_list(points) and length(points) >= 2 do
    points
    |> Enum.chunk_every(2, 1, [hd(points)])
    |> Enum.map(fn [a, b] ->
      %{x1: point_x(a), y1: point_y(a), x2: point_x(b), y2: point_y(b)}
    end)
  end

  defp placement_edges(_), do: []

  defp point_x(point) when is_map(point) do
    to_float(Map.get(point, "x") || Map.get(point, :x))
  end

  defp point_y(point) when is_map(point) do
    to_float(Map.get(point, "y") || Map.get(point, :y))
  end

  defp placement_label_x(points), do: elem(FloorPlans.polygon_centroid(points), 0)
  defp placement_label_y(points), do: elem(FloorPlans.polygon_centroid(points), 1)

  defp floors_top_first(floors) when is_list(floors) do
    Enum.sort_by(floors, & &1.position, :desc)
  end

  defp floor_at_top?(%Floor{} = floor, floors) when is_list(floors) do
    Enum.all?(floors, &(&1.position <= floor.position))
  end

  defp floor_at_bottom?(%Floor{} = floor, floors) when is_list(floors) do
    Enum.all?(floors, &(&1.position >= floor.position))
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0
end
