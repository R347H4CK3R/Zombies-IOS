import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from Tools.ci_visual_validate import analyze_image, validate_diagnostics


class CIVisualValidateTests(unittest.TestCase):
    def test_black_viewport_fails(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "black.png"
            Image.new("RGB", (400, 800), (0, 0, 0)).save(path)
            self.assertFalse(analyze_image(path)["passes_visibility"])

    def test_visible_geometry_passes(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "visible.png"
            image = Image.new("RGB", (400, 800), (3, 3, 3))
            draw = ImageDraw.Draw(image)
            draw.rectangle((60, 180, 340, 520), fill=(170, 170, 170))
            draw.line((60, 180, 340, 520), fill=(0, 255, 0), width=5)
            image.save(path)
            self.assertTrue(analyze_image(path)["passes_visibility"])

    def test_invalid_diagnostics_fail(self):
        self.assertFalse(validate_diagnostics({"ready": False})["passes_diagnostics"])

    def test_valid_diagnostics_pass(self):
        diag = {
            "ready": True,
            "vertexCount": 8,
            "indexCount": 36,
            "triangleCount": 12,
            "worldInFrustum": True,
            "frameCount": 24,
            "lastFrameTimestamp": 1.0,
        }
        self.assertTrue(validate_diagnostics(diag)["passes_diagnostics"])


if __name__ == "__main__":
    unittest.main()
