import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('assets', Path(__file__).resolve().parents[1] / 'scripts/assets.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)

class AssetsTest(unittest.TestCase):
    def test_public_excludes_personal_config_and_unreviewed_files(self):
        with tempfile.TemporaryDirectory() as temp:
            src, dst = Path(temp)/'web', Path(temp)/'out'
            src.mkdir()
            for name in assets.PUBLIC_ASSETS:
                (src/name).write_text('public')
            (src/'local-config.js').write_text('PRIVATE_SENTINEL')
            (src/'private-backup.json').write_text('PRIVATE_SENTINEL')
            assets.stage_assets(src, dst)
            self.assertEqual((dst/'local-config.js').read_text(), assets.EMPTY_CONFIG)
            self.assertEqual(set(p.name for p in dst.iterdir()), set(assets.PUBLIC_ASSETS)|{'local-config.js'})
            assets.stage_assets(src, dst, personal=True)
            self.assertEqual((dst/'local-config.js').read_text(), 'PRIVATE_SENTINEL')
