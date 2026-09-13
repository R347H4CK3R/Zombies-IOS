from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from PIL import Image
from Clean.BO2Quake.Converter.bo2convert.t6.images import convert_image_to_png


class TextureConversionTests(unittest.TestCase):
    def test_converts_dds_to_rgba_png_and_metadata(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            src = root / 'fixture.dds'
            im = Image.new('RGBA', (4, 2), (17, 34, 51, 255))
            im.save(src, format='DDS')
            out = root / 'texture'
            result = convert_image_to_png(src, out, texture_id='fixture')
            self.assertEqual(result.payloads, ('texture.png','texture.json'))
            meta = json.loads((out / 'texture.json').read_text())
            self.assertEqual(meta['formatVersion'], 1)
            self.assertEqual(meta['width'], 4)
            self.assertEqual(meta['height'], 2)
            self.assertEqual(meta['pixelFormat'], 'rgba8-srgb')
            decoded = Image.open(out / 'texture.png').convert('RGBA')
            self.assertEqual(decoded.size, (4,2))
            self.assertEqual(decoded.getpixel((0,0)), (17,34,51,255))

    def test_rejects_unsupported_or_corrupt_source(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            src = root / 'bad.dds'; src.write_bytes(b'not-dds')
            with self.assertRaises(ValueError):
                convert_image_to_png(src, root / 'out', texture_id='bad')


if __name__ == '__main__':
    unittest.main()
