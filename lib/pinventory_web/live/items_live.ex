defmodule PinventoryWeb.ItemsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.form for={@query} class="flex flex-row gap-1" phx-change="search" phx-submit="search">
        <.input type="text" field={@query[:q]} wrapperclass="flex-1" placeholder="Filter..." />
        <.input type="select" field={@query[:location]} prompt="Location..." options={[]} />
      </.form>
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
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> stream(:items, Items.list_items())
      |> assign(:query, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", params, socket) do
    query = to_query(params)

    socket =
      socket
      |> push_patch(to: ~p"/?#{query}")

    {:noreply, socket}
  end

  defp to_query(params) do
    keys = [:location, :q]

    for key <- keys, val = params[to_string(key)], val != "" do
      {key, val}
    end
  end
end
