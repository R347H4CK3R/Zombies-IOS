from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeWorldRuntimeContractTests(unittest.TestCase):
    def test_runtime_loads_world_gamedata_and_draws_with_metal(self):
        world = (ROOT / 'Sources' / 'Runtime' / 'WorldRuntimeAsset.swift').read_text()
        renderer = (ROOT / 'Sources' / 'Runtime' / 'MetalWorldView.swift').read_text()
        root = (ROOT / 'Sources' / 'App' / 'RootView.swift').read_text()
        combined = world + renderer + root
        self.assertIn('MTKView', renderer)
        self.assertIn('MTKViewDelegate', renderer)
        self.assertIn('UInt32', world)
        self.assertIn('vertices.bin', world)
        self.assertIn('indices.bin', world)
        self.assertIn('surfaces.json', world)
        self.assertIn('GameDataLoader', root)
        self.assertIn('MetalWorldView', root)
        self.assertNotIn('SceneKit', combined)


if __name__ == '__main__':
    unittest.main()
