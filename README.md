# Pinventory

Personal inventory app built with Phoenix. Data is stored in **SQLite**
(single file). Item name search uses **FTS5** with the trigram tokenizer.

## Database

* Dev default: `priv/repo/pinventory_dev.db` (override with `DATABASE_PATH`)
* Test default: `priv/repo/pinventory_test.db`
* Prod: set `DATABASE_PATH` to the SQLite file path (required at runtime)

Create and migrate a new file database:

```text
mix ecto.create
mix ecto.migrate
```

Or: `mix ecto.setup` / `mix setup`.

This project is greenfield on SQLite. Older Postgres databases are not
migrated in place. If you still have Postgres data, export it yourself
before pointing the app at a new SQLite file.

Name filters use SQLite `LIKE` / FTS5 defaults: case-insensitive for ASCII
A–Z only.

## Development

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Installable app (PWA)

Pinventory can be installed from the browser. The pieces:

* `priv/static/manifest.webmanifest`: name, colors and icons. Its colors are
  the `base-100` of the light theme in `assets/css/app.css`. The two
  `theme-color` metas in `root.html.heex` carry the light and dark colors,
  and the theme script there keeps them matching a forced theme.
* `priv/static/sw.js`: the service worker, registered from `assets/js/app.js`.
  It caches only the icons, `/offline.html` and digested `/assets` files. It
  must never cache HTML or anything else that carries a CSRF token or
  session state. Navigations that fail show `priv/static/offline.html`.
  Bump `VERSION` in `sw.js` when you change what it caches, so old caches are
  deleted on activation.
* Icons in `priv/static/images` are generated from `priv/static/favicon.svg`
  by `scripts/generate-pwa-icons` (needs headless Chrome or Chromium). Run it
  and commit the PNGs when the favicon changes.
* Reference `manifest.webmanifest` and `sw.js` by plain path, not `~p`. In
  prod `~p` links a digested name that `Plug.Static`'s `only` list doesn't
  serve.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
