import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.xasset import parse_xasset_list


class XAssetIndexTests(unittest.TestCase):
    def test_parses_inline_script_strings_dependencies_and_assets(self):
        # 0x28 XFile header + 0x18 XAssetList = first inline table at 0x40.
        zone = bytearray(256)
        struct.pack_into('>10I', zone, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        struct.pack_into('>iIiIiI', zone, 40,
                         2, 0xFFFFFFFF,
                         0, 0,
                         3, 0xFFFFFFFF)
        struct.pack_into('>2I', zone, 64, 0xFFFFFFFF, 0xFFFFFFFF)
        zone[72:78] = b'alpha\0'
        zone[78:83] = b'beta\0'
        # Alignment to 4 => asset array at 84. Each XAsset is type + header pointer.
        struct.pack_into('>II', zone, 84, 5, 0xFFFFFFFF)   # XMODEL
        struct.pack_into('>II', zone, 92, 9, 0xFFFFFFFF)   # IMAGE
        struct.pack_into('>II', zone, 100, 17, 0xFFFFFFFF) # MAP_ENTS

        parsed = parse_xasset_list(bytes(zone))
        self.assertEqual(parsed.script_strings, ('alpha', 'beta'))
        self.assertEqual(parsed.script_string_array_offset, 64)
        self.assertEqual(parsed.asset_array_offset, 84)
        self.assertEqual(parsed.asset_payload_offset, 108)
        self.assertEqual([asset.type_name for asset in parsed.assets], ['XMODEL', 'IMAGE', 'MAP_ENTS'])
        self.assertTrue(all(asset.header_word == 0xFFFFFFFF for asset in parsed.assets))

    def test_rejects_unknown_external_inline_table_pointer(self):
        zone = bytearray(128)
        struct.pack_into('>10I', zone, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        struct.pack_into('>iIiIiI', zone, 40,
                         1, 0x12345678,
                         0, 0,
                         0, 0)
        with self.assertRaisesRegex(ValueError, 'external script-string pointer'):
            parse_xasset_list(bytes(zone))


if __name__ == '__main__':
    unittest.main()
