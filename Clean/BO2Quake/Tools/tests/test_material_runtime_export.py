import json
import unittest

from Clean.BO2Quake.Converter.bo2convert.material_export import (
    MaterialTextureBinding,
    build_material_payloads,
)


class MaterialRuntimeExportTests(unittest.TestCase):
    def test_exports_texture_bindings_and_render_state(self):
        result = build_material_payloads(
            material_name='mp_deck',
            technique_set='mc_lit_sm_r0c0n0s0',
            render_class='opaque',
            textures=[
                MaterialTextureBinding('colorMap', 'texture:deck_d', 0x11111111, 0),
                MaterialTextureBinding('normalMap', 'texture:deck_n', 0x22222222, 1),
            ],
            state_bits={'depthWrite': True, 'depthTest': True, 'cull': 'back'},
        )
        self.assertEqual(result.dependencies, ('texture:deck_d', 'texture:deck_n'))
        payload = json.loads(result.payloads['material.json'])
        self.assertEqual(payload['name'], 'mp_deck')
        self.assertEqual(payload['renderClass'], 'opaque')
        self.assertEqual(payload['techniqueSet'], 'mc_lit_sm_r0c0n0s0')
        self.assertEqual(payload['textures'][0]['semantic'], 'colorMap')
        self.assertTrue(payload['stateBits']['depthWrite'])

    def test_rejects_unknown_render_class_instead_of_fallback(self):
        with self.assertRaisesRegex(ValueError, 'unsupported material render class'):
            build_material_payloads(
                material_name='bad', technique_set='x', render_class='mystery',
                textures=[], state_bits={}
            )

    def test_rejects_duplicate_texture_semantics(self):
        with self.assertRaisesRegex(ValueError, 'duplicate texture semantic'):
            build_material_payloads(
                material_name='bad', technique_set='x', render_class='opaque',
                textures=[
                    MaterialTextureBinding('colorMap', 'texture:a', 1, 0),
                    MaterialTextureBinding('colorMap', 'texture:b', 2, 0),
                ], state_bits={}
            )


if __name__ == '__main__':
    unittest.main()
