/**
 * SVG floor-plan canvas: draw wall segments and place/move location pins.
 *
 * data-mode: "wall" | "place" | "select"
 * data-location-id: when mode is "place", the location to pin on click
 *
 * Pushes LiveView events:
 *   wall_drawn   — {x1,y1,x2,y2} normalized 0–1
 *   pin_placed   — {location_id, x, y}
 *   pin_moved    — {location_id, x, y}
 *   pin_selected — {location_id}
 */
const MIN_WALL_LENGTH = 0.02

const FloorPlanCanvas = {
  mounted() {
    this.svg = this.el.querySelector("[data-floor-plan-svg]")
    this.draft = null
    this.dragPin = null
    this.syncFromEl()

    this.onPointerDown = (event) => this.handlePointerDown(event)
    this.onPointerMove = (event) => this.handlePointerMove(event)
    this.onPointerUp = (event) => this.handlePointerUp(event)

    this.svg.addEventListener("pointerdown", this.onPointerDown)
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
  },

  updated() {
    this.syncFromEl()
  },

  destroyed() {
    this.svg.removeEventListener("pointerdown", this.onPointerDown)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    this.clearDraft()
  },

  syncFromEl() {
    this.mode = this.el.dataset.mode || "wall"
    this.locationId = this.el.dataset.locationId || ""
  },

  handlePointerDown(event) {
    if (event.button !== 0) return

    const pinEl = event.target.closest("[data-pin-location-id]")
    if (pinEl && (this.mode === "select" || this.mode === "place")) {
      event.preventDefault()
      this.dragPin = {
        locationId: pinEl.dataset.pinLocationId,
        pointerId: event.pointerId,
      }
      this.pushEvent("pin_selected", {location_id: this.dragPin.locationId})
      return
    }

    const point = this.eventToUnit(event)
    if (!point) return

    if (this.mode === "wall") {
      event.preventDefault()
      this.draft = {start: point, current: point}
      this.drawDraft()
      return
    }

    if (this.mode === "place" && this.locationId) {
      event.preventDefault()
      this.pushEvent("pin_placed", {
        location_id: this.locationId,
        x: point.x,
        y: point.y,
      })
    }
  },

  handlePointerMove(event) {
    if (this.draft) {
      const point = this.eventToUnit(event)
      if (!point) return
      this.draft.current = point
      this.drawDraft()
      return
    }

    if (this.dragPin) {
      const point = this.eventToUnit(event)
      if (!point) return
      const pin = this.svg.querySelector(
        `[data-pin-location-id="${this.dragPin.locationId}"]`
      )
      if (pin) {
        pin.setAttribute("cx", point.x)
        pin.setAttribute("cy", point.y)
        const label = this.svg.querySelector(
          `[data-pin-label-id="${this.dragPin.locationId}"]`
        )
        if (label) {
          label.setAttribute("x", point.x)
          label.setAttribute("y", Math.max(0.04, point.y - 0.035))
        }
        this.dragPin.x = point.x
        this.dragPin.y = point.y
      }
    }
  },

  handlePointerUp(event) {
    if (this.draft) {
      const point = this.eventToUnit(event) || this.draft.current
      const {start} = this.draft
      this.clearDraft()
      const dx = point.x - start.x
      const dy = point.y - start.y
      if (Math.hypot(dx, dy) >= MIN_WALL_LENGTH) {
        this.pushEvent("wall_drawn", {
          x1: start.x,
          y1: start.y,
          x2: point.x,
          y2: point.y,
        })
      }
      return
    }

    if (this.dragPin && this.dragPin.x != null) {
      this.pushEvent("pin_moved", {
        location_id: this.dragPin.locationId,
        x: this.dragPin.x,
        y: this.dragPin.y,
      })
    }
    this.dragPin = null
  },

  eventToUnit(event) {
    const rect = this.svg.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return null
    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height
    return {
      x: clamp01(x),
      y: clamp01(y),
    }
  },

  drawDraft() {
    if (!this.draft) return
    let line = this.svg.querySelector("[data-wall-draft]")
    if (!line) {
      line = document.createElementNS("http://www.w3.org/2000/svg", "line")
      line.setAttribute("data-wall-draft", "true")
      line.setAttribute("stroke", "currentColor")
      line.setAttribute("stroke-width", "0.012")
      line.setAttribute("stroke-linecap", "round")
      line.setAttribute("stroke-dasharray", "0.03 0.02")
      line.setAttribute("class", "text-primary opacity-80")
      this.svg.appendChild(line)
    }
    const {start, current} = this.draft
    line.setAttribute("x1", start.x)
    line.setAttribute("y1", start.y)
    line.setAttribute("x2", current.x)
    line.setAttribute("y2", current.y)
  },

  clearDraft() {
    this.draft = null
    const line = this.svg && this.svg.querySelector("[data-wall-draft]")
    if (line) line.remove()
  },
}

function clamp01(n) {
  return Math.max(0, Math.min(1, n))
}

export default FloorPlanCanvas
