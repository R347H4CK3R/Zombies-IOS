from pathlib import Path
from tempfile import TemporaryDirectory
import json
import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.xanim import parse_compiled_xanim_header, export_compiled_xanim


class XAnimPipelineTests(unittest.TestCase):
    def test_parses_oat_t6_v19_header(self):
        data = struct.pack('<HHHBBH', 19, 61, 24, 0, 2, 30) + b'payload'
        header = parse_compiled_xanim_header(data)
        self.assertEqual(header.version, 19)
        self.assertEqual(header.frame_count, 60)
        self.assertEqual(header.frame_rate, 30)
        self.assertEqual(header.duration, 2.0)
        self.assertFalse(header.looping)

    def test_looped_raw_stores_frame_count_directly(self):
        data = struct.pack('<HHHBBH', 19, 60, 24, 1, 2, 30)
        header = parse_compiled_xanim_header(data)
        self.assertEqual(header.frame_count, 60)
        self.assertTrue(header.looping)

    def test_exports_binary_unchanged_with_metadata(self):
        data = struct.pack('<HHHBBH', 19, 31, 4, 0, 1, 30) + bytes(range(32))
        with TemporaryDirectory() as td:
            root = Path(td)
            src = root / 'source.xanim'
            src.write_bytes(data)
            out = root / 'out'
            files = export_compiled_xanim(src, out, animation_id='test_anim', source_hash='a' * 64)
            self.assertEqual(files, ('animation.xanim', 'animation.json'))
            self.assertEqual((out / 'animation.xanim').read_bytes(), data)
            meta = json.loads((out / 'animation.json').read_text())
            self.assertEqual(meta['frameCount'], 30)
            self.assertEqual(meta['boneCount'], 4)

    def test_rejects_unknown_version(self):
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            parse_compiled_xanim_header(struct.pack('<HHHBBH', 99, 1, 0, 0, 0, 30))


if __name__ == '__main__':
    unittest.main()
