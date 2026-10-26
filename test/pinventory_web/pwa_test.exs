defmodule PinventoryWeb.PwaTest do
  use PinventoryWeb.ConnCase, async: false

  import Pinventory.AccountsFixtures

  @static_dir Application.app_dir(:pinventory, "priv/static")

  describe "manifest" do
    test "is served as a web manifest that is revalidated on every load", %{conn: conn} do
      conn = get(conn, "/manifest.webmanifest")

      assert response(conn, 200)
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/manifest+json"
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
    end

    test "has the fields browsers need to offer installation", %{conn: conn} do
      manifest = conn |> get("/manifest.webmanifest") |> response(200) |> JSON.decode!()

      assert manifest["name"] == "Pinventory"
      assert manifest["short_name"]
      assert manifest["display"] == "standalone"
      assert manifest["start_url"] == "/"
      assert manifest["scope"] == "/"
      assert manifest["id"]
      assert manifest["theme_color"] =~ ~r/^#[0-9a-f]{6}$/
      assert manifest["background_color"] =~ ~r/^#[0-9a-f]{6}$/
    end

    test "lists real icons, including 192, 512 and maskable", %{conn: conn} do
      manifest = conn |> get("/manifest.webmanifest") |> response(200) |> JSON.decode!()
      icons = manifest["icons"]

      for icon <- icons do
        assert File.regular?(Path.join(@static_dir, icon["src"])), "missing #{icon["src"]}"

        served = get(build_conn(), icon["src"])
        assert response(served, 200)
        assert get_resp_header(served, "content-type") == [icon["type"]]
      end

      assert Enum.any?(icons, &(&1["sizes"] == "192x192" and &1["purpose"] == "any"))
      assert Enum.any?(icons, &(&1["sizes"] == "512x512" and &1["purpose"] == "any"))
      assert Enum.any?(icons, &(&1["sizes"] == "512x512" and &1["purpose"] == "maskable"))
    end
  end

  describe "service worker" do
    test "is served from the root as JavaScript and is not cached long-term", %{conn: conn} do
      conn = get(conn, "/sw.js")

      assert response(conn, 200) =~ "addEventListener"
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/javascript"
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
    end
  end

  describe "offline page" do
    test "is a self-contained HTML page", %{conn: conn} do
      conn = get(conn, "/offline.html")
      document = conn |> response(200) |> LazyHTML.from_document()

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/html"
      assert [_] = document |> LazyHTML.query("#offline-page") |> LazyHTML.to_tree()

      # Nothing is fetched, so it renders with the network down.
      assert [] =
               document
               |> LazyHTML.query("link[rel=stylesheet], script[src], img[src], [href^=http]")
               |> LazyHTML.to_tree()
    end
  end

  describe "static links" do
    # In prod, ~p links a digested name such as /favicon-<hash>.svg. Plug.Static
    # serves root files only under their exact names, so that link 404s.
    test "never use ~p for a file at the root of priv/static" do
      root_files = Enum.filter(PinventoryWeb.static_paths(), &String.contains?(&1, "."))

      offenders =
        for path <- Path.wildcard("lib/**/*.{ex,heex}"),
            {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
            file <- root_files,
            String.contains?(line, ~s(~p"/#{file})),
            do: "#{path}:#{number} links ~p\"/#{file}\". Use the plain path \"/#{file}\"."

      assert offenders == []
    end
  end

  describe "root layout" do
    setup do
      _ = user_fixture()
      :ok
    end

    test "links the manifest and icons", %{conn: conn} do
      document = conn |> get(~p"/user/log-in") |> html_response(200) |> LazyHTML.from_document()

      assert [href] =
               document |> LazyHTML.query(~s(link[rel="manifest"])) |> LazyHTML.attribute("href")

      assert href == "/manifest.webmanifest"

      assert [_] =
               document |> LazyHTML.query(~s(link[rel="apple-touch-icon"])) |> LazyHTML.to_tree()
    end

    test "links the favicons by plain path, which prod serves", %{conn: conn} do
      document = conn |> get(~p"/user/log-in") |> html_response(200) |> LazyHTML.from_document()
      hrefs = document |> LazyHTML.query(~s(link[rel="icon"])) |> LazyHTML.attribute("href")

      assert Enum.sort(hrefs) == ["/favicon.ico", "/favicon.svg"]

      for href <- hrefs do
        assert get(build_conn(), href) |> response(200)
      end
    end

    test "has a theme color for each color scheme", %{conn: conn} do
      document = conn |> get(~p"/user/log-in") |> html_response(200) |> LazyHTML.from_document()
      metas = LazyHTML.query(document, ~s(meta[name="theme-color"]))

      assert Enum.sort(LazyHTML.attribute(metas, "media")) == [
               "(prefers-color-scheme: dark)",
               "(prefers-color-scheme: light)"
             ]

      for color <- LazyHTML.attribute(metas, "content") do
        assert color =~ ~r/^#[0-9a-f]{6}$/
      end
    end

    test "shares its theme colors with the offline page", %{conn: conn} do
      theme_colors = fn html ->
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s(meta[name="theme-color"]))
        |> then(&Enum.zip(LazyHTML.attribute(&1, "media"), LazyHTML.attribute(&1, "content")))
        |> Map.new()
      end

      layout = conn |> get(~p"/user/log-in") |> html_response(200) |> theme_colors.()
      offline = build_conn() |> get("/offline.html") |> response(200) |> theme_colors.()

      assert offline == layout
    end

    # Manifest colors can't follow the color scheme, and some browsers (Firefox,
    # and Chrome in dark mode) use them over the page's, so they match dark mode.
    test "gives the manifest its dark theme color", %{conn: conn} do
      document = conn |> get(~p"/user/log-in") |> html_response(200) |> LazyHTML.from_document()

      assert [dark] =
               document
               |> LazyHTML.query(
                 ~s{meta[name="theme-color"][media="(prefers-color-scheme: dark)"]}
               )
               |> LazyHTML.attribute("content")

      manifest = build_conn() |> get("/manifest.webmanifest") |> response(200) |> JSON.decode!()

      assert manifest["theme_color"] == dark
      assert manifest["background_color"] == dark
    end
  end
end
