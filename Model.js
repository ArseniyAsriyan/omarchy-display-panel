// Pure helpers for the Display plugin.
//
// Everything here is data-in / data-out: no QML, no processes, no file
// system. That keeps the parsing and geometry logic testable in isolation
// (Model.test.js) and keeps Panel.qml focused on presentation.

// ---- numeric helpers -------------------------------------------------------

function clampNumber(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function clampBrightness(value) {
  return Math.round(clampNumber(value, 1, 100))
}

function roundTo(value, decimals) {
  var factor = Math.pow(10, decimals || 0)
  return Math.round(Number(value) * factor) / factor
}

// "60" for 60.00, "59.94" for 59.94: at most two decimals, no trailing zeros.
function trimHz(hz) {
  return String(roundTo(hz, 2))
}

// ---- validation guards -----------------------------------------------------
//
// Anything that reaches `hyprctl eval` is interpolated into Lua source, so it
// is validated against a strict allow-list first.

function isSafeName(name) {
  return /^[A-Za-z0-9._-]+$/.test(String(name || ""))
}

function isSafeMode(mode) {
  return /^[0-9]+x[0-9]+@[0-9]+(\.[0-9]+)?$/.test(String(mode || ""))
}

function isSafePosition(position) {
  // "auto", "auto-left", … or "WxH" with optional negative offsets.
  return /^(auto(-[a-z]+)?|-?[0-9]+x-?[0-9]+)$/.test(String(position || ""))
}

function isSafeScale(scale) {
  var n = Number(scale)
  return isFinite(n) && n > 0 && n <= 10
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function isInternalName(name) {
  return /^(eDP|LVDS|DSI)-/.test(String(name || ""))
}

// ---- scale helpers ---------------------------------------------------------
//
// Hyprland accepts a scale only when it divides the mode evenly, so a naive
// preset list has to be filtered against the monitor's real resolution.

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue
    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) { bestIndex = i; bestDistance = distance }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))
    if (!isFinite(requested) || !isFinite(effective)) continue
    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = { value: String(scales[i]), index: i, distance: Math.abs(requested - effective) }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

// ---- display modes (resolution / refresh rate) ------------------------------

// Group hyprctl's availableModes ("2560x1440@143.99Hz") by resolution.
// Resolutions come largest first, rates highest first. Each rate keeps the
// exact mode string Hyprland listed, and gets a short label: whole Hz, or two
// decimals only when several rates would otherwise round to the same number
// (59.94 / 60.00, 119.88 / 120.00).
function parseModes(modes) {
  var byRes = {}
  var order = []
  if (!Array.isArray(modes)) return []

  for (var i = 0; i < modes.length; i++) {
    var m = /^([0-9]+)x([0-9]+)@([0-9]+(?:\.[0-9]+)?)Hz$/.exec(String(modes[i]))
    if (!m) continue
    var key = m[1] + "x" + m[2]
    var hz = parseFloat(m[3])
    if (!byRes[key]) {
      byRes[key] = { key: key, width: parseInt(m[1], 10), height: parseInt(m[2], 10), rates: [] }
      order.push(key)
    }
    var seen = false
    for (var r = 0; r < byRes[key].rates.length; r++) {
      if (trimHz(byRes[key].rates[r].hz) === trimHz(hz)) { seen = true; break }
    }
    if (!seen) byRes[key].rates.push({ hz: hz, mode: key + "@" + m[3] })
  }

  var resolutions = order.map(function(k) { return byRes[k] })
  resolutions.sort(function(a, b) {
    return (b.width * b.height - a.width * a.height) || (b.width - a.width)
  })

  resolutions.forEach(function(res) {
    res.rates.sort(function(a, b) { return b.hz - a.hz })
    var rounded = {}
    res.rates.forEach(function(rate) {
      var k = String(Math.round(rate.hz))
      rounded[k] = (rounded[k] || 0) + 1
    })
    res.rates.forEach(function(rate) {
      rate.label = rounded[String(Math.round(rate.hz))] > 1 ? trimHz(rate.hz) : String(Math.round(rate.hz))
    })
  })

  return resolutions
}

// The refresh rate to use after switching resolution: keep the current one when
// the new resolution offers it, otherwise take the highest available.
function pickRate(rates, currentHz) {
  if (!Array.isArray(rates) || rates.length === 0) return null
  for (var i = 0; i < rates.length; i++) {
    if (Math.abs(rates[i].hz - Number(currentHz)) < 0.5) return rates[i]
  }
  return rates[0]
}

function findResolution(resolutions, width, height) {
  if (!Array.isArray(resolutions)) return null
  for (var i = 0; i < resolutions.length; i++) {
    if (resolutions[i].width === Number(width) && resolutions[i].height === Number(height)) {
      return resolutions[i]
    }
  }
  return null
}

function closestRateIndex(rates, currentHz) {
  var best = -1
  var bestDistance = Infinity
  if (!Array.isArray(rates)) return -1
  for (var i = 0; i < rates.length; i++) {
    var distance = Math.abs(rates[i].hz - Number(currentHz))
    if (distance < bestDistance) { best = i; bestDistance = distance }
  }
  return best
}

// ---- orientation / arrangement ----------------------------------------------
//
// Four Windows-11-style arrangement choices, mapped onto Hyprland primitives:
//   landscape -> normal transform
//   portrait  -> 90 degree transform
//   mirror    -> this display mirrors the primary one
//   extend    -> normal, positioned on the map (the default desktop behaviour)
//   single    -> only this display is on

var ORIENTATIONS = [
  { id: "landscape", label: "Landscape", glyph: "\uF0377", transform: 0 },
  { id: "portrait", label: "Portrait", glyph: "\uF0378", transform: 1 },
  { id: "landscape-flipped", label: "Landscape (flipped)", glyph: "\uF0379", transform: 2 },
  { id: "portrait-flipped", label: "Portrait (flipped)", glyph: "\uF037A", transform: 3 }
]

function orientations() { return ORIENTATIONS }

function orientationForTransform(transform) {
  var t = Number(transform) || 0
  for (var i = 0; i < ORIENTATIONS.length; i++) {
    if (ORIENTATIONS[i].transform === t) return ORIENTATIONS[i]
  }
  return ORIENTATIONS[0]
}

function orientationIndex(transform) {
  var t = Number(transform) || 0
  for (var i = 0; i < ORIENTATIONS.length; i++) {
    if (ORIENTATIONS[i].transform === t) return i
  }
  return 0
}

// A display's width/height as Hyprland reports them already swap under a 90/270
// transform, so the physical footprint for the map is the reported size.
function isRotated(transform) {
  var t = Number(transform) || 0
  return t === 1 || t === 3
}

// ---- monitor state ----------------------------------------------------------

// `hyprctl monitors all -j` -> the rows the panel works with.
function parseMonitors(raw, primaryName) {
  var list = []
  try {
    list = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    list = []
  }
  if (!Array.isArray(list)) list = []

  // Overlap-based approach to building logical display groups: Hyprland
  // reports a "widest" list where a mirrored output shares its target's
  // geometry. We keep the raw list and let the panel decide.
  var displays = []
  var enabledCount = 0
  var primary = String(primaryName || "")

  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m || typeof m.name !== "string") continue
    var enabled = m.disabled !== true
    if (enabled) enabledCount++
    var transform = Number(m.transform) || 0
    displays.push({
      name: m.name,
      id: Number(m.id),
      description: String(m.description || m.model || ""),
      enabled: enabled,
      focused: m.focused === true,
      internal: isInternalName(m.name),
      width: Number(m.width) || 0,
      height: Number(m.height) || 0,
      physicalWidth: Number(m.physicalWidth) || 0,
      physicalHeight: Number(m.physicalHeight) || 0,
      x: Number(m.x) || 0,
      y: Number(m.y) || 0,
      transform: transform,
      rotated: isRotated(transform),
      refreshRate: Number(m.refreshRate) || 0,
      scale: Number(m.scale) || 1,
      mirrorOf: String(m.mirrorOf || ""),
      availableModes: Array.isArray(m.availableModes) ? m.availableModes.slice() : [],
      resolutions: parseModes(m.availableModes)
    })
  }

  // Pick the map's primary display: an explicit primary wins, else the one
  // Hyprland marks focused, else the first enabled display, else the first.
  var primaryIndex = -1
  for (var p = 0; p < displays.length; p++) {
    if (displays[p].name === primary && displays[p].enabled) { primaryIndex = p; break }
  }
  if (primaryIndex < 0) {
    for (var f = 0; f < displays.length; f++) {
      if (displays[f].focused && displays[f].enabled) { primaryIndex = f; break }
    }
  }
  if (primaryIndex < 0) {
    for (var e = 0; e < displays.length; e++) {
      if (displays[e].enabled) { primaryIndex = e; break }
    }
  }
  if (primaryIndex < 0 && displays.length > 0) primaryIndex = 0

  return {
    displays: displays,
    enabledDisplayCount: enabledCount,
    primaryIndex: primaryIndex,
    primaryName: primaryIndex >= 0 ? displays[primaryIndex].name : ""
  }
}

// Logical size of a display on the map. Hyprland swaps width/height for
// rotated outputs already, but be defensive when only transform is known.
function logicalSize(display) {
  if (!display) return { width: 0, height: 0 }
  return { width: Number(display.width) || 0, height: Number(display.height) || 0 }
}

// Total bounding box of all enabled displays in Hyprland logical coordinates.
function bounds(displays) {
  var list = (displays || []).filter(function(d) { return d && d.enabled })
  if (list.length === 0) return { x: 0, y: 0, width: 0, height: 0 }

  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var i = 0; i < list.length; i++) {
    var size = logicalSize(list[i])
    minX = Math.min(minX, list[i].x)
    minY = Math.min(minY, list[i].y)
    maxX = Math.max(maxX, list[i].x + size.width)
    maxY = Math.max(maxY, list[i].y + size.height)
  }
  return { x: minX, y: minY, width: Math.max(0, maxX - minX), height: Math.max(0, maxY - minY) }
}

// Snap a proposed top-left position so the dragged display's edges align with
// its neighbours' edges, then normalise the whole layout so its bounding box
// starts at 0x0. Snapping makes the map feel like Windows' display settings;
// normalising keeps Hyprland positions small and predictable.
function snapPosition(moving, others, proposedX, proposedY, threshold) {
  var size = logicalSize(moving)
  var tol = Number(threshold) || 40
  var bestX = Math.round(proposedX)
  var bestY = Math.round(proposedY)
  var xFound = false
  var yFound = false
  var bestXDist = tol
  var bestYDist = tol

  for (var i = 0; i < (others || []).length; i++) {
    var o = others[i]
    if (!o || !o.enabled) continue
    var oSize = logicalSize(o)

    // Candidate x alignments: left-left, left-right, right-left, right-right.
    var xCandidates = [o.x, o.x + oSize.width, o.x - size.width, o.x + oSize.width - size.width]
    for (var xi = 0; xi < xCandidates.length; xi++) {
      var xd = Math.abs(xCandidates[xi] - proposedX)
      if (xd <= bestXDist) { bestXDist = xd; bestX = xCandidates[xi]; xFound = true }
    }

    // Candidate y alignments: top-top, top-bottom, bottom-top, bottom-bottom.
    var yCandidates = [o.y, o.y + oSize.height, o.y - size.height, o.y + oSize.height - size.height]
    for (var yi = 0; yi < yCandidates.length; yi++) {
      var yd = Math.abs(yCandidates[yi] - proposedY)
      if (yd <= bestYDist) { bestYDist = yd; bestY = yCandidates[yi]; yFound = true }
    }
  }

  return {
    x: xFound ? bestX : Math.round(proposedX),
    y: yFound ? bestY : Math.round(proposedY),
    snappedX: xFound,
    snappedY: yFound
  }
}

// Shift every display so the layout's top-left corner is at 0x0.
function normalizePositions(displays) {
  var b = bounds(displays)
  if (b.width === 0 && b.height === 0) return displays
  if (b.x === 0 && b.y === 0) return displays

  var out = []
  for (var i = 0; i < displays.length; i++) {
    var d = displays[i]
    if (!d) continue
    var copy = {}
    for (var key in d) if (Object.prototype.hasOwnProperty.call(d, key)) copy[key] = d[key]
    if (d.enabled) { copy.x = d.x - b.x; copy.y = d.y - b.y }
    out.push(copy)
  }
  return out
}

// Do two rectangles overlap? Used to refuse drop positions that would stack
// displays on top of each other (mirroring is handled separately).
function rectsOverlap(aX, aY, aW, aH, bX, bY, bW, bH) {
  return aX < bX + bW && aX + aW > bX && aY < bY + bH && aY + aH > bY
}

// Is the proposed position free of enabled neighbours (ignoring the display
// being moved)?
function positionIsFree(moving, others, proposedX, proposedY) {
  var size = logicalSize(moving)
  for (var i = 0; i < (others || []).length; i++) {
    var o = others[i]
    if (!o || !o.enabled || o.name === moving.name) continue
    var oSize = logicalSize(o)
    if (rectsOverlap(proposedX, proposedY, size.width, size.height, o.x, o.y, oSize.width, oSize.height)) {
      return false
    }
  }
  return true
}

// Find the nearest free grid position for a display, so a drag can never
// produce an overlapping layout. Tries the snapped target first, then rings
// outwards on a coarse step.
function nearestFreePosition(moving, others, proposedX, proposedY) {
  if (positionIsFree(moving, others, proposedX, proposedY)) {
    return { x: Math.round(proposedX), y: Math.round(proposedY) }
  }

  var size = logicalSize(moving)
  var stepX = Math.max(40, size.width)
  var stepY = Math.max(40, size.height)

  for (var ring = 1; ring <= 12; ring++) {
    for (var dx = -ring; dx <= ring; dx++) {
      for (var dy = -ring; dy <= ring; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== ring) continue
        var x = Math.round(proposedX + dx * stepX)
        var y = Math.round(proposedY + dy * stepY)
        if (positionIsFree(moving, others, x, y)) return { x: x, y: y }
      }
    }
  }
  // Nothing free within range: keep the proposed spot rather than lose the drag.
  return { x: Math.round(proposedX), y: Math.round(proposedY) }
}

// Lay displays out left to right, top edges aligned, with no overlap. Used to
// rebuild a sensible arrangement ("Extend") from scratch, where
// Hyprland has no remembered geometry to fall back on. The first display is
// anchored at 0x0; every later one starts where the previous one ends.
function tileLayout(displays) {
  var out = []
  if (!Array.isArray(displays) || displays.length === 0) return out

  var x = 0
  for (var i = 0; i < displays.length; i++) {
    var d = displays[i]
    if (!d) continue
    var size = logicalSize(d)
    out.push({
      name: d.name,
      x: x,
      y: 0,
      width: size.width,
      height: size.height
    })
    x += size.width
  }
  return out
}

// ---- moving a display in space -------------------------------------------------

// Move a display one step in a direction, relative to its neighbours, and
// return a full name -> {x, y} layout for every enabled display laid out with
// no overlaps. Directions are "left"/"right" (swap horizontal neighbours) and
// "up"/"down" (step in y). Returns null when nothing can move.
function moveDisplay(displays, name, direction) {
  var order = orderOf(displays)
  if (order.length < 2) return null

  var idx = -1
  for (var i = 0; i < order.length; i++) if (order[i].name === name) idx = i
  if (idx < 0) return null

  if (direction === "left" || direction === "right") {
    var swapWith = direction === "left" ? idx - 1 : idx + 1
    if (swapWith < 0 || swapWith >= order.length) return null
    var tmp = order[idx]
    order[idx] = order[swapWith]
    order[swapWith] = tmp
    var laid = tileLayout(order.map(function(d) {
      var s = logicalSize(d)
      return { name: d.name, width: s.width, height: s.height }
    }))
    var map = {}
    for (var k = 0; k < laid.length; k++) map[laid[k].name] = { x: laid[k].x, y: laid[k].y }
    return map
  }

  if (direction === "up" || direction === "down") {
    // Step this display in y by a third of its height, keeping others put, then
    // normalise so the top-left of the whole set returns to 0,0.
    var target = order[idx]
    var size = logicalSize(target)
    var step = Math.max(40, Math.round(size.height / 3))
    var delta = direction === "up" ? -step : step

    var positions = {}
    for (var j = 0; j < order.length; j++) {
      var d = order[j]
      var s = logicalSize(d)
      positions[d.name] = { x: d.x, y: (d.name === name ? d.y + delta : d.y) }
    }
    return positions
  }

  return null
}

// ---- ordering / swapping ------------------------------------------------------

// The display list ordered left to right, which is what the map's numbering
// (1, 2, 3 ...) reflects. Ties are broken by name so the order is stable.
function orderOf(displays) {
  var list = (displays || []).filter(function(d) { return d && d.enabled})
  list.sort(function(a, b) {
    if (a.x !== b.x) return a.x - b.x
    if (a.y !== b.y) return a.y - b.y
    return String(a.name) < String(b.name) ? -1 : 1
  })
  return list
}

// ---- night mode --------------------------------------------------------------

var NIGHT_TEMPERATURES = [6500, 5500, 5000, 4500, 4000, 3500, 3000, 2500, 2000]
var IDENTITY_TEMPERATURE = 6000

function nightTemperatures() { return NIGHT_TEMPERATURES }

function clampTemperature(value) {
  return Math.round(clampNumber(value, 1000, 10000))
}

// hyprsunset reports identity when the temperature is at or above its
// identity point; the toggle mirrors omarchy-toggle-nightlight's threshold.
function isNightEnabled(temperature) {
  var temp = Number(temperature)
  if (!isFinite(temp) || temp <= 0) return false
  return temp < IDENTITY_TEMPERATURE
}

// ---- text size ---------------------------------------------------------------

var TEXT_SIZE_STOPS = [9, 10, 11, 12, 14, 16, 20]

function textSizeStops() { return TEXT_SIZE_STOPS }

function nearestTextStopIndex(px) {
  var best = 0
  var bestDist = Infinity
  for (var i = 0; i < TEXT_SIZE_STOPS.length; i++) {
    var d = Math.abs(TEXT_SIZE_STOPS[i] - Number(px))
    if (d < bestDist) { bestDist = d; best = i }
  }
  return best
}

if (typeof module !== "undefined") {
  module.exports = {
    clampNumber: clampNumber,
    clampBrightness: clampBrightness,
    roundTo: roundTo,
    trimHz: trimHz,
    isSafeName: isSafeName,
    isSafeMode: isSafeMode,
    isSafePosition: isSafePosition,
    isSafeScale: isSafeScale,
    normalizeScale: normalizeScale,
    isInternalName: isInternalName,
    gcd: gcd,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseModes: parseModes,
    pickRate: pickRate,
    findResolution: findResolution,
    closestRateIndex: closestRateIndex,
    orientations: orientations,
    orientationForTransform: orientationForTransform,
    orientationIndex: orientationIndex,
    isRotated: isRotated,
    parseMonitors: parseMonitors,
    logicalSize: logicalSize,
    bounds: bounds,
    snapPosition: snapPosition,
    normalizePositions: normalizePositions,
    rectsOverlap: rectsOverlap,
    positionIsFree: positionIsFree,
    nearestFreePosition: nearestFreePosition,
    tileLayout: tileLayout,
    orderOf: orderOf,
    moveDisplay: moveDisplay,
    nightTemperatures: nightTemperatures,
    clampTemperature: clampTemperature,
    isNightEnabled: isNightEnabled,
    textSizeStops: textSizeStops,
    nearestTextStopIndex: nearestTextStopIndex
  }
}
