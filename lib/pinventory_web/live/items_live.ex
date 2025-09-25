defmodule PinventoryWeb.ItemsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="items"
        class="flex flex-col bg-white text-black rounded-xl cursor-default select-none"
        phx-update="stream"
      >
        <div :for={{id, item} <- @streams.items} id={id} class="bg-slate-100 hover:bg-slate-200 p-1">
          {item.name}
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_params(%{"q" => q}, _uri, socket) when q != "" do
    socket =
      socket
      |> stream(:items, Items.list_items(filter: q))

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> stream(:items, Items.list_items())

    {:noreply, socket}
  end
end
