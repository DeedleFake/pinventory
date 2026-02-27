defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations
  alias Pinventory.Locations.Location

  @new_id "<new>"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="locations" class="flex flex-col gap-1" phx-update="stream">
        <.row
          :for={{dom_id, location} <- @streams.locations}
          id={dom_id}
          location={location}
        />
      </div>
    </Layouts.app>
    """
  end

  defp row(assigns) do
    ~H"""
    <.form
      for={@location}
      id={@id}
      class="flex flex-row gap-1"
      phx-change="validate"
      phx-submit="save"
      phx-value-id={@id}
    >
      <.input type="text" field={@location[:name]} placeholder="Name..." />
      <.button variant="primary" type="submit">
        <%= if @location.data.id == nil do %>
          Add
        <% else %>
          Save
        <% end %>
      </.button>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    locations =
      [%Location{} | Locations.list()]
      |> Enum.map(&Locations.change_location/1)
      |> Enum.map(&to_form/1)

    socket =
      socket
      |> stream_configure(:locations, dom_id: &"locations-#{&1.data.id || @new_id}")
      |> stream(:locations, locations)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"id" => id, "location" => location}, socket) do
    id = if id != @new_id, do: id, else: nil

    location =
      %Location{id: id}
      |> Locations.change_location(location)
      |> to_form(action: :validate)

    {:noreply, stream_insert(socket, :locations, location, update_only: true)}
  end

  # @impl true
  # def handle_event("save", %{"location" => new_location}, socket) do
  #   Locations.create(new_location)
  #   |> case do
  #     {:ok, location} ->
  #       new_location =
  #         %Location{}
  #         |> Locations.change_location()
  #         |> to_form(as: :new_location)

  #       socket =
  #         socket
  #         |> assign(:new_location, new_location)
  #         |> stream_insert(:locations, location, at: 0)

  #       {:noreply, socket}

  #     {:error, new_location} ->
  #       new_location = to_form(new_location, as: :new_location)
  #       {:noreply, assign(socket, :new_location, new_location)}
  #   end
  # end
end
