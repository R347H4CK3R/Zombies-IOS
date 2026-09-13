import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.xfile import (
    T6_BLOCK_NAMES,
    XFileLayout,
    XFileSerializedStream,
)


class XFileBlockTests(unittest.TestCase):
    def test_parses_eight_t6_logical_blocks(self):
        sizes = [16, 8, 4, 12, 0, 20, 24, 0]
        # Logical runtime/delay sizes do not imply physically serialized bytes.
        payload = struct.pack('>10I', sum(sizes), 0, *sizes) + b'abc'
        layout = XFileLayout.parse(payload)
        self.assertEqual(tuple(layout.blocks), T6_BLOCK_NAMES)
        self.assertEqual(layout.blocks['temp'].start, 0)
        self.assertEqual(layout.blocks['runtime_virtual'].start, 16)
        self.assertEqual(layout.blocks['physical'].size, 24)
        self.assertEqual(layout.blocks['runtime_virtual'].block_type, 'runtime')
        self.assertEqual(layout.serialized_size, 3)

    def test_stream_alignment_and_bounds(self):
        sizes = [32, 16, 0, 0, 0, 0, 0, 0]
        payload = struct.pack('>10I', sum(sizes), 0, *sizes) + bytes(range(16))
        stream = XFileSerializedStream(XFileLayout.parse(payload))
        self.assertEqual(stream.load('temp', 3), bytes([0, 1, 2]))
        stream.align('temp', 4)
        self.assertEqual(stream.logical_offset('temp'), 4)
        # Logical alignment does not consume a serialized padding byte.
        self.assertEqual(stream.load('temp', 4), bytes([3, 4, 5, 6]))
        with self.assertRaisesRegex(ValueError, 'block bounds'):
            stream.load('temp', 100)

    def test_rejects_header_declared_size_mismatch(self):
        payload = struct.pack('>10I', 99, 0, 4, 0, 0, 0, 0, 0, 0, 0) + b'abcd'
        with self.assertRaisesRegex(ValueError, 'XFile size'):
            XFileLayout.parse(payload)


if __name__ == '__main__':
    unittest.main()
