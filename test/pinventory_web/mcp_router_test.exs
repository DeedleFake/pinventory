defmodule PinventoryWeb.MCPRouterTest do
  use PinventoryWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts
  alias Pinventory.Accounts.ApiToken
  alias Pinventory.Audit
  alias Pinventory.Audit.Event
  alias Pinventory.Items
  alias Pinventory.Locations
  alias Pinventory.Repo
  alias PinventoryWeb.AuditHelpers

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    {:ok, {secret, token}} = Accounts.create_api_token(user, "Claude on phone")
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, drawer} = Locations.create(scope, %{name: "Kitchen drawer"})

    {:ok, towels} =
      Items.create_item(scope, %{name: "Paper towels", notes: "Bounty, 6-roll packs"}, %{
        garage.id => 4
      })

    {:ok, batteries} =
      Items.create_item(scope, %{name: "AA batteries"}, %{drawer.id => 8, garage.id => 24})

    %{
      user: user,
      secret: secret,
      token: token,
      garage: garage,
      drawer: drawer,
      towels: towels,
      batteries: batteries
    }
  end

  # Phantom streams legacy-protocol replies from a gen_server loop, which
  # needs a proc_lib process, so the request runs in a Task.
  defp post_rpc(conn, auth, method, params) do
    Task.async(fn -> do_post_rpc(conn, auth, method, params) end) |> Task.await()
  end

  defp do_post_rpc(conn, auth, method, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> then(&if(auth, do: put_req_header(&1, "authorization", auth), else: &1))
    |> post("/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method, params: params}))
  end

  defp rpc_response(secret, method, params) do
    conn = post_rpc(build_conn(), "Bearer #{secret}", method, params)
    assert conn.status == 200
    [_, data] = Regex.run(~r/^data: (\{.*\})$/m, conn.resp_body)
    Jason.decode!(data)
  end

  defp rpc(secret, method, params \\ %{}), do: rpc_response(secret, method, params)["result"]

  defp invalid_params(secret, tool, args) do
    response = rpc_response(secret, "tools/call", %{name: tool, arguments: args})
    assert %{"error" => %{"message" => "Invalid Params", "data" => data}} = response
    Enum.join(data["validation_errors"], " ")
  end

  defp call(secret, tool, args), do: rpc(secret, "tools/call", %{name: tool, arguments: args})

  defp text(result), do: hd(result["content"])["text"]

  defp stock(item), do: item.id |> Items.get_item!() |> Items.stock_map()

  defp event_count, do: Repo.aggregate(Event, :count)

  describe "authentication" do
    test "answers 401 with a Bearer challenge without a working token", %{
      conn: conn,
      user: user,
      token: token
    } do
      {:ok, {expired, expired_token}} = Accounts.create_api_token(user, "old")

      Repo.update_all(from(t in ApiToken, where: t.id == ^expired_token.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      {:ok, {revoked, _}} = Accounts.replace_api_token(user, token.id)
      Accounts.revoke_all_api_tokens(user)

      for auth <- [nil, "Bearer nope", "Basic abc", "Bearer #{expired}", "Bearer #{revoked}"] do
        conn = post_rpc(conn, auth, "tools/list", %{})
        assert conn.status == 401, "expected 401 for #{inspect(auth)}"
        assert [~s|Bearer realm="pinventory"|] = get_resp_header(conn, "www-authenticate")
      end
    end

    test "initialize returns the agent instructions", %{secret: secret} do
      result =
        rpc(secret, "initialize", %{
          protocolVersion: "2025-06-18",
          capabilities: %{},
          clientInfo: %{name: "test", version: "1"}
        })

      assert result["serverInfo"]["name"] == "Pinventory"
      assert result["instructions"] =~ ~s("towel" finds "Paper Towels")
      assert result["instructions"] =~ "ask the user. Don't guess."
      assert result["instructions"] =~ "happen in the Pinventory web UI"
      assert result["instructions"] =~ "Call get_naming_convention before you create or rename"
    end

    test "lists the tools", %{secret: secret} do
      names = rpc(secret, "tools/list")["tools"] |> Enum.map(& &1["name"]) |> Enum.sort()

      assert names ==
               ~w[change_stock create_item edit_naming_convention get_naming_convention list_items list_locations move_stock rename_item rename_location]
    end
  end

  describe "list_locations" do
    test "returns every location with its page", %{secret: secret, garage: garage} do
      %{"locations" => locations} = call(secret, "list_locations", %{})["structuredContent"]

      assert Enum.map(locations, & &1["name"]) == ["Garage", "Kitchen drawer"]
      assert %{"id" => id, "floor" => nil, "url" => url} = hd(locations)
      assert id == garage.id
      assert url =~ "/location/#{garage.id}"
    end
  end

  describe "list_items" do
    test "searches names by any term, with stock per location", %{
      secret: secret,
      towels: towels,
      garage: garage
    } do
      %{"items" => [item]} =
        call(secret, "list_items", %{terms: ["kitchen roll", "paper towel"]})["structuredContent"]

      assert item["id"] == towels.id
      assert item["notes"] == "Bounty, 6-roll packs"
      assert item["url"] =~ "/item/#{towels.id}"

      assert item["stock"] == [
               %{"location_id" => garage.id, "location" => "Garage", "quantity" => 4}
             ]

      assert %{"items" => []} =
               call(secret, "list_items", %{terms: ["battery"]})["structuredContent"]

      assert %{"items" => [%{"name" => "AA batteries"}]} =
               call(secret, "list_items", %{terms: ["battery", "batteries"]})["structuredContent"]
    end

    test "does not search notes", %{secret: secret} do
      assert call(secret, "list_items", %{terms: ["bounty"]})["structuredContent"] == %{
               "items" => []
             }
    end

    test "tells the agent to keep looking when nothing matches", %{secret: secret} do
      result = call(secret, "list_items", %{terms: ["light bulb"]})

      assert result["structuredContent"] == %{"items" => []}

      assert text(result) =~
               ~s(Try singular forms, irregular forms such as both "knife" and "knives")

      assert text(result) =~ "call list_items with no terms"
    end

    test "lists every item without terms", %{secret: secret} do
      %{"items" => items} = call(secret, "list_items", %{})["structuredContent"]
      assert Enum.map(items, & &1["name"]) == ["AA batteries", "Paper towels"]
    end

    test "lists every item at one location, with stock at every location", %{
      secret: secret,
      garage: garage,
      drawer: drawer
    } do
      %{"items" => [item]} =
        call(secret, "list_items", %{location_id: drawer.id})["structuredContent"]

      assert item["name"] == "AA batteries"

      assert item["stock"] == [
               %{"location_id" => garage.id, "location" => "Garage", "quantity" => 24},
               %{"location_id" => drawer.id, "location" => "Kitchen drawer", "quantity" => 8}
             ]

      %{"items" => items} =
        call(secret, "list_items", %{location_id: garage.id})["structuredContent"]

      assert Enum.map(items, & &1["name"]) == ["AA batteries", "Paper towels"]
    end

    test "searches names only at one location", %{secret: secret, garage: garage, drawer: drawer} do
      terms = ["paper towel", "batteries"]

      assert %{"items" => [%{"name" => "AA batteries"}]} =
               call(secret, "list_items", %{terms: terms, location_id: drawer.id})[
                 "structuredContent"
               ]

      %{"items" => items} =
        call(secret, "list_items", %{terms: terms, location_id: garage.id})["structuredContent"]

      assert items |> Enum.map(& &1["name"]) |> Enum.sort() == ["AA batteries", "Paper towels"]

      result = call(secret, "list_items", %{terms: ["towel"], location_id: drawer.id})
      assert result["structuredContent"] == %{"items" => []}
      assert text(result) =~ "Try singular forms"
    end

    test "refuses an unknown or malformed location id", %{secret: secret} do
      for id <- [Ecto.UUID.generate(), "garage", ""] do
        result = call(secret, "list_items", %{location_id: id})
        assert result["isError"]
        assert text(result) == "No location has that id. Call list_locations for ids."
      end

      result = call(secret, "list_items", %{terms: ["towel"], location_id: Ecto.UUID.generate()})
      assert result["isError"]
    end
  end

  describe "create_item" do
    test "creates an item that change_stock can then stock, marked as via the agent", %{
      secret: secret,
      user: user,
      garage: garage
    } do
      %{"item" => item} =
        call(secret, "create_item", %{name: " Light bulbs ", notes: "E26, warm white"})[
          "structuredContent"
        ]

      assert %{"name" => "Light bulbs", "notes" => "E26, warm white", "stock" => []} = item
      assert item["url"] =~ "/item/#{item["id"]}"
      assert Items.get_item!(item["id"]).name == "Light bulbs"

      [edit] = Audit.list_edits_for_item(item["id"])
      assert AuditHelpers.edit_heading(edit) =~ "#{user.email} via Claude on phone"
      assert List.last(Items.note_versions(item["id"])).text == "E26, warm white"

      assert %{"from" => 0, "to" => 3} =
               call(secret, "change_stock", %{item_id: item["id"], location_id: garage.id, add: 3})[
                 "structuredContent"
               ]

      assert %{"items" => [%{"name" => "Light bulbs"}]} =
               call(secret, "list_items", %{terms: ["bulb"], location_id: garage.id})[
                 "structuredContent"
               ]
    end

    test "refuses a duplicate or too-short name and writes nothing", %{secret: secret} do
      before = event_count()

      for {name, message} <- [
            {"Paper towels", "name has already been taken"},
            {" x ", "name should be at least 2 character(s)"},
            {"", "name can't be blank"}
          ] do
        result = call(secret, "create_item", %{name: name})
        assert result["isError"]
        assert text(result) == "Nothing was changed: #{message}."
      end

      assert event_count() == before
    end
  end

  describe "rename_item" do
    test "renames an item, keeps its notes and stock, and records the edit", %{
      secret: secret,
      user: user,
      batteries: batteries,
      garage: garage,
      drawer: drawer
    } do
      before = Items.get_item!(batteries.id)

      %{"item" => item} =
        call(secret, "rename_item", %{item_id: batteries.id, name: "AA batteries (Eneloop)"})[
          "structuredContent"
        ]

      assert item["name"] == "AA batteries (Eneloop)"
      assert stock(batteries) == %{garage.id => 24, drawer.id => 8}

      renamed = Items.get_item!(batteries.id)
      assert renamed.notes == before.notes
      assert renamed.lock_version == before.lock_version + 1

      [edit | _] = Audit.list_edits_for_item(batteries.id, limit: 1)
      assert AuditHelpers.edit_heading(edit) =~ "#{user.email} via Claude on phone"

      assert Enum.map(edit.events, & &1.changes) == [
               %{"name" => %{"from" => "AA batteries", "to" => "AA batteries (Eneloop)"}}
             ]
    end

    test "refuses an unknown item or a bad name and writes nothing", %{
      secret: secret,
      batteries: batteries
    } do
      before = event_count()

      for {args, message} <- [
            {%{item_id: Ecto.UUID.generate(), name: "Batteries"},
             "No item has that id. Call list_items for ids."},
            {%{item_id: "batteries", name: "Batteries"},
             "No item has that id. Call list_items for ids."},
            {%{item_id: batteries.id, name: "Paper towels"},
             "Nothing was changed: name has already been taken."},
            {%{item_id: batteries.id, name: "A"},
             "Nothing was changed: name should be at least 2 character(s)."}
          ] do
        result = call(secret, "rename_item", args)
        assert result["isError"]
        assert text(result) == message
      end

      assert event_count() == before
      assert Items.get_item!(batteries.id).name == "AA batteries"
    end
  end

  describe "rename_location" do
    test "renames a location, keeps its stock, and records the edit", %{
      secret: secret,
      user: user,
      garage: garage,
      towels: towels
    } do
      assert %{"location" => %{"id" => id, "name" => "Shed", "url" => url}} =
               call(secret, "rename_location", %{location_id: garage.id, name: " Shed "})[
                 "structuredContent"
               ]

      assert id == garage.id
      assert url =~ "/location/#{garage.id}"
      assert Locations.get(garage.id).name == "Shed"
      assert stock(towels) == %{garage.id => 4}

      # Setup's stock edits can share the rename's timestamp, so find the rename by action.
      edit =
        Enum.find(
          Audit.list_edits_for_location(garage.id),
          &Enum.any?(&1.events, fn event -> event.action == "location.updated" end)
        )

      assert AuditHelpers.edit_heading(edit) =~ "#{user.email} via Claude on phone"

      assert Enum.map(edit.events, & &1.changes) == [
               %{"name" => %{"from" => "Garage", "to" => "Shed"}}
             ]
    end

    test "refuses an unknown location or a bad name and writes nothing", %{
      secret: secret,
      garage: garage
    } do
      before = event_count()

      for {args, message} <- [
            {%{location_id: Ecto.UUID.generate(), name: "Shed"},
             "No location has that id. Call list_locations for ids."},
            {%{location_id: "garage", name: "Shed"},
             "No location has that id. Call list_locations for ids."},
            {%{location_id: garage.id, name: "Kitchen drawer"},
             "Nothing was changed: name has already been taken."},
            {%{location_id: garage.id, name: "  "}, "Nothing was changed: name can't be blank."}
          ] do
        result = call(secret, "rename_location", args)
        assert result["isError"]
        assert text(result) == message
      end

      assert event_count() == before
      assert Locations.get(garage.id).name == "Garage"
    end
  end

  describe "naming convention" do
    test "create_item and rename_item point to it, rename_location doesn't", %{secret: secret} do
      descriptions =
        Map.new(rpc(secret, "tools/list")["tools"], &{&1["name"], &1["description"]})

      assert descriptions["create_item"] =~ "get_naming_convention"
      assert descriptions["rename_item"] =~ "get_naming_convention"
      refute descriptions["rename_location"] =~ "naming_convention"
    end

    test "reads the seeded version, edits it as the agent, and refuses a stale version", %{
      secret: secret,
      user: user
    } do
      %{"naming_convention" => seeded} =
        call(secret, "get_naming_convention", %{})["structuredContent"]

      assert %{"version" => 0, "edited_by" => nil, "edited_at" => nil} = seeded
      assert seeded["text"] =~ "Boxes of Tissues"
      assert seeded["url"] =~ "/items/naming-convention"

      %{"naming_convention" => edited} =
        call(secret, "edit_naming_convention", %{text: "Use plurals.", version: 0})[
          "structuredContent"
        ]

      assert %{"version" => 1, "text" => "Use plurals."} = edited
      assert edited["edited_by"] == "#{user.email} via Claude on phone"
      assert Pinventory.NamingConvention.current().via_token_name == "Claude on phone"

      result = call(secret, "edit_naming_convention", %{text: "Stale", version: 0})

      assert result["isError"]
      assert text(result) =~ "now at version 1, not 0. Nothing was changed."
      assert Pinventory.NamingConvention.current().text == "Use plurals."
    end
  end

  describe "change_stock" do
    test "adds and sets one location's count and marks the edit as via the agent", %{
      secret: secret,
      user: user,
      towels: towels,
      garage: garage
    } do
      args = %{item_id: towels.id, location_id: garage.id}

      assert %{"from" => 4, "to" => 10} =
               call(secret, "change_stock", Map.put(args, :add, 6))["structuredContent"]

      assert %{"from" => 10, "to" => 0, "item" => %{"stock" => []}} =
               call(secret, "change_stock", Map.put(args, :set, 0))["structuredContent"]

      assert stock(towels) == %{}

      [latest | _] = Audit.list_edits_for_item(towels.id, limit: 1)
      assert AuditHelpers.edit_heading(latest) =~ "#{user.email} via Claude on phone"
    end

    test "refuses bad changes and writes nothing", %{
      secret: secret,
      towels: towels,
      garage: garage,
      drawer: drawer
    } do
      before = event_count()
      args = %{item_id: towels.id, location_id: garage.id}

      refusals = [
        {Map.put(args, :add, -5), "below zero: Garage has 4"},
        {Map.put(args, :add, 1_000_000), "more than 1,000,000"},
        {Map.merge(args, %{add: 1, set: 2}), "exactly one of add or set"},
        {args, "exactly one of add or set"},
        {%{args | item_id: Ecto.UUID.generate()} |> Map.put(:add, 1), "No item has that id"},
        {%{args | item_id: "nope"} |> Map.put(:add, 1), "No item has that id"},
        {%{args | location_id: Ecto.UUID.generate()} |> Map.put(:add, 1),
         "No location has that id"}
      ]

      for {call_args, message} <- refusals do
        result = call(secret, "change_stock", call_args)
        assert result["isError"], "expected an error for #{inspect(call_args)}"
        assert text(result) =~ message
      end

      assert invalid_params(secret, "change_stock", Map.put(args, :set, 1_000_001)) =~
               "maximum 1000000"

      assert stock(towels) == %{garage.id => 4}
      refute Map.has_key?(stock(towels), drawer.id)
      assert event_count() == before
    end
  end

  describe "move_stock" do
    test "moves stock as one edit with a line per location", %{
      secret: secret,
      batteries: batteries,
      drawer: drawer,
      garage: garage
    } do
      result =
        call(secret, "move_stock", %{
          item_id: batteries.id,
          from_location_id: drawer.id,
          to_location_id: garage.id,
          quantity: 8
        })["structuredContent"]

      assert result["from"] == %{"location_id" => drawer.id, "from" => 8, "to" => 0}
      assert result["to"] == %{"location_id" => garage.id, "from" => 24, "to" => 32}
      assert stock(batteries) == %{garage.id => 32}

      [edit | _] = Audit.list_edits_for_item(batteries.id, limit: 1)
      assert length(edit.events) == 2
      assert Enum.all?(edit.events, &(&1.metadata["via_token_name"] == "Claude on phone"))
    end

    test "a refused move changes neither location", %{
      secret: secret,
      batteries: batteries,
      drawer: drawer,
      garage: garage
    } do
      before = event_count()
      args = %{item_id: batteries.id, from_location_id: drawer.id, to_location_id: garage.id}

      refusals = [
        {Map.put(args, :quantity, 9), "not enough: Kitchen drawer has 8"},
        {%{args | to_location_id: drawer.id} |> Map.put(:quantity, 1), "the same"},
        {%{args | to_location_id: Ecto.UUID.generate()} |> Map.put(:quantity, 1),
         "No location has that id"}
      ]

      for {call_args, message} <- refusals do
        result = call(secret, "move_stock", call_args)
        assert result["isError"]
        assert text(result) =~ message
      end

      {:ok, _} =
        Items.change_stock(user_scope_fixture(), batteries.id, garage.id, {:set, 999_995})

      result = call(secret, "move_stock", Map.put(args, :quantity, 8))
      assert text(result) =~ "more than 1,000,000"

      assert invalid_params(secret, "move_stock", Map.put(args, :quantity, 0)) =~ "minimum 1"
      assert stock(batteries) == %{drawer.id => 8, garage.id => 999_995}
      assert event_count() == before + 1
    end
  end
end
