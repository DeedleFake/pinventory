defmodule Pinventory.NoteDiffTest do
  use ExUnit.Case, async: true

  alias Pinventory.NoteDiff

  describe "rows/2" do
    test "marks changed words within a line" do
      assert NoteDiff.rows("Bottom shelf", "Top shelf") == [
               {:line, [{:del, "Bottom"}, {:ins, "Top"}, {:eq, " shelf"}]}
             ]
    end

    test "collapses unchanged lines and keeps one line of context" do
      assert NoteDiff.rows("a\nb\nc\nd\ne\nf", "a\nb\nc\nd\ne\nF") == [
               {:skip, 4},
               {:line, [{:eq, "e"}]},
               {:line, [{:del, "f"}, {:ins, "F"}]}
             ]
    end

    test "keeps a lone unchanged line instead of collapsing it" do
      assert NoteDiff.rows("one\ntwo\nthree", "one\ntwo\nnew\nthree") == [
               {:line, [{:eq, "one"}]},
               {:line, [{:eq, "two"}]},
               {:line, [{:ins, "new"}]},
               {:line, [{:eq, "three"}]}
             ]
    end

    test "gives added and removed lines their own rows" do
      assert NoteDiff.rows("keep\ndrop", "keep") == [
               {:line, [{:eq, "keep"}]},
               {:line, [{:del, "drop"}]}
             ]
    end

    test "shows every line when nothing changed" do
      assert NoteDiff.rows("a\nb\nc", "a\nb\nc") == [
               {:line, [{:eq, "a"}]},
               {:line, [{:eq, "b"}]},
               {:line, [{:eq, "c"}]}
             ]
    end

    test "diffs from the empty note" do
      assert NoteDiff.rows("", "Basement fridge") == [{:line, [{:ins, "Basement fridge"}]}]
    end
  end

  test "old_side/1 and new_side/1 split one row into its two columns" do
    ops = [{:del, "Bottom"}, {:ins, "Top"}, {:eq, " shelf"}]

    assert NoteDiff.old_side(ops) == [{:del, "Bottom"}, {:eq, " shelf"}]
    assert NoteDiff.new_side(ops) == [{:ins, "Top"}, {:eq, " shelf"}]
  end

  test "counts/1 counts added and removed words" do
    assert NoteDiff.counts(NoteDiff.rows("a b c\nold line", "a x c d")) == %{
             added: 2,
             removed: 3
           }
  end
end
