defmodule Pinventory.TextDiff do
  @moduledoc """
  Line-aligned, word-level diffs between two versions of a text.

  `rows/2` returns one row per displayed line. Each `{:line, ops}` row holds
  the word operations for one old line and the new line it became, so an
  inline view and a side-by-side view render the same rows and stay aligned.
  The old side of a row is its `:eq` and `:del` ops; the new side is its `:eq`
  and `:ins` ops. Runs of unchanged lines farther than one line from a change
  collapse into `{:skip, count}`.
  """

  @type op :: {:eq | :del | :ins, String.t()}
  @type row :: {:line, [op]} | {:skip, pos_integer()}

  @context 1

  @spec rows(String.t(), String.t()) :: [row]
  def rows(old_text, new_text) do
    old_text
    |> String.split("\n")
    |> List.myers_difference(String.split(new_text, "\n"))
    |> line_rows([])
    |> collapse()
  end

  @spec counts([row]) :: %{added: non_neg_integer(), removed: non_neg_integer()}
  def counts(rows) do
    ops = for {:line, ops} <- rows, op <- ops, do: op
    %{added: word_count(ops, :ins), removed: word_count(ops, :del)}
  end

  @spec old_side([op]) :: [op]
  def old_side(ops), do: Enum.reject(ops, &match?({:ins, _}, &1))

  @spec new_side([op]) :: [op]
  def new_side(ops), do: Enum.reject(ops, &match?({:del, _}, &1))

  defp line_rows([], acc), do: Enum.reverse(acc)

  defp line_rows([{:eq, lines} | rest], acc) do
    line_rows(rest, Enum.reverse(Enum.map(lines, &line_ops(:eq, &1)), acc))
  end

  defp line_rows([{:del, old}, {:ins, new} | rest], acc) do
    paired = Enum.zip_with(old, new, &word_ops/2)
    extra_old = old |> Enum.drop(length(new)) |> Enum.map(&line_ops(:del, &1))
    extra_new = new |> Enum.drop(length(old)) |> Enum.map(&line_ops(:ins, &1))
    line_rows(rest, Enum.reverse(paired ++ extra_old ++ extra_new, acc))
  end

  defp line_rows([{op, lines} | rest], acc) do
    line_rows(rest, Enum.reverse(Enum.map(lines, &line_ops(op, &1)), acc))
  end

  defp line_ops(_op, ""), do: []
  defp line_ops(op, line), do: [{op, line}]

  defp word_ops(old_line, new_line) do
    tokens(old_line)
    |> List.myers_difference(tokens(new_line))
    |> Enum.map(fn {op, tokens} -> {op, Enum.join(tokens)} end)
  end

  defp tokens(line), do: Regex.split(~r/\s+/, line, include_captures: true, trim: true)

  defp collapse(rows) do
    changed = rows |> Enum.map(&changed?/1) |> List.to_tuple()
    last = tuple_size(changed) - 1

    if last < 0 or not Enum.any?(Tuple.to_list(changed)) do
      Enum.map(rows, &{:line, &1})
    else
      rows
      |> Enum.with_index()
      |> Enum.chunk_by(fn {_ops, i} -> near_change?(changed, i, last) end)
      |> Enum.flat_map(fn
        [{_, i} | _] = run when length(run) > 1 ->
          if near_change?(changed, i, last),
            do: Enum.map(run, fn {ops, _} -> {:line, ops} end),
            else: [{:skip, length(run)}]

        [{ops, _}] ->
          [{:line, ops}]
      end)
    end
  end

  defp near_change?(changed, i, last) do
    Enum.any?(max(i - @context, 0)..min(i + @context, last)//1, &elem(changed, &1))
  end

  defp changed?(ops), do: Enum.any?(ops, fn {op, _} -> op != :eq end)

  defp word_count(ops, kind) do
    for {^kind, text} <- ops, reduce: 0 do
      count -> count + length(String.split(text, ~r/\s+/, trim: true))
    end
  end
end
