defmodule PinventoryWeb.MarkdownComponents do
  @moduledoc """
  Renders user-written Markdown, sanitized, with the `.markdown` styles from
  `app.css`.

  The Markdown always sits inside a page that has its own `h1`, so its
  headings move down one level: `#` renders as `h2`.
  """

  use Phoenix.Component

  alias Pinventory.Markdown

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :class, :any, default: nil
  attr :empty, :string, default: "Nothing written yet."
  attr :sourcepos, :boolean, default: false, doc: "mark each block with its source lines"

  def markdown(assigns) do
    ~H"""
    <div id={@id} class={["markdown", @class]}>
      <p :if={String.trim(@text) == ""} class="italic opacity-60">{@empty}</p>
      {if String.trim(@text) != "",
        do: Phoenix.HTML.raw(Markdown.to_html(@text, sourcepos: @sourcepos, heading_offset: 1))}
    </div>
    """
  end
end
