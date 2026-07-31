defmodule Mix.Tasks.Pinventory.Invite do
  @shortdoc "Mint a one-time registration invite and print the URL"

  @moduledoc """
  Creates a blank invite registration ticket and prints the URL.

      mix pinventory.invite
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Pinventory.Accounts.create_invite() do
      {:ok, invite, plain_token} ->
        url = PinventoryWeb.Endpoint.url() <> Pinventory.Accounts.invite_path(plain_token)
        Mix.shell().info("Invite #{invite.id}")
        Mix.shell().info("Expires at: #{invite.expires_at}")
        Mix.shell().info("Registration URL:")
        Mix.shell().info(url)

      {:error, reason} ->
        Mix.raise("failed to create invite: #{inspect(reason)}")
    end
  end
end
