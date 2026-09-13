from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from Clean.BO2Quake.Converter.bo2convert.runtime_format import GameDataBuilder, validate_gamedata


class GameDataFormatTests(unittest.TestCase):
    def test_manifest_is_versioned_and_deterministic(self):
        with TemporaryDirectory() as td:
            root = Path(td) / 'GameData'
            builder = GameDataBuilder(root)
            builder.add_asset('world:hijacked', 'world', 'a' * 64, [], {'mesh': b'abc'})
            builder.add_asset('material:test', 'material', 'b' * 64, ['world:hijacked'], {'material': b'{}'})
            first = builder.finalize(required_classes=['world', 'material'])
            bytes1 = (root / 'manifest.json').read_bytes()
            second = builder.finalize(required_classes=['world', 'material'])
            bytes2 = (root / 'manifest.json').read_bytes()
            self.assertEqual(bytes1, bytes2)
            self.assertEqual(first['formatVersion'], 1)
            self.assertEqual(second['complete'], True)

    def test_missing_dependency_is_rejected(self):
        with TemporaryDirectory() as td:
            root = Path(td) / 'GameData'
            builder = GameDataBuilder(root)
            builder.add_asset('weapon:test', 'weapon', 'c' * 64, ['model:missing'], {'weapon': b'{}'})
            builder.finalize(required_classes=['weapon'])
            report = validate_gamedata(root)
            self.assertFalse(report['complete'])
            self.assertTrue(any('model:missing' in item for item in report['failures']))

    def test_major_package_directories_are_created(self):
        with TemporaryDirectory() as td:
            root = Path(td) / 'GameData'
            GameDataBuilder(root)
            for name in ('worlds','materials','textures','models','animations','audio','weapons','entities','scripts','gamemodes','ui'):
                self.assertTrue((root / name).is_dir(), name)


if __name__ == '__main__':
    unittest.main()
