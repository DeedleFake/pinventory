/**
 * List → canvas highlight: toggle `.is-list-hover` on matching `.placement-group`.
 *
 * LiveView JS.add_class targeting SVG <g> nodes is unreliable across morphs;
 * this hook listens on the list and queries by data-location-id instead.
 */

export function placementGroupSelector(locationId) {
  if (locationId == null || locationId === "") return null
  const id = String(locationId)
  // Quote-escape only. CSS.escape() is for identifiers and rewrites a leading
  // digit (common in UUIDs) to "\3N ...", which breaks attribute matching.
  const escaped = id.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  return `.placement-group[data-location-id="${escaped}"]`
}

export function findPlacementGroup(root, locationId) {
  const selector = placementGroupSelector(locationId)
  if (!selector || !root || typeof root.querySelector !== "function") return null
  return root.querySelector(selector)
}

export function setListHover(group, on) {
  if (!group || !group.classList) return false
  group.classList.toggle("is-list-hover", Boolean(on))
  return group.classList.contains("is-list-hover")
}

function rowLocationId(event, listEl) {
  const target = event.target
  if (!target || typeof target.closest !== "function") return null
  const row = target.closest("[data-location-id]")
  if (!row || !listEl.contains(row)) return null
  const id = row.getAttribute("data-location-id")
  return id == null || id === "" ? null : String(id)
}

function canvasQueryRoot(doc) {
  // Prefer the floor SVG so we don't miss groups if the page has other roots,
  // and so floor switches (new SVG id) still resolve after morphs.
  return (
    doc.querySelector("#locations-floor-canvas [data-floor-plan-svg]") ||
    doc.querySelector("#floor-plan-canvas [data-floor-plan-svg]") ||
    doc.querySelector("[data-floor-plan-svg]") ||
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
    // Floor switch replaces the SVG; drop stale hover class tracking.
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

export default PlacementListHover
