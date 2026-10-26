defmodule PinventoryWeb.MCPRouter do
  @moduledoc """
  MCP server that lets an agent read the inventory, create and rename items,
  rename locations, and change stock counts of items at existing locations,
  acting as the user who owns the API token.

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
  - To add a new item, search with list_items first so you don't make a duplicate, then create_item, then change_stock to record how many and where.
  - You can only change counts at existing locations. Deleting items, creating or deleting locations, and editing notes of existing items happen in the Pinventory web UI. Send the user the item's or location's url.
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
  Pass location_id to only get items that have stock at that location. To list everything at one location, pass location_id without terms.
  To list every item, leave out both terms and location_id. Do this only when a more focused query does not accomplish the goal.
  If more than one item could be the one the user means, ask the user.
  """
  tool :list_items, read_only: true do
    field :terms, {:array, :string},
      description: "Words to search for. Any one term matching is enough."

    field :location_id, :string, description: "Location id from list_locations."
  end

  def list_items(params, session) do
    case fetch_location_filter(params["location_id"]) do
      {:ok, location_id} ->
        {:reply, list_items_reply(params["terms"], location_id), session}

      :error ->
        {:reply, Tool.error(error_message(:location_not_found, nil)), session}
    end
  end

  defp fetch_location_filter(nil), do: {:ok, nil}

  defp fetch_location_filter(location_id) do
    with {:ok, location} <- fetch(location_id, &Locations.get/1), do: {:ok, location.id}
  end

  defp list_items_reply(terms, location_id) when is_list(terms) and terms != [] do
    case Items.search_items(terms, location_id: location_id) do
      [] ->
        %{structuredContent: %{items: []}, content: [%{type: :text, text: @no_match_hint}]}

      items ->
        Tool.structured(%{items: Enum.map(preload_stock(items), &item_json/1)})
    end
  end

  defp list_items_reply(_terms, location_id) do
    items = Items.list_items(limit: 1000, location_id: location_id)
    Tool.structured(%{items: Enum.map(preload_stock(items), &item_json/1)})
  end

  @description """
  Create a new item with no stock. Search with list_items first, with several wordings, so you don't make a duplicate of an item that already exists. Names must be unique and at least 2 characters.
  Returns the item like list_items does. Then use change_stock to record how many there are and where.
  """
  tool :create_item, idempotent: false, destructive: false do
    field :name, :string, required: true, description: "The item's name."
    field :notes, :string, description: "Notes about the item."
  end

  def create_item(params, session) do
    case Items.create_item(session.assigns.scope, Map.take(params, ["name", "notes"])) do
      {:ok, item} ->
        {:reply, Tool.structured(%{item: stock_item_json(item)}), session}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:reply, Tool.error(changeset_message(changeset)), session}
    end
  end

  @description """
  Rename one existing item. Names must be unique and at least 2 characters. Notes and stock stay as they are.
  Use the id from list_items. Returns the item like list_items does.
  """
  tool :rename_item, idempotent: true, destructive: false do
    field :item_id, :string, required: true, description: "Item id from list_items."
    field :name, :string, required: true, description: "The new name."
  end

  def rename_item(%{"item_id" => item_id, "name" => name}, session) do
    with {:ok, item} <- fetch(item_id, &Items.get_item/1),
         {:ok, item} <-
           Items.update_item(
             session.assigns.scope,
             item,
             %{"name" => name},
             Items.stock_map(item)
           ) do
      {:reply, Tool.structured(%{item: stock_item_json(item)}), session}
    else
      :error -> {:reply, Tool.error(error_message(:item_not_found, nil)), session}
      {:error, :stale} -> {:reply, Tool.error(error_message(:stale, nil)), session}
      {:error, changeset} -> {:reply, Tool.error(changeset_message(changeset)), session}
    end
  end

  @description """
  Rename one existing location. Names must be unique. Its items and stock stay as they are.
  Use the id from list_locations. Returns the location's id, name, and page url.
  """
  tool :rename_location, idempotent: true, destructive: false do
    field :location_id, :string, required: true, description: "Location id from list_locations."
    field :name, :string, required: true, description: "The new name."
  end

  def rename_location(%{"location_id" => location_id, "name" => name}, session) do
    with {:ok, location} <- fetch(location_id, &Locations.get/1),
         {:ok, location} <- Locations.update(session.assigns.scope, location, %{"name" => name}) do
      {:reply,
       Tool.structured(%{
         location: %{
           id: location.id,
           name: location.name,
           url: url(~p"/location/#{location.id}")
         }
       }), session}
    else
      :error -> {:reply, Tool.error(error_message(:location_not_found, nil)), session}
      {:error, changeset} -> {:reply, Tool.error(changeset_message(changeset)), session}
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

  defp error_message(:stale, _),
    do: "The item changed while renaming it. Nothing was changed. Try again."

  defp error_message(:same_location, _), do: "The from and to locations are the same."

  defp error_message(:too_many, _),
    do: "That would put more than 1,000,000 at one location. Nothing was changed."

  defp error_message({:below_zero, count}, location_id),
    do:
      "below zero: #{location_name(location_id)} has #{count}. Nothing was changed. Ask the user what happened."

  defp error_message({:not_enough, count}, location_id),
    do: "not enough: #{location_name(location_id)} has #{count}. Nothing was changed."

  defp fetch(id, get) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %{} = record <- get.(uuid) do
      {:ok, record}
    else
      _ -> :error
    end
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join(", ")
    |> then(&"Nothing was changed: #{&1}.")
  end

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
