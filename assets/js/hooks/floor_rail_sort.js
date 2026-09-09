/**
 * Drag-and-drop reorder for the floor rail (highest-at-top list order).
 *
 * Live-reorders DOM nodes while dragging (pointer Y vs row midpoint).
 * Expects children with [data-floor-id]. Drag from [data-floor-handle].
 * Pushes LiveView event: reorder_floors — {floor_ids: [id, ...]} highest-first.
 */
const INSERT_BEFORE = ["border-t-2", "!border-t-primary"]
const INSERT_AFTER = ["border-b-2", "!border-b-primary"]
const DRAGGING = ["opacity-50", "scale-[0.98]", "shadow-md"]
const HANDLE_GRABBING = ["cursor-grabbing"]

const FloorRailSort = {
  mounted() {
    this.dragId = null
    this.dragEl = null
    this.handleEl = null
    this.originalOrder = null
    this.didDrop = false

    this.onDragStart = (event) => {
      const handle = event.target.closest("[data-floor-handle]")
      if (!handle || !this.el.contains(handle)) return

      const item = handle.closest("[data-floor-id]")
      if (!item) return

      this.dragId = item.dataset.floorId
      this.dragEl = item
      this.handleEl = handle
      this.didDrop = false
      this.originalOrder = this.currentOrder()

      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", this.dragId)

      item.classList.add(...DRAGGING)
      handle.classList.add(...HANDLE_GRABBING)
    }

    this.onDragEnd = () => {
      if (!this.didDrop && this.originalOrder) {
        this.restoreOrder(this.originalOrder)
      }
      this.cleanupDrag()
    }

    this.onDragOver = (event) => {
      if (!this.dragId || !this.dragEl) return

      event.preventDefault()
      event.dataTransfer.dropEffect = "move"

      const item = event.target.closest("[data-floor-id]")
      if (!item || !this.el.contains(item)) {
        this.clearInsertionIndicators()
        return
      }

      if (item === this.dragEl) {
        this.clearInsertionIndicators()
        return
      }

      const rect = item.getBoundingClientRect()
      const before = event.clientY < rect.top + rect.height / 2

      if (before) {
        if (item.previousElementSibling !== this.dragEl) {
          this.el.insertBefore(this.dragEl, item)
        }
      } else if (item.nextElementSibling !== this.dragEl) {
        this.el.insertBefore(this.dragEl, item.nextElementSibling)
      }

      this.clearInsertionIndicators()
      item.classList.add(...(before ? INSERT_BEFORE : INSERT_AFTER))
    }

    this.onDragLeave = (event) => {
      // relatedTarget is null when leaving the window; ignore flips caused by
      // live DOM moves while the pointer stays inside the list.
      const related = event.relatedTarget
      if (related && this.el.contains(related)) return
      this.clearInsertionIndicators()
    }

    this.onDrop = (event) => {
      event.preventDefault()
      this.didDrop = true

      if (!this.dragId) {
        this.cleanupDrag()
        return
      }

      const ids = this.currentOrder()
      const changed =
        !this.originalOrder ||
        ids.length !== this.originalOrder.length ||
        ids.some((id, i) => id !== this.originalOrder[i])

      if (changed) {
        this.pushEvent("reorder_floors", {floor_ids: ids})
      }

      this.cleanupDrag()
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

  currentOrder() {
    return [...this.el.querySelectorAll("[data-floor-id]")].map((el) => el.dataset.floorId)
  },

  restoreOrder(order) {
    order.forEach((id) => {
      const node = this.el.querySelector(`[data-floor-id="${CSS.escape(id)}"]`)
      if (node) this.el.appendChild(node)
    })
  },

  clearInsertionIndicators() {
    this.el.querySelectorAll("[data-floor-id]").forEach((el) => {
      el.classList.remove(...INSERT_BEFORE, ...INSERT_AFTER)
    })
  },

  cleanupDrag() {
    this.clearInsertionIndicators()

    if (this.dragEl) {
      this.dragEl.classList.remove(...DRAGGING)
    }
    if (this.handleEl) {
      this.handleEl.classList.remove(...HANDLE_GRABBING)
    }

    // Belt-and-suspenders in case refs were lost mid-drag.
    this.el.querySelectorAll("[data-floor-id]").forEach((el) => {
      el.classList.remove(...DRAGGING)
    })
    this.el.querySelectorAll("[data-floor-handle]").forEach((el) => {
      el.classList.remove(...HANDLE_GRABBING)
    })

    this.dragId = null
    this.dragEl = null
    this.handleEl = null
    this.originalOrder = null
    this.didDrop = false
  }
}

export default FloorRailSort
