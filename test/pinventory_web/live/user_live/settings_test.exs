defmodule PinventoryWeb.UserLive.SettingsTest do
  use PinventoryWeb.ConnCase, async: false

  alias Pinventory.Accounts
  import Phoenix.LiveViewTest
  import Pinventory.AccountsFixtures
  import Ecto.Query, only: [from: 2]

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
      assert has_element?(lv, ~s|#nav-items[href="/"]|, "Items")
      assert has_element?(lv, ~s|#nav-locations[href="/locations"]|, "Locations")
      assert has_element?(lv, ~s|#nav-settings[aria-current="page"]|)
    end

    test "redirects if user is not logged in", %{conn: conn} do
      # A user must exist so the app redirects to log in (not bootstrap register).
      _user = user_fixture()

      assert {:error, redirect} = live(conn, ~p"/user/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/user/log-in"
      refute Map.has_key?(flash, "error")
    end

    test "redirects every settings tab if user is not in sudo mode", %{conn: conn} do
      conn =
        log_in_user(conn, user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -21, :minute)
        )

      for path <- [~p"/user/settings", ~p"/user/settings/users", ~p"/user/settings/activity"] do
        assert {:error, {:redirect, %{to: to, flash: flash}}} = live(conn, path)
        assert to == ~p"/user/log-in"
        # Reauth is expected; do not treat it as an error flash.
        refute Map.has_key?(flash, "error")
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

    test "activity tab links location-only edits to the location page", %{conn: conn} do
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
               ~s|a#activity-edit-#{garage_edit.edit_id}[href="/location/#{garage.id}"]|
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

    test "activity tab does not link deleted location entries", %{conn: conn} do
      alias Pinventory.Accounts.Scope
      alias Pinventory.Locations

      user = user_fixture()
      scope = Scope.for_user(user)
      conn = log_in_user(conn, user)

      {:ok, location} = Locations.create(scope, %{name: "Gone Bin"})
      location_id = location.id
      assert {:ok, _} = Locations.delete(scope, location)

      assert {:ok, view, _html} = live(conn, ~p"/user/settings/activity")

      deleted =
        Pinventory.Audit.list_recent_edits(limit: 20)
        |> Enum.find(fn edit ->
          Enum.any?(
            edit.events,
            &(&1.action == "location.deleted" and &1.location_id == location_id)
          )
        end)

      assert deleted
      [event] = deleted.events
      assert has_element?(view, "#activity-event-#{event.id}", "Deleted location")
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
      refute Map.has_key?(flash, "error")
    end
  end

  describe "passkeys" do
    alias Pinventory.Accounts
    alias Pinventory.SoftAuthenticator

    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    defp enroll(lv, auth, opts \\ []) do
      lv |> element("#add-passkey-button") |> render_click()
      assert_push_event lv, "passkey:register", %{options: options}

      lv
      |> element("#passkeys-section")
      |> render_hook("passkey_attestation", %{
        credential: SoftAuthenticator.create(auth, options, opts)
      })
    end

    test "adds a passkey that can then log in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/user/settings")
      assert html =~ "No passkeys yet."

      auth = SoftAuthenticator.new()
      assert enroll(lv, auth) =~ "Passkey added."
      assert [cred] = Accounts.list_passkey_credentials(user)
      assert has_element?(lv, "#passkey-#{cred.id}")

      {options, ceremony} = Accounts.begin_passkey_authentication()

      {:ok, assertion} =
        auth
        |> SoftAuthenticator.get(options, user_handle: Ecto.UUID.dump!(user.id))
        |> PinventoryWeb.Passkey.Wire.assertion()

      assert {:ok, %{id: id}} = Accounts.finish_passkey_authentication(ceremony, assertion)
      assert id == user.id
    end

    test "rejects an attestation for the wrong origin", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      assert enroll(lv, SoftAuthenticator.new(), origin: "https://evil.example") =~
               "Could not add passkey."

      assert Accounts.list_passkey_credentials(user) == []
    end

    test "rejects an attestation with no ceremony in flight", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      {options, _} = Accounts.begin_passkey_registration(user)

      html =
        lv
        |> element("#passkeys-section")
        |> render_hook("passkey_attestation", %{
          credential: SoftAuthenticator.create(SoftAuthenticator.new(), options)
        })

      assert html =~ "Could not add passkey."
      assert Accounts.list_passkey_credentials(user) == []
    end

    test "removes a passkey", %{conn: conn, user: user} do
      {_, cred} = passkey_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      assert has_element?(lv, "#passkey-#{cred.id}")

      assert lv |> element("#passkey-#{cred.id} button", "Remove") |> render_click() =~
               "Passkey removed."

      refute has_element?(lv, "#passkey-#{cred.id}")
      assert Accounts.list_passkey_credentials(user) == []
    end

    test "an open page whose session was deleted loses sudo", %{
      conn: conn,
      user: user
    } do
      {_, cred} = passkey_fixture(user)
      other_token = Accounts.generate_user_session_token(user)

      other_conn =
        build_conn()
        |> init_test_session(%{
          user_token: other_token,
          live_socket_id: "user_sessions:#{Base.url_encode64(other_token)}"
        })

      {:ok, other_lv, _} = live(other_conn, ~p"/user/settings")

      {:ok, lv, _} = live(conn, ~p"/user/settings")
      lv |> element("#passkey-#{cred.id} button", "Remove") |> render_click()

      # LiveViewTest does not deliver the socket-id disconnect broadcast, so
      # this exercises the fallback: the still-mounted page holds a user with
      # a fresh authenticated_at, yet sudo-gated events now fail.
      {_, second} = passkey_fixture(user)

      other_lv
      |> element("#passkeys-section")
      |> render_hook("revoke_passkey", %{"id" => second.id})

      assert [_] = Accounts.list_passkey_credentials(user)
    end

    test "removing a passkey signs out other sessions only", %{conn: conn, user: user} do
      {_, cred} = passkey_fixture(user)
      other = Accounts.generate_user_session_token(user)
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      lv |> element("#passkey-#{cred.id} button", "Remove") |> render_click()

      refute Accounts.get_user_by_session_token(other)
      assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
    end

    test "cannot remove another user's passkey", %{conn: conn} do
      {_, cred} = passkey_fixture(user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      html =
        lv |> element("#passkeys-section") |> render_hook("revoke_passkey", %{"id" => cred.id})

      assert html =~ "Could not remove passkey."
      assert Pinventory.Repo.get!(Accounts.PasskeyCredential, cred.id).revoked_at == nil
    end
  end

  describe "agent access" do
    alias Pinventory.Accounts.ApiToken
    alias Pinventory.Repo

    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    defp create_token(lv, name) do
      lv |> form("#api-token-form", api_token: %{name: name}) |> render_change()
      lv |> form("#api-token-form", api_token: %{name: name}) |> render_submit()
    end

    defp shown_secret(lv) do
      lv
      |> element("#latest-api-token-value")
      |> render()
      |> then(&Regex.run(~r/value="([^"]+)"/, &1))
      |> List.last()
    end

    defp toggle(lv), do: lv |> element("#show-inactive-api-tokens") |> render_click()

    test "creates a token and shows its secret once", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/user/settings")
      assert html =~ "No active tokens."

      assert create_token(lv, "Claude on phone") =~ "Token created."
      secret = shown_secret(lv)

      assert {:ok, %{user: %{id: id}, api_token: token}} =
               Accounts.fetch_scope_for_api_token(secret)

      assert id == user.id
      assert has_element?(lv, "#api-token-#{token.id}", "Claude on phone")
      assert has_element?(lv, "#api-token-#{token.id}", "expires")
      refute lv |> element("#api_token_name") |> render() =~ ~s(value="Claude on phone")

      lv |> element("#revoke-api-token-#{token.id}") |> render_click()
      refute has_element?(lv, "#latest-api-token")
    end

    test "a blank name shows an error", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      assert create_token(lv, " ") =~ "can&#39;t be blank"
      assert Accounts.list_api_tokens(user) == []
    end

    test "revoked and expired tokens are hidden until the toggle is on", %{conn: conn, user: user} do
      {:ok, {_, active}} = Accounts.create_api_token(user, "active one")
      {:ok, {_, expired}} = Accounts.create_api_token(user, "expired one")

      Repo.update_all(from(t in ApiToken, where: t.id == ^expired.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -60)]
      )

      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      lv |> element("#revoke-api-token-#{active.id}") |> render_click()

      refute has_element?(lv, "#api-token-#{active.id}")
      refute has_element?(lv, "#api-token-#{expired.id}")
      assert has_element?(lv, "#api-tokens-empty", "No active tokens.")

      toggle(lv)
      assert has_element?(lv, "#api-token-#{active.id}-status", "Revoked")
      assert has_element?(lv, "#api-token-#{expired.id}-status", "Expired")
      refute has_element?(lv, "#revoke-api-token-#{active.id}")
      refute has_element?(lv, "#revoke-api-token-#{expired.id}")

      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      refute has_element?(lv, "#api-token-#{active.id}")
    end

    test "revoke all revokes every active token", %{conn: conn, user: user} do
      {:ok, {a, _}} = Accounts.create_api_token(user, "a")
      {:ok, {b, _}} = Accounts.create_api_token(user, "b")

      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      assert lv |> element("#revoke-all-api-tokens") |> render_click() =~ "Revoked 2 tokens."

      assert :error = Accounts.fetch_scope_for_api_token(a)
      assert :error = Accounts.fetch_scope_for_api_token(b)
      refute has_element?(lv, "#revoke-all-api-tokens")
      assert length(Accounts.list_api_tokens(user)) == 2
    end

    test "make replacement gives a revoked token a new secret under the same name", %{
      conn: conn,
      user: user
    } do
      {:ok, {_, old}} = Accounts.create_api_token(user, "Claude on phone")
      {:ok, _} = Accounts.revoke_api_token(user, old.id)

      {:ok, lv, _html} = live(conn, ~p"/user/settings")
      toggle(lv)

      assert lv |> element("#replace-api-token-#{old.id}") |> render_click() =~
               "Replacement created."

      assert {:ok, %{api_token: new}} = Accounts.fetch_scope_for_api_token(shown_secret(lv))
      assert new.name == "Claude on phone"
      assert has_element?(lv, "#revoke-api-token-#{new.id}")
      assert has_element?(lv, "#api-token-#{old.id}-status", "Revoked")
    end

    test "cannot revoke another user's token", %{conn: conn} do
      {:ok, {secret, other}} = Accounts.create_api_token(user_fixture(), "theirs")
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      assert render_click(lv, "revoke_api_token", %{"id" => other.id}) =~
               "Could not revoke token."

      assert {:ok, _} = Accounts.fetch_scope_for_api_token(secret)
    end

    test "token actions need sudo mode", %{conn: conn, user: user} do
      {:ok, {secret, token}} = Accounts.create_api_token(user, "agent")
      {:ok, lv, _html} = live(conn, ~p"/user/settings")

      [{session_token, _}] =
        Repo.all(
          from t in Accounts.UserToken,
            where: t.user_id == ^user.id and t.context == "session",
            select: {t.token, t.id}
        )

      override_token_authenticated_at(
        session_token,
        DateTime.add(DateTime.utc_now(:second), -21, :minute)
      )

      assert {:error, {:redirect, %{to: "/user/log-in"}}} =
               lv |> element("#revoke-api-token-#{token.id}") |> render_click()

      assert {:ok, _} = Accounts.fetch_scope_for_api_token(secret)
    end
  end
end
