defmodule PinventoryWeb.MCPRouter do
  @moduledoc """
  MCP server that lets an agent read the inventory and change stock counts
  of existing items at existing locations, acting as the user who owns the
  API token.

  The agent decides which item and location the user means. The server only
  checks what it can know for certain: the ids exist, counts stay within
  0..1,000,000, and every change records in Activity marked with the token.
  """

  @instructions """
  Pinventory is a household inventory. Items are stored at locations, with a count at each location.

  - list_items matches the letters of each word in order inside item names, ignoring case, with gaps allowed. A singular word also finds its regular plural ("towel" finds "Paper Towels"), but a plural doesn't find the singular. Gaps mean loose matches too ("towel" also finds "Tool wheel"), so check the names before using a result. Notes are not searched.
  - Before deciding an item isn't in Pinventory, search with several wordings in one list_items call: singular forms, irregular forms (both "knife" and "knives"), synonyms, and brand names. If that finds nothing, call list_items with no terms to see everything.
  - When more than one item or location could be the one the user means, ask the user. Don't guess. If the user didn't say which location, ask.
  - Use the ids from list_items and list_locations for changes.
  - To move stock between locations, use move_stock, not two change_stock calls.
  - You can only change counts of existing items at existing locations. Creating, renaming, or deleting items or locations, and editing notes, happen in the Pinventory web UI. Send the user the item's or location's url.
  """

  use Phantom.Router,
    name: "Pinventory",
    vsn: "1.0",
    instructions: @instructions,
    # No tool elicits input, but Phantom needs these to serve MCP 2026-07-28.
    secret_key_base: {PinventoryWeb.Endpoint, :config, [:secret_key_base]},
    request_state_salt: "pinventory mcp request_state v1"

  use PinventoryWeb, :verified_routes

  require Phantom.Tool, as: Tool

  alias Pinventory.Accounts
  alias Pinventory.Items
  alias Pinventory.Locations
  alias Pinventory.Repo

  @no_match_hint "No item names matched these terms. Try singular forms, irregular forms " <>
                   "such as both \"knife\" and \"knives\", other names, or brands, " <>
                   "or call list_items with no terms to see everything, " <>
                   "before telling the user it isn't in Pinventory."

  @impl true
  def connect(session, conn) do
    with [header | _] <- Plug.Conn.get_req_header(conn, "authorization"),
         [_, secret] <- Regex.run(~r/\Abearer\s+(\S+)\s*\z/i, header),
         {:ok, scope} <- Accounts.fetch_scope_for_api_token(secret) do
      {:ok, Phantom.Session.assign(session, :scope, scope)}
    else
      _ -> {:unauthorized, %{method: "Bearer", realm: "pinventory"}}
    end
  end

  @description """
  List every location, ordered by name. Each has an id, a name, the floor-plan floor it is on (or null), and its page url.
  If more than one location could be the one the user means, ask the user.
  """
  tool :list_locations, read_only: true

  def list_locations(_params, session) do
    locations =
      Enum.map(Locations.list_with_item_counts_and_placements(), fn location ->
        %{
          id: location.id,
          name: location.name,
          floor: location.floor_name,
          url: url(~p"/location/#{location.id}")
        }
      end)

    {:reply, Tool.structured(%{locations: locations}), session}
  end

  @description """
  Search items by name. An item matches when, for any one term, the letters of every word appear in its name in order, ignoring case, with gaps allowed. Expect some loose matches. Notes are not searched. A singular word also finds its regular plural ("towel" finds "Paper Towels"). Pass several wordings at once, for example ["paper towel", "kitchen roll", "bounty"], and pass irregular forms yourself, such as both "knife" and "knives". Results come best match first, with notes, the count at each location, and the item's page url.
  Leave out terms only as a last resort, to list every item.
  If more than one item could be the one the user means, ask the user.
  """
  tool :list_items, read_only: true do
    field :terms, {:array, :string},
      description: "Words to search for. Any one term matching is enough."
  end

  def list_items(params, session) do
    case params["terms"] do
      terms when is_list(terms) and terms != [] ->
        case Items.search_items(terms) do
          [] ->
            {:reply,
             %{structuredContent: %{items: []}, content: [%{type: :text, text: @no_match_hint}]},
             session}

          items ->
            {:reply, Tool.structured(%{items: Enum.map(preload_stock(items), &item_json/1)}),
             session}
        end

      _ ->
        items = Items.list_items(limit: 1000)
        {:reply, Tool.structured(%{items: Enum.map(preload_stock(items), &item_json/1)}), session}
    end
  end

  @description """
  Change the count of one existing item at one existing location. Send exactly one of add (a whole number, negative to take some away) or set (the new count, 0 to 1,000,000; 0 removes the item from that location).
  Use ids from list_items and list_locations. If the user didn't say which location, ask.
  To move stock between locations, use move_stock instead.
  """
  tool :change_stock, idempotent: false, destructive: false do
    field :item_id, :string, required: true, description: "Item id from list_items."
    field :location_id, :string, required: true, description: "Location id from list_locations."
    field :add, :integer, description: "Amount to add. Negative takes some away."
    field :set, :integer, minimum: 0, maximum: 1_000_000, description: "The new count."
  end

  def change_stock(%{"item_id" => item_id, "location_id" => location_id} = params, session) do
    change =
      case {params["add"], params["set"]} do
        {add, nil} when is_integer(add) -> {:add, add}
        {nil, set} when is_integer(set) -> {:set, set}
        _ -> nil
      end

    if change do
      case Items.change_stock(session.assigns.scope, item_id, location_id, change) do
        {:ok, %{item: item, from: from, to: to}} ->
          {:reply, Tool.structured(%{item: stock_item_json(item), from: from, to: to}), session}

        {:error, reason} ->
          {:reply, Tool.error(error_message(reason, location_id)), session}
      end
    else
      {:reply, Tool.error("Send exactly one of add or set."), session}
    end
  end

  @description """
  Move some of one existing item from one location to another, as a single change: both counts change or neither does.
  Use ids from list_items and list_locations. If the user didn't say how many moved, ask.
  """
  tool :move_stock, idempotent: false, destructive: false do
    field :item_id, :string, required: true, description: "Item id from list_items."

    field :from_location_id, :string,
      required: true,
      description: "Location id to take the stock from."

    field :to_location_id, :string, required: true, description: "Location id to put it in."
    field :quantity, :integer, required: true, minimum: 1, description: "How many to move."
  end

  def move_stock(
        %{
          "item_id" => item_id,
          "from_location_id" => from_id,
          "to_location_id" => to_id,
          "quantity" => quantity
        },
        session
      ) do
    case Items.move_stock(session.assigns.scope, item_id, from_id, to_id, quantity) do
      {:ok, %{item: item, from: from, to: to}} ->
        {:reply,
         Tool.structured(%{
           item: stock_item_json(item),
           from: Map.put(from, :location_id, from_id),
           to: Map.put(to, :location_id, to_id)
         }), session}

      {:error, reason} ->
        {:reply, Tool.error(error_message(reason, from_id)), session}
    end
  end

  defp error_message(:item_not_found, _), do: "No item has that id. Call list_items for ids."

  defp error_message(:location_not_found, _),
    do: "No location has that id. Call list_locations for ids."

  defp error_message(:same_location, _), do: "The from and to locations are the same."

  defp error_message(:too_many, _),
    do: "That would put more than 1,000,000 at one location. Nothing was changed."

  defp error_message({:below_zero, count}, location_id),
    do:
      "below zero: #{location_name(location_id)} has #{count}. Nothing was changed. Ask the user what happened."

  defp error_message({:not_enough, count}, location_id),
    do: "not enough: #{location_name(location_id)} has #{count}. Nothing was changed."

  defp location_name(location_id), do: Locations.get(location_id).name

  defp stock_item_json(item), do: item |> preload_stock() |> item_json()

  defp preload_stock(items), do: Repo.preload(items, [item_locations: :location], force: true)

  defp item_json(item) do
    %{
      id: item.id,
      name: item.name,
      notes: item.notes,
      stock:
        item.item_locations
        |> Enum.sort_by(& &1.location.name)
        |> Enum.map(
          &%{location_id: &1.location_id, location: &1.location.name, quantity: &1.quantity}
        ),
      url: url(~p"/item/#{item.id}")
    }
  end
end
