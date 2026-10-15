import importlib.util
import unittest
from pathlib import Path


def load_mxctl():
    path = Path(__file__).resolve().parents[1] / "mxctl.py"
    spec = importlib.util.spec_from_file_location("mxctl", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mxctl = load_mxctl()


class DeviceNameTests(unittest.TestCase):
    def test_accepts_pro_series_names_without_the_g(self):
        # Solaar's name and codename for a PRO X Wireless (WPID 4093) on Lightspeed.
        self.assertTrue(mxctl.is_mx_name("PRO X Wireless"))
        self.assertTrue(mxctl.is_mx_name("PRO X"))

    def test_still_accepts_g_series_names(self):
        self.assertTrue(mxctl.is_mx_name("G Pro Wireless Gaming Mouse"))
        self.assertTrue(mxctl.is_mx_name("G915 TKL LIGHTSPEED Wireless RGB Mechanical Gaming Keyboard"))
        self.assertTrue(mxctl.is_mx_name("MX Master 3S"))

    def test_rejects_pro_headsets_webcams_and_receivers(self):
        self.assertFalse(mxctl.is_mx_name("PRO X 2 LIGHTSPEED Gaming Headset"))
        self.assertFalse(mxctl.is_mx_name("C922 Pro Stream Webcam"))
        self.assertFalse(mxctl.is_mx_name("Lightspeed Receiver"))
        self.assertFalse(mxctl.is_mx_name("Programmable"))


if __name__ == "__main__":
    unittest.main()
