import importlib.util
import json
import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import mxpointer  # noqa: E402
from test_plain_hid_text import mxctl  # noqa: E402

SERVICE = ROOT / "Service.qml"
SETTINGS = ROOT / "MxSettings.qml"
PANEL = ROOT / "Panel.qml"
MODEL = ROOT / "Model.js"
HELPER = ROOT / "mxctl.py"


class FakeHyprland:
    """Records IPC requests; answers devices/getoption like Hyprland."""
    def __init__(self, mice, force_no_accel=False, reject=False):
        self.mice = list(mice)
        self.force_no_accel = force_no_accel
        self.reject = reject
        self.requests = []

    def __call__(self, command):
        self.requests.append(command)
        if command == "j/devices":
            return json.dumps({"mice": [{"name": m} for m in self.mice], "keyboards": []})
        if command.startswith("j/getoption input:force_no_accel"):
            return json.dumps({"option": "input:force_no_accel", "bool": self.force_no_accel, "set": True})
        if command.startswith("/eval "):
            return "error: nope" if self.reject else "ok"
        raise AssertionError("unexpected request " + command)

    def evals(self):
        return [r[len("/eval "):] for r in self.requests if r.startswith("/eval ")]


class FakeEvents:
    def __init__(self):
        self.connected = False
        self.reloaded = False

    def fileno(self):
        return 99 if self.connected else None

    def connect(self):
        self.connected = True
        return True

    def close(self):
        self.connected = False

    def drain(self):
        seen, self.reloaded = self.reloaded, False
        return seen


def sysfs_with(root: Path, node: str, names):
    for index, name in enumerate(names):
        entry = root / node / "device" / "input" / f"input{index}"
        entry.mkdir(parents=True)
        (entry / "name").write_text(name + "\n")


class CurveTests(unittest.TestCase):
    def test_gain_rises_with_speed_and_saturates(self):
        gains = [mxpointer.mac_gain(v) for v in (0, 0.5, 1, 2, 4, 8, 16, 64)]
        self.assertEqual(gains, sorted(gains))
        self.assertAlmostEqual(gains[0], mxpointer.MAC_GAIN_MIN)
        self.assertLess(gains[-1], mxpointer.MAC_GAIN_MAX)
        self.assertGreater(gains[-1], mxpointer.MAC_GAIN_MAX - 0.05)
        # Half of the extra gain arrives at the knee speed.
        self.assertAlmostEqual(mxpointer.mac_gain(mxpointer.MAC_KNEE), (mxpointer.MAC_GAIN_MIN + mxpointer.MAC_GAIN_MAX) / 2)

    def test_curve_format_is_hyprland_custom_profile(self):
        curve = mxpointer.mac_curve(1000)
        parts = curve.split(" ")
        self.assertEqual(parts[0], "custom")
        self.assertEqual(float(parts[1]), mxpointer.MAC_STEP)
        points = [float(p) for p in parts[2:]]
        self.assertEqual(len(points), mxpointer.MAC_POINTS)
        self.assertLessEqual(len(points), 64)
        self.assertEqual(points[0], 0.0)
        # Output speed must be strictly increasing so the pointer never
        # slows down as the hand speeds up.
        self.assertEqual(points, sorted(points))
        self.assertTrue(all(b > a for a, b in zip(points, points[1:])))
        # First point is about 1:1 minus the precision dip; the tail
        # carries the full gain.
        self.assertAlmostEqual(points[1], 1 * mxpointer.mac_gain(1), places=3)
        self.assertGreater(points[-1] / 24, 3.0)

    def test_curve_scales_with_dpi(self):
        base = mxpointer.mac_curve(1000).split(" ")
        double = mxpointer.mac_curve(2000).split(" ")
        self.assertAlmostEqual(float(double[1]), 2 * float(base[1]))
        for a, b in zip(base[2:], double[2:]):
            self.assertAlmostEqual(float(b), 2 * float(a), places=3)
        # Only digits, dots and spaces may reach Hyprland.
        self.assertRegex(mxpointer.mac_curve(850), r"^custom( [0-9.]+)+$")

    def test_clamp_dpi(self):
        self.assertEqual(mxpointer.clamp_dpi(None), 1000)
        self.assertEqual(mxpointer.clamp_dpi("abc"), 1000)
        self.assertEqual(mxpointer.clamp_dpi(float("nan")), 1000)
        self.assertEqual(mxpointer.clamp_dpi(float("inf")), 1000)
        self.assertEqual(mxpointer.clamp_dpi(0), 1000)
        self.assertEqual(mxpointer.clamp_dpi(850.4), 850)
        self.assertEqual(mxpointer.clamp_dpi(999999), mxpointer.DPI_MAX)
        self.assertEqual(mxpointer.device_dpi({"settings": [{"name": "dpi", "value": 850}]}), 850)
        self.assertEqual(mxpointer.device_dpi({"settings": [{"name": "dpi", "value": {"id": 1600, "name": "1600"}}]}), 1600)
        self.assertEqual(mxpointer.device_dpi({"settings": []}), 1000)


class NamingTests(unittest.TestCase):
    def test_slug_matches_hyprland_naming(self):
        self.assertEqual(mxpointer.hypr_device_slug("Logitech MX Master 3S"), "logitech-mx-master-3s")
        mice = ["logitech-g305-1", "satechi-sm1-keyboard-2", "logitech-mx-master-3s"]
        self.assertEqual(mxpointer.match_hypr_names(mice, ["Logitech MX Master 3S"]), ["logitech-mx-master-3s"])
        self.assertEqual(mxpointer.match_hypr_names(mice, ["Logitech G305"]), ["logitech-g305-1"])
        self.assertEqual(mxpointer.match_hypr_names(mice, ["Logitech G305 Keyboard"]), [])
        self.assertEqual(mxpointer.match_hypr_names(mice, [""]), [])

    def test_evdev_names_from_sysfs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sysfs_with(root, "hidraw8", ["Logitech MX Master 3S"])
            self.assertEqual(mxpointer.evdev_names_for_hidraw("/dev/hidraw8", root), ["Logitech MX Master 3S"])
            self.assertEqual(mxpointer.evdev_names_for_hidraw("/dev/hidraw9", root), [])
            self.assertEqual(mxpointer.evdev_names_for_hidraw("../../etc/passwd", root), [])
            self.assertEqual(mxpointer.evdev_names_for_hidraw("", root), [])

    def test_lua_never_embeds_untrusted_text_as_code(self):
        lua = mxpointer.lua_device_config("logitech-mx-master-3s", "custom 1 0 1")
        self.assertEqual(lua, 'hl.device({ name = "logitech-mx-master-3s", accel_profile = "custom 1 0 1" })')
        revert = mxpointer.lua_device_config("logitech-mx-master-3s", None)
        self.assertIn('hl.get_config("input.accel_profile")', revert)
        for bad in ('x" }) os.execute("rm', "Logitech MX", "", "-leading", "a" * 200, "name\n"):
            with self.assertRaises(ValueError):
                mxpointer.lua_device_config(bad, "custom 1 0 1")
        with self.assertRaises(ValueError):
            mxpointer.lua_device_config("ok-name", 'custom 1" })')

    def test_accel_mode_validation(self):
        self.assertEqual(mxpointer.accel_mode(None), "system")
        self.assertEqual(mxpointer.accel_mode(" MAC "), "mac")
        with self.assertRaises(ValueError):
            mxpointer.accel_mode("flat")


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        sysfs_with(self.root, "hidraw8", ["Logitech MX Master 3S"])
        sysfs_with(self.root, "hidraw7", ["Logitech G305"])
        self.devices = [
            {"id": "748DEB1B", "kind": "mouse", "path": "/dev/hidraw8", "online": True, "settings": [{"name": "dpi", "value": 850}]},
            {"id": "57CF710E", "kind": "mouse", "path": "/dev/hidraw7", "online": False, "settings": []},
            {"id": "KBD", "kind": "keyboard", "path": "/dev/hidraw2", "online": True, "settings": []},
        ]
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "test-signature"

    def tearDown(self):
        self.tmp.cleanup()
        os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    def runtime(self, mice=("logitech-mx-master-3s", "logitech-g305-1"), **kw):
        ipc = FakeHyprland(mice, **kw)
        events = FakeEvents()
        return mxpointer.PointerRuntime(request=ipc, events=events, sysfs_root=self.root), ipc, events

    def test_idle_without_overrides_costs_nothing(self):
        rt, ipc, events = self.runtime()
        self.assertFalse(rt.sync(self.devices, {}))
        self.assertEqual(ipc.requests, [])
        self.assertFalse(events.connected)
        self.assertEqual(rt.status(), {"available": True, "error": "", "applied": [], "missing": []})

    def test_apply_revert_and_dpi_rescale(self):
        rt, ipc, events = self.runtime()
        prefs = {"748DEB1B": {"acceleration": "mac"}}
        self.assertTrue(rt.sync(self.devices, prefs))
        self.assertEqual(ipc.evals(), [mxpointer.lua_device_config("logitech-mx-master-3s", mxpointer.mac_curve(850))])
        self.assertTrue(events.connected)
        self.assertEqual(rt.status()["applied"], ["logitech-mx-master-3s"])
        # Unchanged state: no IPC at all, so idle wakes stay free.
        ipc.requests.clear()
        self.assertFalse(rt.sync(self.devices, prefs))
        self.assertEqual(ipc.requests, [])
        # A DPI change rescales the curve.
        self.devices[0]["settings"][0]["value"] = 1700
        rt.sync(self.devices, prefs)
        self.assertEqual(ipc.evals(), [mxpointer.lua_device_config("logitech-mx-master-3s", mxpointer.mac_curve(1700))])
        # A compositor reload re-sends even when nothing changed.
        ipc.requests.clear()
        events.reloaded = True
        self.assertTrue(rt.poll())
        rt.sync(self.devices, prefs, force=True)
        self.assertEqual(len(ipc.evals()), 1)
        # Turning it off reverts to the global profile and drops the socket.
        ipc.requests.clear()
        self.assertTrue(rt.sync(self.devices, {}))
        self.assertEqual(ipc.evals(), [mxpointer.lua_device_config("logitech-mx-master-3s", None)])
        self.assertFalse(events.connected)
        self.assertEqual(rt.status()["applied"], [])

    def test_shutdown_reverts_everything(self):
        rt, ipc, events = self.runtime()
        rt.sync(self.devices, {"748DEB1B": {"acceleration": "mac"}, "57CF710E": {"acceleration": "mac"}})
        self.assertEqual(sorted(rt.applied), ["logitech-g305-1", "logitech-mx-master-3s"])
        ipc.requests.clear()
        rt.shutdown()
        self.assertEqual(len(ipc.evals()), 2)
        self.assertTrue(all('hl.get_config("input.accel_profile")' in lua for lua in ipc.evals()))
        self.assertEqual(rt.applied, {})
        self.assertFalse(events.connected)

    def test_reports_missing_mouse_force_no_accel_and_rejections(self):
        rt, ipc, _ = self.runtime(mice=())
        rt.sync(self.devices, {"748DEB1B": {"acceleration": "mac"}})
        self.assertEqual(rt.status()["missing"], ["748DEB1B"])
        self.assertIn("reconnect", rt.status()["error"])
        rt, ipc, _ = self.runtime(force_no_accel=True)
        rt.sync(self.devices, {"748DEB1B": {"acceleration": "mac"}})
        self.assertIn("force_no_accel", rt.status()["error"])
        rt, ipc, _ = self.runtime(reject=True)
        rt.sync(self.devices, {"748DEB1B": {"acceleration": "mac"}})
        self.assertIn("rejected", rt.status()["error"])
        self.assertEqual(rt.applied, {})
        # A failed apply is retried on the next sync instead of being cached.
        ipc.reject = False
        rt.sync(self.devices, {"748DEB1B": {"acceleration": "mac"}})
        self.assertEqual(rt.applied, {"logitech-mx-master-3s": mxpointer.mac_curve(850)})
        self.assertEqual(rt.status()["error"], "")

    def test_keyboards_never_get_a_curve(self):
        rt, ipc, _ = self.runtime(mice=("satechi-sm1-keyboard-2",))
        sysfs_with(self.root, "hidraw2", ["Satechi SM1 Keyboard"])
        rt.sync(self.devices, {"KBD": {"acceleration": "mac"}})
        self.assertEqual(ipc.evals(), [])
        self.assertEqual(rt.status()["missing"], [])

    def test_unavailable_hyprland(self):
        os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        rt, ipc, _ = self.runtime()
        rt.sync(self.devices, {"748DEB1B": {"acceleration": "mac"}})
        self.assertEqual(ipc.requests, [])
        self.assertIn("not running", rt.status()["error"])


class EventSocketTests(unittest.TestCase):
    def test_drain_detects_config_reload_across_chunks(self):
        left, right = socket.socketpair()
        events = mxpointer.HyprlandEvents()
        right.setblocking(False)
        events.sock = right
        self.assertFalse(events.drain())
        left.sendall(b"activewindow>>foo,bar\nconfigrelo")
        self.assertFalse(events.drain())
        left.sendall(b"aded>>\nworkspace>>2\n")
        self.assertTrue(events.drain())
        self.assertFalse(events.drain())
        left.close()
        self.assertFalse(events.drain())
        self.assertIsNone(events.fileno())

    def test_wait_for_event_keeps_kept_fds_unread(self):
        left, right = socket.socketpair()
        right.setblocking(False)
        left.sendall(b"configreloaded>>\n")
        self.assertTrue(mxctl.wait_for_event([right.fileno()], 0.2, keep=(right.fileno(),)))
        self.assertEqual(right.recv(64), b"configreloaded>>\n")
        left.close()
        right.close()

    def test_connect_without_hyprland_is_quiet(self):
        old = os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        try:
            events = mxpointer.HyprlandEvents()
            self.assertFalse(events.connect())
            self.assertIsNone(events.fileno())
        finally:
            if old is not None:
                os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = old


class StoreAndProfileTests(unittest.TestCase):
    def setUp(self):
        self.config = tempfile.mkdtemp(prefix="omarchy-mx-cfg-")
        self.old_config = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = self.config

    def tearDown(self):
        if self.old_config is None:
            os.environ.pop("XDG_CONFIG_HOME", None)
        else:
            os.environ["XDG_CONFIG_HOME"] = self.old_config

    def test_prefs_roundtrip_and_cleanup(self):
        self.assertEqual(mxctl.load_pointer_prefs(), {"version": 1, "devices": {}})
        mxctl.set_pointer_pref("748DEB1B", "mac")
        path = mxctl.pointer_file()
        self.assertTrue(path.is_file())
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")
        self.assertEqual(mxctl.load_pointer_prefs()["devices"], {"748DEB1B": {"acceleration": "mac"}})
        self.assertEqual(mxctl.pointer_pref(mxctl.load_pointer_prefs(), "748DEB1B"), {"acceleration": "mac"})
        self.assertEqual(mxctl.pointer_pref(mxctl.load_pointer_prefs(), "other"), {"acceleration": "system"})
        # "system" is the absence of an override; the file goes away with it.
        mxctl.set_pointer_pref("748DEB1B", "system")
        self.assertFalse(path.exists())
        self.assertFalse(mxctl.discover_payload().get("hasPointer"))

    def test_prefs_ignore_garbage(self):
        path = mxctl.pointer_file()
        path.write_text('{"version": 1, "devices": {"a": {"acceleration": "flat"}, "b": "x", "c": {"acceleration": "mac"}}}')
        self.assertEqual(mxctl.load_pointer_prefs()["devices"], {"c": {"acceleration": "mac"}})
        path.write_text("not json")
        self.assertEqual(mxctl.load_pointer_prefs()["devices"], {})

    def test_profile_save_and_apply_carry_the_preference(self):
        source = HELPER.read_text(encoding="utf-8")
        save = source[source.index("def profile_save"):source.index("def profile_delete")]
        self.assertIn('"pointer": pointer_pref(load_pointer_prefs(), device_id(dev))', save)
        apply_ = source[source.index("def profile_apply"):source.index("def load_actions")]
        self.assertIn("set_pointer_pref(device_id(dev), accel_mode(pointer.get(\"acceleration\")))", apply_)
        self.assertIn('if op == "pointer-set":', source)
        self.assertIn("pointer.shutdown()", source)
        self.assertIn("keep=(event_fd,)", source)

    def test_pointer_set_validates(self):
        class Dev:
            serial = "748DEB1B"
            unitId = ""
            path = "/dev/hidraw8"
            name = "MX Master 3S"
            codename = "MX Master 3S"
            product_id = "B034"
            kind = "mouse"
            isDevice = True

        class Kbd(Dev):
            serial = "KBD1"
            name = "MX Keys"
            codename = "MX Keys"
            kind = "keyboard"

        mxctl.pointer_set([Dev()], {"device": "748DEB1B", "acceleration": "mac"})
        self.assertEqual(mxctl.load_pointer_prefs()["devices"], {"748DEB1B": {"acceleration": "mac"}})
        with self.assertRaises(ValueError):
            mxctl.pointer_set([Dev()], {"device": "748DEB1B", "acceleration": "turbo"})
        with self.assertRaises(RuntimeError):
            mxctl.pointer_set([Dev()], {"device": "missing", "acceleration": "mac"})
        with self.assertRaises(ValueError):
            mxctl.pointer_set([Kbd()], {"device": "KBD1", "acceleration": "mac"})


class UiContractTests(unittest.TestCase):
    def test_qml_and_model_wiring(self):
        service = SERVICE.read_text(encoding="utf-8")
        settings = SETTINGS.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        model = MODEL.read_text(encoding="utf-8")
        self.assertIn('op: "pointer-set"', service)
        self.assertIn("parsed.hasPointer", service)
        self.assertIn("function setPointerAcceleration", service)
        for text in (settings, panel):
            self.assertIn("macOS-style acceleration", text)
            self.assertIn("mx.setPointerAcceleration", text)
            self.assertIn("Model.pointerAccelHelp()", text)
        self.assertIn("function pointerMode", model)
        self.assertIn("function patchPointerMode", model)
        self.assertIn("pointerRuntime:", model)
        # The helper's error text is HID/compositor facing: keep it plain.
        idx = settings.index("mx.pointerRuntime.error ? String(mx.pointerRuntime.error)")
        self.assertIn("textFormat: Text.PlainText", settings[idx:idx + 200])


if __name__ == "__main__":
    unittest.main()
