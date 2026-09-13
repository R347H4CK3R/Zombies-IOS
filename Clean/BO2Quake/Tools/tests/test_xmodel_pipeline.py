from pathlib import Path
from tempfile import TemporaryDirectory
import json
import struct
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.xmodel import parse_xmodel_export, export_runtime_model

FIXTURE = '''// OpenAssetTools XMODEL_EXPORT File
MODEL
VERSION 6

NUMBONES 2
BONE 0 -1 "root"
BONE 1 0 "tag_weapon"

BONE 0
OFFSET 0.000000, 0.000000, 0.000000
SCALE 1.000000, 1.000000, 1.000000
X 1.000000, 0.000000, 0.000000
Y 0.000000, 1.000000, 0.000000
Z 0.000000, 0.000000, 1.000000

BONE 1
OFFSET 0.000000, 1.000000, 0.000000
SCALE 1.000000, 1.000000, 1.000000
X 1.000000, 0.000000, 0.000000
Y 0.000000, 1.000000, 0.000000
Z 0.000000, 0.000000, 1.000000

NUMVERTS 3
VERT 0
OFFSET 0.000000, 0.000000, 0.000000
BONES 1
BONE 0 1.000000

VERT 1
OFFSET 1.000000, 0.000000, 0.000000
BONES 2
BONE 0 0.500000
BONE 1 0.500000

VERT 2
OFFSET 0.000000, 1.000000, 0.000000
BONES 1
BONE 1 1.000000

NUMFACES 1
TRI 0 0 0 0
VERT 0
NORMAL 0.000000 0.000000 1.000000
COLOR 1.000000 1.000000 1.000000 1.000000
UV 1 0.000000 0.000000
VERT 1
NORMAL 0.000000 0.000000 1.000000
COLOR 1.000000 1.000000 1.000000 1.000000
UV 1 1.000000 0.000000
VERT 2
NORMAL 0.000000 0.000000 1.000000
COLOR 1.000000 1.000000 1.000000 1.000000
UV 1 0.000000 1.000000

NUMOBJECTS 1
OBJECT 0 "mesh"

NUMMATERIALS 1
MATERIAL 0 "mat_test" "Phong" "../images/test.dds"
COLOR 1.000000 1.000000 1.000000 1.000000
TRANSPARENCY 0.000000 0.000000 0.000000 0.000000
AMBIENTCOLOR 0.000000 0.000000 0.000000 1.000000
INCANDESCENCE 0.000000 0.000000 0.000000 1.000000
COEFFS 0.800000 0.200000
GLOW 0.000000 0
REFRACTIVE 0 1.000000
SPECULARCOLOR 1.000000 1.000000 1.000000 1.000000
REFLECTIVECOLOR 0.000000 0.000000 0.000000 1.000000
REFLECTIVE 0 0.000000
BLINN 0.000000 0.000000
PHONG 0.000000
'''


class XModelPipelineTests(unittest.TestCase):
    def test_parses_bones_weights_faces_and_materials(self):
        model = parse_xmodel_export(FIXTURE)
        self.assertEqual(len(model.bones), 2)
        self.assertEqual(model.bones[1].parent, 0)
        self.assertEqual(len(model.positions), 3)
        self.assertEqual(model.positions[1].weights, ((0, .5), (1, .5)))
        self.assertEqual(len(model.faces), 1)
        self.assertEqual(model.faces[0].material_index, 0)
        self.assertEqual(model.faces[0].vertices[1].uv, (1.0, 0.0))
        self.assertEqual(model.materials[0].name, 'mat_test')

    def test_exports_deterministic_native_payloads(self):
        with TemporaryDirectory() as td:
            out = Path(td)
            result = export_runtime_model(parse_xmodel_export(FIXTURE), out, model_id='test_model')
            self.assertEqual(set(result.payloads), {'model.json','positions.bin','skin.bin','vertices.bin','indices.bin'})
            meta = json.loads((out / 'model.json').read_text())
            self.assertEqual(meta['formatVersion'], 1)
            self.assertEqual(meta['indexType'], 'uint32')
            self.assertEqual(meta['vertexCount'], 3)
            self.assertEqual(meta['indexCount'], 3)
            self.assertEqual(meta['bones'][1]['parent'], 0)
            self.assertEqual(meta['materials'], ['materials:mat_test'])
            indices = struct.unpack('<3I', (out / 'indices.bin').read_bytes())
            self.assertEqual(indices, (0,1,2))
            self.assertIn('materials:mat_test', result.dependencies)

    def test_rejects_invalid_weight_sum_and_bad_indices(self):
        bad = FIXTURE.replace('BONE 0 0.500000\nBONE 1 0.500000', 'BONE 0 0.200000\nBONE 1 0.200000')
        with self.assertRaises(ValueError):
            parse_xmodel_export(bad)
        bad2 = FIXTURE.replace('VERT 2\nNORMAL', 'VERT 9\nNORMAL', 1)
        with self.assertRaises(ValueError):
            parse_xmodel_export(bad2)


if __name__ == '__main__':
    unittest.main()
