defmodule PinventoryWeb.EditItemLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items
  alias Pinventory.Items.Item
  alias Pinventory.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="item-page" class="space-y-4" phx-hook=".UnsavedChanges">
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-xl font-semibold tracking-tight">{page_heading(@live_action)}</h1>
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            Back
          </.link>
        </div>

        <.form
          for={@form}
          id="item-form"
          class="space-y-4"
          phx-change="validate"
          phx-submit="save"
        >
          <div class="relative space-y-1">
            <.input
              type="text"
              field={@form[:name]}
              label="Name"
              placeholder="Item name..."
              autocomplete="off"
              phx-debounce="300"
              wrapperclass="mb-0"
            />

            <div
              :if={@live_action == :new and @suggestions != []}
              id="item-suggestions"
              class={[
                "absolute z-20 mt-1 w-full overflow-hidden rounded-xl border",
                "border-base-300 bg-base-100 shadow-lg"
              ]}
              role="listbox"
              aria-label="Matching items"
            >
              <button
                :for={suggestion <- @suggestions}
                type="button"
                id={"item-suggestion-#{suggestion.id}"}
                role="option"
                class={[
                  "flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm",
                  "transition-colors hover:bg-primary/10 focus:bg-primary/10 focus:outline-none"
                ]}
                phx-click="select_suggestion"
                phx-value-id={suggestion.id}
              >
                <span class="font-medium">{suggestion.name}</span>
                <span class="text-xs opacity-60">Open</span>
              </button>
            </div>
          </div>

          <div class="flex items-baseline justify-between gap-3">
            <h2 class="text-sm font-medium opacity-80">Locations</h2>
            <p id="item-total" class="text-sm tabular-nums opacity-70">
              Total: {total_quantity(@quantities)}
            </p>
          </div>

          <div
            :if={@locations == []}
            id="item-locations-empty"
            class="rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
          >
            No locations yet.
            <.link navigate={~p"/locations"} class="link link-primary">
              Add locations
            </.link>
          </div>

          <div :if={@locations != []} id="item-locations" class="flex flex-col gap-1">
            <div
              :for={location <- @locations}
              id={"location-row-#{location.id}"}
              class={[
                "rounded-xl border bg-base-100 p-2 transition-all",
                quantity_for(@quantities, location.id) > 0 &&
                  "border-primary/40 bg-primary/5",
                quantity_for(@quantities, location.id) == 0 &&
                  "border-base-300 hover:border-base-content/20"
              ]}
            >
              <div class="flex flex-row items-center gap-2">
                <div class="min-w-0 flex-1 truncate px-1 text-sm font-medium">
                  {location.name}
                </div>

                <div class="flex shrink-0 items-center gap-1">
                  <button
                    type="button"
                    id={"quantity-dec-#{location.id}"}
                    class="btn btn-sm btn-square btn-ghost"
                    phx-click="adjust"
                    phx-value-location-id={location.id}
                    phx-value-delta="-1"
                    disabled={quantity_for(@quantities, location.id) == 0}
                    aria-label={"Decrease #{location.name}"}
                  >
                    <.icon name="hero-minus" class="size-4" />
                  </button>

                  <input
                    type="number"
                    id={"quantity-#{location.id}"}
                    name={"quantities[#{location.id}]"}
                    value={quantity_for(@quantities, location.id)}
                    min="0"
                    step="1"
                    class="input input-sm w-20 text-center tabular-nums"
                  />

                  <button
                    type="button"
                    id={"quantity-inc-#{location.id}"}
                    class="btn btn-sm btn-square btn-ghost"
                    phx-click="adjust"
                    phx-value-location-id={location.id}
                    phx-value-delta="1"
                    aria-label={"Increase #{location.name}"}
                  >
                    <.icon name="hero-plus" class="size-4" />
                  </button>

                  <button
                    type="button"
                    id={"move-start-#{location.id}"}
                    class="btn btn-sm btn-ghost"
                    phx-click="start_move"
                    phx-value-location-id={location.id}
                    disabled={quantity_for(@quantities, location.id) == 0}
                  >
                    Move
                  </button>
                </div>
              </div>

              <div
                :if={@move_from == location.id}
                id={"move-panel-#{location.id}"}
                class="mt-2 flex flex-col gap-2 rounded-lg border border-dashed border-base-300 bg-base-200/50 p-2 sm:flex-row sm:items-end"
              >
                <div class="flex-1">
                  <label class="label py-0 text-xs" for={"move-to-#{location.id}"}>To</label>
                  <select
                    id={"move-to-#{location.id}"}
                    name="move_to"
                    class="select select-sm w-full"
                    phx-change="set_move_to"
                    phx-value-location-id={location.id}
                  >
                    <option value="">Select location...</option>
                    <option
                      :for={dest <- move_destinations(@locations, location.id)}
                      value={dest.id}
                      selected={@move_to == dest.id}
                    >
                      {dest.name}
                    </option>
                  </select>
                </div>

                <div class="w-full sm:w-24">
                  <label class="label py-0 text-xs" for={"move-amount-#{location.id}"}>
                    Amount
                  </label>
                  <input
                    type="number"
                    id={"move-amount-#{location.id}"}
                    name="move_amount"
                    value={@move_amount}
                    min="1"
                    max={quantity_for(@quantities, location.id)}
                    step="1"
                    class="input input-sm w-full tabular-nums"
                    phx-change="set_move_amount"
                    phx-value-location-id={location.id}
                  />
                </div>

                <div class="flex gap-1">
                  <button
                    type="button"
                    id={"move-confirm-#{location.id}"}
                    class="btn btn-sm btn-primary"
                    phx-click="confirm_move"
                    disabled={not can_confirm_move?(@move_to, @move_amount, @quantities, location.id)}
                  >
                    Confirm
                  </button>
                  <button
                    type="button"
                    id={"move-cancel-#{location.id}"}
                    class="btn btn-sm btn-ghost"
                    phx-click="cancel_move"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-2 pt-2">
            <.button
              type="submit"
              id="item-save"
              variant="primary"
              disabled={not @dirty?}
            >
              Save
            </.button>
          </div>
        </.form>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".UnsavedChanges">
        const MESSAGE = "You have unsaved changes. Leave this page?"

        export default {
          mounted() {
            this.dirty = false
            this.allowNext = false

            this.onBeforeUnload = (event) => {
              if (!this.dirty || this.allowNext) return
              event.preventDefault()
              event.returnValue = MESSAGE
            }

            this.onClick = (event) => {
              if (!this.dirty || this.allowNext) return
              if (event.defaultPrevented) return
              if (event.button !== 0) return
              if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

              const link = event.target.closest("a[href]")
              if (!link) return
              if (link.target === "_blank" || link.hasAttribute("download")) return
              if (!this.isLeavingPage(link)) return

              if (!window.confirm(MESSAGE)) {
                event.preventDefault()
                event.stopImmediatePropagation()
                return
              }

              this.allowNext = true
              this.dirty = false
            }

            window.addEventListener("beforeunload", this.onBeforeUnload)
            document.addEventListener("click", this.onClick, true)

            this.handleEvent("unsaved-changes", ({dirty}) => {
              this.dirty = !!dirty
              this.allowNext = false
            })
          },

          destroyed() {
            window.removeEventListener("beforeunload", this.onBeforeUnload)
            document.removeEventListener("click", this.onClick, true)
          },

          isLeavingPage(link) {
            const url = new URL(link.href, window.location.href)
            if (url.origin !== window.location.origin) return true

            return (
              url.pathname !== window.location.pathname ||
              url.search !== window.location.search
            )
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:suggestions, [])
     |> assign(:move_from, nil)
     |> assign(:move_to, nil)
     |> assign(:move_amount, 1)
     |> assign(:dirty?, false)
     |> assign(:unsaved?, false)}
  end

  @impl true
  def handle_params(%{"item_id" => item_id}, _uri, socket) do
    item = Items.get_item!(item_id)
    locations = Locations.list()
    quantities = draft_quantities(locations, Items.stock_map(item))

    socket =
      socket
      |> assign(:page_title, item.name)
      |> assign(:live_action, :edit)
      |> assign(:item, item)
      |> assign(:locations, locations)
      |> assign(:baseline_name, item.name)
      |> assign(:baseline_quantities, quantities)
      |> assign(:quantities, quantities)
      |> assign(:form, to_item_form(Items.change_item(item)))
      |> assign(:suggestions, [])
      |> clear_move()
      |> sync_unsaved()

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    item = %Item{}
    locations = Locations.list()
    quantities = draft_quantities(locations, %{})

    socket =
      socket
      |> assign(:page_title, "New item")
      |> assign(:live_action, :new)
      |> assign(:item, item)
      |> assign(:locations, locations)
      |> assign(:baseline_name, "")
      |> assign(:baseline_quantities, quantities)
      |> assign(:quantities, quantities)
      |> assign(:form, to_item_form(Items.change_item(item)))
      |> assign(:suggestions, [])
      |> clear_move()
      |> sync_unsaved()

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    name = get_in(params, ["item", "name"]) || ""
    quantities = merge_quantity_params(socket.assigns.quantities, params["quantities"])

    form =
      socket.assigns.item
      |> Items.change_item(%{"name" => name})
      |> Map.put(:action, :validate)
      |> to_item_form()

    suggestions = load_suggestions(socket.assigns.live_action, name)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:quantities, quantities)
     |> assign(:suggestions, suggestions)
     |> sync_unsaved()}
  end

  def handle_event("adjust", %{"location-id" => location_id, "delta" => delta}, socket) do
    delta = String.to_integer(delta)
    current = quantity_for(socket.assigns.quantities, location_id)
    quantities = Map.put(socket.assigns.quantities, location_id, max(current + delta, 0))

    socket =
      socket
      |> assign(:quantities, quantities)
      |> maybe_clear_move(location_id)
      |> sync_unsaved()

    {:noreply, socket}
  end

  def handle_event("start_move", %{"location-id" => location_id}, socket) do
    qty = quantity_for(socket.assigns.quantities, location_id)

    if qty > 0 do
      {:noreply,
       socket
       |> assign(:move_from, location_id)
       |> assign(:move_to, nil)
       |> assign(:move_amount, min(1, qty))}
    else
      {:noreply, put_flash(socket, :error, "No stock to move from this location")}
    end
  end

  def handle_event("cancel_move", _params, socket) do
    {:noreply, clear_move(socket)}
  end

  def handle_event("set_move_to", %{"location-id" => _from, "move_to" => to_id}, socket) do
    to_id = if to_id == "", do: nil, else: to_id
    {:noreply, assign(socket, :move_to, to_id)}
  end

  def handle_event("set_move_amount", params, socket) do
    amount =
      params
      |> Map.get("move_amount", "1")
      |> parse_non_neg_int()
      |> max(1)

    from_id = socket.assigns.move_from || params["location-id"]
    max_qty = quantity_for(socket.assigns.quantities, from_id)
    amount = min(amount, max(max_qty, 1))

    {:noreply, assign(socket, :move_amount, amount)}
  end

  def handle_event("confirm_move", _params, socket) do
    from_id = socket.assigns.move_from
    to_id = socket.assigns.move_to
    amount = socket.assigns.move_amount
    quantities = socket.assigns.quantities

    cond do
      from_id == nil or to_id == nil or from_id == to_id ->
        {:noreply, put_flash(socket, :error, "Choose a destination location")}

      amount < 1 or amount > quantity_for(quantities, from_id) ->
        {:noreply, put_flash(socket, :error, "Invalid move amount")}

      true ->
        quantities =
          quantities
          |> Map.update!(from_id, &(&1 - amount))
          |> Map.update!(to_id, &(&1 + amount))

        {:noreply,
         socket
         |> assign(:quantities, quantities)
         |> clear_move()
         |> sync_unsaved()}
    end
  end

  def handle_event("select_suggestion", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:dirty?, false)
     |> assign(:unsaved?, false)
     |> push_event("unsaved-changes", %{dirty: false})
     |> push_navigate(to: ~p"/item/#{id}")}
  end

  def handle_event("save", params, socket) do
    name = get_in(params, ["item", "name"]) || ""
    quantities = merge_quantity_params(socket.assigns.quantities, params["quantities"])
    attrs = %{"name" => name}

    result =
      case socket.assigns.live_action do
        :new -> Items.create_item(attrs, quantities)
        :edit -> Items.update_item(socket.assigns.item, attrs, quantities)
      end

    case result do
      {:ok, item} ->
        message = if socket.assigns.live_action == :new, do: "Item created", else: "Item saved"

        socket =
          socket
          |> assign(:dirty?, false)
          |> assign(:unsaved?, false)
          |> push_event("unsaved-changes", %{dirty: false})
          |> put_flash(:info, message)

        socket =
          if socket.assigns.live_action == :new do
            push_navigate(socket, to: ~p"/item/#{item.id}")
          else
            quantities = draft_quantities(socket.assigns.locations, Items.stock_map(item))

            socket
            |> assign(:item, item)
            |> assign(:baseline_name, item.name)
            |> assign(:baseline_quantities, quantities)
            |> assign(:quantities, quantities)
            |> assign(:form, to_item_form(Items.change_item(item)))
            |> assign(:suggestions, [])
            |> clear_move()
            |> sync_unsaved()
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_item_form(changeset, action: :validate))
         |> assign(:quantities, quantities)
         |> assign(:suggestions, load_suggestions(socket.assigns.live_action, name))
         |> sync_unsaved()}
    end
  end

  defp page_heading(:new), do: "New item"
  defp page_heading(:edit), do: "Edit item"

  defp to_item_form(changeset, opts \\ []) do
    to_form(changeset, Keyword.merge([as: :item, id: "item"], opts))
  end

  defp draft_quantities(locations, stock_map) do
    Map.new(locations, fn location ->
      {location.id, Map.get(stock_map, location.id, 0)}
    end)
  end

  defp merge_quantity_params(current, nil), do: current

  defp merge_quantity_params(current, raw) when is_map(raw) do
    Enum.reduce(raw, current, fn {location_id, value}, acc ->
      if Map.has_key?(acc, location_id) do
        Map.put(acc, location_id, parse_non_neg_int(value))
      else
        acc
      end
    end)
  end

  defp quantity_for(quantities, location_id) do
    Map.get(quantities, location_id, 0)
  end

  defp total_quantity(quantities) do
    quantities
    |> Map.values()
    |> Enum.sum()
  end

  defp load_suggestions(:new, name) do
    name = String.trim(name)

    if String.length(name) >= 2 do
      Items.suggest_items(name)
    else
      []
    end
  end

  defp load_suggestions(:edit, _name), do: []

  defp move_destinations(locations, from_id) do
    Enum.reject(locations, &(&1.id == from_id))
  end

  defp can_confirm_move?(to_id, amount, quantities, from_id) do
    to_id not in [nil, ""] and amount >= 1 and amount <= quantity_for(quantities, from_id)
  end

  defp clear_move(socket) do
    socket
    |> assign(:move_from, nil)
    |> assign(:move_to, nil)
    |> assign(:move_amount, 1)
  end

  defp maybe_clear_move(socket, location_id) do
    if socket.assigns.move_from == location_id and
         quantity_for(socket.assigns.quantities, location_id) == 0 do
      clear_move(socket)
    else
      socket
    end
  end

  defp parse_non_neg_int(value) when is_integer(value), do: max(value, 0)

  defp parse_non_neg_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> max(int, 0)
      :error -> 0
    end
  end

  defp parse_non_neg_int(_), do: 0

  defp sync_unsaved(socket) do
    name = current_name(socket)
    dirty? = name != socket.assigns.baseline_name or quantities_dirty?(socket)

    socket = assign(socket, :dirty?, dirty?)

    if socket.assigns.unsaved? == dirty? do
      socket
    else
      socket
      |> assign(:unsaved?, dirty?)
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

  defp quantities_dirty?(socket) do
    socket.assigns.quantities != socket.assigns.baseline_quantities
  end
end
