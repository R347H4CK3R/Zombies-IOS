from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.weapons import export_weapon


class WeaponFidelityTests(unittest.TestCase):
    def test_preserves_damage_ranges_fire_mode_and_ads_timing(self):
        text = (
            'WEAPONFILE\\displayName\\AN-94\\iClipSize\\30\\iMaxAmmo\\240'
            '\\iFireTime\\100\\iReloadTime\\2100\\damage\\40\\minDamage\\24'
            '\\maxDamageRange\\1200.5\\minDamageRange\\2400.25'
            '\\fireType\\Full Auto\\adsTransInTime\\250\\adsTransOutTime\\180'
            '\\adsZoomFov1\\55.0'
        )
        with TemporaryDirectory() as td:
            export_weapon(text, Path(td), weapon_id='an94')
            data = json.loads((Path(td) / 'weapon.json').read_text())
            self.assertEqual(data['maxDamageRange'], 1200.5)
            self.assertEqual(data['minDamageRange'], 2400.25)
            self.assertEqual(data['fireType'], 'Full Auto')
            self.assertEqual(data['adsTransInMs'], 250)
            self.assertEqual(data['adsTransOutMs'], 180)
            self.assertEqual(data['adsZoomFov'], 55.0)

    def test_missing_damage_ranges_is_completion_blocker(self):
        text = 'WEAPONFILE\\iClipSize\\30\\iMaxAmmo\\240\\iFireTime\\100\\iReloadTime\\2100\\damage\\40\\minDamage\\24'
        with TemporaryDirectory() as td:
            with self.assertRaisesRegex(ValueError, 'damage range'):
                export_weapon(text, Path(td), weapon_id='bad')


if __name__ == '__main__':
    unittest.main()
