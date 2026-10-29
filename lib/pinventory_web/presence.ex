defmodule PinventoryWeb.Presence do
  @moduledoc """
  Tracks who has an edit page open, so each editor can see who else is
  editing the same thing. Pages are keyed by the same subjects as
  `Pinventory.LiveEdits`.

  A page calls `track_editor/2` once it knows its subject, and
  `refresh_editors/1` on each `%Phoenix.Socket.Broadcast{event:
  "presence_diff"}`. `@editors` holds the other people's labels.
  """

  use Phoenix.Presence, otp_app: :pinventory, pubsub_server: Pinventory.PubSub

  alias PinventoryWeb.AuditHelpers

  @spec track_editor(Phoenix.LiveView.Socket.t(), Pinventory.LiveEdits.subject()) ::
          Phoenix.LiveView.Socket.t()
  def track_editor(socket, subject) do
    topic = topic(subject)

    if Phoenix.LiveView.connected?(socket) do
      user = socket.assigns.current_scope.user
      :ok = Phoenix.PubSub.subscribe(Pinventory.PubSub, topic)
      {:ok, _} = track(self(), topic, user.id, %{label: AuditHelpers.actor_label(user)})
    end

    socket
    |> Phoenix.Component.assign(:editors_topic, topic)
    |> refresh_editors()
  end

  @spec refresh_editors(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_editors(socket) do
    me = socket.assigns.current_scope.user.id

    others =
      for {id, %{metas: [meta | _]}} <- list(socket.assigns.editors_topic), id != me do
        meta.label
      end

    Phoenix.Component.assign(socket, :editors, Enum.sort(others))
  end

  defp topic({kind, id}), do: "editors:#{kind}:#{id}"
  defp topic(:naming_convention), do: "editors:naming_convention"
end
