from pathlib import Path
from tempfile import TemporaryDirectory
import json
import zipfile
import unittest

from Clean.BO2Quake.Converter.bo2convert.completion import validate_completion, REQUIRED_FAMILIES
from Clean.BO2Quake.Converter.bo2convert.packager import package_self_contained_ipa


class CompletionPackagerTests(unittest.TestCase):
    def _manifest(self, root: Path, complete: bool = True):
        assets = []
        for family in REQUIRED_FAMILIES:
            payload = root / family / 'fixture.bin'
            payload.parent.mkdir(parents=True, exist_ok=True)
            payload.write_bytes((family + '\n').encode())
            assets.append({
                'id': family + ':fixture', 'kind': family, 'version': 1,
                'sourceHash': '0' * 64, 'dependencies': [],
                'payloads': [str(payload.relative_to(root))],
                'validation': 'complete' if complete else 'incomplete',
            })
        manifest = {'formatVersion': 1, 'assets': assets, 'conversionFailures': [], 'unsupportedSemantics': []}
        (root / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True))

    def test_completion_requires_every_required_family(self):
        with TemporaryDirectory() as td:
            root = Path(td) / 'GameData'; root.mkdir()
            self._manifest(root)
            result = validate_completion(root)
            self.assertTrue(result.complete, result.failures)
            (root / 'audio' / 'fixture.bin').unlink()
            result = validate_completion(root)
            self.assertFalse(result.complete)
            self.assertTrue(any('missing payload' in x for x in result.failures))

    def test_completion_rejects_conversion_failures_and_unsupported_semantics(self):
        with TemporaryDirectory() as td:
            root = Path(td) / 'GameData'; root.mkdir()
            self._manifest(root)
            manifest = json.loads((root / 'manifest.json').read_text())
            manifest['conversionFailures'] = ['bad.ff']
            manifest['unsupportedSemantics'] = ['shader:unknown']
            (root / 'manifest.json').write_text(json.dumps(manifest))
            result = validate_completion(root)
            self.assertFalse(result.complete)
            self.assertTrue(any('conversion failure' in x for x in result.failures))
            self.assertTrue(any('unsupported semantic' in x for x in result.failures))

    def test_packager_embeds_gamedata_and_does_not_require_source_dump(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            game = root / 'GameData'; game.mkdir(); self._manifest(game)
            app = root / 'BO2Quake.app'; app.mkdir()
            (app / 'BO2Quake').write_bytes(b'executable')
            out = root / 'BO2Quake-self-contained.ipa'
            report = package_self_contained_ipa(app, game, out)
            self.assertTrue(report.complete)
            self.assertTrue(out.is_file())
            with zipfile.ZipFile(out) as zf:
                names = set(zf.namelist())
                self.assertIn('Payload/BO2Quake.app/BO2Quake', names)
                self.assertIn('Payload/BO2Quake.app/GameData/manifest.json', names)
                self.assertIn('Payload/BO2Quake.app/GameData/worlds/fixture.bin', names)
                self.assertFalse(any('PS3_GAME' in name or name.endswith('.ff') or name.endswith('.ipak') or name.endswith('.sabs') for name in names))

    def test_packager_refuses_incomplete_gamedata(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            game = root / 'GameData'; game.mkdir(); self._manifest(game, complete=False)
            app = root / 'BO2Quake.app'; app.mkdir(); (app / 'BO2Quake').write_bytes(b'x')
            with self.assertRaises(ValueError):
                package_self_contained_ipa(app, game, root / 'bad.ipa')


if __name__ == '__main__':
    unittest.main()
