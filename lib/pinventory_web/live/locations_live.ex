defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="locations-page"
        class="space-y-4"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-xl font-semibold tracking-tight">Locations</h1>
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm" id="locations-back">
            Back
          </.link>
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
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true

  defp location_row(assigns) do
    assigns = assign(assigns, :row_dirty?, row_dirty?(assigns.form))

    ~H"""
    <.form
      for={@form}
      id={@id}
      class={[
        "flex flex-row items-start gap-2 rounded-xl border bg-base-100 p-2 transition-all",
        @row_dirty? && "border-primary ring-1 ring-primary/30 bg-primary/5",
        not @row_dirty? && "border-base-300 hover:border-base-content/20"
      ]}
      phx-change="validate"
      phx-submit="save"
      phx-value-id={@form.data.id}
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
      <.button variant="primary" type="submit" id={"#{@id}-save"} disabled={not @row_dirty?}>
        Save
      </.button>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    locations = Locations.list_with_item_counts()
    locations_by_id = Map.new(locations, &{&1.id, &1})
    forms = Enum.map(locations, &to_location_form/1)

    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(:locations_by_id, locations_by_id)
      |> assign(:new_form, empty_new_form())
      |> assign(:dirty_ids, MapSet.new())
      |> assign(:dirty?, false)
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
     |> sync_dirty()}
  end

  def handle_event("save_new", %{"location" => params}, socket) do
    %Location{}
    |> Locations.change_location(params)
    |> Locations.create()
    |> case do
      {:ok, location} ->
        location = %{location | item_count: 0}
        form = to_location_form(location)

        socket =
          socket
          |> update(:locations_by_id, &Map.put(&1, location.id, location))
          |> assign(:new_form, empty_new_form())
          |> stream_insert(:locations, form, at: 0)
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

  def handle_event("validate", %{"id" => id, "location" => params}, socket) do
    case Map.get(socket.assigns.locations_by_id, id) do
      nil ->
        {:noreply, socket}

      location ->
        form =
          location
          |> Locations.change_location(params)
          |> Map.put(:action, :validate)
          |> to_location_form()

        {:noreply,
         socket
         |> stream_insert(:locations, form, update_only: true)
         |> track_row_dirty(id, form)
         |> sync_dirty()}
    end
  end

  def handle_event("save", %{"id" => id, "location" => params}, socket) do
    case Map.get(socket.assigns.locations_by_id, id) do
      nil ->
        {:noreply, socket}

      location ->
        save_location_row(socket, id, location, params)
    end
  end

  defp save_location_row(socket, id, location, params) do
    changeset = Locations.change_location(location, params)

    if row_dirty?(changeset) do
      case Locations.update(changeset) do
        {:ok, updated} ->
          updated = %{updated | item_count: location.item_count}
          form = to_location_form(updated)

          socket =
            socket
            |> update(:locations_by_id, &Map.put(&1, id, updated))
            |> stream_insert(:locations, form, update_only: true)
            |> track_row_dirty(id, form)
            |> put_flash(:info, "Location saved")
            |> sync_dirty()

          {:noreply, socket}

        {:error, changeset} ->
          form =
            changeset
            |> Map.update!(:data, &%{&1 | item_count: location.item_count})
            |> to_location_form(action: :validate)

          {:noreply,
           socket
           |> stream_insert(:locations, form, update_only: true)
           |> track_row_dirty(id, form)
           |> sync_dirty()}
      end
    else
      form = to_location_form(location)

      {:noreply,
       socket
       |> stream_insert(:locations, form, update_only: true)
       |> track_row_dirty(id, form)
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

  defp track_row_dirty(socket, id, form_or_changeset) do
    dirty_ids =
      if row_dirty?(form_or_changeset) do
        MapSet.put(socket.assigns.dirty_ids, id)
      else
        MapSet.delete(socket.assigns.dirty_ids, id)
      end

    assign(socket, :dirty_ids, dirty_ids)
  end

  defp sync_dirty(socket) do
    dirty? =
      MapSet.size(socket.assigns.dirty_ids) > 0 or row_dirty?(socket.assigns.new_form)

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

  defp row_dirty?(%Phoenix.HTML.Form{source: source}), do: row_dirty?(source)

  defp row_dirty?(%Ecto.Changeset{changes: changes}) when map_size(changes) > 0, do: true
  defp row_dirty?(_), do: false

  defp location_dom_id(%Phoenix.HTML.Form{data: %Location{id: id}}), do: "location-#{id}"
  defp location_dom_id(%Location{id: id}), do: "location-#{id}"

  defp item_count_label(1), do: "1 item"
  defp item_count_label(count), do: "#{count} items"
end
