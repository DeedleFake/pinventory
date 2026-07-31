defmodule Mix.Tasks.Pinventory.User do
  @shortdoc "Create a confirmed user (email + password)"

  @moduledoc """
  Creates a confirmed application user.

      mix pinventory.user EMAIL PASSWORD

  Example:

      mix pinventory.user admin@example.com "a long password"
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [email, password] when email != "" and password != "" ->
        case Pinventory.Accounts.create_user(%{
               "email" => email,
               "password" => password,
               "password_confirmation" => password
             }) do
          {:ok, user} ->
            Mix.shell().info("Created user #{user.id} (#{user.email})")

          {:error, %Ecto.Changeset{} = changeset} ->
            Mix.raise("failed to create user: #{inspect(changeset.errors)}")
        end

      _ ->
        Mix.raise("usage: mix pinventory.user EMAIL PASSWORD")
    end
  end
end
