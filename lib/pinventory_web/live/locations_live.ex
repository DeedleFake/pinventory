defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="locations-page" class="space-y-4" phx-hook=".UnsavedChanges">
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-xl font-semibold tracking-tight">Locations</h1>
        </div>

        <.form
          for={@new_form}
          id="location-new-form"
          class={[
            "flex flex-row items-start gap-2 rounded-xl border border-dashed",
            "border-base-300 bg-base-200/50 p-2 transition-colors",
            "focus-within:border-primary/40 focus-within:bg-base-200"
          ]}
          phx-change="validate_new"
          phx-submit="save_new"
        >
          <.input
            type="text"
            field={@new_form[:name]}
            placeholder="New location name..."
            wrapperclass="mb-0 flex-1"
            autocomplete="off"
          />
          <.button variant="primary" type="submit" id="location-add-button">
            Add
          </.button>
        </.form>

        <div id="locations" class="flex flex-col gap-1" phx-update="stream">
          <div
            id="locations-empty"
            class="hidden only:block rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
          >
            No locations yet. Add one above.
          </div>

          <.location_row
            :for={{dom_id, form} <- @streams.locations}
            id={dom_id}
            form={form}
          />
        </div>
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

              // User accepted leave; do not warn again for this navigation.
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

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true

  defp location_row(assigns) do
    assigns = assign(assigns, :dirty?, dirty?(assigns.form))

    ~H"""
    <.form
      for={@form}
      id={@id}
      class={[
        "flex flex-row items-start gap-2 rounded-xl border bg-base-100 p-2 transition-all",
        @dirty? && "border-primary ring-1 ring-primary/30 bg-primary/5",
        not @dirty? && "border-base-300 hover:border-base-content/20"
      ]}
      phx-change="validate"
      phx-submit="save"
      phx-value-id={@form.data.id}
      phx-value-count={@form.data.item_count || 0}
      phx-value-original={@form.data.name || ""}
    >
      <.input
        type="text"
        field={@form[:name]}
        placeholder="Name..."
        wrapperclass="mb-0 flex-1"
        autocomplete="off"
      />
      <div
        id={"#{@id}-item-count"}
        class="flex h-10 shrink-0 items-center px-2 text-sm tabular-nums opacity-70"
      >
        {item_count_label(@form.data.item_count || 0)}
      </div>
      <.button variant="primary" type="submit" id={"#{@id}-save"} disabled={not @dirty?}>
        Save
      </.button>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    forms =
      Locations.list_with_item_counts()
      |> Enum.map(&to_location_form/1)

    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(:new_form, empty_new_form())
      |> assign(:dirty_ids, MapSet.new())
      |> assign(:unsaved?, false)
      |> stream_configure(:locations, dom_id: &location_dom_id/1)
      |> stream(:locations, forms)

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
     |> sync_unsaved()}
  end

  def handle_event("save_new", %{"location" => params}, socket) do
    %Location{}
    |> Locations.change_location(params)
    |> Locations.create()
    |> case do
      {:ok, location} ->
        form = to_location_form(%{location | item_count: 0})

        socket =
          socket
          |> assign(:new_form, empty_new_form())
          |> stream_insert(:locations, form, at: 0)
          |> put_flash(:info, "Location created")
          |> sync_unsaved()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:new_form, to_new_form(changeset, action: :validate))
         |> sync_unsaved()}
    end
  end

  def handle_event(
        "validate",
        %{"id" => id, "count" => count, "original" => original, "location" => params},
        socket
      ) do
    form =
      location_struct(id, count, original)
      |> Locations.change_location(params)
      |> Map.put(:action, :validate)
      |> to_location_form()

    {:noreply,
     socket
     |> stream_insert(:locations, form, update_only: true)
     |> track_row_dirty(id, form)
     |> sync_unsaved()}
  end

  def handle_event(
        "save",
        %{"id" => id, "count" => count, "original" => original, "location" => params},
        socket
      ) do
    count = parse_item_count(count)
    location = location_struct(id, count, original)
    changeset = Locations.change_location(location, params)

    if dirty?(changeset) do
      case Locations.update(changeset) do
        {:ok, updated} ->
          form = to_location_form(%{updated | item_count: count})

          socket =
            socket
            |> stream_insert(:locations, form, update_only: true)
            |> track_row_dirty(id, form)
            |> put_flash(:info, "Location saved")
            |> sync_unsaved()

          {:noreply, socket}

        {:error, changeset} ->
          form =
            changeset
            |> Map.update!(:data, &%{&1 | item_count: count})
            |> to_location_form(action: :validate)

          {:noreply,
           socket
           |> stream_insert(:locations, form, update_only: true)
           |> track_row_dirty(id, form)
           |> sync_unsaved()}
      end
    else
      form = to_location_form(location)

      {:noreply,
       socket
       |> stream_insert(:locations, form, update_only: true)
       |> track_row_dirty(id, form)
       |> sync_unsaved()}
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

  defp to_location_form(changeset_or_location, opts \\ [])

  defp to_location_form(%Location{} = location, opts) do
    location
    |> Locations.change_location()
    |> to_location_form(opts)
  end

  defp to_location_form(%Ecto.Changeset{} = changeset, opts) do
    id = changeset.data.id

    to_form(
      changeset,
      Keyword.merge([as: :location, id: "location-form-#{id}"], opts)
    )
  end

  defp location_struct(id, item_count, name) do
    %Location{id: id, name: name, item_count: parse_item_count(item_count)}
  end

  defp parse_item_count(count) when is_integer(count), do: count

  defp parse_item_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_item_count(_), do: 0

  defp track_row_dirty(socket, id, form_or_changeset) do
    dirty_ids =
      if dirty?(form_or_changeset) do
        MapSet.put(socket.assigns.dirty_ids, id)
      else
        MapSet.delete(socket.assigns.dirty_ids, id)
      end

    assign(socket, :dirty_ids, dirty_ids)
  end

  defp sync_unsaved(socket) do
    unsaved? =
      MapSet.size(socket.assigns.dirty_ids) > 0 or dirty?(socket.assigns.new_form)

    if socket.assigns.unsaved? == unsaved? do
      socket
    else
      socket
      |> assign(:unsaved?, unsaved?)
      |> push_event("unsaved-changes", %{dirty: unsaved?})
    end
  end

  defp dirty?(%Phoenix.HTML.Form{source: source}), do: dirty?(source)

  defp dirty?(%Ecto.Changeset{changes: changes}) when map_size(changes) > 0, do: true
  defp dirty?(_), do: false

  defp location_dom_id(%Phoenix.HTML.Form{data: %Location{id: id}}), do: "location-#{id}"
  defp location_dom_id(%Location{id: id}), do: "location-#{id}"

  defp item_count_label(1), do: "1 item"
  defp item_count_label(count), do: "#{count} items"
end
