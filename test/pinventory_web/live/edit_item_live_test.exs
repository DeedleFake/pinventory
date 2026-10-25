defmodule PinventoryWeb.EditItemLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pinventory.Items
  alias Pinventory.Locations

  import Pinventory.AccountsFixtures

  setup :register_and_log_in_user

  test "renders the new item form with locations ordered by name", %{conn: conn, scope: scope} do
    {:ok, _} = Locations.create(scope, %{name: "Zebra"})
    {:ok, _} = Locations.create(scope, %{name: "Alpha"})

    {:ok, view, html} = live(conn, ~p"/item")

    assert html =~ "New item"
    assert has_element?(view, ~s|#nav-items[aria-current="page"]|)
    assert has_element?(view, "#item-form")
    refute has_element?(view, "#item-delete")
    refute has_element?(view, "#item-delete-modal")
    assert has_element?(view, ~s(#item-total[data-stock-dirty="false"]))
    assert has_element?(view, "#item-total-value", "0")
    assert html =~ ~r/Alpha[\s\S]*Zebra/
  end

  test "creates an item with stock and navigates to edit", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

    {:ok, view, _html} = live(conn, ~p"/item")

    set_quantity(view, garage.id, 3)

    view
    |> form("#item-form", item: %{name: "Hammer"})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path =~ ~r"^/item/"
    assert flash["info"] == "Item created"

    {:ok, view, html} = live(conn, path)
    assert html =~ "Edit item"
    assert_quantity(view, garage.id, 3)
    assert_quantity(view, shelf.id, 0)
    assert has_element?(view, ~s(#item-total[data-stock-dirty="false"]))
    assert has_element?(view, "#item-total-value", "3")

    [item] = Items.list_items()
    assert item.name == "Hammer"
    assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 3}
  end

  test "shows validation errors for a blank name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/item")

    html =
      view
      |> form("#item-form", item: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "edits an existing item name and quantities", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
    {:ok, item} = Items.create_item(scope, %{name: "Nails"}, %{garage.id => 5})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    assert_quantity(view, garage.id, 5)
    assert has_element?(view, "#item-save:disabled")

    set_quantity(view, garage.id, 2)
    set_quantity(view, shelf.id, 4)

    view
    |> form("#item-form", item: %{name: "Box Nails"})
    |> render_submit()

    html = render(view)
    assert html =~ "Item saved"
    assert has_element?(view, "#item-save:disabled")
    assert_quantity(view, garage.id, 2)
    assert_quantity(view, shelf.id, 4)
    assert has_element?(view, ~s(#item-total[data-stock-dirty="false"]))
    assert has_element?(view, "#item-total-value", "6")

    updated = Items.get_item!(item.id)
    assert updated.name == "Box Nails"
    assert Items.stock_map(updated) == %{garage.id => 2, shelf.id => 4}
  end

  test "adjust buttons change draft quantities without saving", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    assert has_element?(view, ~s(#item-total[data-stock-dirty="false"]))
    assert has_element?(view, "#item-total-value", "1")

    view
    |> element("#quantity-inc-#{garage.id}")
    |> render_click()

    assert_quantity(view, garage.id, 2)
    assert has_element?(view, ~s(#item-total[data-stock-dirty="true"]))
    assert has_element?(view, ~s(#item-total[data-total-changed="true"]))
    assert has_element?(view, "#item-total-was", "1")
    assert has_element?(view, "#item-total-value", "2")
    assert has_element?(view, "#item-total-hint", "total changed")
    refute has_element?(view, "#item-save:disabled")

    # Not saved yet
    assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 1}
  end

  test "shows was and now totals when stock rebalance keeps the total the same", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
    {:ok, item} = Items.create_item(scope, %{name: "Washers"}, %{garage.id => 5})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    set_quantity(view, garage.id, 3)
    set_quantity(view, shelf.id, 2)

    assert has_element?(view, ~s(#item-total[data-stock-dirty="true"]))
    assert has_element?(view, ~s(#item-total[data-total-changed="false"]))
    assert has_element?(view, "#item-total-was", "5")
    assert has_element?(view, "#item-total-value", "5")
    assert has_element?(view, "#item-total-hint", "total unchanged")
  end

  test "marks dirty quantity rows when stock differs from baseline", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
    {:ok, item} = Items.create_item(scope, %{name: "Bolts"}, %{garage.id => 2, shelf.id => 4})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    refute has_element?(view, ~s(#location-row-#{garage.id}[data-dirty="true"]))
    refute has_element?(view, ~s(#location-row-#{shelf.id}[data-dirty="true"]))

    set_quantity(view, garage.id, 5)

    assert has_element?(view, ~s(#location-row-#{garage.id}[data-dirty="true"]))
    refute has_element?(view, ~s(#location-row-#{shelf.id}[data-dirty="true"]))
    assert has_element?(view, "#location-row-#{garage.id}.border-primary")

    set_quantity(view, garage.id, 2)

    refute has_element?(view, ~s(#location-row-#{garage.id}[data-dirty="true"]))
  end

  test "set_quantity updates only the edited location when multiple locations exist", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})
    {:ok, item} = Items.create_item(scope, %{name: "Screws"}, %{garage.id => 1, shelf.id => 9})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    # Real browser form change: _target + quantities map, no phx-value location-id.
    view
    |> element("#quantity-#{garage.id}")
    |> render_change(%{
      "_target" => ["quantities", garage.id],
      "quantities" => %{garage.id => "4"}
    })

    assert_quantity(view, garage.id, 4)
    assert_quantity(view, shelf.id, 9)
    assert has_element?(view, "#item-total-was", "10")
    assert has_element?(view, "#item-total-value", "13")
  end

  for raw <- ["-3", "1.5", "", "abc", "1000001"] do
    test "rejects quantity #{inspect(raw)} instead of clearing that location's stock", %{
      conn: conn,
      scope: scope
    } do
      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, item} = Items.create_item(scope, %{name: "Towels"}, %{garage.id => 5})

      {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

      set_quantity(view, garage.id, unquote(raw))

      view |> form("#item-form", item: %{name: "Paper towels"}) |> render_submit()

      updated = Items.get_item!(item.id)
      assert Items.stock_map(updated) == %{garage.id => 5}
      assert updated.name == "Towels"

      assert has_element?(view, "#quantity-error-#{garage.id}", "Enter a whole number")
      assert has_element?(view, ~s(#quantity-#{garage.id}[aria-invalid="true"]))
      assert has_element?(view, "#item-save[disabled]")

      set_quantity(view, garage.id, 6)

      refute has_element?(view, "#quantity-error-#{garage.id}")
      assert has_element?(view, "#item-total-value", "6")
    end
  end

  test "a typed 0 still removes stock at that location", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, item} = Items.create_item(scope, %{name: "Towels"}, %{garage.id => 5})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    set_quantity(view, garage.id, 0)
    refute has_element?(view, "#quantity-error-#{garage.id}")
    view |> form("#item-form") |> render_submit()

    assert Items.stock_map(Items.get_item!(item.id)) == %{}
  end

  test "stock controls live in a stock form separate from the name form", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})

    {:ok, view, _html} = live(conn, ~p"/item")

    assert has_element?(view, "#item-form")
    assert has_element?(view, "#item-stock-form")
    assert has_element?(view, ~s(#item-save[form="item-form"]))
    assert has_element?(view, "#item-stock-form #quantity-#{garage.id}")
    refute has_element?(view, "#item-form #quantity-#{garage.id}")
    refute has_element?(view, ~s(#item-stock-form button[type="submit"]))
  end

  test "stock save failures keep the name form and flash an error", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})

    {:ok, view, _html} = live(conn, ~p"/item")

    view
    |> form("#item-form", item: %{name: "Orphan stock"})
    |> render_change()

    set_quantity(view, garage.id, 2)

    # Delete the location after draft stock is set so stock insert hits an FK error.
    Pinventory.Repo.delete!(garage)

    html =
      view
      |> form("#item-form", item: %{name: "Orphan stock"})
      |> render_submit()

    assert html =~ "Could not save item stock: location does not exist"
    assert has_element?(view, ~s(#item_name[value="Orphan stock"]))
    assert Items.list_items() == []
  end

  test "shows name suggestions and navigates on select", %{conn: conn, scope: scope} do
    {:ok, existing} = Items.create_item(scope, %{name: "Screwdriver set"})

    {:ok, view, _html} = live(conn, ~p"/item")

    view
    |> element("#item_name")
    |> render_focus()

    view
    |> form("#item-form", item: %{name: "Screw"})
    |> render_change()

    assert has_element?(view, "#item-suggestions")
    assert has_element?(view, "#item-suggestion-#{existing.id}", "Screwdriver set")

    view
    |> element("#item-suggestion-#{existing.id}")
    |> render_click()

    assert_redirect(view, "/item/#{existing.id}")
  end

  test "hides name suggestions when the name field is blurred", %{conn: conn, scope: scope} do
    {:ok, _existing} = Items.create_item(scope, %{name: "Screwdriver set"})

    {:ok, view, _html} = live(conn, ~p"/item")

    view
    |> element("#item_name")
    |> render_focus()

    view
    |> form("#item-form", item: %{name: "Screw"})
    |> render_change()

    assert has_element?(view, "#item-suggestions")

    view
    |> element("#item_name")
    |> render_blur()

    send(view.pid, :hide_name_suggestions)
    html = render(view)

    refute html =~ ~s(id="item-suggestions")
  end

  test "does not reopen suggestions when editing quantities after blur", %{
    conn: conn,
    scope: scope
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, _existing} = Items.create_item(scope, %{name: "Paper towels"})

    {:ok, view, _html} = live(conn, ~p"/item")

    view
    |> element("#item_name")
    |> render_focus()

    view
    |> form("#item-form", item: %{name: "Paper"})
    |> render_change()

    assert has_element?(view, "#item-suggestions")

    view
    |> element("#item_name")
    |> render_blur()

    send(view.pid, :hide_name_suggestions)
    _ = render(view)

    set_quantity(view, garage.id, 2)

    refute has_element?(view, "#item-suggestions")
  end

  test "does not show suggestions while editing", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Wrench"})
    {:ok, _other} = Items.create_item(scope, %{name: "Wrench set"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item_name")
    |> render_focus()

    view
    |> form("#item-form", item: %{name: "Wrench"})
    |> render_change()

    refute has_element?(view, "#item-suggestions")
  end

  test "marks the form dirty and pushes unsaved-changes events", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Level"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    assert has_element?(view, ~s(#item-page[phx-hook="UnsavedChanges"][data-dirty="false"]))

    view
    |> form("#item-form", item: %{name: "Spirit Level"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})
    assert has_element?(view, ~s(#item-page[data-dirty="true"]))
    refute has_element?(view, "#item-save:disabled")

    view
    |> form("#item-form", item: %{name: "Level"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
    assert has_element?(view, ~s(#item-page[data-dirty="false"]))
    assert has_element?(view, "#item-save:disabled")
  end

  test "highlights an unsaved name change on edit", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, item} = Items.create_item(scope, %{name: "Level"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    assert has_element?(view, ~s(#item-name-section[data-name-dirty="false"]))
    refute has_element?(view, "#item-name-hint")

    view
    |> form("#item-form", item: %{name: "Spirit Level"})
    |> render_change()

    assert has_element?(view, ~s(#item-name-section[data-name-dirty="true"]))
    assert has_element?(view, "#item-name-hint", "Unsaved name change")
    assert has_element?(view, "#item-name-hint", "Level")

    # Quantity-only edits do not mark the name as dirty.
    set_quantity(view, garage.id, 2)

    assert has_element?(view, ~s(#item-name-section[data-name-dirty="true"]))
    assert has_element?(view, ~s(#item-total[data-stock-dirty="true"]))

    view
    |> form("#item-form", item: %{name: "Level"})
    |> render_change()

    assert has_element?(view, ~s(#item-name-section[data-name-dirty="false"]))
    refute has_element?(view, "#item-name-hint")
    assert has_element?(view, ~s(#item-total[data-stock-dirty="true"]))
  end

  test "does not mark name dirty on the new item page while typing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/item")

    assert has_element?(view, ~s(#item-name-section[data-name-dirty="false"]))

    view
    |> form("#item-form", item: %{name: "Hammer"})
    |> render_change()

    assert has_element?(view, ~s(#item-name-section[data-name-dirty="false"]))
    refute has_element?(view, "#item-name-hint")
  end

  test "shows item activity timeline grouped by edit with actor and events", %{
    conn: conn,
    scope: scope,
    user: user
  } do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

    {:ok, item} =
      Items.create_item(scope, %{name: "Level"}, %{garage.id => 1, shelf.id => 2})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    assert has_element?(view, "#item-activity")
    assert has_element?(view, "#item-activity-list")
    refute has_element?(view, "#item-activity-empty")

    edits = Pinventory.Audit.list_edits_for_item(item.id)
    assert edits != []

    create_edit =
      Enum.find(edits, fn edit ->
        Enum.any?(edit.events, &(&1.action == "item.created"))
      end)

    assert create_edit
    # item.created + two stock.changed under one edit_id
    assert length(create_edit.events) == 3

    assert has_element?(view, "#item-edit-#{create_edit.edit_id}")
    assert has_element?(view, "#item-edit-#{create_edit.edit_id}", user.email)
    assert has_element?(view, "#item-edit-#{create_edit.edit_id}", "stock at 2 locations")

    for event <- create_edit.events do
      assert has_element?(view, "#item-event-#{event.id}")
    end

    created = Enum.find(create_edit.events, &(&1.action == "item.created"))
    stock = Enum.find(create_edit.events, &(&1.action == "stock.changed"))

    assert created
    assert stock
    assert has_element?(view, "#item-event-#{created.id}", "Created item")
    refute has_element?(view, ~s|a#item-event-#{created.id}|)
    assert has_element?(view, "#item-event-#{stock.id}", "Stock at")

    garage_stock = Enum.find(create_edit.events, &(&1.location_id == garage.id))
    shelf_stock = Enum.find(create_edit.events, &(&1.location_id == shelf.id))

    assert has_element?(
             view,
             ~s|a#item-event-#{garage_stock.id}[href="/location/#{garage.id}"]|
           )

    assert has_element?(
             view,
             ~s|a#item-event-#{shelf_stock.id}[href="/location/#{shelf.id}"]|
           )
  end

  test "shows empty locations state with a link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/item")

    assert has_element?(view, "#item-locations-empty")
    assert has_element?(view, "a[href='/locations']", "Add locations")
  end

  test "redirects when the item does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/item/#{Ecto.UUID.generate()}")

    assert path == "/"
    assert flash["error"] == "Item not found."
  end

  test "shows delete on edit and disables it when the name is unsaved", %{
    conn: conn,
    scope: scope
  } do
    {:ok, item} = Items.create_item(scope, %{name: "Level"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    assert has_element?(view, "#item-delete")
    refute has_element?(view, "#item-delete:disabled")
    refute has_element?(view, "#item-delete-reason")
    refute has_element?(view, "#item-delete-modal")

    view
    |> form("#item-form", item: %{name: "Spirit Level"})
    |> render_change()

    assert has_element?(view, "#item-delete:disabled")
    assert has_element?(view, "#item-delete-reason", "Save or revert the name first.")
    refute has_element?(view, "#item-delete-modal")
    assert Items.get_item!(item.id).name == "Level"
  end

  test "allows delete when only stock is unsaved", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    set_quantity(view, garage.id, 4)

    refute has_element?(view, "#item-delete:disabled")
    refute has_element?(view, "#item-delete-reason")
  end

  test "opens a name-confirm modal and deletes the item", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

    {:ok, item} =
      Items.create_item(scope, %{name: "Gone"}, %{garage.id => 5, shelf.id => 3})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item-delete")
    |> render_click()

    assert has_element?(view, "#item-delete-modal")
    assert has_element?(view, "#item-delete-form")
    assert has_element?(view, "#item-delete-impact", "Gone")
    assert has_element?(view, "#item-delete-impact-total", "8")
    assert has_element?(view, "#item-delete-impact-locations", "2")
    assert has_element?(view, ~s(#item-delete-confirm[autocomplete="off"]))
    assert has_element?(view, ~s(#item-delete-confirm[spellcheck="false"]))
    assert has_element?(view, "#item-delete-confirm-submit:disabled")

    view
    |> form("#item-delete-form", delete: %{name: "Gon"})
    |> render_change()

    assert has_element?(view, "#item-delete-confirm-submit:disabled")

    view
    |> form("#item-delete-form", delete: %{name: "Gone"})
    |> render_change()

    refute has_element?(view, "#item-delete-confirm-submit:disabled")

    view
    |> form("#item-delete-form", delete: %{name: "Gone"})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/"
    assert flash["info"] == "Item deleted"

    assert_raise Ecto.NoResultsError, fn -> Items.get_item!(item.id) end
    assert Pinventory.Repo.get_by(Pinventory.Items.ItemLocation, item_id: item.id) == nil

    deleted =
      Pinventory.Audit.list_recent_edits(limit: 20)
      |> Enum.find(fn edit ->
        Enum.any?(edit.events, &(&1.action == "item.deleted" and &1.item_id == item.id))
      end)

    assert deleted
  end

  test "does not delete when the confirm name does not match", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Keep Me"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item-delete")
    |> render_click()

    view
    |> form("#item-delete-form", delete: %{name: "keep me"})
    |> render_submit()

    assert has_element?(view, "#item-delete-modal")
    assert Items.get_item!(item.id).name == "Keep Me"
  end

  test "server refuses delete when the name is unsaved", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Keep"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item-delete")
    |> render_click()

    view
    |> form("#item-form", item: %{name: "Changed"})
    |> render_change()

    html =
      view
      |> form("#item-delete-form", delete: %{name: "Keep"})
      |> render_submit()

    assert html =~ "Save or revert the name first."
    assert Items.get_item!(item.id).name == "Keep"
  end

  test "trims confirm name spaces and deletes the item", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Spare"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item-delete")
    |> render_click()

    view
    |> form("#item-delete-form", delete: %{name: "  Spare  "})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/"
    assert flash["info"] == "Item deleted"
    assert_raise Ecto.NoResultsError, fn -> Items.get_item!(item.id) end
  end

  test "clears unsaved-changes before navigating away on delete", %{conn: conn, scope: scope} do
    {:ok, garage} = Locations.create(scope, %{name: "Garage"})
    {:ok, item} = Items.create_item(scope, %{name: "Tape"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    set_quantity(view, garage.id, 4)
    assert_push_event(view, "unsaved-changes", %{dirty: true})

    view
    |> element("#item-delete")
    |> render_click()

    view
    |> form("#item-delete-form", delete: %{name: "Tape"})
    |> render_submit()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
    {path, flash} = assert_redirect(view)
    assert path == "/"
    assert flash["info"] == "Item deleted"
  end

  test "deletes an item when the saved name has padding", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Keep"})

    item
    |> Ecto.Changeset.change(%{name: "Keep "})
    |> Pinventory.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item-delete")
    |> render_click()

    view
    |> form("#item-delete-form", delete: %{name: "Keep"})
    |> render_change()

    refute has_element?(view, "#item-delete-confirm-submit:disabled")

    view
    |> form("#item-delete-form", delete: %{name: "Keep"})
    |> render_submit()

    {path, flash} = assert_redirect(view)
    assert path == "/"
    assert flash["info"] == "Item deleted"
  end

  test "clears the confirm name when the delete modal closes", %{conn: conn, scope: scope} do
    {:ok, item} = Items.create_item(scope, %{name: "Level"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item-delete")
    |> render_click()

    view
    |> form("#item-delete-form", delete: %{name: "Lev"})
    |> render_change()

    view
    |> element("#item-delete-cancel")
    |> render_click()

    refute has_element?(view, "#item-delete-modal")

    view
    |> element("#item-delete")
    |> render_click()

    refute has_element?(view, ~s(#item-delete-confirm[value="Lev"]))
    assert has_element?(view, "#item-delete-confirm-submit:disabled")
  end

  describe "notes" do
    test "saves notes with the item and links the activity line to that version", %{
      conn: conn,
      scope: scope
    } do
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, view, _html} = live(conn, ~p"/item/#{item}")

      view |> form("#item-form", item: %{notes: "Bottom shelf"}) |> render_change()

      assert has_element?(view, ~s(#item-notes-section[data-notes-dirty="true"]))
      assert has_element?(view, "#item-save:not([disabled])")

      view |> form("#item-form") |> render_submit()

      assert Items.get_item!(item.id).notes == "Bottom shelf"
      assert has_element?(view, ~s(#item-notes-section[data-notes-dirty="false"]))
      assert has_element?(view, "#note-edited-menu", "edited 1 time")

      [event] =
        item.id
        |> Pinventory.Audit.list_for_item()
        |> Enum.filter(&(&1.action == "item.notes_changed"))

      line = element(view, "#item-event-#{event.id}")

      assert render(line) =~ "Edited notes +2 −0"
      assert render(line) =~ ~s(href="/item/#{item.id}?note=1")

      render_click(line)

      assert_patch(view, ~p"/item/#{item}?note=1")
      assert has_element?(view, "#note-history-summary", "v0 → v1")
    end

    test "the history window compares any two versions", %{conn: conn, scope: scope} do
      sam = user_scope_fixture(user_fixture(%{email: "sam@example.com"}))

      item =
        item_with_notes(scope, [
          {scope, "Fridge"},
          {sam, "Basement fridge"},
          {scope, "Basement fridge, bottom shelf"}
        ])

      {:ok, view, _html} = live(conn, ~p"/item/#{item}?note=2")

      assert has_element?(view, "#note-history-summary", "Changes by sam@example.com")
      assert has_element?(view, "#note-history-counts", "+2 −1")
      assert has_element?(view, "#note-diff[data-view=inline] .text-success", "Basement")
      assert has_element?(view, "#note-history-next", "v3")
      assert has_element?(view, "#note-history-prev", "v1")

      view
      |> form("#note-compare-form", %{from: "0", to: "3"})
      |> render_change()

      assert has_element?(
               view,
               "#note-history-summary",
               "Changes by #{scope.user.email} and sam@example.com"
             )

      assert has_element?(view, "#note-history-summary", "v0 → v3")
      assert has_element?(view, "#note-history-counts", "+4 −0")

      view |> element("#note-view-split") |> render_click()

      assert has_element?(view, "#note-diff[data-view=split]")

      view |> element("#note-history-close") |> render_click()

      assert_patch(view, ~p"/item/#{item}")
      refute has_element?(view, "#note-history")
    end

    test "a range with four authors names two and others", %{conn: conn, scope: scope} do
      edits =
        for {email, text} <- [
              {"alex@x.test", "a"},
              {"deedle@x.test", "a b"},
              {"sam@x.test", "a b c"},
              {"kim@x.test", "a b c d"}
            ] do
          {user_scope_fixture(user_fixture(%{email: email})), text}
        end

      item = item_with_notes(scope, edits)
      {:ok, view, _html} = live(conn, ~p"/item/#{item}?note=4")

      view |> form("#note-compare-form", %{from: "0", to: "4"}) |> render_change()

      assert has_element?(
               view,
               ~s(#note-history-summary [title="alex@x.test, deedle@x.test, sam@x.test, kim@x.test"]),
               "alex@x.test, deedle@x.test, and others"
             )
    end

    test "restore fills the form and Save writes a new version", %{conn: conn, scope: scope} do
      item = item_with_notes(scope, [{scope, "Fridge"}, {scope, "Freezer"}])
      {:ok, view, _html} = live(conn, ~p"/item/#{item}?note=1")

      view |> element("#note-history-restore") |> render_click()

      assert_patch(view, ~p"/item/#{item}")
      assert has_element?(view, "#item_notes", "Fridge")
      assert has_element?(view, "#item-notes-hint", "restored from v1")
      assert Items.get_item!(item.id).notes == "Freezer"

      view |> form("#item-form") |> render_submit()

      assert Enum.map(Items.note_versions(item.id), & &1.text) == [
               "",
               "Fridge",
               "Freezer",
               "Fridge"
             ]
    end

    test "a save from an out-of-date copy warns instead of overwriting", %{
      conn: conn,
      scope: scope
    } do
      sam = user_scope_fixture(user_fixture(%{email: "sam@example.com"}))
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, view, _html} = live(conn, ~p"/item/#{item}")

      {:ok, _} = Items.update_item(sam, item, %{notes: "Their note"})

      view |> form("#item-form", item: %{notes: "My note"}) |> render_submit()

      assert has_element?(view, "#item-stale-warning", "sam@example.com saved this item")
      assert has_element?(view, "#item-stale-notes-diff .text-error", "Their")
      assert has_element?(view, "#item-stale-notes-diff .text-success", "My")
      assert Items.get_item!(item.id).notes == "Their note"

      view |> element("#item-stale-keep") |> render_click()

      refute has_element?(view, "#item-stale-warning")
      assert has_element?(view, ~s(#item-notes-section[data-notes-dirty="true"]))

      view |> form("#item-form") |> render_submit()

      assert Items.get_item!(item.id).notes == "My note"
    end

    test "loading the newer version drops the unsaved edits", %{conn: conn, scope: scope} do
      sam = user_scope_fixture(user_fixture(%{email: "sam@example.com"}))
      {:ok, item} = Items.create_item(scope, %{name: "Milk"})
      {:ok, view, _html} = live(conn, ~p"/item/#{item}")
      {:ok, _} = Items.update_item(sam, item, %{notes: "Their note"})

      view |> form("#item-form", item: %{notes: "My note"}) |> render_submit()
      view |> element("#item-stale-load") |> render_click()

      refute has_element?(view, "#item-stale-warning")
      assert has_element?(view, "#item_notes", "Their note")
      assert has_element?(view, ~s(#item-notes-section[data-notes-dirty="false"]))
    end
  end

  defp item_with_notes(scope, edits) do
    {:ok, item} = Items.create_item(scope, %{name: "Milk"})

    Enum.reduce(edits, item, fn {editor, text}, item ->
      {:ok, item} = Items.update_item(editor, item, %{notes: text})
      item
    end)
  end

  defp assert_quantity(view, location_id, quantity) do
    assert has_element?(view, ~s(#quantity-#{location_id}[value="#{quantity}"]))
  end

  defp set_quantity(view, location_id, quantity) do
    view
    |> element("#quantity-#{location_id}")
    |> render_change(%{
      "_target" => ["quantities", location_id],
      "quantities" => %{location_id => to_string(quantity)}
    })
  end
end
