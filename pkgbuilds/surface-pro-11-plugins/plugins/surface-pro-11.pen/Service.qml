import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// Surface Slim Pen: shows the OSD with the pen's battery when it connects
// (a tail-button click reconnects it). `omarchy-shell pen charging <percent>`
// shows a charging OSD on demand.
//
// A docked pen connects too, e.g. when the pen dock service sets the dock up
// at boot, so while surface-pro-11-support says the pen is docked the OSD
// waits, and shows when the pen is taken out instead.
Item {
  id: root

  property var shell: null

  readonly property string penGlyph: "󰏪"
  readonly property string chargingGlyph: "󱐋"
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pen: {
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d && d.connected && String(d.name || "").indexOf("Slim Pen") !== -1) return d
    }
    return null
  }
  readonly property int penBattery: pen && pen.batteryAvailable ? Math.round(pen.battery * 100) : -1

  property bool shownThisConnection: false
  // A missing file (no pen dock service) counts as not docked.
  property bool penDocked: false

  FileView {
    path: "/run/surface-pro-11-support/pen-docked"
    watchChanges: true
    printErrors: false
    onLoaded: root.readDocked(text())
    onLoadFailed: root.penDocked = false
    onFileChanged: reload()
  }

  // The service rewrites "1" or "0" in place; ignore a half-written read.
  function readDocked(value) {
    var v = String(value).trim()
    if (v === "1" || v === "0") penDocked = v === "1"
  }

  function osd(args) {
    osdProc.command = ["omarchy-osd"].concat(args)
    osdProc.running = true
  }

  function showBattery() {
    if (penBattery < 0) return
    shownThisConnection = true
    osd(["-i", penGlyph, "-p", String(penBattery), "-d", "1800"])
  }

  Process { id: osdProc }

  // Battery Level arrives a moment after the link comes up: show as soon as
  // it's known, or give up quietly after a few seconds.
  onPenChanged: {
    shownThisConnection = false
    if (pen) settle.restart()
  }
  onPenBatteryChanged: if (pen && !shownThisConnection && !penDocked && penBattery >= 0) showBattery()
  // Taken out of the dock: show the battery whether the pen connects now or
  // was already connected while docked.
  onPenDockedChanged: if (!penDocked && pen) showBattery()

  function showCharging(percent) {
    osd(["-i", chargingGlyph, "-m", "Pen charging · " + percent + "%", "-d", "2500"])
  }

  Timer {
    id: settle
    interval: 4000
    onTriggered: root.shownThisConnection = true
  }

  IpcHandler {
    target: "pen"
    function charging(percent: string): string {
      var p = parseInt(percent, 10)
      if (isNaN(p)) root.osd(["-i", root.chargingGlyph, "-m", "Pen charging", "-d", "2500"])
      else root.showCharging(p)
      return "ok"
    }
    function battery(): string { return String(root.penBattery) }
    function docked(): string { return String(root.penDocked) }
    function show(): string { root.showBattery(); return "ok" }
  }
}
