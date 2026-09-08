"""Isolated Quickshell integration test; never starts the real device helper.

Run with: python3 test/service_recovery.py
Requires Quickshell. No window is shown and all runtime files use a temp dir.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="mx-service-test-") as directory:
    root = Path(directory)
    for name in ("Service.qml", "Model.js"):
        shutil.copyfile(ROOT / name, root / name)
    (root / "mxctl.py").write_text('''import json, sys, time
from pathlib import Path
if sys.argv[1] == "serve":
    with Path(__file__).with_name("starts.jsonl").open("a") as output:
        output.write(json.dumps(time.monotonic()) + "\\n")
    raise SystemExit(1)
''')
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  property bool failed: false
  function check(value, message) {
    if (!value) { failed = true; console.error("FAIL: " + message) }
  }
  Service {
    id: service
    passive: true
    Component.onCompleted: Qt.callLater(function() {
      var snapshot = {ok: true, installed: true, accessible: true,
        serving: true, ts: Math.floor(Date.now() / 1000),
        devices: [{id: "fixture", online: true, settings: [{name: "dpi", value: 1000}]}]}
      service.applyStatus(JSON.stringify(snapshot), "file")
      check(service.hasHidppSnapshot, "live device snapshot")
      var empty = Object.assign({}, snapshot, {devices: []})
      service.applyStatus(JSON.stringify(empty), "discover")
      check(service.devices.length === 1, "late discovery preserves live snapshot")
      service.applyStatus(JSON.stringify(empty), "file")
      check(service.devices.length === 0 && !service.hasHidppSnapshot, "disconnect clears stale snapshot")
      service.hidppTicks = 149
      snapshot.ts = 1
      service.applyStatus(JSON.stringify(snapshot), "file")
      check(service.hidppTicks === 149 && !service.hasHidppSnapshot, "stale cache does not reset poll limit")
      service.ensureDaemon()
    })
  }
  Timer {
    interval: 4000
    running: true
    onTriggered: service.hidppTicks = 150
  }
  Timer {
    interval: 5000
    running: true
    onTriggered: check(service.hidppTicks === 150, "startup polling stops at limit")
  }
  Timer {
    interval: 7800
    running: true
    onTriggered: {
      service.teardown()
      console.log(failed ? "RECOVERY FAILED" : "RECOVERY PASSED")
      Qt.quit()
    }
  }
}
''')
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
                       QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       QT_QPA_PLATFORMTHEME="basic")
    try:
        result = subprocess.run(["quickshell", "-p", str(root), "--no-color"],
                                env=environment, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired as exc:
        raise AssertionError((exc.stdout or b"").decode() + (exc.stderr or b"").decode()) from exc
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "RECOVERY PASSED" in output, output
    assert "FAIL:" not in output and "Error:" not in output and "Binding loop" not in output, output
    starts = [json.loads(line) for line in (root / "starts.jsonl").read_text().splitlines()]
    assert len(starts) == 4, f"Expected starts at 0, 1, 3, 7 seconds; got {starts}\n{output}"
    gaps = [b - a for a, b in zip(starts, starts[1:])]
    assert all(gap >= minimum for gap, minimum in zip(gaps, (0.9, 1.9, 3.9))), gaps
    print("Service recovery passed: disconnect, bounded polling, crash backoff", [round(x, 2) for x in gaps])
