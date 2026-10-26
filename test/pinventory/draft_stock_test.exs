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

  test "adjust and put cap at max_quantity" do
    max = DraftStock.max_quantity()
    quantities = DraftStock.from_locations(locations(), %{"a" => max})

    assert DraftStock.adjust(quantities, "a", 1)["a"] == max
    assert DraftStock.put(quantities, "b", max + 5)["b"] == max
  end

  test "put ignores unknown location ids" do
    quantities = DraftStock.from_locations(locations())

    assert DraftStock.put(quantities, "missing", 9) == quantities
    assert DraftStock.put(quantities, "a", 4)["a"] == 4
  end

  test "total and dirty? compare draft maps" do
    baseline = DraftStock.from_locations(locations(), %{"a" => 1})
    draft = DraftStock.adjust(baseline, "b", 2)

    assert DraftStock.total(draft) == 3
    assert DraftStock.dirty?(draft, baseline)
    refute DraftStock.dirty?(baseline, baseline)
  end

  test "parse_quantity accepts only whole numbers in range" do
    assert DraftStock.parse_quantity(" 12 ") == {:ok, 12}
    assert DraftStock.parse_quantity("0") == {:ok, 0}
    assert DraftStock.parse_quantity("1000000") == {:ok, 1_000_000}

    for raw <- ["-3", "1.5", "", "nope", "4abc", "1000001"] do
      assert DraftStock.parse_quantity(raw) == :error
    end
  end
end
