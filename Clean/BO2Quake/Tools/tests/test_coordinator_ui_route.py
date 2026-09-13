from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CoordinatorUIRouteTests(unittest.TestCase):
    def test_root_builds_game_from_real_world_and_weapon_assets(self):
        root = (ROOT / 'Sources' / 'App' / 'RootView.swift').read_text()
        self.assertIn('RuntimeAssetLoader', root)
        self.assertIn('firstWeapon()', root)
        self.assertIn('BO2GameCoordinator', root)
        self.assertIn('BO2GameplayView', root)

    def test_touch_gameplay_routes_fire_reload_and_hud_through_coordinator(self):
        view = (ROOT / 'Sources' / 'Runtime' / 'BO2GameplayView.swift').read_text()
        self.assertIn('coordinator.fire', view)
        self.assertIn('coordinator.beginReload', view)
        self.assertIn('coordinator.weapon.magazine', view)
        self.assertIn('coordinator.step', view)
        self.assertIn('MetalWorldView', view)


if __name__ == '__main__':
    unittest.main()
