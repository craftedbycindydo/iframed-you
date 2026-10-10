import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'check_network', Path(__file__).resolve().parents[1] / 'scripts/check_network.py'
)
check_network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_network)


class NetworkProbeTests(unittest.TestCase):
    def test_only_configured_authorized_usb_transport_is_accepted(self):
        listing = '''List of devices attached
OTHER device usb:1-1 product:frame
TARGET unauthorized usb:1-2 product:frame
adb-TARGET-key._adb-tls-connect._tcp device product:frame
'''
        self.assertFalse(check_network.usb_selected(listing, 'TARGET'))
        listing += 'TARGET device usb:1-2 product:frame\n'
        self.assertTrue(check_network.usb_selected(listing, 'TARGET'))

    def test_gateway_comes_from_selected_policy_route(self):
        route = '1.1.1.1 via 192.0.2.1 dev wlan0 table wlan0 src 192.0.2.44 uid 2000'
        self.assertEqual(check_network.gateway_from_route(route), '192.0.2.1')
        self.assertIsNone(check_network.gateway_from_route('default via 999.1.1.1 dev wlan0'))
        self.assertIsNone(check_network.gateway_from_route('unreachable 1.1.1.1'))


if __name__ == '__main__':
    unittest.main()
