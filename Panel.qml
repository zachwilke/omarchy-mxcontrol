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
  readonly property var remapSetting: Model.settingByNames(device, ["reprogrammable-keys"])
  readonly property var reportSetting: Model.settingByNames(device, ["report_rate", "report-rate", "report_rate_extended"])
  readonly property var fnSetting: Model.settingByNames(device, ["fn-swap", "fn_swap"])
  readonly property var backlightSetting: Model.settingByNames(device, ["backlight", "backlight_level", "backlight-level"])
  readonly property var extraSettings: Model.remainingSettings(device, usedSettingNames())
  readonly property var smartState: Model.smartShiftState(smartSetting)
  readonly property var hostOptions: Model.hostOptions(device)
  readonly property bool showDevices: mx && mx.displayDevices && mx.displayDevices.length > 1
  readonly property var adapters: mx && mx.adapters ? mx.adapters : []
  readonly property bool showPointer: !!(dpiSetting || pointerSetting)
  readonly property bool showScroll: !!(smartSetting || smartThresholdSetting || invertSetting || hiresSetting)
  readonly property bool showThumb: !!(thumbInvertSetting || thumbModeSetting)
  readonly property bool showHosts: !!(hostSetting || (device && device.hosts && device.hosts.length))
  readonly property bool showKeys: !!(remapSetting && remapSetting.keys && remapSetting.keys.length)
  readonly property bool showMore: extraSettings.length > 0 || !!(reportSetting || fnSetting || backlightSetting)
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

  function usedSettingNames() {
    var names = []
    function add(setting) { if (setting && setting.name) names.push(setting.name) }
    add(dpiSetting); add(pointerSetting); add(smartSetting); add(smartThresholdSetting); add(invertSetting)
    add(hiresSetting); add(thumbInvertSetting); add(thumbModeSetting); add(hostSetting)
    add(remapSetting); add(reportSetting); add(fnSetting); add(backlightSetting)
    return names
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
      if (showScroll) sections.push("scroll")
      if (showThumb) sections.push("thumb")
      if (showHosts) sections.push("hosts")
      if (showKeys) sections.push("keys")
      if (showMore) sections.push("more")
    }
    return sections
  }

  function sectionCount(section) {
    if (section === "devices") return mx && mx.displayDevices ? mx.displayDevices.length : 0
    if (section === "pointer") return (dpiSetting ? 1 : 0) + (pointerSetting ? 1 : 0)
    if (section === "scroll") return (smartSetting ? 1 : 0) + (invertSetting ? 1 : 0) + (hiresSetting ? 1 : 0)
    if (section === "thumb") return (thumbInvertSetting ? 1 : 0) + (thumbModeSetting ? 1 : 0)
    if (section === "hosts") return hostOptions.length
    if (section === "keys") return remapSetting && remapSetting.keys ? remapSetting.keys.length : 0
    if (section === "more") {
      var n = extraSettings.length
      if (reportSetting) n += 1
      if (fnSetting) n += 1
      if (backlightSetting) n += 1
      return n
    }
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
    else if (focusSection === "more" && extraSettings[cursorIndex] && extraSettings[cursorIndex].kind === "toggle")
      writeToggle(extraSettings[cursorIndex])
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
              subtitle: reportSetting ? (Math.round(Model.numericValue(reportSetting, 0)) + " Hz") : ""
              info: Model.helpForSetting(reportSetting, "How often the mouse reports movement. 8K is 8000 Hz when the device supports it.")
              setting: reportSetting
              formatValue: function(v) { return Math.round(v) + " Hz" }
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
            visible: false
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            Row {
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                text: "BUTTONS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                width: parent.width - buttonsInfo.implicitWidth - parent.spacing
              }
              InfoHint {
                id: buttonsInfo
                anchors.verticalCenter: parent.verticalCenter
                text: "Remap a button to another action. The first entry in each list is the factory default."
              }
            }

            Repeater {
              model: remapSetting && remapSetting.keys ? remapSetting.keys : []
              KeyRow {
                required property var modelData
                required property int index
                width: column.width
                row: modelData
                rowIndex: index
              }
            }
          }

          Column {
            visible: false
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "MORE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            HintedToggle {
              visible: !!fnSetting && fnSetting.kind === "toggle"
              width: parent.width
              label: fnSetting ? fnSetting.label : "Fn swap"
              info: Model.helpForSetting(fnSetting, "Function keys send media actions by default. Hold Fn for F1–F12.")
              checked: fnSetting ? Model.boolValue(fnSetting) : false
              onClicked: root.writeToggle(fnSetting)
            }

            SliderBlock {
              visible: !!backlightSetting && backlightSetting.kind === "range"
              width: parent.width
              title: backlightSetting ? backlightSetting.label : "Backlight"
              subtitle: backlightSetting ? String(Math.round(Model.numericValue(backlightSetting, 0))) : ""
              info: Model.helpForSetting(backlightSetting, "How bright the keyboard backlight is.")
              setting: backlightSetting
            }

            HintedToggle {
              visible: !!backlightSetting && backlightSetting.kind === "toggle"
              width: parent.width
              label: backlightSetting ? backlightSetting.label : "Backlight"
              info: Model.helpForSetting(backlightSetting, "Keyboard lighting on or off.")
              checked: backlightSetting ? Model.boolValue(backlightSetting) : false
              onClicked: root.writeToggle(backlightSetting)
            }

            Repeater {
              model: extraSettings
              ExtraRow {
                required property var modelData
                required property int index
                width: column.width
                setting: modelData
                rowIndex: index
              }
            }
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

    Row {
      width: parent.width
      spacing: Style.space(8)
      Text {
        text: sliderBlock.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      InfoHint {
        anchors.verticalCenter: parent.verticalCenter
        text: sliderBlock.info !== "" ? sliderBlock.info : Model.helpForSetting(sliderBlock.setting, "")
      }
      Item { width: Math.max(0, parent.width - parent.children[0].width - parent.children[1].width - valueLabel.width - parent.spacing * 2); height: 1 }
      Text {
        id: valueLabel
        text: sliderBlock.liveSubtitle !== "" ? sliderBlock.liveSubtitle : sliderBlock.subtitle
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
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
      }
    }
  }

  component KeyRow: Column {
    id: keyRow
    property var row: ({})
    property int rowIndex: 0
    spacing: Style.space(4)

    Row {
      width: parent.width
      spacing: Style.space(8)
      Dropdown {
        width: parent.width - keyInfo.implicitWidth - parent.spacing
        label: row && row.label ? row.label : "Button"
      value: {
        var current = row && row.value
        if (current && typeof current === "object" && current.id !== undefined) return String(current.id)
        return current === undefined || current === null ? "" : String(current)
      }
      options: {
        var choices = row && row.choices ? row.choices : []
        var list = []
        for (var i = 0; i < choices.length; i++) {
          var item = choices[i]
          list.push({
            value: item && item.id !== undefined ? String(item.id) : String(item && item.name || item),
            label: item && item.name ? String(item.name) : String(item)
          })
        }
        return list
      }
      hasCursor: root.cursorActive && root.focusSection === "keys" && root.cursorIndex === rowIndex
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(value) {
        if (root.remapSetting) root.writeSetting(root.remapSetting, value, row.key)
      }
      onHovered: function(on) { if (on) root.setCursor("keys", rowIndex) }
      onPopupOpenChanged: root.dropdownOpen = popupOpen
      Component.onDestruction: if (popupOpen) root.dropdownOpen = false
      }

      InfoHint {
        id: keyInfo
        anchors.verticalCenter: parent.verticalCenter
        text: Model.helpForSetting(root.remapSetting, "Changes what this button sends. The first action is the factory default.")
      }
    }
  }

  component ExtraRow: Column {
    id: extra
    property var setting: null
    property int rowIndex: 0
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(4)

    HintedToggle {
      visible: extra.setting && extra.setting.kind === "toggle"
      width: parent.width
      label: extra.setting ? extra.setting.label : ""
      info: Model.helpForSetting(extra.setting, "")
      checked: extra.setting ? Model.boolValue(extra.setting) : false
      hasCursor: root.cursorActive && root.focusSection === "more" && root.cursorIndex === extra.rowIndex
      onClicked: root.writeToggle(extra.setting)
      onHovered: function(on) { if (on) root.setCursor("more", extra.rowIndex) }
    }

    SliderBlock {
      visible: extra.setting && extra.setting.kind === "range"
      width: parent.width
      title: extra.setting ? extra.setting.label : ""
      subtitle: extra.setting ? String(Math.round(Model.numericValue(extra.setting, 0))) : ""
      info: Model.helpForSetting(extra.setting, "")
      setting: extra.setting
      hasCursor: root.cursorActive && root.focusSection === "more" && root.cursorIndex === extra.rowIndex
      onHoveredIn: root.setCursor("more", extra.rowIndex)
    }

    Row {
      visible: extra.setting && extra.setting.kind === "choice"
      width: parent.width
      spacing: Style.space(8)

      Dropdown {
        width: parent.width - extraInfo.implicitWidth - parent.spacing
        label: extra.setting ? extra.setting.label : ""
        value: extra.setting ? Model.choiceId(extra.setting) : ""
        options: extra.setting ? Model.choiceOptions(extra.setting) : []
        hasCursor: root.cursorActive && root.focusSection === "more" && root.cursorIndex === extra.rowIndex
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(value) { root.writeSetting(extra.setting, value) }
        onHovered: function(on) { if (on) root.setCursor("more", extra.rowIndex) }
        onPopupOpenChanged: root.dropdownOpen = popupOpen
        Component.onDestruction: if (popupOpen) root.dropdownOpen = false
      }

      InfoHint {
        id: extraInfo
        anchors.verticalCenter: parent.verticalCenter
        text: Model.helpForSetting(extra.setting, "")
      }
    }
  }
}
