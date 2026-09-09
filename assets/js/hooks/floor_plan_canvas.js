/**
 * SVG floor-plan canvas: draw/erase/move walls and draw/extend/move location polygons.
 *
 * data-mode: "wall" | "erase" | "move" | "place"
 * data-location-id: when mode is "place", the location for the polygon
 * data-place-mode: "new" | "extend"
 * data-existing-points: JSON [{x,y}, ...] when extending an existing polygon
 *
 * Pushes LiveView events:
 *   wall_drawn      — {x1,y1,x2,y2} normalized 0–1
 *   wall_erased     — {index}
 *   wall_moved      — {index, x1,y1,x2,y2}
 *   polygon_placed  — {location_id, points: [{x,y}, ...]} (full polygon)
 *   polygon_moved   — {location_id, points: [{x,y}, ...]}
 *   undo / redo     — keyboard shortcuts
 *
 * Walls: first click sets start (snap), second click commits; Escape cancels.
 * Move: drag a wall segment (or endpoint) / location polygon; Escape cancels drag.
 * Snap: wall endpoints/segments + placement vertices/edges (data-snap-*).
 * Polygon finish: close on a different vertex, double-click, or Done (adjacent auto); Escape cancels.
 */
import {
  mergeExtension as mergeExtensionGeometry,
  provisionalCloseIndex,
} from "./floor_plan_geometry.js"

const MIN_WALL_LENGTH = 0.02
const SNAP_DISTANCE = 0.03
const CLOSE_DISTANCE = 0.025
const ENDPOINT_HIT = 0.028

const FloorPlanCanvas = {
  mounted() {
    this.svg = this.el.querySelector("[data-floor-plan-svg]")
    this.finishBtn = this.el.querySelector("[data-polygon-finish]")
    this.draftWall = null
    this.draftPolygon = null
    this.moveDrag = null
    this.moveHoverEl = null
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
    if (this.moveDrag) this.applyMoveDragVisual()
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
    this.clearMoveDrag(false)
    this.clearMoveHover()
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
      this.clearMoveDrag(false)
      this.clearMoveHover()
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
        if (this.moveDrag) {
          event.preventDefault()
          this.clearMoveDrag(true)
          this.clearSnapIndicator()
          return
        }
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

    if (this.mode === "move") {
      event.preventDefault()
      this.el.focus({preventScroll: true})
      this.beginMoveDrag(event)
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

    // Explicit click-close requires a different existing vertex than the attach.
    if (draft.points.length >= 2 && existingHit) {
      if (existingHit.index === draft.attachIndex) {
        return
      }
      draft.closeIndex = existingHit.index
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

    if (this.mode === "move") {
      if (this.moveDrag) {
        this.updateMoveDrag(raw)
        return
      }
      this.updateMoveHover(event)
      this.clearSnapIndicator()
      return
    }

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
    if (event.button !== 0) return
    if (!this.moveDrag) return
    const raw = this.eventToUnit(event) || this.moveDrag.lastPointer
    this.commitMoveDrag(raw)
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
   * Merge extension chain into existing ring (arc replace; see floor_plan_geometry.js).
   * Done / unset closeIndex auto-picks an adjacent edge; click-close uses closeIndex ≠ attach.
   */
  mergeExtension(draft) {
    return mergeExtensionGeometry(draft)
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

  collectSnapVertices(segs, opts = {}) {
    const vertices = []
    const seen = new Set()
    const excludeLoc = opts.excludeLocationId
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
        if (excludeLoc) {
          const snapGroup = el.closest("[data-placement-snap]")
          if (snapGroup && snapGroup.getAttribute("data-placement-snap") === String(excludeLoc)) {
            return
          }
        }
        const x = Number(el.getAttribute("cx") ?? el.getAttribute("x"))
        const y = Number(el.getAttribute("cy") ?? el.getAttribute("y"))
        if (Number.isFinite(x) && Number.isFinite(y)) add({x, y})
      })
    }

    return vertices
  },

  beginMoveDrag(event) {
    const raw = this.eventToUnit(event)
    if (!raw) return

    const wallEl = event.target.closest("[data-wall-index]")
    if (wallEl) {
      const index = Number(wallEl.dataset.wallIndex)
      const x1 = Number(wallEl.getAttribute("x1"))
      const y1 = Number(wallEl.getAttribute("y1"))
      const x2 = Number(wallEl.getAttribute("x2"))
      const y2 = Number(wallEl.getAttribute("y2"))
      if (![x1, y1, x2, y2].every(Number.isFinite)) return

      const start = {x: x1, y: y1}
      const end = {x: x2, y: y2}
      const dStart = Math.hypot(raw.x - start.x, raw.y - start.y)
      const dEnd = Math.hypot(raw.x - end.x, raw.y - end.y)
      let kind = "wall"
      let which = null
      if (dStart <= ENDPOINT_HIT && dStart <= dEnd) {
        kind = "wall_end"
        which = "start"
      } else if (dEnd <= ENDPOINT_HIT) {
        kind = "wall_end"
        which = "end"
      }

      const group = wallEl.parentElement
      const segEl = group && group.querySelector("[data-wall-seg]")
      this.clearMoveHover()
      this.moveDrag = {
        kind,
        index,
        which,
        startPointer: raw,
        lastPointer: raw,
        original: {x1, y1, x2, y2},
        wallEl,
        segEl,
      }
      this.setMoveHighlight(wallEl, true)
      if (segEl) this.setMoveHighlight(segEl, true)
      this.applyMoveDragVisual()
      return
    }

    const polyEl = event.target.closest("[data-placement-location-id]")
    if (polyEl) {
      const locationId = polyEl.dataset.placementLocationId
      const points = parsePointsAttr(polyEl.getAttribute("points"))
      if (!locationId || points.length < 3) return
      const group = polyEl.parentElement
      this.clearMoveHover()
      this.moveDrag = {
        kind: "polygon",
        locationId,
        startPointer: raw,
        lastPointer: raw,
        original: points.map((p) => ({x: p.x, y: p.y})),
        polyEl,
        group,
      }
      this.setMoveHighlight(polyEl, true)
      this.applyMoveDragVisual()
    }
  },

  updateMoveDrag(raw) {
    if (!this.moveDrag || !raw) return
    this.moveDrag.lastPointer = raw
    const geometry = this.computeMoveGeometry(raw, true)
    this.moveDrag.preview = geometry
    this.applyMoveDragVisual()
  },

  commitMoveDrag(raw) {
    if (!this.moveDrag) return
    const geometry = this.computeMoveGeometry(raw || this.moveDrag.lastPointer, true)
    const drag = this.moveDrag

    if (drag.kind === "wall" || drag.kind === "wall_end") {
      const {x1, y1, x2, y2} = geometry
      const unchanged =
        approxEq(x1, drag.original.x1) &&
        approxEq(y1, drag.original.y1) &&
        approxEq(x2, drag.original.x2) &&
        approxEq(y2, drag.original.y2)
      const tooShort = Math.hypot(x2 - x1, y2 - y1) < MIN_WALL_LENGTH
      if (!unchanged && tooShort) {
        this.clearMoveDrag(true)
      } else {
        this.clearMoveDrag(false)
      }
      this.clearSnapIndicator()
      if (!unchanged && !tooShort) {
        this.pushEvent("wall_moved", {index: drag.index, x1, y1, x2, y2})
      }
      return
    }

    if (drag.kind === "polygon") {
      const points = geometry
      const unchanged =
        points.length === drag.original.length &&
        points.every((p, i) => approxEq(p.x, drag.original[i].x) && approxEq(p.y, drag.original[i].y))
      this.clearMoveDrag(false)
      this.clearSnapIndicator()
      if (!unchanged && points.length >= 3) {
        this.pushEvent("polygon_moved", {
          location_id: drag.locationId,
          points: points.map((p) => ({x: p.x, y: p.y})),
        })
      }
    }
  },

  computeMoveGeometry(pointer, withSnap) {
    const drag = this.moveDrag
    if (!drag || !pointer) {
      if (drag?.kind === "polygon") return drag.original
      return drag?.original
    }

    const dx = pointer.x - drag.startPointer.x
    const dy = pointer.y - drag.startPointer.y

    if (drag.kind === "wall_end") {
      let x1 = drag.original.x1
      let y1 = drag.original.y1
      let x2 = drag.original.x2
      let y2 = drag.original.y2
      if (drag.which === "start") {
        let p = {x: clamp01(x1 + dx), y: clamp01(y1 + dy)}
        if (withSnap) {
          const snapped = this.snapExcludingWall(p, drag.index)
          this.snapPoint = snapped.snapped ? snapped.point : null
          this.drawSnapIndicator()
          p = snapped.point
        }
        x1 = p.x
        y1 = p.y
      } else {
        let p = {x: clamp01(x2 + dx), y: clamp01(y2 + dy)}
        if (withSnap) {
          const snapped = this.snapExcludingWall(p, drag.index)
          this.snapPoint = snapped.snapped ? snapped.point : null
          this.drawSnapIndicator()
          p = snapped.point
        }
        x2 = p.x
        y2 = p.y
      }
      return {x1, y1, x2, y2}
    }

    if (drag.kind === "wall") {
      const pts = [
        {x: drag.original.x1, y: drag.original.y1},
        {x: drag.original.x2, y: drag.original.y2},
      ]
      let delta = clampTranslate(pts, dx, dy)
      if (withSnap) {
        delta = this.snapTranslateDelta(pts, delta.dx, delta.dy, {
          excludeWallIndex: drag.index,
        })
        delta = clampTranslate(pts, delta.dx, delta.dy)
      }
      return {
        x1: drag.original.x1 + delta.dx,
        y1: drag.original.y1 + delta.dy,
        x2: drag.original.x2 + delta.dx,
        y2: drag.original.y2 + delta.dy,
      }
    }

    // polygon
    let delta = clampTranslate(drag.original, dx, dy)
    if (withSnap) {
      delta = this.snapTranslateDelta(drag.original, delta.dx, delta.dy, {
        excludeLocationId: drag.locationId,
      })
      delta = clampTranslate(drag.original, delta.dx, delta.dy)
    }
    return drag.original.map((p) => ({
      x: p.x + delta.dx,
      y: p.y + delta.dy,
    }))
  },

  /**
   * Adjust a uniform translate so the nearest moved vertex snaps, if within range.
   */
  snapTranslateDelta(points, dx, dy, opts = {}) {
    let bestAdj = null
    let bestDist = SNAP_DISTANCE

    for (const p of points) {
      const moved = {x: clamp01(p.x + dx), y: clamp01(p.y + dy)}
      const snapped = this.snapExcluding(moved, opts)
      if (!snapped.snapped) continue
      const adjDx = snapped.point.x - p.x
      const adjDy = snapped.point.y - p.y
      const d = Math.hypot(snapped.point.x - moved.x, snapped.point.y - moved.y)
      if (d <= bestDist) {
        bestDist = d
        bestAdj = {dx: adjDx, dy: adjDy}
      }
    }

    if (bestAdj) {
      this.snapPoint = {
        x: clamp01(points[0].x + bestAdj.dx),
        y: clamp01(points[0].y + bestAdj.dy),
      }
      // Prefer showing the actual snapped vertex: recompute best display point
      for (const p of points) {
        const candidate = {x: clamp01(p.x + bestAdj.dx), y: clamp01(p.y + bestAdj.dy)}
        const check = this.snapExcluding(candidate, opts)
        if (check.snapped && approxEq(check.point.x, candidate.x) && approxEq(check.point.y, candidate.y)) {
          this.snapPoint = check.point
          break
        }
      }
      this.drawSnapIndicator()
      return bestAdj
    }

    this.snapPoint = null
    this.drawSnapIndicator()
    return {dx, dy}
  },

  snapExcludingWall(point, wallIndex) {
    return this.snapExcluding(point, {excludeWallIndex: wallIndex})
  },

  snapExcluding(point, opts = {}) {
    if (!point) return {point: null, snapped: false}

    const segs = this.collectSnapSegmentsFiltered(opts)
    const vertices = this.collectSnapVertices(segs, opts)

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

  collectSnapSegmentsFiltered(opts = {}) {
    const segs = []
    if (!this.svg) return segs
    const excludeWall = opts.excludeWallIndex
    const excludeLoc = opts.excludeLocationId

    this.svg.querySelectorAll("[data-wall-seg]").forEach((line) => {
      const hit = line.parentElement && line.parentElement.querySelector("[data-wall-index]")
      if (hit && excludeWall != null && Number(hit.dataset.wallIndex) === excludeWall) {
        return
      }
      segs.push([
        {x: Number(line.getAttribute("x1")), y: Number(line.getAttribute("y1"))},
        {x: Number(line.getAttribute("x2")), y: Number(line.getAttribute("y2"))},
      ])
    })

    this.svg.querySelectorAll("[data-snap-edge]").forEach((line) => {
      if (excludeLoc) {
        const snapGroup = line.closest("[data-placement-snap]")
        if (snapGroup && snapGroup.getAttribute("data-placement-snap") === String(excludeLoc)) {
          return
        }
      }
      segs.push([
        {x: Number(line.getAttribute("x1")), y: Number(line.getAttribute("y1"))},
        {x: Number(line.getAttribute("x2")), y: Number(line.getAttribute("y2"))},
      ])
    })

    return segs
  },

  applyMoveDragVisual() {
    const drag = this.moveDrag
    if (!drag) return
    const geometry = drag.preview || this.computeMoveGeometry(drag.lastPointer, false)

    if (drag.kind === "wall" || drag.kind === "wall_end") {
      const {x1, y1, x2, y2} = geometry
      if (drag.wallEl) {
        drag.wallEl.setAttribute("x1", x1)
        drag.wallEl.setAttribute("y1", y1)
        drag.wallEl.setAttribute("x2", x2)
        drag.wallEl.setAttribute("y2", y2)
      }
      if (drag.segEl) {
        drag.segEl.setAttribute("x1", x1)
        drag.segEl.setAttribute("y1", y1)
        drag.segEl.setAttribute("x2", x2)
        drag.segEl.setAttribute("y2", y2)
      }
      return
    }

    if (drag.kind === "polygon" && drag.polyEl) {
      this.applyPolygonVisual(drag.polyEl, drag.group, geometry)
    }
  },

  applyPolygonVisual(polyEl, group, points) {
    polyEl.setAttribute("points", points.map((p) => `${p.x},${p.y}`).join(" "))
    if (!group) return

    const edges = group.querySelectorAll("[data-snap-edge]")
    for (let i = 0; i < edges.length; i++) {
      const a = points[i]
      const b = points[(i + 1) % points.length]
      if (!a || !b) break
      edges[i].setAttribute("x1", a.x)
      edges[i].setAttribute("y1", a.y)
      edges[i].setAttribute("x2", b.x)
      edges[i].setAttribute("y2", b.y)
    }

    const verts = group.querySelectorAll("[data-snap-vertex]")
    for (let i = 0; i < verts.length; i++) {
      const p = points[i]
      if (!p) break
      verts[i].setAttribute("cx", p.x)
      verts[i].setAttribute("cy", p.y)
    }

    const label = group.querySelector("text")
    if (label && points.length) {
      const c = polygonCentroid(points)
      label.setAttribute("x", c.x)
      label.setAttribute("y", c.y)
    }
  },

  restoreWallVisual(drag) {
    if (!drag?.original) return
    const {x1, y1, x2, y2} = drag.original
    if (drag.wallEl) {
      drag.wallEl.setAttribute("x1", x1)
      drag.wallEl.setAttribute("y1", y1)
      drag.wallEl.setAttribute("x2", x2)
      drag.wallEl.setAttribute("y2", y2)
    }
    if (drag.segEl) {
      drag.segEl.setAttribute("x1", x1)
      drag.segEl.setAttribute("y1", y1)
      drag.segEl.setAttribute("x2", x2)
      drag.segEl.setAttribute("y2", y2)
    }
  },

  clearMoveDrag(restore) {
    const drag = this.moveDrag
    if (!drag) return

    if (restore) {
      if (drag.kind === "wall" || drag.kind === "wall_end") {
        this.restoreWallVisual(drag)
      } else if (drag.kind === "polygon" && drag.polyEl) {
        this.applyPolygonVisual(drag.polyEl, drag.group, drag.original)
      }
    }

    if (drag.wallEl) this.setMoveHighlight(drag.wallEl, false)
    if (drag.segEl) this.setMoveHighlight(drag.segEl, false)
    if (drag.polyEl) this.setMoveHighlight(drag.polyEl, false)

    this.moveDrag = null
  },

  updateMoveHover(event) {
    const wallEl = event.target.closest("[data-wall-index]")
    const polyEl = event.target.closest("[data-placement-location-id]")
    const next = wallEl || polyEl || null
    if (next === this.moveHoverEl) return
    this.clearMoveHover()
    if (next) {
      this.moveHoverEl = next
      this.setMoveHighlight(next, true)
      const seg = next.parentElement && next.parentElement.querySelector("[data-wall-seg]")
      if (seg && next.hasAttribute("data-wall-index")) this.setMoveHighlight(seg, true)
    }
  },

  clearMoveHover() {
    if (!this.moveHoverEl) return
    const el = this.moveHoverEl
    this.setMoveHighlight(el, false)
    const seg = el.parentElement && el.parentElement.querySelector("[data-wall-seg]")
    if (seg && el.hasAttribute("data-wall-index")) this.setMoveHighlight(seg, false)
    this.moveHoverEl = null
  },

  setMoveHighlight(el, on) {
    if (!el) return
    if (on) el.setAttribute("data-move-active", "true")
    else el.removeAttribute("data-move-active")
    if (el.hasAttribute("data-wall-seg")) {
      el.classList.toggle("opacity-80", !on)
      el.classList.toggle("opacity-100", on)
      el.classList.toggle("text-primary", on)
    }
    if (el.hasAttribute("data-placement-location-id")) {
      el.classList.toggle("fill-primary/45", on)
      el.classList.toggle("stroke-secondary", on)
    }
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
      // Preview using the same merge as commit; provisional close = nearby vertex or adjacent auto.
      let preview = null
      if (points.length >= 2) {
        const chain = current ? points.concat([current]) : points
        if (chain.length >= 2) {
          const closeIndex = provisionalCloseIndex(
            existing,
            attachIndex,
            current,
            CLOSE_DISTANCE,
          )
          preview = this.mergeExtension({
            existing,
            attachIndex,
            points: chain,
            closeIndex,
          })
        }
      }
      if (preview && preview.length >= 3) {
        poly.setAttribute("points", preview.map((p) => `${p.x},${p.y}`).join(" "))
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

function clampTranslate(points, dx, dy) {
  let adx = dx
  let ady = dy
  for (const p of points) {
    adx = Math.max(-p.x, Math.min(1 - p.x, adx))
    ady = Math.max(-p.y, Math.min(1 - p.y, ady))
  }
  return {dx: adx, dy: ady}
}

function approxEq(a, b) {
  return Math.abs(a - b) < 1e-6
}

function parsePointsAttr(attr) {
  if (!attr) return []
  return attr
    .trim()
    .split(/\s+/)
    .map((pair) => {
      const [x, y] = pair.split(",").map(Number)
      return {x, y}
    })
    .filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y))
}

function polygonCentroid(points) {
  if (!points.length) return {x: 0.5, y: 0.5}
  let sx = 0
  let sy = 0
  for (const p of points) {
    sx += p.x
    sy += p.y
  }
  return {x: sx / points.length, y: sy / points.length}
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
