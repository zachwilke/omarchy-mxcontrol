import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.zachwilke.mx"
  ipcTarget: "io.github.zachwilke.mx"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var mx: null

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color surface: Color.popups.background
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property bool canWrite: !!(mx && mx.hidppReady)
  readonly property var dpiSetting: Model.settingByNames(device, ["dpi", "dpi-extended", "dpi_extended"])
  readonly property var pointerSetting: Model.settingByNames(device, ["pointer_speed", "pointer-speed"])
  readonly property var smartSetting: Model.settingByNames(device, ["scroll-ratchet", "smartshift"])
  readonly property var smartThresholdSetting: Model.settingByNames(device, ["smart-shift", "smartshift"])
  readonly property var invertSetting: Model.settingByNames(device, ["hires-smooth-invert", "scroll-invert"])
  readonly property var hiresSetting: Model.settingByNames(device, ["hires-smooth-resolution", "hires-scroll-mode"])
  readonly property var thumbInvertSetting: Model.settingByNames(device, ["thumb-scroll-invert"])
  readonly property var thumbModeSetting: Model.settingByNames(device, ["thumb-scroll-mode"])
  readonly property var hostSetting: Model.settingByNames(device, ["change-host", "change_host"])
  readonly property var reportSetting: Model.settingByNames(device, ["report_rate", "report-rate", "report_rate_extended"])
  readonly property var ledControlSetting: Model.settingByNames(device, ["led_control"])
  readonly property var ledZoneSettings: Model.ledZones(device)
  readonly property bool showLighting: !!(ledControlSetting && ledZoneSettings.length > 0)
  readonly property var smartState: Model.smartShiftState(smartSetting)
  readonly property var hostOptions: Model.hostOptions(device)
  readonly property bool showDevices: mx && mx.displayDevices && mx.displayDevices.length > 1
  readonly property var adapters: mx && mx.adapters ? mx.adapters : []
  readonly property bool showPointer: !!(dpiSetting || pointerSetting)
  readonly property bool showScroll: !!(smartSetting || smartThresholdSetting || invertSetting || hiresSetting)
  readonly property bool showThumb: !!(thumbInvertSetting || thumbModeSetting)
  readonly property bool showHosts: !!(hostSetting || (device && device.hosts && device.hosts.length))
  readonly property string heroMeta: {
    if (!mx) return "Checking"
    if (!mx.installed) return "Needs Solaar"
    if (!device) return mx.message || "No device"
    var parts = []
    var battery = Model.batteryLabel(device)
    if (battery) parts.push(battery)
    var link = Model.connectionLabel(device)
    if (link) parts.push(link)
    if (device.online === false) parts.push("Offline")
    return parts.join(" · ") || "Connected"
  }

  property string focusSection: "header"
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool dropdownOpen: false
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Tuning the thumb",
    "Ratcheting quietly",
    "Smoothing the MagSpeed",
    "Pairing the channel",
    "Counting clicks",
    "Balancing DPI",
    "Watching the wheel"
  ]
  readonly property string heroPhraseText: !device ? heroMeta : activePhrases[phraseIndex % activePhrases.length]
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  function hidName(item, fallback) {
    var raw = ""
    if (item && item.name) raw = String(item.name)
    else if (fallback !== undefined && fallback !== null) raw = String(fallback)
    if (raw.indexOf("&") === -1 && raw.indexOf("<") === -1 && raw.indexOf(">") === -1)
      return raw
    return raw.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function open() {
    root.controller.show()
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
    }
  }

  function close() {
    dropdownOpen = false
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSelected(id) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.selectedDevice = String(id || "")
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseDevice(id) {
    if (!mx) return
    mx.selectDevice(id)
    persistSelected(id)
    mx.refresh()
  }

  function openSettings() {
    var payload = {}
    if (device && device.id) payload.device = String(device.id)
    root.close()
    Qt.callLater(function() {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
        root.bar.shell.summon("io.github.zachwilke.mx", JSON.stringify(payload))
    })
  }

  function writeSetting(setting, value, key) {
    if (!mx || !setting) return
    if (String(setting.name) === "change-host" && Model.choiceId(setting) === String(value)) return
    mx.setSetting(setting.name, value, key)
  }

  function writeToggle(setting) {
    if (!setting) return
    writeSetting(setting, Model.nextToggleValue(setting))
  }

  function sectionList() {
    var sections = ["header"]
    if (mx && !mx.installed) sections.push("install")
    else if (mx && mx.installed && !mx.accessible) sections.push("access")
    if (showDevices) sections.push("devices")
    if (root.canWrite) {
      if (showPointer) sections.push("pointer")
      if (showLighting) sections.push("lighting")
      if (showScroll) sections.push("scroll")
      if (showThumb) sections.push("thumb")
      if (showHosts) sections.push("hosts")
    }
    return sections
  }

  function sectionCount(section) {
    if (section === "devices") return mx && mx.displayDevices ? mx.displayDevices.length : 0
    if (section === "pointer") return (dpiSetting ? 1 : 0) + (pointerSetting ? 1 : 0)
    if (section === "lighting") return ledZoneSettings.length
    if (section === "scroll") return (smartSetting ? 1 : 0) + (invertSetting ? 1 : 0) + (hiresSetting ? 1 : 0)
    if (section === "thumb") return (thumbInvertSetting ? 1 : 0) + (thumbModeSetting ? 1 : 0)
    if (section === "hosts") return hostOptions.length
    return 1
  }

  function ensureCursor() {
    var sections = sectionList()
    if (sections.indexOf(focusSection) < 0) focusSection = sections.length ? sections[0] : "header"
    var count = sectionCount(focusSection)
    if (cursorIndex >= count) cursorIndex = Math.max(0, count - 1)
    if (cursorIndex < 0) cursorIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (focusSection === "pointer" && dx !== 0 && dpiSetting && cursorIndex === 0) {
      var bounds = Model.sliderBounds(dpiSetting)
      var next = Model.numericValue(dpiSetting, bounds.min) + dx * bounds.step
      next = Math.max(bounds.min, Math.min(bounds.max, next))
      writeSetting(dpiSetting, Model.snapToChoices(dpiSetting, next))
      return
    }
    if (dy === 0) return
    var sections = sectionList()
    var index = sections.indexOf(focusSection)
    var count = sectionCount(focusSection)
    if (dy > 0 && cursorIndex < count - 1) {
      cursorIndex += 1
      return
    }
    if (dy < 0 && cursorIndex > 0) {
      cursorIndex -= 1
      return
    }
    var nextSection = index + (dy > 0 ? 1 : -1)
    if (nextSection < 0 || nextSection >= sections.length) return
    focusSection = sections[nextSection]
    cursorIndex = dy > 0 ? 0 : Math.max(0, sectionCount(focusSection) - 1)
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "install" && mx) mx.installSolaar()
    else if (focusSection === "access" && mx) mx.triggerUdev()
    else if (focusSection === "devices" && mx && mx.displayDevices[cursorIndex])
      chooseDevice(mx.displayDevices[cursorIndex].id)
    else if (focusSection === "scroll" && cursorIndex === 0 && smartSetting) writeToggle(smartSetting)
    else if (focusSection === "scroll" && invertSetting) writeToggle(invertSetting)
    else if (focusSection === "thumb" && thumbInvertSetting) writeToggle(thumbInvertSetting)
    else if (focusSection === "hosts" && hostSetting) writeSetting(hostSetting, hostOptions[cursorIndex].value)
  }

  function setCursor(section, index) {
    cursorActive = true
    focusSection = section
    cursorIndex = index
  }

  onOpenedChanged: {
    if (!opened) {
      dropdownOpen = false
      return
    }
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
    }
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, root.canWrite ? 0 : Style.space(260)), Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // blocked, not enabled:false — disabling this item also disables the
      // Flickable and every Dropdown inside it, so the popup never receives
      // clicks and dropdownOpen can stay stuck until the shell restarts.
      blocked: root.dropdownOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { if (mx) mx.refresh() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor

            PanelHero {
              id: hero
              width: parent.width
              // HID names are untrusted peripheral identity; never render as rich text.
              title: device ? root.hidName(device, "MX Control") : "MX Control"
              meta: root.canWrite ? root.heroPhraseText : root.heroMeta
              detail: device && Model.batteryLabel(device) ? Model.batteryLabel(device) : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: device && device.online !== false ? 1.0 : 0.5
              iconComponent: Component {
                MxIcon {
                  iconSize: Style.font.display
                  color: root.device && root.mx && root.mx.batteryLow ? root.urgent : root.foreground
                  cutoutColor: root.surface
                  lowBattery: !!(root.mx && root.mx.batteryLow)
                  badgeColor: root.urgent
                }
              }
            }
          }

          Text {
            visible: mx && (mx.actionStatus !== "" || mx.lastError !== "")
            width: parent.width
            text: mx && mx.actionStatus !== "" ? mx.actionStatus : (mx ? mx.lastError : "")
            textFormat: Text.PlainText
            color: mx && mx.lastError !== "" && mx.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: mx && !mx.installed
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Solaar talks HID++ to the mouse. Install it, then reconnect the MX Master so hidraw permissions apply."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              text: "Install Solaar"
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "install"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (mx) mx.installSolaar()
              onHovered: function(on) { if (on) root.setCursor("install", 0) }
            }
          }

          Column {
            visible: mx && mx.installed && !mx.accessible
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Solaar is installed, but hidraw is still root-only. Reconnect the mouse or reload udev rules."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              text: "Reload udev"
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "access"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (mx) mx.triggerUdev()
              onHovered: function(on) { if (on) root.setCursor("access", 0) }
            }
          }

          Column {
            visible: root.adapters.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "ADAPTERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.adapters
              Text {
                required property var modelData
                width: parent ? parent.width : implicitWidth
                // HID names are untrusted peripheral identity; never render as rich text.
                text: root.hidName(modelData, "Receiver") + " · " + Model.connectionLabel(modelData)
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          Column {
            visible: root.showDevices
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: mx ? mx.displayDevices : []
                Button {
                  required property var modelData
                  required property int index
                  text: root.hidName(modelData, "Device") + (modelData.connection ? (" · " + Model.connectionLabel(modelData)) : "")
                  bordered: true
                  selected: device && String(device.id) === String(modelData.id)
                  hasCursor: root.cursorActive && root.focusSection === "devices" && root.cursorIndex === index
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.chooseDevice(modelData.id)
                  onHovered: function(on) { if (on) root.setCursor("devices", index) }
                }
              }
            }
          }

          Column {
            visible: root.showPointer && root.canWrite
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "POINTER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SliderBlock {
              visible: !!dpiSetting
              width: parent.width
              title: "Sensitivity"
              subtitle: dpiSetting ? (Math.round(Model.numericValue(dpiSetting, 0)) + " DPI") : ""
              info: Model.helpForSetting(dpiSetting, "How far the pointer travels. 8K is 8000 DPI, the MX sensor maximum.")
              setting: dpiSetting
              formatValue: function(v) { return Math.round(v) + " DPI" }
              hasCursor: root.cursorActive && root.focusSection === "pointer" && root.cursorIndex === 0
              onHoveredIn: root.setCursor("pointer", 0)
            }

            Row {
              visible: dpiSetting && Model.dpiPresets(dpiSetting).length > 0
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "Presets"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              InfoHint {
                anchors.verticalCenter: parent.verticalCenter
                text: "Jump to a common DPI. 8K is 8000 DPI — the same maximum Options+ offers on MX Master 3S."
              }

              Item { width: Math.max(0, 1); height: 1 }
            }

            ButtonGroup {
              visible: dpiSetting && Model.dpiPresets(dpiSetting).length > 0
              width: parent.width
              options: dpiSetting ? Model.dpiPresets(dpiSetting) : []
              value: dpiSetting ? String(Math.round(Model.numericValue(dpiSetting, 0))) : ""
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { if (dpiSetting) root.writeSetting(dpiSetting, Number(value)) }
            }

            SliderBlock {
              visible: !!pointerSetting
              width: parent.width
              title: pointerSetting ? pointerSetting.label : "Pointer speed"
              subtitle: pointerSetting ? String(Math.round(Model.numericValue(pointerSetting, 0))) : ""
              info: Model.helpForSetting(pointerSetting, "A software pointer-speed multiplier on top of hardware DPI.")
              setting: pointerSetting
            }

            SliderBlock {
              visible: !!(reportSetting && (reportSetting.kind === "range" || (reportSetting.choices && reportSetting.choices.length)))
              width: parent.width
              title: "Report rate"
              subtitle: reportSetting ? Model.reportRateLabel(Model.numericValue(reportSetting, 0)) : ""
              info: Model.helpForSetting(reportSetting, "How often the mouse reports movement, shown as Hz. Devices store the polling interval in milliseconds, so 1 ms is 1000 Hz.")
              setting: reportSetting
              formatValue: function(v) { return Model.reportRateLabel(v) }
            }

            HintedToggle {
              visible: !!(reportSetting && reportSetting.kind === "toggle")
              width: parent.width
              label: "8K polling"
              info: Model.helpForSetting(reportSetting, "Raises the report rate to the device maximum when the hardware supports it.")
              checked: reportSetting ? Model.boolValue(reportSetting) : false
              onClicked: root.writeToggle(reportSetting)
            }
          }

          Column {
            visible: root.showLighting && root.canWrite
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "LIGHTING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            HintedToggle {
              visible: !!ledControlSetting
              width: parent.width
              label: "Host control"
              info: "Let this panel drive the mouse LEDs instead of the onboard profile. Turn it off to hand the LEDs back."
              checked: ledControlSetting ? Model.boolValue(ledControlSetting) : false
              onClicked: root.writeToggle(ledControlSetting)
            }

            Repeater {
              model: ledZoneSettings

              delegate: Column {
                required property var modelData
                readonly property var zone: modelData
                readonly property var zoneEffects: zone && zone.effects ? zone.effects : []
                readonly property var currentValue: zone && zone.value ? zone.value : {}
                readonly property int currentId: currentValue.ID !== undefined ? Number(currentValue.ID) : -1
                readonly property var currentEffect: zoneEffects.find(function(e) { return e.id === currentId }) || null
                readonly property bool needsColor: !!currentEffect && currentEffect.params.some(function(p) { return p.name === "color" })
                width: parent.width
                spacing: Style.space(6)

                function pickEffect(idv) {
                  var payload = { ID: idv }
                  var eff = zoneEffects.find(function(e) { return e.id === idv })
                  if (!eff) {
                    root.writeSetting(zone, payload)
                    return
                  }
                  // Seed every declared parameter; zeros make effects
                  // degenerate (a 0 ms period breathes nothing at all).
                  for (var i = 0; i < eff.params.length; i++) {
                    var p = eff.params[i]
                    if (p.name === "color") payload.color = Model.ledCurrentColor(currentValue)
                    else if (p.kind === "range" || p.kind === "choice") payload[p.name] = Model.ledRangeDefault(p)
                  }
                  root.writeSetting(zone, payload)
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    text: zone && zone.label ? String(zone.label).toUpperCase() : "ZONE"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  InfoHint { text: Model.helpForSetting(zone, "Pick an effect for this LED zone.") }
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: zoneEffects
                    delegate: Button {
                      required property var modelData
                      text: modelData.label
                      selected: currentId === Number(modelData.id)
                      bordered: true
                      focusable: false
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onClicked: pickEffect(Number(modelData.id))
                    }
                  }
                }

                Flow {
                  visible: needsColor
                  width: parent.width
                  spacing: Style.space(8)
                  Repeater {
                    model: Model.ledPalette()
                    delegate: LedColorSwatch {
                      required property var modelData
                      swatchColor: modelData.color
                      selected: currentValue.color !== undefined && Number(currentValue.color) === modelData.value
                      onPicked: root.writeSetting(zone, { ID: currentId, color: modelData.value })
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: root.showScroll && root.canWrite
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "SCROLL WHEEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            HintedToggle {
              visible: !!smartSetting
              width: parent.width
              label: "SmartShift"
              info: Model.helpForSetting(smartSetting, "Ratchet at slow speeds, free-spin when you scroll quickly.")
              checked: root.smartState.on
              hasCursor: root.cursorActive && root.focusSection === "scroll" && root.cursorIndex === 0
              onClicked: root.writeToggle(smartSetting)
              onHovered: function(on) { if (on) root.setCursor("scroll", 0) }
            }

            SliderBlock {
              visible: !!(smartThresholdSetting && smartThresholdSetting.kind === "range")
              width: parent.width
              title: "SmartShift threshold"
              subtitle: smartThresholdSetting ? String(Math.round(Model.numericValue(smartThresholdSetting, 20))) : ""
              info: Model.helpForSetting(smartThresholdSetting, "How fast you must scroll before the wheel leaves ratchet mode.")
              setting: smartThresholdSetting
              hasCursor: root.cursorActive && root.focusSection === "scroll" && root.cursorIndex === 0
              onHoveredIn: root.setCursor("scroll", 0)
            }

            HintedToggle {
              visible: !!invertSetting
              width: parent.width
              label: "Invert scroll"
              info: Model.helpForSetting(invertSetting, "Reverse the vertical wheel direction.")
              checked: invertSetting ? Model.boolValue(invertSetting) : false
              hasCursor: root.cursorActive && root.focusSection === "scroll" && root.cursorIndex === (smartSetting ? 1 : 0)
              onClicked: root.writeToggle(invertSetting)
              onHovered: function(on) { if (on) root.setCursor("scroll", smartSetting ? 1 : 0) }
            }

            HintedToggle {
              visible: !!hiresSetting && hiresSetting.kind === "toggle"
              width: parent.width
              label: "High-resolution scroll"
              info: Model.helpForSetting(hiresSetting, "Finer wheel steps. Best over Bluetooth on the MX Master 3S.")
              checked: hiresSetting ? Model.boolValue(hiresSetting) : false
              hasCursor: root.cursorActive && root.focusSection === "scroll" && root.cursorIndex === ((smartSetting ? 1 : 0) + (invertSetting ? 1 : 0))
              onClicked: root.writeToggle(hiresSetting)
              onHovered: function(on) { if (on) root.setCursor("scroll", (smartSetting ? 1 : 0) + (invertSetting ? 1 : 0)) }
            }
          }

          Column {
            visible: root.showThumb && root.canWrite
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "THUMB WHEEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            HintedToggle {
              visible: !!thumbInvertSetting
              width: parent.width
              label: "Invert thumb wheel"
              info: Model.helpForSetting(thumbInvertSetting, "Reverse horizontal / thumb-wheel scrolling.")
              checked: thumbInvertSetting ? Model.boolValue(thumbInvertSetting) : false
              hasCursor: root.cursorActive && root.focusSection === "thumb" && root.cursorIndex === 0
              onClicked: root.writeToggle(thumbInvertSetting)
              onHovered: function(on) { if (on) root.setCursor("thumb", 0) }
            }

            HintedToggle {
              visible: !!thumbModeSetting && thumbModeSetting.kind === "toggle"
              width: parent.width
              label: "HID++ thumb wheel"
              info: Model.helpForSetting(thumbModeSetting, "Send thumb-wheel motion as HID++ so Solaar rules can handle it.")
              checked: thumbModeSetting ? Model.boolValue(thumbModeSetting) : false
              hasCursor: root.cursorActive && root.focusSection === "thumb" && root.cursorIndex === (thumbInvertSetting ? 1 : 0)
              onClicked: root.writeToggle(thumbModeSetting)
              onHovered: function(on) { if (on) root.setCursor("thumb", thumbInvertSetting ? 1 : 0) }
            }
          }

          Column {
            visible: root.showHosts && root.canWrite
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            Row {
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                text: "EASY SWITCH"
                foreground: root.foreground
                fontFamily: root.fontFamily
                width: parent.width - easyInfo.implicitWidth - parent.spacing
              }
              InfoHint {
                id: easyInfo
                anchors.verticalCenter: parent.verticalCenter
                text: Model.helpForSetting(hostSetting, "Jump to another paired computer. Same as the channel slider on the bottom of the device.")
              }
            }

            ButtonGroup {
              width: parent.width
              options: root.hostOptions
              value: hostSetting ? Model.choiceId(hostSetting) : ""
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              cursorIndex: root.cursorActive && root.focusSection === "hosts" ? root.cursorIndex : -1
              onChanged: function(value) { if (hostSetting) root.writeSetting(hostSetting, value) }
              onHovered: function(index, on) { if (on) root.setCursor("hosts", index) }
            }
          }

          Button {
            visible: root.canWrite
            text: "All settings"
            bordered: true
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.openSettings()
          }

          Column {
            visible: mx && mx.installed && mx.accessible && !root.canWrite
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: {
                if (!mx || !mx.daemonWanted)
                  return "Click the bar icon again if settings do not appear."
                if (mx.lastError)
                  return mx.lastError
                if (mx.hidppTicks > 12)
                  return "Still reading settings. Right-click the bar icon to retry."
                if (mx.progressLabel)
                  return "Reading " + mx.progressLabel + "…"
                return "Reading settings from the device…"
              }
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              visible: !!(mx && mx.daemonWanted && !mx.lastError)
              width: parent.width
              spacing: Style.space(8)

              Item {
                width: parent.width - pctLabel.implicitWidth - parent.spacing
                height: Style.space(8)

                Rectangle {
                  anchors.fill: parent
                  radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height
                  radius: height / 2
                  color: root.foreground
                  width: Math.max(parent.height, parent.width * ((mx && mx.readPercent ? mx.readPercent : 0) / 100))

                  Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
              }

              Text {
                id: pctLabel
                anchors.verticalCenter: parent.verticalCenter
                text: (mx && mx.readPercent ? mx.readPercent : 0) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 3200
    running: root.opened && root.canWrite
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component InfoHint: Item {
    id: hint
    property string text: ""

    implicitWidth: Style.space(18)
    implicitHeight: Style.space(18)
    visible: String(text || "") !== ""

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius > 0 ? width / 2 : 0
      color: hintMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
      borderSpec: Border.controlSpec(hintMouse.containsMouse ? "hover-cursor" : "normal", root.foreground, root.accent)

      Text {
        anchors.centerIn: parent
        text: "i"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.italic: true
      }
    }

    MouseArea {
      id: hintMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.WhatsThisCursor
    }

    PanelToolTip {
      visible: hintMouse.containsMouse
      delay: 80
      text: hint.text
      fontFamily: root.fontFamily
    }
  }

  component HintedToggle: Row {
    id: hinted
    property string label: ""
    property string info: ""
    property bool checked: false
    property bool hasCursor: false
    signal clicked()
    signal hovered(bool isHovered)

    spacing: Style.space(8)

    Toggle {
      width: parent.width - (hinted.info !== "" ? hintedInfo.implicitWidth + hinted.spacing : 0)
      label: hinted.label
      checked: hinted.checked
      hasCursor: hinted.hasCursor
      foreground: root.foreground
      fontFamily: root.fontFamily
      accent: root.accent
      onClicked: hinted.clicked()
      onHovered: function(on) { hinted.hovered(on) }
    }

    InfoHint {
      id: hintedInfo
      anchors.verticalCenter: parent.verticalCenter
      text: hinted.info
    }
  }

  component LedColorSwatch: Rectangle {
    property color swatchColor: "#ffffff"
    property bool selected: false
    signal picked()
    width: 22
    height: 22
    radius: 6
    color: swatchColor
    border.color: selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
    border.width: selected ? 2 : 1
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.picked()
    }
  }

  component SliderBlock: Column {
    id: sliderBlock
    property string title: ""
    property string subtitle: ""
    property string info: ""
    property var setting: null
    property var formatValue: null
    property string liveSubtitle: ""
    property bool hasCursor: false
    readonly property var bounds: Model.sliderBounds(setting)
    signal hoveredIn()

    function displayFor(value) {
      if (sliderBlock.formatValue) return sliderBlock.formatValue(value)
      return String(Math.round(value))
    }

    spacing: Style.space(4)

    Item {
      width: parent.width
      height: Math.max(titleLabel.implicitHeight, valueLabel.implicitHeight)
      Text {
        id: titleLabel
        text: sliderBlock.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      InfoHint {
        anchors.left: titleLabel.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: sliderBlock.info !== "" ? sliderBlock.info : Model.helpForSetting(sliderBlock.setting, "")
      }
      Text {
        id: valueLabel
        text: sliderBlock.liveSubtitle !== "" ? sliderBlock.liveSubtitle : sliderBlock.subtitle
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width - titleLabel.implicitWidth - Style.space(40))
      }
    }

    CursorSurface {
      width: parent.width
      implicitHeight: slider.implicitHeight
      hasCursor: sliderBlock.hasCursor
      foreground: root.foreground

      PanelSlider {
        id: slider
        anchors.left: parent.left
        anchors.right: parent.right
        bar: root.bar
        minimum: sliderBlock.bounds.min
        maximum: sliderBlock.bounds.max
        step: sliderBlock.bounds.step
        integer: true
        value: sliderBlock.setting ? Model.numericValue(sliderBlock.setting, sliderBlock.bounds.min) : sliderBlock.bounds.min
        onMoved: function(next) {
          sliderBlock.liveSubtitle = sliderBlock.displayFor(Model.snapToChoices(sliderBlock.setting, next))
        }
        onReleased: function(next) {
          sliderBlock.liveSubtitle = ""
          if (sliderBlock.setting) root.writeSetting(sliderBlock.setting, Model.snapToChoices(sliderBlock.setting, next))
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: sliderBlock.hoveredIn()
        onExited: root.cursorActive = false
      }
    }
  }

}
