defmodule Pinventory.Items.DraftStock do
  @moduledoc """
  Pure helpers for draft stock quantities keyed by location id.

  Quantities are maps of `location_id => integer` from 0 to `max_quantity/0`.
  Missing keys are treated as zero when reading; writes only update existing
  keys.
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
  Sets the quantity for a known location id, clamped to 0..`max_quantity/0`.
  Unknown ids are ignored.
  """
  def put(quantities, location_id, quantity) when is_integer(quantity) do
    if Map.has_key?(quantities, location_id) do
      Map.put(quantities, location_id, quantity |> max(0) |> min(max_quantity()))
    else
      quantities
    end
  end

  @doc """
  Adjusts the quantity for a location by `delta`, clamped like `put/3`.
  """
  def adjust(quantities, location_id, delta) when is_integer(delta) do
    put(quantities, location_id, get(quantities, location_id) + delta)
  end

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

  @max_quantity 1_000_000

  @doc """
  Largest quantity a user can enter for one location.
  """
  def max_quantity, do: @max_quantity

  @doc """
  Parses a user-entered quantity. Only a whole number from 0 to
  `max_quantity/0` is accepted. Anything else is `:error`, never 0, because 0
  removes the stock at that location.
  """
  def parse_quantity(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int in 0..@max_quantity -> {:ok, int}
      _ -> :error
    end
  end
end
