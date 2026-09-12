from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ConvertedAssetArchitectureTests(unittest.TestCase):
    def test_manifest_and_paths_contract_exist(self):
        manifest = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitManifest.swift").read_text()
        paths = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitPaths.swift").read_text()
        fingerprint = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedSourceFingerprint.swift").read_text()
        self.assertIn("packageFormatVersion", manifest)
        self.assertIn("complete", manifest)
        self.assertIn("ConvertedTranzit", paths)
        self.assertIn("applicationSupportDirectory", paths)
        self.assertIn("modificationDate", fingerprint)
        self.assertIn("fileSize", fingerprint)


if __name__ == "__main__":
    unittest.main()
