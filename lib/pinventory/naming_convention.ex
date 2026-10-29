defmodule Pinventory.NamingConvention do
  @moduledoc """
  The one Markdown convention for naming items, shared by everyone who uses
  this inventory, people and agents alike.

  Every save appends a numbered version and the newest one is the
  convention, so the table is its own history. Version 0 is the starting
  text from the migration and has no author.
  """

  import Ecto.Query, warn: false

  alias Pinventory.Accounts.Scope
  alias Pinventory.Audit
  alias Pinventory.LiveEdits
  alias Pinventory.NamingConvention.Version
  alias Pinventory.Repo

  @doc """
  Returns the newest version.
  """
  @spec current() :: Version.t()
  def current do
    from(v in Version, order_by: [desc: v.number], limit: 1, preload: [:user])
    |> Repo.one!()
  end

  @doc """
  Returns every version, oldest first. A version's `number` is its index.
  """
  @spec versions() :: [Version.t()]
  def versions do
    from(v in Version, order_by: [asc: v.number], preload: [:user])
    |> Repo.all()
  end

  @doc """
  Saves `text` as a new version on top of version `base`, the version the
  editor started from.

  When another save has landed since `base`, nothing is written and
  `{:error, :stale, newest}` is returned. Saving the same text as `base`
  writes nothing and returns `base`. Open pages hear about a save through
  `Pinventory.LiveEdits`.
  """
  @spec save(Scope.t(), non_neg_integer(), String.t()) ::
          {:ok, Version.t()} | {:error, :stale, Version.t()} | {:error, Ecto.Changeset.t()}
  def save(%Scope{} = scope, base, text) when is_integer(base) and is_binary(text) do
    user_id = Audit.actor_id(scope)
    via_token_name = scope.api_token && scope.api_token.name

    changeset =
      Version.changeset(%Version{}, %{
        number: base + 1,
        text: text,
        user_id: user_id,
        via_token_name: via_token_name
      })

    Repo.transaction(fn ->
      newest = current()

      cond do
        newest.number != base -> Repo.rollback({:stale, newest})
        Ecto.Changeset.get_field(changeset, :text) == newest.text -> newest
        true -> changeset |> Repo.insert() |> insert_result()
      end
    end)
    |> case do
      {:ok, version} ->
        LiveEdits.broadcast(:naming_convention, :saved)
        {:ok, version}

      {:error, {:stale, newest}} ->
        {:error, :stale, newest}

      {:error, %Ecto.Changeset{errors: [{:number, _} | _]}} ->
        {:error, :stale, current()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp insert_result({:ok, version}), do: Repo.preload(version, :user)
  defp insert_result({:error, changeset}), do: Repo.rollback(changeset)
end
