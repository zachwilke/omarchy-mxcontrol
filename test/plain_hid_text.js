var Model = require("../Model.js")

var fails = 0

function check(name, got, want) {
  if (got !== want) {
    fails += 1
    console.error("FAIL " + name + ": got " + JSON.stringify(got) + " want " + JSON.stringify(want))
    return
  }
  console.log("ok " + name)
}

check("mx master", Model.plainHidText("MX Master 3S"), "MX Master 3S")
check("bolt receiver", Model.plainHidText("Bolt Receiver"), "Bolt Receiver")
check("unifying", Model.plainHidText("Unifying Receiver"), "Unifying Receiver")
check("empty", Model.plainHidText(""), "")
check("null", Model.plainHidText(null), "")
check("undefined", Model.plainHidText(undefined), "")
check("img tag", Model.plainHidText('<img src="https://evil">'), "&lt;img src=\"https://evil\"&gt;")
check("amp first", Model.plainHidText("A & B <C>"), "A &amp; B &lt;C&gt;")
check("display name", Model.hidDisplayName({ name: "MX Master 3S" }, "MX"), "MX Master 3S")
check("display fallback", Model.hidDisplayName({}, "Receiver"), "Receiver")
check("display missing", Model.hidDisplayName(null, "MX"), "MX")
check("display markup", Model.hidDisplayName({ name: '<img src="https://evil">' }, "MX"), "&lt;img src=\"https://evil\"&gt;")
check("battery percent", Model.batteryLabel({ battery: { level: 84 } }), "84%")
check("battery text markup", Model.batteryLabel({ battery: { text: '<img src="https://evil">' } }), "&lt;img src=\"https://evil\"&gt;")
check("runtime xdg", Model.runtimeDir("/run/user/1000", "999"), "/run/user/1000/omarchy-mx")
check("runtime fallback", Model.runtimeDir("", "1000"), "/run/user/1000/omarchy-mx")
check("runtime null xdg", Model.runtimeDir(null, "42"), "/run/user/42/omarchy-mx")
check("progress half", Model.parseProgress({ done: 1, total: 2 }).percent, 50)
check("progress empty", Model.parseProgress(null).percent, 0)
check("status progress", Model.parseStatus('{"ok":true,"progress":{"done":1,"total":4,"percent":25}}').progress.percent, 25)
var board = Model.bindKeyLayout(Model.mxKeysLayout(), {
  keys: [{ key: "199", label: "Brightness Down", value: 0 }, { key: "233", label: "Volume Up", value: 1 }]
})
check("keyboard hits", board.hits, 2)
check("keyboard diverted", Model.keyIsDiverted({ value: 1 }), true)
check("keyboard regular", Model.keyIsDiverted({ value: 0 }), false)
function keysOf() {
  var keys = []
  for (var i = 0; i < arguments.length; i++) keys.push({ key: String(arguments[i]), label: String(arguments[i]), value: 0 })
  return { keys: keys }
}

function liveIds(board) {
  var out = []
  var rows = board && board.rows ? board.rows : []
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      var cap = rows[r][c]
      if (cap && cap.id && cap.row && !cap.decorative && !cap.spacer) out.push(String(cap.id))
    }
  }
  return out
}

function allGlyphs(board) {
  var out = []
  var rows = board && board.rows ? board.rows : []
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      var cap = rows[r][c]
      if (cap && cap.glyph && !cap.spacer) out.push(String(cap.glyph))
    }
  }
  return out.join(" ")
}

function hasLive(board, id) {
  return liveIds(board).indexOf(String(id)) !== -1
}

function frowLive(board) {
  return liveIds({ rows: board && board.rows ? [board.rows[0]] : [] })
}

check("family full", Model.keyboardFamily({ name: "MX Keys Keyboard" }, { keys: [{ key: "199" }] }), "full")
check("family mini", Model.keyboardFamily({ name: "MX Keys Mini" }, { keys: [{ key: "199" }] }), "mini")
check("family s by name", Model.keyboardFamily({ name: "MX Keys S" }, { keys: [{ key: "199" }] }), "s")
check("family s by keys", Model.keyboardFamily({ name: "MX Keys Keyboard" }, { keys: [{ key: "259" }, { key: "264" }] }), "s")
check("family business", Model.keyboardFamily({ name: "MX Keys for Business" }, keysOf("199", "259")), "s")
check("family mini business name", Model.keyboardFamily({ name: "MX Keys Mini for Business" }, keysOf("199", "259")), "mini")
check("family craft", Model.keyboardFamily({ name: "Craft Advanced Keyboard", productId: "B350" }, keysOf("199", "110")), "full")
check("family mechanical", Model.keyboardFamily({ name: "MX Mechanical" }, keysOf("199", "110", "226")), "full")
check("family mechanical mini", Model.keyboardFamily({ name: "MX Mechanical Mini" }, keysOf("199", "321")), "mini")
check("family pid original", Model.keyboardFamily({ name: "MX Keys Keyboard", productId: "B35B" }, keysOf("199", "110")), "full")
check("family mini by lock id", Model.keyboardFamily({ name: "MX Keys Keyboard" }, keysOf("199", "259", "266", "279")), "mini")
check("family mini by compact ids", Model.keyboardFamily({ name: "Keyboard" }, keysOf("199", "259", "264", "266", "284")), "mini")
check("family s by volume+smart", Model.keyboardFamily({ name: "Keyboard" }, keysOf("199", "259", "264", "284", "232", "10")), "s")

var miniBoard = Model.divertLayout({ name: "MX Keys Mini", kind: "keyboard" }, {
  keys: [{ key: "199" }, { key: "200" }, { key: "259" }, { key: "264" }, { key: "209" }]
})
check("mini layout", miniBoard && miniBoard.family, "mini")
check("mini label", miniBoard && miniBoard.familyLabel, "MX Keys Mini")
check("mini compact", !!(miniBoard && miniBoard.compact), true)
check("mini no numpad", allGlyphs(miniBoard).indexOf("nl") === -1, true)
check("mini no calc slot", allGlyphs(miniBoard).indexOf("calc") === -1, true)

var fullKeys = keysOf(
  "209", "210", "211", "199", "200", "224", "225", "110", "226", "227",
  "228", "229", "230", "231", "232", "233", "10", "191", "234", "111", "236", "235"
)
var fullBoard = Model.divertLayout({ name: "MX Keys Keyboard", kind: "keyboard", productId: "B35B", codename: "MX Keys" }, fullKeys)
check("full layout", fullBoard && fullBoard.family, "full")
check("full label", fullBoard && fullBoard.familyLabel, "MX Keys")
check("full compact", !!(fullBoard && fullBoard.compact), false)
check("full desk live", hasLive(fullBoard, "110"), true)
check("full backlight live", hasLive(fullBoard, "226"), true)
check("full no dictation", hasLive(fullBoard, "259"), false)
check("full no numpad", allGlyphs(fullBoard).indexOf("nl") === -1, true)
check("full calc live", hasLive(fullBoard, "10"), true)
check("full frow desk", frowLive(fullBoard).indexOf("110") !== -1, true)
check("full frow lock", frowLive(fullBoard).indexOf("111") !== -1, true)
check("full frow host1", frowLive(fullBoard).indexOf("209") !== -1, true)
function frowGlyphs(board) {
  var row = board && board.rows && board.rows[0] ? board.rows[0] : []
  var out = []
  for (var i = 0; i < row.length; i++) if (row[i] && row[i].glyph) out.push(String(row[i].glyph))
  return out.join(" ")
}
check("full f1", frowGlyphs(fullBoard).indexOf("F1") !== -1, true)
check("full f5", frowGlyphs(fullBoard).indexOf("F5") !== -1, true)
check("full f12", frowGlyphs(fullBoard).indexOf("F12") !== -1, true)

var sKeys = keysOf(
  "209", "210", "211", "199", "200", "224", "225", "259", "264", "284",
  "228", "229", "230", "231", "232", "233", "10", "266", "234", "111", "236", "235"
)
var sBoard = Model.divertLayout({ name: "MX Keys S", kind: "keyboard" }, sKeys)
check("s layout", sBoard && sBoard.family, "s")
check("s label", sBoard && sBoard.familyLabel, "MX Keys S")
check("s dictation live", hasLive(sBoard, "259"), true)
check("s emoji live", hasLive(sBoard, "264"), true)
check("s mic live", hasLive(sBoard, "284"), true)
check("s no desk", hasLive(sBoard, "110"), false)
check("s f6", frowGlyphs(sBoard).indexOf("F6") !== -1, true)
check("s frow dictation", frowLive(sBoard).indexOf("259") !== -1, true)
check("s frow no desk", frowLive(sBoard).indexOf("110") === -1, true)
check("s no numpad", allGlyphs(sBoard).indexOf("nl") === -1, true)
check("s capture 266", hasLive(sBoard, "266"), true)

var bizBoard = Model.divertLayout({ name: "MX Keys for Business", kind: "keyboard" }, sKeys)
check("business family", bizBoard && bizBoard.family, "s")
check("business label", bizBoard && bizBoard.familyLabel, "MX Keys for Business")

var miniKeys = keysOf(
  "209", "210", "211", "199", "200", "224", "225", "259", "264", "266", "284",
  "228", "229", "230", "231", "234", "279", "236", "235"
)
var miniFull = Model.divertLayout({ name: "MX Keys Mini", kind: "keyboard" }, miniKeys)
check("mini screenshot in frow", frowLive(miniFull).indexOf("266") !== -1, true)
check("mini lock 279", hasLive(miniFull, "279"), true)
check("mini no volume in frow", frowLive(miniFull).indexOf("232") === -1, true)

var mechMini = Model.divertLayout({ name: "MX Mechanical Mini", kind: "keyboard" }, keysOf("199", "200", "259", "321", "209", "210"))
check("mech mini family", mechMini && mechMini.family, "mini")
check("mech mini label", mechMini && mechMini.familyLabel, "MX Mechanical Mini")
check("mech mini play 321", hasLive(mechMini, "321"), true)

var craftBoard = Model.divertLayout({ name: "Craft Advanced Keyboard", kind: "keyboard", productId: "B350" }, fullKeys)
check("craft family", craftBoard && craftBoard.family, "full")
check("craft label", craftBoard && craftBoard.familyLabel, "Craft")

function spotIds(board) {
  var out = []
  var spots = board && board.spots ? board.spots : []
  for (var i = 0; i < spots.length; i++) {
    if (spots[i] && spots[i].id && (spots[i].row || spots[i].remap)) out.push(String(spots[i].id))
  }
  return out
}
function hasSpot(board, id) {
  return spotIds(board).indexOf(String(id)) !== -1
}

check("status lastError strips", Model.parseStatus('{"ok":true,"lastError":"<img src=\\"https://evil\\"> offline"}').lastError, "&lt;img src=\"https://evil\"&gt; offline")
check("status message strips", Model.parseStatus('{"ok":false,"message":"<b>nope</b>"}').message, "&lt;b&gt;nope&lt;/b&gt;")
check("progress label strips", Model.parseProgress({ done: 1, total: 2, label: '<img src="https://evil">' }).label, "&lt;img src=\"https://evil\"&gt;")
check("mouse family label name", Model.mouseFamilyLabel("master", { name: "MX Master 3S" }), "MX Master 3S")
check("mouse family label markup", Model.mouseFamilyLabel("master", { name: '<img src="https://evil">' }), "&lt;img src=\"https://evil\"&gt;")
check("mouse family label fallback", Model.mouseFamilyLabel("anywhere", {}), "MX Anywhere")
check("mouse family master", Model.mouseFamily({ name: "MX Master 3S", productId: "B034" }), "master")
check("mouse family anywhere", Model.mouseFamily({ name: "MX Anywhere 3" }), "anywhere")
check("mouse family vertical", Model.mouseFamily({ name: "MX Vertical", productId: "B020" }), "vertical")
check("mouse family lift", Model.mouseFamily({ name: "Lift Mouse" }), "lift")
check("mouse family ergo", Model.mouseFamily({ name: "MX Ergo" }), "ergo")

var masterDivert = keysOf("82", "83", "86", "195", "196")
var masterRemap = keysOf("80", "81", "82", "83", "86", "195", "196")
var masterBoard = Model.divertLayout(
  { name: "MX Master 3S", kind: "mouse", productId: "B034" },
  masterDivert,
  masterRemap
)
check("master view", masterBoard && masterBoard.view, "mouse")
check("master family", masterBoard && masterBoard.family, "master")
check("master label", masterBoard && masterBoard.familyLabel, "MX Master 3S")
check("master hull", masterBoard && masterBoard.hull, "master")
check("master gesture", hasSpot(masterBoard, "195"), true)
check("master smartshift", hasSpot(masterBoard, "196"), true)
check("master left remap", hasSpot(masterBoard, "80"), true)
check("master no rows", !!(masterBoard && masterBoard.rows && masterBoard.rows.length === 0), true)
check("master leftover markup", (function() {
  var dirty = Model.divertLayout(
    { name: "MX Master 3S", kind: "mouse", productId: "B034" },
    { keys: masterDivert.keys.concat([{ key: "999", label: '<img src="https://evil">' }]) },
    masterRemap
  )
  var extras = dirty && dirty.extras ? dirty.extras : []
  for (var i = 0; i < extras.length; i++) {
    if (String(extras[i].id) === "999") return extras[i].title
  }
  return ""
})(), "&lt;img src=\"https://evil\"&gt;")
check("master dirty family label", Model.divertLayout(
  { name: '<img src="https://evil">', kind: "mouse", productId: "B034" },
  masterDivert,
  masterRemap
).familyLabel, "&lt;img src=\"https://evil\"&gt;")

var anywhereBoard = Model.divertLayout({ name: "MX Anywhere 3", kind: "mouse" }, keysOf("82", "83", "86", "237"))
check("anywhere view", anywhereBoard && anywhereBoard.family, "anywhere")
check("anywhere hull", anywhereBoard && anywhereBoard.hull, "anywhere")
check("anywhere dpi", hasSpot(anywhereBoard, "237"), true)
check("anywhere no gesture", hasSpot(anywhereBoard, "195"), false)

var verticalBoard = Model.divertLayout({ name: "MX Vertical", kind: "mouse" }, keysOf("80", "81", "82", "83", "86"))
check("vertical hull", verticalBoard && verticalBoard.hull, "vertical")

var ergoBoard = Model.divertLayout({ name: "MX Ergo", kind: "mouse" }, keysOf("80", "81", "82"))
check("ergo hull", ergoBoard && ergoBoard.hull, "ergo")

if (fails) {
  console.error(fails + " failed")
  process.exit(1)
}
console.log("all passed")
