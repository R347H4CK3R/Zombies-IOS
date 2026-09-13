import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.gfxworld import (
    decode_vertex_data0,
    decode_vertex_data1,
    parse_surface,
    remap_surface_indices,
)


class WorldMaterialPipelineTests(unittest.TestCase):
    def test_decodes_t6_split_world_vertex_streams(self):
        vd0 = struct.pack('>3ff4B4f', 1.0, 2.0, 3.0, -1.0, 10, 20, 30, 255, 0.25, 0.5, 0.75, 1.0)
        vd1 = struct.pack('>II', 0x11223344, 0x55667788)
        v0 = decode_vertex_data0(vd0, '>')[0]
        v1 = decode_vertex_data1(vd1, '>')[0]
        self.assertEqual(v0.position, (1.0, 3.0, -2.0))
        self.assertEqual(v0.color, (10, 20, 30, 255))
        self.assertEqual(v0.uv, (0.25, 0.5))
        self.assertEqual(v0.lightmap_uv, (0.75, 1.0))
        self.assertEqual(v1.normal_packed, 0x11223344)
        self.assertEqual(v1.tangent_packed, 0x55667788)

    def test_parses_surface_material_and_light_indices(self):
        raw = bytearray(0x50)
        struct.pack_into('>3fi3fiifHHI', raw, 0,
                         -1.0, -2.0, -3.0, 0,
                         1.0, 2.0, 3.0, 0,
                         70000, 1.0, 3, 1, 12)
        struct.pack_into('>I4B', raw, 0x30, 0xAABBCCDD, 2, 3, 4, 5)
        surface = parse_surface(bytes(raw), 0, '>')
        self.assertEqual(surface.first_vertex, 70000)
        self.assertEqual(surface.material_ref, 0xAABBCCDD)
        self.assertEqual(surface.lightmap_index, 2)
        self.assertEqual(surface.reflection_probe_index, 3)
        self.assertEqual(surface.primary_light_index, 4)
        self.assertEqual(surface.flags, 5)

    def test_remaps_indices_above_uint16_runtime_limit(self):
        mapped = remap_surface_indices(
            [0, 1, 2], first_vertex=70000, vertex_count=3, base_output=70000
        )
        self.assertEqual(mapped, [70000, 70001, 70002])
        self.assertGreater(mapped[2], 65535)

    def test_accepts_global_source_indices_and_rebases_to_runtime(self):
        mapped = remap_surface_indices(
            [70000, 70001, 70002], first_vertex=70000, vertex_count=3, base_output=90000
        )
        self.assertEqual(mapped, [90000, 90001, 90002])


if __name__ == '__main__':
    unittest.main()
