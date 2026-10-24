import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons

// Concave rounded-corner fills, in two independent families:
//
//   screen — four fills flush with the physical display corners, over the bar,
//     so the picture appears to bend into the bezel.
//   bar — the two fills at the bar's inner edge, so the desktop bends into the
//     bar instead of starting square below it. Follows the bar's position and
//     size, turns see-through and blurred with a glassy bar, and drops out
//     while the bar is hidden or clear.
//
// Settings are inline on this plugin's entry in ~/.config/omarchy/shell.json:
//
//   { "id": "surface-pro-11.corners", "screenRadius": "", "barRadius": "",
//     "screenColor": "#000000", "barColor": "", "screen": true, "bar": true }
//
// An empty or missing radius follows Hyprland's decoration:rounding, so the
// fills match the windows; a number pins it. An empty barColor follows the
// theme's bar background, and a glassy bar caps either at the bar's glass alpha.
Item {
  id: root

  // Injected by the host: scoped shell facade (bar state) and our manifest.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "surface-pro-11.corners"

  property var settings: ({})

  function setting(key, fallback) {
    var value = settings ? settings[key] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  // Style.cornerRadius mirrors Hyprland's decoration:rounding.
  readonly property int screenRadius: Math.max(0, Number(setting("screenRadius", Style.cornerRadius)) || 0)
  readonly property int barRadius: Math.max(0, Number(setting("barRadius", Style.cornerRadius)) || 0)
  readonly property color screenColor: setting("screenColor", "#000000")
  readonly property color barBaseColor: setting("barColor", Color.bar.background)
  // Same tint as the bar's own glassBackground (Bar.qml caps it at 0.35), so the
  // fills read as one surface.
  readonly property color barColor: barGlassy
    ? Qt.rgba(barBaseColor.r, barBaseColor.g, barBaseColor.b, Math.min(barBaseColor.a, 0.35))
    : barBaseColor
  readonly property bool screenOn: setting("screen", true) === true && screenRadius > 0
  readonly property bool barOn: setting("bar", true) === true && barRadius > 0

  readonly property var barState: shell ? shell.bar : null
  readonly property string barEdge: barState ? barState.position : "top"
  readonly property int barSize: barState ? barState.barSize : 0
  // Read from shell.json below rather than shell.barConfig: that snapshot is
  // not refreshed when the bar's double-click background cycle steps along.
  // bar.background is "opaque", "glassy" or "none".
  property string barBackground: "opaque"
  readonly property bool barTransparent: barBackground === "none"
  readonly property bool barGlassy: barBackground === "glassy"
  readonly property bool barVisible: barSize > 0 && !(barState && barState.barHidden) && !barTransparent

  property bool configLoaded: false

  // Hyprland blurs everything behind a layer, so the bar fills, which sit
  // beside windows and right under the bar, come out darker than the bar.
  // Same as omarchy-bar's sync_glass: a toggle file Hyprland loads, present
  // only while it matters, reloading Hyprland only when it changes.
  readonly property bool glassRuleWanted: barOn && barGlassy
  onGlassRuleWantedChanged: syncGlassRule()
  onConfigLoadedChanged: syncGlassRule()

  function syncGlassRule() {
    if (!configLoaded) return
    var stateHome = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    // Hyprland requires these by module name, where a dot means a directory.
    var flag = stateHome + "/omarchy/toggles/hypr/" + pluginId.replace(/\./g, "-") + "-glassy.lua"
    var source = Qt.resolvedUrl("hypr/bar-glassy.lua").toString().replace(/^file:\/\//, "")
    Quickshell.execDetached(["bash", "-c",
      'if [[ $3 == 1 ]]; then [[ -f $2 ]] && exit; mkdir -p "${2%/*}" && cp "$1" "$2" || exit; '
        + 'else [[ -f $2 ]] || exit; rm -f "$2" || exit; fi; hyprctl reload >/dev/null 2>&1',
      "bash", source, flag, glassRuleWanted ? "1" : "0"])
  }

  readonly property var barCornerNames: barEdge === "left" ? ["topLeft", "bottomLeft"]
    : barEdge === "right" ? ["topRight", "bottomRight"]
    : barEdge === "bottom" ? ["bottomLeft", "bottomRight"]
    : ["topLeft", "topRight"]

  // One entry per fill, "<family>:<corner>". The bar family comes first so the
  // screen fills are the younger surfaces and win where the two overlap.
  readonly property var pieces: (barOn && barVisible ? barCornerNames.map(name => "bar:" + name) : [])
    .concat(screenOn ? ["topLeft", "topRight", "bottomLeft", "bottomRight"].map(name => "screen:" + name) : [])

  // The shell only re-reads Hyprland's rounding on startup and theme changes;
  // nudge it when the Hyprland config reloads so an edited rounding applies.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") Style.scheduleRefresh()
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var config = JSON.parse(text())
        var plugins = config.plugins || []
        var bar = config.bar || {}
        // A config from before bar.background says transparent instead.
        root.barBackground = bar.background || (bar.transparent === true ? "none" : "opaque")
        var entry = plugins.find(p => p && p.id === root.pluginId)
        root.settings = entry || ({})
        root.configLoaded = true
      } catch (e) {
        console.warn(root.pluginId + ": could not read settings:", e)
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Scope {
      id: screenScope

      required property ShellScreen modelData

      Variants {
        model: root.pieces

        delegate: PanelWindow {
          id: win

          required property string modelData // "<family>:<corner>", e.g. "bar:topLeft"

          readonly property bool onBar: modelData.startsWith("bar:")
          readonly property string corner: modelData.substring(modelData.indexOf(":") + 1)
          readonly property bool isTop: corner.startsWith("top")
          readonly property bool isLeft: corner.endsWith("Left")
          readonly property int size: onBar ? root.barRadius : root.screenRadius

          screen: screenScope.modelData
          color: "transparent"
          implicitWidth: size
          implicitHeight: size

          anchors.top: isTop
          anchors.bottom: !isTop
          anchors.left: isLeft
          anchors.right: !isLeft

          // Only the bar family clears the bar; the screen family stays flush
          // with the display on every edge, bar included.
          margins.top: onBar && root.barEdge === "top" ? root.barSize : 0
          margins.bottom: onBar && root.barEdge === "bottom" ? root.barSize : 0
          margins.left: onBar && root.barEdge === "left" ? root.barSize : 0
          margins.right: onBar && root.barEdge === "right" ? root.barSize : 0

          // The bar fills share the bar's namespace so Hyprland's glassy layer
          // rules (^omarchy-bar$) blur behind them exactly as behind the bar.
          WlrLayershell.namespace: onBar ? "omarchy-bar" : "omarchy-corners-screen"
          WlrLayershell.layer: WlrLayer.Top
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          // Reserve nothing, and honour nobody else's zone either: the fills are
          // anchored to the raw screen edges and offset only by the margins above.
          exclusionMode: ExclusionMode.Ignore
          mask: Region {}

          CornerFill {
            anchors.fill: parent
            isTop: win.isTop
            isLeft: win.isLeft
            fill: win.onBar ? root.barColor : root.screenColor
          }
        }
      }
    }
  }
}
