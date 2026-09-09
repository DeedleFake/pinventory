/**
 * Pure polygon helpers for floor-plan area extend / merge.
 * Extend replaces a boundary arc a ⇝ c with a → midPoints → c.
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
