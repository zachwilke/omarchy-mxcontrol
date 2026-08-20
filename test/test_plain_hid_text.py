import importlib.util
import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path


def load_mxctl():
    path = Path(__file__).resolve().parents[1] / "mxctl.py"
    spec = importlib.util.spec_from_file_location("mxctl", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mxctl = load_mxctl()


class PlainHidTextTests(unittest.TestCase):
    def test_keeps_logitech_adapter_names(self):
        self.assertEqual(mxctl.plain_hid_text("MX Master 3S"), "MX Master 3S")
        self.assertEqual(mxctl.plain_hid_text("Bolt Receiver"), "Bolt Receiver")
        self.assertEqual(mxctl.plain_hid_text("Unifying Receiver"), "Unifying Receiver")

    def test_strips_rich_text_markup(self):
        self.assertEqual(mxctl.plain_hid_text('<img src="https://evil">'), 'img src="https://evil"')
        self.assertEqual(mxctl.plain_hid_text("A <b>Bolt</b> Receiver"), "A bBolt/b Receiver")

    def test_empty_and_none(self):
        self.assertEqual(mxctl.plain_hid_text(""), "")
        self.assertEqual(mxctl.plain_hid_text(None), "")

    def test_fail_strips_markup_from_message(self):
        buf = io.StringIO()
        with self.assertRaises(SystemExit) as ctx, redirect_stdout(buf):
            mxctl.fail('MX <img src="https://evil"> is offline')
        self.assertEqual(ctx.exception.code, 1)
        payload = json.loads(buf.getvalue())
        self.assertEqual(payload["message"], 'MX img src="https://evil" is offline')
        self.assertNotIn("<", payload["message"])
        self.assertNotIn(">", payload["message"])

    def test_status_last_error_strips_markup(self):
        snap = mxctl.status_from_described([], [], [], "", 'MX <img src="https://evil"> is offline')
        self.assertEqual(snap["lastError"], 'MX img src="https://evil" is offline')
        self.assertNotIn("<", snap["lastError"])
        self.assertNotIn(">", snap["lastError"])


if __name__ == "__main__":
    unittest.main()
