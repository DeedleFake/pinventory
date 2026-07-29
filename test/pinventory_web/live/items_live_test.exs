defmodule PinventoryWeb.ItemsLiveTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Pinventory.Items
  alias Pinventory.Locations

  test "renders empty state when there are no items", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "h1", "Items")
    assert has_element?(view, "#items-empty", "No items yet")
    assert has_element?(view, "#items-empty a[href='/item']")
  end

  test "shows new item and edit locations actions above the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#items-actions #new-item[href='/item']", "New Item")

    assert has_element?(
             view,
             "#items-actions #edit-locations[href='/locations']",
             "Edit Locations"
           )
  end

  test "lists items with stock labels and links to edit", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, shelf} = Locations.create(%{name: "Shelf"})

    {:ok, screws} =
      Items.create_item(%{name: "Screws"}, %{garage.id => 5, shelf.id => 3})

    {:ok, empty} = Items.create_item(%{name: "Empty Box"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#items-#{screws.id}")
    assert has_element?(view, "a[href='/item/#{screws.id}']", "Screws")
    assert has_element?(view, "#items-#{screws.id}-stock", "8 total in 2 locations")

    assert has_element?(view, "a[href='/item/#{empty.id}']", "Empty Box")
    assert has_element?(view, "#items-#{empty.id}-stock", "0 total")
    refute has_element?(view, "#items-#{empty.id}-stock", " in ")
  end

  test "uses singular location wording for one stock location", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, item} = Items.create_item(%{name: "Hammer"}, %{garage.id => 2})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#items-#{item.id}-stock", "2 total in 1 location")
  end

  test "filters items by name", %{conn: conn} do
    {:ok, _} = Items.create_item(%{name: "Box Nails"})
    {:ok, _} = Items.create_item(%{name: "Hammer"})

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#items-filter-form", %{q: "nail"})
    |> render_change()

    assert_patch(view, "/?q=nail")
    assert has_element?(view, "#items a", "Box Nails")
    refute has_element?(view, "#items a", "Hammer")
  end

  test "filters items by location", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, shelf} = Locations.create(%{name: "Shelf"})

    {:ok, _} = Items.create_item(%{name: "Drill"}, %{garage.id => 1})
    {:ok, _} = Items.create_item(%{name: "Tape"}, %{shelf.id => 2})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#items-filter-form option", "Garage")

    view
    |> form("#items-filter-form", %{location: garage.id})
    |> render_change()

    assert_patch(view, "/?location=#{garage.id}")
    assert has_element?(view, "#items a", "Drill")
    refute has_element?(view, "#items a", "Tape")
  end

  test "shows no-match empty state when filters exclude everything", %{conn: conn} do
    {:ok, _} = Items.create_item(%{name: "Hammer"})

    {:ok, view, _html} = live(conn, ~p"/?q=zzzz")

    assert has_element?(view, "#items-empty", "No items match")
    refute has_element?(view, "#items a", "Hammer")
  end

  test "navigates to the item editor when a row is clicked", %{conn: conn} do
    {:ok, item} = Items.create_item(%{name: "Level"})

    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, _view, html} =
      view
      |> element("#items-#{item.id}")
      |> render_click()
      |> follow_redirect(conn, ~p"/item/#{item.id}")

    assert html =~ "Edit item"
  end
end
