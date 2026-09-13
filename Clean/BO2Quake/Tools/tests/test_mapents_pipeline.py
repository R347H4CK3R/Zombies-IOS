from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.mapents import parse_mapents, export_mapents

FIXTURE = '''
{
"classname" "worldspawn"
"skyboxmodel" "skybox_test"
}
{
"classname" "mp_dm_spawn"
"origin" "100 200 32"
"angles" "0 90 0"
}
{
"classname" "script_model"
"model" "prop_chair"
"origin" "25 50 10"
"modelscale" "1.5"
}
{
"classname" "trigger_multiple"
"targetname" "door_trigger"
"model" "*4"
"script_noteworthy" "open_door"
}
{
"classname" "ctf_flag_allies"
"origin" "0 0 64"
}
'''

class MapEntsPipelineTests(unittest.TestCase):
    def test_parse_preserves_all_key_values_and_classifies_entities(self):
        entities = parse_mapents(FIXTURE)
        self.assertEqual(len(entities), 5)
        self.assertEqual(entities[0]['classname'], 'worldspawn')
        self.assertEqual(entities[1]['origin'], [100.0, 32.0, -200.0])
        self.assertEqual(entities[2]['model'], 'prop_chair')

    def test_export_builds_spawn_trigger_objective_and_model_indexes(self):
        with TemporaryDirectory() as td:
            result = export_mapents(FIXTURE, Path(td), map_id='mp_test')
            data = json.loads((Path(td)/'entities.json').read_text())
            self.assertEqual(len(data['spawns']), 1)
            self.assertEqual(len(data['scriptModels']), 1)
            self.assertEqual(len(data['triggers']), 1)
            self.assertEqual(len(data['objectives']), 1)
            self.assertIn('models:prop_chair', result.dependencies)
            self.assertIn('models:skybox_test', result.dependencies)

    def test_malformed_entity_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_mapents('{\n"classname" "broken"\n')

if __name__ == '__main__':
    unittest.main()
