defmodule PinventoryWeb.FloorPlanLive do
  use PinventoryWeb, :live_view

  alias Pinventory.FloorPlans
  alias Pinventory.FloorPlans.Floor

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:locations}>
      <div id="floor-plan-page" class="space-y-4">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div class="space-y-1">
            <div class="flex items-center gap-2 text-sm opacity-60">
              <.link navigate={~p"/locations"} class="hover:opacity-100 hover:underline">
                Locations
              </.link>
              <.icon name="hero-chevron-right" class="size-3.5 opacity-50" />
              <span>Floor plan</span>
            </div>
            <h1 class="text-xl font-semibold tracking-tight">Floor plan</h1>
            <p class="text-sm opacity-60">
              Draw walls, add floors, and place locations on the plan.
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              id="floor-plan-delete"
              class="btn btn-ghost text-error hover:bg-error/10"
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

        <div id="floor-tabs" class="flex flex-wrap items-center gap-1.5">
          <button
            :for={floor <- @floors}
            type="button"
            id={"floor-tab-#{floor.id}"}
            phx-click="select_floor"
            phx-value-id={floor.id}
            class={[
              "btn btn-sm",
              floor.id == @selected_floor.id && "btn-primary",
              floor.id != @selected_floor.id && "btn-ghost border border-base-300"
            ]}
          >
            {floor.name}
          </button>
          <button
            type="button"
            id="floor-add"
            class="btn btn-sm btn-ghost border border-dashed border-base-300"
            phx-click="add_floor"
          >
            <.icon name="hero-plus" class="size-4" /> Floor
          </button>
        </div>

        <div
          id="floor-rename-row"
          class="flex flex-col gap-2 sm:flex-row sm:items-end"
        >
          <form
            id="floor-rename-form"
            phx-submit="rename_floor"
            class="flex min-w-0 flex-1 flex-col gap-1.5 sm:flex-row sm:items-center"
          >
            <label class="label py-0 text-xs uppercase tracking-wide opacity-50" for="floor-name">
              Floor name
            </label>
            <div class="join w-full sm:max-w-sm">
              <input
                type="text"
                id="floor-name"
                name="name"
                value={@selected_floor.name}
                autocomplete="off"
                class="input join-item input-sm min-w-0 grow"
              />
              <button type="submit" id="floor-rename-save" class="btn btn-sm btn-primary join-item">
                Rename
              </button>
            </div>
          </form>

          <button
            type="button"
            id="floor-remove"
            class="btn btn-sm btn-ghost text-error hover:bg-error/10"
            phx-click="remove_floor"
            disabled={length(@floors) <= 1}
          >
            <.icon name="hero-minus-circle" class="size-4" /> Remove floor
          </button>
        </div>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_16rem]">
          <div class="space-y-3">
            <div
              id="floor-plan-tools"
              class="flex flex-wrap items-center gap-2 rounded-xl border border-base-300 bg-base-100 p-2"
            >
              <span class="px-1 text-xs font-semibold uppercase tracking-wide opacity-50">
                Tool
              </span>
              <button
                type="button"
                id="tool-wall"
                phx-click="set_mode"
                phx-value-mode="wall"
                class={[
                  "btn btn-sm",
                  @mode == "wall" && "btn-primary",
                  @mode != "wall" && "btn-ghost"
                ]}
              >
                <.icon name="hero-pencil" class="size-4" /> Draw wall
              </button>
              <button
                type="button"
                id="tool-place"
                phx-click="set_mode"
                phx-value-mode="place"
                class={[
                  "btn btn-sm",
                  @mode == "place" && "btn-primary",
                  @mode != "place" && "btn-ghost"
                ]}
              >
                <.icon name="hero-map-pin" class="size-4" /> Place location
              </button>
              <button
                type="button"
                id="tool-select"
                phx-click="set_mode"
                phx-value-mode="select"
                class={[
                  "btn btn-sm",
                  @mode == "select" && "btn-primary",
                  @mode != "select" && "btn-ghost"
                ]}
              >
                <.icon name="hero-hand-raised" class="size-4" /> Move pin
              </button>

              <button
                :if={@mode == "wall" and @selected_floor.walls != []}
                type="button"
                id="wall-undo"
                class="btn btn-sm btn-ghost ml-auto"
                phx-click="undo_wall"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" /> Undo wall
              </button>
            </div>

            <div
              id="floor-plan-canvas"
              phx-hook="FloorPlanCanvas"
              data-mode={@mode}
              data-location-id={@placing_location_id || ""}
              class={[
                "relative overflow-hidden rounded-2xl border border-base-300 bg-base-200/40",
                "aspect-[4/3] touch-none select-none",
                @mode == "wall" && "cursor-crosshair",
                @mode == "place" && @placing_location_id && "cursor-cell",
                @mode == "place" && !@placing_location_id && "cursor-not-allowed",
                @mode == "select" && "cursor-grab"
              ]}
            >
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
                <line
                  :for={wall <- @selected_floor.walls}
                  x1={wall["x1"]}
                  y1={wall["y1"]}
                  x2={wall["x2"]}
                  y2={wall["y2"]}
                  stroke="currentColor"
                  stroke-width="0.014"
                  stroke-linecap="round"
                  class="opacity-80"
                />
                <g :for={placement <- @selected_floor.location_placements}>
                  <circle
                    data-pin-location-id={placement.location_id}
                    cx={placement.x}
                    cy={placement.y}
                    r="0.028"
                    class={[
                      "fill-primary stroke-base-100",
                      @selected_pin_id == placement.location_id && "opacity-100",
                      @selected_pin_id != placement.location_id && "opacity-90"
                    ]}
                    stroke-width="0.008"
                  />
                  <text
                    data-pin-label-id={placement.location_id}
                    x={placement.x}
                    y={max(0.04, placement.y - 0.035)}
                    text-anchor="middle"
                    font-size="0.045"
                    class="fill-base-content pointer-events-none"
                    style="paint-order: stroke; stroke: var(--color-base-100, #fff); stroke-width: 0.012px;"
                  >
                    {placement.location && placement.location.name}
                  </text>
                </g>
              </svg>

              <p
                :if={@selected_floor.walls == [] and @selected_floor.location_placements == []}
                class="pointer-events-none absolute inset-0 flex items-center justify-center p-6 text-center text-sm opacity-50"
              >
                <%= if @mode == "wall" do %>
                  Drag on the canvas to draw a wall.
                <% else %>
                  Choose a location on the right, then click the canvas to place it.
                <% end %>
              </p>
            </div>
          </div>

          <aside
            id="floor-plan-sidebar"
            class="space-y-3 rounded-2xl border border-base-300 bg-base-100 p-3"
          >
            <div class="space-y-1">
              <h2 class="text-sm font-semibold tracking-tight">Locations</h2>
              <p class="text-xs opacity-60">
                <%= if @mode == "place" do %>
                  Select one, then click the plan to drop a pin.
                <% else %>
                  Switch to Place location to add pins. Move pin to drag.
                <% end %>
              </p>
            </div>

            <div
              :if={@selected_pin_id}
              id="pin-actions"
              class="rounded-xl border border-base-300 bg-base-200/50 p-2 space-y-2"
            >
              <p class="text-xs opacity-70">Selected pin</p>
              <button
                type="button"
                id="pin-unplace"
                class="btn btn-sm btn-ghost w-full text-error hover:bg-error/10"
                phx-click="unplace_selected"
              >
                <.icon name="hero-x-mark" class="size-4" /> Remove from plan
              </button>
            </div>

            <ul id="placeable-locations" class="flex max-h-[28rem] flex-col gap-1 overflow-y-auto">
              <li
                :if={@locations == []}
                class="rounded-lg px-2 py-6 text-center text-sm opacity-50"
              >
                No locations yet. Add some on the Locations page.
              </li>
              <li :for={location <- @locations}>
                <button
                  type="button"
                  id={"place-location-#{location.id}"}
                  phx-click="select_location"
                  phx-value-id={location.id}
                  class={[
                    "flex w-full items-center gap-2 rounded-lg border px-2.5 py-2 text-left text-sm transition-colors",
                    @placing_location_id == location.id &&
                      "border-primary bg-primary/10 ring-1 ring-primary/30",
                    @placing_location_id != location.id &&
                      "border-transparent hover:border-base-300 hover:bg-base-200/60",
                    location_placed_on_floor?(location.id, @selected_floor) && "opacity-70"
                  ]}
                >
                  <span class="min-w-0 flex-1 truncate font-medium">{location.name}</span>
                  <span
                    :if={Map.has_key?(@placement_by_location, location.id)}
                    class="shrink-0 rounded-full bg-base-200 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide opacity-70"
                  >
                    {floor_label(@placement_by_location[location.id], @selected_floor.id)}
                  </span>
                </button>
              </li>
            </ul>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    case FloorPlans.get_floor_plan() do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No floor plan yet. Add one from Locations.")
         |> push_navigate(to: ~p"/locations")}

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
         |> assign(:selected_pin_id, nil)
         |> assign(:delete_plan?, false)
         |> assign_location_lists()}
    end
  end

  @impl true
  def handle_event("select_floor", %{"id" => id}, socket) do
    floor = Enum.find(socket.assigns.floors, &(&1.id == id)) || socket.assigns.selected_floor

    {:noreply,
     socket
     |> assign(:selected_floor, FloorPlans.get_floor!(floor.id))
     |> assign(:selected_pin_id, nil)}
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
         |> assign(:selected_pin_id, nil)
         |> put_flash(:info, "Floor added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add floor")}
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
         |> assign(:selected_floor, floor)
         |> put_flash(:info, "Floor renamed")}

      {:error, changeset} ->
        msg =
          case changeset.errors[:name] do
            {message, _} -> message
            _ -> "Could not rename floor"
          end

        {:noreply, put_flash(socket, :error, msg)}
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
         |> assign(:selected_pin_id, nil)
         |> assign_location_lists()
         |> put_flash(:info, "Floor removed")}

      {:error, :last_floor} ->
        {:noreply, put_flash(socket, :error, "Keep at least one floor")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove floor")}
    end
  end

  def handle_event("set_mode", %{"mode" => mode}, socket)
      when mode in ["wall", "place", "select"] do
    socket =
      socket
      |> assign(:mode, mode)
      |> then(fn s ->
        if mode != "place", do: assign(s, :placing_location_id, nil), else: s
      end)
      |> then(fn s ->
        if mode != "select", do: assign(s, :selected_pin_id, nil), else: s
      end)

    {:noreply, socket}
  end

  def handle_event("select_location", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:mode, "place")
     |> assign(:placing_location_id, id)
     |> assign(:selected_pin_id, nil)}
  end

  def handle_event("wall_drawn", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    wall = %{
      "x1" => to_float(x1),
      "y1" => to_float(y1),
      "x2" => to_float(x2),
      "y2" => to_float(y2)
    }

    case FloorPlans.add_wall(socket.assigns.selected_floor, wall) do
      {:ok, floor} ->
        {:noreply, refresh_selected_floor(socket, floor)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add wall")}
    end
  end

  def handle_event("undo_wall", _params, socket) do
    floor = socket.assigns.selected_floor
    index = length(floor.walls) - 1

    case FloorPlans.remove_wall(floor, index) do
      {:ok, updated} ->
        {:noreply, refresh_selected_floor(socket, updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "pin_placed",
        %{"location_id" => location_id, "x" => x, "y" => y},
        socket
      ) do
    place_pin(socket, location_id, x, y)
  end

  def handle_event(
        "pin_moved",
        %{"location_id" => location_id, "x" => x, "y" => y},
        socket
      ) do
    place_pin(socket, location_id, x, y)
  end

  def handle_event("pin_selected", %{"location_id" => location_id}, socket) do
    {:noreply,
     socket
     |> assign(:mode, "select")
     |> assign(:selected_pin_id, location_id)
     |> assign(:placing_location_id, nil)}
  end

  def handle_event("unplace_selected", _params, socket) do
    case socket.assigns.selected_pin_id do
      nil ->
        {:noreply, socket}

      location_id ->
        _ = FloorPlans.unplace_location(location_id)
        floor = FloorPlans.get_floor!(socket.assigns.selected_floor.id)

        {:noreply,
         socket
         |> refresh_selected_floor(floor)
         |> assign(:selected_pin_id, nil)
         |> assign_location_lists()
         |> put_flash(:info, "Location removed from plan")}
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
        {:noreply,
         socket
         |> put_flash(:info, "Floor plan deleted")
         |> push_navigate(to: ~p"/locations")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete floor plan")}
    end
  end

  defp place_pin(socket, location_id, x, y) do
    case FloorPlans.place_location(
           socket.assigns.selected_floor,
           location_id,
           to_float(x),
           to_float(y)
         ) do
      {:ok, _placement} ->
        floor = FloorPlans.get_floor!(socket.assigns.selected_floor.id)

        {:noreply,
         socket
         |> refresh_selected_floor(floor)
         |> assign(:selected_pin_id, location_id)
         |> assign_location_lists()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not place location")}
    end
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

  defp floor_label(%{floor_id: floor_id, floor_name: name}, selected_floor_id) do
    if floor_id == selected_floor_id, do: "Here", else: name
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
