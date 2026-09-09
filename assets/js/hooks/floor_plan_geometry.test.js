import assert from "node:assert/strict"
import {describe, it} from "node:test"
import {
  mergeExtension,
  polygonArea,
  polygonSelfIntersects,
  replaceRingArc,
  segmentsIntersect,
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
