import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property bool closingFromHost: false
  property bool dropdownOpen: false
  property string profileDraft: ""
  property string selectedDivertId: ""

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
      if (payloadJson) {
        try {
          var parsed = JSON.parse(String(payloadJson))
          if (parsed && parsed.device) mx.selectDevice(parsed.device)
        } catch (e) { /* ignore */ }
      }
    }
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("io.github.zachwilke.mx")
    else window.visible = false
  }

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family
  readonly property var fakeBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: root.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }
  property var bar: fakeBar

  Service {
    id: mx
  }

  readonly property var device: mx.selectedDevice
  onDeviceChanged: selectedDivertId = ""
  readonly property bool canWrite: mx.hidppReady
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
  readonly property var divertSetting: Model.settingByNames(device, ["divert-keys"])
  readonly property var reportSetting: Model.settingByNames(device, ["report_rate", "report-rate", "report_rate_extended"])
  readonly property var fnSetting: Model.settingByNames(device, ["fn-swap", "fn_swap"])
  readonly property var backlightSetting: Model.settingByNames(device, ["backlight", "backlight_level", "backlight-level"])
  readonly property var platformSetting: Model.settingByNames(device, ["multiplatform"])
  readonly property var lockSetting: Model.settingByNames(device, ["disable-keyboard-keys"])
  readonly property var extraSettings: Model.remainingSettings(device, usedSettingNames())
  readonly property var divertBoard: bindDivertBoard(device, divertSetting, remapSetting)
  readonly property bool mouseView: !!(divertBoard && divertBoard.view === "mouse")
  readonly property var selectedDivertRow: {
    var keys = divertSetting && divertSetting.keys ? divertSetting.keys : []
    for (var i = 0; i < keys.length; i++) {
      if (String(keys[i].key) === String(root.selectedDivertId)) return keys[i]
    }
    return null
  }
  readonly property var selectedRemapRow: {
    var keys = remapSetting && remapSetting.keys ? remapSetting.keys : []
    for (var i = 0; i < keys.length; i++) {
      if (String(keys[i].key) === String(root.selectedDivertId)) return keys[i]
    }
    return null
  }
  readonly property var smartState: Model.smartShiftState(smartSetting)
  readonly property var hostOptions: Model.hostOptions(device)
  readonly property var deviceProfiles: {
    var list = mx.profiles || []
    var kind = device && device.kind ? String(device.kind) : ""
    var out = []
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (!row) continue
      if (kind && row.kind && String(row.kind) !== kind) continue
      out.push(row)
    }
    return out
  }

  function usedSettingNames() {
    var names = []
    function add(setting) { if (setting && setting.name) names.push(setting.name) }
    add(dpiSetting); add(pointerSetting); add(smartSetting); add(smartThresholdSetting)
    add(invertSetting); add(hiresSetting); add(thumbInvertSetting); add(thumbModeSetting)
    add(hostSetting); add(remapSetting); add(divertSetting); add(reportSetting)
    add(fnSetting); add(backlightSetting); add(platformSetting); add(lockSetting)
    return names
  }

  function cap(id, glyph, title, span) {
    return { id: String(id), glyph: glyph, title: title, span: span || 1, decorative: false, spacer: false }
  }
  function dead(glyph, span) {
    return { id: "", glyph: glyph || "", title: "", span: span || 1, decorative: true, spacer: false }
  }
  function gap(span) {
    return { id: "", glyph: "", title: "", span: span || 1, decorative: true, spacer: true }
  }
  function bindDivertBoard(dev, setting, remap) {
    if (typeof Model.divertLayout === "function") {
      try { return Model.divertLayout(dev, setting, remap) } catch (e) {}
    }
    return null
  }

  function selectedCapTitle() {
    var id = String(root.selectedDivertId || "")
    if (!id || !root.divertBoard) return ""
    var rows = root.divertBoard.rows || []
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r] || []
      for (var c = 0; c < row.length; c++) {
        if (row[c] && String(row[c].id) === id && row[c].title) return String(row[c].title)
      }
    }
    var spots = root.divertBoard.spots || []
    for (var i = 0; i < spots.length; i++) {
      if (spots[i] && String(spots[i].id) === id && spots[i].title) return String(spots[i].title)
    }
    return ""
  }

  function hidName(item, fallback) {
    var raw = ""
    if (item && item.name) raw = String(item.name)
    else if (fallback !== undefined && fallback !== null) raw = String(fallback)
    if (raw.indexOf("&") === -1 && raw.indexOf("<") === -1 && raw.indexOf(">") === -1)
      return raw
    return raw.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function writeSetting(setting, value, key) {
    if (!mx || !setting) return
    mx.setSetting(setting.name, value, key)
  }

  function writeToggle(setting) {
    if (!setting) return
    writeSetting(setting, Model.nextToggleValue(setting))
  }

  function rowValue(row) {
    var current = row && row.value
    if (current && typeof current === "object" && current.id !== undefined) return String(current.id)
    return current === undefined || current === null ? "" : String(current)
  }

  function rowOptions(row) {
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

  FloatingWindow {
    id: window
    title: "MX Control"
    color: root.background
    implicitWidth: 760
    implicitHeight: 780
    minimumSize: Qt.size(560, 520)
    maximumSize: Qt.size(880, 980)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("io.github.zachwilke.mx")
    }

    FocusScope {
      anchors.fill: parent
      focus: true

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.dropdownOpen
        onCloseRequested: root.requestClose()
        onTextKey: function(t) {
          if (t === "r" || t === "R") mx.refresh(true)
        }

        Flickable {
          id: flick
          anchors.fill: parent
          anchors.margins: Style.space(18)
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: column
            width: flick.width
            spacing: Style.space(14)

            Row {
              width: parent.width
              spacing: Style.space(12)
              MxIcon {
                iconSize: Style.font.display
                color: mx.batteryLow ? root.urgent : root.foreground
                cutoutColor: root.background
                lowBattery: mx.batteryLow
                badgeColor: root.urgent
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                spacing: Style.space(2)
                width: parent.width - Style.font.display - parent.spacing
                Text {
                  text: device ? root.hidName(device, "MX Control") : "MX Control"
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  text: {
                    var parts = []
                    var battery = Model.batteryLabel(device)
                    if (battery) parts.push(battery)
                    var link = Model.connectionLabel(device)
                    if (link) parts.push(link)
                    parts.push("All settings")
                    return parts.join(" · ")
                  }
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              visible: mx.actionStatus !== "" || mx.lastError !== ""
              width: parent.width
              text: mx.actionStatus !== "" ? mx.actionStatus : mx.lastError
              textFormat: Text.PlainText
              color: mx.lastError !== "" && mx.actionStatus === "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: mx.displayDevices
                Button {
                  required property var modelData
                  text: root.hidName(modelData, "Device") + (modelData.connection ? (" · " + Model.connectionLabel(modelData)) : "")
                  bordered: true
                  selected: device && String(device.id) === String(modelData.id)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: mx.selectDevice(modelData.id)
                }
              }
            }

            Text {
              visible: !root.canWrite
              width: parent.width
              text: mx.daemonWanted
                ? ("Reading settings" + (mx.progressLabel ? (" · " + mx.progressLabel) : "") + " · " + mx.readPercent + "%")
                : "Open the bar icon once if settings do not appear."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Column {
              visible: !!dpiSetting && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "POINTER"; foreground: root.foreground; fontFamily: root.fontFamily }
              SliderBlock {
                visible: !!dpiSetting
                width: parent.width
                title: "Sensitivity"
                subtitle: dpiSetting ? (Math.round(Model.numericValue(dpiSetting, 0)) + " DPI") : ""
                info: Model.helpForSetting(dpiSetting, "How far the pointer travels. 8K is 8000 DPI.")
                setting: dpiSetting
                formatValue: function(v) { return Math.round(v) + " DPI" }
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
            }

            Column {
              visible: !!(smartSetting || invertSetting || hiresSetting) && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "SCROLL"; foreground: root.foreground; fontFamily: root.fontFamily }
              HintedToggle {
                visible: !!smartSetting
                width: parent.width
                label: "SmartShift"
                info: Model.helpForSetting(smartSetting, "Ratchet at slow speeds, free-spin when you scroll quickly.")
                checked: root.smartState.on
                onClicked: root.writeToggle(smartSetting)
              }
              SliderBlock {
                visible: !!(smartThresholdSetting && smartThresholdSetting.kind === "range")
                width: parent.width
                title: "SmartShift threshold"
                subtitle: smartThresholdSetting ? String(Math.round(Model.numericValue(smartThresholdSetting, 20))) : ""
                info: Model.helpForSetting(smartThresholdSetting, "How fast you must scroll before the wheel leaves ratchet mode.")
                setting: smartThresholdSetting
              }
              HintedToggle {
                visible: !!invertSetting
                width: parent.width
                label: "Invert scroll"
                info: Model.helpForSetting(invertSetting, "Reverse the vertical wheel.")
                checked: invertSetting ? Model.boolValue(invertSetting) : false
                onClicked: root.writeToggle(invertSetting)
              }
              HintedToggle {
                visible: !!hiresSetting && hiresSetting.kind === "toggle"
                width: parent.width
                label: "High-resolution scroll"
                info: Model.helpForSetting(hiresSetting, "Finer wheel steps.")
                checked: hiresSetting ? Model.boolValue(hiresSetting) : false
                onClicked: root.writeToggle(hiresSetting)
              }
            }

            Column {
              visible: !!(thumbInvertSetting || thumbModeSetting) && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "THUMB WHEEL"; foreground: root.foreground; fontFamily: root.fontFamily }
              HintedToggle {
                visible: !!thumbInvertSetting
                width: parent.width
                label: "Invert thumb wheel"
                info: Model.helpForSetting(thumbInvertSetting, "Reverse the thumb wheel.")
                checked: thumbInvertSetting ? Model.boolValue(thumbInvertSetting) : false
                onClicked: root.writeToggle(thumbInvertSetting)
              }
              HintedToggle {
                visible: !!thumbModeSetting && thumbModeSetting.kind === "toggle"
                width: parent.width
                label: "HID++ thumb wheel"
                info: Model.helpForSetting(thumbModeSetting, "Send thumb-wheel motion as HID++ for Solaar rules.")
                checked: thumbModeSetting ? Model.boolValue(thumbModeSetting) : false
                onClicked: root.writeToggle(thumbModeSetting)
              }
            }

            Column {
              visible: !!(hostSetting || (device && device.hosts && device.hosts.length)) && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "EASY SWITCH"; foreground: root.foreground; fontFamily: root.fontFamily }
              ButtonGroup {
                width: parent.width
                options: root.hostOptions
                value: hostSetting ? Model.choiceId(hostSetting) : ""
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { if (hostSetting) root.writeSetting(hostSetting, value) }
              }
            }

            Column {
              visible: !!(remapSetting && remapSetting.keys && remapSetting.keys.length) && root.canWrite && !root.mouseView
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "BUTTON REMAPS"; foreground: root.foreground; fontFamily: root.fontFamily }
              Text {
                width: parent.width
                text: "The first action in each list is the factory default."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: remapSetting && remapSetting.keys ? remapSetting.keys : []
                MapRow {
                  required property var modelData
                  width: column.width
                  row: modelData
                  setting: root.remapSetting
                }
              }
            }

            Column {
              visible: (!!(divertSetting && divertSetting.keys && divertSetting.keys.length) || root.mouseView) && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                text: root.mouseView ? "BUTTONS" : "KEYS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Text {
                width: parent.width
                text: root.divertBoard
                  ? ((root.divertBoard.familyLabel ? root.divertBoard.familyLabel + ". " : "") + (root.mouseView
                    ? "Click a lit control to remap it or send it to HID++. Dim controls are not on this model."
                    : "F1–F12 are the function row. The small label is the default action; Fn swap changes whether you need Fn to get a real F-key. Grey keys are just the chassis."))
                  : "Regular is a normal click. Divert sends HID++ so Solaar rules can handle the press."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Item {
                visible: !!root.divertBoard && !root.mouseView
                width: parent.width
                height: keyBoard.height
                KeyBoard {
                  id: keyBoard
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Math.min(parent.width, root.divertBoard && root.divertBoard.compact ? 620 : 740)
                  layout: root.divertBoard
                }
              }
              Item {
                visible: root.mouseView
                width: parent.width
                height: mouseBoard.height
                MouseBoard {
                  id: mouseBoard
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Math.min(parent.width * 0.56, 340)
                  layout: root.divertBoard
                }
              }
              Column {
                visible: !!(root.selectedDivertRow || root.selectedRemapRow) && !!root.divertBoard
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: root.hidName({
                    name: root.selectedCapTitle()
                      || (root.selectedDivertRow && root.selectedDivertRow.label)
                      || (root.selectedRemapRow && root.selectedRemapRow.label)
                  }, "Control")
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                MapRow {
                  visible: !!root.selectedRemapRow && root.mouseView
                  width: parent.width
                  row: root.selectedRemapRow
                  setting: root.remapSetting
                }
                ButtonGroup {
                  visible: !!root.selectedDivertRow
                  width: parent.width
                  options: root.rowOptions(root.selectedDivertRow)
                  value: root.rowValue(root.selectedDivertRow)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onChanged: function(value) {
                    if (root.divertSetting && root.selectedDivertRow)
                      root.writeSetting(root.divertSetting, value, root.selectedDivertRow.key)
                  }
                }
              }
              Repeater {
                model: root.divertBoard ? [] : (divertSetting && divertSetting.keys ? divertSetting.keys : [])
                MapRow {
                  required property var modelData
                  width: column.width
                  row: modelData
                  setting: root.divertSetting
                }
              }
            }

            Column {
              visible: !!(fnSetting || backlightSetting || platformSetting || lockSetting) && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "KEYBOARD"; foreground: root.foreground; fontFamily: root.fontFamily }
              HintedToggle {
                visible: !!fnSetting && fnSetting.kind === "toggle"
                width: parent.width
                label: fnSetting ? fnSetting.label : "Fn swap"
                info: Model.helpForSetting(fnSetting, "Function keys send media actions by default.")
                checked: fnSetting ? Model.boolValue(fnSetting) : false
                onClicked: root.writeToggle(fnSetting)
              }
              SliderBlock {
                visible: !!backlightSetting && backlightSetting.kind === "range"
                width: parent.width
                title: backlightSetting ? backlightSetting.label : "Backlight"
                subtitle: backlightSetting ? String(Math.round(Model.numericValue(backlightSetting, 0))) : ""
                info: Model.helpForSetting(backlightSetting, "Keyboard backlight brightness.")
                setting: backlightSetting
              }
              ExtraChoice {
                visible: !!backlightSetting && backlightSetting.kind === "choice"
                width: parent.width
                setting: backlightSetting
              }
              ExtraChoice {
                visible: !!platformSetting && platformSetting.kind === "choice"
                width: parent.width
                setting: platformSetting
              }
              Repeater {
                model: lockSetting && lockSetting.keys ? lockSetting.keys : []
                HintedToggle {
                  required property var modelData
                  width: column.width
                  visible: true
                  label: "Disable " + (modelData && modelData.label ? modelData.label : "key")
                  info: Model.helpForSetting(root.lockSetting, "Stops this key from sending its usual scancode.")
                  checked: !!(modelData && modelData.value)
                  onClicked: if (root.lockSetting) root.writeSetting(root.lockSetting, !(modelData && modelData.value), modelData.key)
                }
              }
            }

            Column {
              visible: root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "PROFILES"; foreground: root.foreground; fontFamily: root.fontFamily }
              Text {
                width: parent.width
                text: "Snapshots of this device’s onboard settings on this computer. Easy Switch channel is not stored. Not Logi cloud profiles."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Row {
                width: parent.width
                spacing: Style.space(8)
                TextField {
                  id: profileField
                  width: parent.width - saveBtn.implicitWidth - parent.spacing
                  placeholderText: "Desk"
                  font.family: root.fontFamily
                  onAccepted: {
                    mx.saveProfile(text)
                    text = ""
                  }
                }
                Button {
                  id: saveBtn
                  text: "Save"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    mx.saveProfile(profileField.text)
                    profileField.text = ""
                  }
                }
              }
              Repeater {
                model: root.deviceProfiles
                Row {
                  required property var modelData
                  width: column.width
                  spacing: Style.space(8)
                  Text {
                    text: root.hidName(modelData, "Profile")
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - applyBtn.implicitWidth - delBtn.implicitWidth - parent.spacing * 2
                    elide: Text.ElideRight
                  }
                  Button {
                    id: applyBtn
                    text: "Apply"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: mx.applyProfile(modelData.name)
                  }
                  Button {
                    id: delBtn
                    text: "Delete"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: mx.deleteProfile(modelData.name)
                  }
                }
              }
              Text {
                visible: root.deviceProfiles.length === 0
                text: "No profiles yet."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              visible: extraSettings.length > 0 && root.canWrite
              width: parent.width
              spacing: Style.space(8)
              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "MORE"; foreground: root.foreground; fontFamily: root.fontFamily }
              Repeater {
                model: extraSettings
                ExtraBlock {
                  required property var modelData
                  width: column.width
                  setting: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  component HintedToggle: Row {
    id: hinted
    property string label: ""
    property string info: ""
    property bool checked: false
    signal clicked()
    spacing: Style.space(8)
    Toggle {
      width: parent.width - (hinted.info !== "" ? hintedInfo.implicitWidth + hinted.spacing : 0)
      label: hinted.label
      checked: hinted.checked
      foreground: root.foreground
      fontFamily: root.fontFamily
      accent: root.accent
      onClicked: hinted.clicked()
    }
    InfoHint {
      id: hintedInfo
      anchors.verticalCenter: parent.verticalCenter
      text: hinted.info
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

  component SliderBlock: Column {
    id: sliderBlock
    property string title: ""
    property string subtitle: ""
    property string info: ""
    property var setting: null
    property var formatValue: null
    property string liveSubtitle: ""
    readonly property var bounds: Model.sliderBounds(setting)
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
        text: sliderBlock.info
      }
      Item { width: Math.max(0, 1); height: 1 }
      Text {
        text: sliderBlock.liveSubtitle !== "" ? sliderBlock.liveSubtitle : sliderBlock.subtitle
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    PanelSlider {
      width: parent.width
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
  }

  component KeyBoard: Column {
    id: board
    property var layout: null
    spacing: Style.space(4)
    readonly property var rows: layout && layout.rows ? layout.rows : []

    Repeater {
      model: board.rows.length
      Row {
        id: keyRow
        required property int index
        width: board.width
        spacing: Style.space(3)
        readonly property var caps: board.rows[index] || []
        readonly property real spanTotal: {
          var n = 0
          var list = keyRow.caps
          for (var i = 0; i < list.length; i++) n += Number(list[i].span || 1)
          return Math.max(1, n)
        }
        readonly property real unit: Math.max(8, (width - Math.max(0, caps.length - 1) * spacing) / spanTotal)

        Repeater {
          model: keyRow.caps.length
          Item {
            required property int index
            readonly property var cap: keyRow.caps[index] || ({})
            width: keyRow.unit * Number(cap.span || 1)
            height: cap.spacer ? 1 : Style.space(cap.decorative ? 26 : (cap.hint ? 42 : 34))

            BorderSurface {
              visible: !cap.spacer
              anchors.fill: parent
              radius: Style.cornerRadius
              color: {
                if (cap.decorative) return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                if (String(cap.id) === String(root.selectedDivertId))
                  return Style.hoverFillFor(root.foreground, root.accent)
                if (cap.row && Number(cap.row.value) !== 0)
                  return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
                return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              }
              borderSpec: Border.controlSpec(
                String(cap.id) === String(root.selectedDivertId) ? "hover-cursor" : "normal",
                root.foreground,
                root.accent
              )

              Column {
                anchors.centerIn: parent
                spacing: 0
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: cap.glyph || ""
                  color: cap.decorative ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: cap.hint ? Style.font.body : Style.font.caption
                  font.bold: !!cap.hint
                  opacity: cap.decorative ? 0.45 : 1
                }
                Text {
                  visible: !!cap.hint
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: cap.hint || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  opacity: 0.7
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: !!cap.row
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.selectedDivertId = String(cap.id)
              }
            }
          }
        }
      }
    }
  }

  component MouseBoard: Column {
    id: mouseBoardRoot
    property var layout: null
    spacing: Style.space(8)
    readonly property var spots: layout && layout.spots ? layout.spots : []
    readonly property var extras: layout && layout.extras ? layout.extras : []
    readonly property real aspect: layout && layout.aspect ? Number(layout.aspect) : 1.3
    readonly property string hull: layout && layout.hull ? String(layout.hull) : "master"

    Item {
      id: stage
      width: mouseBoardRoot.width
      height: width * mouseBoardRoot.aspect

      Canvas {
        id: hullCanvas
        anchors.fill: parent
        property color fillColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
        property color strokeColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
        property string kind: mouseBoardRoot.hull
        onFillColorChanged: requestPaint()
        onStrokeColorChanged: requestPaint()
        onKindChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function strokeFill(ctx) {
          ctx.fillStyle = fillColor
          ctx.strokeStyle = strokeColor
          ctx.lineWidth = Math.max(1.2, width * 0.012)
          ctx.fill()
          ctx.stroke()
        }

        onPaint: {
          var ctx = getContext("2d")
          var w = width
          var h = height
          if (w < 8 || h < 8) return
          ctx.reset()
          ctx.lineJoin = "round"
          ctx.lineCap = "round"
          ctx.beginPath()
          if (kind === "vertical") {
            ctx.moveTo(w * 0.78, h * 0.04)
            ctx.quadraticCurveTo(w * 0.96, h * 0.08, w * 0.94, h * 0.28)
            ctx.quadraticCurveTo(w * 0.92, h * 0.62, w * 0.82, h * 0.92)
            ctx.quadraticCurveTo(w * 0.62, h * 0.99, w * 0.42, h * 0.90)
            ctx.quadraticCurveTo(w * 0.22, h * 0.70, w * 0.16, h * 0.48)
            ctx.quadraticCurveTo(w * 0.14, h * 0.22, w * 0.42, h * 0.06)
            ctx.quadraticCurveTo(w * 0.60, h * 0.02, w * 0.78, h * 0.04)
          } else if (kind === "ergo") {
            ctx.moveTo(w * 0.18, h * 0.18)
            ctx.quadraticCurveTo(w * 0.50, h * 0.02, w * 0.82, h * 0.18)
            ctx.quadraticCurveTo(w * 0.98, h * 0.50, w * 0.82, h * 0.84)
            ctx.quadraticCurveTo(w * 0.50, h * 0.98, w * 0.18, h * 0.84)
            ctx.quadraticCurveTo(w * 0.02, h * 0.50, w * 0.18, h * 0.18)
          } else if (kind === "anywhere") {
            ctx.moveTo(w * 0.50, h * 0.04)
            ctx.quadraticCurveTo(w * 0.88, h * 0.08, w * 0.90, h * 0.42)
            ctx.quadraticCurveTo(w * 0.88, h * 0.82, w * 0.50, h * 0.96)
            ctx.quadraticCurveTo(w * 0.12, h * 0.82, w * 0.10, h * 0.42)
            ctx.quadraticCurveTo(w * 0.12, h * 0.08, w * 0.50, h * 0.04)
          } else {
            ctx.moveTo(w * 0.56, h * 0.03)
            ctx.quadraticCurveTo(w * 0.90, h * 0.06, w * 0.93, h * 0.26)
            ctx.quadraticCurveTo(w * 0.96, h * 0.52, w * 0.88, h * 0.82)
            ctx.quadraticCurveTo(w * 0.78, h * 0.98, w * 0.52, h * 0.97)
            ctx.quadraticCurveTo(w * 0.30, h * 0.96, w * 0.26, h * 0.78)
            ctx.quadraticCurveTo(w * 0.18, h * 0.60, w * 0.04, h * 0.52)
            ctx.quadraticCurveTo(w * -0.02, h * 0.40, w * 0.08, h * 0.30)
            ctx.quadraticCurveTo(w * 0.22, h * 0.20, w * 0.32, h * 0.16)
            ctx.quadraticCurveTo(w * 0.40, h * 0.07, w * 0.56, h * 0.03)
          }
          ctx.closePath()
          strokeFill(ctx)
          if (kind === "ergo") {
            ctx.beginPath()
            ctx.arc(w * 0.50, h * 0.48, Math.min(w, h) * 0.16, 0, Math.PI * 2)
            ctx.fillStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
            ctx.lineWidth = Math.max(1, width * 0.01)
            ctx.fill()
            ctx.stroke()
          }
        }
      }

      Repeater {
        model: mouseBoardRoot.spots.length
        Item {
          required property int index
          readonly property var cap: mouseBoardRoot.spots[index] || ({})
          readonly property bool live: !!(cap.row || cap.remap)
          x: Number(cap.x) * stage.width
          y: Number(cap.y) * stage.height
          width: Math.max(18, Number(cap.w) * stage.width)
          height: Math.max(16, Number(cap.h) * stage.height)

          BorderSurface {
            anchors.fill: parent
            radius: cap.shape === "wheel" || cap.shape === "pill" ? Math.min(width, height) / 2 : Style.cornerRadius
            color: {
              if (!live) return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              if (String(cap.id) === String(root.selectedDivertId))
                return Style.hoverFillFor(root.foreground, root.accent)
              if (cap.row && Number(cap.row.value) !== 0)
                return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
              return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }
            borderSpec: Border.controlSpec(
              String(cap.id) === String(root.selectedDivertId) ? "hover-cursor" : "normal",
              root.foreground,
              root.accent
            )

            Text {
              anchors.centerIn: parent
              text: cap.glyph || ""
              color: live ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              opacity: live ? 1 : 0.45
            }

            MouseArea {
              anchors.fill: parent
              enabled: live
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.selectedDivertId = String(cap.id)
            }
          }
        }
      }
    }

    Flow {
      visible: mouseBoardRoot.extras.length > 0
      width: mouseBoardRoot.width
      spacing: Style.space(6)
      Repeater {
        model: mouseBoardRoot.extras.length
        BorderSurface {
          required property int index
          readonly property var cap: mouseBoardRoot.extras[index] || ({})
          width: extraLabel.implicitWidth + Style.space(16)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: String(cap.id) === String(root.selectedDivertId)
            ? Style.hoverFillFor(root.foreground, root.accent)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          borderSpec: Border.controlSpec(
            String(cap.id) === String(root.selectedDivertId) ? "hover-cursor" : "normal",
            root.foreground,
            root.accent
          )
          Text {
            id: extraLabel
            anchors.centerIn: parent
            text: cap.title || cap.glyph || cap.id
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedDivertId = String(cap.id)
          }
        }
      }
    }
  }

  component MapRow: Row {
    property var row: ({})
    property var setting: null
    spacing: Style.space(8)
    Dropdown {
      width: parent.width
      label: row && row.label ? row.label : "Button"
      value: root.rowValue(row)
      options: root.rowOptions(row)
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(value) { if (setting) root.writeSetting(setting, value, row.key) }
      onPopupOpenChanged: root.dropdownOpen = popupOpen
      Component.onDestruction: if (popupOpen) root.dropdownOpen = false
    }
  }

  component ExtraChoice: Dropdown {
    property var setting: null
    width: parent ? parent.width : implicitWidth
    label: setting ? setting.label : ""
    value: setting ? Model.choiceId(setting) : ""
    options: setting ? Model.choiceOptions(setting) : []
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) { if (setting) root.writeSetting(setting, value) }
    onPopupOpenChanged: root.dropdownOpen = popupOpen
  }

  component ExtraBlock: Column {
    id: extraBlock
    property var setting: null
    spacing: Style.space(4)
    HintedToggle {
      visible: extraBlock.setting && extraBlock.setting.kind === "toggle"
      width: parent.width
      label: extraBlock.setting ? extraBlock.setting.label : ""
      info: Model.helpForSetting(extraBlock.setting, "")
      checked: extraBlock.setting ? Model.boolValue(extraBlock.setting) : false
      onClicked: root.writeToggle(extraBlock.setting)
    }
    SliderBlock {
      visible: extraBlock.setting && extraBlock.setting.kind === "range"
      width: parent.width
      title: extraBlock.setting ? extraBlock.setting.label : ""
      subtitle: extraBlock.setting ? String(Math.round(Model.numericValue(extraBlock.setting, 0))) : ""
      info: Model.helpForSetting(extraBlock.setting, "")
      setting: extraBlock.setting
    }
    ExtraChoice {
      visible: extraBlock.setting && extraBlock.setting.kind === "choice"
      width: parent.width
      setting: extraBlock.setting
    }
  }
}
