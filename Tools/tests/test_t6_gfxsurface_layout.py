import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SURFACE = ROOT / "Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift"
BOUNDS = ROOT / "Sources/ZombiesIOS/Services/T6GfxBoundsFallbackExtractor.swift"


class T6GfxSurfaceLayoutTests(unittest.TestCase):
    def test_real_mesh_extractor_uses_t6_srftriangles_offsets(self):
        source = SURFACE.read_text()
        expected = [
            "firstVertex = Int(Int32(bitPattern: be32(bytes, offset + 0x20)))",
            "himipRadiusInvSq = beFloat(bytes, offset + 0x24)",
            "vertexCount = Int(be16(bytes, offset + 0x28))",
            "triCount = Int(be16(bytes, offset + 0x2A))",
            "baseIndex = Int(Int32(bitPattern: be32(bytes, offset + 0x2C)))",
        ]
        for text in expected:
            self.assertIn(text, source)

    def test_bounds_fallback_uses_same_t6_srftriangles_offsets(self):
        source = BOUNDS.read_text()
        expected = [
            "firstVertex = Int(Int32(bitPattern: be32(bytes, offset + 0x20)))",
            "himip = beFloat(bytes, offset + 0x24)",
            "vertexCount = Int(be16(bytes, offset + 0x28))",
            "triCount = Int(be16(bytes, offset + 0x2A))",
            "baseIndex = Int(Int32(bitPattern: be32(bytes, offset + 0x2C)))",
        ]
        for text in expected:
            self.assertIn(text, source)


if __name__ == "__main__":
    unittest.main()
