defmodule Pinventory.FloorPlans.Geometry do
  @moduledoc """
  Pure geometry helpers for floor-plan walls and location polygons.

  Used to merge collinear connecting walls and drop extraneous collinear
  polygon vertices so the database stays free of redundant geometry.
  """

  # Unit-square coords; slightly loose so float endpoints still merge.
  @eps 1.0e-5
  @collinear_eps 1.0e-4
  @min_remainder_length 0.02

  @type point :: {number(), number()}
  @type segment :: {point(), point()}

  @doc """
  True when two points are within `eps` (default #{@eps}).
  """
  def points_equal?({x1, y1}, {x2, y2}, eps \\ @eps)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) do
    abs(x1 - x2) <= eps and abs(y1 - y2) <= eps
  end

  @doc """
  True when `b` lies on the line through `a` and `c` (cross product ≈ 0).
  """
  def collinear_points?(a, b, c, eps \\ @collinear_eps) do
    {ax, ay} = a
    {bx, by} = b
    {cx, cy} = c
    cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    abs(cross) <= eps
  end

  @doc """
  True when segments share an endpoint (within eps) and lie on the same line.
  Parallel but non-touching segments are false.
  """
  def collinear_connected?(seg_a, seg_b) do
    share_endpoint?(seg_a, seg_b) and segments_collinear?(seg_a, seg_b)
  end

  @doc """
  Outermost endpoints of two collinear segments as `{x1, y1, x2, y2}` map keys
  matching wall attrs (`:x1`, `:y1`, `:x2`, `:y2`).
  """
  def merge_segment_span({{x1, y1}, {x2, y2}} = _a, {{x3, y3}, {x4, y4}} = _b) do
    pts = [{x1, y1}, {x2, y2}, {x3, y3}, {x4, y4}]
    dx = x2 - x1
    dy = y2 - y1

    {dx, dy} =
      if abs(dx) < @eps and abs(dy) < @eps do
        {x4 - x3, y4 - y3}
      else
        {dx, dy}
      end

    sorted =
      if abs(dx) >= abs(dy) do
        Enum.sort_by(pts, fn {x, _y} -> x end)
      else
        Enum.sort_by(pts, fn {_x, y} -> y end)
      end

    {ox1, oy1} = hd(sorted)
    {ox2, oy2} = List.last(sorted)

    %{x1: ox1 * 1.0, y1: oy1 * 1.0, x2: ox2 * 1.0, y2: oy2 * 1.0}
  end

  @doc """
  Absorb every existing wall that is collinear and endpoint-connected with the
  growing segment. Returns `{merged_coords, walls_to_delete}`.
  """
  def merge_wall_into_existing(existing_walls, %{x1: _, y1: _, x2: _, y2: _} = new_coords)
      when is_list(existing_walls) do
    new_seg = wall_to_segment(new_coords)
    absorb_walls(existing_walls, new_seg, [])
  end

  @doc """
  Parameter `t` in `[0, 1]` and the clamped point of `point` on `seg`.
  """
  def project_point_on_segment(%{x1: x1, y1: y1, x2: x2, y2: y2}, {px, py})
      when is_number(px) and is_number(py) do
    dx = x2 - x1
    dy = y2 - y1

    t =
      cond do
        abs(dx) <= @eps and abs(dy) <= @eps ->
          0.0

        true ->
          (((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy))
          |> max(0.0)
          |> min(1.0)
      end

    {t * 1.0, {x1 + t * dx, y1 + t * dy}}
  end

  @doc """
  Cut the open segment `seg` on `[t0, t1]` (order-independent, clamped to `[0, 1]`).

  Returns remainder coord maps. A remainder shorter than #{@min_remainder_length}
  is dropped. Empty list means the whole segment was removed. When `t0` and `t1`
  are within eps, returns the original segment as the sole remainder.
  """
  def cut_segment(%{x1: x1, y1: y1, x2: x2, y2: y2}, t0, t1)
      when is_number(t0) and is_number(t1) do
    t0 = t0 |> max(0.0) |> min(1.0)
    t1 = t1 |> max(0.0) |> min(1.0)
    {t_lo, t_hi} = if t0 <= t1, do: {t0, t1}, else: {t1, t0}

    if abs(t_hi - t_lo) <= @eps do
      [segment_to_coords({{x1, y1}, {x2, y2}})]
    else
      dx = x2 - x1
      dy = y2 - y1
      at = fn t -> {x1 + t * dx, y1 + t * dy} end

      [
        remainder_coords({x1, y1}, at.(t_lo)),
        remainder_coords(at.(t_hi), {x2, y2})
      ]
      |> Enum.filter(& &1)
    end
  end

  @doc """
  Drop vertices that are collinear with both neighbors on a closed polygon.
  Repeats until stable; always keeps at least three vertices.
  Accepts `%{"x" => _, "y" => _}` maps (and atom-key maps).
  """
  def drop_collinear_polygon_vertices(points) when is_list(points) do
    do_drop_collinear(points)
  end

  defp do_drop_collinear(points) when length(points) <= 3, do: points

  defp do_drop_collinear(points) do
    n = length(points)

    kept =
      points
      |> Enum.with_index()
      |> Enum.reject(fn {_p, i} ->
        prev = Enum.at(points, rem(i - 1 + n, n))
        curr = Enum.at(points, i)
        next = Enum.at(points, rem(i + 1, n))

        collinear_points?(point_tuple(prev), point_tuple(curr), point_tuple(next))
      end)
      |> Enum.map(&elem(&1, 0))

    cond do
      length(kept) < 3 -> points
      length(kept) == length(points) -> kept
      true -> do_drop_collinear(kept)
    end
  end

  defp remainder_coords({x1, y1}, {x2, y2}) do
    len = :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))

    if len < @min_remainder_length do
      nil
    else
      %{x1: x1 * 1.0, y1: y1 * 1.0, x2: x2 * 1.0, y2: y2 * 1.0}
    end
  end

  defp absorb_walls(remaining, seg, deleted) do
    {mergeable, rest} =
      Enum.split_with(remaining, &collinear_connected?(seg, wall_to_segment(&1)))

    case mergeable do
      [] ->
        {segment_to_coords(seg), deleted}

      _ ->
        merged =
          Enum.reduce(mergeable, seg, fn wall, acc ->
            span = merge_segment_span(acc, wall_to_segment(wall))
            {{span.x1, span.y1}, {span.x2, span.y2}}
          end)

        absorb_walls(rest, merged, deleted ++ mergeable)
    end
  end

  defp share_endpoint?({{a1, a2}, {b1, b2}}, {{c1, c2}, {d1, d2}}) do
    ends_a = [{a1, a2}, {b1, b2}]
    ends_b = [{c1, c2}, {d1, d2}]
    Enum.any?(ends_a, fn pa -> Enum.any?(ends_b, &points_equal?(pa, &1)) end)
  end

  defp segments_collinear?({{a, b}, {c, d}}, {{e, f}, {g, h}}) do
    # All four points on one line: both endpoints of B on line through A.
    collinear_points?({a, b}, {c, d}, {e, f}) and collinear_points?({a, b}, {c, d}, {g, h})
  end

  defp wall_to_segment(%{x1: x1, y1: y1, x2: x2, y2: y2}), do: {{x1, y1}, {x2, y2}}

  defp wall_to_segment(wall) when is_map(wall) do
    x1 = Map.get(wall, :x1) || Map.get(wall, "x1")
    y1 = Map.get(wall, :y1) || Map.get(wall, "y1")
    x2 = Map.get(wall, :x2) || Map.get(wall, "x2")
    y2 = Map.get(wall, :y2) || Map.get(wall, "y2")
    {{x1, y1}, {x2, y2}}
  end

  defp segment_to_coords({{x1, y1}, {x2, y2}}) do
    %{x1: x1 * 1.0, y1: y1 * 1.0, x2: x2 * 1.0, y2: y2 * 1.0}
  end

  defp point_tuple(%{"x" => x, "y" => y}), do: {x, y}
  defp point_tuple(%{x: x, y: y}), do: {x, y}

  defp point_tuple(point) when is_map(point) do
    {Map.get(point, "x") || Map.get(point, :x), Map.get(point, "y") || Map.get(point, :y)}
  end
end
