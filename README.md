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

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
