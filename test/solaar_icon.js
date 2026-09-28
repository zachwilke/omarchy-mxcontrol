var fs = require("fs")
var path = require("path")

var fails = 0

function check(name, got, want) {
  if (got !== want) {
    fails += 1
    console.error("FAIL " + name + ": got " + JSON.stringify(got) + " want " + JSON.stringify(want))
    return
  }
  console.log("ok " + name)
}

var root = path.join(__dirname, "..")
var qml = fs.readFileSync(path.join(root, "MxIcon.qml"), "utf8")
var SOLAAR_PATH = "M 17.98 0 C 8.02 0 0 8.02 0 17.98 L 0 82.02 C 0 91.98 8.02 100 17.98 100 L 82.02 100 C 91.98 100 100 91.98 100 82.02 L 100 17.98 C 100 8.02 91.98 0 82.02 0 L 17.98 0 Z M 36.17 12.57 L 46.31 30.13 C 47.51 29.91 48.74 29.78 50 29.78 C 51.26 29.78 52.49 29.91 53.69 30.13 L 63.83 12.57 L 75.49 19.31 L 65.34 36.87 C 66.94 38.73 68.19 40.9 69.03 43.26 L 89.33 43.26 L 89.33 56.74 L 69.03 56.74 C 68.19 59.1 66.94 61.27 65.34 63.13 L 75.49 80.69 L 63.83 87.43 L 53.69 69.87 C 52.49 70.09 51.26 70.22 50 70.22 C 48.74 70.22 47.51 70.09 46.31 69.87 L 36.17 87.43 L 24.51 80.69 L 34.66 63.13 C 33.06 61.27 31.81 59.1 30.97 56.74 L 10.67 56.74 L 10.67 43.26 L 30.97 43.26 C 31.81 40.9 33.06 38.73 34.66 36.87 L 24.51 19.31 L 36.17 12.57 Z M 63.48 50 C 63.48 57.45 57.45 63.48 50 63.48 C 42.55 63.48 36.52 57.45 36.52 50 C 36.52 42.55 42.55 36.52 50 36.52 C 57.45 36.52 63.48 42.55 63.48 50 Z"

check("solaar path", qml.indexOf(SOLAAR_PATH) !== -1, true)
check("not master silhouette", qml.indexOf("MagSpeed") === -1, true)
check("vector path", qml.indexOf("PathSvg") !== -1, true)
check("keeps low-battery badge", qml.indexOf("lowBattery") !== -1, true)

var credit = ""
try { credit = fs.readFileSync(path.join(root, "THIRD_PARTY.md"), "utf8") } catch (e) { credit = "" }
check("cc by-sa", credit.indexOf("CC BY-SA 3.0") !== -1 || credit.indexOf("Creative Commons Attribution-ShareAlike 3.0") !== -1, true)
check("daniel pavel", credit.toLowerCase().indexOf("daniel pavel") !== -1, true)

if (fails) process.exit(1)
console.log(fails === 0 ? "all ok" : "")
