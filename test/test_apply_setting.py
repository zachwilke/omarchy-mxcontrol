import unittest
from types import SimpleNamespace

from test_plain_hid_text import mxctl


class FakeRangeSetting:
    name = "force-sensing"
    kind = 0x04

    def __init__(self):
        self.written = []

    def write(self, value, save=True):
        self.written.append(value)
        return value


class ApplyRangeSettingTests(unittest.TestCase):
    def test_plain_value(self):
        setting = FakeRangeSetting()
        mxctl.apply_setting(setting, None, 4105)
        self.assertEqual(setting.written, [4105])

    def test_single_force_button_map_from_saved_profile(self):
        # profiles.json stores ForceSensing's read() result, {"0": 4105}.
        setting = FakeRangeSetting()
        mxctl.apply_setting(setting, None, {"0": 4105})
        self.assertEqual(setting.written, [4105])


if __name__ == "__main__":
    unittest.main()
