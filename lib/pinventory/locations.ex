defmodule Pinventory.Locations do
  @moduledoc """
  Context for storage locations and location-level queries.

  Public functions use short names (`create/2`, `update/2`, `list/0`) because
  the module already scopes them as location operations. Compare with
  `Pinventory.Items`, which uses `create_item/3`-style names when the context
  owns multiple related schemas.

  Mutating APIs take an authenticated `Pinventory.Accounts.Scope` as the first
  argument and write audit events in the same transaction as the change.
  """

  # Exclude Ecto.Query.update so local update/2 and update/3 are not captured as macros.
  import Ecto.Query, warn: false, except: [update: 2, update: 3]

  alias Ecto.Multi
  alias Pinventory.Accounts.Scope
  alias Pinventory.Audit
  alias Pinventory.Items.ItemLocation
  alias Pinventory.Repo

  alias Pinventory.Locations.Location

  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  def create(%Scope{} = scope, %Ecto.Changeset{} = changeset) do
    user_id = Audit.actor_id(scope)
    edit_id = Audit.new_edit_id()

    Multi.new()
    |> Multi.insert(:location, changeset)
    |> Multi.run(:audit_events, fn repo, %{location: location} ->
      Audit.insert_events(repo, [
        Audit.location_event_attrs(
          action: "location.created",
          edit_id: edit_id,
          user_id: user_id,
          location: location,
          changes: %{"name" => %{"from" => nil, "to" => location.name}},
          edit_seq: 0
        )
      ])
    end)
    |> Multi.run(:result, fn _repo, %{location: location} -> {:ok, location} end)
    |> Repo.transaction()
    |> unwrap_location_transaction()
  end

  def create(%Scope{} = scope, attrs) do
    create(scope, change_location(%Location{}, attrs))
  end

  def update(%Scope{} = scope, %Ecto.Changeset{} = changeset) do
    user_id = Audit.actor_id(scope)
    edit_id = Audit.new_edit_id()
    name_change = name_change_diff(changeset)

    cond do
      not changeset.valid? ->
        {:error, changeset}

      name_change == nil ->
        # No-op rename: return current data without writing audit.
        {:ok, changeset.data}

      true ->
        Multi.new()
        |> Multi.update(:location, changeset)
        |> Multi.run(:audit_events, fn repo, %{location: location} ->
          Audit.insert_events(repo, [
            Audit.location_event_attrs(
              action: "location.updated",
              edit_id: edit_id,
              user_id: user_id,
              location: location,
              changes: %{"name" => name_change},
              edit_seq: 0
            )
          ])
        end)
        |> Multi.run(:result, fn _repo, %{location: location} -> {:ok, location} end)
        |> Repo.transaction()
        |> unwrap_location_transaction()
    end
  end

  def update(%Scope{} = scope, %Location{} = location, attrs) do
    update(scope, change_location(location, attrs))
  end

  @doc """
  Deletes a location that has no stock and records `location.deleted`.

  Returns `{:error, :location_has_items}` when the location still has items.
  Does not move or discard stock.
  """
  def delete(%Scope{} = scope, %Location{} = location) do
    user_id = Audit.actor_id(scope)
    edit_id = Audit.new_edit_id()

    Multi.new()
    |> Multi.run(:empty?, fn repo, _ ->
      if location_has_items?(repo, location.id) do
        {:error, :location_has_items}
      else
        {:ok, true}
      end
    end)
    |> Multi.run(:audit_events, fn repo, _ ->
      Audit.insert_events(repo, [
        Audit.location_event_attrs(
          action: "location.deleted",
          edit_id: edit_id,
          user_id: user_id,
          location: location,
          changes: %{"name" => %{"from" => location.name, "to" => nil}},
          edit_seq: 0
        )
      ])
    end)
    |> Multi.delete(:location, location)
    |> Multi.run(:result, fn _repo, %{location: deleted} -> {:ok, deleted} end)
    |> Repo.transaction()
    |> unwrap_location_transaction()
  end

  def list do
    query =
      from location in Location,
        order_by: [asc: location.name]

    Repo.all(query)
  end

  @doc """
  Gets a single location.

  Returns `nil` if the location does not exist.
  """
  def get(id), do: Repo.get(Location, id)

  @doc """
  Gets a single location.

  Raises `Ecto.NoResultsError` if the location does not exist.
  """
  def get!(id), do: Repo.get!(Location, id)

  @doc """
  Returns locations ordered by name, each with `item_count` set to the number
  of distinct item types stored at that location.
  """
  def list_with_item_counts do
    query =
      from location in Location,
        left_join: item_location in assoc(location, :item_locations),
        group_by: location.id,
        order_by: [asc: location.name],
        select_merge: %{item_count: count(item_location.id)}

    Repo.all(query)
  end

  @doc """
  Like `list_with_item_counts/0`, plus floor-plan placement cues.

  When a floor plan exists, each location gets `on_plan?` and optional
  `floor_name`. When there is no plan, `on_plan?` is false and `floor_name`
  is nil (callers should hide plan badges entirely via `FloorPlans.floor_plan_exists?/0`).
  """
  def list_with_item_counts_and_placements do
    placements = Pinventory.FloorPlans.placement_index()

    Enum.map(list_with_item_counts(), fn location ->
      case Map.get(placements, location.id) do
        %{floor_name: floor_name} ->
          %{location | on_plan?: true, floor_name: floor_name}

        nil ->
          %{location | on_plan?: false, floor_name: nil}
      end
    end)
  end

  defp location_has_items?(repo, location_id) do
    repo.exists?(from il in ItemLocation, where: il.location_id == ^location_id)
  end

  defp name_change_diff(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.fetch_change(changeset, :name) do
      :error ->
        nil

      {:ok, new_name} ->
        old_name = changeset.data.name

        if old_name == new_name do
          nil
        else
          %{"from" => old_name, "to" => new_name}
        end
    end
  end

  defp unwrap_location_transaction(result) do
    case result do
      {:ok, %{result: location}} -> {:ok, location}
      {:error, :location, changeset, _} -> {:error, changeset}
      {:error, :audit_events, reason, _} -> {:error, reason}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end
end
