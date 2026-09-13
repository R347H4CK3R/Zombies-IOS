from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from Clean.BO2Quake.Converter.bo2convert.discovery import discover_dump
from Clean.BO2Quake.Converter.bo2convert.ledger import ConversionLedger


class FullDumpDiscoveryTests(unittest.TestCase):
    def test_discovers_recursive_t6_content_deterministically(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            (root / 'PS3_GAME' / 'USRDIR' / 'zone').mkdir(parents=True)
            (root / 'PS3_GAME' / 'USRDIR' / 'sound').mkdir(parents=True)
            (root / 'PS3_GAME' / 'USRDIR' / 'zone' / 'mp_hijacked.ff').write_bytes(b'abc')
            (root / 'PS3_GAME' / 'USRDIR' / 'zone' / 'mp_hijacked.ipak').write_bytes(b'def')
            (root / 'PS3_GAME' / 'USRDIR' / 'sound' / 'mpl_hijacked.all.sabs').write_bytes(b'ghi')
            (root / 'PS3_GAME' / 'USRDIR' / 'EBOOT.BIN').write_bytes(b'jkl')

            inventory = discover_dump(root)
            paths = [item.relative_path for item in inventory.files]
            self.assertEqual(paths, sorted(paths))
            self.assertIn('PS3_GAME/USRDIR/zone/mp_hijacked.ff', paths)
            self.assertIn('PS3_GAME/USRDIR/zone/mp_hijacked.ipak', paths)
            self.assertIn('PS3_GAME/USRDIR/sound/mpl_hijacked.all.sabs', paths)
            self.assertTrue(all(len(item.sha256) == 64 for item in inventory.files))

    def test_resume_ledger_only_accepts_matching_hash_and_converter_version(self):
        with TemporaryDirectory() as td:
            path = Path(td) / 'conversion-state.json'
            ledger = ConversionLedger.open(path)
            self.assertFalse(ledger.is_current('a' * 64, 'v1'))
            ledger.record_success('asset-key', 'a' * 64, 'v1', ['out.bin'])
            ledger.save()

            reloaded = ConversionLedger.open(path)
            self.assertTrue(reloaded.is_current('a' * 64, 'v1'))
            self.assertFalse(reloaded.is_current('b' * 64, 'v1'))
            self.assertFalse(reloaded.is_current('a' * 64, 'v2'))

    def test_failure_is_explicit_and_not_current(self):
        with TemporaryDirectory() as td:
            path = Path(td) / 'conversion-state.json'
            ledger = ConversionLedger.open(path)
            ledger.record_failure('broken', 'c' * 64, 'v1', 'decoder failed')
            ledger.save()
            data = json.loads(path.read_text())
            self.assertEqual(data['records']['broken']['status'], 'failed')
            self.assertFalse(ledger.is_current('c' * 64, 'v1'))


if __name__ == '__main__':
    unittest.main()
