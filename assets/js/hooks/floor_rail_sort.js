/**
 * Pointer-based reorder for the floor rail (highest-at-top list order).
 *
 * Drag from [data-floor-handle]. While dragging:
 *   - floating semi-transparent ghost follows the pointer (clamped inside the list)
 *   - source row becomes an open slot that live-reorders under the pointer
 *   - sibling rows animate with a short FLIP transform
 *
 * Pushes LiveView event: reorder_floors — {floor_ids: [id, ...]} highest-first.
 * Escape cancels and restores the original order.
 */

const SLOT = ["floor-rail-slot"]
const HANDLE_GRABBING = ["cursor-grabbing"]
const FLIP_MS = 160

const FloorRailSort = {
  mounted() {
    this.dragId = null
    this.dragEl = null
    this.handleEl = null
    this.ghostEl = null
    this.originalOrder = null
    this.didDrop = false
    this.pointerId = null
    this.ghostW = 0
    this.ghostH = 0
    this.offsetX = 0
    this.offsetY = 0
    this.dragging = false

    this.onPointerDown = (event) => {
      if (event.button !== 0) return
      const handle = event.target.closest("[data-floor-handle]")
      if (!handle || !this.el.contains(handle)) return

      const item = handle.closest("[data-floor-id]")
      if (!item) return

      event.preventDefault()
      this.dragging = true
      this.didDrop = false
      this.dragId = item.dataset.floorId
      this.dragEl = item
      this.handleEl = handle
      this.originalOrder = this.currentOrder()
      this.pointerId = event.pointerId

      const rect = item.getBoundingClientRect()
      this.ghostW = rect.width
      this.ghostH = rect.height
      this.offsetX = event.clientX - rect.left
      this.offsetY = event.clientY - rect.top

      item.classList.add(...SLOT)
      handle.classList.add(...HANDLE_GRABBING)
      this.createGhost(item)
      this.positionGhost(event.clientX, event.clientY)

      try {
        handle.setPointerCapture(event.pointerId)
      } catch (_err) {
        /* ignore */
      }

      window.addEventListener("pointermove", this.onPointerMove)
      window.addEventListener("pointerup", this.onPointerUp)
      window.addEventListener("pointercancel", this.onPointerUp)
      window.addEventListener("keydown", this.onKeyDown)
    }

    this.onPointerMove = (event) => {
      if (!this.dragging || !this.dragEl) return
      if (this.pointerId != null && event.pointerId !== this.pointerId) return

      event.preventDefault()
      this.positionGhost(event.clientX, event.clientY)
      this.reorderSlotToward(event.clientY)
    }

    this.onPointerUp = (event) => {
      if (!this.dragging) return
      if (this.pointerId != null && event.pointerId !== this.pointerId) return

      this.didDrop = true
      this.finishDrag({commit: true})
    }

    this.onKeyDown = (event) => {
      if (!this.dragging) return
      if (event.key === "Escape") {
        event.preventDefault()
        event.stopPropagation()
        this.finishDrag({commit: false})
      }
    }

    this.el.addEventListener("pointerdown", this.onPointerDown)
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.teardownWindowListeners()
    this.removeGhost()
  },

  finishDrag({commit}) {
    if (!this.dragging) return

    const order = this.currentOrder()
    const original = this.originalOrder

    if (!commit && original) {
      this.restoreOrder(original)
    } else if (commit && original) {
      const changed =
        order.length !== original.length || order.some((id, i) => id !== original[i])
      if (changed) {
        this.pushEvent("reorder_floors", {floor_ids: order})
      }
    }

    this.cleanupDrag()
  },

  createGhost(item) {
    this.removeGhost()
    const ghost = item.cloneNode(true)
    ghost.removeAttribute("id")
    ghost.removeAttribute("data-floor-id")
    ghost.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"))
    ghost.querySelectorAll("[data-floor-handle]").forEach((el) => {
      el.removeAttribute("data-floor-handle")
    })
    ghost.classList.remove(...SLOT)
    ghost.classList.add("floor-rail-ghost")
    ghost.setAttribute("aria-hidden", "true")
    ghost.style.width = `${this.ghostW}px`
    ghost.style.height = `${this.ghostH}px`
    document.body.appendChild(ghost)
    this.ghostEl = ghost
  },

  positionGhost(clientX, clientY) {
    if (!this.ghostEl) return
    const list = this.el.getBoundingClientRect()
    let left = clientX - this.offsetX
    let top = clientY - this.offsetY

    // Keep the ghost visually locked inside the list bounds.
    left = Math.max(list.left, Math.min(left, list.right - this.ghostW))
    top = Math.max(list.top, Math.min(top, list.bottom - this.ghostH))

    this.ghostEl.style.transform = `translate(${left}px, ${top}px)`
  },

  reorderSlotToward(clientY) {
    if (!this.dragEl) return

    const items = [...this.el.querySelectorAll("[data-floor-id]")].filter(
      (el) => el !== this.dragEl,
    )
    if (items.length === 0) return

    let insertBefore = null
    for (const item of items) {
      const rect = item.getBoundingClientRect()
      const mid = rect.top + rect.height / 2
      if (clientY < mid) {
        insertBefore = item
        break
      }
    }

    const targetNext =
      insertBefore == null ? null : insertBefore
    const currentlyBefore = this.dragEl.nextElementSibling

    if (targetNext === this.dragEl) return
    if (targetNext === currentlyBefore) return
    if (targetNext == null && currentlyBefore == null && this.el.lastElementChild === this.dragEl) {
      return
    }

    this.withFlip(() => {
      if (targetNext) {
        this.el.insertBefore(this.dragEl, targetNext)
      } else {
        this.el.appendChild(this.dragEl)
      }
    })
  },

  withFlip(mutate) {
    const kids = [...this.el.children]
    const first = new Map()
    for (const el of kids) {
      first.set(el, el.getBoundingClientRect())
    }

    mutate()

    for (const el of kids) {
      if (!this.el.contains(el)) continue
      const last = el.getBoundingClientRect()
      const prev = first.get(el)
      if (!prev) continue
      const dy = prev.top - last.top
      if (Math.abs(dy) < 0.5) continue

      el.style.transition = "none"
      el.style.transform = `translateY(${dy}px)`
      // Force reflow so the invert sticks before playing.
      void el.offsetWidth
      el.style.transition = `transform ${FLIP_MS}ms ease`
      el.style.transform = ""
      const clear = () => {
        el.style.transition = ""
        el.style.transform = ""
        el.removeEventListener("transitionend", clear)
      }
      el.addEventListener("transitionend", clear)
    }
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

  removeGhost() {
    if (this.ghostEl) {
      this.ghostEl.remove()
      this.ghostEl = null
    }
    document.querySelectorAll(".floor-rail-ghost").forEach((el) => el.remove())
  },

  teardownWindowListeners() {
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerUp)
    window.removeEventListener("keydown", this.onKeyDown)
  },

  cleanupDrag() {
    this.teardownWindowListeners()
    this.removeGhost()

    if (this.handleEl && this.pointerId != null) {
      try {
        this.handleEl.releasePointerCapture(this.pointerId)
      } catch (_err) {
        /* ignore */
      }
    }

    if (this.dragEl) {
      this.dragEl.classList.remove(...SLOT)
      this.dragEl.style.transition = ""
      this.dragEl.style.transform = ""
    }
    if (this.handleEl) {
      this.handleEl.classList.remove(...HANDLE_GRABBING)
    }

    this.el.querySelectorAll("[data-floor-id]").forEach((el) => {
      el.classList.remove(...SLOT)
      el.style.transition = ""
      el.style.transform = ""
    })
    this.el.querySelectorAll("[data-floor-handle]").forEach((el) => {
      el.classList.remove(...HANDLE_GRABBING)
    })

    this.dragId = null
    this.dragEl = null
    this.handleEl = null
    this.originalOrder = null
    this.didDrop = false
    this.pointerId = null
    this.dragging = false
  },
}

export default FloorRailSort
