import QtQuick
import Quickshell
import Quickshell.Io

// AOSP-style auto-brightness for the Surface Pro 11 internal panel.
//
// Lux comes from iio-sensor-proxy via als-lux.py. A base curve maps lux to
// brightness; whatever you set by hand becomes a personal offset on that
// curve (AOSP's short-term model), so the level you chose is kept and only
// moved when the room changes enough:
//   - lux is smoothed (fast and slow averages) and has to leave a band around
//     the lux of the last decision, and stay out for a debounce time
//     (brightening reacts sooner than darkening, as in AOSP);
//   - the new target has to differ from the current level by at least
//     `minDelta` points, otherwise nothing moves;
//   - changes ramp over ~1.5 s.
// Any brightness change that wasn't ours (keys, slider) re-anchors the curve.
Item {
  id: root

  property bool active: false
  property real offset: 0           // percentage points on top of the curve
  readonly property alias lux: st.slowLux
  readonly property bool sensorLive: st.live

  // Tunables.
  readonly property int minDelta: 6
  readonly property real brightenStops: 0.6   // log2 lux band above the anchor
  readonly property real darkenStops: 0.8     // log2 lux band below the anchor
  readonly property int brightenDebounceMs: 3000
  readonly property int darkenDebounceMs: 8000
  readonly property int manualHoldMs: 4000
  readonly property int rampMs: 1500
  // Base curve, lux -> percent, interpolated in log(lux + 1). This sensor is
  // insensitive: a TV-lit room reads 0, an overhead-lit room 1-20 lux.
  readonly property var curve: [[0, 22], [1, 30], [5, 40], [20, 52], [80, 66], [300, 80], [1000, 92], [3000, 100]]

  readonly property string backlight: "/sys/class/backlight/dp_aux_backlight"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/surface-pro-11-autobrightness.json"

  signal adjusted(int percent)

  function curveAt(l) {
    var x = Math.log(Math.max(0, l) + 1)
    var pts = curve
    if (x <= Math.log(pts[0][0] + 1)) return pts[0][1]
    for (var i = 1; i < pts.length; i++) {
      var x1 = Math.log(pts[i][0] + 1)
      if (x <= x1) {
        var x0 = Math.log(pts[i - 1][0] + 1)
        var t = (x - x0) / (x1 - x0)
        return pts[i - 1][1] + t * (pts[i][1] - pts[i - 1][1])
      }
    }
    return pts[pts.length - 1][1]
  }

  function targetFor(l) {
    return Math.max(1, Math.min(100, Math.round(curveAt(l) + offset)))
  }

  function stops(a, b) {
    return Math.log((a + 1) / (b + 1)) / Math.LN2
  }

  function setActive(on) {
    if (active === on) return
    active = on
    if (on && st.haveLux && st.maxRaw > 0) {
      // Start from where you are: today's level becomes the anchor.
      offset = clampOffset(st.curPct() - curveAt(st.slowLux))
      st.anchorLux = st.slowLux
      log("on at " + Math.round(st.curPct()) + "%, " + st.slowLux.toFixed(2) + " lux, offset " + offset.toFixed(1))
    }
    save()
  }

  function clampOffset(o) {
    return Math.max(-40, Math.min(40, o))
  }

  function log(msg) {
    console.log("surface-pro-11 autobrightness: " + msg)
  }

  function save() {
    saveProc.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\"", "sh",
                        statePath, JSON.stringify({ enabled: active, offset: Math.round(offset * 10) / 10 })]
    saveProc.running = true
  }

  function status() {
    return JSON.stringify({
      enabled: active,
      sensorLive: st.live,
      lux: Math.round(st.slowLux * 100) / 100,
      fastLux: Math.round(st.fastLux * 100) / 100,
      anchorLux: Math.round(st.anchorLux * 100) / 100,
      offset: Math.round(offset * 10) / 10,
      brightness: st.maxRaw > 0 ? Math.round(st.curPct()) : -1,
      target: st.haveLux ? targetFor(st.slowLux) : -1,
      ramping: rampTimer.running
    })
  }

  QtObject {
    id: st
    property bool haveLux: false
    property bool settled: false
    property bool live: false
    property real fastLux: 0
    property real slowLux: 0
    property real anchorLux: 0
    property real lastLux: 0
    property double lastLuxAt: 0
    property double lastTick: 0
    property double outOfBandSince: 0
    property int outOfBandDir: 0
    property double holdUntil: 0
    property int maxRaw: 0
    property int curRaw: -1
    property int lastSetRaw: -1
    property int manualCandidate: -1
    function curPct() { return maxRaw > 0 ? curRaw * 100 / maxRaw : 0 }
  }

  // als-lux.py prints the sensor's lux once a second while it holds a claim
  // on iio-sensor-proxy; the sensor is live while those lines keep coming.
  Process {
    id: alsProc
    command: ["python3", "-I", String(Qt.resolvedUrl("als-lux.py")).replace(/^file:\/\//, "")]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var l = parseFloat(line)
        if (isFinite(l)) { st.lastLux = l; st.lastLuxAt = Date.now() }
      }
    }
  }
  FileView { id: rawFile; blockLoading: true; path: root.backlight + "/actual_brightness"; printErrors: false }
  FileView {
    id: maxFile
    blockLoading: true
    path: root.backlight + "/max_brightness"
    printErrors: false
    onLoaded: st.maxRaw = parseInt(text(), 10) || 0
  }
  FileView {
    id: stFile
    path: root.statePath
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        root.active = !!s.enabled
        root.offset = root.clampOffset(Number(s.offset) || 0)
      } catch (e) {}
    }
  }

  Process { id: saveProc }
  Process { id: setProc }

  function writeRaw(raw) {
    if (setProc.running) return false
    st.lastSetRaw = raw
    setProc.command = ["brightnessctl", "-q", "-d", "dp_aux_backlight", "set", String(raw)]
    setProc.running = true
    return true
  }

  // Ramp in raw units, linear in time.
  Timer {
    id: rampTimer
    interval: 75
    repeat: true
    property int fromRaw: 0
    property int toRaw: 0
    property double startedAt: 0
    onTriggered: {
      // Done once the final value has been written and that write finished.
      if (st.lastSetRaw === toRaw && !setProc.running) {
        stop()
        st.holdUntil = Date.now() + 2000
        root.log("ramp done at " + toRaw)
        return
      }
      var t = Math.min(1, (Date.now() - startedAt) / root.rampMs)
      var raw = Math.round(fromRaw + (toRaw - fromRaw) * t)
      if (raw !== st.lastSetRaw) root.writeRaw(raw)
    }
  }

  function rampTo(percent) {
    var toRaw = Math.round(percent * st.maxRaw / 100)
    rampTimer.fromRaw = st.curRaw
    rampTimer.toRaw = toRaw
    rampTimer.startedAt = Date.now()
    st.lastSetRaw = st.curRaw
    rampTimer.start()
    root.log("lux " + st.slowLux.toFixed(2) + " -> " + percent + "% (from " + Math.round(st.curPct()) + "%)")
    root.adjusted(percent)
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  function tick() {
    var now = Date.now()
    if (st.maxRaw <= 0) { maxFile.reload(); return }

    rawFile.reload()
    var raw = parseInt(rawFile.text(), 10)
    if (isFinite(raw)) st.curRaw = raw

    if (!alsProc.running) alsProc.running = true
    var l = st.lastLux
    st.live = now - st.lastLuxAt < 3000
    if (st.live) {
      var dt = st.lastTick > 0 ? Math.min(5, (now - st.lastTick) / 1000) : 1
      if (!st.haveLux) {
        st.fastLux = l
        st.slowLux = l
        st.anchorLux = l
        st.haveLux = true
      } else {
        st.fastLux += (l - st.fastLux) * (1 - Math.exp(-dt / 2))
        st.slowLux += (l - st.slowLux) * (1 - Math.exp(-dt / 6))
      }
    }
    st.lastTick = now

    if (rampTimer.running || setProc.running) return

    // Someone else moved the backlight: that is the level you want here.
    // The read can lag our own last write by a tick, so ignore it while our
    // write settles and accept a new level only once two ticks agree.
    var tol = st.maxRaw / 100
    if (st.lastSetRaw >= 0 && Math.abs(st.curRaw - st.lastSetRaw) > tol) {
      if (now < st.holdUntil) return
      if (st.manualCandidate < 0 || Math.abs(st.curRaw - st.manualCandidate) > tol) {
        st.manualCandidate = st.curRaw
        return
      }
      st.manualCandidate = -1
      st.lastSetRaw = st.curRaw
      st.holdUntil = now + root.manualHoldMs
      if (root.active && st.haveLux) {
        root.offset = root.clampOffset(st.curPct() - root.curveAt(st.slowLux))
        root.log("manual " + Math.round(st.curPct()) + "% at " + st.slowLux.toFixed(2) + " lux, offset " + root.offset.toFixed(1))
        st.anchorLux = st.slowLux
        st.outOfBandSince = 0
        root.save()
      }
      return
    }
    st.manualCandidate = -1
    if (st.lastSetRaw < 0) st.lastSetRaw = st.curRaw

    if (!root.active || !st.live || now < st.holdUntil) return

    // First decision after start (login, shell restart): go to your curve.
    if (!st.settled) {
      st.settled = true
      st.anchorLux = st.slowLux
      var first = root.targetFor(st.slowLux)
      if (Math.abs(first - st.curPct()) >= root.minDelta) root.rampTo(first)
      return
    }

    var d = root.stops(st.fastLux, st.anchorLux)
    var dir = d > root.brightenStops ? 1 : (d < -root.darkenStops ? -1 : 0)
    if (dir === 0 || dir !== st.outOfBandDir) {
      st.outOfBandDir = dir
      st.outOfBandSince = dir === 0 ? 0 : now
      return
    }
    var wait = dir > 0 ? root.brightenDebounceMs : root.darkenDebounceMs
    if (now - st.outOfBandSince < wait) return

    // The room really changed. Decide from the slow average.
    st.anchorLux = st.slowLux
    st.outOfBandSince = 0
    st.outOfBandDir = 0
    var target = root.targetFor(st.slowLux)
    if (Math.abs(target - st.curPct()) >= root.minDelta) root.rampTo(target)
    else root.log("lux " + st.slowLux.toFixed(2) + ": target " + target + "% within " + root.minDelta + " of " + Math.round(st.curPct()) + "%")
  }
}
