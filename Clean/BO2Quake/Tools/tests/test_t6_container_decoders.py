from pathlib import Path
from tempfile import TemporaryDirectory
import struct
import unittest
import zlib

from Clean.BO2Quake.Converter.bo2convert.t6.salsa20 import T6SalsaState
from Clean.BO2Quake.Converter.bo2convert.t6.fastfile import decode_fastfile
from Clean.BO2Quake.Converter.bo2convert.t6.ipak import IPAKArchive, lzo1x_decompress


class T6ContainerDecoderTests(unittest.TestCase):
    def test_lzo1x_known_vectors(self):
        vectors = [
            ('110000', b''),
            ('1231110000', b'1'),
            ('133132110000', b'12'),
            ('14414243110000', b'ABC'),
            ('1541424344110000', b'ABCD'),
            ('164142434445110000', b'ABCDE'),
            ('20796f6f796f6f796f6f796f6f796f6f110000', b'yooyooyooyooyoo'),
        ]
        for encoded, expected in vectors:
            self.assertEqual(lzo1x_decompress(bytes.fromhex(encoded)), expected)

    def test_salsa_state_roundtrip_for_first_stream_block(self):
        clear = b'hello t6 ps3' * 17
        encryptor = T6SalsaState('mp_test')
        encrypted = encryptor.crypt_without_advance(0, clear)
        decryptor = T6SalsaState('mp_test')
        self.assertEqual(decryptor.decrypt(0, encrypted), clear)

    def test_decodes_minimal_signed_fastfile_xchunk(self):
        with TemporaryDirectory() as td:
            path = Path(td) / 'mp_test.ff'
            zone = struct.pack('>10I', 40, 0, 0, 0, 0, 0, 0, 0, 0, 0) + b'payload'
            compressed = zlib.compress(zone)
            salsa = T6SalsaState('mp_test')
            encrypted = salsa.crypt_without_advance(0, compressed)
            auth = b'PHEEBs71' + struct.pack('>I', 0) + b'mp_test\0'.ljust(32, b'\0') + bytes(256)
            raw = b'TAff0100' + struct.pack('>I', 0x92) + auth + struct.pack('>I', len(encrypted)) + encrypted + struct.pack('>I', 0)
            path.write_bytes(raw)
            decoded = decode_fastfile(path)
            self.assertEqual(decoded.zone_bytes, zone)
            self.assertEqual(decoded.zone_name, 'mp_test')
            self.assertEqual(decoded.chunk_count, 1)

    def test_indexes_and_decodes_big_endian_ipak_entry(self):
        with TemporaryDirectory() as td:
            path = Path(td) / 'test.ipak'
            entry_key = 0x0123456789ABCDEF
            entry_offset = 0
            encoded_span = 192
            file_size = 256
            header = b'IPAK' + struct.pack('>III', 1, file_size, 2)
            segments = (
                struct.pack('>4I', 1, 48, 16, 1)
                + struct.pack('>4I', 2, 64, 192, 0)
            )
            entry = struct.pack('>QII', entry_key, entry_offset, encoded_span)
            first_word = 0x01000000
            commands = [3] + [0] * 30
            block_header = struct.pack('>I31I', first_word, *commands)
            data = b'abc' + bytes(61)
            path.write_bytes(header + segments + entry + block_header + data)

            archive = IPAKArchive(path)
            indexed = archive.index()
            self.assertEqual(indexed.endian, '>')
            self.assertEqual(len(indexed.entries), 1)
            self.assertEqual(indexed.entries[0].key, entry_key)
            decoded = archive.decode_entry(entry_key)
            self.assertEqual(decoded.data, b'abc')
            self.assertEqual(decoded.raw_blocks, 1)
            self.assertEqual(decoded.lzo_blocks, 0)


if __name__ == '__main__':
    unittest.main()
