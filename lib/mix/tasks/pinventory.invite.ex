defmodule Mix.Tasks.Pinventory.Invite do
  @shortdoc "Mint a one-time registration invite and print the URL"

  @moduledoc """
  Creates an email-bound invite registration ticket and prints the URL.

  The invite is not sent by email; share the printed URL out of band.

      mix pinventory.invite user@example.com
  """

  use Mix.Task

  @impl Mix.Task
  def run([email]) when is_binary(email) and email != "" do
    Mix.Task.run("app.start")

    case Pinventory.Accounts.create_invite(email) do
      {:ok, invite, plain_token} ->
        url = PinventoryWeb.Endpoint.url() <> Pinventory.Accounts.invite_path(plain_token)
        Mix.shell().info("Invite #{invite.id}")
        Mix.shell().info("Email: #{invite.email}")
        Mix.shell().info("Expires at: #{invite.expires_at}")
        Mix.shell().info("Registration URL:")
        Mix.shell().info(url)

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise("failed to create invite: #{format_changeset_errors(changeset)}")

      {:error, reason} ->
        Mix.raise("failed to create invite: #{inspect(reason)}")
    end
  end

  def run(_args) do
    Mix.raise("usage: mix pinventory.invite user@example.com")
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end
end
