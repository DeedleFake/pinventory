defmodule PinventoryWeb.EditItemLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Audit
  alias Pinventory.Items
  alias Pinventory.Items.DraftStock
  alias Pinventory.Items.Item
  alias Pinventory.Locations

  import PinventoryWeb.AuditHelpers, only: [edit_heading: 1, event_line: 1, format_event_time: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="item-page"
        class="space-y-4"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <h1 class="text-xl font-semibold tracking-tight">{page_heading(@live_action)}</h1>

        <%!-- Name lives in its own form so stock Enter keys do not submit Save. --%>
        <.form
          for={@form}
          id="item-form"
          class="space-y-1"
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
              phx-focus="name_focus"
              phx-blur="name_blur"
              wrapperclass="mb-0"
            />

            <.suggestion_list
              :if={@live_action == :new and @suggestions != []}
              suggestions={@suggestions}
            />
          </div>
        </.form>

        <div class="space-y-4">
          <.stock_total
            quantities={@quantities}
            baseline_quantities={@baseline_quantities}
          />

          <h2 class="text-sm font-medium opacity-80">Locations</h2>

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

          <%!-- Own form so LiveView input events work; separate from name/save form. --%>
          <form
            :if={@locations != []}
            id="item-stock-form"
            class="flex flex-col gap-1"
            phx-submit="stock_noop"
          >
            <div id="item-locations" class="flex flex-col gap-1">
              <.location_row
                :for={location <- @locations}
                location={location}
                quantity={DraftStock.get(@quantities, location.id)}
                dirty?={
                  DraftStock.get(@quantities, location.id) !=
                    DraftStock.get(@baseline_quantities, location.id)
                }
              />
            </div>
          </form>

          <div class="flex justify-end gap-2 pt-2">
            <.button
              type="submit"
              form="item-form"
              id="item-save"
              variant="primary"
              disabled={not @dirty?}
            >
              Save
            </.button>
          </div>
        </div>

        <section
          :if={@live_action == :edit}
          id="item-activity"
          class="space-y-3 border-t border-base-300 pt-6"
          aria-labelledby="item-activity-heading"
        >
          <div>
            <h2 id="item-activity-heading" class="text-sm font-medium opacity-80">Activity</h2>
            <p class="mt-0.5 text-xs opacity-60">History for this item</p>
          </div>

          <div
            :if={@item_edits == []}
            id="item-activity-empty"
            class="rounded-xl border border-base-300 px-3 py-6 text-center text-sm opacity-60"
          >
            No activity yet.
          </div>

          <div
            :if={@item_edits != []}
            id="item-activity-list"
            class="flex flex-col gap-1"
          >
            <article
              :for={edit <- @item_edits}
              id={"item-edit-#{edit.edit_id}"}
              class="rounded-xl border border-base-300 bg-base-100 p-4 space-y-2"
            >
              <div class="flex flex-wrap items-baseline justify-between gap-2">
                <p class="text-sm font-medium">{edit_heading(edit)}</p>
                <time
                  class="text-xs tabular-nums opacity-60"
                  datetime={DateTime.to_iso8601(edit.inserted_at)}
                >
                  {format_event_time(edit.inserted_at)}
                </time>
              </div>
              <ul class="space-y-1 border-t border-base-300/80 pt-2">
                <li
                  :for={event <- edit.events}
                  id={"item-event-#{event.id}"}
                  class="text-sm opacity-80"
                >
                  {event_line(event)}
                </li>
              </ul>
            </article>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :quantities, :map, required: true
  attr :baseline_quantities, :map, required: true

  defp stock_total(assigns) do
    current = DraftStock.total(assigns.quantities)
    baseline = DraftStock.total(assigns.baseline_quantities)
    stock_dirty? = DraftStock.dirty?(assigns.quantities, assigns.baseline_quantities)
    total_changed? = stock_dirty? and current != baseline

    assigns =
      assigns
      |> assign(:current, current)
      |> assign(:baseline, baseline)
      |> assign(:stock_dirty?, stock_dirty?)
      |> assign(:total_changed?, total_changed?)

    ~H"""
    <%!-- Fixed min-height: dirty content fits without growing; clean content centers. --%>
    <div
      id="item-total"
      data-stock-dirty={to_string(@stock_dirty?)}
      data-total-changed={to_string(@total_changed?)}
      class={[
        "flex min-h-20 items-center justify-between gap-4 rounded-2xl border px-4 py-3",
        "ring-1 transition-colors duration-200",
        @stock_dirty? && @total_changed? &&
          "border-warning/50 bg-warning/10 ring-warning/25",
        @stock_dirty? && not @total_changed? &&
          "border-primary/50 bg-primary/10 ring-primary/25",
        not @stock_dirty? && "border-base-300 bg-base-100 ring-transparent"
      ]}
    >
      <div class="min-w-0">
        <p class="text-xs font-semibold tracking-wide uppercase opacity-60">
          Total quantity
        </p>
        <p
          :if={@stock_dirty?}
          id="item-total-hint"
          class="mt-0.5 text-xs opacity-70"
        >
          <%= if @total_changed? do %>
            Unsaved · total changed
          <% else %>
            Unsaved · total unchanged
          <% end %>
        </p>
      </div>

      <div class="flex shrink-0 items-center gap-2 sm:gap-3">
        <div
          :if={@stock_dirty?}
          class="flex min-w-[1.75rem] flex-col items-center text-center leading-none"
        >
          <span class="text-[0.65rem] font-medium uppercase tracking-wide opacity-50">
            Was
          </span>
          <span
            id="item-total-was"
            class="text-lg font-medium tabular-nums opacity-50 line-through decoration-base-content/30"
          >
            {@baseline}
          </span>
        </div>

        <.icon
          :if={@stock_dirty?}
          name="hero-arrow-right"
          class={
            "size-4 shrink-0 sm:size-5 " <>
              if(@total_changed?, do: "text-warning", else: "text-primary")
          }
        />

        <div class="flex min-w-[1.75rem] flex-col items-center justify-center text-center leading-none">
          <span
            :if={@stock_dirty?}
            class={[
              "text-[0.65rem] font-medium uppercase tracking-wide",
              @total_changed? && "text-warning",
              not @total_changed? && "text-primary"
            ]}
          >
            Now
          </span>
          <span
            id="item-total-value"
            class={[
              "text-3xl font-semibold tracking-tight tabular-nums sm:text-4xl",
              @stock_dirty? && @total_changed? && "text-warning",
              @stock_dirty? && not @total_changed? && "text-primary"
            ]}
          >
            {@current}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :suggestions, :list, required: true

  defp suggestion_list(assigns) do
    ~H"""
    <div
      id="item-suggestions"
      class={[
        "absolute z-30 mt-1.5 w-full overflow-hidden rounded-xl",
        "border-2 border-primary/50 bg-base-100 shadow-2xl",
        "ring-4 ring-primary/15"
      ]}
      role="listbox"
      aria-label="Matching items"
    >
      <div class={[
        "flex items-center gap-2 border-b border-primary/20",
        "bg-primary/10 px-3 py-2 text-xs font-semibold tracking-wide",
        "text-primary uppercase"
      ]}>
        <.icon name="hero-magnifying-glass" class="size-3.5 shrink-0 opacity-80" />
        <span>Similar items already exist</span>
      </div>

      <div class="max-h-56 divide-y divide-base-300/80 overflow-y-auto">
        <button
          :for={suggestion <- @suggestions}
          type="button"
          id={"item-suggestion-#{suggestion.id}"}
          role="option"
          class={[
            "flex w-full items-center gap-3 px-3 py-2.5 text-left text-sm",
            "transition-colors hover:bg-primary/15 focus:bg-primary/15 focus:outline-none"
          ]}
          phx-click="select_suggestion"
          phx-value-id={suggestion.id}
        >
          <.icon name="hero-cube" class="size-4 shrink-0 text-primary/70" />
          <span class="min-w-0 flex-1 truncate font-medium">{suggestion.name}</span>
          <span class={[
            "inline-flex shrink-0 items-center gap-1 rounded-full",
            "bg-primary/15 px-2 py-0.5 text-xs font-medium text-primary"
          ]}>
            Open <.icon name="hero-arrow-right" class="size-3" />
          </span>
        </button>
      </div>
    </div>
    """
  end

  attr :location, :map, required: true
  attr :quantity, :integer, required: true
  attr :dirty?, :boolean, required: true

  defp location_row(assigns) do
    ~H"""
    <div
      id={"location-row-#{@location.id}"}
      data-dirty={to_string(@dirty?)}
      class={[
        "rounded-xl border bg-base-100 p-2 transition-all",
        @dirty? && "border-primary ring-1 ring-primary/30 bg-primary/5",
        (not @dirty? and @quantity > 0) && "border-primary/40 bg-primary/5",
        (not @dirty? and @quantity == 0) && "border-base-300 hover:border-base-content/20"
      ]}
    >
      <div class="flex flex-row items-center gap-2">
        <div class="min-w-0 flex-1 truncate px-1 text-sm font-medium">
          {@location.name}
        </div>

        <div class="flex shrink-0 items-center gap-1">
          <button
            type="button"
            id={"quantity-dec-#{@location.id}"}
            class="btn btn-sm btn-square btn-ghost"
            phx-click="adjust"
            phx-value-location-id={@location.id}
            phx-value-delta="-1"
            disabled={@quantity == 0}
            aria-label={"Decrease #{@location.name}"}
          >
            <.icon name="hero-minus" class="size-4" />
          </button>

          <input
            type="number"
            id={"quantity-#{@location.id}"}
            name={"quantities[#{@location.id}]"}
            value={@quantity}
            min="0"
            step="1"
            class="input input-sm no-spinner w-20 text-center tabular-nums"
            phx-change="set_quantity"
          />

          <button
            type="button"
            id={"quantity-inc-#{@location.id}"}
            class="btn btn-sm btn-square btn-ghost"
            phx-click="adjust"
            phx-value-location-id={@location.id}
            phx-value-delta="1"
            aria-label={"Increase #{@location.name}"}
          >
            <.icon name="hero-plus" class="size-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Delay hide so a click on a suggestion can run before the list is removed.
  @hide_suggestions_ms 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:suggestions, [])
     |> assign(:show_suggestions?, false)
     |> assign(:hide_suggestions_ref, nil)
     |> assign(:dirty?, false)
     |> assign(:item_edits, [])}
  end

  @impl true
  def handle_params(%{"item_id" => item_id}, _uri, socket) do
    item = Items.get_item!(item_id)
    locations = Locations.list()
    quantities = DraftStock.from_locations(locations, Items.stock_map(item))

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
      |> assign(:item_edits, Audit.list_edits_for_item(item.id))
      |> clear_suggestions()
      |> sync_dirty()

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    item = %Item{}
    locations = Locations.list()
    quantities = DraftStock.from_locations(locations)

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
      |> assign(:item_edits, [])
      |> clear_suggestions()
      |> sync_dirty()

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    name = get_in(params, ["item", "name"]) || ""

    form =
      socket.assigns.item
      |> Items.change_item(%{"name" => name})
      |> Map.put(:action, :validate)
      |> to_item_form()

    suggestions =
      if socket.assigns.show_suggestions? do
        load_suggestions(socket.assigns.live_action, name)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:suggestions, suggestions)
     |> sync_dirty()}
  end

  def handle_event("name_focus", _params, socket) do
    name = current_name(socket)

    {:noreply,
     socket
     |> cancel_hide_suggestions()
     |> assign(:show_suggestions?, true)
     |> assign(:suggestions, load_suggestions(socket.assigns.live_action, name))}
  end

  def handle_event("name_blur", _params, socket) do
    socket = cancel_hide_suggestions(socket)
    ref = Process.send_after(self(), :hide_name_suggestions, @hide_suggestions_ms)

    {:noreply, assign(socket, :hide_suggestions_ref, ref)}
  end

  def handle_event("set_quantity", params, socket) do
    case quantity_change_from_params(params) do
      {:ok, location_id, raw} ->
        quantity = DraftStock.parse_non_neg_int(raw)
        quantities = DraftStock.put(socket.assigns.quantities, location_id, quantity)

        {:noreply,
         socket
         |> assign(:quantities, quantities)
         |> sync_dirty()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("adjust", %{"location-id" => location_id, "delta" => delta}, socket) do
    case parse_adjust_delta(delta) do
      {:ok, delta} ->
        quantities = DraftStock.adjust(socket.assigns.quantities, location_id, delta)

        {:noreply,
         socket
         |> assign(:quantities, quantities)
         |> sync_dirty()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("select_suggestion", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> cancel_hide_suggestions()
     |> clear_suggestions()
     |> assign_dirty(false)
     |> push_navigate(to: ~p"/item/#{id}")}
  end

  # Stock form only exists so LiveView can serialize inputs; Enter must not navigate.
  def handle_event("stock_noop", _params, socket), do: {:noreply, socket}

  def handle_event("save", params, socket) do
    name = get_in(params, ["item", "name"]) || current_name(socket)
    quantities = socket.assigns.quantities
    attrs = %{"name" => name}
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.live_action do
        :new -> Items.create_item(scope, attrs, quantities)
        :edit -> Items.update_item(scope, socket.assigns.item, attrs, quantities)
      end

    case result do
      {:ok, item} ->
        message = if socket.assigns.live_action == :new, do: "Item created", else: "Item saved"

        socket =
          socket
          |> assign_dirty(false)
          |> put_flash(:info, message)

        socket =
          if socket.assigns.live_action == :new do
            push_navigate(socket, to: ~p"/item/#{item.id}")
          else
            quantities =
              DraftStock.from_locations(socket.assigns.locations, Items.stock_map(item))

            socket
            |> assign(:item, item)
            |> assign(:baseline_name, item.name)
            |> assign(:baseline_quantities, quantities)
            |> assign(:quantities, quantities)
            |> assign(:form, to_item_form(Items.change_item(item)))
            |> assign(:item_edits, Audit.list_edits_for_item(item.id))
            |> clear_suggestions()
            |> sync_dirty()
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{data: %Item{}} = changeset} ->
        suggestions =
          if socket.assigns.show_suggestions? do
            load_suggestions(socket.assigns.live_action, name)
          else
            []
          end

        {:noreply,
         socket
         |> assign(:form, to_item_form(changeset, action: :validate))
         |> assign(:suggestions, suggestions)
         |> sync_dirty()}

      {:error, %Ecto.Changeset{data: %Items.ItemLocation{}} = changeset} ->
        {:noreply, put_flash(socket, :error, stock_save_error_message(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save item stock")}
    end
  end

  @impl true
  def handle_info(:hide_name_suggestions, socket) do
    {:noreply, clear_suggestions(socket)}
  end

  defp page_heading(:new), do: "New item"
  defp page_heading(:edit), do: "Edit item"

  defp stock_save_error_message(%Ecto.Changeset{} = changeset) do
    case Keyword.get(changeset.errors, :location_id) do
      {msg, _opts} -> "Could not save item stock: location #{msg}"
      nil -> "Could not save item stock"
    end
  end

  defp to_item_form(changeset, opts \\ []) do
    to_form(changeset, Keyword.merge([as: :item, id: "item"], opts))
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

  defp clear_suggestions(socket) do
    socket
    |> cancel_hide_suggestions()
    |> assign(:show_suggestions?, false)
    |> assign(:suggestions, [])
  end

  defp cancel_hide_suggestions(socket) do
    if ref = socket.assigns[:hide_suggestions_ref] do
      Process.cancel_timer(ref)
    end

    assign(socket, :hide_suggestions_ref, nil)
  end

  defp parse_adjust_delta("1"), do: {:ok, 1}
  defp parse_adjust_delta("-1"), do: {:ok, -1}
  defp parse_adjust_delta(_), do: :error

  # Browser form change events send quantities[id] and _target, not phx-value-location-id.
  defp quantity_change_from_params(%{
         "_target" => ["quantities", location_id],
         "quantities" => quantities
       })
       when is_binary(location_id) and is_map(quantities) do
    {:ok, location_id, Map.get(quantities, location_id, "0")}
  end

  defp quantity_change_from_params(%{"location-id" => location_id} = params)
       when is_binary(location_id) do
    raw =
      get_in(params, ["quantities", location_id]) ||
        Map.get(params, "quantity") ||
        "0"

    {:ok, location_id, raw}
  end

  defp quantity_change_from_params(%{"quantities" => quantities}) when is_map(quantities) do
    case Map.to_list(quantities) do
      [{location_id, raw}] when is_binary(location_id) -> {:ok, location_id, raw}
      _ -> :error
    end
  end

  defp quantity_change_from_params(_), do: :error

  defp sync_dirty(socket) do
    name = current_name(socket)

    dirty? =
      name != socket.assigns.baseline_name or
        DraftStock.dirty?(socket.assigns.quantities, socket.assigns.baseline_quantities)

    assign_dirty(socket, dirty?)
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
end
