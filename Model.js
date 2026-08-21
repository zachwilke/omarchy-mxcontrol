var HID_AMP_RE = /&/g
var HID_LT_RE = /</g
var HID_GT_RE = />/g

function emptyProgress() {
  return { done: 0, total: 0, percent: 0, label: "", phase: "" }
}

function parseProgress(raw) {
  var data = raw && typeof raw === "object" ? raw : {}
  var total = parseInt(String(data.total !== undefined ? data.total : 0), 10)
  var done = parseInt(String(data.done !== undefined ? data.done : 0), 10)
  var percent = parseInt(String(data.percent !== undefined ? data.percent : 0), 10)
  if (!isFinite(total) || total < 0) total = 0
  if (!isFinite(done) || done < 0) done = 0
  if (total > 0 && done > total) done = total
  if (!isFinite(percent) || percent < 0) percent = 0
  if (percent > 100) percent = 100
  if (total > 0 && data.percent === undefined)
    percent = Math.round(100 * done / total)
  return {
    done: done,
    total: total,
    percent: percent,
    label: data.label ? plainHidText(data.label) : "",
    phase: data.phase ? String(data.phase) : ""
  }
}

function emptyStatus(message) {
  return {
    ok: false,
    installed: false,
    accessible: false,
    serving: false,
    ts: 0,
    message: message || "",
    devices: [],
    adapters: [],
    progress: emptyProgress(),
    hasProfiles: false,
    profiles: []
  }
}

// HID identity is untrusted peripheral data. Escape so leftover RichText /
// AutoText / StyledText surfaces cannot treat a crafted name as markup.
function plainHidText(value) {
  if (value === undefined || value === null) return ""
  var text = String(value)
  if (text.indexOf("&") === -1 && text.indexOf("<") === -1 && text.indexOf(">") === -1)
    return text
  return text.replace(HID_AMP_RE, "&amp;").replace(HID_LT_RE, "&lt;").replace(HID_GT_RE, "&gt;")
}

function hidDisplayName(item, fallback) {
  var raw = ""
  if (item && item.name) raw = item.name
  else if (fallback !== undefined && fallback !== null) raw = fallback
  return plainHidText(raw)
}

// Kept for tests and the Python helper. Service.qml computes this itself so
// FileView cannot break if this module is cached stale.
function runtimeDir(xdgRuntimeDir, uid) {
  var dir = xdgRuntimeDir === undefined || xdgRuntimeDir === null ? "" : String(xdgRuntimeDir)
  if (dir !== "") return dir + "/omarchy-mx"
  return "/run/user/" + String(uid || "") + "/omarchy-mx"
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return emptyStatus("No response from mxctl")
  try {
    var data = JSON.parse(text)
    return {
      ok: data.ok !== false,
      installed: data.installed === true,
      accessible: data.accessible === true,
      serving: data.serving === true,
      ts: isFinite(Number(data.ts)) ? Number(data.ts) : 0,
      message: plainHidText(data.message || ""),
      lastError: plainHidText(data.lastError || ""),
      devices: Array.isArray(data.devices) ? data.devices : [],
      adapters: Array.isArray(data.adapters) ? data.adapters : [],
      progress: parseProgress(data.progress),
      hasProfiles: Array.isArray(data.profiles),
      profiles: Array.isArray(data.profiles) ? data.profiles : []
    }
  } catch (e) {
    return emptyStatus("Failed to parse device status")
  }
}

function settingNames(aliases) {
  return aliases || []
}

function settingByNames(device, names) {
  var settings = device && device.settings ? device.settings : []
  var wanted = {}
  for (var i = 0; i < names.length; i++) wanted[String(names[i]).toLowerCase()] = true
  for (var j = 0; j < settings.length; j++) {
    var item = settings[j]
    if (item && wanted[String(item.name || "").toLowerCase()]) return item
  }
  return null
}

function settingValue(setting) {
  if (!setting) return undefined
  var value = setting.value
  if (value && typeof value === "object" && value.name !== undefined && value.id !== undefined)
    return value
  return value
}

function numericValue(setting, fallback) {
  var value = settingValue(setting)
  if (value && typeof value === "object" && value.id !== undefined) return Number(value.id)
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function reportRateLabel(value) {
  // Solaar stores the report rate as the polling interval in milliseconds
  // (1 means 1000 Hz). Convert so the UI can talk in Hz like Logitech does.
  var ms = Number(value)
  if (!isFinite(ms) || ms <= 0) return ""
  var hz = Math.round(1000 / ms)
  return hz >= 1000 ? ((hz / 1000) + " kHz") : (hz + " Hz")
}

function boolValue(setting) {
  var value = settingValue(setting)
  if (value && typeof value === "object" && value.id !== undefined) return Number(value.id) !== 0
  return value === true || value === 1 || value === "true"
}

function choiceName(setting) {
  var value = settingValue(setting)
  if (value && typeof value === "object" && value.name) return String(value.name)
  if (setting && setting.display) return String(setting.display)
  return value === undefined || value === null ? "" : String(value)
}

function choiceId(setting) {
  var value = settingValue(setting)
  if (value && typeof value === "object" && value.id !== undefined) return String(value.id)
  return value === undefined || value === null ? "" : String(value)
}

function hostActiveIndex(device) {
  var setting = settingByNames(device, ["change-host", "change_host"])
  if (!setting) return -1
  var value = settingValue(setting)
  if (value && typeof value === "object" && value.id !== undefined) return Number(value.id)
  var n = Number(value)
  return isFinite(n) ? n : -1
}

function isMouse(device) {
  if (!device) return false
  var kind = String(device.kind || "").toLowerCase()
  if (kind === "mouse" || kind === "trackball" || kind === "touchpad") return true
  return /master|mouse|anywhere|vertical|lift|ergo|trackball/.test(String(device.name || "").toLowerCase())
}

function isKeyboard(device) {
  if (!device) return false
  var kind = String(device.kind || "").toLowerCase()
  if (kind.indexOf("key") !== -1) return true
  return /key|mechanical/.test(String(device.name || "").toLowerCase())
}

function deviceMatches(device, needle) {
  if (!device || needle === undefined || needle === null || String(needle) === "") return false
  var want = String(needle).toLowerCase()
  var keys = [device.id, device.unitId, device.serial, device.path, device.name, device.codename]
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] !== undefined && keys[i] !== null && String(keys[i]).toLowerCase() === want) return true
  }
  if (device.path && String(device.path).split("/").pop().toLowerCase() === want) return true
  return false
}

function pickDefaultDevice(devices, preferredId, userPicked) {
  var list = Array.isArray(devices) ? devices : []
  if (preferredId) {
    for (var i = 0; i < list.length; i++) {
      if (deviceMatches(list[i], preferredId)) {
        if (userPicked === true || !isKeyboard(list[i])) return list[i]
        break
      }
    }
  }
  for (var j = 0; j < list.length; j++) if (isMouse(list[j]) && list[j].online !== false) return list[j]
  for (var k = 0; k < list.length; k++) if (list[k].online !== false) return list[k]
  return list.length > 0 ? list[0] : null
}

function isWritableDevice(device) {
  return !!(device && device.readonly !== true && device.online !== false && (device.settings || []).length > 0)
}

function batteryPercent(device) {
  if (!device) return -1
  var battery = device.battery
  if (battery && typeof battery.level === "number" && isFinite(battery.level)) return Math.round(battery.level)
  if (typeof device.bluetoothBattery === "number" && isFinite(device.bluetoothBattery))
    return Math.round(device.bluetoothBattery * 100)
  return -1
}

function batteryLabel(device) {
  var percent = batteryPercent(device)
  if (percent >= 0) return percent + "%"
  if (device && device.battery && device.battery.text) return plainHidText(device.battery.text)
  return ""
}

function batteryLow(device) {
  var percent = batteryPercent(device)
  return percent >= 0 && percent <= 20
}

function connectionLabel(device) {
  if (!device) return ""
  var value = String(device.connection || device.kind || "").toLowerCase()
  if (value === "bluetooth") return "Bluetooth"
  if (value === "usb") return "USB"
  if (value === "bolt") return "Bolt"
  if (value === "unifying") return "Unifying"
  if (value === "lightspeed") return "Lightspeed"
  if (value === "nano") return "Nano"
  if (value === "receiver") return "2.4 GHz"
  if (device.online === false) return "Offline"
  return device.protocol || "HID++"
}

function kindIcon(device) {
  if (isKeyboard(device)) return "󰌌"
  if (isMouse(device)) return "󰍽"
  return "󰐪"
}

function smartShiftState(setting) {
  if (!setting) return { on: false, threshold: 20, hasThreshold: false }
  if (setting.kind === "toggle") return { on: boolValue(setting), threshold: 20, hasThreshold: false }
  if (setting.kind === "range") {
    var n = numericValue(setting, 20)
    return { on: n > 1, threshold: n, hasThreshold: true }
  }
  if (setting.kind === "choice") {
    var name = choiceName(setting).toLowerCase()
    var id = choiceId(setting)
    return {
      on: id === "2" || name.indexOf("ratchet") !== -1,
      threshold: 20,
      hasThreshold: false
    }
  }
  var value = setting.value
  if (value && typeof value === "object") {
    var first = value
    if (value["1"] !== undefined) first = value["1"]
    else {
      for (var key in value) { first = value[key]; break }
    }
    if (first && typeof first === "object") {
      return {
        on: first.on !== false && first.ratchet !== true,
        threshold: Number(first.threshold !== undefined ? first.threshold : 20),
        hasThreshold: first.threshold !== undefined
      }
    }
  }
  return { on: boolValue(setting), threshold: 20, hasThreshold: false }
}

function cloneValue(value) {
  if (value === null || value === undefined) return value
  if (typeof value !== "object") return value
  if (Array.isArray(value)) {
    var list = []
    for (var i = 0; i < value.length; i++) list.push(cloneValue(value[i]))
    return list
  }
  var copy = {}
  for (var key in value) copy[key] = cloneValue(value[key])
  return copy
}

function nextToggleValue(setting) {
  if (!setting) return true
  if (setting.kind === "choice") {
    var on = smartShiftState(setting).on
    var choices = setting.choices || []
    if (choices.length >= 2) {
      var pick = on ? choices[0] : choices[1]
      if (String(pick.name || "").toLowerCase().indexOf("free") !== -1 && on)
        pick = choices[0]
      if (String(pick.name || "").toLowerCase().indexOf("ratchet") !== -1 && !on)
        pick = choices[1]
      return pick && pick.id !== undefined ? pick.id : (on ? 1 : 2)
    }
    return on ? 1 : 2
  }
  return !boolValue(setting)
}

function patchedSettingValue(setting, value, key) {
  var item = cloneValue(setting)
  if (key !== undefined && key !== null && String(key) !== "" && item.keys) {
    for (var i = 0; i < item.keys.length; i++) {
      if (String(item.keys[i].key) === String(key)) {
        item.keys[i].value = value
        break
      }
    }
    return item
  }
  item.value = value
  if (value && typeof value === "object" && value.name) item.display = String(value.name)
  else item.display = String(value)
  return item
}

function scalar(value) {
  if (value && typeof value === "object") {
    if (value.id !== undefined) return String(value.id)
    if (value.name !== undefined) return String(value.name)
    if (value.value !== undefined) return scalar(value.value)
  }
  if (value === true || value === "true") return "true"
  if (value === false || value === "false") return "false"
  if (value === undefined || value === null) return ""
  return String(value)
}

function valuesMatch(left, right) {
  return scalar(left) === scalar(right)
}

function settingCurrentValue(device, name, key) {
  var setting = settingByNames(device, [name])
  if (!setting) return undefined
  if (key !== undefined && key !== null && String(key) !== "" && setting.keys) {
    for (var i = 0; i < setting.keys.length; i++) {
      if (String(setting.keys[i].key) === String(key)) return setting.keys[i].value
    }
  }
  return setting.value
}

function writeIsConfirmed(devices, write) {
  var list = Array.isArray(devices) ? devices : []
  for (var i = 0; i < list.length; i++) {
    if (!deviceMatches(list[i], write.device)) continue
    return valuesMatch(settingCurrentValue(list[i], write.name, write.key), write.value)
  }
  return false
}

function applyPendingWrites(devices, writes) {
  var next = devices
  var kept = []
  var now = Date.now()
  for (var i = 0; i < writes.length; i++) {
    var write = writes[i]
    if (!write || now - Number(write.ts || 0) > 4000) continue
    if (writeIsConfirmed(next, write)) continue
    next = patchDeviceSetting(next, write.device, write.name, write.value, write.key)
    kept.push(write)
  }
  return { devices: next, writes: kept }
}

function patchDeviceHostName(devices, deviceId, hostIndex, name) {
  var list = Array.isArray(devices) ? devices : []
  var next = []
  for (var i = 0; i < list.length; i++) {
    var device = cloneValue(list[i])
    if (deviceMatches(device, deviceId) && device.hosts) {
      for (var j = 0; j < device.hosts.length; j++) {
        if (Number(device.hosts[j].index) === Number(hostIndex))
          device.hosts[j].name = plainHidText(name)
      }
    }
    next.push(device)
  }
  return next
}

function patchDeviceSetting(devices, deviceId, name, value, key) {
  var list = Array.isArray(devices) ? devices : []
  var next = []
  for (var i = 0; i < list.length; i++) {
    var device = cloneValue(list[i])
    if (deviceMatches(device, deviceId) && device.settings) {
      var settings = []
      for (var j = 0; j < device.settings.length; j++) {
        var setting = device.settings[j]
        if (setting && setting.name === name)
          settings.push(patchedSettingValue(setting, value, key))
        else
          settings.push(setting)
      }
      device.settings = settings
    }
    next.push(device)
  }
  return next
}

var SETTING_HELP = {
  "dpi": "How far the pointer travels, in 50 DPI steps from 200 to 8000. 8K is the sensor maximum (8000 DPI).",
  "dpi-extended": "How far the pointer travels. 8K is the sensor maximum when the device supports 8000 DPI.",
  "dpi_extended": "How far the pointer travels. 8K is the sensor maximum when the device supports 8000 DPI.",
  "report_rate": "How often the mouse reports movement, shown as Hz. Devices store the polling interval in milliseconds, so 1 ms is 1000 Hz.",
  "report-rate": "How often the mouse reports movement, shown as Hz. Devices store the polling interval in milliseconds, so 1 ms is 1000 Hz.",
  "report_rate_extended": "How often the mouse reports movement, shown as Hz. Devices store the polling interval in milliseconds, so 1 ms is 1000 Hz.",
  "pointer_speed": "A software pointer-speed multiplier on top of the hardware DPI.",
  "pointer-speed": "A software pointer-speed multiplier on top of the hardware DPI.",
  "scroll-ratchet": "When on, the MagSpeed wheel clicks at slow speeds and free-spins when you scroll quickly. Off is always free-spin.",
  "smartshift": "When on, the MagSpeed wheel clicks at slow speeds and free-spins when you scroll quickly.",
  "smart-shift": "How fast you must scroll before the wheel leaves ratchet mode. Lower switches to free-spin sooner.",
  "hires-smooth-invert": "Flips the vertical wheel so rolling away from you scrolls the opposite direction.",
  "scroll-invert": "Flips the vertical wheel so rolling away from you scrolls the opposite direction.",
  "hires-smooth-resolution": "Sends finer scroll steps. Feels smoother in apps that support high-resolution scrolling.",
  "hires-scroll-mode": "Sends wheel motion as HID++ events so Solaar rules can handle them instead of normal scroll.",
  "thumb-scroll-invert": "Flips the side thumb wheel so rolling it one way scrolls the opposite direction.",
  "thumb-scroll-mode": "Sends thumb-wheel motion as HID++ events for Solaar rules instead of normal horizontal scroll.",
  "change-host": "Jump to another paired computer. Same action as the channel slider on the bottom of the device.",
  "change_host": "Jump to another paired computer. Same action as the channel slider on the bottom of the device.",
  "reprogrammable-keys": "Changes what this button sends. The first action in the list is the factory default.",
  "divert-keys": "Regular is a normal click. Divert sends HID++ so this window or Solaar rules can handle the press — that is how gesture-button actions work on Linux.",
  "disable-keyboard-keys": "Stops this key from sending its usual scancode. Useful to mute Caps Lock or the Win key.",
  "multiplatform": "Which shortcut set the keyboard sends: Windows, macOS, or iPad-style.",
  "fn-swap": "When on, the F-keys send media and special actions by default. Hold Fn for F1–F12.",
  "fn_swap": "When on, the F-keys send media and special actions by default. Hold Fn for F1–F12.",
  "backlight": "Keyboard lighting on or off.",
  "backlight_level": "How bright the keyboard backlight is.",
  "backlight-level": "How bright the keyboard backlight is."
}

function choiceNumericValues(setting) {
  var choices = setting && setting.choices ? setting.choices : []
  var nums = []
  for (var i = 0; i < choices.length; i++) {
    var item = choices[i]
    var n = Number(item && item.id !== undefined ? item.id : (item && item.name !== undefined ? item.name : item))
    if (isFinite(n)) nums.push(n)
  }
  nums.sort(function(a, b) { return a - b })
  return nums
}

function sliderBounds(setting) {
  if (!setting) return { min: 0, max: 100, step: 1 }
  if (setting.kind === "range" && setting.min !== undefined && setting.min !== null)
    return { min: Number(setting.min), max: Number(setting.max), step: 1 }
  var nums = choiceNumericValues(setting)
  if (nums.length === 0) return { min: 0, max: 100, step: 1 }
  var step = nums.length > 1 ? nums[1] - nums[0] : 1
  return { min: nums[0], max: nums[nums.length - 1], step: step > 0 ? step : 1, values: nums }
}

function snapToChoices(setting, value) {
  var nums = choiceNumericValues(setting)
  if (nums.length === 0) return Math.round(value)
  var best = nums[0]
  var bestD = Math.abs(value - best)
  for (var i = 1; i < nums.length; i++) {
    var d = Math.abs(value - nums[i])
    if (d < bestD) {
      best = nums[i]
      bestD = d
    }
  }
  return best
}

function dpiPresets(setting) {
  var wanted = [400, 800, 1200, 1600, 3200, 8000]
  var nums = choiceNumericValues(setting)
  if (nums.length === 0) {
    var bounds = sliderBounds(setting)
    nums = []
    for (var n = bounds.min; n <= bounds.max; n += Math.max(1, bounds.step)) nums.push(n)
  }
  var have = {}
  for (var i = 0; i < nums.length; i++) have[nums[i]] = true
  var options = []
  for (var j = 0; j < wanted.length; j++) {
    if (!have[wanted[j]]) continue
    options.push({
      value: String(wanted[j]),
      label: wanted[j] >= 8000 ? "8K" : String(wanted[j])
    })
  }
  return options
}

function keyCap(id, glyph, title, span) {
  return { id: String(id), glyph: glyph, title: title, span: span || 1, decorative: false, spacer: false }
}

function deadCap(glyph, span) {
  return { id: "", glyph: glyph || "", title: "", span: span || 1, decorative: true, spacer: false }
}

function gapCap(span) {
  return { id: "", glyph: "", title: "", span: span || 1, decorative: true, spacer: true }
}

var KEY_FACE = {
  "10": { glyph: "calc", title: "Calculator" },
  "110": { glyph: "Desk", title: "Show desktop" },
  "111": { glyph: "Lock", title: "Lock" },
  "191": { glyph: "cam", title: "Capture" },
  "199": { glyph: "B-", title: "Brightness −" },
  "200": { glyph: "B+", title: "Brightness +" },
  "209": { glyph: "1", title: "Host 1" },
  "210": { glyph: "2", title: "Host 2" },
  "211": { glyph: "3", title: "Host 3" },
  "224": { glyph: "TV", title: "Task view" },
  "225": { glyph: "AC", title: "Action center" },
  "226": { glyph: "L-", title: "Backlight −" },
  "227": { glyph: "L+", title: "Backlight +" },
  "228": { glyph: "|<", title: "Previous" },
  "229": { glyph: "play", title: "Play" },
  "230": { glyph: ">|", title: "Next" },
  "231": { glyph: "mute", title: "Mute" },
  "232": { glyph: "V-", title: "Vol −" },
  "233": { glyph: "V+", title: "Vol +" },
  "234": { glyph: "menu", title: "Menu" },
  "235": { glyph: ">", title: "Right" },
  "236": { glyph: "<", title: "Left" },
  "259": { glyph: "mic", title: "Dictation" },
  "264": { glyph: ":)", title: "Emoji" },
  "266": { glyph: "cam", title: "Capture" },
  "279": { glyph: "Del", title: "Lock / Delete" },
  "284": { glyph: "Mic", title: "Mic mute" },
  "316": { glyph: "opt", title: "Right option" },
  "321": { glyph: "play", title: "Play" },
  "436": { glyph: "AI", title: "AI" }
}

// Physical F-rows. Dim placeholders stay so the silhouette matches the model
// even when a key is not in divert-keys.
var FROW_BY_FAMILY = {
  full: ["199", "200", "224", "225", "110", "226", "227", "228", "229", "230", "231", "232", "233"],
  s: ["199", "200", "224", "225", "259", "264", "284", "228", "229", "230", "231", "232", "233"],
  mini: ["199", "200", "224", "225", "259", "264", "266", "284", "228", "229", "230", "231"]
}

var FAMILY_BY_PID = {
  "b35b": "full",
  "408a": "full",
  "b350": "full",
  "4066": "full"
}

function deviceBlob(device) {
  if (!device) return ""
  return [device.name, device.codename, device.productId, device.product_id].join(" ").toLowerCase()
}

function presentKeyIds(setting) {
  var ids = {}
  var keys = setting && setting.keys ? setting.keys : []
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] && keys[i].key !== undefined) ids[String(keys[i].key)] = keys[i]
  }
  return ids
}

function hasKeyId(ids, id) {
  return !!(ids && ids[String(id)])
}

function hasAnyKey(ids, list) {
  for (var i = 0; i < list.length; i++) {
    if (hasKeyId(ids, list[i])) return true
  }
  return false
}

function keyboardFamily(device, setting) {
  var blob = deviceBlob(device)
  var ids = presentKeyIds(setting)
  var pid = String(device && (device.productId || device.product_id) || "").toLowerCase()

  if (/\bmini\b/.test(blob)) return "mini"
  if (hasAnyKey(ids, ["279", "321", "316"])) return "mini"
  if (hasAnyKey(ids, ["259", "264", "284"]) && hasKeyId(ids, "266") &&
      !hasKeyId(ids, "232") && !hasKeyId(ids, "10") && !hasKeyId(ids, "110") && !hasKeyId(ids, "226"))
    return "mini"

  if (FAMILY_BY_PID[pid] === "full") return "full"
  if (/\bkeys[\s-]*s\b/.test(blob) || /\bbusiness\b/.test(blob)) return "s"
  if (hasAnyKey(ids, ["259", "264", "284"]) && hasAnyKey(ids, ["232", "233", "10"]) &&
      !hasKeyId(ids, "110") && !hasKeyId(ids, "226"))
    return "s"
  if (hasAnyKey(ids, ["259", "264", "284", "266"])) return "s"
  return "full"
}

function keyboardFamilyLabel(family, device) {
  var blob = deviceBlob(device)
  if (family === "mini") {
    if (blob.indexOf("mechanical") !== -1) return "MX Mechanical Mini"
    if (blob.indexOf("business") !== -1) return "MX Keys Mini for Business"
    return "MX Keys Mini"
  }
  if (family === "s") {
    if (blob.indexOf("business") !== -1) return "MX Keys for Business"
    return "MX Keys S"
  }
  if (blob.indexOf("craft") !== -1) return "Craft"
  if (blob.indexOf("mechanical") !== -1) return "MX Mechanical"
  return "MX Keys"
}

function faceFor(id, fallbackTitle) {
  var face = KEY_FACE[String(id)]
  if (face) return { glyph: face.glyph, title: face.title }
  var title = fallbackTitle || String(id)
  var glyph = title.length <= 4 ? title : title.slice(0, 3)
  return { glyph: glyph, title: title }
}

function liveCap(id, span, fallbackTitle) {
  var face = faceFor(id, fallbackTitle)
  return keyCap(id, face.glyph, face.title, span)
}

function slotCap(id, ids, span) {
  if (hasKeyId(ids, id)) return liveCap(id, span)
  var face = faceFor(id)
  return deadCap(face.glyph, span)
}

function frowSlot(id, index, ids) {
  var n = index + 1
  var face = faceFor(id)
  var glyph = n <= 12 ? ("F" + n) : (n === 13 ? "Vol+" : face.glyph)
  var title = n <= 12 ? ("F" + n + " · " + face.title) : face.title
  var cap = hasKeyId(ids, id) ? keyCap(id, glyph, title) : deadCap(glyph)
  cap.hint = n <= 12 ? face.glyph : ""
  return cap
}

function familyFrowIds(family, ids) {
  var order = (FROW_BY_FAMILY[family] || FROW_BY_FAMILY.full).slice()
  if (family === "mini" && hasKeyId(ids, "321")) {
    for (var i = 0; i < order.length; i++) {
      if (order[i] === "229") order[i] = "321"
    }
  }
  return order
}

function lockIdFor(family, ids) {
  if (family === "mini") {
    if (hasKeyId(ids, "279")) return "279"
    if (hasKeyId(ids, "111")) return "111"
    return "279"
  }
  if (hasKeyId(ids, "111")) return "111"
  if (hasKeyId(ids, "279")) return "279"
  return "111"
}

function captureIdFor(family, ids) {
  if (family === "s") {
    if (hasKeyId(ids, "266")) return "266"
    if (hasKeyId(ids, "191")) return "191"
    return "266"
  }
  if (hasKeyId(ids, "191")) return "191"
  if (hasKeyId(ids, "266")) return "266"
  return "191"
}

function mxKeysLayoutFor(family, setting) {
  var ids = presentKeyIds(setting)
  var compact = family === "mini"
  var frow = familyFrowIds(family, ids)
  var lockId = lockIdFor(family, ids)
  var fn = [deadCap("fn", compact ? 1.2 : 1.3)]
  for (var i = 0; i < frow.length; i++) fn.push(frowSlot(frow[i], i, ids))
  fn.push(gapCap(0.6))
  fn.push(slotCap(lockId, ids, 1.2))
  fn.push(slotCap("209", ids))
  fn.push(slotCap("210", ids))
  fn.push(slotCap("211", ids))

  var letters = compact
    ? [
        [deadCap("esc", 1.2), deadCap("1"), deadCap("2"), deadCap("3"), deadCap("4"), deadCap("5"), deadCap("6"), deadCap("7"), deadCap("8"), deadCap("9"), deadCap("0"), deadCap("-"), deadCap("bksp", 1.8)],
        [deadCap("tab", 1.4), deadCap("Q"), deadCap("W"), deadCap("E"), deadCap("R"), deadCap("T"), deadCap("Y"), deadCap("U"), deadCap("I"), deadCap("O"), deadCap("P"), deadCap("enter", 1.6)],
        [deadCap("caps", 1.6), deadCap("A"), deadCap("S"), deadCap("D"), deadCap("F"), deadCap("G"), deadCap("H"), deadCap("J"), deadCap("K"), deadCap("L"), deadCap(";"), deadCap("'")],
        [deadCap("shift", 2.0), deadCap("Z"), deadCap("X"), deadCap("C"), deadCap("V"), deadCap("B"), deadCap("N"), deadCap("M"), deadCap(","), deadCap("."), deadCap("shift", 2.0)]
      ]
    : [
        [deadCap("esc", 1.3), deadCap("1"), deadCap("2"), deadCap("3"), deadCap("4"), deadCap("5"), deadCap("6"), deadCap("7"), deadCap("8"), deadCap("9"), deadCap("0"), deadCap("-"), deadCap("="), deadCap("bksp", 1.7)],
        [deadCap("tab", 1.5), deadCap("Q"), deadCap("W"), deadCap("E"), deadCap("R"), deadCap("T"), deadCap("Y"), deadCap("U"), deadCap("I"), deadCap("O"), deadCap("P"), deadCap("["), deadCap("]"), deadCap("\\", 1.5)],
        [deadCap("caps", 1.8), deadCap("A"), deadCap("S"), deadCap("D"), deadCap("F"), deadCap("G"), deadCap("H"), deadCap("J"), deadCap("K"), deadCap("L"), deadCap(";"), deadCap("'"), deadCap("enter", 2.2)],
        [deadCap("shift", 2.3), deadCap("Z"), deadCap("X"), deadCap("C"), deadCap("V"), deadCap("B"), deadCap("N"), deadCap("M"), deadCap(","), deadCap("."), deadCap("/"), deadCap("shift", 2.7)]
      ]

  var captureId = captureIdFor(family, ids)
  var bottom = compact
    ? [
        deadCap("ctrl", 1.2), deadCap("fn", 1.1), deadCap("win", 1.1), deadCap("alt", 1.1), deadCap("", 4.2),
        slotCap("234", ids, 1.1),
        slotCap("236", ids),
        slotCap("235", ids)
      ]
    : [
        deadCap("ctrl", 1.3), deadCap("fn", 1.1), deadCap("win", 1.1), deadCap("alt", 1.1), deadCap("", 4.8),
        slotCap("234", ids, 1.2),
        slotCap(captureId, ids, 1.2),
        slotCap("10", ids, 1.2),
        slotCap("236", ids),
        slotCap("235", ids)
      ]

  var placed = { "209": true, "210": true, "211": true }
  placed[lockId] = true
  placed[captureId] = true
  placed["234"] = true
  placed["10"] = true
  placed["236"] = true
  placed["235"] = true
  for (var f = 0; f < frow.length; f++) placed[frow[f]] = true

  var extraRow = []
  for (var key in ids) {
    if (!placed[key]) extraRow.push(liveCap(key, 1, ids[key].label))
  }

  var rows = [fn]
  for (var r = 0; r < letters.length; r++) rows.push(letters[r])
  rows.push(bottom)
  if (extraRow.length) rows.push(extraRow)
  return rows
}

function mxKeysLayout() {
  var keys = []
  var ids = FROW_BY_FAMILY.full.concat(["209", "210", "211", "111", "234", "191", "10", "236", "235"])
  for (var i = 0; i < ids.length; i++) keys.push({ key: ids[i], label: ids[i] })
  return mxKeysLayoutFor("full", { keys: keys })
}

function mouseFamily(device) {
  var blob = deviceBlob(device)
  var pid = String(device && (device.productId || device.product_id) || "").toLowerCase()
  if (/anywhere/.test(blob)) return "anywhere"
  if (/vertical/.test(blob) || pid === "b020" || pid === "407b" || pid === "c08a") return "vertical"
  if (/\blift\b/.test(blob)) return "lift"
  if (/ergo|trackball/.test(blob)) return "ergo"
  if (/master/.test(blob) || pid === "b034" || pid === "b023" || pid === "b019" || pid === "b012" ||
      pid === "4082" || pid === "4069" || pid === "4041")
    return "master"
  return "master"
}

function mouseFamilyLabel(family, device) {
  var name = device && device.name ? plainHidText(device.name) : ""
  if (name) return name
  if (family === "anywhere") return "MX Anywhere"
  if (family === "vertical") return "MX Vertical"
  if (family === "lift") return "Lift"
  if (family === "ergo") return "MX Ergo"
  return "MX Master"
}

function mouseSpot(id, glyph, title, x, y, w, h, shape) {
  return {
    id: id === undefined || id === null ? "" : String(id),
    glyph: glyph || "",
    title: title || "",
    x: x,
    y: y,
    w: w,
    h: h,
    shape: shape || "rect",
    decorative: !id,
    spacer: false
  }
}

function dpiSpotId(ids) {
  if (hasKeyId(ids, "237")) return "237"
  if (hasKeyId(ids, "253")) return "253"
  return "237"
}

function mxMouseLayoutFor(family, setting) {
  var ids = presentKeyIds(setting)
  var dpi = dpiSpotId(ids)
  if (family === "vertical" || family === "lift") {
    return {
      hull: "vertical",
      aspect: 1.42,
      spots: [
        mouseSpot("80", "L", "Left Button", 0.30, 0.05, 0.36, 0.15),
        mouseSpot("81", "R", "Right Button", 0.66, 0.05, 0.22, 0.15),
        mouseSpot("82", "", "Middle Button", 0.58, 0.06, 0.10, 0.18, "wheel"),
        mouseSpot(dpi, "dpi", "DPI", 0.54, 0.26, 0.16, 0.07),
        mouseSpot("83", "◀", "Back Button", 0.06, 0.38, 0.20, 0.09),
        mouseSpot("86", "▶", "Forward Button", 0.06, 0.50, 0.20, 0.09)
      ]
    }
  }
  if (family === "ergo") {
    return {
      hull: "ergo",
      aspect: 0.88,
      spots: [
        mouseSpot("80", "L", "Left Button", 0.06, 0.28, 0.18, 0.30),
        mouseSpot("81", "R", "Right Button", 0.76, 0.28, 0.18, 0.30),
        mouseSpot("82", "", "Middle Button", 0.42, 0.06, 0.16, 0.12, "wheel"),
        mouseSpot("83", "◀", "Back Button", 0.10, 0.72, 0.18, 0.12),
        mouseSpot("86", "▶", "Forward Button", 0.72, 0.72, 0.18, 0.12)
      ]
    }
  }
  if (family === "anywhere") {
    return {
      hull: "anywhere",
      aspect: 1.18,
      spots: [
        mouseSpot("80", "L", "Left Button", 0.18, 0.07, 0.30, 0.22),
        mouseSpot("81", "R", "Right Button", 0.52, 0.07, 0.30, 0.22),
        mouseSpot("82", "", "Middle Button", 0.44, 0.08, 0.12, 0.22, "wheel"),
        mouseSpot(dpi, "dpi", "DPI", 0.42, 0.33, 0.16, 0.07),
        mouseSpot("83", "◀", "Back Button", 0.06, 0.40, 0.16, 0.09),
        mouseSpot("86", "▶", "Forward Button", 0.06, 0.52, 0.16, 0.09)
      ]
    }
  }
  return {
    hull: "master",
    aspect: 1.32,
    spots: [
      mouseSpot("80", "L", "Left Button", 0.32, 0.06, 0.26, 0.22),
      mouseSpot("81", "R", "Right Button", 0.62, 0.06, 0.26, 0.22),
      mouseSpot("82", "", "Middle Button", 0.54, 0.07, 0.10, 0.22, "wheel"),
      mouseSpot("196", "S", "Smart Shift", 0.53, 0.31, 0.12, 0.07),
      mouseSpot("195", "G", "Mouse Gesture Button", 0.05, 0.34, 0.22, 0.16, "pill"),
      mouseSpot("83", "◀", "Back Button", 0.07, 0.53, 0.16, 0.08),
      mouseSpot("86", "▶", "Forward Button", 0.07, 0.63, 0.16, 0.08),
      mouseSpot("", "", "Thumb wheel", 0.08, 0.74, 0.16, 0.05, "wheel")
    ]
  }
}

function indexSettingKeys(setting) {
  var byId = {}
  var byLabel = {}
  var keys = setting && setting.keys ? setting.keys : []
  for (var i = 0; i < keys.length; i++) {
    var item = keys[i]
    if (!item) continue
    if (item.key !== undefined) byId[String(item.key)] = item
    if (item.label) byLabel[String(item.label).toLowerCase()] = item
  }
  return { byId: byId, byLabel: byLabel, keys: keys }
}

function bindKeyLayout(rows, setting) {
  var index = indexSettingKeys(setting)
  var bound = []
  var hits = 0
  for (var r = 0; r < (rows || []).length; r++) {
    var row = []
    for (var c = 0; c < rows[r].length; c++) {
      var src = rows[r][c] || {}
      var cap = {
        id: src.id || "",
        glyph: src.glyph || "",
        title: src.title || "",
        hint: src.hint || "",
        span: src.span || 1,
        decorative: src.decorative === true,
        spacer: src.spacer === true,
        row: null
      }
      var match = null
      if (cap.id && index.byId[cap.id]) match = index.byId[cap.id]
      else if (cap.title && index.byLabel[String(cap.title).toLowerCase()]) match = index.byLabel[String(cap.title).toLowerCase()]
      if (match) {
        cap.row = match
        cap.id = String(match.key)
        hits += 1
      }
      row.push(cap)
    }
    bound.push(row)
  }
  return { rows: bound, hits: hits, total: index.keys.length }
}

function bindMouseLayout(view, divertSetting, remapSetting) {
  var divert = indexSettingKeys(divertSetting)
  var remap = indexSettingKeys(remapSetting)
  var spots = []
  var hits = 0
  var placed = {}
  var list = view && view.spots ? view.spots : []
  for (var i = 0; i < list.length; i++) {
    var src = list[i] || {}
    var cap = {
      id: src.id || "",
      glyph: src.glyph || "",
      title: src.title || "",
      x: Number(src.x) || 0,
      y: Number(src.y) || 0,
      w: Number(src.w) || 0.1,
      h: Number(src.h) || 0.1,
      shape: src.shape || "rect",
      decorative: src.decorative === true,
      spacer: false,
      row: null,
      remap: null
    }
    if (cap.id && divert.byId[cap.id]) {
      cap.row = divert.byId[cap.id]
      hits += 1
    }
    if (cap.id && remap.byId[cap.id]) cap.remap = remap.byId[cap.id]
    if (cap.remap && !cap.row) hits += 1
    if (cap.id) placed[cap.id] = true
    spots.push(cap)
  }
  var extras = []
  var seen = {}
  function leftover(index) {
    for (var k = 0; k < index.keys.length; k++) {
      var item = index.keys[k]
      if (!item || item.key === undefined) continue
      var id = String(item.key)
      if (placed[id] || seen[id]) continue
      seen[id] = true
      var label = plainHidText(item.label || String(id))
      extras.push({
        id: id,
        glyph: faceFor(id, label).glyph,
        title: label,
        row: divert.byId[id] || null,
        remap: remap.byId[id] || null
      })
    }
  }
  leftover(divert)
  leftover(remap)
  return {
    view: "mouse",
    rows: [],
    spots: spots,
    extras: extras,
    hits: hits,
    total: divert.keys.length || remap.keys.length,
    aspect: view && view.aspect ? view.aspect : 1.3,
    hull: view && view.hull ? view.hull : "master"
  }
}

function divertLayout(device, setting, remapSetting) {
  var hasDivert = !!(setting && setting.keys && setting.keys.length)
  var hasRemap = !!(remapSetting && remapSetting.keys && remapSetting.keys.length)
  if (isMouse(device) && (hasDivert || hasRemap)) {
    var mouseKind = mouseFamily(device)
    var boundMouse = bindMouseLayout(mxMouseLayoutFor(mouseKind, setting || remapSetting), setting, remapSetting)
    boundMouse.family = mouseKind
    boundMouse.compact = false
    boundMouse.familyLabel = mouseFamilyLabel(mouseKind, device)
    if (boundMouse.hits < 2) return null
    return boundMouse
  }
  if (!hasDivert) return null
  var family = keyboardFamily(device, setting)
  var sketch = isKeyboard(device) ? mxKeysLayoutFor(family, setting) : null
  if (!sketch) return null
  var bound = bindKeyLayout(sketch, setting)
  bound.family = family
  bound.compact = family === "mini"
  bound.view = "keyboard"
  bound.familyLabel = keyboardFamilyLabel(family, device)
  if (bound.hits < 4) return null
  return bound
}

function keyIsDiverted(row) {
  if (!row) return false
  var value = row.value
  if (value && typeof value === "object" && value.id !== undefined) value = value.id
  var n = Number(value)
  if (isFinite(n)) return n !== 0
  var name = String(row.display || value || "").toLowerCase()
  return name.indexOf("divert") !== -1 || name.indexOf("gesture") !== -1
}

function helpForSetting(setting, fallback) {
  if (setting && SETTING_HELP[setting.name]) return SETTING_HELP[setting.name]
  var desc = setting && setting.description ? String(setting.description).replace(/\s+/g, " ").trim() : ""
  if (desc) return desc
  return fallback || ""
}

function remainingSettings(device, usedNames) {
  var settings = device && device.settings ? device.settings : []
  var used = {}
  for (var i = 0; i < usedNames.length; i++) used[String(usedNames[i]).toLowerCase()] = true
  var result = []
  for (var j = 0; j < settings.length; j++) {
    var item = settings[j]
    if (!item || used[String(item.name || "").toLowerCase()]) continue
    if (item.kind === "toggle" || item.kind === "range" || item.kind === "choice" || item.kind === "map_choice" || item.kind === "multiple_toggle")
      result.push(item)
  }
  return result
}

function keyRows(setting) {
  if (!setting || !setting.keys) return []
  return setting.keys
}

function optionLabel(option) {
  if (!option) return ""
  if (typeof option === "object") return String(option.label !== undefined ? option.label : option.name || option.value || "")
  return String(option)
}

function optionValue(option) {
  if (!option) return ""
  if (typeof option === "object") {
    if (option.value !== undefined) return String(option.value)
    if (option.id !== undefined) return String(option.id)
    if (option.name !== undefined) return String(option.name)
  }
  return String(option)
}

function choiceOptions(setting) {
  var choices = setting && setting.choices ? setting.choices : []
  var options = []
  for (var i = 0; i < choices.length; i++) {
    var item = choices[i]
    options.push({
      value: item && item.id !== undefined ? String(item.id) : String(item && item.name || item),
      label: item && item.name ? String(item.name) : String(item)
    })
  }
  return options
}

function hostOptions(device) {
  var hosts = device && device.hosts ? device.hosts : []
  var options = []
  if (hosts.length > 0) {
    for (var i = 0; i < hosts.length; i++) {
      var host = hosts[i]
      options.push({
        value: String(host.index),
        label: host.name ? plainHidText(host.name) : ("Channel " + (Number(host.index) + 1)),
        tooltip: host.paired === false ? "Not paired" : ""
      })
    }
    return options
  }
  return [
    { value: "0", label: "1" },
    { value: "1", label: "2" },
    { value: "2", label: "3" }
  ]
}

function mergeBluetoothBattery(devices, btDevices) {
  var list = Array.isArray(devices) ? devices.slice() : []
  var blues = Array.isArray(btDevices) ? btDevices : []
  for (var i = 0; i < list.length; i++) {
    var device = list[i] || {}
    if (device.battery && typeof device.battery.level === "number") continue
    var name = String(device.name || "").toLowerCase()
    for (var j = 0; j < blues.length; j++) {
      var bt = blues[j]
      if (!bt || !bt.connected || !bt.batteryAvailable) continue
      var label = String(bt.deviceName || bt.name || "").toLowerCase()
      if (label && name && (label.indexOf(name) !== -1 || name.indexOf(label) !== -1)) {
        var copy = {}
        for (var key in device) copy[key] = device[key]
        copy.bluetoothBattery = Number(bt.battery)
        copy.battery = copy.battery || { level: Math.round(copy.bluetoothBattery * 100), status: "bluetooth", text: Math.round(copy.bluetoothBattery * 100) + "%" }
        list[i] = copy
        break
      }
    }
  }
  return list
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    settingByNames: settingByNames,
    isMouse: isMouse,
    isKeyboard: isKeyboard,
    pickDefaultDevice: pickDefaultDevice,
    batteryPercent: batteryPercent,
    batteryLabel: batteryLabel,
    smartShiftState: smartShiftState,
    remainingSettings: remainingSettings,
    divertLayout: divertLayout,
    bindKeyLayout: bindKeyLayout,
    mxKeysLayout: mxKeysLayout,
    keyboardFamily: keyboardFamily,
    keyboardFamilyLabel: keyboardFamilyLabel,
    mouseFamily: mouseFamily,
    mouseFamilyLabel: mouseFamilyLabel,
    keyIsDiverted: keyIsDiverted,
    patchDeviceHostName: patchDeviceHostName,
    hostOptions: hostOptions,
    plainHidText: plainHidText,
    hidDisplayName: hidDisplayName,
    runtimeDir: runtimeDir,
    parseProgress: parseProgress,
    reportRateLabel: reportRateLabel
  }
}
