defmodule PinventoryWeb.UserLive.SettingsTest do
  use PinventoryWeb.ConnCase, async: false

  alias Pinventory.Accounts
  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/user/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
      assert has_element?(lv, "#settings-tabs")
      assert has_element?(lv, "#settings-tab-account")
      assert has_element?(lv, "#settings-tab-users")
      assert has_element?(lv, "#settings-tab-activity")
      assert has_element?(lv, "#settings-account")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      # A user must exist so the app redirects to log in (not bootstrap register).
      _user = user_fixture()

      assert {:error, redirect} = live(conn, ~p"/user/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/user/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects every settings tab if user is not in sudo mode", %{conn: conn} do
      conn =
        log_in_user(conn, user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )

      for path <- [~p"/user/settings", ~p"/user/settings/users", ~p"/user/settings/activity"] do
        assert {:error, {:redirect, %{to: to, flash: flash}}} = live(conn, path)
        assert to == ~p"/user/log-in"
        assert flash["error"] == "You must re-authenticate to access this page."
      end
    end

    test "activity tab groups events by edit_id with actor and stock lines", %{conn: conn} do
      alias Pinventory.Accounts.Scope
      alias Pinventory.Items
      alias Pinventory.Locations

      user = user_fixture()
      scope = Scope.for_user(user)
      conn = log_in_user(conn, user)

      {:ok, garage} = Locations.create(scope, %{name: "Garage"})
      {:ok, shelf} = Locations.create(scope, %{name: "Shelf"})

      {:ok, item} =
        Items.create_item(scope, %{name: "Widget"}, %{garage.id => 2, shelf.id => 1})

      assert {:ok, view, _html} = live(conn, ~p"/user/settings/activity")

      assert has_element?(view, "#settings-activity")
      assert has_element?(view, "#activity-edits")
      refute has_element?(view, "#activity-empty")

      # Create edit groups item.created + two stock.changed under one edit_id
      edits = Pinventory.Audit.list_recent_edits(limit: 20)

      widget_edit =
        Enum.find(edits, fn edit ->
          Enum.any?(edit.events, &(&1.item_id == item.id and &1.action == "item.created"))
        end)

      assert widget_edit
      assert has_element?(view, "#activity-edit-#{widget_edit.edit_id}")
      assert has_element?(view, "#activity-edit-#{widget_edit.edit_id}", user.email)
      assert has_element?(view, "#activity-edit-#{widget_edit.edit_id}", "Widget")
      assert has_element?(view, "#activity-edit-#{widget_edit.edit_id}", "stock at 2 locations")

      for event <- widget_edit.events do
        assert has_element?(view, "#activity-event-#{event.id}")
      end

      assert has_element?(view, "#activity-event-#{hd(widget_edit.events).id}", "Created item")

      assert has_element?(
               view,
               ~s|a#activity-edit-#{widget_edit.edit_id}[href="/item/#{item.id}"]|
             )
    end

    test "activity tab links location-only edits to the locations page", %{conn: conn} do
      alias Pinventory.Accounts.Scope
      alias Pinventory.Locations

      user = user_fixture()
      scope = Scope.for_user(user)
      conn = log_in_user(conn, user)

      {:ok, garage} = Locations.create(scope, %{name: "Garage Link"})

      assert {:ok, view, _html} = live(conn, ~p"/user/settings/activity")

      garage_edit =
        Pinventory.Audit.list_recent_edits(limit: 20)
        |> Enum.find(fn edit ->
          Enum.any?(
            edit.events,
            &(&1.action == "location.created" and &1.location_id == garage.id)
          )
        end)

      assert garage_edit

      assert has_element?(
               view,
               ~s|a#activity-edit-#{garage_edit.edit_id}[href="/locations#location-#{garage.id}"]|
             )
    end

    test "activity tab does not link deleted item entries", %{conn: conn} do
      alias Pinventory.Accounts.Scope
      alias Pinventory.Items

      user = user_fixture()
      scope = Scope.for_user(user)
      conn = log_in_user(conn, user)

      {:ok, item} = Items.create_item(scope, %{name: "Gone"}, %{})
      item_id = item.id
      assert {:ok, _} = Items.delete_item(scope, item)

      assert {:ok, view, _html} = live(conn, ~p"/user/settings/activity")

      deleted =
        Pinventory.Audit.list_recent_edits(limit: 20)
        |> Enum.find(fn edit ->
          Enum.any?(edit.events, &(&1.action == "item.deleted" and &1.item_id == item_id))
        end)

      assert deleted
      [event] = deleted.events
      assert has_element?(view, "#activity-event-#{event.id}", "Deleted item")
      # Non-linkable edits render as <article>, not an <a>
      refute has_element?(view, ~s|a#activity-edit-#{deleted.edit_id}|)
      assert has_element?(view, "article#activity-edit-#{deleted.edit_id}")
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/user/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/user/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/user/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/user/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/user/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/user/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/user/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/user/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/user/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
