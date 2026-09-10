/**
 * Pure geometry helpers for the floor-plan canvas.
 *
 * Polygon extend / merge: replace a boundary arc a ⇝ c with a → midPoints → c.
 *
 * Angle snap: while drafting, Shift constrains the free endpoint to the nearest
 * 22.5° ray from the last fixed point (16 directions). For polygons with a
 * closing anchor, Shift may also meet a horizontal/vertical through that
 * vertex — only when the cursor is near that axis (like geometry line snap).
 */

function copyPoint(p) {
  return {x: p.x, y: p.y}
}

/** Cross-product orientation: >0 CCW, <0 CW, 0 collinear. */
function orient(a, b, c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

/**
 * True when open segments ab and cd properly intersect (cross interiors).
 * Endpoint touches alone are not intersections.
 */
export function segmentsIntersect(a, b, c, d) {
  const o1 = orient(a, b, c)
  const o2 = orient(a, b, d)
  const o3 = orient(c, d, a)
  const o4 = orient(c, d, b)
  return o1 * o2 < 0 && o3 * o4 < 0
}

export function polygonSelfIntersects(pts) {
  const n = pts.length
  if (n < 4) return false

  for (let i = 0; i < n; i++) {
    const a = pts[i]
    const b = pts[(i + 1) % n]
    for (let j = i + 1; j < n; j++) {
      // Skip the same edge and edges that share a vertex (adjacent in the ring).
      if ((i + 1) % n === j || (j + 1) % n === i) continue
      const c = pts[j]
      const d = pts[(j + 1) % n]
      if (segmentsIntersect(a, b, c, d)) return true
    }
  }
  return false
}

/** Signed shoelace area (positive ≈ CCW). */
export function polygonArea(pts) {
  let sum = 0
  const n = pts.length
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n
    sum += pts[i].x * pts[j].y - pts[j].x * pts[i].y
  }
  return sum / 2
}

export function arcIntermediateCount(n, fromIdx, toIdx, direction) {
  if (fromIdx === toIdx) return n
  const step = direction === "forward" ? 1 : -1
  let count = 0
  let i = fromIdx
  for (;;) {
    i = (i + step + n) % n
    if (i === toIdx) return count
    count++
    if (count > n) return n
  }
}

/**
 * Replace ring arc fromIdx ⇝ toIdx in `direction` with from → midPoints → to.
 * Complementary arc from to back to from (same direction) is kept.
 */
export function replaceRingArc(ring, fromIdx, toIdx, direction, midPoints) {
  const n = ring.length
  if (n < 3) return ring.map(copyPoint)
  if (fromIdx === toIdx) {
    throw new Error("replaceRingArc requires distinct from/to indices")
  }

  const step = direction === "forward" ? 1 : -1
  const complementary = []
  let i = toIdx
  for (;;) {
    complementary.push(copyPoint(ring[i]))
    i = (i + step + n) % n
    if (i === fromIdx) break
  }

  return [copyPoint(ring[fromIdx]), ...midPoints.map(copyPoint), ...complementary]
}

function pointOutsideEdge(a, neighbor, probe, signedArea) {
  const ex = neighbor.x - a.x
  const ey = neighbor.y - a.y
  const nx = probe.x - a.x
  const ny = probe.y - a.y
  const cross = ex * ny - ey * nx
  // Interior is to the left of each edge for CCW rings (signedArea > 0).
  return signedArea >= 0 ? cross < 0 : cross > 0
}

function pickBestCandidate(candidates) {
  const simple = candidates.filter((c) => c.simple)
  const pool = simple.length > 0 ? simple : candidates
  pool.sort((x, y) => {
    if (x.intermediates !== y.intermediates) return x.intermediates - y.intermediates
    return y.absArea - x.absArea
  })
  return pool[0].result
}

function mergeBetween(ring, attachIdx, closeIdx, midPoints) {
  const n = ring.length
  const candidates = ["forward", "backward"].map((direction) => {
    const result = replaceRingArc(ring, attachIdx, closeIdx, direction, midPoints)
    return {
      result,
      direction,
      intermediates: arcIntermediateCount(n, attachIdx, closeIdx, direction),
      simple: !polygonSelfIntersects(result),
      absArea: Math.abs(polygonArea(result)),
    }
  })
  return pickBestCandidate(candidates).map(copyPoint)
}

/**
 * Done / close-to-attach: replace one adjacent edge with a → midPoints → neighbor.
 * Prefer simple, outward (outside of edge / larger |area|) expansions.
 */
function mergeAdjacentAuto(ring, attachIdx, midPoints) {
  const n = ring.length
  const signed = polygonArea(ring)
  const origAbs = Math.abs(signed)
  const firstNew = midPoints[0]
  const a = ring[attachIdx]

  const opts = [
    {toIdx: (attachIdx + 1) % n, direction: "forward"},
    {toIdx: (attachIdx - 1 + n) % n, direction: "backward"},
  ]

  const scored = opts.map(({toIdx, direction}) => {
    const result = replaceRingArc(ring, attachIdx, toIdx, direction, midPoints)
    const absArea = Math.abs(polygonArea(result))
    const simple = !polygonSelfIntersects(result)
    const outside =
      firstNew != null ? pointOutsideEdge(a, ring[toIdx], firstNew, signed) : false
    const expands = absArea > origAbs + 1e-12
    return {result, simple, absArea, outside, expands, toIdx, direction}
  })

  const simple = scored.filter((c) => c.simple)
  const pool = simple.length > 0 ? simple : scored
  pool.sort((x, y) => {
    const sx = (x.outside ? 2 : 0) + (x.expands ? 1 : 0)
    const sy = (y.outside ? 2 : 0) + (y.expands ? 1 : 0)
    if (sy !== sx) return sy - sx
    return y.absArea - x.absArea
  })
  return pool[0].result.map(copyPoint)
}

/**
 * Merge an extension chain into an existing ring.
 *
 * draft.points[0] is the attach vertex; points[1..] are new intermediate vertices.
 * closeIndex: existing vertex to close on. When omitted or equal to attachIndex,
 * auto-picks an adjacent neighbor (Done). Explicit close must use a different vertex.
 */
export function mergeExtension(draft) {
  const existing = draft.existing
  const attachIdx = draft.attachIndex
  const newPoints = (draft.points || []).slice(1)

  if (!existing || existing.length < 3) return null
  if (!Number.isInteger(attachIdx) || attachIdx < 0 || attachIdx >= existing.length) {
    return null
  }
  if (newPoints.length < 1) return null

  const closeIdx =
    typeof draft.closeIndex === "number" ? draft.closeIndex : attachIdx

  if (closeIdx === attachIdx) {
    return mergeAdjacentAuto(existing, attachIdx, newPoints)
  }

  if (closeIdx < 0 || closeIdx >= existing.length) return null

  return mergeBetween(existing, attachIdx, closeIdx, newPoints)
}


/**
 * Nearest vertex within maxDist, or null.
 * Returns {index, point} with a copied point.
 */
export function nearestVertexWithin(point, vertices, maxDist) {
  if (!point || !vertices || vertices.length === 0) return null
  let best = null
  let bestDist = maxDist
  for (let i = 0; i < vertices.length; i++) {
    const ep = vertices[i]
    const d = Math.hypot(ep.x - point.x, ep.y - point.y)
    if (d <= bestDist) {
      bestDist = d
      best = {index: i, point: copyPoint(ep)}
    }
  }
  return best
}

/**
 * Provisional close index for draft preview while dragging:
 * nearest existing vertex (≠ attach) within closeDist, else attach (adjacent auto).
 */
export function provisionalCloseIndex(existing, attachIndex, cursor, closeDist) {
  if (!cursor || !existing || existing.length < 3) return attachIndex
  let best = null
  let bestDist = closeDist
  for (let i = 0; i < existing.length; i++) {
    if (i === attachIndex) continue
    const ep = existing[i]
    const d = Math.hypot(ep.x - cursor.x, ep.y - cursor.y)
    if (d <= bestDist) {
      bestDist = d
      best = i
    }
  }
  return best == null ? attachIndex : best
}


/** 22.5° in radians — 16 directions around the circle. */
export const ANGLE_SNAP_STEP = Math.PI / 8

/**
 * Project `point` onto the ray from `anchor` at the nearest 22.5° multiple
 * (0°, 22.5°, …, 337.5°). Preserves distance from anchor to point.
 * Returns a copied `{x, y}`; degenerate (zero-length) returns the anchor.
 */
export function angleSnapPoint(anchor, point) {
  if (!anchor || !point) return point ? copyPoint(point) : point
  const dx = point.x - anchor.x
  const dy = point.y - anchor.y
  const dist = Math.hypot(dx, dy)
  if (dist < 1e-12) return copyPoint(anchor)
  const angle = Math.atan2(dy, dx)
  const snapped = Math.round(angle / ANGLE_SNAP_STEP) * ANGLE_SNAP_STEP
  return {
    x: anchor.x + Math.cos(snapped) * dist,
    y: anchor.y + Math.sin(snapped) * dist,
  }
}

/** Angle on the 22.5° grid nearest the vector from `anchor` toward `point`. */
export function nearestAngleStep(anchor, point) {
  if (!anchor || !point) return 0
  const dx = point.x - anchor.x
  const dy = point.y - anchor.y
  if (Math.hypot(dx, dy) < 1e-12) return 0
  const angle = Math.atan2(dy, dx)
  return Math.round(angle / ANGLE_SNAP_STEP) * ANGLE_SNAP_STEP
}

/**
 * Intersection of two infinite lines through points with given directions.
 * Returns null when parallel (or nearly).
 */
export function lineIntersection(a, angleA, b, angleB) {
  if (!a || !b) return null
  const dax = Math.cos(angleA)
  const day = Math.sin(angleA)
  const dbx = Math.cos(angleB)
  const dby = Math.sin(angleB)
  const det = dax * dby - day * dbx
  if (Math.abs(det) < 1e-12) return null
  const ox = b.x - a.x
  const oy = b.y - a.y
  const t = (ox * dby - oy * dbx) / det
  return {x: a.x + dax * t, y: a.y + day * t}
}

/** Horizontal / vertical only — secondary (closing) dual-snap edge. */
const AXIS_ANGLES = [0, Math.PI / 2, Math.PI, -Math.PI / 2]

/** Same order as canvas SNAP_DISTANCE — how near the cursor must be to engage. */
export const DUAL_AXIS_SNAP_DISTANCE = 0.03

/**
 * Shift-snap a free polygon vertex.
 * Newest edge (`prev`) always uses the full 22.5° grid. Closing edge (`next`)
 * is optional: only H/V through `next`, and only when the cursor is within
 * `threshold` of that axis (like snapping to an existing wall/edge). Otherwise
 * returns single-edge snap from `prev`.
 */
export function angleSnapPointDual(prev, next, point, threshold = DUAL_AXIS_SNAP_DISTANCE) {
  if (!prev || !point) return point ? copyPoint(point) : point
  const single = angleSnapPoint(prev, point)
  if (!next) return single

  const preferAngle = nearestAngleStep(prev, point)
  let best = null
  let bestDist = Infinity

  for (const angleNext of AXIS_ANGLES) {
    // Distance from cursor to the infinite H or V through `next`.
    const axisDist =
      Math.abs(Math.cos(angleNext)) < 1e-9
        ? Math.abs(point.x - next.x) // vertical
        : Math.abs(point.y - next.y) // horizontal
    if (axisDist > threshold) continue

    const hit = lineIntersection(prev, preferAngle, next, angleNext)
    if (!hit) continue
    const d = Math.hypot(hit.x - point.x, hit.y - point.y)
    if (d < bestDist) {
      best = hit
      bestDist = d
    }
  }

  return best || single
}

/**
 * Perpendicular distance from `point` to the infinite line through `a` and `b`.
 * Returns 0 when `a` and `b` coincide.
 */
export function distanceToLine(point, a, b) {
  if (!point || !a || !b) return Infinity
  const dx = b.x - a.x
  const dy = b.y - a.y
  const len = Math.hypot(dx, dy)
  if (len < 1e-12) return Math.hypot(point.x - a.x, point.y - a.y)
  return Math.abs(dx * (a.y - point.y) - dy * (a.x - point.x)) / len
}
