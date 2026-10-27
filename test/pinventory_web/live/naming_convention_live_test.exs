defmodule PinventoryWeb.NamingConventionLiveTest do
  use PinventoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  alias Pinventory.Accounts
  alias Pinventory.Accounts.Scope
  alias Pinventory.NamingConvention

  setup :register_and_log_in_user

  test "the items list links to the naming convention", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ~s(#items-actions #naming-convention[href="/items/naming-convention"]),
             "Naming convention"
           )
  end

  test "shows the seeded convention as the initial version", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/items/naming-convention")

    assert has_element?(view, ~s|#nav-items[aria-current="page"]|)
    assert has_element?(view, "#convention-text", "Boxes of Tissues")
    assert has_element?(view, "#convention-preview-body strong", "Boxes of Tissues")
    assert has_element?(view, "#convention-last-edit", "Initial version")
    assert has_element?(view, "#convention-save[disabled]")
    refute has_element?(view, "#convention-history-open")
  end

  test "previews edits sanitized and saves them as a new version", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/items/naming-convention")

    view
    |> form("#convention-form",
      convention: %{text: "## Units\n\n<script>x()</script>\n\n*Boxes*"}
    )
    |> render_change()

    assert has_element?(view, ~s(#convention-preview-body h2[data-sourcepos="1:1-1:8"]), "Units")
    assert has_element?(view, "#convention-preview-body em", "Boxes")
    refute render(element(view, "#convention-preview-body")) =~ "<script"
    assert has_element?(view, "#convention-hint", "Unsaved changes")
    refute has_element?(view, "#convention-save[disabled]")

    view |> form("#convention-form") |> render_submit()

    assert %{number: 1, text: "## Units\n\n<script>x()</script>\n\n*Boxes*"} =
             NamingConvention.current()

    assert has_element?(view, "#convention-last-edit", "Last edited by #{user.email}")
    assert has_element?(view, "#convention-last-edit", "v1")
    assert has_element?(view, "#convention-save[disabled]")
  end

  test "Format rewrites the Markdown in the form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/items/naming-convention")

    view
    |> form("#convention-form", convention: %{text: "Units\n=====\n\n* __Boxes__"})
    |> render_change()

    view |> element("#convention-format") |> render_click()

    assert view |> element("#convention-text") |> render() =~ "># Units\n\n- **Boxes**</textarea>"
    assert has_element?(view, "#convention-format-status", "Formatted")

    view |> element("#convention-format") |> render_click()

    assert has_element?(view, "#convention-format-status", "Already tidy")
  end

  test "history labels agent edits, compares versions, and restores into the form", %{
    conn: conn,
    scope: scope,
    user: user
  } do
    {:ok, {_secret, token}} = Accounts.create_api_token(user, "Claude on phone")
    {:ok, _} = NamingConvention.save(scope, 0, "Plural names")

    {:ok, _} =
      NamingConvention.save(Scope.for_api_token(user, token), 1, "Plural names with units")

    {:ok, view, _html} = live(conn, ~p"/items/naming-convention")

    assert has_element?(view, "#convention-last-edit", "#{user.email} via Claude on phone")
    view |> element("#convention-history-open") |> render_click()

    assert_patch(view, ~p"/items/naming-convention?version=2")
    assert has_element?(view, "#convention-history-version-0", "Initial version")
    assert has_element?(view, "#convention-history-version-2", "via Claude on phone")
    assert has_element?(view, "#convention-history-summary", "v1 → v2")
    assert has_element?(view, "#convention-diff .text-success", "units")
    assert has_element?(view, "#convention-history-restore[disabled]")

    view |> form("#convention-compare-form", %{from: "0", to: "1"}) |> render_change()
    assert has_element?(view, "#convention-history-summary", "v0 → v1")

    view |> element("#convention-history-restore") |> render_click()

    assert_patch(view, ~p"/items/naming-convention")
    assert has_element?(view, "#convention-text", "Plural names")
    assert has_element?(view, "#convention-hint", "restored from v1")

    view |> form("#convention-form") |> render_submit()

    assert %{number: 3, text: "Plural names"} = NamingConvention.current()
  end

  test "warns instead of overwriting a save made while editing", %{conn: conn} do
    sam = user_scope_fixture(user_fixture(%{email: "sam@example.com"}))
    {:ok, view, _html} = live(conn, ~p"/items/naming-convention")

    {:ok, _} = NamingConvention.save(sam, 0, "Sam's version")

    view |> form("#convention-form", convention: %{text: "My version"}) |> render_submit()

    assert has_element?(view, "#convention-stale-warning", "sam@example.com saved")
    assert has_element?(view, "#convention-stale-diff")
    assert has_element?(view, "#convention-text", "My version")
    assert NamingConvention.current().text == "Sam's version"

    view |> element("#convention-stale-keep") |> render_click()
    refute has_element?(view, "#convention-stale-warning")

    view |> form("#convention-form") |> render_submit()

    assert %{number: 2, text: "My version"} = NamingConvention.current()
  end

  test "load their version drops the user's edits", %{conn: conn} do
    sam = user_scope_fixture(user_fixture(%{email: "sam@example.com"}))
    {:ok, view, _html} = live(conn, ~p"/items/naming-convention")
    {:ok, _} = NamingConvention.save(sam, 0, "Sam's version")

    view |> form("#convention-form", convention: %{text: "My version"}) |> render_submit()
    view |> element("#convention-stale-load") |> render_click()

    refute has_element?(view, "#convention-stale-warning")
    assert has_element?(view, "#convention-text", "Sam's version")
    assert has_element?(view, "#convention-save[disabled]")
  end

  describe "item pages" do
    test "show the convention read-only with a link that opens a new tab", %{conn: conn} do
      for path <- [~p"/item", ~p"/item/#{item_fixture()}"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "details#item-naming-convention summary", "Naming convention")
        assert has_element?(view, "#item-naming-convention-body strong", "Boxes of Tissues")

        assert has_element?(
                 view,
                 ~s(#item-naming-convention-edit[href="/items/naming-convention"][target="_blank"])
               )

        refute has_element?(view, "#item-naming-convention textarea")
      end
    end
  end

  defp item_fixture do
    {:ok, item} = Pinventory.Items.create_item(user_scope_fixture(), %{name: "Light bulbs"})
    item
  end
end
