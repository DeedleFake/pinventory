defmodule PinventoryWeb.FloorPlanComponents do
  @moduledoc false
  use PinventoryWeb, :html

  alias Pinventory.FloorPlans

  attr :placement, :map, required: true
  attr :selected?, :boolean, default: false
  attr :highlighted?, :boolean, default: false
  attr :dimmed?, :boolean, default: false
  attr :show_snap?, :boolean, default: false
  attr :polygon_dom_id, :string, default: nil
  attr :navigate, :string, default: nil, doc: "when set, clicking the area navigates here"

  def placement_area(assigns) do
    location_id = assigns.placement.location_id
    points = assigns.placement.points
    {cx, cy} = FloorPlans.polygon_centroid(points)
    name = (assigns.placement.location && assigns.placement.location.name) || ""
    label = label_text(name)
    badge_w = label_badge_width(label)
    badge_h = 0.032

    assigns =
      assigns
      |> assign(:location_id, to_string(location_id))
      |> assign(:cx, cx)
      |> assign(:cy, cy)
      |> assign(:label, label)
      |> assign(:badge_w, badge_w)
      |> assign(:badge_h, badge_h)
      |> assign(:badge_x, -badge_w / 2)
      |> assign(:badge_y, -badge_h / 2)
      |> assign(:edges, placement_edges(points))
      |> assign(:group_id, "placement-group-#{location_id}")

    ~H"""
    <g
      id={@group_id}
      data-location-id={@location_id}
      phx-click={@navigate && JS.navigate(@navigate)}
      class={[
        "placement-group",
        @navigate && "cursor-pointer",
        @selected? && "is-selected",
        @highlighted? && "is-highlighted",
        @dimmed? && "is-dimmed"
      ]}
    >
      <polygon
        id={@polygon_dom_id}
        data-placement-location-id={@location_id}
        points={FloorPlans.polygon_points_attr(@placement.points)}
        class="placement-area stroke-primary"
      />
      <g :if={@show_snap?} data-placement-snap={@location_id} class="pointer-events-none">
        <line
          :for={edge <- @edges}
          data-snap-edge
          x1={edge.x1}
          y1={edge.y1}
          x2={edge.x2}
          y2={edge.y2}
          stroke="transparent"
          stroke-width="0.001"
        />
        <circle
          :for={vertex <- @placement.points}
          data-snap-vertex
          cx={point_x(vertex)}
          cy={point_y(vertex)}
          r="0.001"
          class="fill-transparent"
        />
      </g>
      <g
        class="placement-label pointer-events-none"
        transform={"translate(#{@cx}, #{@cy})"}
      >
        <rect
          class="placement-label-badge"
          x={@badge_x}
          y={@badge_y}
          width={@badge_w}
          height={@badge_h}
          rx={@badge_h / 2}
          ry={@badge_h / 2}
        />
        <text
          class="placement-label-text"
          x="0"
          y="0"
          text-anchor="middle"
          dominant-baseline="central"
          font-size="0.018"
        >
          {@label}
        </text>
      </g>
    </g>
    """
  end

  attr :id, :string, required: true

  def impassable_hatch_defs(assigns) do
    ~H"""
    <defs>
      <pattern
        id={@id}
        width="0.04"
        height="0.04"
        patternUnits="userSpaceOnUse"
        patternTransform="rotate(45)"
      >
        <line
          x1="0"
          y1="0"
          x2="0"
          y2="0.04"
          stroke="currentColor"
          stroke-width="0.01"
          stroke-opacity="0.28"
        />
      </pattern>
    </defs>
    """
  end

  attr :area, :map, required: true
  attr :hatch_id, :string, required: true
  attr :show_snap?, :boolean, default: false
  attr :erasable?, :boolean, default: false

  def impassable_area(assigns) do
    area_id = to_string(assigns.area.id)

    assigns =
      assigns
      |> assign(:area_id, area_id)
      |> assign(:group_id, "impassable-group-#{area_id}")
      |> assign(:edges, placement_edges(assigns.area.points))

    ~H"""
    <g id={@group_id} class="impassable-group">
      <polygon
        id={"impassable-#{@area_id}"}
        data-impassable-id={@area_id}
        points={FloorPlans.polygon_points_attr(@area.points)}
        class={[
          "impassable-area",
          not @erasable? && "pointer-events-none",
          @erasable? && "cursor-pointer"
        ]}
      />
      <polygon
        points={FloorPlans.polygon_points_attr(@area.points)}
        fill={"url(##{@hatch_id})"}
        class="impassable-hatch pointer-events-none"
      />
      <g :if={@show_snap?} class="pointer-events-none">
        <line
          :for={edge <- @edges}
          data-snap-edge
          x1={edge.x1}
          y1={edge.y1}
          x2={edge.x2}
          y2={edge.y2}
          stroke="transparent"
          stroke-width="0.001"
        />
        <circle
          :for={vertex <- @area.points}
          data-snap-vertex
          cx={point_x(vertex)}
          cy={point_y(vertex)}
          r="0.001"
          class="fill-transparent"
        />
      </g>
    </g>
    """
  end

  defp label_text(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> ""
      String.length(trimmed) > 18 -> String.slice(trimmed, 0, 17) <> "…"
      true -> trimmed
    end
  end

  defp label_text(_), do: ""

  defp label_badge_width(text) when is_binary(text) do
    # SVG <text> font-size 0.018 user units; ~0.62em avg glyph + pad
    char_w = 0.018 * 0.62
    pad = 0.018
    max(0.048, String.length(text) * char_w + pad)
  end

  defp placement_edges(points) when is_list(points) and length(points) >= 2 do
    points
    |> Enum.chunk_every(2, 1, [hd(points)])
    |> Enum.map(fn [a, b] ->
      %{x1: point_x(a), y1: point_y(a), x2: point_x(b), y2: point_y(b)}
    end)
  end

  defp placement_edges(_), do: []

  defp point_x(point) when is_map(point) do
    to_float(Map.get(point, "x") || Map.get(point, :x))
  end

  defp point_y(point) when is_map(point) do
    to_float(Map.get(point, "y") || Map.get(point, :y))
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0
end
