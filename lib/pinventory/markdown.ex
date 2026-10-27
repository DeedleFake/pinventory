defmodule Pinventory.Markdown do
  @moduledoc """
  Renders and tidies user-written Markdown, such as the item naming
  convention.
  """

  @extension [strikethrough: true, table: true, autolink: true]
  @list_end "\n\n<!-- end list -->\n\n"

  @doc """
  Renders Markdown to sanitized HTML. Raw HTML, scripts, and unsafe links in
  the source are dropped, so the result is safe to put in a page.

  With `sourcepos: true`, each block gets a `data-sourcepos` attribute such as
  `"3:1-4:8"` naming the source lines it came from.

  With `heading_offset: n`, every heading moves down `n` levels, stopping at
  `h6`, so a `#` heading can sit under the `h1` of the page that shows it.
  """
  @spec to_html(String.t(), [{:sourcepos, boolean()} | {:heading_offset, non_neg_integer()}]) ::
          String.t()
  def to_html(text, opts \\ []) when is_binary(text) do
    offset = Keyword.get(opts, :heading_offset, 0)

    text
    |> MDEx.parse_document!(extension: @extension)
    |> MDEx.Document.update_nodes(MDEx.Heading, &%{&1 | level: min(&1.level + offset, 6)})
    |> MDEx.to_html!(
      extension: @extension,
      render: [sourcepos: Keyword.get(opts, :sourcepos, false)],
      sanitize:
        Keyword.put(MDEx.Document.default_sanitize_options(), :add_generic_attributes, [
          "data-sourcepos"
        ])
    )
  end

  @doc """
  Rewrites Markdown in one consistent style without changing what it
  renders: `#` headings, `-` bullets, `**bold**`, `*italic*`, and fenced code.
  Formatting the result again leaves it as it is.
  """
  @spec format(String.t()) :: String.t()
  def format(text) when is_binary(text) do
    text
    |> MDEx.parse_document!(extension: @extension)
    |> MDEx.to_markdown!(
      extension: @extension,
      render: [prefer_fenced: true, experimental_minimize_commonmark: true]
    )
    |> drop_needless_list_ends()
  end

  # The formatter puts an HTML comment between any two adjacent lists, even a
  # bulleted and a numbered one that can't merge. Keep only the comments that
  # stop two lists from rendering as one.
  defp drop_needless_list_ends(text) do
    [first | rest] = String.split(text, @list_end)
    html = list_html(text)

    rest
    |> Enum.with_index(1)
    |> Enum.reduce(first, fn {part, index}, acc ->
      joined = acc <> "\n\n" <> part
      candidate = Enum.join([joined | Enum.drop(rest, index)], @list_end)
      if list_html(candidate) == html, do: joined, else: acc <> @list_end <> part
    end)
  end

  defp list_html(text) do
    text
    |> MDEx.to_html!(extension: @extension, render: [unsafe: true])
    |> String.replace("<!-- end list -->\n", "")
  end
end
