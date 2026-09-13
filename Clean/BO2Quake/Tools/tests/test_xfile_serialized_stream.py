import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.xfile import XFileLayout, XFileSerializedStream


class XFileSerializedStreamTests(unittest.TestCase):
    def _payload(self):
        # Logical blocks: temp=8, runtime_virtual=16, virtual=8. Runtime bytes are
        # not serialized; the physical stream only contains TEMP + NORMAL reads.
        sizes = [8, 16, 0, 0, 0, 8, 0, 0]
        serialized = b'TEMP' + b'VIRT'
        return struct.pack('>10I', sum(sizes), 0, *sizes) + serialized

    def test_runtime_block_allocation_consumes_no_serialized_bytes(self):
        layout = XFileLayout.parse(self._payload())
        stream = XFileSerializedStream(layout)
        self.assertEqual(stream.load('temp', 4), b'TEMP')
        self.assertEqual(stream.load('runtime_virtual', 12), bytes(12))
        self.assertEqual(stream.serialized_offset, 44)
        self.assertEqual(stream.load('virtual', 4), b'VIRT')
        self.assertEqual(stream.serialized_offset, 48)

    def test_alignment_advances_logical_offset_only(self):
        sizes = [16, 0, 0, 0, 0, 8, 0, 0]
        payload = struct.pack('>10I', sum(sizes), 0, *sizes) + b'ABCDEFGH'
        stream = XFileSerializedStream(XFileLayout.parse(payload))
        self.assertEqual(stream.load('temp', 3), b'ABC')
        stream.align('temp', 8)
        self.assertEqual(stream.logical_offset('temp'), 8)
        self.assertEqual(stream.serialized_offset, 43)
        self.assertEqual(stream.load('temp', 2), b'DE')

    def test_offset_pointer_decodes_block_and_logical_offset(self):
        sizes = [0, 0, 0, 0, 0, 32, 32, 0]
        payload = struct.pack('>10I', sum(sizes), 0, *sizes)
        layout = XFileLayout.parse(payload)
        # T6 is 32-bit with 3 block bits: encoded pointer is (block << 29 | off) + 1.
        block = 6
        logical = 12
        encoded = ((block << 29) | logical) + 1
        ref = layout.decode_offset_pointer(encoded)
        self.assertEqual(ref.block_name, 'physical')
        self.assertEqual(ref.offset, logical)

    def test_following_and_insert_sentinels_are_not_offsets(self):
        layout = XFileLayout.parse(self._payload())
        self.assertEqual(layout.pointer_type(0), 'null')
        self.assertEqual(layout.pointer_type(0xFFFFFFFF), 'following')
        self.assertEqual(layout.pointer_type(0xFFFFFFFE), 'insert')


if __name__ == '__main__':
    unittest.main()
