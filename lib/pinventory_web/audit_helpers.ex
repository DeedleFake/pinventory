defmodule PinventoryWeb.AuditHelpers do
  @moduledoc """
  Shared display helpers for audit events in LiveViews.
  """

  @doc """
  Human-readable actor label from a preloaded user or nil.
  """
  def actor_label(%{email: email}) when is_binary(email), do: email
  def actor_label(_), do: "Unknown user"

  @doc """
  Formats an event timestamp for UI.
  """
  def format_event_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  @doc """
  One-line description of a single audit event for activity feeds and timelines.
  """
  def event_line(%{action: "item.created", metadata: meta}) do
    "Created item “#{meta["item_name"] || "item"}”"
  end

  def event_line(%{action: "item.updated", changes: changes}) do
    case changes do
      %{"name" => %{"from" => from, "to" => to}} ->
        "Renamed item from “#{from}” to “#{to}”"

      _ ->
        "Updated item"
    end
  end

  def event_line(%{action: "item.deleted", metadata: meta}) do
    "Deleted item “#{meta["item_name"] || "item"}”"
  end

  def event_line(%{action: "location.created", metadata: meta}) do
    "Created location “#{meta["location_name"] || "location"}”"
  end

  def event_line(%{action: "location.updated", changes: changes}) do
    case changes do
      %{"name" => %{"from" => from, "to" => to}} ->
        "Renamed location from “#{from}” to “#{to}”"

      _ ->
        "Updated location"
    end
  end

  def event_line(%{action: "stock.changed", changes: changes, metadata: meta}) do
    location = meta["location_name"] || "location"

    case changes do
      %{"quantity" => %{"from" => from, "to" => to}} ->
        "Stock at #{location}: #{from} → #{to}"

      _ ->
        "Stock changed at #{location}"
    end
  end

  def event_line(%{action: action}), do: action

  @doc """
  Returns an item id that can be opened in the UI, or `nil`.

  Skips `item.deleted` (the item row is gone) and events with no `item_id`.
  """
  def linkable_item_id(%{action: "item.deleted"}), do: nil

  def linkable_item_id(%{item_id: item_id}) when is_binary(item_id) and item_id != "",
    do: item_id

  def linkable_item_id(_), do: nil

  @doc """
  First linkable item id among an edit group's events, or `nil`.
  """
  def linkable_item_id_for_edit(%{events: events}) when is_list(events) do
    Enum.find_value(events, &linkable_item_id/1)
  end

  def linkable_item_id_for_edit(_), do: nil

  @doc """
  Returns a location id that can be opened in the UI, or `nil`.

  There is no location delete action today; all location-bearing events are eligible.
  """
  def linkable_location_id(%{location_id: location_id})
      when is_binary(location_id) and location_id != "",
      do: location_id

  def linkable_location_id(_), do: nil

  @doc """
  First linkable location id among an edit group's events, or `nil`.
  """
  def linkable_location_id_for_edit(%{events: events}) when is_list(events) do
    Enum.find_value(events, &linkable_location_id/1)
  end

  def linkable_location_id_for_edit(_), do: nil

  @doc """
  Navigation target for an activity edit group.

  Prefers the item page when the edit touches an item; otherwise the location
  page for a location-only edit. Returns `{:item, id}`, `{:location, id}`,
  or `nil`.
  """
  def activity_link_target(edit) do
    cond do
      item_id = linkable_item_id_for_edit(edit) ->
        {:item, item_id}

      location_id = linkable_location_id_for_edit(edit) ->
        {:location, location_id}

      true ->
        nil
    end
  end

  @doc """
  Heading for an edit group (`list_recent_edits/1` map).
  """
  def edit_heading(%{user: user, events: events}) do
    who = actor_label(user)
    subject = edit_subject(events)
    summary = edit_summary(events)

    cond do
      subject && summary -> "#{who} · #{subject} — #{summary}"
      subject -> "#{who} · #{subject}"
      true -> "#{who} · #{summary || "changes"}"
    end
  end

  @doc """
  Compact "user · when" label for last stock change on the items list.
  """
  def last_stock_label(event) do
    "#{actor_label(event.user)} · #{format_event_time(event.inserted_at)}"
  end

  defp edit_subject(events) do
    Enum.find_value(events, fn event ->
      event.metadata["item_name"] || event.metadata["location_name"]
    end)
  end

  defp edit_summary(events) do
    stock_count = Enum.count(events, &(&1.action == "stock.changed"))

    parts =
      events
      |> Enum.reject(&(&1.action == "stock.changed"))
      |> Enum.map(&summary_part/1)
      |> Enum.reject(&is_nil/1)

    parts =
      if stock_count > 0 do
        stock_label =
          if stock_count == 1,
            do: "stock at 1 location",
            else: "stock at #{stock_count} locations"

        parts ++ [stock_label]
      else
        parts
      end

    case parts do
      [] -> nil
      list -> Enum.join(list, "; ")
    end
  end

  defp summary_part(%{action: "item.created"}), do: "created"
  defp summary_part(%{action: "item.updated"}), do: "renamed"
  defp summary_part(%{action: "item.deleted"}), do: "deleted"
  defp summary_part(%{action: "location.created"}), do: "location created"
  defp summary_part(%{action: "location.updated"}), do: "location renamed"
  defp summary_part(_), do: nil
end
