defmodule PinventoryWeb.LocationsLiveTest do
  use PinventoryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Pinventory.Items.Item
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Locations
  alias Pinventory.Repo

  test "renders locations ordered by name with item counts", %{conn: conn} do
    {:ok, garage} = Locations.create(%{name: "Garage"})
    {:ok, _alpha} = Locations.create(%{name: "Alpha"})

    item = insert_item!("Drill")
    insert_item_location!(item, garage, 3)

    {:ok, view, html} = live(conn, ~p"/locations")

    assert html =~ "Locations"
    assert has_element?(view, "#location-new-form")
    assert has_element?(view, "#locations")

    # Alphabetical order on load: Alpha before Garage
    assert html =~ ~r/Alpha[\s\S]*Garage/

    assert has_element?(view, "#location-#{garage.id}-item-count", "1 item")
  end

  test "adds a new location at the top of the list", %{conn: conn} do
    {:ok, existing} = Locations.create(%{name: "Existing"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-new-form", location: %{name: "Brand New"})
    |> render_submit()

    html = render(view)

    assert html =~ "Brand New"
    assert html =~ "Location created"

    # New location is first stream row after the empty-state placeholder
    assert html =~ ~r/id="location-[^"]+"[\s\S]*id="location-#{existing.id}"/
  end

  test "shows validation errors for a blank new location", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    html =
      view
      |> form("#location-new-form", location: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "renames a location without removing it from the list", %{conn: conn} do
    {:ok, location} = Locations.create(%{name: "Old Name"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-#{location.id}", location: %{name: "New Name"})
    |> render_submit()

    assert has_element?(view, "#location-#{location.id}")
    assert render(view) =~ "New Name"
    assert render(view) =~ "Location saved"
    refute render(view) =~ "Old Name"
  end

  test "disables save until the name changes and marks the dirty row", %{conn: conn} do
    {:ok, location} = Locations.create(%{name: "Shelf"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, "#location-#{location.id}-save:disabled")
    refute has_element?(view, "#location-#{location.id}.border-primary")

    view
    |> form("#location-#{location.id}", location: %{name: "Shelf 2"})
    |> render_change()

    refute has_element?(view, "#location-#{location.id}-save:disabled")
    assert has_element?(view, "#location-#{location.id}.border-primary")

    view
    |> form("#location-#{location.id}", location: %{name: "Shelf"})
    |> render_change()

    assert has_element?(view, "#location-#{location.id}-save:disabled")
    refute has_element?(view, "#location-#{location.id}.border-primary")
  end

  test "disables save again after a successful rename", %{conn: conn} do
    {:ok, location} = Locations.create(%{name: "Bin"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-#{location.id}", location: %{name: "Bin A"})
    |> render_submit()

    assert has_element?(view, "#location-#{location.id}-save:disabled")
    refute has_element?(view, "#location-#{location.id}.border-primary")
  end

  test "pushes unsaved-changes events when edits start and clear", %{conn: conn} do
    {:ok, location} = Locations.create(%{name: "Drawer"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, "#locations-page[phx-hook]")

    view
    |> form("#location-#{location.id}", location: %{name: "Drawer 2"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})

    view
    |> form("#location-#{location.id}", location: %{name: "Drawer"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
  end

  test "clears unsaved-changes after a successful save", %{conn: conn} do
    {:ok, location} = Locations.create(%{name: "Crate"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-#{location.id}", location: %{name: "Crate 2"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})

    view
    |> form("#location-#{location.id}", location: %{name: "Crate 2"})
    |> render_submit()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
  end

  test "marks typed new location drafts as unsaved", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/locations")

    view
    |> form("#location-new-form", location: %{name: "Draft Place"})
    |> render_change()

    assert_push_event(view, "unsaved-changes", %{dirty: true})

    view
    |> form("#location-new-form", location: %{name: "Draft Place"})
    |> render_submit()

    assert_push_event(view, "unsaved-changes", %{dirty: false})
  end

  test "shows zero items for a location with no stock", %{conn: conn} do
    {:ok, location} = Locations.create(%{name: "Empty"})

    {:ok, view, _html} = live(conn, ~p"/locations")

    assert has_element?(view, "#location-#{location.id}-item-count", "0 items")
  end

  test "header links to the locations page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "a[href='/locations']", "Locations")
  end

  defp insert_item!(name) do
    %Item{}
    |> Item.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp insert_item_location!(item, location, quantity) do
    %ItemLocation{
      item_id: item.id,
      location_id: location.id,
      quantity: quantity
    }
    |> Repo.insert!()
  end
end
