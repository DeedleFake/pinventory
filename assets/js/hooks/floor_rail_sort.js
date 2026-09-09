/**
 * Drag-and-drop reorder for the floor rail (highest-at-top list order).
 *
 * Expects children with [data-floor-id]. Drag from [data-floor-handle].
 * Pushes LiveView event: reorder_floors — {floor_ids: [id, ...]} highest-first.
 */
const FloorRailSort = {
  mounted() {
    this.dragId = null

    this.onDragStart = (event) => {
      const handle = event.target.closest("[data-floor-handle]")
      if (!handle || !this.el.contains(handle)) return

      const item = handle.closest("[data-floor-id]")
      if (!item) return

      this.dragId = item.dataset.floorId
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", this.dragId)
      item.classList.add("opacity-50")
    }

    this.onDragEnd = (event) => {
      const item = event.target.closest("[data-floor-id]")
      if (item) item.classList.remove("opacity-50")
      this.clearDropIndicators()
      this.dragId = null
    }

    this.onDragOver = (event) => {
      if (!this.dragId) return
      const item = event.target.closest("[data-floor-id]")
      if (!item || !this.el.contains(item)) return
      if (item.dataset.floorId === this.dragId) return

      event.preventDefault()
      event.dataTransfer.dropEffect = "move"
      this.clearDropIndicators()
      item.classList.add("ring-1", "ring-primary/40")
    }

    this.onDragLeave = (event) => {
      const item = event.target.closest("[data-floor-id]")
      if (item) item.classList.remove("ring-1", "ring-primary/40")
    }

    this.onDrop = (event) => {
      event.preventDefault()
      this.clearDropIndicators()

      const target = event.target.closest("[data-floor-id]")
      if (!target || !this.el.contains(target) || !this.dragId) return

      const ids = [...this.el.querySelectorAll("[data-floor-id]")].map(
        (el) => el.dataset.floorId
      )
      const from = ids.indexOf(this.dragId)
      const to = ids.indexOf(target.dataset.floorId)
      if (from < 0 || to < 0 || from === to) return

      ids.splice(from, 1)
      ids.splice(to, 0, this.dragId)
      this.pushEvent("reorder_floors", {floor_ids: ids})
      this.dragId = null
    }

    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragend", this.onDragEnd)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("dragleave", this.onDragLeave)
    this.el.addEventListener("drop", this.onDrop)
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragend", this.onDragEnd)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("dragleave", this.onDragLeave)
    this.el.removeEventListener("drop", this.onDrop)
  },

  clearDropIndicators() {
    this.el.querySelectorAll("[data-floor-id]").forEach((el) => {
      el.classList.remove("ring-1", "ring-primary/40", "opacity-50")
    })
  }
}

export default FloorRailSort
