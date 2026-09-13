from pathlib import Path
from tempfile import TemporaryDirectory
import csv
import json
import wave
import unittest

from Clean.BO2Quake.Converter.bo2convert.t6.audio import convert_sound_alias_csv


class AudioPipelineTests(unittest.TestCase):
    def _wav(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), 'wb') as f:
            f.setnchannels(1); f.setsampwidth(2); f.setframerate(8000)
            f.writeframes(b'\x00\x00' * 80)

    def test_converts_alias_csv_and_audio_dependencies(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            self._wav(root / 'snd' / 'gun.wav')
            csv_path = root / 'aliases.csv'
            headers = ['Name','FileSource','Secondary','Bus','VolMin','VolMax','DistMin','DistMaxDry','PitchMin','PitchMax','PanType','Looping','Probability','StartDelay','IsMusic','FadeIn','FadeOut','Pauseable']
            with csv_path.open('w', newline='') as f:
                w = csv.DictWriter(f, fieldnames=headers); w.writeheader()
                w.writerow({'Name':'rifle_fire','FileSource':'snd/gun.wav','Secondary':'','Bus':'sfx','VolMin':'80','VolMax':'100','DistMin':'32','DistMaxDry':'2048','PitchMin':'-50','PitchMax':'50','PanType':'3d','Looping':'nonlooping','Probability':'1','StartDelay':'0','IsMusic':'no','FadeIn':'0','FadeOut':'0','Pauseable':'yes'})
            out = root / 'out'
            result = convert_sound_alias_csv(csv_path, root, out, bank_id='testbank')
            self.assertEqual(result.alias_count, 1)
            meta = json.loads((out / 'aliases.json').read_text())
            alias = meta['aliases'][0]
            self.assertEqual(alias['name'], 'rifle_fire')
            self.assertEqual(alias['file'], 'files/snd/gun.wav')
            self.assertEqual(alias['spatial'], True)
            self.assertEqual(alias['looping'], False)
            self.assertTrue((out / 'files' / 'snd' / 'gun.wav').is_file())

    def test_missing_audio_file_is_explicit_failure(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            csv_path = root / 'aliases.csv'
            csv_path.write_text('Name,FileSource\nmissing,nope.wav\n')
            with self.assertRaises(ValueError):
                convert_sound_alias_csv(csv_path, root, root / 'out', bank_id='bad')

    def test_path_escape_is_rejected(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            csv_path = root / 'aliases.csv'
            csv_path.write_text('Name,FileSource\nevil,../outside.wav\n')
            with self.assertRaises(ValueError):
                convert_sound_alias_csv(csv_path, root, root / 'out', bank_id='bad')


if __name__ == '__main__':
    unittest.main()
