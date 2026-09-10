import assert from "node:assert/strict"
import {describe, it} from "node:test"
import {
  ANGLE_SNAP_STEP,
  angleSnapPoint,
  angleSnapPointDual,
  lineIntersection,
  nearestAngleStep,
  distanceToLine,
  segmentHitOnAngleLine,
  snapOnAngleLine,
  measurementLabelPose,
  lengthInFeet,
  formatFeet,
  DEFAULT_FEET_PER_UNIT,
  mergeExtension,
  nearestVertexWithin,
  polygonArea,
  polygonSelfIntersects,
  replaceRingArc,
  segmentsIntersect,
  contentBoundsFromSegments,
  fitSquareCamera,
} from "./floor_plan_geometry.js"

const triangle = [
  {x: 0.2, y: 0.2},
  {x: 0.8, y: 0.2},
  {x: 0.5, y: 0.8},
]

function pts(list) {
  return list.map(([x, y]) => ({x, y}))
}

describe("segmentsIntersect / polygonSelfIntersects", () => {
  it("detects proper crossings and ignores shared endpoints", () => {
    assert.equal(
      segmentsIntersect({x: 0, y: 0}, {x: 1, y: 1}, {x: 0, y: 1}, {x: 1, y: 0}),
      true,
    )
    assert.equal(
      segmentsIntersect({x: 0, y: 0}, {x: 1, y: 0}, {x: 1, y: 0}, {x: 2, y: 0}),
      false,
    )
  })

  it("flags hourglass quads", () => {
    const bowtie = pts([
      [0, 0],
      [1, 1],
      [1, 0],
      [0, 1],
    ])
    assert.equal(polygonSelfIntersects(bowtie), true)
    assert.equal(polygonSelfIntersects(triangle), false)
  })
})

describe("replaceRingArc", () => {
  it("replaces a forward adjacent edge", () => {
    const mid = pts([[0.2, 0.5]])
    const result = replaceRingArc(triangle, 0, 1, "forward", mid)
    assert.deepEqual(
      result.map((p) => [p.x, p.y]),
      [
        [0.2, 0.2],
        [0.2, 0.5],
        [0.8, 0.2],
        [0.5, 0.8],
      ],
    )
  })

  it("replaces a backward adjacent edge", () => {
    const mid = pts([[0.2, 0.5]])
    const result = replaceRingArc(triangle, 0, 2, "backward", mid)
    assert.deepEqual(
      result.map((p) => [p.x, p.y]),
      [
        [0.2, 0.2],
        [0.2, 0.5],
        [0.5, 0.8],
        [0.8, 0.2],
      ],
    )
  })
})

describe("mergeExtension triangle → quad", () => {
  it("Done auto-picks adjacent edge that expands outward (no hourglass)", () => {
    const draft = {
      existing: triangle,
      attachIndex: 0,
      points: [triangle[0], {x: 0.05, y: 0.5}],
      closeIndex: 0,
    }
    const merged = mergeExtension(draft)
    assert.ok(merged)
    assert.equal(merged.length, 4)
    assert.equal(polygonSelfIntersects(merged), false)
    assert.ok(Math.abs(polygonArea(merged)) > Math.abs(polygonArea(triangle)))
  })

  it("Done chooses the non-crossing adjacent when one side hourglasses", () => {
    // Forward splice onto edge 0→1 crosses; backward onto 0→2 stays simple.
    const newPt = {x: 0.1, y: 0.9}
    const forward = replaceRingArc(triangle, 0, 1, "forward", [newPt])
    const backward = replaceRingArc(triangle, 0, 2, "backward", [newPt])
    assert.equal(polygonSelfIntersects(forward), true)
    assert.equal(polygonSelfIntersects(backward), false)

    const merged = mergeExtension({
      existing: triangle,
      attachIndex: 0,
      points: [triangle[0], newPt],
    })
    assert.ok(merged)
    assert.equal(polygonSelfIntersects(merged), false)
    assert.equal(merged.length, 4)
    assert.deepEqual(
      merged.map((p) => [p.x, p.y]),
      backward.map((p) => [p.x, p.y]),
    )
  })

  it("explicit close to another vertex prefers the shorter simple arc", () => {
    const newPt = {x: 0.0, y: 0.3}
    const short = replaceRingArc(triangle, 0, 2, "backward", [newPt])
    const long = replaceRingArc(triangle, 0, 2, "forward", [newPt])
    assert.equal(short.length, 4)
    assert.equal(long.length, 3)
    assert.equal(polygonSelfIntersects(short), false)
    assert.equal(polygonSelfIntersects(long), false)

    const merged = mergeExtension({
      existing: triangle,
      attachIndex: 0,
      closeIndex: 2,
      points: [triangle[0], newPt],
    })
    assert.ok(merged)
    assert.equal(merged.length, 4)
    assert.equal(polygonSelfIntersects(merged), false)
    assert.deepEqual(
      merged.map((p) => [p.x, p.y]),
      short.map((p) => [p.x, p.y]),
    )
  })

  it("explicit close prefers the simple arc when the short one hourglasses", () => {
    // Short backward 0→2 crosses the bottom edge; long forward drops mid vertex and stays simple.
    const newPt = {x: 0.5, y: 0.05}
    const short = replaceRingArc(triangle, 0, 2, "backward", [newPt])
    const long = replaceRingArc(triangle, 0, 2, "forward", [newPt])
    assert.equal(polygonSelfIntersects(short), true)
    assert.equal(polygonSelfIntersects(long), false)

    const merged = mergeExtension({
      existing: triangle,
      attachIndex: 0,
      closeIndex: 2,
      points: [triangle[0], newPt],
    })
    assert.ok(merged)
    assert.equal(merged.length, 3)
    assert.equal(polygonSelfIntersects(merged), false)
    assert.deepEqual(
      merged.map((p) => [p.x, p.y]),
      long.map((p) => [p.x, p.y]),
    )
  })

  it("returns null without new intermediate points", () => {
    assert.equal(
      mergeExtension({
        existing: triangle,
        attachIndex: 0,
        points: [triangle[0]],
      }),
      null,
    )
  })
})

describe("nearestVertexWithin", () => {
  const ring = pts([
    [0.2, 0.2],
    [0.8, 0.2],
    [0.5, 0.8],
  ])

  it("returns the nearest vertex inside maxDist", () => {
    const hit = nearestVertexWithin({x: 0.21, y: 0.22}, ring, 0.03)
    assert.ok(hit)
    assert.equal(hit.index, 0)
    assert.deepEqual([hit.point.x, hit.point.y], [0.2, 0.2])
  })

  it("returns null when outside maxDist", () => {
    assert.equal(nearestVertexWithin({x: 0.5, y: 0.5}, ring, 0.03), null)
  })

  it("prefers the closer of two nearby vertices", () => {
    const hit = nearestVertexWithin({x: 0.79, y: 0.21}, ring, 0.05)
    assert.ok(hit)
    assert.equal(hit.index, 1)
  })
})


describe("angleSnapPoint", () => {
  const origin = {x: 0.5, y: 0.5}

  it("uses 22.5° steps (16 directions)", () => {
    assert.equal(ANGLE_SNAP_STEP, Math.PI / 8)
  })

  it("snaps near-horizontal to 0°", () => {
    const p = angleSnapPoint(origin, {x: 0.8, y: 0.51})
    assert.ok(Math.abs(p.y - 0.5) < 1e-9)
    assert.ok(p.x > 0.5)
  })

  it("snaps near-vertical to 90°", () => {
    const p = angleSnapPoint(origin, {x: 0.51, y: 0.8})
    assert.ok(Math.abs(p.x - 0.5) < 1e-9)
    assert.ok(p.y > 0.5)
  })

  it("snaps to 45° when closer than 22.5°/67.5°", () => {
    // 40° from +x should round to 45° (π/4)
    const rad = (40 * Math.PI) / 180
    const raw = {x: origin.x + Math.cos(rad) * 0.2, y: origin.y + Math.sin(rad) * 0.2}
    const p = angleSnapPoint(origin, raw)
    const angle = Math.atan2(p.y - origin.y, p.x - origin.x)
    assert.ok(Math.abs(angle - Math.PI / 4) < 1e-9)
    assert.ok(Math.abs(Math.hypot(p.x - origin.x, p.y - origin.y) - 0.2) < 1e-9)
  })

  it("snaps to 22.5°", () => {
    const rad = (20 * Math.PI) / 180
    const raw = {x: origin.x + Math.cos(rad), y: origin.y + Math.sin(rad)}
    const p = angleSnapPoint(origin, raw)
    const angle = Math.atan2(p.y - origin.y, p.x - origin.x)
    assert.ok(Math.abs(angle - Math.PI / 8) < 1e-9)
  })

  it("returns the anchor for zero-length", () => {
    assert.deepEqual(angleSnapPoint(origin, {x: 0.5, y: 0.5}), {x: 0.5, y: 0.5})
  })
})

describe("distanceToLine", () => {
  it("is zero on the line and positive off it", () => {
    const a = {x: 0, y: 0}
    const b = {x: 1, y: 0}
    assert.equal(distanceToLine({x: 0.5, y: 0}, a, b), 0)
    assert.ok(Math.abs(distanceToLine({x: 0.5, y: 0.1}, a, b) - 0.1) < 1e-9)
  })
})

describe("angleSnapPointDual", () => {
  it("places a rectangle corner when near the closing axis", () => {
    // A(0.2,0.2) → … → C(0.8,0.7), drafting near vertical through A
    const prev = {x: 0.8, y: 0.7}
    const next = {x: 0.2, y: 0.2}
    const raw = {x: 0.22, y: 0.68}
    const p = angleSnapPointDual(prev, next, raw)
    assert.ok(Math.abs(p.x - 0.2) < 1e-9)
    assert.ok(Math.abs(p.y - 0.7) < 1e-9)
  })

  it("falls back to newest-edge snap when next is null", () => {
    const prev = {x: 0.5, y: 0.5}
    const raw = {x: 0.8, y: 0.51}
    const p = angleSnapPointDual(prev, null, raw)
    assert.ok(Math.abs(p.y - 0.5) < 1e-9)
  })

  it("ignores closing axis when the cursor is too far", () => {
    const prev = {x: 0.8, y: 0.7}
    const next = {x: 0.2, y: 0.2}
    // Far from both x=0.2 and y=0.2 — newest-edge only (horizontal from prev)
    const raw = {x: 0.5, y: 0.71}
    const p = angleSnapPointDual(prev, next, raw)
    assert.ok(Math.abs(p.y - 0.7) < 1e-9)
    assert.ok(Math.abs(p.x - 0.2) > 0.05)
  })

  it("secondary snap is horizontal/vertical only", () => {
    const prev = {x: 0.5, y: 0.5}
    const next = {x: 0.2, y: 0.35}
    // Near vertical through next; newest prefers ~0°
    const raw = {x: 0.215, y: 0.5}
    const p = angleSnapPointDual(prev, next, raw)
    assert.ok(Math.abs(p.x - 0.2) < 1e-9)
    assert.ok(Math.abs(p.y - 0.5) < 1e-9)
  })
})

describe("lineIntersection", () => {
  it("finds axis crossing", () => {
    const p = lineIntersection({x: 0, y: 0.7}, 0, {x: 0.2, y: 0}, Math.PI / 2)
    assert.ok(Math.abs(p.x - 0.2) < 1e-9)
    assert.ok(Math.abs(p.y - 0.7) < 1e-9)
  })
})

describe("contentBoundsFromSegments", () => {
  it("returns the default unit square when empty", () => {
    assert.deepEqual(contentBoundsFromSegments([]), {
      minX: 0,
      minY: 0,
      maxX: 1,
      maxY: 1,
    })
  })

  it("unions segment endpoints including outside [0,1]", () => {
    const bounds = contentBoundsFromSegments([
      [
        {x: -0.5, y: 0.2},
        {x: 1.5, y: 0.8},
      ],
      {x1: 0, y1: -1, x2: 0.1, y2: 2},
    ])
    assert.equal(bounds.minX, -0.5)
    assert.equal(bounds.minY, -1)
    assert.equal(bounds.maxX, 1.5)
    assert.equal(bounds.maxY, 2)
  })
})

describe("fitSquareCamera", () => {
  it("pads content into a centered square viewBox", () => {
    const cam = fitSquareCamera({minX: 0, minY: 0, maxX: 1, maxY: 0.5}, 0.08)
    // span = 1 → size = 1.16; center (0.5, 0.25)
    assert.ok(Math.abs(cam.size - 1.16) < 1e-9)
    assert.ok(Math.abs(cam.x - (0.5 - 0.58)) < 1e-9)
    assert.ok(Math.abs(cam.y - (0.25 - 0.58)) < 1e-9)
  })

  it("uses size 1 for a degenerate point bound", () => {
    const cam = fitSquareCamera({minX: 2, minY: 3, maxX: 2, maxY: 3}, 0.08)
    assert.ok(Math.abs(cam.size - 1.16) < 1e-9)
    assert.ok(Math.abs(cam.x - (2 - 0.58)) < 1e-9)
    assert.ok(Math.abs(cam.y - (3 - 0.58)) < 1e-9)
  })

  it("roomier padding leaves empty world outside unit content", () => {
    const cam = fitSquareCamera({minX: 0, minY: 0, maxX: 1, maxY: 1}, 0.5)
    assert.ok(Math.abs(cam.size - 2) < 1e-9)
    assert.ok(cam.x < 0 && cam.y < 0)
    assert.ok(cam.x + cam.size > 1 && cam.y + cam.size > 1)
  })
})

describe("snapOnAngleLine", () => {
  it("snaps to a segment only at the angle-line intersection", () => {
    const anchor = {x: 0, y: 0}
    // Horizontal angle toward (1, 0); nearby diagonal wall from (0.8,-0.2) to (0.8,0.2)
    const rayPoint = {x: 0.85, y: 0}
    const segs = [[{x: 0.8, y: -0.2}, {x: 0.8, y: 0.2}]]
    const hit = snapOnAngleLine(anchor, rayPoint, segs, [], 0.1)
    assert.ok(hit)
    assert.ok(Math.abs(hit.x - 0.8) < 1e-9)
    assert.ok(Math.abs(hit.y - 0) < 1e-9)
  })

  it("ignores a nearby segment that does not cross the angle line within range", () => {
    const anchor = {x: 0, y: 0}
    const rayPoint = {x: 0.5, y: 0}
    // Parallel horizontal segment above the ray — never intersects y=0 line usefully as a vertical? 
    // Horizontal segment y=0.05 from x=0.4 to 0.6: angle line is y=0, parallel, no hit
    const segs = [[{x: 0.4, y: 0.05}, {x: 0.6, y: 0.05}]]
    const hit = snapOnAngleLine(anchor, rayPoint, segs, [], 0.03)
    assert.equal(hit, null)
  })

  it("prefers a vertex that lies on the angle line", () => {
    const anchor = {x: 0, y: 0}
    const rayPoint = {x: 0.55, y: 0}
    const verts = [{x: 0.5, y: 0}, {x: 0.5, y: 0.02}]
    const hit = snapOnAngleLine(anchor, rayPoint, [], verts, 0.1)
    assert.ok(hit)
    assert.ok(Math.abs(hit.y) < 1e-9)
    assert.ok(Math.abs(hit.x - 0.5) < 1e-9)
  })
})

describe("measurement labels", () => {
  it("reports feet from world length and default scale", () => {
    const ft = lengthInFeet({x: 0, y: 0}, {x: 0.5, y: 0}, DEFAULT_FEET_PER_UNIT)
    assert.ok(Math.abs(ft - 20) < 1e-9)
    assert.equal(formatFeet(20), "20 ft")
    assert.equal(formatFeet(3.2), "3.2 ft")
  })

  it("keeps label angles readable (never upside-down)", () => {
    const right = measurementLabelPose({x: 0, y: 0}, {x: 1, y: 0}, 0.03)
    assert.ok(Math.abs(right.angleDeg) < 1e-6)
    const left = measurementLabelPose({x: 1, y: 0}, {x: 0, y: 0}, 0.03)
    assert.ok(Math.abs(left.angleDeg) < 1e-6)
    const up = measurementLabelPose({x: 0, y: 1}, {x: 0, y: 0}, 0.03)
    assert.ok(up.angleDeg > -90 && up.angleDeg <= 90)
    const steep = measurementLabelPose({x: 0, y: 0}, {x: -1, y: 0.1}, 0.03)
    assert.ok(steep.angleDeg > -90 && steep.angleDeg <= 90)
  })
})
