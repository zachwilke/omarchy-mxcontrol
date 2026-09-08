import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  // Injected by shells with plugin-service support: the same shared Service
  // instance the bar widgets use, so selection and snapshots stay in sync.
  property var service: null
  property bool closingFromHost: false
  property bool dropdownOpen: false
  property string section: "device"
  property bool showHardware: false
  readonly property bool wideLayout: window.width >= Style.space(900)
  readonly property var navigation: [
    { key: "device", label: Model.isKeyboard(device) ? "Keyboard" : "Point & scroll", detail: Model.isKeyboard(device) ? "Function keys and backlighting" : "Sensitivity and wheel behavior" },
    { key: "buttons", label: Model.isKeyboard(device) ? "Keys & actions" : "Buttons & actions", detail: "Shortcuts for the way you work" },
    { key: "hosts", label: "Easy Switch", detail: "Your paired computers" },
    { key: "profiles", label: "Profiles", detail: "Save and restore device settings" },
    { key: "advanced", label: "Advanced", detail: "Additional device controls" }
  ]
  readonly property var currentPage: navigation.filter(function(n) { return n.key === root.section })[0]
  onSectionChanged: flick.contentY = 0

  function resolveService() {
    if (service || !shell) return
    if (typeof shell.ensureService === "function")
      service = shell.ensureService("io.github.zachwilke.mx") || null
    if (!service && typeof shell.serviceFor === "function")
      service = shell.serviceFor("io.github.zachwilke.mx")
  }

  function open(payloadJson) {
    closingFromHost = false
    resolveService()
    window.visible = true
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
      if (typeof mx.refreshApplications === "function") mx.refreshApplications()
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
  readonly property color dim: Qt.alpha(foreground, 0.68)
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

  // Fallback for shells without plugin services. Stays passive: it reads
  // status.json and starts the helper when the window actually opens.
  Service {
    id: localMx
    passive: true
  }

  readonly property var mx: root.service || localMx

  readonly property var device: mx.selectedDevice
  readonly property bool canWrite: mx.hidppReady
  readonly property var dpiSetting: Model.settingByNames(device, ["dpi", "dpi-extended", "dpi_extended"])
  readonly property var smartSetting: Model.settingByNames(device, ["scroll-ratchet", "smartshift"])
  readonly property var smartThresholdSetting: Model.settingByNames(device, ["smart-shift", "smartshift"])
  readonly property var invertSetting: Model.settingByNames(device, ["hires-smooth-invert", "scroll-invert"])
  readonly property var hiresSetting: Model.settingByNames(device, ["hires-smooth-resolution", "hires-scroll-mode"])
  readonly property var thumbInvertSetting: Model.settingByNames(device, ["thumb-scroll-invert"])
  readonly property var thumbModeSetting: Model.settingByNames(device, ["thumb-scroll-mode"])
  readonly property var hostSetting: Model.settingByNames(device, ["change-host", "change_host"])
  readonly property var remapSetting: Model.settingByNames(device, ["reprogrammable-keys"])
  readonly property var divertSetting: Model.settingByNames(device, ["divert-keys"])
  readonly property var fnSetting: Model.settingByNames(device, ["fn-swap", "fn_swap"])
  readonly property var backlightSetting: Model.settingByNames(device, ["backlight", "backlight_level", "backlight-level"])
  readonly property var platformSetting: Model.settingByNames(device, ["multiplatform"])
  readonly property var lockSetting: Model.settingByNames(device, ["disable-keyboard-keys"])
  readonly property var extraSettings: Model.remainingSettings(device, usedSettingNames())
  readonly property var assignmentControls: Model.assignmentControls(remapSetting, divertSetting)
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
    add(dpiSetting)
    add(smartSetting)
    // smartshift can be a range that also supplies the on/off control.
    if (smartThresholdSetting && smartThresholdSetting.kind === "range") add(smartThresholdSetting)
    if (invertSetting && invertSetting.kind === "toggle") add(invertSetting)
    if (hiresSetting && hiresSetting.kind === "toggle") add(hiresSetting)
    if (thumbInvertSetting && thumbInvertSetting.kind === "toggle") add(thumbInvertSetting)
    if (thumbModeSetting && thumbModeSetting.kind === "toggle") add(thumbModeSetting)
    add(hostSetting); add(remapSetting); add(divertSetting)
    if (fnSetting && fnSetting.kind === "toggle") add(fnSetting)
    if (backlightSetting && (backlightSetting.kind === "range" || backlightSetting.kind === "choice")) add(backlightSetting)
    if (platformSetting && platformSetting.kind === "choice") add(platformSetting)
    add(lockSetting)
    return names
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
    implicitWidth: 1100
    implicitHeight: 820
    minimumSize: Qt.size(560, 520)
    maximumSize: Qt.size(1400, 1200)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("io.github.zachwilke.mx")
    }

    FocusScope {
      anchors.fill: parent
      focus: true

      FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (root.dropdownOpen) return
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            mx.refresh(true)
            event.accepted = true
          }
        }

        Rectangle {
          visible: root.wideLayout
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(212)
          color: Qt.alpha(root.foreground, 0.025)
          Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(root.foreground, 0.08) }
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(20)
            spacing: Style.space(28)
            Column {
              spacing: Style.space(6)
              Text { text: "MX Control"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
              Text { text: "Your devices. Your way."; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            }
            Column {
              width: parent.width
              spacing: Style.space(8)
              Repeater {
                model: root.navigation
                Button {
                  required property var modelData
                  width: parent.width
                  text: modelData.label
                  leftAlign: true
                  verticalPadding: Style.space(12)
                  selected: root.section === modelData.key
                  bordered: selected
                  focusable: true
                  onClicked: root.section = modelData.key
                }
              }
            }
          }
        }

        Column {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(28)
          anchors.leftMargin: root.wideLayout ? Style.space(240) : Style.space(28)
          spacing: Style.space(16)

          Row {
            width: parent.width
            spacing: Style.space(12)
            Column {
              width: parent.width - refreshButton.width - parent.spacing
              spacing: Style.space(4)
              Text {
                text: "DEVICE SETTINGS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.width
                text: device ? root.hidName(device, "Logitech device") : "Your Logitech devices"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle * 1.5
                font.bold: true
              }
              Text {
                width: parent.width
                text: device ? [Model.connectionLabel(device), Model.batteryLabel(device)].filter(function(v) { return !!v }).join("  ·  ") : "Connect a mouse or keyboard to get started."
                textFormat: Text.PlainText
                color: mx.batteryLow ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
            Button {
              id: refreshButton
              text: "Refresh"
              bordered: true
              focusable: true
              anchors.verticalCenter: parent.verticalCenter
              onClicked: mx.refresh(true)
            }
          }

          Dropdown {
            visible: mx.displayDevices.length > 1
            width: parent.width
            showLabel: false
            value: device ? String(device.id) : ""
            options: mx.displayDevices.filter(function(d) { return !!d }).map(function(d) { return { value: String(d.id), label: root.hidName(d, "Device") } })
            onChanged: function(value) { mx.selectDevice(value) }
            onPopupOpenChanged: root.dropdownOpen = popupOpen
          }

          Flow {
            visible: !root.wideLayout
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.navigation
              Button {
                required property var modelData
                text: modelData.label
                selected: root.section === modelData.key
                bordered: selected
                focusable: true
                onClicked: root.section = modelData.key
              }
            }
          }
        }

        Flickable {
          id: flick
          anchors.top: header.bottom
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(24)
          anchors.topMargin: Style.space(24)
          anchors.leftMargin: root.wideLayout ? Style.space(240) : Style.space(28)
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: column
            width: flick.width - Style.space(12)
            spacing: Style.space(16)

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                width: parent.width
                text: root.currentPage.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle * 1.35
                font.bold: true
              }
              Text {
                width: parent.width
                text: root.currentPage.detail
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
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

            Text {
              visible: !root.canWrite
              width: parent.width
              text: !mx.installed ? "Install Solaar to configure your devices: omarchy pkg add solaar"
                : !device ? "No supported device found. Connect your device, then refresh."
                : device.online === false ? "This device is offline. Wake it or reconnect, then refresh."
                : !mx.accessible ? "Waiting for device access. After installing Solaar, reconnect your device so its access rules apply."
                : "Reading settings" + (mx.progressLabel ? (" · " + mx.progressLabel) : "") + " · " + mx.readPercent + "%"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            SectionCard {
              visible: root.section === "device" && (!!dpiSetting && root.canWrite)
              width: parent.width
              title: "Pointer"
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

            SectionCard {
              visible: root.section === "device" && (!!(smartSetting || smartThresholdSetting || invertSetting || hiresSetting) && root.canWrite)
              width: parent.width
              title: "Scrolling"
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

            SectionCard {
              visible: root.section === "device" && (!!(thumbInvertSetting || thumbModeSetting) && root.canWrite)
              width: parent.width
              title: "Thumb wheel"
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

            SectionCard {
              visible: root.section === "hosts" && (!!(hostSetting || (device && device.hosts && device.hosts.length)) && root.canWrite)
              width: parent.width
              title: "Easy Switch"
              ButtonGroup {
                width: parent.width
                options: root.hostOptions
                value: hostSetting ? Model.choiceId(hostSetting) : ""
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { if (hostSetting) root.writeSetting(hostSetting, value) }
              }
              Text {
                visible: !!(device && device.hosts && device.hosts.length)
                width: parent.width
                text: "Rename a channel below. Names are stored on the device and show on every computer. Solaar may keep the active channel set to this computer's hostname."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: (device && device.hosts && device.hosts.length) ? device.hosts : []
                Row {
                  id: hostRow
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    id: hostNum
                    text: String(Number(hostRow.modelData.index) + 1) + (hostRow.modelData.current ? " •" : "")
                    textFormat: Text.PlainText
                    color: hostRow.modelData.current ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    width: Style.space(28)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  TextField {
                    id: hostNameField
                    width: parent.width - hostNum.width - hostRenameBtn.implicitWidth - parent.spacing * 2
                    placeholderText: root.hidName(hostRow.modelData, "Channel " + (Number(hostRow.modelData.index) + 1))
                    font.family: root.fontFamily
                    onAccepted: {
                      mx.renameHost(hostRow.modelData.index, text)
                      text = ""
                    }
                  }
                  Button {
                    id: hostRenameBtn
                    text: "Rename"
                    bordered: true
                    focusable: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: {
                      mx.renameHost(hostRow.modelData.index, hostNameField.text)
                      hostNameField.text = ""
                    }
                  }
                }
              }
            }

            SectionCard {
              visible: root.section === "buttons" && root.canWrite
              width: parent.width
              ActionEditor {
                width: parent.width
                service: root.mx
                device: root.device
                controls: root.assignmentControls
              }
            }
            Button {
              visible: root.section === "buttons" && root.canWrite
              text: root.showHardware ? "Hide hardware controls" : "Hardware remaps & Solaar rules"
              focusable: true
              bordered: true
              onClicked: root.showHardware = !root.showHardware
            }

            SectionCard {
              visible: root.section === "buttons" && root.canWrite && root.showHardware
              width: parent.width
              title: Model.isKeyboard(device) ? "Key assignments" : "Button assignments"
              description: "Hardware remaps apply across all apps. Solaar rule handling is for external Solaar rules; leave it Regular when using assignments above."
              Text {
                visible: root.assignmentControls.length === 0
                width: parent.width
                text: "This device does not expose configurable buttons or keys."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.assignmentControls
                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(10)
                  Text {
                    width: parent.width
                    text: modelData.label
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Flow {
                    width: parent.width
                    spacing: Style.space(12)
                    MapRow {
                      visible: !!modelData.remap
                      width: parent.width < Style.space(560) || !modelData.divert ? parent.width : (parent.width - parent.spacing) / 2
                      row: modelData.remap
                      setting: root.remapSetting
                      label: "Hardware action"
                    }
                    MapRow {
                      visible: !!modelData.divert
                      width: parent.width < Style.space(560) || !modelData.remap ? parent.width : (parent.width - parent.spacing) / 2
                      row: modelData.divert
                      setting: root.divertSetting
                      label: "Solaar rule handling"
                    }
                  }
                  PanelSeparator { foreground: root.foreground }
                }
              }

            }

            SectionCard {
              visible: root.section === "device" && (!!(fnSetting || backlightSetting || platformSetting || lockSetting) && root.canWrite)
              width: parent.width
              title: "Keyboard"
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
                  width: parent.width
                  visible: true
                  label: "Disable " + (modelData && modelData.label ? modelData.label : "key")
                  info: Model.helpForSetting(root.lockSetting, "Stops this key from sending its usual scancode.")
                  checked: !!(modelData && modelData.value)
                  onClicked: if (root.lockSetting) root.writeSetting(root.lockSetting, !(modelData && modelData.value), modelData.key)
                }
              }
            }

            SectionCard {
              visible: root.section === "profiles" && (root.canWrite)
              width: parent.width
              title: "Local profiles"
              Text {
                width: parent.width
                text: "Save this device’s current settings and apply them later. Profiles stay on this computer and exclude the Easy Switch channel."
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
                  placeholderText: "Profile name, e.g. Work"
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
                  focusable: true
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
                  width: parent.width
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
                    focusable: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: mx.applyProfile(modelData.name)
                  }
                  Button {
                    id: delBtn
                    text: "Delete"
                    bordered: true
                    focusable: true
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

            Text {
              visible: root.canWrite && ((root.section === "hosts" && !hostSetting && !(device && device.hosts && device.hosts.length))
                || (root.section === "advanced" && extraSettings.length === 0)
                || (root.section === "device" && !(dpiSetting || smartSetting || smartThresholdSetting || invertSetting || hiresSetting || thumbInvertSetting || thumbModeSetting || fnSetting || backlightSetting || platformSetting || lockSetting)))
              width: parent.width
              text: root.section === "hosts" ? "This device does not expose Easy Switch controls."
                : root.section === "advanced" ? "No additional settings are exposed by this device."
                : "Use the other tabs to configure the settings this device exposes."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            SectionCard {
              visible: root.section === "advanced" && (extraSettings.length > 0 && root.canWrite)
              width: parent.width
              title: "Advanced settings"
              Repeater {
                model: extraSettings
                ExtraBlock {
                  required property var modelData
                  width: parent.width
                  setting: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  component SectionCard: Rectangle {
    id: card
    property string title: ""
    property string description: ""
    default property alias contents: cardContent.data
    implicitHeight: cardLayout.implicitHeight + Style.space(36)
    color: Qt.alpha(root.foreground, 0.025)
    border.color: Qt.alpha(root.foreground, 0.10)
    border.width: 1
    radius: Style.cornerRadius
    data: Column {
      id: cardLayout
      x: Style.space(18)
      y: Style.space(18)
      width: parent.width - Style.space(36)
      spacing: Style.space(16)
      Text {
        width: parent.width
        visible: card.title !== ""
        text: card.title
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
      }
      Text {
        visible: card.description !== ""
        width: parent.width
        text: card.description
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
      Column {
        id: cardContent
        width: parent.width
        spacing: Style.space(14)
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
    property var settingKey: undefined
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
        textFormat: Text.PlainText
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
        if (sliderBlock.setting) root.writeSetting(sliderBlock.setting, Model.snapToChoices(sliderBlock.setting, next), sliderBlock.settingKey)
      }
    }
  }

  component MapRow: Row {
    property var row: ({})
    property var setting: null
    property string label: row && row.label ? row.label : "Button"
    spacing: Style.space(8)
    Dropdown {
      width: parent.width
      label: parent.label
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
    spacing: Style.space(10)
    Text {
      visible: extraBlock.setting && (extraBlock.setting.kind === "map_choice" || extraBlock.setting.kind === "multiple_toggle")
      width: parent.width
      text: extraBlock.setting ? extraBlock.setting.label || extraBlock.setting.name : ""
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
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
    Repeater {
      model: extraBlock.setting && (extraBlock.setting.kind === "map_choice" || extraBlock.setting.kind === "multiple_toggle") ? Model.keyRows(extraBlock.setting) : []
      Column {
        required property var modelData
        width: parent.width
        MapRow {
          visible: modelData.kind === "choice"
          width: parent.width
          row: modelData
          setting: extraBlock.setting
        }
        HintedToggle {
          visible: modelData.kind === "toggle"
          width: parent.width
          label: modelData.label || modelData.key
          checked: !!modelData.value
          onClicked: root.writeSetting(extraBlock.setting, !modelData.value, modelData.key)
        }
        SliderBlock {
          visible: modelData.kind === "range"
          width: parent.width
          title: modelData.label || modelData.key
          subtitle: String(modelData.value)
          setting: Object.assign({}, modelData, { name: extraBlock.setting.name })
          settingKey: modelData.key
        }
      }
    }
  }
}
