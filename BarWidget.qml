import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.zachwilke.mx"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color iconColor: {
    if (!mx.hasDevice) return Qt.darker(barForeground, 1.55)
    if (mx.batteryLow) return bar && bar.urgent ? bar.urgent : Color.urgent
    return mx.online ? barForeground : Qt.darker(barForeground, 1.55)
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    mx.refresh(true)
  }

  // One IpcHandler per plugin id. A bar surface exists per monitor; the
  // leftmost screen owns the target and broadcast() fans out to peers.
  readonly property bool ipcOwner: {
    var win = button.QsWindow ? button.QsWindow.window : null
    var mine = win && win.screen ? win.screen : null
    var screens = Quickshell.screens
    var count = screens && screens.length ? screens.length : 0
    if (!mine || count === 0) return count <= 1
    var best = screens[0]
    for (var i = 1; i < count; i++) {
      var screen = screens[i]
      if (!screen) continue
      if (screen.x < best.x || (screen.x === best.x && screen.y < best.y))
        best = screen
    }
    return mine.name === best.name
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("mx" in target) target.mx = mx
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Service {
    id: mx
    settings: root.settings
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    enabled: root.ipcOwner
    target: "io.github.zachwilke.mx"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (!mx.hasDevice) return mx.installed ? "No MX device" : "MX Control — install Solaar"
      var name = Model.plainHidText(mx.selectedDevice && mx.selectedDevice.name ? mx.selectedDevice.name : "MX")
      var link = Model.connectionLabel(mx.selectedDevice)
      var battery = mx.batteryPercent >= 0 ? (" · " + mx.batteryPercent + "%") : ""
      return name + (link ? (" · " + link) : "") + battery
    }
    iconComponent: Component {
      MxIcon {
        iconSize: Style.bar.iconCanvas
        color: root.iconColor
        cutoutColor: root.bar ? root.bar.background : Color.background
        lowBattery: mx.batteryLow
        badgeColor: root.bar && root.bar.urgent ? root.bar.urgent : Color.urgent
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }
}
