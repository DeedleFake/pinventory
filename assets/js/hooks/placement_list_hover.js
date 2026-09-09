/**
 * List → canvas highlight: toggle `.is-list-hover` on matching `.placement-group`.
 *
 * LiveView JS.add_class targeting SVG <g> nodes is unreliable across morphs;
 * this hook listens on the list and queries by data-location-id instead.
 */

export function placementGroupSelector(locationId) {
  if (!locationId) return null
  const escaped =
    typeof CSS !== "undefined" && typeof CSS.escape === "function"
      ? CSS.escape(locationId)
      : locationId.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
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
  const row = event.target.closest("[data-location-id]")
  if (!row || !listEl.contains(row)) return null
  return row.getAttribute("data-location-id")
}

const PlacementListHover = {
  mounted() {
    this.hoveredId = null
    this.root = this.el.ownerDocument || document

    this.clearHover = () => {
      if (!this.hoveredId) return
      const group = findPlacementGroup(this.root, this.hoveredId)
      setListHover(group, false)
      this.hoveredId = null
    }

    this.onOver = (event) => {
      const id = rowLocationId(event, this.el)
      if (!id) return
      if (id === this.hoveredId) return
      this.clearHover()
      this.hoveredId = id
      setListHover(findPlacementGroup(this.root, id), true)
    }

    this.onOut = (event) => {
      const id = rowLocationId(event, this.el)
      if (!id || id !== this.hoveredId) return
      const related = event.relatedTarget
      const row = event.target.closest("[data-location-id]")
      if (related && row && row.contains(related)) return
      this.clearHover()
    }

    this.el.addEventListener("mouseover", this.onOver)
    this.el.addEventListener("mouseout", this.onOut)
  },

  destroyed() {
    if (this.clearHover) this.clearHover()
    if (this.onOver) this.el.removeEventListener("mouseover", this.onOver)
    if (this.onOut) this.el.removeEventListener("mouseout", this.onOut)
  },
}

export default PlacementListHover
