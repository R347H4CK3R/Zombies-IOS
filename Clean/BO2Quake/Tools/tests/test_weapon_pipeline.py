from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.weapons import parse_info_string, export_weapon


class WeaponPipelineTests(unittest.TestCase):
    def test_parses_oat_info_string_and_core_combat_fields(self):
        text = 'WEAPONFILE\\displayName\\AN-94\\gunModel\\viewmodel_an94\\fireAnim\\an94_fire\\reloadAnim\\an94_reload\\fireSound\\wpn_an94_fire\\ammoName\\ar_ammo\\clipName\\an94_clip\\iClipSize\\30\\iMaxAmmo\\240\\iFireTime\\100\\iReloadTime\\2100\\damage\\40\\minDamage\\24\\maxDamageRange\\1200\\minDamageRange\\2400'
        prefix, values = parse_info_string(text)
        self.assertEqual(prefix, 'WEAPONFILE')
        self.assertEqual(values['iClipSize'], '30')
        with TemporaryDirectory() as td:
            result = export_weapon(text, Path(td), weapon_id='an94')
            data = json.loads((Path(td)/'weapon.json').read_text())
            self.assertEqual(data['clipSize'], 30)
            self.assertEqual(data['maxAmmo'], 240)
            self.assertEqual(data['fireIntervalMs'], 100)
            self.assertEqual(data['reloadTimeMs'], 2100)
            self.assertEqual(data['damage'], 40)
            self.assertEqual(data['maxDamageRange'], 1200.0)
            self.assertEqual(data['minDamageRange'], 2400.0)
            self.assertIn('models:viewmodel_an94', result.dependencies)
            self.assertIn('animations:an94_fire', result.dependencies)
            self.assertIn('audio:wpn_an94_fire', result.dependencies)
            self.assertEqual(data['raw']['minDamage'], '24')

    def test_rejects_malformed_odd_info_string(self):
        with self.assertRaises(ValueError):
            parse_info_string('WEAPONFILE\\key')

    def test_requires_core_ammo_timing_and_range_values(self):
        with TemporaryDirectory() as td:
            with self.assertRaises(ValueError):
                export_weapon('WEAPONFILE\\displayName\\bad', Path(td), weapon_id='bad')


if __name__ == '__main__':
    unittest.main()
