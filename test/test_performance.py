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

    def test_device_online_uses_ping_not_cached_protocol(self):
        class Awake:
            online = False
            protocol = 4.5

            def ping(self):
                return True

        class AsleepPaired:
            # Bolt register_new_device() sets online=True without a ping, and
            # the descriptor caches HID++ 4.5. That is not a live device.
            online = True
            protocol = 4.5
            _protocol = 4.5

            def ping(self):
                self.online = False
                return False

        self.assertTrue(self.mxctl.device_is_online(Awake()))
        self.assertFalse(self.mxctl.device_is_online(AsleepPaired()))

    def test_device_online_treats_no_such_device_as_offline(self):
        class NoSuchDevice(Exception):
            pass

        class AsleepLightspeed:
            # The receiver answers the ping with UNKNOWN_DEVICE; Solaar raises
            # NoSuchDevice and leaves the pairing-time online=True in place.
            online = True

            def ping(self):
                raise NoSuchDevice()

        class Flaky:
            online = True

            def ping(self):
                raise OSError("transient")

        self.assertFalse(self.mxctl.device_is_online(AsleepLightspeed()))
        self.assertTrue(self.mxctl.device_is_online(Flaky()))

    def test_reset_feature_probe_allows_another_query(self):
        class Feats:
            supported = False
            count = 0

        class Dev:
            features = Feats()
            _feature_settings_checked = True

        dev = Dev()
        self.mxctl.reset_feature_probe(dev)
        self.assertTrue(dev.features.supported)
        self.assertFalse(dev._feature_settings_checked)

    def test_progress_complete_requires_settings_on_online_devices(self):
        described = [
            {"online": True, "settings": [{"name": "dpi"}]},
            {"online": True, "settings": []},
        ]
        self.assertFalse(self.mxctl.progress_complete(described))
        described[1]["settings"] = [{"name": "fn-swap"}]
        self.assertTrue(self.mxctl.progress_complete(described))
        self.assertEqual(self.mxctl.settings_incomplete({"devices": [
            {"id": "keys", "settings": [], "readonly": False},
            {"id": "mouse", "settings": [{"name": "dpi"}], "readonly": False},
        ]}), ["keys"])

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

    def test_read_cmds_drains_spool_in_order(self):
        runtime = self.mxctl.runtime_dir()
        for index, value in enumerate((400, 800, 1600)):
            name = f"cmd-{index:020d}-1.json"
            (runtime / name).write_text(
                json.dumps({"op": "set", "setting": "dpi", "value": value}) + "\n", encoding="utf-8"
            )
        cmds = self.mxctl._read_cmds(runtime)
        self.assertEqual([cmd["value"] for cmd in cmds], [400, 800, 1600])
        self.assertEqual(list(runtime.glob("cmd-*.json")), [])

    def make_supply(self, name, **attrs):
        folder = Path(self.xdg) / "power_supply" / name
        folder.mkdir(parents=True, exist_ok=True)
        for key, value in attrs.items():
            (folder / key).write_text(str(value) + "\n", encoding="utf-8")
        return folder.parent

    def test_scan_power_supply_reads_kernel_nodes(self):
        root = self.make_supply(
            "hidpp_battery_0",
            capacity=85, status="Discharging", online=1,
            serial_number="ab-cd-ef", model_name="Wireless Mouse MX Master 3S",
        )
        self.make_supply("hidpp_battery_1", capacity_level="Low", status="Discharging", online=1,
                         serial_number="11-22-33", model_name="MX Keys")
        self.make_supply("hidpp_battery_2", capacity=50, online=0,
                         serial_number="off-li-ne", model_name="Gone")
        self.make_supply("BAT0", capacity=99, online=1)
        supplies = self.mxctl.scan_power_supply(root)
        self.assertEqual(len(supplies), 2)
        self.assertEqual(supplies[0]["level"], 85)
        self.assertEqual(supplies[0]["status"], "discharging")
        self.assertEqual(supplies[1]["level"], self.mxctl.CAPACITY_LEVEL_PERCENT["low"])

    def test_battery_from_power_supply_matching(self):
        supplies = [
            {"serial": "AB-CD-EF", "model": "Wireless Mouse MX Master 3S", "level": 85, "status": "discharging"},
            {"serial": "11-22-33", "model": "MX Keys", "level": 40, "status": "charging"},
        ]
        by_serial = self.mxctl.battery_from_power_supply(supplies, "ab-cd-ef", "")
        self.assertEqual(by_serial["level"], 85)
        self.assertEqual(by_serial["text"], "85%")
        by_name = self.mxctl.battery_from_power_supply(supplies, "", "MX Master 3S")
        self.assertEqual(by_name["level"], 85)
        self.assertIsNone(self.mxctl.battery_from_power_supply(supplies, "zz-zz", "MX Vertical"))

    def test_battery_differs_ignores_voltage_and_case(self):
        old = {"level": 85, "status": "Discharging", "voltage": 3900}
        self.assertFalse(self.mxctl.battery_differs(old, {"level": 85, "status": "discharging", "voltage": None}))
        self.assertTrue(self.mxctl.battery_differs(old, {"level": 84, "status": "discharging"}))
        self.assertTrue(self.mxctl.battery_differs(old, {"level": 85, "status": "charging"}))

    def test_attach_sysfs_batteries_fills_gaps_only(self):
        supplies = [{"serial": "ab-cd", "model": "MX Master 3S", "level": 70, "status": "discharging"}]
        devices = [
            {"id": "solaar", "serial": "ab-cd", "name": "MX Master 3S", "battery": {"level": 68}},
            {"id": "hidraw", "serial": "ab-cd", "name": "MX Master 3S", "battery": None},
        ]
        self.mxctl.attach_sysfs_batteries(devices, supplies)
        self.assertEqual(devices[0]["battery"]["level"], 68)
        self.assertEqual(devices[1]["battery"]["level"], 70)

    def test_refresh_batteries_sysfs_updates_and_covers(self):
        root = self.make_supply(
            "hidpp_battery_0",
            capacity=61, status="Charging", online=1,
            serial_number="ab-cd", model_name="MX Master 3S",
        )
        self.mxctl.POWER_SUPPLY_ROOT = root
        payload = {"devices": [
            {"id": "mouse", "serial": "ab-cd", "name": "MX Master 3S", "battery": {"level": 62, "status": "discharging"}},
            {"id": "keys", "serial": "zz-zz", "name": "MX Keys", "battery": {"level": 30}},
        ]}
        changed, covered = self.mxctl.refresh_batteries_sysfs(payload)
        self.assertTrue(changed)
        self.assertEqual(covered, {"mouse"})
        self.assertEqual(payload["devices"][0]["battery"]["level"], 61)
        self.assertEqual(payload["devices"][0]["battery"]["status"], "charging")
        self.assertEqual(payload["devices"][1]["battery"]["level"], 30)
        changed, covered = self.mxctl.refresh_batteries_sysfs(payload)
        self.assertFalse(changed)
        self.assertEqual(covered, {"mouse"})

    def test_sanitize_host_name(self):
        self.assertEqual(self.mxctl.sanitize_host_name("  Desk   PC "), "Desk PC")
        self.assertEqual(self.mxctl.sanitize_host_name('<b>Desk</b>'), "bDesk/b")
        self.assertEqual(len(self.mxctl.sanitize_host_name("x" * 99)), self.mxctl.HOST_NAME_MAX)
        with self.assertRaises(ValueError):
            self.mxctl.sanitize_host_name("   ")

    class FakeHostsDev:
        def __init__(self, names, current=0, flags=0x03, max_len=24):
            self.names = {i: (True, n) for i, n in enumerate(names)}
            self.current = current
            self.flags = flags
            self.max_len = max_len
            self.writes = []

        def feature_request(self, feature, function=0x00, *params):
            import struct

            if function == 0x00:
                return struct.pack("!BBBB", self.flags, 0, len(self.names), self.current) + b"\x00" * 12
            if function == 0x10:
                host = int(params[0])
                paired, name = self.names[host]
                raw = name.encode("utf-8")
                return struct.pack("!BBBBBB", host, 1 if paired else 0, 0, 0, len(raw), self.max_len) + b"\x00" * 10
            if function == 0x30:
                host, offset = int(params[0]), int(params[1])
                raw = self.names[host][1].encode("utf-8")
                return bytes([host, offset]) + raw[offset : offset + 14]
            if function == 0x40:
                host, offset, chunk = int(params[0]), int(params[1]), params[2]
                self.writes.append((host, offset, bytes(chunk)))
                return b"\x00\x01"
            return None

    def test_read_host_names_is_pure(self):
        # Keep the suite import-free: the fake device accepts the raw id.
        self.mxctl._hosts_feature = lambda: self.mxctl.HOSTS_INFO_FEATURE
        dev = self.FakeHostsDev(["Desk", "A name much longer than one chunk"], current=1)
        names, current = self.mxctl.read_host_names(dev)
        self.assertEqual(current, 1)
        self.assertEqual(names[0], (True, "Desk"))
        self.assertEqual(names[1], (True, "A name much longer than one chunk"))
        # A pure read must never write (Solaar's get_host_names does).
        self.assertEqual(dev.writes, [])
        hosts = self.mxctl.hosts_payload(dev)
        self.assertEqual(hosts[0]["current"], False)
        self.assertEqual(hosts[1]["current"], True)

    def test_write_host_name_targets_any_channel(self):
        self.mxctl._hosts_feature = lambda: self.mxctl.HOSTS_INFO_FEATURE
        dev = self.FakeHostsDev(["Desk", "Laptop"], current=0, max_len=24)
        self.mxctl.write_host_name(dev, 1, "Workshop Machine Longer")
        written = b"".join(chunk for host, _off, chunk in dev.writes if host == 1)
        self.assertEqual(written.decode("utf-8"), "Workshop Machine Longer")
        self.assertTrue(all(len(chunk) <= 14 for _h, _o, chunk in dev.writes))
        dev = self.FakeHostsDev(["Desk"], max_len=8)
        self.mxctl.write_host_name(dev, 0, "A very long name")
        self.assertEqual(len(b"".join(c for _h, _o, c in dev.writes)), 8)
        with self.assertRaises(ValueError):
            self.mxctl.write_host_name(self.FakeHostsDev(["Desk"]), 5, "Nope")
        with self.assertRaises(RuntimeError):
            self.mxctl.write_host_name(self.FakeHostsDev(["Desk"], flags=0x01), 0, "Nope")

    def test_rename_host_qml_contract(self):
        service = SERVICE.read_text(encoding="utf-8")
        self.assertIn("rename-host", service)
        self.assertIn("patchDeviceHostName", service)
        settings = SETTINGS.read_text(encoding="utf-8")
        self.assertIn("renameHost", settings)
        model = MODEL.read_text(encoding="utf-8")
        self.assertIn("function patchDeviceHostName", model)

    def test_plan_cycle_coalesces_bursts(self):
        plan = self.mxctl.plan_cycle([{"op": "refresh"}], False)
        self.assertTrue(plan["full"])
        self.assertTrue(plan["reopen"])
        self.assertTrue(plan["live"])
        plan = self.mxctl.plan_cycle([{"op": "rename-host", "device": "mouse", "host": 1}], False)
        self.assertFalse(plan["full"])
        self.assertTrue(plan["rehost"])
        self.assertEqual(plan["set_devices"], ["mouse"])
        plan = self.mxctl.plan_cycle(
            [{"op": "set", "device": "mouse"}, {"op": "set", "device": "mouse"}], False
        )
        self.assertFalse(plan["full"])
        self.assertFalse(plan["live"])
        self.assertEqual(plan["set_devices"], ["mouse", "mouse"])
        plan = self.mxctl.plan_cycle([{"op": "profile-save"}], False)
        self.assertFalse(plan["full"])
        self.assertEqual(plan["set_devices"], [])
        plan = self.mxctl.plan_cycle([{"op": "profile-apply"}], False)
        self.assertTrue(plan["full"])
        plan = self.mxctl.plan_cycle([], True)
        self.assertTrue(plan["full"])
        self.assertTrue(plan["reopen"])
        self.assertFalse(plan["live"])

    def test_refresh_batteries_updates_only_changed_levels(self):
        class Dev:
            def __init__(self, serial, level):
                self.serial = serial
                self.unitId = serial
                self.path = ""
                self.name = "MX Master 3S"
                self.online = True
                self._level = level

            def battery(self):
                import types

                return types.SimpleNamespace(level=self._level, status="discharging", voltage=None)

            @property
            def isDevice(self):
                return True

        payload = {
            "devices": [
                {"id": "mouse", "settings": [{"name": "dpi"}], "battery": {"level": 80}, "readonly": False},
                {"id": "hidraw9", "settings": [], "battery": None, "readonly": True},
            ]
        }
        self.assertTrue(self.mxctl.refresh_batteries([Dev("mouse", 55)], payload))
        self.assertEqual(payload["devices"][0]["battery"]["level"], 55)
        self.assertIsNone(payload["devices"][1]["battery"])
        self.assertFalse(self.mxctl.refresh_batteries([Dev("mouse", 55)], payload))

    def test_describe_device_streams_settings_before_hosts(self):
        import types

        def make_setting(name):
            setting = types.SimpleNamespace(
                name=name, label=name, description="", kind=0x01, persist=True
            )
            setting.read = lambda cached=True: True
            return setting

        dev = types.SimpleNamespace(
            online=True,
            path="",
            name="MX Master 3S",
            codename="MX Master 3S",
            kind="mouse",
            product_id="B034",
            wpid="",
            serial="abc",
            unitId="abc",
            protocol=4.5,
            receiver=None,
            settings=[make_setting("dpi"), make_setting("smartshift")],
        )
        dev.battery = lambda: None
        mods = {"configuration": types.SimpleNamespace(attach_to=lambda d: None)}
        seen = []

        def on_settings(payload, done, total):
            seen.append((done, total, len(payload["settings"])))

        payload = self.mxctl.describe_device(mods, dev, full=True, read_hosts=False, on_settings=on_settings)
        self.assertEqual(seen, [(1, 2, 1), (2, 2, 2)])
        self.assertEqual(len(payload["settings"]), 2)
        self.assertEqual(payload["hosts"], [])

    def test_progress_payload_percent_override(self):
        payload = self.mxctl.progress_payload(1, 2, "MX Master 3S", "hidpp", percent=17)
        self.assertEqual(payload["percent"], 17)
        self.assertEqual(self.mxctl.progress_payload(0, 0, "", "hidpp", percent=250)["percent"], 100)

    def test_shared_service_singleton_contract(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertIn("service", manifest["kinds"])
        self.assertEqual(manifest["entryPoints"]["service"], "Service.qml")
        bar = BAR.read_text(encoding="utf-8")
        self.assertIn("ensureService", bar)
        self.assertIn("serviceFor", bar)
        self.assertIn("sharedMx || localMx", bar)
        self.assertIn("passive: true", bar)
        settings = SETTINGS.read_text(encoding="utf-8")
        self.assertIn("property var service", settings)
        self.assertIn("root.service || localMx", settings)
        service = SERVICE.read_text(encoding="utf-8")
        self.assertIn("property var shell", service)
        self.assertIn("onPassiveChanged", service)
        # Fallback instances must not spawn processes until promoted.
        self.assertIn("if (!passive) mkdirProcess.running = true", service)

    def test_qml_status_freshness_and_passive_service(self):
        service = SERVICE.read_text(encoding="utf-8")
        self.assertIn("statusIsFresh", service)
        self.assertIn("lastStatusMs", service)
        self.assertIn("property bool passive", service)
        self.assertIn("if (force === true)", service)
        self.assertNotIn("daemon.running && (force === true", service)
        settings = SETTINGS.read_text(encoding="utf-8")
        self.assertIn("passive: true", settings)
        panel = PANEL.read_text(encoding="utf-8")
        self.assertNotIn('sections.push("keys")', panel)
        self.assertNotIn('sections.push("more")', panel)
        helper = HELPER.read_text(encoding="utf-8")
        self.assertIn("HEARTBEAT_SEC", helper)
        self.assertIn("plan_cycle", helper)
        self.assertIn("prune_dead", helper)
        self.assertIn("cmd_spool_name", helper)

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
