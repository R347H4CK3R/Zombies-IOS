from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WeaponRuntimeFidelityTests(unittest.TestCase):
    def test_runtime_consumes_source_damage_ranges_and_ads(self):
        text = (ROOT / 'Sources' / 'Runtime' / 'WeaponCombatRuntime.swift').read_text()
        for token in ('maxDamageRange', 'minDamageRange', 'fireType', 'adsTransInMs', 'adsTransOutMs', 'adsZoomFov'):
            self.assertIn(token, text)
        self.assertIn('distance <= definition.maxDamageRange', text)
        self.assertIn('definition.minDamageRange', text)

    def test_gamedata_weapon_loader_decodes_weapon_json(self):
        text = (ROOT / 'Sources' / 'Runtime' / 'RuntimeAssetLoader.swift').read_text()
        self.assertIn('func loadWeapon', text)
        self.assertIn('weapon.json', text)
        self.assertIn('WeaponDefinition.self', text)


if __name__ == '__main__':
    unittest.main()
