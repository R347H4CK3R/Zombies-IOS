from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BO2EntityMappingTests(unittest.TestCase):
    def test_entity_parser_preserves_key_values_and_spawn_classes(self):
        path = ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2EntityParser.swift"
        self.assertTrue(path.exists())
        text = path.read_text()
        self.assertIn('"worldspawn"', text)
        self.assertIn('"mp_dm_spawn"', text)
        self.assertIn('"mp_tdm_spawn"', text)
        self.assertIn("BO2RuntimeSpawn", text)
        self.assertIn("convertOrigin", text)

    def test_loader_extracts_entities_from_decoded_zone(self):
        path = ROOT / "Sources/ZombiesIOS/Services/BO2MapRuntimeLoader.swift"
        text = path.read_text()
        self.assertIn("BO2EntityParser.extractEntityLump", text)
        self.assertIn("BO2EntityParser.parse", text)
        self.assertIn("entities:", text)
        self.assertIn("spawns:", text)


if __name__ == "__main__":
    unittest.main()
