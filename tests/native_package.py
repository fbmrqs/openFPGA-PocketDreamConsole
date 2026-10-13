"""Check the generated native package's Pocket setup files."""
import json
from pathlib import Path
import sys
import unittest

PACKAGE = Path(sys.argv.pop(1))
MANIFEST = json.loads(next(PACKAGE.glob('native*-manifest.json')).read_text())


class NativeSetup(unittest.TestCase):
    def test_diagnostic_menu(self):
        for core in (PACKAGE / 'Cores').iterdir():
            menu = json.loads((core / 'interact.json').read_text())['interact']['variables']
            self.assertEqual([v['name'] for v in menu], list('SFOMRLWAB'))
            self.assertEqual(len({v['address'] for v in menu}), 9)
            self.assertTrue(all(v['type'] == 'number_u32' and not v['enabled'] for v in menu))

    def test_core_definition_files(self):
        cores = list((PACKAGE / 'Cores').iterdir())
        self.assertEqual(len(cores), 2)
        modes = set()
        bitstreams = []
        for core in cores:
            for name in ('core', 'audio', 'video', 'data', 'input', 'interact', 'variants'):
                with self.subTest(core=core.name, definition=name):
                    definition = json.loads((core / f'{name}.json').read_text())
                    self.assertEqual(definition[name]['magic'], 'APF_VER_1')
            video = json.loads((core / 'video.json').read_text())['video']
            ids = [int(mode['id'], 16) for mode in video['display_modes']]
            self.assertLessEqual(len(ids), 16)
            self.assertEqual(len(ids), len(set(ids)))
            modes.update(ids)
            self.assertEqual(video['scaler_modes'][0]['width'], 320)
            self.assertEqual(video['scaler_modes'][0]['height'], 240)
            definition = json.loads((core / 'core.json').read_text())
            for variant in definition['core']['cores']:
                bitstream = (core / variant['filename']).read_bytes()
                self.assertGreater(len(bitstream), 0)
                bitstreams.append(bitstream)
            instances = PACKAGE / 'Assets/pdc' / core.name
            self.assertEqual(len(list(instances.glob('*.json'))), MANIFEST.get('rom_count', 2))
            for instance in instances.glob('*.json'):
                slots = json.loads(instance.read_text())['instance']['data_slots']
                self.assertTrue(all((PACKAGE / 'Assets/pdc/common' / slot['filename']).is_file() for slot in slots))
                self.assertTrue(all(Path(slot['filename']).stem not in MANIFEST.get('excluded_roms', {}) for slot in slots))
        self.assertTrue(all(bitstream == bitstreams[0] for bitstream in bitstreams))
        self.assertEqual(modes, {0x10, 0x20, 0x21, 0x22, 0x23, 0x30, 0x31, 0x32,
            0x40, 0x41, 0x42, 0x51, 0x52, 0x61, 0x62, 0x63, 0x71, 0x72, 0x81,
            0x82, 0xE0, 0xE1})


if __name__ == '__main__':
    unittest.main()
