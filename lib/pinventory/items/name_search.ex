defmodule Pinventory.Items.NameSearch do
  @moduledoc """
  Searches item names the way fzf matches lines, without fzf's operators.

  Typed text splits on whitespace into terms, and every term has to match. A
  term matches a name when all of its characters appear in the name in order,
  with gaps allowed across spaces and symbols. "pntbrsh" matches "Paint brush",
  and "candy" never matches "Handsaw".

  Ranking scores each term by how cleanly it matches and sums the scores. For
  ranking, a space or ASCII punctuation counts as a word boundary, so "100" is
  an exact word in "100% wool".

  Case folding is ASCII only, on both sides: terms use
  `String.downcase(term, :ascii)` and names use SQLite's `lower/1`.
  """

  import Ecto.Query, warn: false

  defmodule Term do
    @moduledoc """
    One typed term and the SQL `GLOB` patterns that match and rank it.

    `match` and `substring` run against the lowercased name. The other
    patterns run against the lowercased name padded with a space on each end,
    and treat a space or ASCII punctuation character as a word boundary.
    """

    @enforce_keys [
      :text,
      :match,
      :exact_word,
      :word_prefix,
      :word_starts,
      :substring,
      :word_start_gap
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            text: String.t(),
            match: String.t(),
            exact_word: String.t(),
            word_prefix: String.t(),
            word_starts: String.t(),
            substring: String.t(),
            word_start_gap: String.t()
          }
  end

  # A GLOB character class for one space or ASCII punctuation character.
  @boundary "[ -/:-@[-`{-~]"

  @match_sql "lower(?) GLOB ?"

  @rank_sql """
  CASE
    WHEN (' ' || lower(?) || ' ') GLOB ? THEN 6
    WHEN (' ' || lower(?) || ' ') GLOB ? THEN 5
    WHEN (' ' || lower(?) || ' ') GLOB ? THEN 4
    WHEN lower(?) GLOB ? THEN 3
    WHEN (' ' || lower(?) || ' ') GLOB ? THEN 2
    ELSE 1
  END
  """

  @doc """
  Parses typed text into terms, or `nil` when the text is blank.
  """
  @spec parse(String.t()) :: [Term.t(), ...] | nil
  def parse(text) when is_binary(text) do
    case String.split(text) do
      [] -> nil
      words -> Enum.map(words, &term/1)
    end
  end

  @doc """
  Keeps only rows of the `:item` binding whose name matches every term.
  """
  @spec where_matches(Ecto.Queryable.t(), [Term.t(), ...]) :: Ecto.Query.t()
  def where_matches(query, terms) do
    Enum.reduce(terms, query, fn term, query ->
      where(query, [item: item], fragment(@match_sql, item.name, ^term.match))
    end)
  end

  @doc """
  Orders rows of the `:item` binding by match quality, then by shorter name,
  then by name.
  """
  @spec order_by_rank(Ecto.Queryable.t(), [Term.t(), ...]) :: Ecto.Query.t()
  def order_by_rank(query, terms) do
    score =
      terms
      |> Enum.map(&rank/1)
      |> Enum.reduce(fn rank, sum -> dynamic(^sum + ^rank) end)

    query
    |> order_by(^[desc: score])
    |> order_by([item: item], asc: fragment("length(?)", item.name), asc: item.name)
  end

  defp rank(%Term{} = term) do
    dynamic(
      [item: item],
      fragment(
        @rank_sql,
        item.name,
        ^term.exact_word,
        item.name,
        ^term.word_prefix,
        item.name,
        ^term.word_starts,
        item.name,
        ^term.substring,
        item.name,
        ^term.word_start_gap
      )
    )
  end

  defp term(word) do
    text = String.downcase(word, :ascii)
    chars = text |> String.codepoints() |> Enum.map(&escape_glob/1)
    literal = Enum.join(chars)

    %Term{
      text: text,
      match: "*" <> Enum.join(chars, "*") <> "*",
      exact_word: "*" <> @boundary <> literal <> @boundary <> "*",
      word_prefix: "*" <> @boundary <> literal <> "*",
      word_starts: "*" <> @boundary <> Enum.join(chars, "*" <> @boundary) <> "*",
      substring: "*" <> literal <> "*",
      word_start_gap: "*" <> @boundary <> Enum.join(chars, "*") <> "*"
    }
  end

  defp escape_glob(char) when char in ["*", "?", "["], do: "[" <> char <> "]"
  defp escape_glob(char), do: char
end
