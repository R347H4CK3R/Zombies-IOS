from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ConvertedCIRouteTests(unittest.TestCase):
    def test_ci_fixture_builds_native_converted_package(self):
        fixture = (ROOT / "Sources/ZombiesIOS/Support/CIConvertedPackageFixture.swift").read_text()
        self.assertIn("ConvertedMeshFormat.encode", fixture)
        self.assertIn("ConvertedTranzitManifest", fixture)
        self.assertIn("ConvertedPackageStore", fixture)
        self.assertIn("materials/materials.json", fixture)
        self.assertIn("weapons/primary.mesh", fixture)
        self.assertIn("ConvertedTranzitLoader", fixture)

    def test_ci_entry_renders_converted_package_not_raw_runtime_fixture(self):
        view = (ROOT / "Sources/ZombiesIOS/Views/CIGameplayValidationEntryView.swift").read_text()
        self.assertIn("CIConvertedPackageFixture", view)
        self.assertIn("ConvertedTranzitSceneView", view)
        self.assertNotIn("CIRuntimeMeshFixture", view)
        self.assertNotIn("NativeFPSSceneView", view)


if __name__ == "__main__":
    unittest.main()
