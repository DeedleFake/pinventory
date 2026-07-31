defmodule Pinventory.Release do
  @moduledoc """
  Used for executing DB release tasks when Mix is not available in production.

  ## Examples

      bin/pinventory eval 'Pinventory.Release.migrate()'
      bin/pinventory eval 'Pinventory.Release.create_user("admin@example.com", "a long password")'
      bin/pinventory eval 'Pinventory.Release.create_invite()'

  """

  @app :pinventory

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates a confirmed user with email and password.

  Prints the user id and email on success. Raises on failure.
  """
  def create_user(email, password)
      when is_binary(email) and is_binary(password) do
    load_app()

    {:ok, _, result} =
      Ecto.Migrator.with_repo(Pinventory.Repo, fn _repo ->
        Pinventory.Accounts.create_user(%{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        })
      end)

    case result do
      {:ok, user} ->
        IO.puts("Created user #{user.id} (#{user.email})")
        {:ok, user}

      {:error, %Ecto.Changeset{} = changeset} ->
        raise "failed to create user: #{inspect(changeset.errors)}"
    end
  end

  @doc """
  Mints a blank invite and prints the registration URL.

  Returns `{:ok, invite, url}`.
  """
  def create_invite do
    load_app()

    {:ok, _, result} =
      Ecto.Migrator.with_repo(Pinventory.Repo, fn _repo ->
        Pinventory.Accounts.create_invite()
      end)

    case result do
      {:ok, invite, plain_token} ->
        url = PinventoryWeb.Endpoint.url() <> Pinventory.Accounts.invite_path(plain_token)
        IO.puts("Invite #{invite.id}")
        IO.puts("Expires at: #{invite.expires_at}")
        IO.puts("Registration URL:")
        IO.puts(url)
        {:ok, invite, url}

      {:error, reason} ->
        raise "failed to create invite: #{inspect(reason)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
