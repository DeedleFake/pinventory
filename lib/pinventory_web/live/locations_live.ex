defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-4">
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

        <div
          id="locations"
          class="flex flex-col gap-1"
          phx-update="stream"
        >
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
    ~H"""
    <.form
      for={@form}
      id={@id}
      class={[
        "flex flex-row items-start gap-2 rounded-xl border border-base-300",
        "bg-base-100 p-2 transition-colors hover:border-base-content/20"
      ]}
      phx-change="validate"
      phx-submit="save"
      phx-value-id={@form.data.id}
      phx-value-count={@form.data.item_count || 0}
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
      <.button type="submit" id={"#{@id}-save"}>
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

    {:noreply, assign(socket, :new_form, form)}
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

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_new_form(changeset, action: :validate))}
    end
  end

  def handle_event("validate", %{"id" => id, "count" => count, "location" => params}, socket) do
    form =
      location_struct(id, count)
      |> Locations.change_location(params)
      |> Map.put(:action, :validate)
      |> to_location_form()

    {:noreply, stream_insert(socket, :locations, form, update_only: true)}
  end

  def handle_event("save", %{"id" => id, "count" => count, "location" => params}, socket) do
    count = parse_item_count(count)
    location = location_struct(id, count)

    location
    |> Locations.change_location(params)
    |> Locations.update()
    |> case do
      {:ok, updated} ->
        form = to_location_form(%{updated | item_count: count})

        socket =
          socket
          |> stream_insert(:locations, form, update_only: true)
          |> put_flash(:info, "Location saved")

        {:noreply, socket}

      {:error, changeset} ->
        form =
          changeset
          |> Map.update!(:data, &%{&1 | item_count: count})
          |> to_location_form(action: :validate)

        {:noreply, stream_insert(socket, :locations, form, update_only: true)}
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

  defp location_struct(id, item_count) do
    %Location{id: id, item_count: parse_item_count(item_count)}
  end

  defp parse_item_count(count) when is_integer(count), do: count

  defp parse_item_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_item_count(_), do: 0

  defp location_dom_id(%Phoenix.HTML.Form{data: %Location{id: id}}), do: "location-#{id}"
  defp location_dom_id(%Location{id: id}), do: "location-#{id}"

  defp item_count_label(1), do: "1 item"
  defp item_count_label(count), do: "#{count} items"
end
