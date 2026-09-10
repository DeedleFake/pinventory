import assert from "node:assert/strict"
import {describe, it} from "node:test"
import {
  findPlacementGroup,
  placementGroupSelector,
  setListHover,
} from "./placement_list_hover.js"

function fakeEl(attrs = {}, kids = []) {
  const classSet = new Set((attrs.class || "").split(/\s+/).filter(Boolean))
  const el = {
    attrs,
    kids,
    classList: {
      contains: (c) => classSet.has(c),
      add: (c) => classSet.add(c),
      remove: (c) => classSet.delete(c),
      toggle: (c, on) => {
        if (on) classSet.add(c)
        else classSet.delete(c)
        return classSet.has(c)
      },
    },
    getAttribute: (name) => attrs[name] ?? null,
    querySelector(selector) {
      const match = selector.match(
        /^\.placement-group\[data-location-id="(.+)"\]$/,
      )
      if (!match) return null
      const want = match[1]
      const stack = [...kids]
      while (stack.length) {
        const node = stack.pop()
        if (
          node.attrs?.class?.split(/\s+/).includes("placement-group") &&
          node.attrs["data-location-id"] === want
        ) {
          return node
        }
        if (node.kids) stack.push(...node.kids)
      }
      return null
    },
  }
  return el
}

describe("placementGroupSelector", () => {
  it("builds an attribute selector for the location id", () => {
    assert.equal(
      placementGroupSelector("abc-123"),
      '.placement-group[data-location-id="abc-123"]',
    )
  })


  it("matches leading-digit UUIDs without CSS.escape rewriting", () => {
    const id = "524c561f-d8e4-439c-a42f-200ad153a3be"
    assert.equal(
      placementGroupSelector(id),
      `.placement-group[data-location-id="${id}"]`,
    )
  })

  it("returns null for empty ids", () => {
    assert.equal(placementGroupSelector(""), null)
    assert.equal(placementGroupSelector(null), null)
  })
})

describe("findPlacementGroup + setListHover", () => {
  it("finds the group by data-location-id and toggles is-list-hover", () => {
    const group = fakeEl({
      class: "placement-group",
      "data-location-id": "loc-1",
    })
    const root = fakeEl({}, [group])

    assert.equal(findPlacementGroup(root, "missing"), null)
    assert.equal(findPlacementGroup(root, "loc-1"), group)

    assert.equal(setListHover(group, true), true)
    assert.equal(group.classList.contains("is-list-hover"), true)
    assert.equal(setListHover(group, false), false)
    assert.equal(group.classList.contains("is-list-hover"), false)
  })
})
