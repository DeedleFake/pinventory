defmodule PinventoryWeb.EditItemLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Audit
  alias Pinventory.Items
  alias Pinventory.Items.DraftStock
  alias Pinventory.Items.Item
  alias Pinventory.Locations

  import PinventoryWeb.AuditHelpers,
    only: [
      activity_event_line: 1,
      edit_heading: 1,
      format_event_time: 1,
      linkable_location_id: 1
    ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:items}>
      <div
        id="item-page"
        class="space-y-4"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h1 class="text-xl font-semibold tracking-tight">{page_heading(@live_action)}</h1>
          <div
            :if={@live_action == :edit}
            id="item-delete-actions"
            class="flex flex-wrap items-center justify-end gap-2"
          >
            <p :if={@delete_blocked_reason} id="item-delete-reason" class="text-sm opacity-70">
              {@delete_blocked_reason}
            </p>
            <button
              type="button"
              id="item-delete"
              class="btn btn-ghost text-error hover:bg-error/10"
              phx-click="open_delete"
              disabled={@delete_blocked_reason != nil}
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </button>
          </div>
        </div>

        <%!-- Name lives in its own form so stock Enter keys do not submit Save. --%>
        <.form
          for={@form}
          id="item-form"
          class="space-y-1"
          phx-change="validate"
          phx-submit="save"
        >
          <div
            id="item-name-section"
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
              placeholder="Item name..."
              autocomplete="off"
              phx-debounce="300"
              phx-focus="name_focus"
              phx-blur="name_blur"
              wrapperclass="mb-0"
            />

            <p
              :if={@name_dirty?}
              id="item-name-hint"
              class="text-xs text-primary"
            >
              Unsaved name change · was {@baseline_name}
            </p>

            <.suggestion_list
              :if={@live_action == :new and @suggestions != []}
              suggestions={@suggestions}
            />
          </div>
        </.form>

        <div class="space-y-4">
          <.stock_total
            mode={@stock_total_mode}
            current={@total_current}
            baseline={@total_baseline}
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
                dirty?={Map.get(@location_dirty, location.id, false)}
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
                <.activity_event_line
                  :for={event <- edit.events}
                  id={"item-event-#{event.id}"}
                  event={event}
                  href={item_activity_event_href(event)}
                />
              </ul>
            </article>
          </div>
        </section>

        <.item_delete_modal
          :if={@live_action == :edit and @delete_modal?}
          form={@delete_form}
          item_name={@item.name}
          total={@delete_total}
          location_count={@delete_location_count}
          confirm_ready?={@delete_confirm_ready?}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :mode, :atom, required: true
  attr :current, :integer, required: true
  attr :baseline, :integer, required: true

  # Presentation only: mode / totals come from sync_dirty/1.
  defp stock_total(assigns) do
    {chrome_class, accent_class, hint} =
      case assigns.mode do
        :clean ->
          {"border-base-300 bg-base-100 ring-transparent", nil, nil}

        :rebalance ->
          {"border-primary/50 bg-primary/10 ring-primary/25", "text-primary",
           "Unsaved · total unchanged"}

        :total_changed ->
          {"border-warning/50 bg-warning/10 ring-warning/25", "text-warning",
           "Unsaved · total changed"}
      end

    assigns =
      assigns
      |> assign(:chrome_class, chrome_class)
      |> assign(:accent_class, accent_class)
      |> assign(:hint, hint)

    ~H"""
    <%!-- Fixed min-height: dirty content fits without growing; clean content centers. --%>
    <div
      id="item-total"
      data-stock-dirty={to_string(@mode != :clean)}
      data-total-changed={to_string(@mode == :total_changed)}
      class={[
        "flex min-h-20 items-center justify-between gap-4 rounded-2xl border px-4 py-3",
        "ring-1 transition-colors duration-200",
        @chrome_class
      ]}
    >
      <div class="min-w-0">
        <p class="text-xs font-semibold tracking-wide uppercase opacity-60">
          Total quantity
        </p>
        <p
          :if={@hint}
          id="item-total-hint"
          class="mt-0.5 text-xs opacity-70"
        >
          {@hint}
        </p>
      </div>

      <div class="flex shrink-0 items-center gap-2 sm:gap-3">
        <div
          :if={@mode != :clean}
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
          :if={@mode != :clean}
          name="hero-arrow-right"
          class={"size-4 shrink-0 sm:size-5 #{@accent_class}"}
        />

        <div class="flex min-w-[1.75rem] flex-col items-center justify-center text-center leading-none">
          <span
            :if={@mode != :clean}
            class={["text-[0.65rem] font-medium uppercase tracking-wide", @accent_class]}
          >
            Now
          </span>
          <span
            id="item-total-value"
            class={[
              "text-3xl font-semibold tracking-tight tabular-nums sm:text-4xl",
              @accent_class
            ]}
          >
            {@current}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :item_name, :string, required: true
  attr :total, :integer, required: true
  attr :location_count, :integer, required: true
  attr :confirm_ready?, :boolean, required: true

  defp item_delete_modal(assigns) do
    ~H"""
    <div
      id="item-delete-modal"
      class="fixed inset-0 z-50 flex items-end justify-center bg-neutral/40 p-4 sm:items-center"
      phx-window-keydown="close_delete"
      phx-key="Escape"
    >
      <div
        id="item-delete-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="item-delete-title"
        class="w-full max-w-md rounded-2xl border border-base-300 bg-base-100 p-5 shadow-2xl sm:p-6"
        phx-click-away="close_delete"
      >
        <div class="space-y-1">
          <h2 id="item-delete-title" class="text-lg font-semibold tracking-tight">
            Delete item
          </h2>
          <p id="item-delete-impact" class="text-sm opacity-70">
            This will delete {@item_name}.
          </p>
          <p id="item-delete-impact-total" class="text-sm opacity-70">
            Total quantity: {@total}.
          </p>
          <p id="item-delete-impact-locations" class="text-sm opacity-70">
            Locations with stock: {@location_count}.
          </p>
        </div>

        <.form
          for={@form}
          id="item-delete-form"
          class="mt-4 space-y-4"
          phx-change="validate_delete"
          phx-submit="confirm_delete"
        >
          <.input
            type="text"
            field={@form[:name]}
            id="item-delete-confirm"
            label="Type the item name to confirm"
            placeholder={@item_name}
            autocomplete="off"
            spellcheck="false"
            phx-mounted={JS.focus()}
          />

          <div class="flex justify-end gap-2">
            <button
              type="button"
              id="item-delete-cancel"
              class="btn btn-ghost"
              phx-click="close_delete"
            >
              Cancel
            </button>
            <button
              type="submit"
              id="item-delete-confirm-submit"
              class="btn btn-error"
              disabled={not @confirm_ready?}
            >
              Delete
            </button>
          </div>
        </.form>
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
     |> assign(:name_dirty?, false)
     |> assign(:dirty?, false)
     |> assign(:stock_total_mode, :clean)
     |> assign(:total_current, 0)
     |> assign(:total_baseline, 0)
     |> assign(:location_dirty, %{})
     |> assign(:item_edits, [])
     |> assign(:delete_modal?, false)
     |> assign(:delete_form, delete_form(""))
     |> assign(:delete_confirm_ready?, false)
     |> assign(:delete_blocked_reason, nil)
     |> assign(:delete_total, 0)
     |> assign(:delete_location_count, 0)}
  end

  @impl true
  def handle_params(%{"item_id" => item_id}, _uri, socket) do
    case Items.get_item(item_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Item not found.")
         |> push_navigate(to: ~p"/")}

      item ->
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
          |> close_delete_modal()
          |> sync_dirty()

        {:noreply, socket}
    end
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
      |> close_delete_modal()
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

  def handle_event("open_delete", _params, socket) do
    {:noreply, open_delete_modal(socket)}
  end

  def handle_event("close_delete", _params, socket) do
    {:noreply, close_delete_modal(socket)}
  end

  def handle_event("validate_delete", params, socket) do
    {:noreply, assign_delete_form(socket, delete_name_from_params(params))}
  end

  def handle_event("confirm_delete", params, socket) do
    raw_name = delete_name_from_params(params)

    cond do
      socket.assigns.live_action != :edit ->
        {:noreply, socket}

      unsaved_name?(socket) ->
        {:noreply,
         socket
         |> close_delete_modal()
         |> put_flash(:error, "Save or revert the name first.")}

      not confirm_name_matches?(raw_name, saved_name(socket)) ->
        {:noreply, assign_delete_form(socket, raw_name)}

      true ->
        case Items.delete_item(socket.assigns.current_scope, socket.assigns.item) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign_dirty(false)
             |> put_flash(:info, "Item deleted")
             |> push_navigate(to: ~p"/")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete the item")}
        end
    end
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

  defp item_activity_event_href(event) do
    case linkable_location_id(event) do
      nil -> nil
      location_id -> ~p"/location/#{location_id}"
    end
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

  # Single owner of dirty / total-mode rules for name, stock, rows, and save.
  defp sync_dirty(socket) do
    name = current_name(socket)
    quantities = socket.assigns.quantities
    baseline_quantities = socket.assigns.baseline_quantities
    stock_dirty? = DraftStock.dirty?(quantities, baseline_quantities)
    total_current = DraftStock.total(quantities)
    total_baseline = DraftStock.total(baseline_quantities)

    # Only flag on edit: new items always start from an empty baseline name.
    name_dirty? = socket.assigns.live_action == :edit and name != socket.assigns.baseline_name

    stock_total_mode =
      cond do
        not stock_dirty? -> :clean
        total_current != total_baseline -> :total_changed
        true -> :rebalance
      end

    location_dirty =
      Map.new(quantities, fn {location_id, qty} ->
        {location_id, qty != DraftStock.get(baseline_quantities, location_id)}
      end)

    dirty? = name != socket.assigns.baseline_name or stock_dirty?

    socket
    |> assign(:name_dirty?, name_dirty?)
    |> assign(:stock_total_mode, stock_total_mode)
    |> assign(:total_current, total_current)
    |> assign(:total_baseline, total_baseline)
    |> assign(:location_dirty, location_dirty)
    |> assign(:delete_blocked_reason, item_delete_blocked_reason(name_dirty?))
    |> assign_dirty(dirty?)
  end

  defp item_delete_blocked_reason(true), do: "Save or revert the name first."
  defp item_delete_blocked_reason(false), do: nil

  defp open_delete_modal(socket) do
    cond do
      socket.assigns.live_action != :edit ->
        socket

      unsaved_name?(socket) ->
        socket

      true ->
        {total, location_count} = item_stock_summary(socket.assigns.item)

        socket
        |> assign(:delete_modal?, true)
        |> assign(:delete_total, total)
        |> assign(:delete_location_count, location_count)
        |> assign_delete_form("")
    end
  end

  defp close_delete_modal(socket) do
    socket
    |> assign(:delete_modal?, false)
    |> assign_delete_form("")
  end

  defp assign_delete_form(socket, raw_name) when is_binary(raw_name) do
    socket
    |> assign(:delete_form, delete_form(raw_name))
    |> assign(:delete_confirm_ready?, confirm_name_matches?(raw_name, saved_name(socket)))
  end

  defp delete_form(name) do
    to_form(%{"name" => name}, as: :delete)
  end

  defp delete_name_from_params(%{"delete" => %{"name" => name}}) when is_binary(name), do: name
  defp delete_name_from_params(_), do: ""

  defp confirm_name_matches?(typed, saved) when is_binary(typed) and is_binary(saved) do
    typed == saved or String.trim(typed) == String.trim(saved)
  end

  defp unsaved_name?(socket) do
    socket.assigns.live_action == :edit and current_name(socket) != saved_name(socket)
  end

  defp saved_name(%{assigns: %{item: %Item{name: name}}}) when is_binary(name), do: name
  defp saved_name(_), do: ""

  defp item_stock_summary(%Item{} = item) do
    stock = Items.stock_map(item)
    {stock |> Map.values() |> Enum.sum(), map_size(stock)}
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
