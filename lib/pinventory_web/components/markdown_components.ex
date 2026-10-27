defmodule PinventoryWeb.MarkdownComponents do
  @moduledoc """
  Renders user-written Markdown, sanitized, with the `.markdown` styles from
  `app.css`.
  """

  use Phoenix.Component

  alias Pinventory.Markdown

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :class, :any, default: nil
  attr :empty, :string, default: "Nothing written yet."

  def markdown(assigns) do
    ~H"""
    <div id={@id} class={["markdown", @class]}>
      <p :if={String.trim(@text) == ""} class="italic opacity-60">{@empty}</p>
      {if String.trim(@text) != "", do: Phoenix.HTML.raw(Markdown.to_html(@text))}
    </div>
    """
  end
end
