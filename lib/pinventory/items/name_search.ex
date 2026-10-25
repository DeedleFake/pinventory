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
    where(query, ^all_match(terms))
  end

  @doc """
  Keeps only rows of the `:item` binding whose name matches every term of at
  least one group.
  """
  @spec where_matches_any(Ecto.Queryable.t(), [[Term.t(), ...], ...]) :: Ecto.Query.t()
  def where_matches_any(query, groups) do
    where(query, ^(groups |> Enum.map(&all_match/1) |> Enum.reduce(&dynamic(^&2 or ^&1))))
  end

  @doc """
  Orders rows of the `:item` binding by match quality, then by shorter name,
  then by name.
  """
  @spec order_by_rank(Ecto.Queryable.t(), [Term.t(), ...]) :: Ecto.Query.t()
  def order_by_rank(query, terms) do
    order_by_score(query, score(terms))
  end

  @doc """
  Orders rows of the `:item` binding by how many groups fully match, then by
  the summed match quality of those groups, then by shorter name, then by
  name.
  """
  @spec order_by_groups(Ecto.Queryable.t(), [[Term.t(), ...], ...]) :: Ecto.Query.t()
  def order_by_groups(query, groups) do
    # A fully matched group adds 1000, which outweighs any quality sum (at most 6 per term).
    groups
    |> Enum.map(fn terms ->
      dynamic(fragment("CASE WHEN ? THEN 1000 + ? ELSE 0 END", ^all_match(terms), ^score(terms)))
    end)
    |> Enum.reduce(&dynamic(^&2 + ^&1))
    |> then(&order_by_score(query, &1))
  end

  defp order_by_score(query, score) do
    query
    |> order_by(^[desc: score])
    |> order_by([item: item], asc: fragment("length(?)", item.name), asc: item.name)
  end

  defp all_match(terms) do
    terms
    |> Enum.map(&dynamic([item: item], fragment(@match_sql, item.name, ^&1.match)))
    |> Enum.reduce(&dynamic(^&2 and ^&1))
  end

  defp score(terms) do
    terms |> Enum.map(&rank/1) |> Enum.reduce(&dynamic(^&2 + ^&1))
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
