import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.xfile import (
    T6_BLOCK_NAMES,
    XFileLayout,
)


class XFileBlockTests(unittest.TestCase):
    def test_parses_eight_t6_blocks_and_contiguous_ranges(self):
        sizes = [16, 8, 4, 12, 0, 20, 24, 0]
        payload = struct.pack('>10I', sum(sizes), 0, *sizes) + bytes(sum(sizes))
        layout = XFileLayout.parse(payload)
        self.assertEqual(tuple(layout.blocks), T6_BLOCK_NAMES)
        self.assertEqual(layout.blocks['temp'].start, 40)
        self.assertEqual(layout.blocks['runtime_virtual'].start, 56)
        self.assertEqual(layout.blocks['physical'].size, 24)
        self.assertEqual(layout.blocks['physical'].end, len(payload))

    def test_block_cursor_alignment_and_bounds(self):
        sizes = [32, 16, 0, 0, 0, 0, 0, 0]
        payload = struct.pack('>10I', sum(sizes), 0, *sizes) + bytes(range(48))
        layout = XFileLayout.parse(payload)
        cursor = layout.cursor('temp')
        self.assertEqual(cursor.read(3), bytes([0, 1, 2]))
        cursor.align(4)
        self.assertEqual(cursor.tell(), 4)
        self.assertEqual(cursor.read(4), bytes([4, 5, 6, 7]))
        with self.assertRaisesRegex(ValueError, 'block bounds'):
            cursor.read(100)

    def test_rejects_header_size_that_does_not_match_payload(self):
        payload = struct.pack('>10I', 99, 0, 4, 0, 0, 0, 0, 0, 0, 0) + b'abcd'
        with self.assertRaisesRegex(ValueError, 'XFile size'):
            XFileLayout.parse(payload)


if __name__ == '__main__':
    unittest.main()
