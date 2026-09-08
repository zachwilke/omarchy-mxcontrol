import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: editor
  property var service: null
  property var device: null
  readonly property string deviceId: device ? String(device.id) : ""
  property var controls: []
  property string control: ""
  property string scope: ""
  property bool customScope: false
  property bool recording: false
  property string mode: "shortcut"
  property string steps: "CTRL+c"
  property var directions: ({ up: "", down: "", left: "", right: "" })
  readonly property var supported: controls.filter(function(c) { return !!c.divert })
  readonly property var selected: supported.filter(function(c) { return c.key === editor.control })[0] || null
  readonly property bool gestureCapable: !!selected && (selected.divert.choices || []).some(function(c) { return Number(c.id) === 2 })
  readonly property var assignments: (service.actions || []).filter(function(r) { return device && r.device === String(device.id) })
  readonly property color muted: Qt.alpha(Color.foreground, 0.65)
  readonly property bool active: device && ((service.actionRuntime || {}).activeDevices || []).indexOf(String(device.id)) !== -1
  spacing: Style.space(16)
  onDeviceIdChanged: { control = ""; scope = ""; customScope = false; recording = false; mode = "shortcut"; steps = "CTRL+c"; directions = ({ up: "", down: "", left: "", right: "" }) }

  Keys.onPressed: function(event) {
    if (!recording) return
    event.accepted = true
    if (event.key === Qt.Key_Escape) { recording = false; return }
    if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].indexOf(event.key) >= 0) return
    var special = ({})
    special[Qt.Key_Return] = "Return"; special[Qt.Key_Enter] = "Return"
    special[Qt.Key_Tab] = "Tab"; special[Qt.Key_Backspace] = "BackSpace"
    special[Qt.Key_Delete] = "Delete"; special[Qt.Key_Space] = "space"
    special[Qt.Key_Left] = "Left"; special[Qt.Key_Right] = "Right"
    special[Qt.Key_Up] = "Up"; special[Qt.Key_Down] = "Down"
    special[Qt.Key_Home] = "Home"; special[Qt.Key_End] = "End"
    special[Qt.Key_PageUp] = "Prior"; special[Qt.Key_PageDown] = "Next"
    var key = special[event.key] || ""
    if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) key = "F" + (event.key - Qt.Key_F1 + 1)
    if (!key && ((event.key >= Qt.Key_A && event.key <= Qt.Key_Z) || (event.key >= Qt.Key_0 && event.key <= Qt.Key_9))) key = String.fromCharCode(event.key).toLowerCase()
    if (!key) return
    var mods = []
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    steps = mods.concat([key]).join("+")
    recording = false
  }

  function edit(row) {
    control = row.control
    scope = row.app
    customScope = !!row.app && (service.applications || []).indexOf(row.app) < 0
    mode = row.mode
    steps = row.shortcut
    directions = Object.assign({ up: "", down: "", left: "", right: "" }, row.gestures)
  }

  Text {
    width: parent.width
    text: "Shortcuts & gestures"
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }
  Text {
    width: parent.width
    text: "Give a button a shortcut, a sequence of shortcuts, or four directional gestures. Add an app override after saving its All apps action."
    color: editor.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
  Text {
    visible: !!((service.actionRuntime || {}).error)
    width: parent.width
    text: (service.actionRuntime || {}).error || ""
    textFormat: Text.PlainText
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
  Text {
    visible: supported.length === 0
    width: parent.width
    text: "This device does not expose buttons that can run software actions."
    color: editor.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
  Column {
    visible: editor.supported.length > 0
    width: parent.width
    spacing: Style.space(14)
    Dropdown {
      width: parent.width
      label: "Control"
      value: editor.control
      options: [{ value: "", label: "Choose a button or key" }].concat(editor.supported.map(function(c) { return { value: c.key, label: c.label } }))
      onChanged: function(value) { editor.control = value; if (!editor.gestureCapable) editor.mode = "shortcut" }
    }
    Dropdown {
      width: parent.width
      label: "Application"
      value: editor.customScope ? "__custom__" : editor.scope
      options: [{value: "", label: "All apps"}].concat((service.applications || []).map(function(a) { return {value: a, label: a} })).concat([{value: "__custom__", label: "Another app…"}])
      onChanged: function(value) { editor.customScope = value === "__custom__"; editor.scope = editor.customScope ? "" : value }
    }
    TextField {
      visible: editor.customScope
      width: parent.width
      placeholderText: "Hyprland app class, e.g. chromium"
      text: editor.scope
      onTextEdited: editor.scope = text
      Accessible.name: "Application class; leave blank for All apps"
    }
    ButtonGroup {
      width: parent.width
      options: editor.gestureCapable ? [{value: "shortcut", label: "Shortcut / sequence"}, {value: "gesture", label: "Directional gestures"}] : [{value: "shortcut", label: "Shortcut / sequence"}]
      value: editor.mode
      onChanged: function(value) { editor.mode = value }
    }
    Text {
      text: editor.mode === "gesture" ? "Click action" : "Shortcut steps"
      color: editor.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    TextArea {
      width: parent.width
      implicitHeight: Style.space(76)
      text: editor.steps
      onTextChanged: if (activeFocus) editor.steps = text
      placeholderText: "CTRL+c\nOne shortcut per line, up to 8 steps"
      wrapMode: TextEdit.Wrap
      color: Color.foreground
      placeholderTextColor: editor.muted
      selectionColor: Qt.alpha(Color.accent, 0.35)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      padding: Style.space(12)
      background: Rectangle {
        color: Qt.alpha(Color.foreground, 0.035)
        border.color: parent.activeFocus ? Color.accent : Qt.alpha(Color.foreground, 0.18)
        radius: Style.cornerRadius
      }
      Accessible.name: "Shortcut steps"
    }
    Button {
      text: editor.recording ? "Press a shortcut · Esc to cancel" : "Record shortcut"
      bordered: true
      focusable: true
      selected: editor.recording
      onClicked: { editor.recording = !editor.recording; if (editor.recording) editor.forceActiveFocus() }
    }
    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: [{label: "Copy", value: "CTRL+c"}, {label: "Paste", value: "CTRL+v"}, {label: "Undo", value: "CTRL+z"}, {label: "Back", value: "ALT+Left"}, {label: "Next tab", value: "CTRL+Tab"}]
        Button {
          required property var modelData
          text: modelData.label
          bordered: true
          focusable: true
          onClicked: editor.steps = modelData.value
        }
      }
    }
    Grid {
      visible: editor.mode === "gesture"
      width: parent.width
      columns: width > Style.space(500) ? 2 : 1
      spacing: Style.space(10)
      Repeater {
        model: ["up", "down", "left", "right"]
        Column {
          required property string modelData
          width: (parent.width - (parent.columns - 1) * parent.spacing) / parent.columns
          spacing: Style.space(5)
          Text {
            text: "Move " + modelData
            color: editor.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: editor.directions[modelData] || ""
            placeholderText: "No action"
            onTextEdited: {
              var next = Object.assign({}, editor.directions)
              next[modelData] = text
              editor.directions = next
            }
            Accessible.name: "Gesture " + modelData
          }
        }
      }
    }
    Row {
      width: parent.width
      spacing: Style.space(12)
      Button {
        text: "Save assignment"
        bordered: true
        focusable: true
        enabled: !!editor.control && editor.steps.trim() !== "" && service.hidppReady
        opacity: enabled ? 1 : 0.4
        onClicked: service.saveAction({ device: String(device.id), control: editor.control, app: editor.scope.trim(), mode: editor.mode, shortcut: editor.steps, gestures: editor.directions })
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: editor.active ? "● Actions running" : "Starts when saved"
        color: editor.active ? Color.accent : editor.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
  Text {
    width: parent.width
    text: "Shortcuts go to the focused app. Gestures run on release; small movements count as a click. Leave a direction empty to do nothing."
    color: editor.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  Repeater {
    model: editor.assignments
    Rectangle {
      required property var modelData
      width: parent.width
      height: savedRow.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Qt.alpha(Color.foreground, 0.035)
      Row {
        id: savedRow
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        spacing: Style.space(8)
        Column {
          width: parent.width - editButton.width - removeButton.width - parent.spacing * 2
          spacing: Style.space(4)
          Text {
            width: parent.width
            text: (editor.controls.filter(function(c) { return c.key === modelData.control })[0] || {}).label || modelData.control
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            text: (modelData.app || "All apps") + " · " + (modelData.mode === "gesture" ? "Gestures" : modelData.shortcut.replace(/\n/g, " → "))
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: editor.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Button { id: editButton; text: "Edit"; focusable: true; onClicked: editor.edit(modelData) }
        Button { id: removeButton; text: "Remove"; focusable: true; tooltipText: modelData.app ? "Remove this app override" : "Remove this action and its app overrides"; onClicked: service.deleteAction(modelData) }
      }
    }
  }
}
