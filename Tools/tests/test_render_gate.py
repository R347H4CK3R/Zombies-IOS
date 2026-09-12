import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from Tools import render_gate


class RenderGateTests(unittest.TestCase):
    def test_all_black_image_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            screenshot = root / "black.png"
            metrics = root / "metrics.json"
            write_png(screenshot, 10, 10, [(0, 0, 0, 255)] * 100)
            write_metrics(metrics, black_ratio=1.0)

            self.assertEqual(render_gate.main([str(screenshot), str(metrics)]), 1)

    def test_ninety_eight_percent_black_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            screenshot = root / "mostly-black.png"
            metrics = root / "metrics.json"
            pixels = [(0, 0, 0, 255)] * 98 + [(220, 100, 40, 255)] * 2
            write_png(screenshot, 10, 10, pixels)
            write_metrics(metrics, black_ratio=0.98)

            self.assertEqual(render_gate.main([str(screenshot), str(metrics)]), 1)

    def test_varied_non_black_image_with_real_metrics_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            screenshot = root / "scene.png"
            metrics = root / "metrics.json"
            pixels = []
            for y in range(10):
                for x in range(10):
                    pixels.append((30 + x * 10, 25 + y * 8, 40 + ((x + y) % 5) * 15, 255))
            write_png(screenshot, 10, 10, pixels)
            write_metrics(metrics, black_ratio=0.0)

            self.assertEqual(render_gate.main([str(screenshot), str(metrics)]), 0)

    def test_fallback_only_metrics_fail_even_with_bright_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            screenshot = root / "bright.png"
            metrics = root / "metrics.json"
            write_png(screenshot, 4, 4, [(200, 120, 60, 255)] * 16)
            metrics.write_text(json.dumps({
                "submittedTriangles": 500,
                "drawnSurfaces": 4,
                "nonFallbackMaterials": 0,
                "residentTextures": 0,
                "renderedProps": 0,
                "validCamera": True,
                "blackPixelRatio": 0.0,
            }))

            self.assertEqual(render_gate.main([str(screenshot), str(metrics)]), 1)

    def test_missing_camera_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            screenshot = root / "bright.png"
            metrics = root / "metrics.json"
            write_png(screenshot, 4, 4, [(200, 120, 60, 255)] * 16)
            write_metrics(metrics, black_ratio=0.0, valid_camera=False)

            self.assertEqual(render_gate.main([str(screenshot), str(metrics)]), 1)


def write_metrics(path: Path, black_ratio: float, valid_camera: bool = True):
    path.write_text(json.dumps({
        "submittedTriangles": 500,
        "drawnSurfaces": 4,
        "nonFallbackMaterials": 2,
        "residentTextures": 2,
        "renderedProps": 1,
        "validCamera": valid_camera,
        "blackPixelRatio": black_ratio,
    }))


def write_png(path: Path, width: int, height: int, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixels[y * width + x])

    def chunk(kind: bytes, data: bytes):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    payload = signature + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")
    path.write_bytes(payload)


if __name__ == "__main__":
    unittest.main()
