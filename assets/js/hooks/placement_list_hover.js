/**
 * Bidirectional placement hover:
 * - PlacementListHover (list): toggles `.is-list-hover` on matching `.placement-group`
 * - PlacementCanvasHover helpers: toggle `.is-list-hover` on the group and
 *   `.is-canvas-hover` on the matching list row
 *
 * LiveView JS.add_class targeting SVG <g> / stream rows across morphs is
 * unreliable; these hooks query by data-location-id instead.
 */

export function placementGroupSelector(locationId) {
  if (locationId == null || locationId === "") return null
  const id = String(locationId)
  // Quote-escape only. CSS.escape() is for identifiers and rewrites a leading
  // digit (common in UUIDs) to "\3N ...", which breaks attribute matching.
  const escaped = id.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  return `.placement-group[data-location-id="${escaped}"]`
}

export function listRowSelector(locationId) {
  if (locationId == null || locationId === "") return null
  const id = String(locationId)
  const escaped = id.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  return `[data-location-id="${escaped}"]`
}

export function findPlacementGroup(root, locationId) {
  const selector = placementGroupSelector(locationId)
  if (!selector || !root || typeof root.querySelector !== "function") return null
  return root.querySelector(selector)
}

export function findListRow(root, locationId) {
  const selector = listRowSelector(locationId)
  if (!selector || !root || typeof root.querySelector !== "function") return null
  // Prefer stream row anchors / list items; skip placement groups themselves.
  const nodes = root.querySelectorAll(selector)
  for (const node of nodes) {
    if (!node || !node.classList) continue
    if (node.classList.contains("placement-group")) continue
    return node
  }
  return null
}

export function setListHover(group, on) {
  if (!group || !group.classList) return false
  group.classList.toggle("is-list-hover", Boolean(on))
  return group.classList.contains("is-list-hover")
}

export function setCanvasHover(row, on) {
  if (!row || !row.classList) return false
  row.classList.toggle("is-canvas-hover", Boolean(on))
  return row.classList.contains("is-canvas-hover")
}

function rowLocationId(event, listEl) {
  const target = event.target
  if (!target || typeof target.closest !== "function") return null
  const row = target.closest("[data-location-id]")
  if (!row || !listEl.contains(row)) return null
  if (row.classList && row.classList.contains("placement-group")) return null
  const id = row.getAttribute("data-location-id")
  return id == null || id === "" ? null : String(id)
}

function groupLocationId(event, canvasEl) {
  const target = event.target
  if (!target || typeof target.closest !== "function") return null
  const group = target.closest(".placement-group[data-location-id]")
  if (!group || !canvasEl.contains(group)) return null
  const id = group.getAttribute("data-location-id")
  return id == null || id === "" ? null : String(id)
}

function canvasQueryRoot(doc) {
  return (
    doc.querySelector("#locations-floor-canvas [data-floor-plan-svg]") ||
    doc.querySelector("#floor-plan-canvas [data-floor-plan-svg]") ||
    doc.querySelector("[data-floor-plan-svg]") ||
    doc
  )
}

function listQueryRoot(doc) {
  return (
    doc.querySelector("#locations-list-hover") ||
    doc.querySelector("#locations") ||
    doc.querySelector("#locations-list") ||
    doc.querySelector('[phx-hook="PlacementListHover"]') ||
    doc
  )
}

const PlacementListHover = {
  mounted() {
    this.hoveredId = null
    this.doc = this.el.ownerDocument || document

    this.clearHover = () => {
      if (!this.hoveredId) return
      const group = findPlacementGroup(canvasQueryRoot(this.doc), this.hoveredId)
      setListHover(group, false)
      this.hoveredId = null
    }

    this.onOver = (event) => {
      const id = rowLocationId(event, this.el)
      if (!id) return
      if (id === this.hoveredId) return
      this.clearHover()
      this.hoveredId = id
      setListHover(findPlacementGroup(canvasQueryRoot(this.doc), id), true)
    }

    this.onOut = (event) => {
      const id = rowLocationId(event, this.el)
      if (!id || id !== this.hoveredId) return
      const related = event.relatedTarget
      const row =
        event.target && typeof event.target.closest === "function"
          ? event.target.closest("[data-location-id]")
          : null
      if (related && row && typeof row.contains === "function" && row.contains(related)) {
        return
      }
      this.clearHover()
    }

    this.el.addEventListener("mouseover", this.onOver)
    this.el.addEventListener("mouseout", this.onOut)
  },

  updated() {
    if (this.hoveredId) {
      const group = findPlacementGroup(canvasQueryRoot(this.doc), this.hoveredId)
      if (!group) this.hoveredId = null
    }
  },

  destroyed() {
    if (this.clearHover) this.clearHover()
    if (this.onOver) this.el.removeEventListener("mouseover", this.onOver)
    if (this.onOut) this.el.removeEventListener("mouseout", this.onOut)
  },
}

/** Canvas → list (+ self) highlight. Mount on the floor-plan canvas root. */
export const PlacementCanvasHover = {
  mounted() {
    this.hoveredId = null
    this.doc = this.el.ownerDocument || document

    this.clearHover = () => {
      if (!this.hoveredId) return
      const id = this.hoveredId
      this.hoveredId = null
      const group = findPlacementGroup(this.el, id) || findPlacementGroup(canvasQueryRoot(this.doc), id)
      setListHover(group, false)
      setCanvasHover(findListRow(listQueryRoot(this.doc), id), false)
    }

    this.onOver = (event) => {
      const id = groupLocationId(event, this.el)
      if (!id) return
      if (id === this.hoveredId) return
      this.clearHover()
      this.hoveredId = id
      const group =
        findPlacementGroup(this.el, id) || findPlacementGroup(canvasQueryRoot(this.doc), id)
      setListHover(group, true)
      setCanvasHover(findListRow(listQueryRoot(this.doc), id), true)
    }

    this.onOut = (event) => {
      const id = groupLocationId(event, this.el)
      if (!id || id !== this.hoveredId) return
      const related = event.relatedTarget
      const group =
        event.target && typeof event.target.closest === "function"
          ? event.target.closest(".placement-group[data-location-id]")
          : null
      if (related && group && typeof group.contains === "function" && group.contains(related)) {
        return
      }
      this.clearHover()
    }

    this.el.addEventListener("mouseover", this.onOver)
    this.el.addEventListener("mouseout", this.onOut)
  },

  updated() {
    if (this.hoveredId) {
      const group =
        findPlacementGroup(this.el, this.hoveredId) ||
        findPlacementGroup(canvasQueryRoot(this.doc), this.hoveredId)
      if (!group) this.hoveredId = null
    }
  },

  destroyed() {
    if (this.clearHover) this.clearHover()
    if (this.onOver) this.el.removeEventListener("mouseover", this.onOver)
    if (this.onOut) this.el.removeEventListener("mouseout", this.onOut)
  },
}

export default PlacementListHover
