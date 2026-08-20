import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_plain_hid_text import mxctl

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "mxctl.py"
SERVICE = ROOT / "Service.qml"
MODEL = ROOT / "Model.js"
SETTINGS = ROOT / "MxSettings.qml"
PANEL = ROOT / "Panel.qml"
BAR = ROOT / "BarWidget.qml"


class RuntimeDirTests(unittest.TestCase):
    def setUp(self):
        self.xdg = tempfile.mkdtemp(prefix="omarchy-mx-test-")
        self.config = tempfile.mkdtemp(prefix="omarchy-mx-cfg-")
        self.old_xdg = os.environ.get("XDG_RUNTIME_DIR")
        self.old_config = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_RUNTIME_DIR"] = self.xdg
        os.environ["XDG_CONFIG_HOME"] = self.config

    def tearDown(self):
        if self.old_xdg is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self.old_xdg
        if self.old_config is None:
            os.environ.pop("XDG_CONFIG_HOME", None)
        else:
            os.environ["XDG_CONFIG_HOME"] = self.old_config
        shutil.rmtree(self.xdg, ignore_errors=True)
        shutil.rmtree(self.config, ignore_errors=True)

    def run_helper(self, *args, env=None):
        merged = os.environ.copy() if env is None else dict(env)
        return subprocess.run(
            ["python3", str(HELPER), *args],
            env=merged,
            capture_output=True,
            text=True,
        )

    def test_same_fallback_path_in_qml_and_python(self):
        self.assertEqual(mxctl.runtime_path("/run/user/1000", 999), "/run/user/1000/omarchy-mx")
        self.assertEqual(mxctl.runtime_path("", 1000), "/run/user/1000/omarchy-mx")
        self.assertEqual(mxctl.runtime_path(None, 42), "/run/user/42/omarchy-mx")
        self.assertEqual(
            mxctl.runtime_path(os.environ["XDG_RUNTIME_DIR"], os.getuid()),
            f"{self.xdg}/omarchy-mx",
        )

    def test_no_tmp_runtime_fallback(self):
        service = SERVICE.read_text(encoding="utf-8")
        python = HELPER.read_text(encoding="utf-8")
        model = MODEL.read_text(encoding="utf-8")
        settings = SETTINGS.read_text(encoding="utf-8")
        self.assertNotIn("/tmp", service)
        self.assertNotIn("/var/tmp", service)
        self.assertNotIn("/tmp", model)
        self.assertNotIn("/tmp", settings)
        self.assertNotIn("/var/tmp", settings)
        self.assertNotIn("/tmp/omarchy-mx", python)
        self.assertIn('Quickshell.env("XDG_RUNTIME_DIR")', service)
        self.assertIn("/run/user/", service)
        self.assertNotIn("Model.runtimeDir", service)
        self.assertIn("write-cmd", service)
        self.assertNotIn("printf %s", service)
        self.assertNotIn("bash", service.split("function triggerUdev")[0])

    def test_runtime_dir_mode_0700(self):
        path = mxctl.runtime_dir()
        self.assertEqual(str(path), f"{self.xdg}/omarchy-mx")
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)

    def test_runtime_dir_cli_fallback(self):
        env = os.environ.copy()
        env.pop("XDG_RUNTIME_DIR", None)
        expected = f"/run/user/{os.getuid()}/omarchy-mx"
        self.assertEqual(mxctl.runtime_path(None, os.getuid()), expected)
        proc = self.run_helper("runtime-dir", env=env)
        self.assertNotIn("/tmp", proc.stdout)
        self.assertNotIn("/tmp", proc.stderr)
        if proc.returncode == 0:
            self.assertEqual(proc.stdout.strip(), expected)
        else:
            self.assertIn(expected, proc.stderr)

    def test_write_cmd_roundtrip(self):
        cmd = {"op": "set", "device": "abc", "setting": "dpi", "value": 800}
        proc = self.run_helper("write-cmd", json.dumps(cmd))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        written = json.loads((Path(self.xdg) / "omarchy-mx" / "cmd.json").read_text(encoding="utf-8"))
        self.assertEqual(written["op"], "set")
        self.assertEqual(written["device"], "abc")
        self.assertEqual(written["value"], 800)

    def test_write_cmd_symlink_does_not_truncate(self):
        victim = Path(self.xdg) / "victim.txt"
        victim.write_text("keep-me\n", encoding="utf-8")
        runtime = Path(self.xdg) / "omarchy-mx"
        runtime.mkdir()
        cmd_path = runtime / "cmd.json"
        cmd_path.symlink_to(victim)
        proc = self.run_helper("write-cmd", json.dumps({"op": "refresh"}))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(victim.read_text(encoding="utf-8"), "keep-me\n")
        self.assertTrue(cmd_path.is_file())
        self.assertFalse(cmd_path.is_symlink())
        self.assertEqual(json.loads(cmd_path.read_text(encoding="utf-8"))["op"], "refresh")

    def test_atomic_write_status_symlink_does_not_truncate(self):
        victim = Path(self.xdg) / "status-victim.txt"
        victim.write_text("keep-status\n", encoding="utf-8")
        runtime = mxctl.runtime_dir()
        status = runtime / "status.json"
        status.symlink_to(victim)
        mxctl.atomic_write(status, {"ok": True, "devices": []})
        self.assertEqual(victim.read_text(encoding="utf-8"), "keep-status\n")
        self.assertTrue(status.is_file())
        self.assertFalse(status.is_symlink())
        self.assertTrue(json.loads(status.read_text(encoding="utf-8"))["ok"])

    def test_cleanup_same_directory(self):
        proc = self.run_helper("write-cmd", json.dumps({"op": "refresh"}))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((Path(self.xdg) / "omarchy-mx" / "cmd.json").exists())
        cleaned = self.run_helper("cleanup")
        self.assertEqual(cleaned.returncode, 0, cleaned.stderr)
        self.assertFalse((Path(self.xdg) / "omarchy-mx" / "cmd.json").exists())
        self.assertFalse((Path(self.xdg) / "omarchy-mx" / "mxctl.lock").exists())

    def test_cleanup_keeps_status_cache(self):
        runtime = mxctl.runtime_dir()
        status = runtime / "status.json"
        mxctl.atomic_write(status, {"ok": True, "devices": [{"name": "MX Master 3S"}]})
        cleaned = self.run_helper("cleanup")
        self.assertEqual(cleaned.returncode, 0, cleaned.stderr)
        self.assertTrue(status.is_file())
        self.assertEqual(json.loads(status.read_text(encoding="utf-8"))["ok"], True)

    def test_serve_exits_when_lock_held(self):
        lock = mxctl.acquire_lock(blocking=True)
        self.addCleanup(lock.close)
        started = time.perf_counter()
        proc = self.run_helper("serve")
        self.assertEqual(proc.returncode, 3, proc.stderr)
        self.assertLess(time.perf_counter() - started, 0.6)

    def test_profiles_dir_mode_0700(self):
        path = mxctl.profiles_file()
        self.assertEqual(path, Path(self.config) / "omarchy-mx" / "profiles.json")
        self.assertTrue(path.parent.is_dir())
        self.assertFalse(path.parent.is_symlink())
        self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)

    def test_profiles_dir_chmods_existing(self):
        folder = Path(self.config) / "omarchy-mx"
        folder.mkdir(mode=0o755)
        os.chmod(folder, 0o755)
        path = mxctl.profiles_file()
        self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)

    def test_profiles_dir_replaces_nondir_and_symlink(self):
        folder = Path(self.config) / "omarchy-mx"
        folder.write_text("not-a-dir\n", encoding="utf-8")
        path = mxctl.profiles_file()
        self.assertTrue(path.parent.is_dir())
        self.assertFalse(path.parent.is_symlink())
        real = Path(self.config) / "other"
        real.mkdir()
        if path.parent.exists():
            shutil.rmtree(path.parent)
        folder.symlink_to(real)
        path = mxctl.profiles_file()
        self.assertTrue(path.parent.is_dir())
        self.assertFalse(path.parent.is_symlink())
        self.assertTrue(real.is_dir())

    def test_profiles_read_symlink_does_not_follow(self):
        victim = Path(self.config) / "secret.json"
        victim.write_text('{"version": 1, "profiles": [{"name": "Stolen"}]}\n', encoding="utf-8")
        folder = Path(self.config) / "omarchy-mx"
        folder.mkdir()
        planted = folder / "profiles.json"
        planted.symlink_to(victim)
        data = mxctl.load_profiles()
        self.assertEqual(data["profiles"], [])
        self.assertEqual(json.loads(victim.read_text(encoding="utf-8"))["profiles"][0]["name"], "Stolen")
        self.assertTrue(planted.is_symlink())

    def test_profiles_write_mode_0600(self):
        mxctl.write_profiles({"version": 1, "profiles": [{"name": "Desk", "settings": []}]})
        path = mxctl.profiles_file()
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertFalse(path.is_symlink())

    def test_profile_name_strips_markup(self):
        self.assertEqual(mxctl.sanitize_profile_name("  Desk  "), "Desk")
        self.assertEqual(mxctl.sanitize_profile_name('  <Desk>  '), "Desk")
        self.assertEqual(mxctl.sanitize_profile_name('<img src="https://evil">'), 'img src="https://evil"')
        with self.assertRaises(ValueError):
            mxctl.sanitize_profile_name("<>")

    def test_profile_apply_skips_change_host(self):
        source = HELPER.read_text(encoding="utf-8")
        start = source.index("def profile_apply")
        end = source.index("def apply_cmd")
        self.assertIn("PROFILE_SKIP", source[start:end])

    def test_hid_facing_texts_are_plain(self):
        settings = SETTINGS.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        bar = BAR.read_text(encoding="utf-8")

        def near(source, needle):
            idx = source.find(needle)
            self.assertNotEqual(idx, -1, needle)
            window = source[max(0, idx - 120):idx + 900]
            self.assertIn("textFormat: Text.PlainText", window, needle)

        near(settings, 'text: device ? root.hidName(device, "MX Control")')
        near(settings, "Reading settings")
        near(settings, "root.divertBoard.familyLabel")
        near(settings, "root.selectedCapTitle()")
        near(settings, 'text: root.hidName(modelData, "Profile")')
        near(settings, "cap.title || cap.glyph || cap.id")
        near(panel, "return mx.lastError")
        self.assertIn("Model.plainHidText", bar)
        self.assertIn("tooltipText", bar)
        self.assertIn("function hidName", settings)


if __name__ == "__main__":
    unittest.main()
