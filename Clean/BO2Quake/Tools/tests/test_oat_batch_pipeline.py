from pathlib import Path
from tempfile import TemporaryDirectory
import stat
import unittest

from Clean.BO2Quake.Converter.bo2convert.discovery import discover_dump
from Clean.BO2Quake.Converter.bo2convert.ledger import ConversionLedger
from Clean.BO2Quake.Converter.bo2convert.oat_backend import OATBackend
from Clean.BO2Quake.Converter.bo2convert.oat_pipeline import extract_fastfiles


class OATBatchPipelineTests(unittest.TestCase):
    def _tool(self, root: Path) -> Path:
        tool = root / 'fake-unlinker'
        tool.write_text('''#!/bin/sh
set -eu
OUT="$2"
ZONE="${8:-${7:-${6:-$#}}}"
# Last argument is the zone path.
for last; do :; done
ZONE="$last"
NAME=$(basename "$ZONE" .ff)
mkdir -p "$OUT/$NAME/materials" "$OUT/$NAME/xmodel" "$OUT/$NAME/weapons"
printf '{"name":"m"}' > "$OUT/$NAME/materials/$NAME.json"
printf glb > "$OUT/$NAME/xmodel/$NAME.glb"
printf 'ammo=30\\n' > "$OUT/$NAME/weapons/$NAME"
''')
        tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
        return tool

    def test_extracts_every_fastfile_and_records_resume(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            dump = root / 'PS3_GAME'; english = dump / 'USRDIR' / 'english'; english.mkdir(parents=True)
            (english / 'a.ff').write_bytes(b'a')
            (english / 'b.ff').write_bytes(b'b')
            (english / 'ignore.ipak').write_bytes(b'IPAK')
            inventory = discover_dump(dump)
            ledger = ConversionLedger.open(root / 'state.json')
            result = extract_fastfiles(
                inventory,
                source_root=dump,
                staging_root=root / 'oat',
                backend=OATBackend(self._tool(root)),
                ledger=ledger,
            )
            self.assertTrue(result.complete, result.failures)
            self.assertEqual(result.zones_processed, 2)
            self.assertEqual(result.zones_skipped, 0)
            self.assertGreaterEqual(len(result.outputs), 6)
            ledger.save()

            ledger2 = ConversionLedger.open(root / 'state.json')
            result2 = extract_fastfiles(
                inventory,
                source_root=dump,
                staging_root=root / 'oat',
                backend=OATBackend(self._tool(root)),
                ledger=ledger2,
            )
            self.assertTrue(result2.complete)
            self.assertEqual(result2.zones_processed, 0)
            self.assertEqual(result2.zones_skipped, 2)

    def test_one_failed_zone_is_explicit_completion_failure(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            dump = root / 'PS3_GAME'; english = dump / 'USRDIR' / 'english'; english.mkdir(parents=True)
            (english / 'bad.ff').write_bytes(b'bad')
            tool = root / 'bad-unlinker'; tool.write_text('#!/bin/sh\nexit 9\n'); tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
            result = extract_fastfiles(
                discover_dump(dump), source_root=dump, staging_root=root / 'oat',
                backend=OATBackend(tool), ledger=ConversionLedger.open(root / 'state.json'),
            )
            self.assertFalse(result.complete)
            self.assertEqual(result.zones_failed, 1)
            self.assertTrue(any('bad.ff' in failure for failure in result.failures))


if __name__ == '__main__':
    unittest.main()
