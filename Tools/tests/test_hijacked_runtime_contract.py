from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "Sources/ZombiesIOS/Models/BO2MapTarget.swift"
LOADER = ROOT / "Sources/ZombiesIOS/Services/BO2MapRuntimeLoader.swift"
SCANNER = ROOT / "Sources/ZombiesIOS/Services/PS3DumpScanner.swift"


class HijackedRuntimeContractTests(unittest.TestCase):
    def test_hijacked_source_names_are_declared(self):
        text = TARGET.read_text(encoding="utf-8")
        for name in ("mp_hijacked.ff", "mp_hijacked.ipak", "mpl_hijacked.all.sabs"):
            self.assertIn(name, text)

    def test_scanner_accepts_map_targets_without_relaxing_manifest_filter(self):
        text = SCANNER.read_text(encoding="utf-8")
        self.assertIn("BO2MapTarget.recognizes(relative)", text)
        self.assertIn("BO2ZombiesManifest.contains(relative)", text)

    def test_loader_uses_real_t6_decode_and_gfxworld_extractor(self):
        text = LOADER.read_text(encoding="utf-8")
        self.assertIn("T6PS3PayloadDecoder", text)
        self.assertIn("T6GfxSurfaceMeshExtractor.extract", text)
        self.assertIn("BO2RuntimePackageWriter.write", text)
        self.assertNotIn("T6GfxBoundsFallbackExtractor", text)


if __name__ == "__main__":
    unittest.main()
