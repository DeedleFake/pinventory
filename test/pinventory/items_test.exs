defmodule Pinventory.ItemsTest do
  use Pinventory.DataCase, async: false

  alias Pinventory.Audit
  alias Pinventory.Items
  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations
  alias Pinventory.Repo

  import Pinventory.AccountsFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "create_item/3" do
    test "creates an item with a name only", %{scope: scope} do
      assert {:ok, %Item{name: "Hammer"}} = Items.create_item(scope, %{name: "Hammer"})
    end

    test "rejects a quantity over the max instead of storing it", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 1_000_000})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Items.update_item(scope, item, %{name: "Tape"}, %{garage.id => 1_000_001})

      assert %{quantity: [_]} = errors_on(changeset)
      assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 1_000_000}
    end

    test "returns an ItemLocation changeset when stock references a missing location", %{
      scope: scope
    } do
      fake_location_id = Ecto.UUID.generate()

      assert {:error, changeset} =
               Items.create_item(scope, %{name: "Orphan"}, %{fake_location_id => 1})

      assert %Ecto.Changeset{
               data: %ItemLocation{item_id: item_id, location_id: ^fake_location_id}
             } = changeset

      assert is_binary(item_id)
      assert errors_on(changeset) == %{location_id: ["does not exist"]}

      assert Items.list_items() == []
    end

    test "stores only positive stock rows", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, item} =
               Items.create_item(scope, %{name: "Screws"}, %{
                 garage.id => 5,
                 shelf.id => 0
               })

      stock = Items.stock_map(item)

      assert stock == %{garage.id => 5}
      assert Repo.aggregate(ItemLocation, :count) == 1
    end

    test "rejects a blank name", %{scope: scope} do
      assert {:error, changeset} = Items.create_item(scope, %{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects a duplicate name", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"})
      assert {:error, changeset} = Items.create_item(scope, %{name: "Drill"})
      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "trims name padding on create", %{scope: scope} do
      assert {:ok, %Item{name: "Hammer"}} = Items.create_item(scope, %{name: "  Hammer  "})
    end

    test "rejects a duplicate name after trim", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"})
      assert {:error, changeset} = Items.create_item(scope, %{name: "  Drill  "})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update_item/4" do
    test "renames an item and syncs stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
      {:ok, item} = Items.create_item(scope, %{name: "Nails"}, %{garage.id => 10})

      assert {:ok, updated} =
               Items.update_item(scope, item, %{name: "Box Nails"}, %{
                 garage.id => 0,
                 shelf.id => 4
               })

      assert updated.name == "Box Nails"
      assert Items.stock_map(updated) == %{shelf.id => 4}
      assert Repo.aggregate(ItemLocation, :count) == 1
    end

    test "clears all stock when every quantity is zero", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 2})

      assert {:ok, updated} = Items.update_item(scope, item, %{name: "Tape"}, %{garage.id => 0})

      assert Items.stock_map(updated) == %{}
      assert Repo.aggregate(ItemLocation, :count) == 0
    end

    test "rejects a negative quantity instead of clearing the stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 2})

      assert {:error, %Ecto.Changeset{}} =
               Items.update_item(scope, item, %{name: "Tape"}, %{garage.id => -3})

      assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 2}
    end

    test "returns an ItemLocation changeset when stock references a missing location", %{
      scope: scope
    } do
      {:ok, item} = Items.create_item(scope, %{name: "Kept"})
      fake_location_id = Ecto.UUID.generate()

      assert {:error, changeset} =
               Items.update_item(scope, item, %{name: "Kept"}, %{fake_location_id => 1})

      assert %Ecto.Changeset{
               data: %ItemLocation{item_id: item_id, location_id: ^fake_location_id}
             } = changeset

      assert item_id == item.id
      assert errors_on(changeset) == %{location_id: ["does not exist"]}
      assert Items.get_item!(item.id).name == "Kept"
      assert Items.stock_map(Items.get_item!(item.id)) == %{}
    end
  end

  describe "notes" do
    test "update_item/4 saves notes and records the old and new text", %{scope: scope} do
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})

      assert {:ok, %Item{notes: "Bottom shelf"}} =
               Items.update_item(scope, item, %{name: "Milk", notes: "Bottom shelf"})

      assert [%{action: "item.notes_changed", changes: changes, user_id: user_id}] =
               Audit.list_for_item(item.id) |> Enum.filter(&(&1.action == "item.notes_changed"))

      assert changes == %{"notes" => %{"from" => "", "to" => "Bottom shelf"}}
      assert user_id == scope.user.id
    end

    test "a rename and a notes edit in one save share an edit", %{scope: scope} do
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, _} = Items.update_item(scope, item, %{name: "Oat milk", notes: "Door"})

      [edit] =
        item.id
        |> Audit.list_edits_for_item()
        |> Enum.reject(&match?([%{action: "item.created"}], &1.events))

      assert Enum.map(edit.events, &{&1.action, &1.edit_seq}) == [
               {"item.updated", 0},
               {"item.notes_changed", 1}
             ]
    end

    test "browser line endings are stored as \\n", %{scope: scope} do
      {:ok, item} = Items.create_item(scope, %{name: "Milk", notes: "a\r\nb"})

      assert item.notes == "a\nb"
    end

    test "note_versions/1 lists every saved version, oldest first", %{scope: scope} do
      other = user_scope_fixture()
      {:ok, item} = Items.create_item(scope, %{name: "Milk", notes: "Fridge"})
      {:ok, item} = Items.update_item(other, item, %{notes: "Basement fridge"})
      {:ok, _} = Items.update_item(scope, item, %{name: "Whole milk"})

      versions = Items.note_versions(item.id)

      assert Enum.map(versions, &{&1.number, &1.text, &1.user && &1.user.id}) == [
               {0, "", nil},
               {1, "Fridge", scope.user.id},
               {2, "Basement fridge", other.user.id}
             ]
    end

    test "update_item/4 rejects a save from an out-of-date copy", %{scope: scope} do
      other = user_scope_fixture()
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, _} = Items.update_item(other, item, %{notes: "Their note"})

      assert Items.update_item(scope, item, %{notes: "My note"}) == {:error, :stale}
      assert Items.get_item!(item.id).notes == "Their note"
      assert length(Items.note_versions(item.id)) == 2
    end

    test "a stock-only save detects someone else's stock save", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, _} = Items.update_item(scope, item, %{}, %{garage.id => 5})

      assert Items.update_item(scope, item, %{}, %{garage.id => 2}) == {:error, :stale}
      assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 5}
    end

    test "a save to one section goes through after someone else saved another", %{scope: scope} do
      other = user_scope_fixture()
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Milk", notes: "Old"}, %{garage.id => 1})
      {:ok, _} = Items.update_item(other, item, %{name: "Whole milk"}, Items.stock_map(item))

      assert {:ok, saved} = Items.update_item(scope, item, %{}, %{garage.id => 4})
      assert {saved.name, Items.stock_map(saved)} == {"Whole milk", %{garage.id => 4}}

      assert {:ok, saved} = Items.update_item(scope, item, %{notes: "New"}, %{garage.id => 1})

      assert {saved.name, saved.notes, Items.stock_map(saved)} ==
               {"Whole milk", "New", %{garage.id => 4}}

      assert Items.update_item(scope, item, %{name: "Skim milk"}, %{garage.id => 1}) ==
               {:error, :stale}
    end

    test "a save fails whole when any section it changes is out of date", %{scope: scope} do
      other = user_scope_fixture()
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, _} = Items.update_item(other, item, %{name: "Whole milk"})

      assert Items.update_item(scope, item, %{name: "Skim milk"}, %{garage.id => 3}) ==
               {:error, :stale}

      assert Items.stock_map(Items.get_item!(item.id)) == %{}
    end
  end

  describe "get_item/1" do
    test "returns nil when the item does not exist" do
      assert Items.get_item(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_item!/1" do
    test "preloads item_locations", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Level"}, %{garage.id => 1})

      loaded = Items.get_item!(item.id)

      assert Ecto.assoc_loaded?(loaded.item_locations)
      assert hd(loaded.item_locations).quantity == 1
    end
  end

  describe "suggest_items/1" do
    test "returns empty list for blank or whitespace-only queries", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      assert Items.suggest_items("") == []
      assert Items.suggest_items("   ") == []
      assert Items.suggest_items("\t\n") == []
    end

    test "returns matching items by prefix", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Phillips screwdriver"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Flat screwdriver"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert "Phillips screwdriver" in names
      assert "Flat screwdriver" in names
      refute "Hammer" in names
    end

    test "treats LIKE special characters in the query as literals", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "100% wool"})
      assert {:ok, _} = Items.create_item(scope, %{name: "100x wool"})
      assert {:ok, _} = Items.create_item(scope, %{name: "under_score"})
      assert {:ok, _} = Items.create_item(scope, %{name: "path\\to"})
      assert {:ok, _} = Items.create_item(scope, %{name: "plain item"})
      assert {:ok, _} = Items.create_item(scope, %{name: "quote\"mark"})

      percent_only = Enum.map(Items.suggest_items("%"), & &1.name)
      assert percent_only == ["100% wool"]

      percent_names = Enum.map(Items.suggest_items("100%"), & &1.name)
      assert "100% wool" in percent_names
      refute "100x wool" in percent_names

      underscore_names = Enum.map(Items.suggest_items("under_score"), & &1.name)
      assert "under_score" in underscore_names

      slash_names = Enum.map(Items.suggest_items("path\\t"), & &1.name)
      assert "path\\to" in slash_names
      refute "plain item" in slash_names

      quote_names = Enum.map(Items.suggest_items("quote\"m"), & &1.name)
      assert "quote\"mark" in quote_names
    end

    test "matches short prefixes", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Saw"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Sandpaper"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.suggest_items("sa"), & &1.name)

      assert "Sandpaper" in names
      assert "Saw" in names
      refute "Hammer" in names
    end

    test "ranks prefix matches above non-prefix contains", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Phillips screwdriver set"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Screwdriver"})

      names = Enum.map(Items.suggest_items("screw"), & &1.name)

      assert names == ["Screwdriver", "Phillips screwdriver set"]
    end

    test "ranks prefix matches above non-prefix contains for short queries", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Saw"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Handsaw"})

      names = Enum.map(Items.suggest_items("sa"), & &1.name)

      assert names == ["Saw", "Handsaw"]
    end

    test "matches mixed-case queries case-insensitively for ASCII", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Hex Bolt"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.suggest_items("HEX"), & &1.name)

      assert names == ["Hex Bolt"]
    end

    test "a renamed item matches its new name and not its old one", %{scope: scope} do
      assert {:ok, item} = Items.create_item(scope, %{name: "Old Widget"})

      assert Enum.map(Items.suggest_items("old"), & &1.name) == ["Old Widget"]

      assert {:ok, _} = Items.update_item(scope, item, %{name: "New Gadget"}, %{})

      refute "Old Widget" in Enum.map(Items.suggest_items("old"), & &1.name)
      assert Enum.map(Items.suggest_items("new"), & &1.name) == ["New Gadget"]
      assert Enum.map(Items.suggest_items("gadget"), & &1.name) == ["New Gadget"]
    end

    test "a deleted item no longer matches", %{scope: scope} do
      assert {:ok, item} = Items.create_item(scope, %{name: "Disposable Widget"})

      assert Enum.map(Items.suggest_items("disposable"), & &1.name) == ["Disposable Widget"]

      assert {:ok, _} = Items.delete_item(scope, item)

      assert Items.suggest_items("disposable") == []
    end
  end

  describe "name search" do
    defp create_items(scope, names) do
      for name <- names, do: {:ok, _} = Items.create_item(scope, %{name: name})
    end

    defp suggest(text), do: Enum.map(Items.suggest_items(text), & &1.name)

    test "matches typed letters in order, with gaps across words and symbols", %{scope: scope} do
      create_items(scope, ["Paint brush", "Paper towels", "Handsaw", "Candles", "Candy"])

      assert suggest("pntbrsh") == ["Paint brush"]
      assert suggest("pant brsh") == ["Paint brush"]
      assert suggest("candy") == ["Candy"]
    end

    test "does not match letters typed out of order", %{scope: scope} do
      create_items(scope, ["Paper towels", "Towel rack"])

      assert suggest("towle") == []
    end

    test "requires every term, in any order", %{scope: scope} do
      create_items(scope, ["Bolt 10mm hex", "Bolt, 10mm", "Hex key"])

      assert suggest("hex bolt") == ["Bolt 10mm hex"]
      assert suggest("bolt hex") == ["Bolt 10mm hex"]
    end

    test "matches short terms mixed with longer ones", %{scope: scope} do
      create_items(scope, ["Bolt 10mm hex", "Bolt, 10mm", ~s(Screws, #8 x 1/2"), "Hammer"])

      assert Enum.sort(suggest("10 bo")) == ["Bolt 10mm hex", "Bolt, 10mm"]
      assert suggest("x 8") == [~s(Screws, #8 x 1/2")]
    end

    test "ranks an exact word above the same letters inside a word", %{scope: scope} do
      create_items(scope, ["Handsaw", "Saw", "Saw blade set"])

      assert suggest("saw") == ["Saw", "Saw blade set", "Handsaw"]
      assert suggest("sa") == ["Saw", "Saw blade set", "Handsaw"]
    end

    test "ranks whole words above a run inside one word", %{scope: scope} do
      create_items(scope, ["Papertowel", "Paper towels"])

      assert suggest("towel paper") == ["Paper towels", "Papertowel"]
      assert suggest("papr towl") == ["Paper towels", "Papertowel"]
    end

    test "treats symbols in names as word boundaries when ranking", %{scope: scope} do
      create_items(scope, ["fuzzyfinder", "fuzzy-finder", "1000 screws", "100% wool socks"])

      assert suggest("ff") == ["fuzzy-finder", "fuzzyfinder"]
      assert suggest("100") == ["100% wool socks", "1000 screws"]
    end

    test "requires symbols that were typed", %{scope: scope} do
      create_items(scope, ["Bolt, 10mm", "Bolt 10mm hex", "O'Brien wrench", ~s(Screws, #8 x 1/2")])

      assert suggest("bolt,") == ["Bolt, 10mm"]
      assert Enum.sort(suggest("bolt")) == ["Bolt 10mm hex", "Bolt, 10mm"]
      assert suggest("obrien") == ["O'Brien wrench"]
      assert suggest("o'brien") == ["O'Brien wrench"]
      assert suggest("#8 screw") == [~s(Screws, #8 x 1/2")]
    end

    test "ranks terms with symbols by the same word boundaries", %{scope: scope} do
      create_items(scope, [
        ~s(Screws, #8 x 1/2"),
        "1 inch / 2 pack",
        "x100% y",
        "Big 100% cotton tee"
      ])

      assert suggest("1/2") == [~s(Screws, #8 x 1/2"), "1 inch / 2 pack"]
      assert suggest("100%") == ["Big 100% cotton tee", "x100% y"]
    end

    test "treats wildcards, backslashes, and quotes as plain characters", %{scope: scope} do
      create_items(scope, [
        "100% wool",
        "100x wool",
        "under_score",
        "underscore",
        "path\\to",
        ~s(quote"mark),
        "size [m]",
        "what?",
        "a*b",
        "plain item"
      ])

      assert suggest("1%w") == ["100% wool"]
      assert suggest("_") == ["under_score"]
      assert suggest("u_s") == ["under_score"]
      assert suggest("\\") == ["path\\to"]
      assert suggest(~s(")) == [~s(quote"mark)]
      assert suggest("(") == []
      assert suggest("*") == ["a*b"]
      assert suggest("?") == ["what?"]
      assert suggest("[m") == ["size [m]"]
      assert suggest("t?") == ["what?"]
      assert suggest("' OR 1=1 --") == []
    end

    test "folds ASCII case only", %{scope: scope} do
      create_items(scope, ["Café", "HEX bolt"])

      assert suggest("hex") == ["HEX bolt"]
      assert suggest("café") == ["Café"]
      assert suggest("CAFÉ") == []
      assert suggest("cafe") == []
    end

    test "list_items filters with the same matching and ranking", %{scope: scope} do
      create_items(scope, ["Paint brush", "Brush paint", "Hammer", "Bags of Almonds", "Salmon"])

      filter = fn text -> Enum.map(Items.list_items(filter: text), & &1.name) end

      assert filter.("pnt brsh") == ["Brush paint", "Paint brush"]
      assert filter.("pntbrsh") == ["Paint brush"]
      assert filter.("candy") == []
      assert filter.("salmon") == ["Salmon", "Bags of Almonds"]
      assert filter.("SALMON") == ["Salmon", "Bags of Almonds"]
      assert filter.("salm") == ["Salmon", "Bags of Almonds"]
      assert filter.("almonds") == ["Bags of Almonds"]
    end
  end

  describe "delete_item/2" do
    test "deletes the item and cascaded stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Disposable"}, %{garage.id => 4})

      assert {:ok, _} = Items.delete_item(scope, item)
      assert_raise Ecto.NoResultsError, fn -> Items.get_item!(item.id) end
      assert Repo.get_by(ItemLocation, item_id: item.id) == nil
    end
  end

  describe "list_items/1" do
    test "returns stock totals and location counts", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, _} =
               Items.create_item(scope, %{name: "Screws"}, %{garage.id => 5, shelf.id => 3})

      assert {:ok, _} = Items.create_item(scope, %{name: "Empty Box"})

      by_name = Map.new(Items.list_items(), &{&1.name, &1})

      assert by_name["Screws"].total_quantity == 8
      assert by_name["Screws"].location_count == 2
      assert by_name["Empty Box"].total_quantity == 0
      assert by_name["Empty Box"].location_count == 0
    end

    test "filters by name substring", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Box Nails"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Hammer"})

      names = Enum.map(Items.list_items(filter: "nail"), & &1.name)

      assert names == ["Box Nails"]
    end

    test "trims whitespace-only filter to no filter", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Alpha"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Beta"})

      names = Enum.map(Items.list_items(filter: "   "), & &1.name)

      assert names == ["Alpha", "Beta"]
    end

    test "filters by location with stock", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(scope, %{name: "Tape"}, %{shelf.id => 2})
      assert {:ok, _} = Items.create_item(scope, %{name: "Empty"})

      names = Enum.map(Items.list_items(location_id: garage.id), & &1.name)

      assert names == ["Drill"]
    end

    test "orders items by name", %{scope: scope} do
      assert {:ok, _} = Items.create_item(scope, %{name: "Zebra"})
      assert {:ok, _} = Items.create_item(scope, %{name: "Apple"})

      assert Enum.map(Items.list_items(), & &1.name) == ["Apple", "Zebra"]
    end
  end

  describe "list_items_at_location/1" do
    test "returns quantity at this location only", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, item} =
               Items.create_item(scope, %{name: "Screws"}, %{garage.id => 2, shelf.id => 5})

      [at_garage] = Items.list_items_at_location(garage.id)

      assert at_garage.id == item.id
      assert at_garage.quantity == 2

      [filtered] = Items.list_items(location_id: garage.id)
      assert filtered.total_quantity == 7
    end

    test "excludes items with no stock at the location", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      assert {:ok, _} = Items.create_item(scope, %{name: "Drill"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(scope, %{name: "Tape"}, %{shelf.id => 2})
      assert {:ok, _} = Items.create_item(scope, %{name: "Empty"})

      names = Enum.map(Items.list_items_at_location(garage.id), & &1.name)

      assert names == ["Drill"]
    end

    test "orders items by name", %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})

      assert {:ok, _} = Items.create_item(scope, %{name: "Zebra"}, %{garage.id => 1})
      assert {:ok, _} = Items.create_item(scope, %{name: "Apple"}, %{garage.id => 1})

      assert Enum.map(Items.list_items_at_location(garage.id), & &1.name) == [
               "Apple",
               "Zebra"
             ]
    end

    test "returns an empty list for a location with no stock", %{scope: scope} do
      {:ok, empty} = Locations.create(scope, %{name: "Empty"})

      assert Items.list_items_at_location(empty.id) == []
    end
  end

  describe "search_items/2" do
    defp item!(scope, name, notes \\ "") do
      {:ok, item} = Items.create_item(scope, %{name: name, notes: notes})
      item
    end

    defp search_names(terms), do: terms |> Items.search_items() |> Enum.map(& &1.name)

    test "matches words as written, so a singular word finds its plural but not the reverse",
         %{scope: scope} do
      item!(scope, "Paper Towel")
      item!(scope, "Paper Towels, select-a-size")
      item!(scope, "Hammer")

      assert search_names(["towel"]) == ["Paper Towel", "Paper Towels, select-a-size"]
      assert search_names(["TOWELS"]) == ["Paper Towels, select-a-size"]
    end

    test "matches words in any order within the name", %{scope: scope} do
      item!(scope, "Paper towels", "Bounty, 6-roll packs")
      item!(scope, "Kitchen trash bags", "13 gallon")

      assert search_names(["towels paper"]) == ["Paper towels"]
      assert search_names(["bag kitchen trash"]) == ["Kitchen trash bags"]
      assert search_names(["kitchen towel"]) == []
    end

    test "does not search notes", %{scope: scope} do
      item!(scope, "Paper towels", "Bounty, 6-roll packs")
      item!(scope, "Dish soap", "next to the paper towel holder")

      assert search_names(["bounty"]) == []
      assert search_names(["paper towel"]) == ["Paper towels"]
    end

    test "matches any of several terms, more matched terms first", %{scope: scope} do
      item!(scope, "Paper towels")
      item!(scope, "Kitchen paper towels")
      item!(scope, "Kitchen roll")
      item!(scope, "Hammer")

      assert search_names(["paper towel", "kitchen", "roll"]) ==
               ["Kitchen paper towels", "Kitchen roll", "Paper towels"]
    end

    test "treats wildcards as plain text", %{scope: scope} do
      item!(scope, "100% cotton rags")
      item!(scope, "Hammer")

      assert search_names(["100%"]) == ["100% cotton rags"]
      assert search_names(["_"]) == []
      assert search_names(["*"]) == []
    end

    test "matches typed letters in order, like the items filter", %{scope: scope} do
      item!(scope, "Paint brush")
      item!(scope, "Handsaw")

      assert search_names(["pntbrsh"]) == ["Paint brush"]
      assert search_names(["candy"]) == []
    end

    test "blank terms find nothing and respect the limit", %{scope: scope} do
      for n <- 1..3, do: item!(scope, "Screw #{n}")

      assert Items.search_items([]) == []
      assert Items.search_items(["", "  "]) == []
      assert length(Items.search_items(["screw"], limit: 2)) == 2
    end
  end

  describe "change_stock/4 and move_stock/5" do
    setup %{scope: scope} do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
      {:ok, item} = Items.create_item(scope, %{name: "Screws"}, %{garage.id => 5})
      %{garage: garage, shelf: shelf, item: item}
    end

    test "changes one location and keeps the others", %{scope: scope} = ctx do
      {:ok, _} = Items.change_stock(scope, ctx.item.id, ctx.shelf.id, {:set, 3})

      assert {:ok, %{from: 5, to: 2}} =
               Items.change_stock(scope, ctx.item.id, ctx.garage.id, {:add, -3})

      assert Items.stock_map(Items.get_item!(ctx.item.id)) == %{
               ctx.garage.id => 2,
               ctx.shelf.id => 3
             }
    end

    test "a browser edit carries no agent marker", %{scope: scope} = ctx do
      {:ok, _} = Items.change_stock(scope, ctx.item.id, ctx.garage.id, {:add, 1})

      [edit | _] = Audit.list_edits_for_item(ctx.item.id, limit: 1)
      assert [%{metadata: metadata}] = edit.events
      refute Map.has_key?(metadata, "via_token_name")
    end

    test "an agent edit records the token", ctx do
      {:ok, {_, token}} = Pinventory.Accounts.create_api_token(ctx.scope.user, "Claude on phone")
      agent = Pinventory.Accounts.Scope.for_api_token(ctx.scope.user, token)

      {:ok, _} = Items.move_stock(agent, ctx.item.id, ctx.garage.id, ctx.shelf.id, 2)

      [edit | _] = Audit.list_edits_for_item(ctx.item.id, limit: 1)
      assert length(edit.events) == 2

      assert Enum.all?(edit.events, fn event ->
               event.metadata["via_token_id"] == token.id and
                 event.metadata["via_token_name"] == "Claude on phone"
             end)

      assert PinventoryWeb.AuditHelpers.last_stock_label(hd(edit.events)) =~
               "#{ctx.scope.user.email} via Claude on phone · "
    end

    test "a refused move writes nothing", %{scope: scope} = ctx do
      assert {:error, {:not_enough, 5}} =
               Items.move_stock(scope, ctx.item.id, ctx.garage.id, ctx.shelf.id, 6)

      assert {:error, :same_location} =
               Items.move_stock(scope, ctx.item.id, ctx.garage.id, ctx.garage.id, 1)

      assert Items.stock_map(Items.get_item!(ctx.item.id)) == %{ctx.garage.id => 5}
      assert length(Audit.list_edits_for_item(ctx.item.id)) == 1
    end
  end
end
