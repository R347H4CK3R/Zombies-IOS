from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ConvertedProductionRoutingTests(unittest.TestCase):
    def test_gameplay_uses_only_converted_runtime_package(self):
        source = (ROOT / "Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift").read_text()
        self.assertIn("ConvertedRuntimePackage", source)
        self.assertIn("ConvertedTranzitSceneView", source)
        self.assertNotIn("decodeT6Payload", source)
        self.assertNotIn("T6PS3PayloadDecoder", source)
        self.assertNotIn("T6GfxSurfaceMeshExtractor", source)
        self.assertNotIn("NativeFPSSceneView", source)

    def test_import_view_blocks_until_conversion_is_ready(self):
        source = (ROOT / "Sources/ZombiesIOS/Views/ConvertedTranzitImportView.swift").read_text()
        self.assertIn("ConvertedTranzitImporter", source)
        self.assertIn("ConvertedTranzitLoader", source)
        self.assertIn("ConvertedSourceFingerprint", source)
        self.assertIn("ProgressView", source)
        self.assertIn("TranzitTouchGameplayView", source)
        self.assertIn("lastError", source)

    def test_content_route_enters_conversion_before_gameplay(self):
        source = (ROOT / "Sources/ZombiesIOS/ContentView.swift").read_text()
        self.assertIn("ConvertedTranzitImportView", source)
        self.assertNotIn("TranzitTouchGameplayView(\n                                    loadedArea:", source)


if __name__ == "__main__":
    unittest.main()
