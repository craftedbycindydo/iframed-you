import importlib.util
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import check_public

class PublicChecksTest(unittest.TestCase):
    def test_household_links_and_credentials_are_reported_without_values(self):
        cases = [
            (b'https://calendar.google.com/calendar/ical/test%40example.org/private-' + b'x'*32 + b'/basic.ics', 'private calendar feed'),
            (b'https://photos.app.goo.gl/' + b'privateSentinel123', 'shared photo link'),
            (b'https://home.google.com/u/0/home/' + b'privateSentinel123', 'household identifier'),
            (b'private-sentinel' + b'@gmail.com', 'personal email'),
            (b'-----BEGIN ' + b'PRIVATE KEY-----', 'private key'),
            (b'ghp_' + b'x'*40, 'GitHub token'),
        ]
        for data, label in cases:
            with self.subTest(label=label):
                self.assertIn(label, check_public.findings(data))
                self.assertNotIn(data.decode(), str(check_public.findings(data)))

    def test_generic_configuration_and_docs_links_are_allowed(self):
        self.assertEqual(check_public.findings(b'https://calendar.google.com/calendar/u/0/r https://home.google.com/u/0/'), [])
        self.assertEqual(check_public.findings('https://photos.app.goo.gl/…'.encode()), [])
        self.assertTrue(check_public.FORBIDDEN.search('web/local-config.js'))
        self.assertFalse(check_public.FORBIDDEN.search('web/local-config.example.js'))
        self.assertTrue(check_public.FORBIDDEN.search('.local/device.json'))
        self.assertTrue(check_public.FORBIDDEN.search('private.keystore'))
