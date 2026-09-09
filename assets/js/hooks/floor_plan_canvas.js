/**
 * SVG floor-plan canvas: draw/erase walls and draw/extend location polygons.
 *
 * data-mode: "wall" | "erase" | "place"
 * data-location-id: when mode is "place", the location for the polygon
 * data-place-mode: "new" | "extend" | "redraw"
 * data-existing-points: JSON [{x,y}, ...] when extending an existing polygon
 *
 * Pushes LiveView events:
 *   wall_drawn      — {x1,y1,x2,y2} normalized 0–1
 *   wall_erased     — {index}
 *   polygon_placed  — {location_id, points: [{x,y}, ...]} (full polygon)
 *   undo / redo     — keyboard shortcuts
 *
 * Walls: first click sets start (snap), second click commits; Escape cancels.
 * Snap: wall endpoints/segments + placement vertices/edges (data-snap-*).
 * Polygon finish: close near first/attach, double-click, or Done; Escape cancels.
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
    window.removeEventListener("keydown", this.onKeyDown)
    if (this.finishBtn) this.finishBtn.removeEventListener("click", this.onFinishClick)
    this.clearWallDraft()
    this.clearPolygonDraft()
    this.clearSnapIndicator()
  },

  syncFromEl() {
    const nextMode = this.el.dataset.mode || "wall"
    const nextLocationId = this.el.dataset.locationId || ""
    const nextPlaceMode = this.el.dataset.placeMode || "new"
    const nextExisting = this.parseExistingPoints(this.el.dataset.existingPoints)

    const modeChanged = nextMode !== this.mode
    const locationChanged = nextLocationId !== this.locationId
    const placeModeChanged = nextPlaceMode !== this.placeMode
    const existingChanged =
      JSON.stringify(nextExisting) !== JSON.stringify(this.existingPoints || [])

    if (modeChanged || locationChanged || placeModeChanged || existingChanged) {
      this.clearWallDraft()
      this.clearPolygonDraft()
      this.clearSnapIndicator()
    }

    this.mode = nextMode
    this.locationId = nextLocationId
    this.placeMode = nextPlaceMode
    this.existingPoints = nextExisting
  },

  parseExistingPoints(raw) {
    if (!raw) return []
    try {
      const parsed = JSON.parse(raw)
      if (!Array.isArray(parsed)) return []
      return parsed
        .map((p) => ({x: Number(p.x), y: Number(p.y)}))
        .filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y))
    } catch (_err) {
      return []
    }
  },

  handleKeyDown(event) {
    if (!this.isEditorHotkeyTarget(event)) return

    const meta = event.ctrlKey || event.metaKey
    if (!meta) {
      if (event.key === "Escape") {
        if (this.mode === "wall" && this.draftWall) {
          event.preventDefault()
          this.clearWallDraft()
          this.clearSnapIndicator()
          return
        }
        if (this.mode === "place" && this.draftPolygon) {
          event.preventDefault()
          this.clearPolygonDraft()
          this.clearSnapIndicator()
          this.updateFinishButton()
          return
        }
      }

      if (this.mode === "place" && this.draftPolygon) {
        if (event.key === "Enter") {
          event.preventDefault()
          this.finishPolygon()
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
      this.el.focus({preventScroll: true})

      if (!this.draftWall) {
        this.draftWall = {start: point, current: point}
        this.drawWallDraft()
        return
      }

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
      return
    }

    if (this.mode === "place" && this.locationId) {
      event.preventDefault()
      this.el.focus({preventScroll: true})
      this.handlePlaceClick(point)
    }
  },

  handlePlaceClick(point) {
    const extending =
      this.placeMode === "extend" && this.existingPoints && this.existingPoints.length >= 3

    if (!this.draftPolygon) {
      if (extending) {
        const attach = this.nearestExistingVertex(point)
        if (!attach) return
        this.draftPolygon = {
          mode: "extend",
          existing: this.existingPoints.slice(),
          attachIndex: attach.index,
          points: [attach.point],
          current: attach.point,
        }
        this.drawPolygonDraft()
        this.updateFinishButton()
        return
      }

      this.draftPolygon = {mode: "new", points: [point], current: point}
      this.drawPolygonDraft()
      this.updateFinishButton()
      return
    }

    if (this.draftPolygon.mode === "extend") {
      this.handleExtendClick(point)
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
  },

  handleExtendClick(point) {
    const draft = this.draftPolygon
    const existingHit = this.nearestExistingVertex(point)

    // After the attach vertex, closing on any existing vertex (including attach) merges.
    if (draft.points.length >= 2 && existingHit) {
      draft.closeIndex = existingHit.index
      this.finishPolygon()
      return
    }

    // Also allow closing near the first point of the new chain (attach).
    const first = draft.points[0]
    if (
      draft.points.length >= 2 &&
      Math.hypot(point.x - first.x, point.y - first.y) <= CLOSE_DISTANCE
    ) {
      draft.closeIndex = draft.attachIndex
      this.finishPolygon()
      return
    }

    draft.points.push(point)
    draft.current = point
    this.drawPolygonDraft()
    this.updateFinishButton()
  },

  nearestExistingVertex(point) {
    const existing = this.existingPoints || []
    let best = null
    let bestDist = CLOSE_DISTANCE
    for (let i = 0; i < existing.length; i++) {
      const ep = existing[i]
      const d = Math.hypot(ep.x - point.x, ep.y - point.y)
      if (d <= bestDist) {
        bestDist = d
        best = {index: i, point: {x: ep.x, y: ep.y}}
      }
    }
    return best
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

  handleDblClick(event) {
    if (this.mode !== "place" || !this.draftPolygon) return
    event.preventDefault()
    this.finishPolygon()
  },

  finishPolygon() {
    if (!this.draftPolygon || !this.locationId) return

    let points
    if (this.draftPolygon.mode === "extend") {
      points = this.mergeExtension(this.draftPolygon)
    } else {
      points = this.draftPolygon.points
    }

    this.clearPolygonDraft()
    this.clearSnapIndicator()
    this.updateFinishButton()
    if (!points || points.length < 3) return

    this.pushEvent("polygon_placed", {
      location_id: this.locationId,
      points: points.map((p) => ({x: p.x, y: p.y})),
    })
  },

  /**
   * Merge extension chain into existing ring.
   * draft.points[0] is the attach vertex; points[1..] are new vertices.
   * closeIndex defaults to attachIndex (Done / close-to-start).
   */
  mergeExtension(draft) {
    const existing = draft.existing
    const attachIdx = draft.attachIndex
    const closeIdx =
      typeof draft.closeIndex === "number" ? draft.closeIndex : draft.attachIndex
    const newPoints = draft.points.slice(1)

    if (newPoints.length < 1) return null

    if (closeIdx === attachIdx) {
      return existing
        .slice(0, attachIdx + 1)
        .concat(newPoints)
        .concat(existing.slice(attachIdx + 1))
        .map((p) => ({x: p.x, y: p.y}))
    }

    if (closeIdx > attachIdx) {
      return existing
        .slice(0, attachIdx + 1)
        .concat(newPoints)
        .concat(existing.slice(closeIdx))
        .map((p) => ({x: p.x, y: p.y}))
    }

    // Wrap-around: keep close..attach, then splice new points after attach.
    return existing
      .slice(closeIdx, attachIdx + 1)
      .concat(newPoints)
      .map((p) => ({x: p.x, y: p.y}))
  },

  updateFinishButton() {
    if (!this.finishBtn) return
    let show = false
    if (this.draftPolygon) {
      if (this.draftPolygon.mode === "extend") {
        show = this.draftPolygon.points.length >= 2
      } else {
        show = this.draftPolygon.points.length >= 3
      }
    }
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
   * Shared snap for walls and location polygons: wall + placement vertices,
   * then nearest point along wall/placement segments within SNAP_DISTANCE.
   */
  snap(point) {
    if (!point) return {point: null, snapped: false}

    const segs = this.collectSnapSegments()
    const vertices = this.collectSnapVertices(segs)

    let best = null
    let bestDist = SNAP_DISTANCE
    for (const ep of vertices) {
      const d = Math.hypot(ep.x - point.x, ep.y - point.y)
      if (d <= bestDist) {
        bestDist = d
        best = ep
      }
    }
    if (best) return {point: {x: best.x, y: best.y}, snapped: true}

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

  collectSnapSegments() {
    const segs = []
    if (!this.svg) return segs

    this.svg.querySelectorAll("[data-wall-seg]").forEach((line) => {
      segs.push([
        {x: Number(line.getAttribute("x1")), y: Number(line.getAttribute("y1"))},
        {x: Number(line.getAttribute("x2")), y: Number(line.getAttribute("y2"))},
      ])
    })

    this.svg.querySelectorAll("[data-snap-edge]").forEach((line) => {
      segs.push([
        {x: Number(line.getAttribute("x1")), y: Number(line.getAttribute("y1"))},
        {x: Number(line.getAttribute("x2")), y: Number(line.getAttribute("y2"))},
      ])
    })

    return segs
  },

  collectSnapVertices(segs) {
    const vertices = []
    const seen = new Set()
    const add = (p) => {
      const key = `${p.x.toFixed(5)},${p.y.toFixed(5)}`
      if (seen.has(key)) return
      seen.add(key)
      vertices.push(p)
    }

    for (const [a, b] of segs) {
      add(a)
      add(b)
    }

    if (this.svg) {
      this.svg.querySelectorAll("[data-snap-vertex]").forEach((el) => {
        const x = Number(el.getAttribute("cx") ?? el.getAttribute("x"))
        const y = Number(el.getAttribute("cy") ?? el.getAttribute("y"))
        if (Number.isFinite(x) && Number.isFinite(y)) add({x, y})
      })
    }

    return vertices
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
    const {points, current, mode, existing, attachIndex} = this.draftPolygon
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

    if (mode === "extend" && existing && existing.length >= 3) {
      // Preview merged outline when we have enough of a chain; otherwise show open polyline via polygon of chain only.
      const preview =
        points.length >= 2
          ? this.mergeExtension({
              existing,
              attachIndex,
              points,
              closeIndex: attachIndex,
            })
          : null
      if (preview && preview.length >= 3) {
        const withCursor = current ? preview.concat([current]) : preview
        poly.setAttribute("points", withCursor.map((p) => `${p.x},${p.y}`).join(" "))
      } else {
        poly.setAttribute("points", all.map((p) => `${p.x},${p.y}`).join(" "))
      }
    } else {
      poly.setAttribute("points", all.map((p) => `${p.x},${p.y}`).join(" "))
    }

    let layer = this.svg.querySelector("[data-polygon-draft-vertices]")
    if (!layer) {
      layer = document.createElementNS("http://www.w3.org/2000/svg", "g")
      layer.setAttribute("data-polygon-draft-vertices", "true")
      this.svg.appendChild(layer)
    }
    while (layer.firstChild) layer.removeChild(layer.firstChild)

    if (mode === "extend" && existing) {
      for (let i = 0; i < existing.length; i++) {
        const p = existing[i]
        const c = document.createElementNS("http://www.w3.org/2000/svg", "circle")
        c.setAttribute("cx", p.x)
        c.setAttribute("cy", p.y)
        c.setAttribute("r", i === attachIndex ? "0.016" : "0.011")
        c.setAttribute(
          "class",
          i === attachIndex ? "fill-secondary stroke-base-100" : "fill-base-content/40",
        )
        c.setAttribute("stroke-width", "0.004")
        layer.appendChild(c)
      }
    }

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
