defmodule Pinventory.TextDiffTest do
  use ExUnit.Case, async: true

  alias Pinventory.TextDiff

  describe "rows/2" do
    test "marks changed words within a line" do
      assert TextDiff.rows("Bottom shelf", "Top shelf") == [
               {:line, [{:del, "Bottom"}, {:ins, "Top"}, {:eq, " shelf"}]}
             ]
    end

    test "collapses unchanged lines and keeps one line of context" do
      assert TextDiff.rows("a\nb\nc\nd\ne\nf", "a\nb\nc\nd\ne\nF") == [
               {:skip, 4},
               {:line, [{:eq, "e"}]},
               {:line, [{:del, "f"}, {:ins, "F"}]}
             ]
    end

    test "keeps a lone unchanged line instead of collapsing it" do
      assert TextDiff.rows("one\ntwo\nthree", "one\ntwo\nnew\nthree") == [
               {:line, [{:eq, "one"}]},
               {:line, [{:eq, "two"}]},
               {:line, [{:ins, "new"}]},
               {:line, [{:eq, "three"}]}
             ]
    end

    test "gives added and removed lines their own rows" do
      assert TextDiff.rows("keep\ndrop", "keep") == [
               {:line, [{:eq, "keep"}]},
               {:line, [{:del, "drop"}]}
             ]
    end

    test "shows every line when nothing changed" do
      assert TextDiff.rows("a\nb\nc", "a\nb\nc") == [
               {:line, [{:eq, "a"}]},
               {:line, [{:eq, "b"}]},
               {:line, [{:eq, "c"}]}
             ]
    end

    test "diffs from the empty note" do
      assert TextDiff.rows("", "Basement fridge") == [{:line, [{:ins, "Basement fridge"}]}]
    end
  end

  test "old_side/1 and new_side/1 split one row into its two columns" do
    ops = [{:del, "Bottom"}, {:ins, "Top"}, {:eq, " shelf"}]

    assert TextDiff.old_side(ops) == [{:del, "Bottom"}, {:eq, " shelf"}]
    assert TextDiff.new_side(ops) == [{:ins, "Top"}, {:eq, " shelf"}]
  end

  test "counts/1 counts added and removed words" do
    assert TextDiff.counts(TextDiff.rows("a b c\nold line", "a x c d")) == %{
             added: 2,
             removed: 3
           }
  end
end
