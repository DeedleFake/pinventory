defmodule Pinventory.Items.DraftStockTest do
  use ExUnit.Case, async: true

  alias Pinventory.Items.DraftStock

  defp locations do
    [%{id: "a", name: "A"}, %{id: "b", name: "B"}, %{id: "c", name: "C"}]
  end

  test "from_locations fills missing stock as zero" do
    assert DraftStock.from_locations(locations(), %{"a" => 3}) == %{
             "a" => 3,
             "b" => 0,
             "c" => 0
           }
  end

  test "adjust clamps at zero" do
    quantities = DraftStock.from_locations(locations(), %{"a" => 1})

    assert DraftStock.adjust(quantities, "a", -5)["a"] == 0
    assert DraftStock.adjust(quantities, "a", 2)["a"] == 3
  end

  test "put ignores unknown location ids" do
    quantities = DraftStock.from_locations(locations())

    assert DraftStock.put(quantities, "missing", 9) == quantities
    assert DraftStock.put(quantities, "a", 4)["a"] == 4
  end

  test "move transfers stock between known locations" do
    quantities = DraftStock.from_locations(locations(), %{"a" => 5})

    assert {:ok, moved} = DraftStock.move(quantities, "a", "b", 2)
    assert moved == %{"a" => 3, "b" => 2, "c" => 0}
  end

  test "move rejects invalid amounts and destinations" do
    quantities = DraftStock.from_locations(locations(), %{"a" => 1})

    assert DraftStock.move(quantities, "a", "b", 0) == {:error, :invalid}
    assert DraftStock.move(quantities, "a", "b", 2) == {:error, :invalid}
    assert DraftStock.move(quantities, "a", "a", 1) == {:error, :invalid}
    assert DraftStock.move(quantities, "a", "missing", 1) == {:error, :invalid}
  end

  test "total and dirty? compare draft maps" do
    baseline = DraftStock.from_locations(locations(), %{"a" => 1})
    draft = DraftStock.adjust(baseline, "b", 2)

    assert DraftStock.total(draft) == 3
    assert DraftStock.dirty?(draft, baseline)
    refute DraftStock.dirty?(baseline, baseline)
  end

  test "parse_non_neg_int normalizes user input" do
    assert DraftStock.parse_non_neg_int(" 12 ") == 12
    assert DraftStock.parse_non_neg_int("-3") == 0
    assert DraftStock.parse_non_neg_int("nope") == 0
    assert DraftStock.parse_non_neg_int(4) == 4
  end
end
