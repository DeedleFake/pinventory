defmodule PinventoryWeb.EditItemLiveTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Pinventory.Items
  alias Pinventory.Locations

  test "renders the new item form with locations ordered by name", %{conn: conn} do
    {:ok, _} = Locations.create(%{name: "Zebra"})
    {:ok, _} = Locations.create(%{name: "Alpha"})

    {:ok, view, html} = live(conn, ~p"/item")

    assert html =~ "New item"
    assert has_element?(view, "#item-form")
    assert has_element?(view, "#item-total", "Total: 0")
    assert html =~ ~r/Alpha[\s\S]*Zebra/
  end

  test "creates an item with stock and navigates to edit", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, shelf} = Locations.create(%{name: "Shelf"})

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
    assert has_element?(view, "#item-total", "Total: 3")

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

  test "edits an existing item name and quantities", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, shelf} = Locations.create(%{name: "Shelf"})
    {:ok, item} = Items.create_item(%{name: "Nails"}, %{garage.id => 5})

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
    assert has_element?(view, "#item-total", "Total: 6")

    updated = Items.get_item!(item.id)
    assert updated.name == "Box Nails"
    assert Items.stock_map(updated) == %{garage.id => 2, shelf.id => 4}
  end

  test "adjust buttons change draft quantities without saving", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, item} = Items.create_item(%{name: "Tape"}, %{garage.id => 1})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#quantity-inc-#{garage.id}")
    |> render_click()

    assert_quantity(view, garage.id, 2)
    assert has_element?(view, "#item-total", "Total: 2")
    refute has_element?(view, "#item-save:disabled")

    # Not saved yet
    assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 1}
  end

  test "set_quantity updates only the edited location when multiple locations exist", %{
    conn: conn
  } do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, shelf} = Locations.create(%{name: "Shelf"})
    {:ok, item} = Items.create_item(%{name: "Screws"}, %{garage.id => 1, shelf.id => 9})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    # Simulate browser form serialization with every quantities[...] field present.
    view
    |> element("#quantity-#{garage.id}")
    |> render_change(%{
      "location-id" => garage.id,
      "quantities" => %{
        garage.id => "4",
        shelf.id => "9"
      }
    })

    assert_quantity(view, garage.id, 4)
    assert_quantity(view, shelf.id, 9)
    assert has_element?(view, "#item-total", "Total: 13")
  end

  test "stock controls live in a stock form separate from the name form", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})

    {:ok, view, _html} = live(conn, ~p"/item")

    assert has_element?(view, "#item-form")
    assert has_element?(view, "#item-stock-form")
    assert has_element?(view, ~s(#item-save[form="item-form"]))
    assert has_element?(view, "#item-stock-form #quantity-#{garage.id}")
    refute has_element?(view, "#item-form #quantity-#{garage.id}")
    refute has_element?(view, ~s(#item-stock-form button[type="submit"]))
  end

  test "stock save failures keep the name form and flash an error", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})

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

    assert html =~ "Could not save item stock"
    assert has_element?(view, ~s(#item_name[value="Orphan stock"]))
    assert Items.list_items() == []
  end

  test "moves quantity between locations in the draft", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, shelf} = Locations.create(%{name: "Shelf"})
    {:ok, item} = Items.create_item(%{name: "Bits"}, %{garage.id => 5})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#move-start-#{garage.id}")
    |> render_click()

    assert has_element?(view, "#move-panel-#{garage.id}")

    view
    |> element("#move-to-#{garage.id}")
    |> render_change(%{"move_to" => shelf.id, "location-id" => garage.id})

    view
    |> element("#move-amount-#{garage.id}")
    |> render_change(%{"move_amount" => "2", "location-id" => garage.id})

    view
    |> element("#move-confirm-#{garage.id}")
    |> render_click()

    assert_quantity(view, garage.id, 3)
    assert_quantity(view, shelf.id, 2)
    assert has_element?(view, "#item-total", "Total: 5")
    refute has_element?(view, "#move-panel-#{garage.id}")

    assert Items.stock_map(Items.get_item!(item.id)) == %{garage.id => 5}
  end

  test "shows name suggestions and navigates on select", %{conn: conn} do
    {:ok, existing} = Items.create_item(%{name: "Screwdriver set"})

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

  test "hides name suggestions when the name field is blurred", %{conn: conn} do
    {:ok, _existing} = Items.create_item(%{name: "Screwdriver set"})

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

  test "does not reopen suggestions when editing quantities after blur", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, _existing} = Items.create_item(%{name: "Paper towels"})

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

  test "does not show suggestions while editing", %{conn: conn} do
    {:ok, item} = Items.create_item(%{name: "Wrench"})
    {:ok, _other} = Items.create_item(%{name: "Wrench set"})

    {:ok, view, _html} = live(conn, ~p"/item/#{item.id}")

    view
    |> element("#item_name")
    |> render_focus()

    view
    |> form("#item-form", item: %{name: "Wrench"})
    |> render_change()

    refute has_element?(view, "#item-suggestions")
  end

  test "marks the form dirty and pushes unsaved-changes events", %{conn: conn} do
    {:ok, item} = Items.create_item(%{name: "Level"})

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

  test "shows empty locations state with a link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/item")

    assert has_element?(view, "#item-locations-empty")
    assert has_element?(view, "a[href='/locations']", "Add locations")
  end

  defp assert_quantity(view, location_id, quantity) do
    assert has_element?(view, ~s(#quantity-#{location_id}[value="#{quantity}"]))
  end

  defp set_quantity(view, location_id, quantity) do
    view
    |> element("#quantity-#{location_id}")
    |> render_change(%{
      "location-id" => location_id,
      "quantities" => %{location_id => to_string(quantity)}
    })
  end
end
