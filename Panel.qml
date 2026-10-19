import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Display Control — a bar widget for the Omarchy shell.
//
// The panel is a display list plus per-display settings in the Windows 11
// grouping: resolution, refresh rate, orientation, position, scale, brightness,
// text size, on/off, and a hyprsunset night mode.
//
// Nothing about the monitor set is hardcoded — every display, mode, rate and
// geometry comes from `hyprctl monitors all -j`, so the plugin works on any
// machine.
Panel {
  id: root
  moduleName: "io.github.arseniyasriyan.display"
  ipcTarget: "io.github.arseniyasriyan.display"
  manageIpc: false

  // ---- monitors -------------------------------------------------------------

  property var displays: []
  property int enabledDisplayCount: 0
  // Hyprland's focused output. There is no user-chosen "primary" — matching the
  // built-in Display panel, which only reports which monitor has focus. Used to
  // place the confirmation dialog and as the mirror target.
  property string focusedName: ""

  // The display the settings sections act on. Selecting a tile on the map (or
  // a row in the list) sets this.
  property string targetName: ""

  readonly property var targetDisplay: {
    for (var i = 0; i < displays.length; i++)
      if (displays[i] && displays[i].name === root.targetName) return displays[i]
    return null
  }
  readonly property bool targetEnabled: targetDisplay !== null && targetDisplay.enabled
  readonly property var targetResolutions: targetDisplay ? targetDisplay.resolutions : []
  readonly property int targetResolutionIndex: {
    if (!targetDisplay) return -1
    for (var i = 0; i < targetResolutions.length; i++) {
      if (targetResolutions[i].width === targetDisplay.width
          && targetResolutions[i].height === targetDisplay.height) return i
    }
    return -1
  }
  readonly property var targetRates: targetResolutionIndex >= 0
    ? targetResolutions[targetResolutionIndex].rates : []
  readonly property int targetRateIndex: targetDisplay
    ? Model.closestRateIndex(targetRates, targetDisplay.refreshRate) : -1

  // ---- per-display settings --------------------------------------------------

  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false

  readonly property var textSizeStops: Model.textSizeStops()
  property int textSizePreviewIndex: -1

  // ---- night mode -------------------------------------------------------------

  property bool nightEnabled: false
  property int nightTemperature: 4000

  // ---- scale -------------------------------------------------------------------

  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: targetDisplay
    ? Model.availableScales(scalePresets, targetDisplay.width, targetDisplay.height)
    : scalePresets

  // ---- layout state on the map --------------------------------------------------

  // Committed positions, keyed by output name. Seeded from hyprctl and updated
  // when the user swaps two displays.
  property var layoutPositions: ({})
  property bool applyingLayout: false
  property var actionQueue: []
  property real wheelAccumulator: 0

  // Displays in the map's left-to-right order: this is the numbering the tiles
  // show (1, 2, 3 ...).
  readonly property var orderedDisplays: Model.orderOf(displays)

  // 1-based number of a display in the left-to-right order, matching the badge
  // on its map tile. Returns 0 when the name is unknown.
  function displayNumber(name) {
    var list = orderedDisplays
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return i + 1
    return 0
  }

  // ---- map geometry ---------------------------------------------------------------

  // Bounding box of the committed layout; the map component scales it to fit.
  readonly property var mapBounds: Model.bounds(displays)

  property string errorMessage: ""
  property bool reflowingText: false
  function markReflowing() { root.reflowingText = true; reflowSettle.restart() }

  // ---- state plumbing ---------------------------------------------------------------

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!nightStateProc.running) nightStateProc.running = true
  }

  function updateFromMonitors(raw) {
    var parsed = Model.parseMonitors(raw, root.focusedName)

    // Assign focusedName first: choosing which display displays[] implies a
    // synchronous onDisplaysChanged, and that handler must see the new primary
    // rather than the previous refresh's value.
    root.focusedName = parsed.primaryName

    // Seed the committed layout from live geometry, so the map tracks any
    // external change (another tool, a reload) without us holding stale state.
    if (!root.applyingLayout) {
      var next = {}
      for (var i = 0; i < parsed.displays.length; i++) {
        var d = parsed.displays[i]
        next[d.name] = { x: d.x, y: d.y }
      }
      root.layoutPositions = next
    }

    // Resolve the selection before publishing displays, for the same reason.
    if (root.targetName === "" || !displayNamed(parsed.displays, root.targetName)) {
      root.targetName = parsed.primaryName !== "" ? parsed.primaryName
        : (parsed.displays.length > 0 ? parsed.displays[0].name : "")
    }

    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  function displayNamed(list, name) {
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].name === name) return list[i]
    return null
  }

  // Hyprland reports `mirrorOf` as the source monitor's id (e.g. "1"), not its
  // name. Resolve it to a name for anything written into monitors.lua, so the
  // saved rule stays readable and survives a monitor renumbering.
  function mirrorName(display) {
    if (!display || !display.mirrorOf || display.mirrorOf === "" || display.mirrorOf === "none")
      return ""
    var src = display.mirrorOf
    for (var i = 0; i < root.displays.length; i++) {
      var d = root.displays[i]
      if (d.name === src) return d.name
      if (String(d.id) === String(src)) return d.name
    }
    return ""   // unknown id: drop it rather than write an unusable rule
  }

  function selectFocused() {
    var name = root.focusedName
    if (name === "" && root.displays.length > 0) name = root.displays[0].name
    root.targetName = name
  }

  function selectByName(name) {
    if (name && name !== root.targetName) root.targetName = name
  }

  // ---- actions ------------------------------------------------------------------------

  // Build one `hl.monitor({...})` Lua call for a display, or "" when no field
  // survives validation. Values are interpolated only after validation.
  function monitorCall(display, fields) {
    if (!display || !Model.isSafeName(display.name)) return ""
    var parts = ["output = \"" + display.name + "\""]
    if (fields.disabled !== undefined) parts.push("disabled = " + (fields.disabled ? "true" : "false"))
    if (fields.mode !== undefined) {
      if (fields.mode === "preferred" || Model.isSafeMode(fields.mode)) parts.push("mode = \"" + fields.mode + "\"")
    }
    if (fields.position !== undefined && Model.isSafePosition(fields.position))
      parts.push("position = \"" + fields.position + "\"")
    if (fields.scale !== undefined && Model.isSafeScale(fields.scale))
      parts.push("scale = " + Number(fields.scale))
    if (fields.transform !== undefined) parts.push("transform = " + (parseInt(fields.transform, 10) || 0))
    if (fields.mirror !== undefined)
      parts.push("mirror = \"" + (Model.isSafeName(fields.mirror) ? fields.mirror : "") + "\"")
    return "hl.monitor({ " + parts.join(", ") + " })"
  }

  // Apply one display's change.
  function applyMonitor(display, fields) {
    var call = monitorCall(display, fields)
    if (call !== "") runAction(["hyprctl", "eval", call])
  }

  // Apply several displays in ONE eval. This matters for layout changes: when
  // positions are sent one at a time, Hyprland shifts an output that would
  // overlap a neighbour, and the layout comes out wrong. A single call makes
  // the whole arrangement land at once.
  function applyMonitorBatch(entries) {
    var calls = []
    for (var i = 0; i < entries.length; i++) {
      var c = monitorCall(entries[i].display, entries[i].fields)
      if (c !== "") calls.push(c)
    }
    if (calls.length === 0) return
    runAction(["hyprctl", "eval", calls.join("; ")])
  }

  function runAction(argv) {
    if (actionProc.running) { root.actionQueue.push(argv); return }
    actionProc.command = argv
    actionProc.running = true
  }

  // ---- change confirmation (Windows 11 "Keep changes") --------------------------------
  //
  // Every risky change first captures the live monitor state, applies the new
  // value, then starts a 15-second countdown. Nothing is written to disk until
  // the user keeps the change; a revert (button, Escape, or timeout) restores
  // the captured state, so a bad mode can never leave the screen unusable.

  property bool confirmPending: false
  property int confirmSeconds: 15
  property string confirmSummary: ""
  property var confirmSnapshot: ({})
  property bool applyingSnapshot: false

  function captureSnapshot() {
    var snap = {}
    for (var i = 0; i < root.displays.length; i++) {
      var d = root.displays[i]
      snap[d.name] = {
        name: d.name,
        disabled: !d.enabled,
        width: d.width,
        height: d.height,
        refreshRate: d.refreshRate,
        x: d.x,
        y: d.y,
        scale: d.scale,
        transform: d.transform,
        mirrorOf: d.mirrorOf,
        mirrorName: root.mirrorName(d)
      }
    }
    return snap
  }

  function beginChange(summary) {
    // Only the first change of a pending batch owns the snapshot: a second
    // quick tweak should still be able to revert to the pre-change state.
    if (!root.confirmPending) {
      root.confirmSnapshot = root.captureSnapshot()
      root.confirmPending = true
    }
    root.confirmSummary = summary
    root.confirmSeconds = 15
    confirmTimer.restart()
  }

  function keepChanges() {
    confirmTimer.stop()
    root.confirmPending = false
    // Persist so the choice survives a reload or reboot.
    root.saveLayout()
  }

  function revertChanges() {
    confirmTimer.stop()
    if (!root.confirmPending) return
    root.confirmPending = false
    var snap = root.confirmSnapshot
    root.applyingSnapshot = true
    var batch = []
    for (var name in snap) {
      if (!Object.prototype.hasOwnProperty.call(snap, name)) continue
      if (!Model.isSafeName(name)) continue
      var s = snap[name]
      var mode = (s.width > 0 && s.height > 0)
        ? s.width + "x" + s.height + "@" + (Math.round(s.refreshRate * 100) / 100)
        : "preferred"
      var fields = {
        disabled: s.disabled,
        position: s.x + "x" + s.y,
        transform: s.transform
      }
      if (!s.disabled) {
        fields.mode = mode
        fields.scale = s.scale
        if (s.mirrorName && s.mirrorName !== "") fields.mirror = s.mirrorName
      }
      batch.push({ display: { name: name }, fields: fields })
    }
    // Restore the whole snapshot in one eval, so outputs never overlap while
    // the revert is being applied.
    applyMonitorBatch(batch)

    snapshotSettle.restart()
  }

  // ---- persistence --------------------------------------------------------------------------

  // The plugin folder's save script, resolved to a real filesystem path.
  readonly property string saveScript: decodeURIComponent(
    Qt.resolvedUrl("save-layout.sh").toString().replace(/^file:\/\//, ""))

  property bool savingLayout: false

  // Write the current monitor state into the managed block of monitors.lua so
  // the layout survives a reload or reboot.
  function saveLayout() {
    if (savingLayout) return
    var list = []
    for (var i = 0; i < root.displays.length; i++) {
      var d = root.displays[i]
      if (!Model.isSafeName(d.name)) continue
      var pos = root.layoutPositions[d.name]
      var x = pos !== undefined && pos !== null ? pos.x : d.x
      var y = pos !== undefined && pos !== null ? pos.y : d.y
      var mode = d.enabled && d.width > 0 && d.height > 0
        ? d.width + "x" + d.height + "@" + (Math.round(d.refreshRate * 100) / 100)
        : "preferred"
      list.push({
        output: d.name,
        mode: mode,
        position: (x + "x" + y),
        scale: Number(d.scale) || 1,
        transform: Number(d.transform) || 0,
        mirror: root.mirrorName(d),
        disabled: !d.enabled
      })
    }
    saveProc.command = ["bash", root.saveScript, JSON.stringify(list)]
    if (!saveProc.running) { savingLayout = true; saveProc.running = true }
  }

  function applyResolutionAndRate(resolutionIndex, rateIndex) {
    var d = root.targetDisplay
    if (!d || resolutionIndex < 0 || resolutionIndex >= d.resolutions.length) return
    var res = d.resolutions[resolutionIndex]
    var rate = (rateIndex >= 0 && rateIndex < res.rates.length)
      ? res.rates[rateIndex] : Model.pickRate(res.rates, d.refreshRate)
    if (!rate) return
    beginChange("Resolution " + res.width + "\u00d7" + res.height + " @ " + rate.label + " Hz on " + d.name)
    applyMonitor(d, { disabled: false, mode: rate.mode, position: "auto", scale: d.scale })
  }

  function applyRate(rateIndex) {
    var d = root.targetDisplay
    if (!d || rateIndex < 0 || rateIndex >= root.targetRates.length) return
    var rate = root.targetRates[rateIndex]
    beginChange("Refresh rate " + rate.label + " Hz on " + d.name)
    applyMonitor(d, { disabled: false, mode: rate.mode, position: "auto", scale: d.scale })
  }

  function applyOrientation(orientationId) {
    var d = root.targetDisplay
    if (!d) return
    var all = Model.orientations()
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === orientationId) {
        beginChange("Orientation " + all[i].label + " on " + d.name)
        applyMonitor(d, { disabled: false, mode: "preferred", position: "auto", transform: all[i].transform })
        return
      }
    }
  }

  function applyScale(scale) {
    var d = root.targetDisplay
    if (!d) return
    beginChange("Scale " + scale + "x on " + d.name)
    applyMonitor(d, { disabled: false, mode: "preferred", position: "auto", scale: scale })
  }

  // Move the selected display one step in space (left/right = swap with the
  // neighbouring monitor horizontally, up/down = step in y). Applies the new
  // layout atomically and asks for confirmation.
  function moveTargetDisplay(direction) {
    var d = root.targetDisplay
    if (!d || !Model.isSafeName(d.name)) return
    var layout = Model.moveDisplay(root.displays, d.name, direction)
    if (!layout) return

    var labels = { left: "Move left", right: "Move right", up: "Move up", down: "Move down" }
    beginChange((labels[direction] || "Move") + ": " + d.name)

    var batch = []
    var names = Object.keys(layout)
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      if (!Model.isSafeName(name)) continue
      var disp = null
      for (var j = 0; j < root.displays.length; j++)
        if (root.displays[j].name === name) disp = root.displays[j]
      if (!disp || !disp.enabled) continue
      var pos = layout[name]
      batch.push({ display: disp, fields: { disabled: false, mode: "preferred", position: pos.x + "x" + pos.y } })
    }
    applyMonitorBatch(batch)
    root.layoutPositions = layout
    root.applyingLayout = true
    layoutSettle.restart()
  }

  function toggleDisplay(display) {
    if (!display || !Model.isSafeName(display.name)) return
    if (display.enabled && root.enabledDisplayCount <= 1) return

    beginChange((display.enabled ? "Turn off " : "Turn on ") + display.name)

    if (!display.enabled) {
      // Re-entering: find a free spot beside the existing layout.
      var others = []
      for (var i = 0; i < root.displays.length; i++)
        if (root.displays[i].name !== display.name && root.displays[i].enabled) others.push(root.displays[i])
      var b = Model.bounds(others)
      var spot = Model.nearestFreePosition(display, others, b.x + b.width, b.y)
      applyMonitor(display, { disabled: false, mode: "preferred", position: spot.x + "x" + spot.y, mirror: "" })
    } else {
      // Turning off: first re-lay the remaining enabled displays from 0x0 and
      // clear any mirror pointing at the output about to go dark, THEN disable
      // it. Order matters — if we disable a mirror source while a mirror still
      // points at it, Hyprland is left with a dangling mirror while it unmaps
      // the output's layer surfaces, which crashes the compositor
      // (CInputManager::refocusLastWindow -> ILuaConfigValue::asString, seen on
      // Hyprland 0.56.2). Dropping the mirror first keeps the survivor
      // standalone before its source disappears.
      var remaining = []
      for (var j = 0; j < root.displays.length; j++) {
        var o = root.displays[j]
        if (o.name !== display.name && o.enabled) remaining.push(o)
      }
      var laid = Model.tileLayout(remaining.map(function(d) {
        return { name: d.name, width: d.width, height: d.height }
      }))
      var posByName = {}
      for (var k = 0; k < laid.length; k++) posByName[laid[k].name] = laid[k]
      var offBatch = []
      for (var m = 0; m < remaining.length; m++) {
        var r = remaining[m]
        var p = posByName[r.name]
        offBatch.push({
          display: r,
          fields: {
            disabled: false,
            mode: "preferred",
            position: p ? (p.x + "x" + p.y) : "auto",
            mirror: ""
          }
        })
      }
      offBatch.push({ display: display, fields: { disabled: true } })
      applyMonitorBatch(offBatch)
    }
  }

  // ---- brightness -----------------------------------------------------------------------

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent
    if (setBrightnessProc.running) { root.brightnessSetQueued = true; return }
    root.brightnessSetQueued = false
    var monitorName = root.targetDisplay ? root.targetDisplay.name : ""
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", monitorName, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function adjustBrightness(delta) { setBrightness(root.brightnessPercent + delta) }

  function brightnessName(percent) { return Model.brightnessName(percent) }

  // ---- text size --------------------------------------------------------------------------

  function displayedTextPx() {
    return root.textSizePreviewIndex >= 0 ? root.textSizeStops[root.textSizePreviewIndex] : Style.font.baseSize
  }

  function currentTextIndex() {
    return root.textSizePreviewIndex >= 0 ? root.textSizePreviewIndex : Model.nearestTextStopIndex(Style.font.baseSize)
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = root.currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > root.textSizeStops.length - 1) idx = root.textSizeStops.length - 1
    markReflowing()
    root.textSizePreviewIndex = idx
    setTextSize(root.textSizeStops[idx])
  }

  // ---- night mode ---------------------------------------------------------------------------

  // On/off goes through Omarchy's own toggle: it starts hyprsunset when
  // missing, retries until the temperature sticks (a freshly-started hyprsunset
  // overrides an early set during its boot), and refreshes the shell UI. When
  // the user has picked a custom warmth we apply it right after, once
  // hyprsunset is definitely up.
  function setNightEnabled(on) {
    root.nightEnabled = on
    var script = on
      ? "omarchy-toggle-nightlight >/dev/null 2>&1; sleep 0.4; hyprctl hyprsunset temperature " + root.nightTemperature + " >/dev/null 2>&1"
      : "omarchy-toggle-nightlight >/dev/null 2>&1"
    nightProc.command = ["bash", "-c", script]
    if (!nightProc.running) nightProc.running = true
  }

  // The slider only moves the temperature of an already-running hyprsunset.
  function setNightTemperature(temp) {
    root.nightTemperature = Model.clampTemperature(temp)
    if (!root.nightEnabled) return
    runAction(["hyprctl", "hyprsunset", "temperature", String(root.nightTemperature)])
  }

  // ---- IPC ------------------------------------------------------------------------------------

  function stateIpc() {
    return JSON.stringify({
      displays: root.displays,
      focused: root.focusedName,
      target: root.targetName,
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      night: { enabled: root.nightEnabled, temperature: root.nightTemperature },
      confirm: root.confirmPending ? { seconds: root.confirmSeconds, summary: root.confirmSummary } : null
    })
  }

  IpcHandler {
    target: "io.github.arseniyasriyan.display"

    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
    function keep(): string { root.keepChanges(); return "ok" }
    function revert(): string { root.revertChanges(); return "ok" }
  }

  // ---- lifecycle ---------------------------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    root.refresh()
    brightnessStateProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      root.refresh()
      brightnessStateProc.running = true
      nightStateProc.running = true
    }
  }

  onDisplaysChanged: if (root.targetName === "" || !root.targetDisplay) root.selectFocused()
  // Brightness is per-display, so re-read it when the selection changes.
  onTargetNameChanged: brightnessStateProc.running = true

  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
  }

  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  Timer {
    id: layoutSettle
    interval: 700
    repeat: false
    onTriggered: {
      root.applyingLayout = false
      root.refresh()
    }
  }

  // 15-second countdown behind the "Keep changes?" banner, exactly like the
  // Windows 11 display-settings dialog. Running out reverts.
  Timer {
    id: confirmTimer
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      root.confirmSeconds = root.confirmSeconds - 1
      if (root.confirmSeconds <= 0) root.revertChanges()
    }
  }

  // Give Hyprland a moment to settle after a revert before re-reading state.
  Timer {
    id: snapshotSettle
    interval: 800
    repeat: false
    onTriggered: {
      root.applyingSnapshot = false
      root.refresh()
    }
  }

  Process {
    id: stateProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateFromMonitors(String(text || ""))
    }
  }

  Process {
    id: nightStateProc
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.nightEnabled = parsed.enabled === true
          if (parsed.temperature !== null && parsed.temperature !== undefined) {
            var temp = Number(parsed.temperature)
            // Identity (>=6000) means "off"; keep the last chosen night value.
            if (Model.isNightEnabled(temp)) root.nightTemperature = temp
          }
        } catch (e) {
          root.nightEnabled = false
        }
      }
    }
  }

  Process {
    id: nightProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Trust the local toggle, then reconcile with hyprsunset's own report.
        nightStateProc.running = false
        nightStateProc.running = true
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out !== "" && out !== "ok") root.errorMessage = out
      }
    }
    onRunningChanged: {
      if (running) return
      if (root.actionQueue.length > 0) {
        actionProc.command = root.actionQueue.shift()
        actionProc.running = true
        return
      }
      root.refresh()
    }
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Deliberately no refresh() here: the locally written value is authoritative
    // and re-reading immediately races the driver.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) root.setBrightness(root.pendingBrightnessPercent)
    }
  }

  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Writes the managed block in monitors.lua once a change is kept.
  Process {
    id: saveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "") root.errorMessage = err
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) { root.savingLayout = false; root.refresh() }
  }

  Process {
    id: brightnessStateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        if (root.brightnessAvailable && !setBrightnessProc.running) {
          root.brightnessPercent = Math.max(0, Math.min(100, parseInt(brightness, 10)))
          root.pendingBrightnessPercent = root.brightnessPercent
        }
      }
    }
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && Model.nearestTextStopIndex(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  // ---- bar button ---------------------------------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.adjustBrightness(wheel.steps * 5)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    // Cap the panel so it always fits on screen; the inner ScrollView then
    // scrolls the remaining sections instead of running off the bottom edge.
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, maxPanelHeight)

    // Leave room for the bar and screen margins on the shortest display.
    readonly property int maxPanelHeight: {
      var list = Quickshell.screens || []
      var screenH = 0
      for (var i = 0; i < list.length; i++) {
        var h = list[i] && list[i].height ? list[i].height : 0
        if (h > 0 && (screenH === 0 || h < screenH)) screenH = h
      }
      if (screenH === 0) screenH = 1080
      return Math.max(Style.space(240), Math.round(screenH * 0.72))
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          // Bind to the panel's own content width rather than the ScrollView's
          // availableWidth: that width is itself derived from this column's
          // implicitHeight, and the cycle leaves implicitHeight at 0, so the
          // panel never learns how tall it needs to be.
          width: panel.contentWidth - panel.padding * 2
          spacing: Style.space(14)

          DisplayHero { width: parent.width; host: root }

          PanelSeparator { foreground: root.bar.foreground }

          SettingsSections { width: parent.width; host: root }

          NightSection { width: parent.width; host: root }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }

  // Confirmation prompt lives in its own centred window on the primary
  // display, not inside the bar panel.
  ConfirmationDialog {
    pending: root.confirmPending
    seconds: root.confirmSeconds
    summary: root.confirmSummary
    focusedOutput: root.focusedName
    onKeepRequested: root.keepChanges()
    onRevertRequested: root.revertChanges()
  }
}
