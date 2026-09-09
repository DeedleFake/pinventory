/**
 * SVG floor-plan canvas: draw/erase walls and draw location polygons.
 *
 * data-mode: "wall" | "erase" | "place"
 * data-location-id: when mode is "place", the location for the polygon
 *
 * Pushes LiveView events:
 *   wall_drawn      — {x1,y1,x2,y2} normalized 0–1
 *   wall_erased     — {index}
 *   polygon_placed  — {location_id, points: [{x,y}, ...]}
 *   undo / redo     — keyboard shortcuts
 */
const MIN_WALL_LENGTH = 0.02
const SNAP_DISTANCE = 0.03
const CLOSE_DISTANCE = 0.025

const FloorPlanCanvas = {
  mounted() {
    this.svg = this.el.querySelector("[data-floor-plan-svg]")
    this.draftWall = null
    this.draftPolygon = null
    this.syncFromEl()

    this.onPointerDown = (event) => this.handlePointerDown(event)
    this.onPointerMove = (event) => this.handlePointerMove(event)
    this.onPointerUp = (event) => this.handlePointerUp(event)
    this.onDblClick = (event) => this.handleDblClick(event)
    this.onKeyDown = (event) => this.handleKeyDown(event)

    this.svg.addEventListener("pointerdown", this.onPointerDown)
    this.svg.addEventListener("dblclick", this.onDblClick)
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("keydown", this.onKeyDown)

    if (!this.el.hasAttribute("tabindex")) {
      this.el.setAttribute("tabindex", "0")
    }
  },

  updated() {
    this.syncFromEl()
    // LiveView re-rendered SVG; clear ephemeral draft overlays that may be gone.
    if (this.draftPolygon) this.drawPolygonDraft()
    if (this.draftWall) this.drawWallDraft()
  },

  destroyed() {
    this.svg.removeEventListener("pointerdown", this.onPointerDown)
    this.svg.removeEventListener("dblclick", this.onDblClick)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("keydown", this.onKeyDown)
    this.clearWallDraft()
    this.clearPolygonDraft()
  },

  syncFromEl() {
    const nextMode = this.el.dataset.mode || "wall"
    if (nextMode !== this.mode) {
      this.clearWallDraft()
      this.clearPolygonDraft()
    }
    this.mode = nextMode
    this.locationId = this.el.dataset.locationId || ""
  },

  handleKeyDown(event) {
    if (!this.isEditorHotkeyTarget(event)) return

    const meta = event.ctrlKey || event.metaKey
    if (!meta) {
      if (this.mode === "place" && this.draftPolygon) {
        if (event.key === "Enter") {
          event.preventDefault()
          this.finishPolygon()
          return
        }
        if (event.key === "Escape") {
          event.preventDefault()
          this.clearPolygonDraft()
          return
        }
      }
      return
    }

    const key = event.key.toLowerCase()
    if (key === "z" && event.shiftKey) {
      event.preventDefault()
      this.pushEvent("redo", {})
      return
    }
    if (key === "z") {
      event.preventDefault()
      this.pushEvent("undo", {})
      return
    }
    if (key === "y") {
      event.preventDefault()
      this.pushEvent("redo", {})
    }
  },

  isEditorHotkeyTarget(event) {
    const target = event.target
    if (!target) return true
    const tag = target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || target.isContentEditable) {
      return false
    }
    // Capture while the floor-plan page is mounted (this hook).
    return document.getElementById("floor-plan-page") != null
  },

  handlePointerDown(event) {
    if (event.button !== 0) return

    if (this.mode === "erase") {
      const wallEl = event.target.closest("[data-wall-index]")
      if (wallEl) {
        event.preventDefault()
        this.pushEvent("wall_erased", {index: Number(wallEl.dataset.wallIndex)})
      }
      return
    }

    const point = this.snap(this.eventToUnit(event))
    if (!point) return

    if (this.mode === "wall") {
      event.preventDefault()
      this.draftWall = {start: point, current: point}
      this.drawWallDraft()
      return
    }

    if (this.mode === "place" && this.locationId) {
      event.preventDefault()
      this.el.focus({preventScroll: true})

      if (!this.draftPolygon) {
        this.draftPolygon = {points: [point], current: point}
        this.drawPolygonDraft()
        return
      }

      const first = this.draftPolygon.points[0]
      if (
        this.draftPolygon.points.length >= 3 &&
        Math.hypot(point.x - first.x, point.y - first.y) <= CLOSE_DISTANCE
      ) {
        this.finishPolygon()
        return
      }

      this.draftPolygon.points.push(point)
      this.draftPolygon.current = point
      this.drawPolygonDraft()
    }
  },

  handlePointerMove(event) {
    if (this.draftWall) {
      const point = this.snap(this.eventToUnit(event))
      if (!point) return
      this.draftWall.current = point
      this.drawWallDraft()
      return
    }

    if (this.draftPolygon) {
      const point = this.snap(this.eventToUnit(event))
      if (!point) return
      this.draftPolygon.current = point
      this.drawPolygonDraft()
    }
  },

  handlePointerUp(event) {
    if (!this.draftWall) return

    const point = this.snap(this.eventToUnit(event)) || this.draftWall.current
    const {start} = this.draftWall
    this.clearWallDraft()
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
  },

  handleDblClick(event) {
    if (this.mode !== "place" || !this.draftPolygon) return
    event.preventDefault()
    this.finishPolygon()
  },

  finishPolygon() {
    if (!this.draftPolygon || !this.locationId) return
    const points = this.draftPolygon.points
    this.clearPolygonDraft()
    if (points.length < 3) return
    this.pushEvent("polygon_placed", {
      location_id: this.locationId,
      points: points.map((p) => ({x: p.x, y: p.y})),
    })
  },

  eventToUnit(event) {
    if (!event) return null
    const rect = this.svg.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return null
    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height
    return {x: clamp01(x), y: clamp01(y)}
  },

  snap(point) {
    if (!point) return null
    const endpoints = this.wallEndpoints()
    let best = null
    let bestDist = SNAP_DISTANCE
    for (const ep of endpoints) {
      const d = Math.hypot(ep.x - point.x, ep.y - point.y)
      if (d <= bestDist) {
        bestDist = d
        best = ep
      }
    }
    return best || point
  },

  wallEndpoints() {
    const points = []
    this.svg.querySelectorAll("[data-wall-seg]").forEach((line) => {
      points.push({
        x: Number(line.getAttribute("x1")),
        y: Number(line.getAttribute("y1")),
      })
      points.push({
        x: Number(line.getAttribute("x2")),
        y: Number(line.getAttribute("y2")),
      })
    })
    return points
  },

  drawWallDraft() {
    if (!this.draftWall) return
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
    const {start, current} = this.draftWall
    line.setAttribute("x1", start.x)
    line.setAttribute("y1", start.y)
    line.setAttribute("x2", current.x)
    line.setAttribute("y2", current.y)
  },

  clearWallDraft() {
    this.draftWall = null
    const line = this.svg && this.svg.querySelector("[data-wall-draft]")
    if (line) line.remove()
  },

  drawPolygonDraft() {
    if (!this.draftPolygon) return
    const {points, current} = this.draftPolygon
    const all = current ? points.concat([current]) : points

    let poly = this.svg.querySelector("[data-polygon-draft]")
    if (!poly) {
      poly = document.createElementNS("http://www.w3.org/2000/svg", "polygon")
      poly.setAttribute("data-polygon-draft", "true")
      poly.setAttribute("class", "fill-primary/20 stroke-primary")
      poly.setAttribute("stroke-width", "0.008")
      poly.setAttribute("stroke-dasharray", "0.02 0.015")
      this.svg.appendChild(poly)
    }
    poly.setAttribute("points", all.map((p) => `${p.x},${p.y}`).join(" "))

    let layer = this.svg.querySelector("[data-polygon-draft-vertices]")
    if (!layer) {
      layer = document.createElementNS("http://www.w3.org/2000/svg", "g")
      layer.setAttribute("data-polygon-draft-vertices", "true")
      this.svg.appendChild(layer)
    }
    while (layer.firstChild) layer.removeChild(layer.firstChild)
    for (const p of points) {
      const c = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      c.setAttribute("cx", p.x)
      c.setAttribute("cy", p.y)
      c.setAttribute("r", "0.012")
      c.setAttribute("class", "fill-primary")
      layer.appendChild(c)
    }
  },

  clearPolygonDraft() {
    this.draftPolygon = null
    if (!this.svg) return
    const poly = this.svg.querySelector("[data-polygon-draft]")
    if (poly) poly.remove()
    const layer = this.svg.querySelector("[data-polygon-draft-vertices]")
    if (layer) layer.remove()
  },
}

function clamp01(n) {
  return Math.max(0, Math.min(1, n))
}

export default FloorPlanCanvas
