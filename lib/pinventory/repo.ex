defmodule Pinventory.Repo do
  use Ecto.Repo,
    otp_app: :pinventory,
    adapter: Ecto.Adapters.SQLite3
end
