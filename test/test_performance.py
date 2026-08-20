import importlib.util
import json
import os
import re
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "mxctl.py"
SERVICE = ROOT / "Service.qml"
PANEL = ROOT / "Panel.qml"
BAR = ROOT / "BarWidget.qml"
SETTINGS = ROOT / "MxSettings.qml"
MODEL = ROOT / "Model.js"


def load_mxctl():
    spec = importlib.util.spec_from_file_location("mxctl_perf", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def solaar_modules():
    names = []
    for name in sys.modules:
        if name == "logitech_receiver" or name.startswith("logitech_receiver."):
            names.append(name)
        if name == "solaar" or name.startswith("solaar."):
            names.append(name)
    return names


class PerformanceTests(unittest.TestCase):
    def setUp(self):
        self.xdg = tempfile.mkdtemp(prefix="omarchy-mx-perf-")
        self.old_xdg = os.environ.get("XDG_RUNTIME_DIR")
        self.old_config = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_RUNTIME_DIR"] = self.xdg
        os.environ["XDG_CONFIG_HOME"] = self.xdg
        self.mxctl = load_mxctl()

    def tearDown(self):
        if self.old_xdg is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self.old_xdg
        if self.old_config is None:
            os.environ.pop("XDG_CONFIG_HOME", None)
        else:
            os.environ["XDG_CONFIG_HOME"] = self.old_config
        import shutil
        shutil.rmtree(self.xdg, ignore_errors=True)

    def test_qml_model_calls_exist(self):
        qml = "\n".join(path.read_text(encoding="utf-8") for path in (SERVICE, PANEL, BAR, SETTINGS))
        model = MODEL.read_text(encoding="utf-8")
        names = sorted({
            name for name in re.findall(r"\bModel\.([A-Za-z_][A-Za-z0-9_]*)", qml)
            if name != "js"
        })
        self.assertTrue(names)
        missing = [name for name in names if f"function {name}" not in model]
        self.assertEqual(missing, [], f"QML calls Model.X but Model.js has no function: {missing}")

    def test_status_pipeline_does_not_depend_on_model_js_helpers(self):
        service = SERVICE.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        bar = BAR.read_text(encoding="utf-8")
        self.assertNotIn("Model.runtimeDir", service)
        self.assertNotIn("Model.hidDisplayName", service)
        self.assertNotIn("Model.hidDisplayName", panel)
        self.assertNotIn("Model.hidDisplayName", bar)
        self.assertIn("catch (e)", service)
        self.assertIn('source === "discover"', service)
        self.assertIn("hidppTicks", service)
        self.assertIn("onRuntimeDirChanged", service)
        self.assertIn("if (!root.hasHidppSnapshot) root.discover()", service)

    def test_idle_qml_does_not_spam_discover(self):
        service = SERVICE.read_text(encoding="utf-8")
        self.assertIn("refreshIntervalSec * 1000", service)
        self.assertNotIn("interval: 3000", service)
        self.assertIn("cmdQueue", service)
        self.assertIn("queued.push(cmd)", service)
        self.assertNotIn("if (cmdProcess.running) return", service)
        panel = PANEL.read_text(encoding="utf-8")
        self.assertIn("blocked: root.dropdownOpen", panel)
        self.assertNotIn("enabled: !root.dropdownOpen", panel)

    def test_helper_idle_is_event_driven(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("wait_for_event", source)
        self.assertIn("open_inotify", source)
        self.assertIn("solaar_available", source)
        self.assertIn("IN_HIDRAW_MASK", source)
        self.assertIn("EXIT_PEER_SERVING", source)
        self.assertIn("on_partial", source)
        self.assertIn("refresh_one_device", source)
        self.assertIn("setting.read(True)", source)
        self.assertIn("if not any(item is not None for item in raw)", source)
        self.assertNotIn("setting.read(cached=False)", source)
        self.assertNotIn("time.sleep(0.25)", source)
        self.assertNotIn("ticks % 6", source)
        service = SERVICE.read_text(encoding="utf-8")
        bar = BAR.read_text(encoding="utf-8")
        self.assertIn("peerServing", service)
        self.assertIn("ipcOwner", bar)
        self.assertIn("enabled: root.ipcOwner", bar)

    def test_device_online_skips_ping_when_known(self):
        class Online:
            online = True

            def ping(self):
                raise AssertionError("ping should not run")

        class Protocol:
            online = False
            protocol = 4.5

            def ping(self):
                raise AssertionError("ping should not run")

        self.assertTrue(self.mxctl.device_is_online(Online()))
        self.assertTrue(self.mxctl.device_is_online(Protocol()))

    def test_write_status_skips_identical_payload(self):
        path = Path(self.xdg) / "omarchy-mx" / "status.json"
        self.mxctl.runtime_dir()
        last = [""]
        self.assertTrue(self.mxctl.write_status(path, {"ok": True, "n": 1}, last))
        first = path.read_text(encoding="utf-8")
        self.assertFalse(self.mxctl.write_status(path, {"ok": True, "n": 1}, last))
        self.assertEqual(path.read_text(encoding="utf-8"), first)
        self.assertTrue(self.mxctl.write_status(path, {"ok": True, "n": 2}, last))

    def test_profile_name_and_store(self):
        self.assertEqual(self.mxctl.sanitize_profile_name("  Desk  "), "Desk")
        self.assertEqual(self.mxctl.sanitize_profile_name('  <Desk>  '), "Desk")
        self.mxctl.write_profiles({"version": 1, "profiles": [{"name": "Desk", "settings": []}]})
        names = [row["name"] for row in self.mxctl.load_profiles()["profiles"]]
        self.assertEqual(names, ["Desk"])
        self.mxctl.profile_delete({"name": "Desk"})
        self.assertEqual(self.mxctl.load_profiles()["profiles"], [])
        too_many = [{"name": f"p{i}", "settings": []} for i in range(self.mxctl.PROFILE_MAX_COUNT + 5)]
        self.mxctl.write_profiles({"version": 1, "profiles": too_many})
        self.assertEqual(len(self.mxctl.load_profiles()["profiles"]), self.mxctl.PROFILE_MAX_COUNT)
        huge = {"name": "Big", "settings": [{"name": "x", "value": "y" * self.mxctl.PROFILE_MAX_BYTES}]}
        with self.assertRaises(ValueError):
            self.mxctl.write_profiles({"version": 1, "profiles": [huge]})

    def test_progress_payload_percent(self):
        half = self.mxctl.progress_payload(1, 2, "MX Master 3S", "hidpp")
        self.assertEqual(half["percent"], 50)
        self.assertEqual(half["done"], 1)
        self.assertEqual(half["total"], 2)
        self.assertEqual(half["label"], "MX Master 3S")
        self.assertEqual(self.mxctl.progress_payload(0, 2, "Starting", "open")["percent"], 0)
        self.assertEqual(self.mxctl.progress_payload(2, 2, "", "idle")["percent"], 100)

    def test_refresh_one_device_keeps_other_snapshot(self):
        previous = {
            "devices": [
                {"id": "mouse", "name": "MX Master 3S", "kind": "mouse", "settings": [{"name": "dpi"}]},
                {"id": "keys", "name": "MX Keys", "kind": "keyboard", "settings": [{"name": "fn-swap"}]},
            ]
        }
        payload = self.mxctl.refresh_one_device(None, [], [], [], "", "missing", previous, "")
        names = [item.get("name") for item in payload.get("devices") or []]
        self.assertIn("MX Master 3S", names)
        self.assertIn("MX Keys", names)

    def test_discover_does_not_import_solaar(self):
        for name in solaar_modules():
            del sys.modules[name]
        mxctl = load_mxctl()
        payload = mxctl.discover_payload()
        self.assertTrue(payload.get("ok"))
        self.assertEqual(solaar_modules(), [])
        self.assertNotIn("logitech_receiver", sys.modules)

    def test_discover_process_stays_cheap(self):
        times = []
        env = os.environ.copy()
        for _ in range(5):
            started = time.perf_counter()
            proc = subprocess.run(
                ["python3", str(HELPER), "discover"],
                env=env,
                capture_output=True,
                text=True,
            )
            times.append(time.perf_counter() - started)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            payload = json.loads(proc.stdout)
            self.assertTrue(payload.get("ok"))
        median = statistics.median(times)
        self.assertLess(
            median,
            0.75,
            f"discover median {median:.3f}s is too slow: {times!r}",
        )

    def test_inotify_wakes_for_cmd_without_busy_loop(self):
        runtime = self.mxctl.runtime_dir()
        fd = self.mxctl.open_inotify(runtime)
        self.assertIsNotNone(fd)
        cmd = runtime / "cmd.json"
        started = time.perf_counter()

        def writer():
            time.sleep(0.04)
            self.mxctl.atomic_write(cmd, {"op": "refresh"})

        thread = threading.Thread(target=writer)
        thread.start()
        woke = self.mxctl.wait_for_event([fd], 2.0)
        elapsed = time.perf_counter() - started
        thread.join()
        os.close(fd)
        self.assertTrue(woke)
        self.assertLess(elapsed, 0.4, f"cmd wake took {elapsed:.3f}s")
        self.assertTrue(cmd.exists())

    def test_wait_timeout_is_a_single_block(self):
        runtime = self.mxctl.runtime_dir()
        fd = self.mxctl.open_inotify(runtime)
        self.assertIsNotNone(fd)
        started = time.perf_counter()
        woke = self.mxctl.wait_for_event([fd], 0.2)
        elapsed = time.perf_counter() - started
        os.close(fd)
        self.assertFalse(woke)
        self.assertGreaterEqual(elapsed, 0.18)
        self.assertLess(elapsed, 0.45)

    def test_solaar_available_uses_find_spec(self):
        installed = self.mxctl.solaar_available()
        self.assertIsInstance(installed, bool)
        self.assertNotIn("logitech_receiver", sys.modules)


if __name__ == "__main__":
    unittest.main()
