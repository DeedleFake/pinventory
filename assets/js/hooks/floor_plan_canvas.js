/**
 * SVG floor-plan canvas: draw/erase walls and draw/extend location polygons.
 *
 * data-mode: "wall" | "erase" | "place" | "browse"
 * data-location-id: when mode is "place", the location for the polygon
 * data-place-mode: "new" | "extend"
 * data-existing-points: JSON [{x,y}, ...] when extending an existing polygon
 *
 * Pushes LiveView events:
 *   wall_drawn      — {x1,y1,x2,y2} world coords
 *   wall_erased     — {id}
 *   polygon_placed  — {location_id, points: [{x,y}, ...]} (full polygon)
 *   undo / redo     — keyboard shortcuts
 *
 * Walls: first click sets start (snap), second click commits; Escape cancels.
 * Snap: wall endpoints/segments + placement vertices/edges (data-snap-*).
 * Hold Ctrl/Meta to place at raw canvas coords (no geometry snap); preview follows.
 * Hold Shift while drafting to constrain to 22.5° angles (16 directions). Walls
 * snap from the start point; polygons may also meet a closing H/V through the
 * first vertex when the cursor is near that axis (line-snap style), else
 * newest-edge only. Order: raw → Shift angle → geometry snap only on that
 * angle line (vertex on-line or segment∩line). Off-angle line snap never wins.
 * Ctrl/Meta skips geometry snap; Shift still angle-constrains. Shift
 * keydown/keyup refreshes the draft.
 * Draft corners dedupe within SNAP_DISTANCE so near-clicks reuse an existing vertex.
 * Draft length labels (feet) sit along the active segment(s); polygons show newest + closing.
 * Polygon finish: close on a different vertex, double-click, or Done (adjacent auto); Escape cancels.
 *
 * Camera: unbounded world (finite floats). SVG viewBox is the viewport (zoom/pan).
 * Wheel zooms toward cursor; browse primary-drag pans; editor uses Space+drag or middle-mouse.
 * Browse Reset/mount fits content tightly (~8% pad). Edit Reset/mount uses a roomier pad so
 * empty world around content is clickable (screen edge is not the old unit-square edge).
 * preserveAspectRatio meet keeps the view square (no window stretch).
 */
import {
  angleSnapPoint,
  angleSnapPointDual,
  contentBoundsFromSegments,
  DEFAULT_FEET_PER_UNIT,
  fitSquareCamera,
  formatFeet,
  lengthInFeet,
  MEASUREMENT_EDGE_GAP_PX,
  measurementFontSize,
  measurementLabelPose,
  worldFromScreenPx,
  mergeExtension as mergeExtensionGeometry,
  nearestVertexWithin,
  provisionalCloseIndex,
  snapOnAngleLine,
} from "./floor_plan_geometry.js"

const MIN_WALL_LENGTH = 0.02
const SNAP_DISTANCE = 0.03
const CLOSE_DISTANCE = 0.025
const PAN_DRAG_THRESHOLD = 6

const FloorPlanCanvas = {
  mounted() {
    this.svg = this.el.querySelector("[data-floor-plan-svg]")
    this.finishBtn = this.el.querySelector("[data-polygon-finish]")
    this.resetBtn = this.el.querySelector("[data-zoom-reset]")
    this.draftWall = null
    this.draftPolygon = null
    this.snapPoint = null
    this.lastRawPoint = null
    this.spaceHeld = false
    this.panning = false
    this.panLast = null
    this.browsePanCandidate = null
    this.suppressClickAfterPan = false
    this.camera = {x: 0, y: 0, size: 1}
    this.feetPerUnit = DEFAULT_FEET_PER_UNIT
    this.floorSvgId = this.svg ? this.svg.id : null
    this.syncFromEl()
    this.resetCamera()

    this.onPointerDown = (event) => this.handlePointerDown(event)
    this.onPointerMove = (event) => this.handlePointerMove(event)
    this.onPointerUp = (event) => this.handlePointerUp(event)
    this.onDblClick = (event) => this.handleDblClick(event)
    this.onKeyDown = (event) => this.handleKeyDown(event)
    this.onKeyUp = (event) => this.handleKeyUp(event)
    this.onWheel = (event) => this.handleWheel(event)
    this.onFinishClick = (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.finishPolygon()
    }
    this.onResetClick = (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.resetCamera()
    }

    this.svg.addEventListener("pointerdown", this.onPointerDown)
    this.svg.addEventListener("dblclick", this.onDblClick)
    this.el.addEventListener("wheel", this.onWheel, {passive: false})
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("pointercancel", this.onPointerUp)
    window.addEventListener("keydown", this.onKeyDown)
    window.addEventListener("keyup", this.onKeyUp)
    if (this.finishBtn) this.finishBtn.addEventListener("click", this.onFinishClick)
    if (this.resetBtn) this.resetBtn.addEventListener("click", this.onResetClick)

    if (!this.el.hasAttribute("tabindex")) {
      this.el.setAttribute("tabindex", "0")
    }

    this.updateFinishButton()
    this.updatePanCursor()
  },

  updated() {
    // Floor switches change the SVG id (floor-svg-<id> / locations-floor-svg-<id>),
    // so morphdom replaces the node. Rebind listeners — mounted() only runs once
    // on the stable canvas wrapper. Fit the new floor's content (don't keep pan/zoom).
    const nextSvg = this.el.querySelector("[data-floor-plan-svg]")
    const nextId = nextSvg ? nextSvg.id : null
    const floorChanged = nextSvg !== this.svg || nextId !== this.floorSvgId
    if (nextSvg !== this.svg) {
      if (this.svg) {
        this.svg.removeEventListener("pointerdown", this.onPointerDown)
        this.svg.removeEventListener("dblclick", this.onDblClick)
      }
      this.svg = nextSvg
      if (this.svg) {
        this.svg.addEventListener("pointerdown", this.onPointerDown)
        this.svg.addEventListener("dblclick", this.onDblClick)
      }
      // Draft overlays lived on the old SVG; drop in-progress drawing.
      this.draftWall = null
      this.draftPolygon = null
      this.snapPoint = null
    }
    if (floorChanged) {
      this.floorSvgId = nextId
      this.syncFromEl()
      this.resetCamera()
    }

    const nextFinish = this.el.querySelector("[data-polygon-finish]")
    if (nextFinish !== this.finishBtn) {
      if (this.finishBtn) this.finishBtn.removeEventListener("click", this.onFinishClick)
      this.finishBtn = nextFinish
      if (this.finishBtn) this.finishBtn.addEventListener("click", this.onFinishClick)
    }

    const nextReset = this.el.querySelector("[data-zoom-reset]")
    if (nextReset !== this.resetBtn) {
      if (this.resetBtn) this.resetBtn.removeEventListener("click", this.onResetClick)
      this.resetBtn = nextReset
      if (this.resetBtn) this.resetBtn.addEventListener("click", this.onResetClick)
    }

    this.syncFromEl()
    this.applyCamera()
    if (this.draftPolygon) this.drawPolygonDraft()
    if (this.draftWall) this.drawWallDraft()
    this.drawSnapIndicator()
    this.updateFinishButton()
    this.updatePanCursor()
  },

  destroyed() {
    if (this.svg) {
      this.svg.removeEventListener("pointerdown", this.onPointerDown)
      this.svg.removeEventListener("dblclick", this.onDblClick)
    }
    this.el.removeEventListener("wheel", this.onWheel)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerUp)
    window.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("keyup", this.onKeyUp)
    if (this.finishBtn) this.finishBtn.removeEventListener("click", this.onFinishClick)
    if (this.resetBtn) this.resetBtn.removeEventListener("click", this.onResetClick)
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
    const scale = Number(this.el.dataset.feetPerUnit)
    this.feetPerUnit = Number.isFinite(scale) && scale > 0 ? scale : DEFAULT_FEET_PER_UNIT
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
    if (event.key === "Control" || event.key === "Meta" || event.key === "Shift") {
      this.refreshPointerFromModifiers(event)
    }

    if (!this.isEditorHotkeyTarget(event)) return

    if (event.code === "Space" && !event.repeat) {
      // Space+drag pans without starting a wall/place click.
      event.preventDefault()
      this.spaceHeld = true
      this.updatePanCursor()
      return
    }

    // Browse mode only needs Space pan (handled above); never undo/redo here.
    if (this.mode === "browse") return

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
    if (document.getElementById("floor-plan-page") != null) return true
    // Locations browse canvas: Space-pan / wheel zoom without editor undo keys.
    return this.mode === "browse"
  },

  handleKeyUp(event) {
    if (event.key === "Control" || event.key === "Meta" || event.key === "Shift") {
      this.refreshPointerFromModifiers(event)
    }
    if (event.code === "Space") {
      this.spaceHeld = false
      if (!this.panning) this.updatePanCursor()
    }
  },

  /** True when Ctrl or Meta is held — placement uses raw canvas coords. */
  skipSnapFromEvent(event) {
    return !!(event && (event.ctrlKey || event.metaKey))
  },

  /**
   * Shift angle-snap anchors.
   * Wall: {prev: start, next: null}.
   * Polygon: prev = last committed point; next = first point when ≥2 points
   * (closing H/V, only if cursor is near that axis). Prefer newest edge.
   */
  draftAngleAnchors() {
    if (this.draftWall && this.draftWall.start) {
      return {prev: this.draftWall.start, next: null}
    }
    if (this.draftPolygon && this.draftPolygon.points && this.draftPolygon.points.length >= 1) {
      const pts = this.draftPolygon.points
      const prev = pts[pts.length - 1]
      const next = pts.length >= 2 ? pts[0] : null
      // Avoid dual snap when prev and next are the same vertex.
      if (next && Math.hypot(prev.x - next.x, prev.y - next.y) < 1e-12) {
        return {prev, next: null}
      }
      return {prev, next}
    }
    return {prev: null, next: null}
  },

  /** @deprecated use draftAngleAnchors */
  draftAnchor() {
    return this.draftAngleAnchors().prev
  },

  /**
   * Resolve pointer to world coords.
   * Order: raw → (if Shift + anchor) project onto nearest 22.5° ray → then
   * optional geometry snap along that constraint (Ctrl/Meta skips geometry snap;
   * Shift still angle-constrains). Always records lastRawPoint for modifier refresh.
   */
  resolvePointer(event) {
    const raw = this.eventToUnit(event)
    if (!raw) return {point: null, snapped: false, raw: null}
    this.lastRawPoint = raw
    return this.resolveFromRaw(raw, event)
  },

  /**
   * Shared resolve used by pointer moves and Shift/Ctrl/Meta key refresh.
   * `mods` is a keyboard/pointer event (shiftKey / ctrlKey / metaKey).
   */
  resolveFromRaw(raw, mods) {
    if (!raw) return {point: null, snapped: false, raw: null}
    const skipGeom = this.skipSnapFromEvent(mods)
    const shift = !!(mods && mods.shiftKey)
    const {prev, next} = this.draftAngleAnchors()

    let point = raw
    if (shift && prev) {
      point = next ? angleSnapPointDual(prev, next, raw) : angleSnapPoint(prev, raw)
    }

    if (skipGeom) {
      return {point, snapped: false, raw}
    }

    // Shift: angle wins — only snap to geometry that lies on the angle line.
    if (shift && prev) {
      const segs = this.collectSnapSegments()
      const verts = this.collectSnapVertices(segs)
      const onRay = snapOnAngleLine(prev, point, segs, verts, SNAP_DISTANCE)
      if (onRay) return {point: onRay, snapped: true, raw}
      return {point, snapped: false, raw}
    }

    const snapped = this.snap(point)
    return {point: snapped.point, snapped: snapped.snapped, raw}
  },

  refreshPointerFromModifiers(event) {
    if (!this.lastRawPoint) return
    if (!(this.mode === "wall" || (this.mode === "place" && this.locationId))) {
      return
    }
    const resolved = this.resolveFromRaw(this.lastRawPoint, event)
    this.snapPoint = resolved.snapped ? resolved.point : null
    this.drawSnapIndicator()
    if (this.draftWall) {
      this.draftWall.current = resolved.point
      this.drawWallDraft()
    } else if (this.draftPolygon) {
      this.draftPolygon.current = resolved.point
      this.drawPolygonDraft()
    }
  },

  /**
   * If `point` is within SNAP_DISTANCE of a draft vertex, reuse that vertex.
   * Returns {point, reusedIndex} where reusedIndex is null when no dedupe.
   */
  dedupeDraftPoint(point, draftVertices) {
    if (!point) return {point: null, reusedIndex: null}
    const hit = nearestVertexWithin(point, draftVertices || [], SNAP_DISTANCE)
    if (!hit) return {point, reusedIndex: null}
    return {point: hit.point, reusedIndex: hit.index}
  },

  handlePointerDown(event) {
    if (event.target.closest("[data-polygon-finish]")) return
    if (event.target.closest("[data-zoom-reset]")) return

    // Middle mouse, or Space + primary button: pan the camera.
    if (event.button === 1 || (event.button === 0 && this.spaceHeld)) {
      event.preventDefault()
      this.browsePanCandidate = null
      this.startPan(event)
      return
    }

    if (event.button !== 0) return

    // Browse: primary-button drag pans after a small movement threshold so
    // a plain click still fires placement phx-click / navigate.
    if (this.mode === "browse") {
      this.browsePanCandidate = {
        x: event.clientX,
        y: event.clientY,
        pointerId: event.pointerId,
      }
      this.suppressClickAfterPan = false
      return
    }

    if (this.mode === "erase") {
      const wallEl = event.target.closest("[data-wall-id]")
      if (wallEl) {
        event.preventDefault()
        this.pushEvent("wall_erased", {id: wallEl.dataset.wallId})
      }
      return
    }

    const resolved = this.resolvePointer(event)
    let point = resolved.point
    this.snapPoint = resolved.snapped ? resolved.point : null
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
      point = this.dedupeDraftPoint(point, [start]).point
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
    // Existing close-near-first (slightly tighter than snap) — keep before dedupe.
    if (
      this.draftPolygon.points.length >= 3 &&
      Math.hypot(point.x - first.x, point.y - first.y) <= CLOSE_DISTANCE
    ) {
      this.finishPolygon()
      return
    }

    const {point: commit, reusedIndex} = this.dedupeDraftPoint(
      point,
      this.draftPolygon.points,
    )
    // Dedupe onto the first vertex with enough points still closes the ring.
    if (reusedIndex === 0 && this.draftPolygon.points.length >= 3) {
      this.finishPolygon()
      return
    }
    // Near an already-placed draft corner: reuse it; do not stack a near-duplicate.
    if (reusedIndex != null) {
      this.draftPolygon.current = commit
      this.drawPolygonDraft()
      this.updateFinishButton()
      return
    }

    this.draftPolygon.points.push(commit)
    this.draftPolygon.current = commit
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

    const {point: commit, reusedIndex} = this.dedupeDraftPoint(point, draft.points)
    if (reusedIndex != null) {
      draft.current = commit
      this.drawPolygonDraft()
      this.updateFinishButton()
      return
    }

    draft.points.push(commit)
    draft.current = commit
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
    if (
      !this.panning &&
      this.browsePanCandidate &&
      this.mode === "browse" &&
      (event.buttons & 1) === 1
    ) {
      const dx = event.clientX - this.browsePanCandidate.x
      const dy = event.clientY - this.browsePanCandidate.y
      if (Math.hypot(dx, dy) >= PAN_DRAG_THRESHOLD) {
        const start = this.browsePanCandidate
        this.browsePanCandidate = null
        this.suppressClickAfterPan = true
        this.startPan({
          clientX: start.x,
          clientY: start.y,
          pointerId: start.pointerId,
        })
        // Apply this move immediately so the first delta isn't lost.
      }
    }

    if (this.panning && this.panLast) {
      event.preventDefault()
      const dx = event.clientX - this.panLast.x
      const dy = event.clientY - this.panLast.y
      this.panLast = {x: event.clientX, y: event.clientY}

      const rect = this.svg.getBoundingClientRect()
      const pixelSize = Math.min(rect.width, rect.height)
      if (pixelSize > 0) {
        const scale = this.camera.size / pixelSize
        this.camera.x -= dx * scale
        this.camera.y -= dy * scale
        this.clampCamera()
        this.applyCamera()
      }
      return
    }

    if (!(this.mode === "wall" || (this.mode === "place" && this.locationId))) {
      this.clearSnapIndicator()
      return
    }

    const resolved = this.resolvePointer(event)
    if (!resolved.point) return

    this.snapPoint = resolved.snapped ? resolved.point : null
    this.drawSnapIndicator()

    if (this.draftWall) {
      this.draftWall.current = resolved.point
      this.drawWallDraft()
      return
    }

    if (this.draftPolygon) {
      this.draftPolygon.current = resolved.point
      this.drawPolygonDraft()
    }
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

  /** Screen → world (unclamped). Name kept for call sites. */
  eventToUnit(event) {
    return this.clientToWorld(event && event.clientX, event && event.clientY)
  },

  /**
   * Screen → world via SVG CTM (honors viewBox zoom/pan + meet letterboxing).
   * Unclamped: world is unbounded.
   */
  clientToWorld(clientX, clientY) {
    if (!this.svg || clientX == null || clientY == null) return null
    const ctm = this.svg.getScreenCTM()
    if (!ctm) return null
    const pt = this.svg.createSVGPoint()
    pt.x = clientX
    pt.y = clientY
    const world = pt.matrixTransform(ctm.inverse())
    if (!Number.isFinite(world.x) || !Number.isFinite(world.y)) return null
    return {x: world.x, y: world.y}
  },

  applyCamera() {
    if (!this.svg || !this.camera) return
    const {x, y, size} = this.camera
    this.svg.setAttribute("viewBox", `${x} ${y} ${size} ${size}`)
    // Keep draft length labels screen-sized as zoom changes.
    if (this.draftWall) this.drawWallDraft()
    else if (this.draftPolygon) this.drawPolygonDraft()
  },

  /** Browse fits content; edit leaves empty world around so you can draw outside. */
  resetCamera() {
    const padding = this.mode === "browse" ? 0.08 : 0.5
    this.camera = fitSquareCamera(this.contentBounds(), padding)
    this.applyCamera()
  },

  /** Zoom size only — free pan (no world bounds). */
  clampCamera() {
    const cam = this.camera
    const bounds = this.contentBounds()
    const span = Math.max(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY, 1)
    const minSize = Math.max(0.05, span * 0.05)
    const maxSize = Math.max(2.5, span * 4)
    cam.size = Math.max(minSize, Math.min(maxSize, cam.size))
  },

  /**
   * Content AABB from live SVG walls + placement polygons (+ draft if any).
   * Empty → default {0,0,1,1}.
   */
  contentBounds() {
    const segments = []
    if (this.svg) {
      this.svg.querySelectorAll("[data-wall-seg]").forEach((line) => {
        segments.push([
          {x: Number(line.getAttribute("x1")), y: Number(line.getAttribute("y1"))},
          {x: Number(line.getAttribute("x2")), y: Number(line.getAttribute("y2"))},
        ])
      })
      this.svg.querySelectorAll("[data-placement-location-id]").forEach((poly) => {
        const raw = poly.getAttribute("points") || ""
        const pts = []
        for (const pair of raw.trim().split(/\s+/)) {
          if (!pair) continue
          const [xs, ys] = pair.split(",")
          pts.push({x: Number(xs), y: Number(ys)})
        }
        if (pts.length) segments.push(pts)
      })
    }
    if (this.draftWall) {
      const {start, current} = this.draftWall
      if (start) segments.push([start])
      if (current) segments.push([current])
    }
    if (this.draftPolygon && this.draftPolygon.points) {
      segments.push(this.draftPolygon.points)
      if (this.draftPolygon.current) segments.push([this.draftPolygon.current])
    }
    return contentBoundsFromSegments(segments)
  },

  handleWheel(event) {
    if (!this.svg) return
    event.preventDefault()

    const world = this.clientToWorld(event.clientX, event.clientY)
    if (!world) return

    const direction = event.deltaY < 0 ? -1 : 1
    // Trackpads can send small deltas; normalize toward discrete steps.
    const intensity = Math.min(1.5, Math.abs(event.deltaY) / 100)
    const factor = direction < 0 ? Math.pow(0.9, intensity) : Math.pow(1.1, intensity)
    const prev = this.camera.size
    const next = prev * factor
    if (next === prev) return

    const tX = (world.x - this.camera.x) / prev
    const tY = (world.y - this.camera.y) / prev
    this.camera.size = next
    this.camera.x = world.x - tX * next
    this.camera.y = world.y - tY * next
    this.clampCamera()
    // Re-anchor after size clamp so the cursor stays under the same world point.
    const size = this.camera.size
    this.camera.x = world.x - tX * size
    this.camera.y = world.y - tY * size
    this.applyCamera()
  },

  startPan(event) {
    this.panning = true
    this.panLast = {x: event.clientX, y: event.clientY}
    this.updatePanCursor()
    try {
      this.svg.setPointerCapture(event.pointerId)
    } catch (_err) {
      /* ignore */
    }
  },

  handlePointerUp(event) {
    this.browsePanCandidate = null

    if (this.panning) {
      this.panning = false
      this.panLast = null
      this.updatePanCursor()
    }

    if (this.suppressClickAfterPan) {
      this.suppressClickAfterPan = false
      // Swallow the click that browsers fire after a drag so we don't navigate.
      const suppress = (clickEvent) => {
        clickEvent.preventDefault()
        clickEvent.stopPropagation()
        clickEvent.stopImmediatePropagation?.()
      }
      const target = this.svg || this.el
      target.addEventListener("click", suppress, true)
      window.setTimeout(() => target.removeEventListener("click", suppress, true), 0)
      if (event && event.preventDefault) event.preventDefault()
    }
  },

  updatePanCursor() {
    if (!this.el) return
    if (this.panning) {
      this.el.style.cursor = "grabbing"
    } else if (this.spaceHeld || this.mode === "browse") {
      this.el.style.cursor = "grab"
    } else {
      this.el.style.cursor = ""
    }
  },

  /**
   * Shared snap for walls and location polygons: wall + placement vertices,
   * then nearest point along wall/placement segments within SNAP_DISTANCE.
   * Callers skip this while Ctrl/Meta is held (see resolvePointer).
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
    this.drawDraftMeasures([[start, current]])
  },

  clearWallDraft() {
    this.draftWall = null
    const line = this.svg && this.svg.querySelector("[data-wall-draft]")
    if (line) line.remove()
    this.clearDraftMeasures()
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

    const segments = []
    if (current && points.length >= 1) {
      segments.push([points[points.length - 1], current])
      if (points.length >= 2) segments.push([current, points[0]])
    }
    this.drawDraftMeasures(segments)
  },

  /**
   * Length labels along draft segments (feet). Text follows each segment;
   * angle stays in (-90, 90] so labels are never upside-down.
   */
  drawDraftMeasures(segments) {
    if (!this.svg) return
    let layer = this.svg.querySelector("[data-draft-measures]")
    if (!layer) {
      layer = document.createElementNS("http://www.w3.org/2000/svg", "g")
      layer.setAttribute("data-draft-measures", "true")
      layer.setAttribute("class", "pointer-events-none")
      this.svg.appendChild(layer)
    }
    while (layer.firstChild) layer.removeChild(layer.firstChild)

    const scale = this.feetPerUnit || DEFAULT_FEET_PER_UNIT
    const viewSize = (this.camera && this.camera.size) || 1
    const fontSize = measurementFontSize(viewSize)
    const rect = this.svg.getBoundingClientRect()
    const cssPx = Math.min(rect.width, rect.height) || 1
    const edgeGap = worldFromScreenPx(viewSize, cssPx, MEASUREMENT_EDGE_GAP_PX)
    for (const pair of segments || []) {
      if (!pair || pair.length < 2) continue
      const [a, b] = pair
      if (!a || !b) continue
      if (Math.hypot(b.x - a.x, b.y - a.y) < 1e-6) continue
      const pose = measurementLabelPose(a, b, fontSize, edgeGap)
      if (!pose) continue
      const label = document.createElementNS("http://www.w3.org/2000/svg", "text")
      label.setAttribute("text-anchor", pose.anchor || "middle")
      label.setAttribute("dominant-baseline", "central")
      label.setAttribute("font-size", String(fontSize))
      label.setAttribute("class", "fill-primary font-sans")
      label.setAttribute(
        "transform",
        `translate(${pose.x} ${pose.y}) rotate(${pose.angleDeg})`,
      )
      label.textContent = formatFeet(lengthInFeet(a, b, scale))
      layer.appendChild(label)
    }
  },

  clearDraftMeasures() {
    const layer = this.svg && this.svg.querySelector("[data-draft-measures]")
    if (layer) layer.remove()
  },

  clearPolygonDraft() {
    this.draftPolygon = null
    if (!this.svg) return
    const poly = this.svg.querySelector("[data-polygon-draft]")
    if (poly) poly.remove()
    const verts = this.svg.querySelector("[data-polygon-draft-vertices]")
    if (verts) verts.remove()
    this.clearDraftMeasures()
  },
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
