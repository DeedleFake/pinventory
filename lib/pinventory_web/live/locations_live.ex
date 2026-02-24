defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="locations" class="flex flex-col gap-1" phx-update="stream">
        <div :for={{id, location} <- @streams.locations} id={id}>{location.name}</div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    locations = Locations.list()

    socket =
      socket
      |> stream(:locations, locations)

    {:ok, socket}
  end
end
