defmodule PinventoryWeb.ItemsLive do
  use PinventoryWeb, :live_view

  alias Pinventory.Items
  alias Pinventory.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="items-page" class="space-y-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h1 class="text-xl font-semibold tracking-tight">Items</h1>
          <div
            id="items-actions"
            class="flex flex-wrap items-center justify-end gap-2"
          >
            <.link
              navigate={~p"/locations"}
              id="edit-locations"
              class="btn btn-ghost btn-soft"
            >
              <.icon name="hero-map-pin" class="size-4" /> Edit Locations
            </.link>
            <.link navigate={~p"/item"} id="new-item" class="btn btn-primary">
              <.icon name="hero-plus" class="size-4" /> New Item
            </.link>
          </div>
        </div>

        <div class="space-y-4">
          <.form
            for={@query}
            id="items-filter-form"
            class="flex flex-row items-start gap-2"
            phx-change="search"
            phx-submit="search"
          >
            <.input
              type="text"
              field={@query[:q]}
              wrapperclass="mb-0 flex-1"
              placeholder="Filter..."
              phx-debounce="300"
              autocomplete="off"
            />
            <.input
              type="select"
              field={@query[:location]}
              prompt="All locations"
              options={@location_options}
              wrapperclass="mb-0 w-40 sm:w-48"
            />
          </.form>

          <div id="items" class="flex flex-col gap-1" phx-update="stream">
            <div
              id="items-empty"
              class="hidden only:block rounded-xl border border-base-300 px-3 py-8 text-center text-sm opacity-60"
            >
              <%= if @filter_active? do %>
                No items match.
              <% else %>
                No items yet.
                <.link navigate={~p"/item"} class="link link-primary">Add an item</.link>
              <% end %>
            </div>

            <.link
              :for={{id, item} <- @streams.items}
              navigate={~p"/item/#{item.id}"}
              id={id}
              class={[
                "flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-3",
                "transition-all hover:border-base-content/20 hover:bg-base-200/40"
              ]}
            >
              <div class="min-w-0 flex-1">
                <div class="truncate font-medium">{item.name}</div>
                <div
                  id={"#{id}-stock"}
                  class="truncate text-sm tabular-nums opacity-60"
                >
                  {stock_label(item)}
                </div>
              </div>
              <.icon name="hero-chevron-right" class="size-4 shrink-0 opacity-40" />
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    location_options =
      Locations.list()
      |> Enum.map(&{&1.name, &1.id})

    {:ok,
     socket
     |> assign(:page_title, "Items")
     |> assign(:location_options, location_options)
     |> assign(:filter_active?, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    items = Items.list_items(list_opts(params))

    socket =
      socket
      |> stream(:items, items, reset: true)
      |> assign(:query, to_form(params))
      |> assign(:filter_active?, filter_active?(params))

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", params, socket) do
    query = to_query(params)

    {:noreply, push_patch(socket, to: ~p"/?#{query}")}
  end

  defp list_opts(params) do
    []
    |> maybe_put_opt(:filter, blank_to_nil(params["q"]))
    |> maybe_put_opt(:location_id, blank_to_nil(params["location"]))
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp filter_active?(params) do
    blank_to_nil(params["q"]) != nil or blank_to_nil(params["location"]) != nil
  end

  defp to_query(params) do
    keys = [:location, :q]

    for key <- keys, val = params[to_string(key)], val != "" do
      {key, val}
    end
  end

  defp stock_label(%{total_quantity: total, location_count: count})
       when is_integer(total) and total > 0 and is_integer(count) and count > 0 do
    locations = if count == 1, do: "1 location", else: "#{count} locations"
    "#{total} total in #{locations}"
  end

  defp stock_label(%{total_quantity: total}) when is_integer(total), do: "#{total} total"
  defp stock_label(_), do: "0 total"
end
