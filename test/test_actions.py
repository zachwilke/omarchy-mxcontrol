import importlib.util
import json
import struct
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mxactions as actions
import mxctl


def binding(**extra):
    return actions.validate_binding(dict(device="mouse", control="83", app="", shortcut="CTRL+c", **extra))


class AssignmentTests(unittest.TestCase):
    def test_shortcut_validation_and_normalization(self):
        self.assertEqual(actions.shortcut("Control + Shift + C"), "CTRL+SHIFT+c")
        self.assertEqual(actions.sequence("CTRL+c\n\nALT+Tab"), "CTRL+c\nALT+Tab")
        for bad in ("CTRL", "CTRL+", "CTRL+c;rm", "CTRL+$(id)", "CTRL+c,activewindow", "BAD+c"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                actions.shortcut(bad)
        with self.assertRaises(ValueError):
            actions.sequence("c\n" * 9)

    def test_override_requires_default_and_falls_back(self):
        default = binding()
        override = dict(default, app="chromium", shortcut="CTRL+l")
        with self.assertRaises(ValueError):
            actions.updated_bindings([], override)
        rows = actions.updated_bindings([default], override)
        self.assertEqual(actions.resolve_binding(rows, 83, "Chromium")["shortcut"], "CTRL+l")
        self.assertEqual(actions.resolve_binding(rows, 83, "foot")["shortcut"], "CTRL+c")
        self.assertEqual(actions.resolve_binding(rows, 83, "chromium-other")["shortcut"], "CTRL+c")
        self.assertEqual(actions.updated_bindings(rows, default, delete=True), [])
        self.assertEqual(actions.updated_bindings(rows, override, delete=True), [default])

    def test_gestures_validate_each_action(self):
        row = binding(mode="gesture", gestures={"up": "CTRL+Tab", "left": ""})
        self.assertEqual(row["gestures"]["up"], "CTRL+Tab")
        self.assertEqual(row["gestures"]["right"], "")
        with self.assertRaises(ValueError):
            binding(mode="gesture", gestures={"up": "CTRL+;"})

    def test_store_roundtrip_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict("os.environ", {"XDG_CONFIG_HOME": temp}):
            self.assertEqual(mxctl.load_actions(), [])
            path = mxctl.profiles_dir() / "actions.json"
            mxctl.write_bytes(path, json.dumps({"version": 1, "bindings": [binding()]}).encode())
            self.assertEqual(mxctl.load_actions(), [binding()])
            path.unlink()
            path.symlink_to(Path(temp) / "other.json")
            with self.assertRaises(OSError):
                mxctl.load_actions()


class PacketTests(unittest.TestCase):
    def press(self, tracker, *keys):
        return tracker.feed(0, struct.pack("!HHHH", *(list(keys) + [0] * (4 - len(keys)))))

    def test_click_once_on_release(self):
        tracker = actions.GestureTracker([83])
        self.assertEqual(self.press(tracker, 83), [])
        self.assertEqual(self.press(tracker, 83), [])
        self.assertEqual(self.press(tracker), [(83, "click")])
        self.assertEqual(self.press(tracker), [])

    def test_directions_and_movement_threshold(self):
        for dx, dy, direction in [(1, 2, "click"), (0, -150, "up"), (140, 0, "right"), (-140, 20, "left"), (10, 160, "down")]:
            tracker = actions.GestureTracker([83])
            self.press(tracker, 83)
            tracker.feed(0x10, struct.pack("!hh", dx, dy))
            self.assertEqual(self.press(tracker), [(83, direction)])

    def test_ignore_mx_first_xy_report_and_unrelated_packets(self):
        tracker = actions.GestureTracker([83], ignore_first=True)
        self.press(tracker, 83)
        tracker.feed(0x10, struct.pack("!hh", 32000, -32000))
        tracker.feed(0x10, struct.pack("!hh", 150, 0))
        self.assertEqual(self.press(tracker), [(83, "right")])
        self.assertEqual(tracker.feed(0, b"bad"), [])
        self.assertEqual(self.press(tracker, 84), [])
        self.assertEqual(tracker.feed(0x20, bytes(8)), [])


class ExecutorTests(unittest.TestCase):
    def result(self, stdout):
        return SimpleNamespace(returncode=0, stdout=stdout, stderr="")

    def test_dispatch_is_argv_and_pinned_to_window(self):
        run = Mock(side_effect=[self.result('{"address":"0xab","class":"foot"}'), self.result('ok')])
        actions.HyprlandExecutor(run).execute("CTRL+c", "0xab", threading.Event())
        self.assertEqual(run.call_args_list[1].args[0], ["hyprctl", "dispatch", 'hl.dsp.send_shortcut({ mods = "CTRL", key = "c", window = "address:0xab" })'])
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_focus_change_aborts_before_sending(self):
        run = Mock(return_value=self.result('{"address":"0xcd","class":"chromium"}'))
        with self.assertRaisesRegex(RuntimeError, "focused window changed"):
            actions.HyprlandExecutor(run).execute("CTRL+v", "0xab", threading.Event())
        self.assertEqual(run.call_count, 1)

    def test_error_stops_remaining_steps(self):
        run = Mock(side_effect=[self.result('{"address":"0xab"}'), self.result('unknown dispatcher')])
        with self.assertRaises(RuntimeError):
            actions.HyprlandExecutor(run).execute("CTRL+c\nCTRL+v", "0xab", threading.Event())
        self.assertEqual(run.call_count, 2)


class RuntimeTests(unittest.TestCase):
    def test_reuses_listener_and_restores_on_removal_or_disconnect(self):
        factory = Mock(side_effect=lambda *args: SimpleNamespace(stop_event=threading.Event(), close=Mock()))
        runtime = actions.ActionRuntime(None, lambda d: d.id, factory)
        device = SimpleNamespace(id="mouse", online=True)
        runtime.sync([device], [binding()])
        session = runtime.sessions["mouse"][2]
        runtime.sync([device], [binding()])
        self.assertEqual(factory.call_count, 1)
        runtime.sync([], [binding()])
        session.close.assert_called_once()
        self.assertEqual(runtime.status()["activeDevices"], [])
        runtime.sync([device], [binding()])
        second = runtime.sessions["mouse"][2]
        runtime.sync([device], [])
        second.close.assert_called_once()

    def test_failed_session_is_reported_not_marked_active(self):
        runtime = actions.ActionRuntime(None, lambda d: d.id, Mock(side_effect=ValueError("already diverted")))
        runtime.sync([SimpleNamespace(id="mouse", online=True)], [binding()])
        self.assertEqual(runtime.status()["activeDevices"], [])
        self.assertIn("already diverted", runtime.error)

    def test_failed_assignment_rolls_back_without_saving(self):
        runtime = Mock()
        runtime.sessions = {}
        runtime.error = "failed"
        device = SimpleNamespace(id="mouse", serial="mouse")
        with patch.object(mxctl, "load_actions", return_value=[]), patch.object(mxctl, "iter_devices", return_value=iter([device])), patch.object(mxctl, "find_device", return_value=device), patch.object(mxctl, "device_is_online", return_value=True), patch.object(mxctl, "device_id", return_value="mouse"), patch.object(mxctl, "write_bytes") as write:
            with self.assertRaises(RuntimeError):
                mxctl.action_command({}, [], {"op": "action-save", "device": "mouse", "binding": binding()}, runtime)
            write.assert_not_called()
            self.assertEqual(runtime.sync.call_count, 2)

class SessionTests(unittest.TestCase):
    def setUp(self):
        from enum import IntFlag
        class Mapping(IntFlag):
            DIVERTED = 1
            RAW_XY_DIVERTED = 2
            PERSISTENTLY_DIVERTED = 4
        class Flag(IntFlag):
            DIVERTABLE = 1
            RAW_XY = 2
            VIRTUAL = 4
        self.Mapping, self.Flag = Mapping, Flag
        self.modules = patch.dict(sys.modules, {
            "logitech_receiver.hidpp20": SimpleNamespace(MappingFlag=Mapping, KeyFlag=Flag),
            "logitech_receiver.hidpp20_constants": SimpleNamespace(SupportedFeature=SimpleNamespace(REPROG_CONTROLS_V4=0x1B04)),
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def key(self, cid, reject=False):
        key = SimpleNamespace(key=cid, flags=self.Flag.DIVERTABLE | self.Flag.RAW_XY, mapping_flags=self.Mapping(0))
        def set_diverted(value):
            if value and reject:
                raise RuntimeError("rejected")
            key.mapping_flags = key.mapping_flags | self.Mapping.DIVERTED if value else key.mapping_flags & ~self.Mapping.DIVERTED
        def set_raw(value):
            key.mapping_flags = key.mapping_flags | self.Mapping.RAW_XY_DIVERTED if value else key.mapping_flags & ~self.Mapping.RAW_XY_DIVERTED
        key.set_diverted = Mock(side_effect=set_diverted)
        key.set_rawXY_reporting = Mock(side_effect=set_raw)
        key._getCidReporting = Mock()
        return key

    def device(self, keys):
        class Features(dict):
            def get_feature_version(self, _):
                return 4
        return SimpleNamespace(path="/dev/mock", number=255, keys=keys, features=Features({0x1B04: 6}))

    def test_read_handle_is_independent_and_close_restores_input(self):
        key = self.key(83)
        base = Mock()
        base.open_path.return_value = 42
        with patch.object(actions.threading, "Thread"):
            session = actions.DeviceSession(base, self.device([key]), [binding(mode="gesture")], Mock())
            self.assertIn(self.Mapping.DIVERTED, key.mapping_flags)
            self.assertIn(self.Mapping.RAW_XY_DIVERTED, key.mapping_flags)
            session.close()
        self.assertEqual(key.mapping_flags, 0)
        base.open_path.assert_called_once_with("/dev/mock")
        base.close.assert_called_once_with(42)

    def test_partial_setup_failure_restores_previous_keys(self):
        first, second = self.key(83), self.key(84, reject=True)
        base = Mock()
        with self.assertRaisesRegex(RuntimeError, "rejected"):
            actions.DeviceSession(base, self.device([first, second]), [binding(), dict(binding(), control="84")], Mock())
        self.assertEqual(first.mapping_flags, 0)
        self.assertEqual(second.mapping_flags, 0)
        base.close.assert_called_once()

    def test_existing_solaar_diversion_is_not_taken_over(self):
        key = self.key(83)
        key.mapping_flags = self.Mapping.DIVERTED
        base = Mock()
        with self.assertRaisesRegex(ValueError, "Regular"):
            actions.DeviceSession(base, self.device([key]), [binding()], Mock())
        key.set_diverted.assert_not_called()
        base.open_path.assert_not_called()
