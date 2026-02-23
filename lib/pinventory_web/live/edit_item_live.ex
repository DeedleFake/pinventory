defmodule PinventoryWeb.EditItemLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      Not implemented.
    </Layouts.app>
    """
  end

  @impl true
  def handle_params(%{"item_id" => item_id}, _uri, socket) do
    item = Items.get_item!(item_id)

    socket =
      socket
      |> assign(:item, to_form(item))

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:item, to_form(%{}))

    {:noreply, socket}
  end
end
