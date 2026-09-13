import json
import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.gfxworld import (
    GfxSurfaceRecord,
    WorldVertexData0,
    WorldVertexData1,
)
from Clean.BO2Quake.Converter.bo2convert.world_export import build_world_payloads


class WorldRuntimeExportTests(unittest.TestCase):
    def test_exports_complete_vertex_attributes_indices_and_material_dependencies(self):
        vertices0 = [
            WorldVertexData0((0.0, 0.0, 0.0), 1.0, (255, 0, 0, 255), (0.0, 0.0), (0.0, 0.0)),
            WorldVertexData0((1.0, 0.0, 0.0), 1.0, (0, 255, 0, 255), (1.0, 0.0), (1.0, 0.0)),
            WorldVertexData0((0.0, 1.0, 0.0), 1.0, (0, 0, 255, 255), (0.0, 1.0), (0.0, 1.0)),
        ]
        vertices1 = [
            WorldVertexData1(0x01020304, 0x05060708),
            WorldVertexData1(0x11121314, 0x15161718),
            WorldVertexData1(0x21222324, 0x25262728),
        ]
        surface = GfxSurfaceRecord(
            mins=(0.0, 0.0, 0.0), maxs=(1.0, 1.0, 0.0),
            vertex_data_offset0=0, vertex_data_offset1=0, first_vertex=0,
            himip_radius_inv_sq=1.0, vertex_count=3, triangle_count=1,
            base_index=0, material_ref=0x1234, lightmap_index=2,
            reflection_probe_index=3, primary_light_index=4, flags=5,
        )
        index_data = struct.pack('>3H', 0, 1, 2)
        result = build_world_payloads(
            vertices0, vertices1, index_data, [surface],
            {0x1234: 'material:deck'}, endian='>'
        )

        self.assertEqual(result.dependencies, ('material:deck',))
        self.assertEqual(set(result.payloads), {'vertices.bin', 'indices.bin', 'surfaces.json'})
        self.assertEqual(len(result.payloads['vertices.bin']), 3 * 44)
        self.assertEqual(struct.unpack('<3I', result.payloads['indices.bin']), (0, 1, 2))
        metadata = json.loads(result.payloads['surfaces.json'])
        self.assertEqual(metadata['vertexStride'], 44)
        self.assertEqual(metadata['indexType'], 'uint32')
        self.assertEqual(metadata['surfaceCount'], 1)
        self.assertEqual(metadata['surfaces'][0]['material'], 'material:deck')
        self.assertEqual(metadata['surfaces'][0]['lightmapIndex'], 2)

    def test_rejects_unresolved_material_reference(self):
        vertices0 = [WorldVertexData0((0, 0, 0), 1.0, (255, 255, 255, 255), (0, 0), (0, 0))] * 3
        vertices1 = [WorldVertexData1(0, 0)] * 3
        surface = GfxSurfaceRecord((0,0,0),(1,1,1),0,0,0,1.0,3,1,0,99,0,0,0,0)
        with self.assertRaisesRegex(ValueError, 'unresolved material'):
            build_world_payloads(vertices0, vertices1, struct.pack('>3H', 0,1,2), [surface], {}, endian='>')


if __name__ == '__main__':
    unittest.main()
