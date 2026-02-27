defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col gap-1">
        <.form
          for={@new_location}
          class="flex flex-row gap-1"
          phx-change="change_new"
          phx-submit="submit_new"
        >
          <.input type="text" field={@new_location[:name]} placeholder="Name..." />
          <.button variant="primary" type="submit">Add</.button>
        </.form>
        <div id="locations" class="contents" phx-update="stream">
          <div :for={{id, location} <- @streams.locations} id={id}>{location.name}</div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    locations = Locations.list()

    socket =
      socket
      |> assign(:new_location, to_form(Locations.create_changeset()))
      |> stream(:locations, locations)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_new", params, socket) do
    new_location =
      params
      |> Locations.create_changeset()
      |> to_form()

    {:noreply, assign(socket, :new_location, new_location)}
  end
end
