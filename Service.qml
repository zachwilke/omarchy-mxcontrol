import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  // Injected by the shell when this file is instantiated as the plugin's
  // shared service (manifest entryPoints.service). One instance then serves
  // every bar widget and the settings window.
  property var shell: null

  // A passive Service reads status.json and can start the daemon on demand,
  // but never runs the idle discover poller. The in-file instances inside
  // BarWidget/MxSettings stay passive fallbacks; a widget promotes its
  // fallback (passive = false) only on shells without plugin services.
  property bool passive: false

  property bool installed: false
  property bool accessible: false
  property bool refreshing: false
  property bool daemonWanted: false
  property int daemonRetryMs: 1000
  property double daemonStartedMs: 0
  property bool userPicked: false
  property bool hasHidppSnapshot: false
  property string statusText: "Checking…"
  property string message: ""
  property string lastError: ""
  property string actionStatus: ""
  property var devices: []
  property var adapters: []
  property var pendingWrites: []
  property var cmdQueue: []
  property var profiles: []
  // Per-device pointer acceleration overrides ({ deviceId: { acceleration } })
  // and the helper's report on applying them through Hyprland.
  property var pointer: ({})
  property var pointerRuntime: ({})
  property var actions: []
  property var applications: []
  property var actionRuntime: ({})
  property string selectedId: ""

  property string probedUid: ""
  readonly property string runtimeUid: {
    var uid = Quickshell.env("UID")
    if (uid && /^\d+$/.test(String(uid))) return String(uid)
    return probedUid
  }
  // Path is computed here, not via Model.js. A cached/stale JS module must
  // not be able to point FileView at the wrong file (or nowhere).
  readonly property string runtimeDir: {
    var dir = Quickshell.env("XDG_RUNTIME_DIR")
    if (dir && dir !== "") return String(dir) + "/omarchy-mx"
    return "/run/user/" + String(runtimeUid || "") + "/omarchy-mx"
  }
  readonly property string statusPath: runtimeDir + "/status.json"
  readonly property string cmdPath: runtimeDir + "/cmd.json"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 10, 3600)
  readonly property string preferredId: String(setting("selectedDevice", selectedId || ""))
  readonly property bool busy: discoverProcess.running || cmdProcess.running
  readonly property string helperPath: resolvedHelper()
  readonly property var bluetoothDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var displayDevices: mergeDevices(devices, bluetoothDevices)
  readonly property var selectedDevice: pickDevice(displayDevices, preferredId, userPicked)
  readonly property bool hidppReady: isWritable(selectedDevice)
  readonly property int batteryPercent: batteryOf(selectedDevice)
  readonly property bool batteryLow: batteryPercent >= 0 && batteryPercent <= 20
  readonly property bool online: !!(selectedDevice && selectedDevice.online !== false)
  readonly property bool hasDevice: !!selectedDevice
  property int hidppTicks: 0
  property bool peerServing: false
  property double lastStatusMs: 0
  property int progressDone: 0
  property int progressTotal: 0
  property int progressPercent: 0
  property string progressLabel: ""
  property string progressPhase: ""

  readonly property int readPercent: {
    if (progressTotal > 0 || progressPercent > 0) return Math.max(0, Math.min(100, progressPercent))
    if (!daemonWanted || hasHidppSnapshot) return 0
    return Math.min(40, hidppTicks * 8)
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function resolvedHelper() {
    var url = String(Qt.resolvedUrl("mxctl.py"))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url
  }

  function isWritable(device) {
    try {
      return Model.isWritableDevice(device)
    } catch (e) {
      return !!(device && device.readonly !== true && device.settings && device.settings.length)
    }
  }

  function pickDevice(list, preferred, picked) {
    try {
      return Model.pickDefaultDevice(list, preferred, picked)
    } catch (e) {
      return list && list.length ? list[0] : null
    }
  }

  function mergeDevices(list, blues) {
    try {
      return Model.mergeBluetoothBattery(list, blues)
    } catch (e) {
      return list
    }
  }

  function batteryOf(device) {
    try {
      return Model.batteryPercent(device)
    } catch (e) {
      if (device && device.battery && typeof device.battery.level === "number")
        return Math.round(device.battery.level)
      return -1
    }
  }

  function applyProgress(parsed) {
    var progress = parsed && parsed.progress ? parsed.progress : null
    if (!progress) return
    progressDone = progress.done || 0
    progressTotal = progress.total || 0
    progressPercent = progress.percent || 0
    progressLabel = String(progress.label || "")
    progressPhase = String(progress.phase || "")
  }

  function statusIsFresh(parsed) {
    // The serve helper stamps ts on every publish and heartbeats every 60s.
    // A snapshot without a recent ts is a cache from a previous session: it
    // may paint, but it must not claim to be live HID++ state.
    if (parsed.serving !== true) return false
    if (!parsed.ts) return false
    return (Date.now() / 1000 - parsed.ts) < 180
  }

  function applyStatus(raw, source) {
    try {
      var parsed = Model.parseStatus(raw)
      if (source === "file") lastStatusMs = Date.now()
      applyProgress(parsed)
      if (parsed.hasProfiles) profiles = parsed.profiles
      if (source === "file") {
        actions = parsed.actions || []
        actionRuntime = parsed.actionRuntime || {}
        pointer = parsed.pointer || {}
        pointerRuntime = parsed.pointerRuntime || {}
      }
      if ((parsed.hasActions || parsed.hasPointer) && !daemonWanted) ensureDaemon()
      var next = parsed.devices || []
      var nextHasHidpp = false
      for (var i = 0; i < next.length; i++) {
        if (isWritable(next[i])) nextHasHidpp = true
      }
      // Sysfs discover must not replace a live HID++ read. While serve is
      // starting, discover stdout is also ignored so a late scan cannot
      // clobber the snapshot FileView is about to load.
      if (!nextHasHidpp && source === "discover" && (hasHidppSnapshot || daemonWanted))
        return
      var merged = Model.applyPendingWrites(next, pendingWrites)
      next = merged.devices
      pendingWrites = merged.writes
      installed = parsed.installed === true
      accessible = parsed.accessible === true
      devices = next
      adapters = parsed.adapters || []
      hasHidppSnapshot = nextHasHidpp && statusIsFresh(parsed)
      if (hasHidppSnapshot) hidppTicks = 0
      if (nextHasHidpp && progressPhase === "idle") {
        progressPercent = 100
        progressDone = progressTotal
      }
      message = String(parsed.message || "")
      var picked = pickDevice(next, preferredId, userPicked)
      if (picked && picked.id) selectedId = String(picked.id)
      lastError = parsed.ok ? String(parsed.lastError || "") : parsed.message
      var name = (picked && picked.name) ? String(picked.name) : "MX"
      statusText = !installed ? "Solaar not installed"
        : (!accessible ? "Waiting for device access"
        : (!(picked && picked.id) ? "No MX device" : name))
    } catch (e) {
      lastError = String(e)
      console.warn("mx applyStatus failed:", e)
    }
  }

  function discover() {
    if (discoverProcess.running || helperPath === "") return
    refreshing = true
    discoverProcess.command = ["python3", helperPath, "discover"]
    discoverProcess.running = true
  }

  function ensureDaemon() {
    daemonWanted = true
    peerServing = false
    // Grace period before the peer-liveness timer may force a takeover.
    lastStatusMs = Date.now()
  }

  function refresh(force) {
    if (daemonWanted) {
      // Only an explicit user refresh writes a command: the daemon does a
      // full live re-read for it. Panel opens just re-load the snapshot —
      // the serve startup burst already covers the first read.
      if (force === true)
        writeCmd({ op: "refresh" })
      statusFile.reload()
      return
    }
    discover()
  }

  function selectDevice(id) {
    userPicked = true
    selectedId = String(id || "")
  }

  function refreshApplications() {
    if (!applicationsProcess.running) applicationsProcess.running = true
  }

  Process {
    id: applicationsProcess
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var clients = JSON.parse(text)
          var seen = {}
          var list = []
          for (var i = 0; i < clients.length; i++) {
            var name = String(clients[i].class || "")
            if (name && !seen["$" + name]) { seen["$" + name] = true; list.push(name) }
          }
          root.applications = list.sort()
        } catch (e) { root.applications = [] }
      }
    }
  }

  function saveAction(binding) {
    ensureDaemon()
    writeCmd({ op: "action-save", device: binding.device, binding: binding })
    actionStatus = "Saving assignment…"
    actionStatusTimer.restart()
  }

  function deleteAction(binding) {
    ensureDaemon()
    writeCmd({ op: "action-delete", device: binding.device, control: binding.control, app: binding.app })
    actionStatus = "Removing assignment…"
    actionStatusTimer.restart()
  }

  function saveProfile(name) {
    if (!selectedDevice || !name) return
    ensureDaemon()
    writeCmd({ op: "profile-save", device: String(selectedDevice.id), name: String(name) })
    actionStatus = "Saving profile…"
    actionStatusTimer.restart()
  }

  function applyProfile(name) {
    if (!selectedDevice || !name) return
    ensureDaemon()
    writeCmd({ op: "profile-apply", device: String(selectedDevice.id), name: String(name) })
    actionStatus = "Applying profile…"
    actionStatusTimer.restart()
  }

  function deleteProfile(name) {
    if (!name) return
    ensureDaemon()
    writeCmd({ op: "profile-delete", name: String(name) })
    actionStatus = "Deleted profile"
    actionStatusTimer.restart()
  }

  readonly property bool pointerAccelerated: pointerModeOf(selectedDevice) === "mac"

  function pointerModeOf(device) {
    try {
      return Model.pointerMode(pointer, device ? device.id : "")
    } catch (e) {
      return "system"
    }
  }

  function setPointerAcceleration(mode) {
    if (!selectedDevice || selectedDevice.readonly) return
    var clean = String(mode) === "mac" ? "mac" : "system"
    ensureDaemon()
    // Optimistic; the confirming snapshot carries the helper's stored value.
    try {
      pointer = Model.patchPointerMode(pointer, String(selectedDevice.id), clean)
    } catch (e) {
      console.warn("mx patchPointerMode failed:", e)
    }
    writeCmd({ op: "pointer-set", device: String(selectedDevice.id), acceleration: clean })
    actionStatus = clean === "mac" ? "Turning on macOS-style acceleration…" : "Restoring system pointer acceleration…"
    actionStatusTimer.restart()
  }

  function renameHost(index, name) {
    if (!selectedDevice || selectedDevice.readonly) return
    var clean = String(name || "").trim()
    if (clean === "") return
    ensureDaemon()
    writeCmd({ op: "rename-host", device: String(selectedDevice.id), host: Number(index), name: clean })
    // Optimistic label; the confirming snapshot re-reads names from the device.
    try {
      devices = Model.patchDeviceHostName(devices, String(selectedDevice.id), index, clean)
    } catch (e) {
      console.warn("mx patchDeviceHostName failed:", e)
    }
    actionStatus = "Renaming channel " + (Number(index) + 1) + "…"
    actionStatusTimer.restart()
  }

  function setSetting(name, value, key) {
    if (!selectedDevice || selectedDevice.readonly) return
    ensureDaemon()
    var write = {
      device: String(selectedDevice.id),
      name: String(name),
      key: key === undefined || key === null ? "" : String(key),
      value: value,
      ts: Date.now()
    }
    var nextWrites = []
    for (var i = 0; i < pendingWrites.length; i++) {
      var existing = pendingWrites[i]
      if (existing.name === write.name && existing.device === write.device && String(existing.key || "") === write.key)
        continue
      nextWrites.push(existing)
    }
    nextWrites.push(write)
    pendingWrites = nextWrites
    try {
      devices = Model.patchDeviceSetting(devices, write.device, write.name, write.value, write.key)
    } catch (e) {
      console.warn("mx patchDeviceSetting failed:", e)
    }
    writeCmd({
      op: "set",
      device: write.device,
      setting: write.name,
      key: write.key,
      value: write.value
    })
  }

  function writeCmd(cmd) {
    if (helperPath === "") return
    if (cmdProcess.running) {
      var queued = cmdQueue.slice()
      queued.push(cmd)
      cmdQueue = queued
      return
    }
    // The JSON goes over stdin, never argv: argv is world-readable through
    // /proc for the life of the process.
    cmdProcess.payload = JSON.stringify(cmd)
    cmdProcess.stdinEnabled = true
    cmdProcess.command = ["python3", helperPath, "write-cmd"]
    cmdProcess.running = true
  }

  function installSolaar() {
    Quickshell.execDetached(["omarchy-launch-tui", "omarchy", "pkg", "add", "solaar"])
    actionStatus = "Opening a terminal to install Solaar…"
    actionStatusTimer.restart()
  }

  function triggerUdev() {
    Quickshell.execDetached(["omarchy-launch-tui", "sudo", "bash", "-lc", "udevadm control --reload-rules && udevadm trigger"])
    actionStatus = "Reloading device permissions…"
    actionStatusTimer.restart()
  }

  function teardown() {
    daemonWanted = false
    daemonRestart.stop()
    peerServing = false
    cmdQueue = []
    if (discoverProcess.running) discoverProcess.running = false
    if (cmdProcess.running) cmdProcess.running = false
    if (helperPath !== "")
      Quickshell.execDetached(["python3", helperPath, "cleanup"])
  }

  Component.onCompleted: {
    if (!passive) mkdirProcess.running = true
    Qt.callLater(function() {
      if (statusFile) statusFile.reload()
      if (root.passive) return
      if (!root.hasHidppSnapshot) root.discover()
    })
  }

  // A fallback instance promoted to active duty (old shell without plugin
  // services) starts discovery it skipped at creation.
  onPassiveChanged: {
    if (passive) return
    mkdirProcess.running = true
    if (!hasHidppSnapshot && !daemonWanted) discover()
  }

  Component.onDestruction: teardown()

  onRuntimeDirChanged: if (statusFile) statusFile.reload()

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyStatus(text(), "file")
    onFileChanged: reload()
  }

  Process {
    id: uidProbe
    running: {
      var dir = Quickshell.env("XDG_RUNTIME_DIR")
      if (dir && dir !== "") return false
      var uid = Quickshell.env("UID")
      if (uid && /^\d+$/.test(String(uid))) return false
      return root.probedUid === ""
    }
    command: ["id", "-u"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var uid = String(text).trim()
        if (/^\d+$/.test(uid)) root.probedUid = uid
      }
    }
  }

  Process {
    id: mkdirProcess
    running: false
    command: ["python3", root.helperPath, "runtime-dir"]
    onExited: Qt.callLater(function() { if (statusFile) statusFile.reload() })
  }

  Timer {
    id: statusPoll
    interval: 400
    repeat: true
    // FileView watches subsequent updates. Bound this startup fallback so
    // missing Solaar/devices cannot poll the filesystem forever.
    running: root.daemonWanted && !root.hasHidppSnapshot && root.hidppTicks < 150
    onTriggered: {
      statusFile.reload()
      root.hidppTicks += 1
    }
  }

  Process {
    id: daemon
    running: root.daemonWanted && !root.peerServing && !daemonRestart.running
    command: ["python3", root.helperPath, "serve"]
    onStarted: {
      root.daemonStartedMs = Date.now()
      root.hidppTicks = 0
    }
    onExited: function(exitCode) {
      if (!root.daemonWanted) return
      if (exitCode === 3) {
        root.peerServing = true
        return
      }
      root.peerServing = false
      if (Date.now() - root.daemonStartedMs >= 60000)
        root.daemonRetryMs = 1000
      daemonRestart.interval = root.daemonRetryMs
      root.daemonRetryMs = Math.min(60000, root.daemonRetryMs * 2)
      daemonRestart.restart()
    }
  }

  Timer {
    id: daemonRestart
    onTriggered: {
      if (root.daemonWanted && !root.peerServing && !daemon.running)
        daemon.running = true
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.daemonWanted && root.peerServing
    onTriggered: {
      // The serving peer heartbeats status.json every 60s. Only try to take
      // over when those heartbeats stop; blind retries spawned a python
      // process every 15 seconds forever.
      if (Date.now() - root.lastStatusMs > 180000)
        root.peerServing = false
    }
  }

  Process {
    id: discoverProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: discoverStdout
      waitForEnd: true
      onStreamFinished: {
        root.refreshing = false
        if (text) root.applyStatus(text, "discover")
      }
    }
    onExited: root.refreshing = false
  }

  Process {
    id: cmdProcess
    property string payload: ""
    running: false
    command: []
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""
      // Closing stdin hands the helper its EOF.
      stdinEnabled = false
    }
    onExited: {
      if (root.cmdQueue.length === 0) return
      var queued = root.cmdQueue.slice()
      var next = queued.shift()
      root.cmdQueue = queued
      root.writeCmd(next)
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2800
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: plugWatch
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: !root.passive && !root.daemonWanted
    onTriggered: root.discover()
  }
}
