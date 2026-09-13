from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from Clean.BO2Quake.Converter.bo2convert.runtime_format import GameDataBuilder, PACKAGE_DIRS

REQUIRED = {
    'world','collision','material','texture','model','animation','audio','weapon',
    'attachment','effect','entity','script','gamemode','ai','vehicle','ui',
    'localization','cinematic',
}


class FullGameDataFamiliesTests(unittest.TestCase):
    def test_builder_supports_every_final_completion_family(self):
        self.assertTrue(REQUIRED.issubset(PACKAGE_DIRS.keys()), REQUIRED - set(PACKAGE_DIRS))
        with TemporaryDirectory() as td:
            builder = GameDataBuilder(Path(td))
            for kind in sorted(REQUIRED):
                builder.add_asset(
                    f'{kind}:fixture', kind, '0' * 64, (),
                    {'runtime.bin': kind.encode('utf-8')},
                )
            manifest = builder.finalize(REQUIRED)
            self.assertTrue(manifest['complete'], manifest['failures'])
            self.assertEqual({a['kind'] for a in manifest['assets']}, REQUIRED)


if __name__ == '__main__':
    unittest.main()
