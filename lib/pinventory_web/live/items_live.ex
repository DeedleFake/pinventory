defmodule PinventoryWeb.ItemsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.input type="text" value={@query} phx-change="change_query" placeholder="Filter..." />
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
      |> assign(:query, q)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> stream(:items, Items.list_items())
      |> assign(:query, "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_query", %{"query" => query}, socket) do
    socket =
      socket
      |> push_patch(~p"/?q=#{query}")

    {:noreply, socket}
  end
end
