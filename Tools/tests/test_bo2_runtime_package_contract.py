from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackage.swift"
WRITER = ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackageWriter.swift"


class RuntimePackageContractTests(unittest.TestCase):
    def test_package_is_versioned_and_uses_32_bit_indices(self):
        text = MODEL.read_text(encoding="utf-8")
        self.assertIn("static let formatVersion: UInt32 = 1", text)
        self.assertIn("let indices: [UInt32]", text)
        self.assertIn("let spawns: [BO2RuntimeSpawn]", text)
        self.assertIn("let entities: [BO2RuntimeEntity]", text)

    def test_package_has_explicit_coordinate_contract(self):
        text = MODEL.read_text(encoding="utf-8")
        self.assertIn('bo2ToRuntime', text)
        self.assertIn('SIMD3<Float>(value.x, value.z, -value.y)', text)

    def test_writer_targets_expressive_cache(self):
        text = WRITER.read_text(encoding="utf-8")
        self.assertIn("RuntimeCachePolicy.expressiveDirectory()", text)
        self.assertIn('appendingPathComponent("world.vertices.bin")', text)
        self.assertIn('appendingPathComponent("world.indices.bin")', text)
        self.assertNotIn("Bundle.main", text)


if __name__ == "__main__":
    unittest.main()
