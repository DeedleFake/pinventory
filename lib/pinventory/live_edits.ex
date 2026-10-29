defmodule Pinventory.LiveEdits do
  @moduledoc """
  Tells open pages that a record they show was saved or deleted, so people
  editing the same thing see each other's saves as they happen.

  Contexts call `broadcast/2` after a write commits, whether it came from a
  web page or an MCP tool. Pages call `subscribe/1` and receive
  `{Pinventory.LiveEdits, record, event}`. The message carries no data:
  the page reads the record again, so the database stays the one source of
  truth.
  """

  @type subject :: {:item, Ecto.UUID.t()} | {:location, Ecto.UUID.t()} | :naming_convention
  @type event :: :saved | :deleted

  @spec subscribe(subject()) :: :ok | {:error, term()}
  def subscribe(record), do: Phoenix.PubSub.subscribe(Pinventory.PubSub, topic(record))

  @doc """
  Sends `event` to every subscriber of `record`, the caller included. Call it
  only after the write has committed, so subscribers read the new data.
  """
  @spec broadcast(subject(), event()) :: :ok | {:error, term()}
  def broadcast(record, event) when event in [:saved, :deleted] do
    Phoenix.PubSub.broadcast(Pinventory.PubSub, topic(record), {__MODULE__, record, event})
  end

  defp topic({kind, id}) when kind in [:item, :location] and is_binary(id),
    do: "live_edits:#{kind}:#{id}"

  defp topic(:naming_convention), do: "live_edits:naming_convention"
end
