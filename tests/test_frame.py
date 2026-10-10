import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('frame', Path(__file__).resolve().parents[1] / 'scripts/frame.py')
frame = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frame)


class DiscoveryTests(unittest.TestCase):
    def test_selects_only_target_tls_connection(self):
        listing = '''List of discovered mdns services
adb-OTHER-key _adb-tls-connect._tcp 10.0.0.20:40000
adb-TARGET-key _adb-tls-pairing._tcp 10.0.0.21:41000
adb-TARGET-key _adb._tcp 10.0.0.21:5555
adb-TARGET-key _adb-tls-connect._tcp 10.0.0.21:42000
'''
        self.assertEqual(frame.tls_endpoint(listing, 'TARGET'), '10.0.0.21:42000')
        self.assertIsNone(frame.tls_endpoint(listing, 'MISSING'))

    def test_reuses_live_tls_transport_when_mdns_listing_is_empty(self):
        listing = "TARGET device\nadb-TARGET-key._adb-tls-connect._tcp device\nadb-OTHER-key._adb-tls-connect._tcp device"
        self.assertEqual(frame.connected_tls(listing, "TARGET"), "adb-TARGET-key._adb-tls-connect._tcp")
        self.assertIsNone(frame.connected_tls("10.0.0.21:5555 device", "TARGET"))

    def test_rejects_serial_prefix_collision(self):
        self.assertIsNone(frame.tls_endpoint('adb-TARGET2-key _adb-tls-connect._tcp 10.0.0.21:42000', 'TARGET'))

    def test_rejects_malformed_endpoints(self):
        for value in ('10.0.0.21:0', '10.0.0.21:65536', 'bad-host:1234'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                frame.checked_endpoint(value)


if __name__ == '__main__':
    unittest.main()
