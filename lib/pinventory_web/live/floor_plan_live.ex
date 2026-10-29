defmodule PinventoryWeb.FloorPlanLive do
  use PinventoryWeb, :live_view

  alias Pinventory.FloorPlans
  alias Pinventory.FloorPlans.Floor
  alias Pinventory.Locations
  alias PinventoryWeb.VersionHistoryComponents

  import PinventoryWeb.FloorPlanComponents

  @resume_keys [
    :editing_floor_id,
    :removing_floor_id,
    :selected_placement_id,
    :placing_location_id
  ]

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

          <div :if={@floors != []} class="ml-auto flex flex-wrap items-center gap-1">
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
          :for={deletion <- @deletions}
          id={"deletion-#{deletion.id}"}
          class="flex flex-wrap items-center gap-3 rounded-xl border border-warning/40 bg-warning/10 px-4 py-3"
        >
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
          <p class="min-w-0 flex-1 text-sm">
            <span class="font-medium">{deleted_by(deletion.by)}</span> {deletion.text}.
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              id={"deletion-restore-#{deletion.id}"}
              class="btn btn-sm btn-primary"
              phx-click="restore_deleted"
              phx-value-id={deletion.id}
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
            </button>
            <button
              type="button"
              id={"deletion-dismiss-#{deletion.id}"}
              class="btn btn-sm btn-ghost"
              phx-click="dismiss_deleted"
              phx-value-id={deletion.id}
            >
              {if @floors == [] and deletion.id == "plan", do: "Leave", else: "Dismiss"}
            </button>
          </div>
        </div>

        <div
          :if={@floors != []}
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
                  id="tool-gap"
                  phx-click="set_mode"
                  phx-value-mode="gap"
                  class={[
                    "btn btn-sm justify-start",
                    @mode == "gap" && "btn-primary",
                    @mode != "gap" && "btn-ghost border border-base-300"
                  ]}
                >
                  <.icon name="hero-minus" class="size-4" /> Cut gap
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

            <section id="floor-plan-impassable-tools" class="space-y-2">
              <h2 class="text-xs font-semibold uppercase tracking-wide opacity-50">Impassable</h2>
              <div class="flex flex-col gap-1.5">
                <button
                  type="button"
                  id="tool-impassable"
                  phx-click="set_mode"
                  phx-value-mode="impassable"
                  class={[
                    "btn btn-sm justify-start",
                    @mode == "impassable" && "btn-primary",
                    @mode != "impassable" && "btn-ghost border border-base-300"
                  ]}
                >
                  <.icon name="hero-no-symbol" class="size-4" /> Draw area
                </button>
                <button
                  type="button"
                  id="tool-impassable-erase"
                  phx-click="set_mode"
                  phx-value-mode="impassable_erase"
                  class={[
                    "btn btn-sm justify-start",
                    @mode == "impassable_erase" && "btn-primary",
                    @mode != "impassable_erase" && "btn-ghost border border-base-300"
                  ]}
                >
                  <.icon name="hero-trash" class="size-4" /> Erase
                </button>
              </div>
            </section>

            <section id="floor-plan-location-tools" class="flex min-h-0 flex-1 flex-col gap-2">
              <h2 class="text-xs font-semibold uppercase tracking-wide opacity-50">Locations</h2>

              <ul
                id="placeable-locations"
                phx-hook="PlacementListHover"
                class="flex max-h-[min(32rem,55vh)] flex-col gap-1 overflow-y-auto lg:max-h-none lg:flex-1"
              >
                <li
                  :if={@locations == []}
                  class="rounded-lg px-2 py-6 text-center text-sm opacity-50"
                >
                  No locations yet. Add some on the Locations page.
                </li>
                <li
                  :for={location <- @locations}
                  data-location-id={to_string(location.id)}
                  class={[
                    "flex items-stretch overflow-hidden rounded-lg border",
                    @mode == "place" && @placing_location_id == location.id &&
                      "border-primary bg-primary/10 ring-1 ring-primary/30",
                    not (@mode == "place" && @placing_location_id == location.id) &&
                      "border-transparent hover:border-base-300 hover:bg-base-200/40"
                  ]}
                >
                  <button
                    :if={not Map.has_key?(@placement_by_location, location.id)}
                    type="button"
                    id={"place-location-#{location.id}"}
                    phx-click="select_location"
                    phx-value-id={location.id}
                    class="flex min-w-0 flex-1 items-center gap-2 px-2.5 py-2 text-left text-sm transition-colors"
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
                    class="flex min-w-0 flex-1 items-center gap-2 px-2.5 py-2 text-left text-sm opacity-70 transition-colors"
                  >
                    <span class="min-w-0 flex-1 truncate">{location.name}</span>
                    <span class="shrink-0 rounded-full bg-base-200 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide opacity-70">
                      {floor_label(@placement_by_location[location.id], @selected_floor.id)}
                    </span>
                  </button>
                  <div
                    :if={location_placed_on_floor?(location.id, @selected_floor)}
                    id={"place-location-#{location.id}"}
                    aria-disabled="true"
                    class="flex min-w-0 flex-1 cursor-not-allowed items-center gap-2 px-2.5 py-2 text-left text-sm"
                  >
                    <span class="min-w-0 flex-1 truncate font-medium">{location.name}</span>
                    <span class="shrink-0 rounded-full bg-primary/15 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-primary">
                      Here
                    </span>
                  </div>
                  <button
                    :if={location_placed_on_floor?(location.id, @selected_floor)}
                    type="button"
                    id={"unplace-location-#{location.id}"}
                    class="inline-flex w-10 shrink-0 items-center justify-center self-stretch border-l border-base-300 text-error transition-colors hover:bg-error/25 hover:text-error"
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

          <div
            id="floor-plan-canvas"
            data-feet-per-unit="40"
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
              (@mode == "wall" || @mode == "gap") && "cursor-crosshair",
              @mode == "impassable" && "cursor-cell",
              (@mode == "erase" || @mode == "impassable_erase") && "cursor-pointer",
              @mode == "place" && @placing_location_id && "cursor-cell",
              @mode == "place" && !@placing_location_id && "cursor-not-allowed"
            ]}
          >
            <div
              id="floor-plan-view-chrome"
              class="pointer-events-none absolute left-3 top-3 z-10 flex items-center gap-2"
            >
              <button
                type="button"
                id="floor-plan-zoom-reset"
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
              preserveAspectRatio="xMidYMid meet"
              class="h-full w-full bg-base-100 text-base-content"
            >
              <.impassable_hatch_defs id={"floor-impassable-hatch-#{@selected_floor.id}"} />

              <.impassable_area
                :for={area <- @selected_floor.impassable_areas}
                area={area}
                hatch_id={"floor-impassable-hatch-#{@selected_floor.id}"}
                show_snap?={true}
                erasable?={@mode == "impassable_erase"}
              />

              <g class={if(@mode == "impassable_erase", do: "pointer-events-none")}>
                <.placement_area
                  :for={placement <- @selected_floor.location_placements}
                  placement={placement}
                  selected?={@selected_placement_id == placement.location_id}
                  show_snap?={true}
                />
              </g>

              <%!-- Opacity on parent so overlapping round caps do not double-composite. --%>
              <g data-walls class="opacity-80">
                <g :for={wall <- @selected_floor.walls}>
                  <line
                    data-wall-seg
                    x1={wall.x1}
                    y1={wall.y1}
                    x2={wall.x2}
                    y2={wall.y2}
                    stroke="currentColor"
                    stroke-width="0.014"
                    stroke-linecap="round"
                    class="pointer-events-none"
                  />
                  <line
                    data-wall-id={wall.id}
                    x1={wall.x1}
                    y1={wall.y1}
                    x2={wall.x2}
                    y2={wall.y2}
                    stroke="transparent"
                    stroke-width="0.045"
                    stroke-linecap="round"
                    class={[
                      (@mode == "erase" || @mode == "gap") && "cursor-pointer",
                      @mode != "erase" && @mode != "gap" && "pointer-events-none"
                    ]}
                  />
                </g>
              </g>
            </svg>

            <p
              :if={
                @selected_floor.walls == [] and @selected_floor.location_placements == [] and
                  @selected_floor.impassable_areas == []
              }
              class="pointer-events-none absolute inset-0 flex items-center justify-center p-6 text-center text-sm opacity-50"
            >
              <%= cond do %>
                <% @mode == "wall" -> %>
                  Click once for the start, again for the end. Snap to walls and location corners. Escape cancels.
                <% @mode == "erase" -> %>
                  Click a wall segment to erase it.
                <% @mode == "impassable" -> %>
                  Click points to draw an impassable area. Close near the first point, double-click, or Done. Escape cancels.
                <% @mode == "impassable_erase" -> %>
                  Click an impassable area to erase it.
                <% @mode == "gap" -> %>
                  Click two points on a wall to cut a gap. Escape cancels.
                <% @mode == "place" && @placing_location_id && @place_mode == "extend" -> %>
                  Click a corner to attach, add points, then click a different corner to close, or Done to close on an adjacent edge. Escape cancels.
                <% @mode == "place" && @placing_location_id -> %>
                  Click points to draw an area. Close near the first point, double-click, or Done. Escape cancels.
                <% true -> %>
                  Choose a location in the sidebar, then click points to draw its area.
              <% end %>
            </p>
          </div>

          <aside
            id="floor-rail"
            class="flex w-full shrink-0 flex-col gap-2 rounded-2xl border border-base-300 bg-base-100 p-3 lg:w-80"
          >
            <div class="flex items-center justify-between gap-2 px-0.5">
              <h2 class="text-xs font-semibold uppercase tracking-wide opacity-50">Floors</h2>
              <button
                type="button"
                id="floor-add"
                class="btn btn-xs btn-ghost border border-dashed border-base-300"
                phx-click="add_floor"
                title="Add floor"
              >
                <.icon name="hero-plus" class="size-3.5" /> Floor
              </button>
            </div>

            <ul
              id="floor-rail-list"
              phx-hook="FloorRailSort"
              class="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto"
            >
              <li
                :for={floor <- FloorPlans.floors_top_first(@floors)}
                id={"floor-rail-item-#{floor.id}"}
                data-floor-id={floor.id}
                class={[
                  "rounded-lg border",
                  floor.id == @selected_floor.id && "border-primary bg-primary/10",
                  floor.id != @selected_floor.id && "border-transparent hover:border-base-300"
                ]}
              >
                <div
                  :if={@removing_floor_id == floor.id}
                  id={"floor-remove-confirm-#{floor.id}"}
                  class="space-y-2 p-2"
                >
                  <p class="text-xs leading-snug">
                    Delete <span class="font-semibold">{floor.name}</span>? Walls, locations, and impassable areas on this floor are removed.
                  </p>
                  <div class="flex flex-wrap gap-1">
                    <button
                      type="button"
                      id={"floor-remove-confirm-button-#{floor.id}"}
                      class="btn btn-xs btn-error"
                      phx-click="remove_floor"
                      phx-value-id={floor.id}
                    >
                      Delete
                    </button>
                    <button
                      type="button"
                      id={"floor-remove-cancel-#{floor.id}"}
                      class="btn btn-xs btn-ghost"
                      phx-click="cancel_remove_floor"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
                <div
                  :if={@removing_floor_id != floor.id}
                  class="flex items-stretch gap-0.5 px-0.5 py-0.5"
                >
                  <button
                    type="button"
                    id={"floor-drag-#{floor.id}"}
                    data-floor-handle
                    class="inline-flex w-7 shrink-0 cursor-grab touch-none items-center justify-center rounded-md opacity-50 hover:bg-base-200 hover:opacity-100 active:cursor-grabbing"
                    title="Drag to reorder"
                    aria-label={"Reorder #{floor.name}"}
                  >
                    <.icon name="hero-bars-2" class="size-4" />
                  </button>
                  <form
                    :if={@editing_floor_id == floor.id}
                    id={"floor-rename-form-#{floor.id}"}
                    phx-submit="rename_floor"
                    class="min-w-0 flex-1"
                  >
                    <input type="hidden" name="floor_id" value={floor.id} />
                    <label class="sr-only" for={"floor-name-#{floor.id}"}>Floor name</label>
                    <input
                      type="text"
                      id={"floor-name-#{floor.id}"}
                      name="name"
                      value={floor.name}
                      autocomplete="off"
                      phx-mounted={JS.focus()}
                      class={[
                        "input input-sm h-auto min-h-0 w-full min-w-0 border-0 bg-transparent px-1.5 py-2",
                        "text-sm font-medium shadow-none",
                        floor.id == @selected_floor.id && "text-primary",
                        "focus:border-0 focus:outline-none focus:ring-0"
                      ]}
                    />
                  </form>
                  <button
                    :if={@editing_floor_id != floor.id}
                    type="button"
                    id={"floor-tab-#{floor.id}"}
                    phx-click="select_floor"
                    phx-value-id={floor.id}
                    class={[
                      "min-w-0 flex-1 truncate rounded-md px-1.5 py-2 text-left text-sm font-medium",
                      floor.id == @selected_floor.id && "text-primary",
                      floor.id != @selected_floor.id && "opacity-80 hover:opacity-100"
                    ]}
                  >
                    {floor.name}
                  </button>
                  <button
                    :if={@editing_floor_id != floor.id}
                    type="button"
                    id={"floor-edit-#{floor.id}"}
                    class="inline-flex w-8 shrink-0 items-center justify-center self-stretch rounded-md opacity-60 transition-colors hover:bg-base-200 hover:opacity-100"
                    phx-click="edit_floor"
                    phx-value-id={floor.id}
                    title="Rename floor"
                    aria-label={"Rename #{floor.name}"}
                  >
                    <.icon name="hero-pencil" class="size-4" />
                  </button>
                  <button
                    :if={@editing_floor_id == floor.id}
                    type="submit"
                    form={"floor-rename-form-#{floor.id}"}
                    id={"floor-save-#{floor.id}"}
                    class="inline-flex w-8 shrink-0 items-center justify-center self-stretch rounded-md text-primary transition-colors hover:bg-primary/15"
                    title="Save name"
                    aria-label={"Save #{floor.name}"}
                  >
                    <.icon name="hero-check" class="size-4" />
                  </button>
                  <button
                    :if={@editing_floor_id == floor.id}
                    type="button"
                    id={"floor-edit-cancel-#{floor.id}"}
                    class="inline-flex w-8 shrink-0 items-center justify-center self-stretch rounded-md opacity-60 transition-colors hover:bg-base-200 hover:opacity-100"
                    phx-click="cancel_edit_floor"
                    phx-value-id={floor.id}
                    title="Cancel rename"
                    aria-label="Cancel rename"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                  <button
                    :if={@editing_floor_id != floor.id}
                    type="button"
                    id={"floor-remove-#{floor.id}"}
                    class={[
                      "inline-flex w-8 shrink-0 items-center justify-center self-stretch rounded-md text-error transition-colors",
                      length(@floors) <= 1 && "cursor-not-allowed opacity-30",
                      length(@floors) > 1 && "hover:bg-error/25 hover:text-error"
                    ]}
                    phx-click="prompt_remove_floor"
                    phx-value-id={floor.id}
                    disabled={length(@floors) <= 1}
                    title={
                      if(length(@floors) <= 1,
                        do: "Can't remove the last floor",
                        else: "Remove floor"
                      )
                    }
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
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
    case FloorPlans.list_floors() do
      [] ->
        {:ok, push_navigate(socket, to: ~p"/locations")}

      floors ->
        selected = List.first(floors)

        if connected?(socket) do
          FloorPlans.subscribe()
          Locations.subscribe()
        end

        {:ok,
         socket
         |> assign(:page_title, "Floor plan")
         |> assign(:floors, floors)
         |> assign(:selected_floor, selected)
         |> assign(:mode, "wall")
         |> assign(:placing_location_id, nil)
         |> assign(:place_mode, "new")
         |> assign(:existing_points_json, "[]")
         |> assign(:selected_placement_id, nil)
         |> assign(:delete_plan?, false)
         |> assign(:removing_floor_id, nil)
         |> assign(:editing_floor_id, nil)
         |> assign(:deletions, [])
         |> assign(:undo_stack, [])
         |> assign(:redo_stack, [])
         |> assign_location_lists()}
    end
  end

  @impl true
  def handle_params(%{"floor_id" => floor_id}, _uri, socket) do
    case Enum.find(socket.assigns.floors, &(&1.id == floor_id)) do
      nil ->
        first = List.first(socket.assigns.floors)
        {:noreply, fallback_to_floor(socket, first.id)}

      floor ->
        {:noreply, apply_selected_floor(socket, floor)}
    end
  end

  def handle_params(_params, _uri, socket) do
    floor = socket.assigns.selected_floor || List.first(socket.assigns.floors)
    {:noreply, fallback_to_floor(socket, floor.id)}
  end

  @impl true
  def handle_event("select_floor", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.floors, &(&1.id == id)) do
      {:noreply, push_patch(socket, to: floor_plan_path(id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_floor", _params, socket) do
    socket = push_undo_snapshot(socket)

    case FloorPlans.add_floor() do
      {:ok, floor} ->
        floors = FloorPlans.list_floors()

        {:noreply,
         socket
         |> assign(:floors, floors)
         |> assign(:selected_placement_id, nil)
         |> assign(:removing_floor_id, nil)
         |> assign(:editing_floor_id, nil)
         |> push_patch(to: floor_plan_path(floor.id))}

      {:error, _} ->
        {:noreply, pop_failed_undo(socket)}
    end
  end

  def handle_event("edit_floor", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.floors, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:editing_floor_id, id)
       |> assign(:removing_floor_id, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_floor", %{"id" => id}, socket) do
    if socket.assigns.editing_floor_id == id do
      {:noreply, assign(socket, :editing_floor_id, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("rename_floor", %{"floor_id" => id, "name" => name}, socket) do
    floor = Enum.find(socket.assigns.floors, &(&1.id == id))

    if floor do
      case FloorPlans.rename_floor(floor, name) do
        {:ok, floor} ->
          floors = FloorPlans.list_floors()
          selected = Enum.find(floors, &(&1.id == socket.assigns.selected_floor.id)) || floor

          {:noreply,
           socket
           |> assign(:floors, floors)
           |> assign(:selected_floor, selected)
           |> assign(:editing_floor_id, nil)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :editing_floor_id, nil)}
    end
  end

  def handle_event("reorder_floors", %{"floor_ids" => floor_ids}, socket)
      when is_list(floor_ids) do
    socket = push_undo_snapshot(socket)

    case FloorPlans.reorder_floors(floor_ids) do
      {:ok, floors} ->
        selected_id = socket.assigns.selected_floor.id
        selected = Enum.find(floors, &(&1.id == selected_id)) || List.first(floors)

        {:noreply,
         socket
         |> assign(:floors, floors)
         |> assign(:selected_floor, FloorPlans.get_floor!(selected.id))
         |> assign(:removing_floor_id, nil)}

      {:error, _} ->
        {:noreply, pop_failed_undo(socket)}
    end
  end

  def handle_event("prompt_remove_floor", %{"id" => id}, socket) do
    if length(socket.assigns.floors) <= 1 do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :removing_floor_id, id)}
    end
  end

  def handle_event("cancel_remove_floor", _params, socket) do
    {:noreply, assign(socket, :removing_floor_id, nil)}
  end

  def handle_event("remove_floor", %{"id" => id}, socket) do
    floor = Enum.find(socket.assigns.floors, &(&1.id == id))

    cond do
      is_nil(floor) ->
        {:noreply, assign(socket, :removing_floor_id, nil)}

      length(socket.assigns.floors) <= 1 ->
        {:noreply, assign(socket, :removing_floor_id, nil)}

      true ->
        socket = push_undo_snapshot(socket)

        case FloorPlans.delete_floor(socket.assigns.current_scope, floor) do
          {:ok, _} ->
            floors = FloorPlans.list_floors()

            selected =
              Enum.find(floors, &(&1.id == socket.assigns.selected_floor.id)) ||
                List.first(floors)

            {:noreply,
             socket
             |> assign(:floors, floors)
             |> assign(:selected_placement_id, nil)
             |> assign(:removing_floor_id, nil)
             |> assign_location_lists()
             |> push_patch(to: floor_plan_path(selected.id))}

          {:error, :last_floor} ->
            {:noreply, pop_failed_undo(socket) |> assign(:removing_floor_id, nil)}

          {:error, _} ->
            {:noreply, pop_failed_undo(socket) |> assign(:removing_floor_id, nil)}
        end
    end
  end

  def handle_event("set_mode", %{"mode" => mode}, socket)
      when mode in ["wall", "erase", "gap", "impassable", "impassable_erase"] do
    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:placing_location_id, nil)
     |> assign(:place_mode, "new")
     |> assign(:existing_points_json, "[]")}
  end

  def handle_event("select_location", %{"id" => id}, socket) do
    {:noreply, start_placing(socket, id)}
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

  def handle_event("wall_erased", %{"id" => wall_id}, socket) when is_binary(wall_id) do
    floor = socket.assigns.selected_floor
    socket = push_undo_snapshot(socket)

    case FloorPlans.remove_wall(floor, wall_id) do
      {:ok, updated} ->
        {:noreply, refresh_selected_floor(socket, updated)}

      {:error, _} ->
        {:noreply, pop_failed_undo(socket)}
    end
  end

  def handle_event(
        "wall_gapped",
        %{"id" => wall_id, "ax" => ax, "ay" => ay, "bx" => bx, "by" => by},
        socket
      )
      when is_binary(wall_id) do
    floor = socket.assigns.selected_floor
    point_a = {to_float(ax), to_float(ay)}
    point_b = {to_float(bx), to_float(by)}

    case FloorPlans.cut_wall_gap(floor, wall_id, point_a, point_b) do
      {:ok, updated} ->
        socket =
          if walls_unchanged?(floor, updated) do
            socket
          else
            push_undo_snapshot(socket)
          end

        {:noreply, refresh_selected_floor(socket, updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("polygon_placed", %{"location_id" => location_id, "points" => points}, socket) do
    place_polygon(socket, location_id, points)
  end

  def handle_event("impassable_placed", %{"points" => points}, socket) do
    normalized = normalize_event_points(points)

    if length(normalized) < 3 do
      {:noreply, socket}
    else
      socket = push_undo_snapshot(socket)

      case FloorPlans.add_impassable_area(socket.assigns.selected_floor, normalized) do
        {:ok, floor} ->
          {:noreply, refresh_selected_floor(socket, floor)}

        {:error, _} ->
          {:noreply, pop_failed_undo(socket)}
      end
    end
  end

  def handle_event("impassable_erased", %{"id" => area_id}, socket) when is_binary(area_id) do
    floor = socket.assigns.selected_floor
    socket = push_undo_snapshot(socket)

    case FloorPlans.remove_impassable_area(floor, area_id) do
      {:ok, updated} ->
        {:noreply, refresh_selected_floor(socket, updated)}

      {:error, _} ->
        {:noreply, pop_failed_undo(socket)}
    end
  end

  def handle_event("unplace_location", %{"id" => location_id}, socket) do
    socket = push_undo_snapshot(socket)
    _ = FloorPlans.unplace_location(socket.assigns.current_scope, location_id)
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

        case FloorPlans.restore_plan_geometry(socket.assigns.current_scope, entry.snapshot) do
          {:ok, floors} ->
            {:noreply,
             socket
             |> assign(:floors, floors)
             |> assign(:undo_stack, rest)
             |> assign(:redo_stack, trim_stack([current | socket.assigns.redo_stack]))
             |> select_history_floor(floors, entry.floor_id)
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

        case FloorPlans.restore_plan_geometry(socket.assigns.current_scope, entry.snapshot) do
          {:ok, floors} ->
            {:noreply,
             socket
             |> assign(:floors, floors)
             |> assign(:redo_stack, rest)
             |> assign(:undo_stack, trim_stack([current | socket.assigns.undo_stack]))
             |> select_history_floor(floors, entry.floor_id)
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

  def handle_event("restore_deleted", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.deletions, &(&1.id == id)) do
      nil -> {:noreply, socket}
      deletion -> {:noreply, restore_deleted(socket, deletion)}
    end
  end

  def handle_event("dismiss_deleted", %{"id" => id}, socket) do
    if socket.assigns.floors == [] and id == "plan" do
      {:noreply, push_navigate(socket, to: ~p"/locations")}
    else
      {:noreply, drop_deletion(socket, id)}
    end
  end

  def handle_event("confirm_delete_plan", _params, socket) do
    case FloorPlans.delete_floor_plan(socket.assigns.current_scope) do
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
      snapshot: FloorPlans.plan_geometry_snapshot(socket.assigns.floors)
    }
  end

  defp select_history_floor(socket, floors, floor_id) do
    selected =
      Enum.find(floors, &(&1.id == floor_id)) ||
        Enum.find(floors, &(&1.id == socket.assigns.selected_floor.id)) ||
        List.first(floors)

    socket
    |> assign(:selected_floor, FloorPlans.get_floor!(selected.id))
    |> assign(:selected_placement_id, nil)
    |> assign(:removing_floor_id, nil)
    |> push_patch(to: floor_plan_path(selected.id))
  end

  defp fallback_to_floor(socket, floor_id) do
    floor =
      Enum.find(socket.assigns.floors, &(&1.id == floor_id)) || List.first(socket.assigns.floors)

    socket = apply_selected_floor(socket, floor)

    # Defer the patch so mount-time handle_params does not live_redirect.
    if connected?(socket) do
      send(self(), {:patch_floor_url, floor.id})
    end

    socket
  end

  @impl true
  def handle_info({:patch_floor_url, floor_id}, socket) do
    {:noreply, push_patch(socket, to: floor_plan_path(floor_id))}
  end

  def handle_info({change, by}, socket)
      when change in [:floor_plan_changed, :locations_changed] do
    {:noreply, apply_remote_change(socket, by)}
  end

  # Someone else wrote to the plan or its locations. Reload what the page shows,
  # offer to restore anything this viewer was using that they deleted, then
  # drop any in-progress action whose target is gone.
  defp apply_remote_change(socket, by) do
    before = socket.assigns
    floors = FloorPlans.list_floors()
    socket = socket |> assign(:floors, floors) |> assign_location_lists()

    socket
    |> track_deletions(deleted_in_use(before, socket.assigns, by))
    |> follow_selected_floor(floors)
    |> drop_stale_history(before.floors, floors)
    |> drop_stale_actions(floors)
  end

  defp follow_selected_floor(socket, []), do: socket

  defp follow_selected_floor(socket, floors) do
    case Enum.find(floors, &(&1.id == socket.assigns.selected_floor.id)) do
      nil ->
        first = List.first(floors)

        socket
        |> apply_selected_floor(first)
        |> push_patch(to: floor_plan_path(first.id))

      floor ->
        assign(socket, :selected_floor, floor)
    end
  end

  # A deletion is something this viewer was using that someone else deleted:
  # the plan, a floor they were on, renaming, or about to delete, or a location
  # they were drawing or had selected. It holds what `restore_deleted/2` needs
  # to put it back and the page state to return to afterwards.
  defp deleted_in_use(%{floors: []}, _now, _by), do: []

  defp deleted_in_use(before, %{floors: []}, by) do
    [
      %{
        id: "plan",
        text: "deleted the floor plan",
        by: by,
        restore: %{
          floors: FloorPlans.plan_geometry_snapshot(before.floors),
          placements: [],
          location: nil
        },
        resume: Map.take(before, @resume_keys) |> Map.put(:floor_id, before.selected_floor.id)
      }
    ]
  end

  defp deleted_in_use(before, now, by) do
    floor_ids = MapSet.new(now.floors, & &1.id)

    deleted_floors =
      for floor <- before.floors,
          not MapSet.member?(floor_ids, floor.id),
          floor.id in [
            before.selected_floor.id,
            before.editing_floor_id,
            before.removing_floor_id
          ] do
        %{
          id: floor.id,
          text: "deleted #{floor.name}",
          by: by,
          restore: %{
            floors: FloorPlans.plan_geometry_snapshot([floor]),
            placements: [],
            location: nil
          },
          resume: %{
            floor_id: if(before.selected_floor.id == floor.id, do: floor.id),
            editing_floor_id: if(before.editing_floor_id == floor.id, do: floor.id),
            removing_floor_id: if(before.removing_floor_id == floor.id, do: floor.id)
          }
        }
      end

    deleted_locations =
      [before.selected_placement_id, before.placing_location_id]
      |> Enum.uniq()
      |> Enum.flat_map(&List.wrap(deleted_location(&1, before, now, floor_ids, by)))

    deleted_floors ++ deleted_locations
  end

  defp deleted_location(nil, _before, _now, _floor_ids, _by), do: nil

  defp deleted_location(id, before, now, floor_ids, by) do
    location = Enum.find(before.locations, &(&1.id == id))
    placement = restorable_placement(before.placement_by_location[id], floor_ids)
    gone? = location != nil and not Enum.any?(now.locations, &(&1.id == id))
    unplaced? = placement != nil and not Map.has_key?(now.placement_by_location, id)

    if gone? or unplaced? do
      %{
        id: id,
        text:
          if(gone?,
            do: "deleted #{location.name}",
            else: "removed #{location.name} from the floor plan"
          ),
        by: by,
        restore: %{
          floors: [],
          placements: List.wrap(placement && Map.put(placement, :location_id, id)),
          location: if(gone?, do: location)
        },
        resume: %{
          selected_placement_id: if(before.selected_placement_id == id, do: id),
          placing_location_id: if(before.placing_location_id == id, do: id)
        }
      }
    end
  end

  # A placement on a floor that was itself deleted comes back with that floor.
  defp restorable_placement(%{floor_id: floor_id, points: points}, floor_ids) do
    if MapSet.member?(floor_ids, floor_id), do: %{floor_id: floor_id, points: points}
  end

  defp restorable_placement(nil, _floor_ids), do: nil

  # Newest first. Drops deletions someone else has already restored.
  defp track_deletions(socket, new) do
    new_ids = MapSet.new(new, & &1.id)
    kept = Enum.reject(socket.assigns.deletions, &MapSet.member?(new_ids, &1.id))

    assign(socket, :deletions, Enum.filter(new ++ kept, &still_deleted?(&1, socket.assigns)))
  end

  defp still_deleted?(%{restore: restore}, assigns) do
    floor_ids = MapSet.new(assigns.floors, & &1.id)

    Enum.all?(restore.floors, &(not MapSet.member?(floor_ids, &1.id))) and
      Enum.all?(
        restore.placements,
        &(not Map.has_key?(assigns.placement_by_location, &1.location_id))
      ) and
      (restore.location == nil or
         not Enum.any?(assigns.locations, &(&1.id == restore.location.id)))
  end

  defp drop_deletion(socket, id) do
    assign(socket, :deletions, Enum.reject(socket.assigns.deletions, &(&1.id == id)))
  end

  defp restore_deleted(socket, %{restore: restore} = deletion) do
    scope = socket.assigns.current_scope

    with {:ok, _} <- restore_location(scope, restore.location),
         {:ok, skipped} <-
           FloorPlans.restore_deleted(scope, Map.take(restore, [:floors, :placements])) do
      socket
      |> assign(:floors, FloorPlans.list_floors())
      |> assign_location_lists()
      |> drop_deletion(deletion.id)
      |> resume(deletion.resume)
      |> put_skipped_flash(skipped)
    else
      {:error, %Ecto.Changeset{}} ->
        put_flash(
          socket,
          :error,
          "#{restore.location.name} can't be restored because another location now has that name."
        )

      {:error, _} ->
        put_flash(socket, :error, "That couldn't be restored. Try again.")
    end
  end

  defp restore_location(_scope, nil), do: {:ok, nil}
  defp restore_location(scope, location), do: Locations.restore(scope, location)

  # A lone location restored while there is no plan has nowhere to go back to.
  defp resume(%{assigns: %{floors: []}} = socket, _resume), do: socket

  defp resume(socket, resume) do
    floors = socket.assigns.floors

    floor =
      Enum.find(floors, &(&1.id == resume[:floor_id])) ||
        Enum.find(floors, &(&1.id == socket.assigns.selected_floor.id)) ||
        List.first(floors)

    socket =
      socket
      |> apply_selected_floor(floor)
      |> assign(Map.take(resume, [:editing_floor_id, :removing_floor_id, :selected_placement_id]))
      |> push_patch(to: floor_plan_path(floor.id))

    case resume[:placing_location_id] do
      nil -> socket
      id -> start_placing(socket, id)
    end
  end

  defp put_skipped_flash(socket, []), do: socket

  defp put_skipped_flash(socket, skipped) do
    put_flash(
      socket,
      :info,
      "Restored, except #{length(skipped)} location #{if length(skipped) == 1, do: "area", else: "areas"} that someone placed again or deleted since."
    )
  end

  defp deleted_by(nil), do: "Someone"
  defp deleted_by(by), do: VersionHistoryComponents.author(by)

  defp start_placing(socket, id) do
    if Map.has_key?(socket.assigns.placement_by_location, id) do
      socket
    else
      {place_mode, points_json} = place_mode_for(socket, id)

      socket
      |> assign(:mode, "place")
      |> assign(:placing_location_id, id)
      |> assign(:place_mode, place_mode)
      |> assign(:existing_points_json, points_json)
      |> assign(:selected_placement_id, id)
    end
  end

  # Undo restores a whole-plan snapshot, so replaying one now would erase the
  # other person's change. Location renames leave the snapshot alone.
  defp drop_stale_history(socket, previous_floors, floors) do
    history? = socket.assigns.undo_stack != [] or socket.assigns.redo_stack != []

    if history? and
         FloorPlans.plan_geometry_snapshot(previous_floors) !=
           FloorPlans.plan_geometry_snapshot(floors) do
      socket
      |> assign(:undo_stack, [])
      |> assign(:redo_stack, [])
      |> put_flash(:info, "Someone else changed the floor plan, so undo history was cleared.")
    else
      socket
    end
  end

  defp drop_stale_actions(socket, floors) do
    floor_ids = MapSet.new(floors, & &1.id)
    keep_floor = fn id -> if MapSet.member?(floor_ids, id), do: id end
    placing = socket.assigns.placing_location_id

    placed? = placing != nil and Map.has_key?(socket.assigns.placement_by_location, placing)
    deleted? = placing != nil and not Enum.any?(socket.assigns.locations, &(&1.id == placing))

    socket =
      socket
      |> assign(:editing_floor_id, keep_floor.(socket.assigns.editing_floor_id))
      |> assign(
        :removing_floor_id,
        if(length(floors) > 1, do: keep_floor.(socket.assigns.removing_floor_id))
      )

    socket =
      if placed? or deleted? do
        socket
        |> assign(:placing_location_id, nil)
        |> assign(:place_mode, "new")
        |> assign(:existing_points_json, "[]")
      else
        socket
      end

    socket =
      if Map.has_key?(socket.assigns.placement_by_location, socket.assigns.selected_placement_id),
        do: socket,
        else: assign(socket, :selected_placement_id, nil)

    if placed? and not deleted?,
      do: put_flash(socket, :info, "Someone else placed the location you were drawing."),
      else: socket
  end

  defp apply_selected_floor(socket, floor) do
    changed? = socket.assigns.selected_floor.id != floor.id

    socket = assign(socket, :selected_floor, FloorPlans.get_floor!(floor.id))

    if changed? do
      socket
      |> assign(:selected_placement_id, nil)
      |> assign(:removing_floor_id, nil)
      |> assign(:editing_floor_id, nil)
    else
      socket
    end
  end

  defp floor_plan_path(floor_id), do: ~p"/locations/floor-plan/#{floor_id}"

  defp pop_failed_undo(socket) do
    case socket.assigns.undo_stack do
      [_ | rest] -> assign(socket, :undo_stack, rest)
      [] -> socket
    end
  end

  defp trim_stack(stack) do
    Enum.take(stack, FloorPlans.undo_limit())
  end

  defp walls_unchanged?(%Floor{walls: before}, %Floor{walls: afterw}) do
    to_set = fn walls ->
      MapSet.new(Enum.map(walls, &{&1.id, &1.x1, &1.y1, &1.x2, &1.y2}))
    end

    to_set.(before) == to_set.(afterw)
  end

  defp refresh_selected_floor(socket, %Floor{} = floor) do
    floors = FloorPlans.list_floors()

    socket
    |> assign(:floors, floors)
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

  defp place_mode_for(socket, location_id) do
    floor = socket.assigns.selected_floor

    case Enum.find(floor.location_placements, &(&1.location_id == location_id)) do
      %{points: points} when is_list(points) and length(points) >= 3 ->
        {"extend", Jason.encode!(normalize_event_points(points))}

      _ ->
        {"new", "[]"}
    end
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
