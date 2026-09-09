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
 *
 * Snap: shared helpers snap to wall endpoints and points along wall segments.
 * Polygon finish: close near first vertex, double-click, or Done; Escape cancels.
 */
const MIN_WALL_LENGTH = 0.02
const SNAP_DISTANCE = 0.03
const CLOSE_DISTANCE = 0.025

const FloorPlanCanvas = {
  mounted() {
    this.svg = this.el.querySelector("[data-floor-plan-svg]")
    this.finishBtn = this.el.querySelector("[data-polygon-finish]")
    this.draftWall = null
    this.draftPolygon = null
    this.snapPoint = null
    this.syncFromEl()

    this.onPointerDown = (event) => this.handlePointerDown(event)
    this.onPointerMove = (event) => this.handlePointerMove(event)
    this.onPointerUp = (event) => this.handlePointerUp(event)
    this.onDblClick = (event) => this.handleDblClick(event)
    this.onKeyDown = (event) => this.handleKeyDown(event)
    this.onFinishClick = (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.finishPolygon()
    }

    this.svg.addEventListener("pointerdown", this.onPointerDown)
    this.svg.addEventListener("dblclick", this.onDblClick)
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("keydown", this.onKeyDown)
    if (this.finishBtn) this.finishBtn.addEventListener("click", this.onFinishClick)

    if (!this.el.hasAttribute("tabindex")) {
      this.el.setAttribute("tabindex", "0")
    }

    this.updateFinishButton()
  },

  updated() {
    this.svg = this.el.querySelector("[data-floor-plan-svg]")
    const nextFinish = this.el.querySelector("[data-polygon-finish]")
    if (nextFinish !== this.finishBtn) {
      if (this.finishBtn) this.finishBtn.removeEventListener("click", this.onFinishClick)
      this.finishBtn = nextFinish
      if (this.finishBtn) this.finishBtn.addEventListener("click", this.onFinishClick)
    }
    this.syncFromEl()
    if (this.draftPolygon) this.drawPolygonDraft()
    if (this.draftWall) this.drawWallDraft()
    this.drawSnapIndicator()
    this.updateFinishButton()
  },

  destroyed() {
    this.svg.removeEventListener("pointerdown", this.onPointerDown)
    this.svg.removeEventListener("dblclick", this.onDblClick)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("keydown", this.onKeyDown)
    if (this.finishBtn) this.finishBtn.removeEventListener("click", this.onFinishClick)
    this.clearWallDraft()
    this.clearPolygonDraft()
    this.clearSnapIndicator()
  },

  syncFromEl() {
    const nextMode = this.el.dataset.mode || "wall"
    if (nextMode !== this.mode) {
      this.clearWallDraft()
      this.clearPolygonDraft()
      this.clearSnapIndicator()
    }
    this.mode = nextMode
    this.locationId = this.el.dataset.locationId || ""
  },

  handleKeyDown(event) {
    if (!this.isEditorHotkeyTarget(event)) return

    const meta = event.ctrlKey || event.metaKey
    if (!meta) {
      if (this.mode === "place" && this.draftPolygon) {
        // Enter remains an obscure shortcut; primary finish is close / double-click / Done.
        if (event.key === "Enter") {
          event.preventDefault()
          this.finishPolygon()
          return
        }
        if (event.key === "Escape") {
          event.preventDefault()
          this.clearPolygonDraft()
          this.clearSnapIndicator()
          this.updateFinishButton()
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
    return document.getElementById("floor-plan-page") != null
  },

  handlePointerDown(event) {
    if (event.button !== 0) return
    if (event.target.closest("[data-polygon-finish]")) return

    if (this.mode === "erase") {
      const wallEl = event.target.closest("[data-wall-index]")
      if (wallEl) {
        event.preventDefault()
        this.pushEvent("wall_erased", {index: Number(wallEl.dataset.wallIndex)})
      }
      return
    }

    const raw = this.eventToUnit(event)
    const snapped = this.snap(raw)
    const point = snapped.point
    this.snapPoint = snapped.snapped ? snapped.point : null
    this.drawSnapIndicator()
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
        this.updateFinishButton()
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
      this.updateFinishButton()
    }
  },

  handlePointerMove(event) {
    const raw = this.eventToUnit(event)
    if (!raw) return

    if (this.mode === "wall" || (this.mode === "place" && this.locationId)) {
      const snapped = this.snap(raw)
      this.snapPoint = snapped.snapped ? snapped.point : null
      this.drawSnapIndicator()

      if (this.draftWall) {
        this.draftWall.current = snapped.point
        this.drawWallDraft()
        return
      }

      if (this.draftPolygon) {
        this.draftPolygon.current = snapped.point
        this.drawPolygonDraft()
      }
      return
    }

    this.clearSnapIndicator()
  },

  handlePointerUp(event) {
    if (!this.draftWall) return

    const raw = this.eventToUnit(event)
    const snapped = raw ? this.snap(raw) : {point: this.draftWall.current}
    const point = snapped.point || this.draftWall.current
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
    this.clearSnapIndicator()
    this.updateFinishButton()
    if (points.length < 3) return
    this.pushEvent("polygon_placed", {
      location_id: this.locationId,
      points: points.map((p) => ({x: p.x, y: p.y})),
    })
  },

  updateFinishButton() {
    if (!this.finishBtn) return
    const show = !!(this.draftPolygon && this.draftPolygon.points.length >= 3)
    this.finishBtn.classList.toggle("hidden", !show)
  },

  eventToUnit(event) {
    if (!event) return null
    const rect = this.svg.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return null
    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height
    return {x: clamp01(x), y: clamp01(y)}
  },

  /**
   * Shared snap for walls and location polygons: nearest wall endpoint or
   * nearest point along a wall segment within SNAP_DISTANCE.
   * Returns {point, snapped}. Prefer vertices, then segment points.
   */
  snap(point) {
    if (!point) return {point: null, snapped: false}

    const segs = []
    this.svg.querySelectorAll("[data-wall-seg]").forEach((line) => {
      segs.push([
        {x: Number(line.getAttribute("x1")), y: Number(line.getAttribute("y1"))},
        {x: Number(line.getAttribute("x2")), y: Number(line.getAttribute("y2"))},
      ])
    })

    // Prefer wall endpoints so corners join cleanly.
    let best = null
    let bestDist = SNAP_DISTANCE
    for (const [a, b] of segs) {
      for (const ep of [a, b]) {
        const d = Math.hypot(ep.x - point.x, ep.y - point.y)
        if (d <= bestDist) {
          bestDist = d
          best = ep
        }
      }
    }
    if (best) return {point: {x: best.x, y: best.y}, snapped: true}

    // Otherwise snap to the nearest point along a wall segment.
    bestDist = SNAP_DISTANCE
    for (const [a, b] of segs) {
      const onSeg = closestPointOnSegment(point, a, b)
      const d = Math.hypot(onSeg.x - point.x, onSeg.y - point.y)
      if (d <= bestDist) {
        bestDist = d
        best = onSeg
      }
    }

    if (best) return {point: {x: best.x, y: best.y}, snapped: true}
    return {point, snapped: false}
  },

  drawSnapIndicator() {
    if (!this.svg) return
    let dot = this.svg.querySelector("[data-snap-indicator]")
    if (!this.snapPoint) {
      if (dot) dot.remove()
      return
    }
    if (!dot) {
      dot = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      dot.setAttribute("data-snap-indicator", "true")
      dot.setAttribute("r", "0.014")
      dot.setAttribute("class", "fill-primary stroke-base-100")
      dot.setAttribute("stroke-width", "0.006")
      this.svg.appendChild(dot)
    }
    dot.setAttribute("cx", this.snapPoint.x)
    dot.setAttribute("cy", this.snapPoint.y)
  },

  clearSnapIndicator() {
    this.snapPoint = null
    const dot = this.svg && this.svg.querySelector("[data-snap-indicator]")
    if (dot) dot.remove()
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

function closestPointOnSegment(p, a, b) {
  const dx = b.x - a.x
  const dy = b.y - a.y
  const len2 = dx * dx + dy * dy
  if (len2 === 0) return {x: a.x, y: a.y}
  let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
  t = Math.max(0, Math.min(1, t))
  return {x: a.x + t * dx, y: a.y + t * dy}
}

export default FloorPlanCanvas
