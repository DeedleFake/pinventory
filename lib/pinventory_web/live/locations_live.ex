defmodule PinventoryWeb.LocationsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Locations
  alias Pinventory.Locations.Location

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
    new_location =
      %Location{}
      |> Locations.change_location()
      |> to_form(as: :new_location)

    locations = Locations.list()

    socket =
      socket
      |> assign(:new_location, new_location)
      |> stream(:locations, locations)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_new", %{"new_location" => new_location}, socket) do
    new_location =
      %Location{}
      |> Locations.change_location(new_location)
      |> to_form(as: :new_location, action: :validate)

    {:noreply, assign(socket, :new_location, new_location)}
  end

  @impl true
  def handle_event("submit_new", %{"new_location" => new_location}, socket) do
    Locations.create(new_location)
    |> case do
      {:ok, location} ->
        new_location =
          %Location{}
          |> Locations.change_location()
          |> to_form(as: :new_location)

        socket =
          socket
          |> assign(:new_location, new_location)
          |> stream_insert(:locations, location, at: 0)

        {:noreply, socket}

      {:error, new_location} ->
        new_location = to_form(new_location, as: :new_location)
        {:noreply, assign(socket, :new_location, new_location)}
    end
  end
end
