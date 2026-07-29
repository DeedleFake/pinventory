defmodule Pinventory.Items.DraftStock do
  @moduledoc """
  Pure helpers for draft stock quantities keyed by location id.

  Quantities are maps of `location_id => non_negative_integer`. Missing keys
  are treated as zero when reading; writes only update existing keys.
  """

  @doc """
  Builds a full quantity map for the given locations from a partial stock map.
  """
  def from_locations(locations, stock_map \\ %{}) do
    Map.new(locations, fn location ->
      {location.id, Map.get(stock_map, location.id, 0)}
    end)
  end

  @doc """
  Returns the quantity for a location, or 0 when missing.
  """
  def get(quantities, location_id) do
    Map.get(quantities, location_id, 0)
  end

  @doc """
  Sets the quantity for a known location id. Unknown ids are ignored.
  """
  def put(quantities, location_id, quantity) when is_integer(quantity) do
    if Map.has_key?(quantities, location_id) do
      Map.put(quantities, location_id, max(quantity, 0))
    else
      quantities
    end
  end

  @doc """
  Adjusts the quantity for a location by `delta` (clamped at zero).
  """
  def adjust(quantities, location_id, delta) when is_integer(delta) do
    put(quantities, location_id, get(quantities, location_id) + delta)
  end

  @doc """
  Moves `amount` from one location to another.

  Returns `{:ok, quantities}` or `{:error, :invalid}`.
  """
  def move(quantities, from_id, to_id, amount)
      when is_integer(amount) and amount >= 1 and from_id != to_id do
    from_qty = get(quantities, from_id)

    if amount <= from_qty and Map.has_key?(quantities, from_id) and
         Map.has_key?(quantities, to_id) do
      {:ok,
       quantities
       |> Map.put(from_id, from_qty - amount)
       |> Map.put(to_id, get(quantities, to_id) + amount)}
    else
      {:error, :invalid}
    end
  end

  def move(_quantities, _from_id, _to_id, _amount), do: {:error, :invalid}

  @doc """
  Sums all quantities in the draft map.
  """
  def total(quantities) do
    quantities
    |> Map.values()
    |> Enum.sum()
  end

  @doc """
  Returns true when the draft differs from the baseline map.
  """
  def dirty?(quantities, baseline), do: quantities != baseline

  @doc """
  Parses a user-entered value into a non-negative integer (default 0).
  """
  def parse_non_neg_int(value) when is_integer(value), do: max(value, 0)

  def parse_non_neg_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> max(int, 0)
      :error -> 0
    end
  end

  def parse_non_neg_int(_), do: 0
end
