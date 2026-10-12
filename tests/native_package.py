"""Check the generated native package's Pocket setup files."""
import json
from pathlib import Path
import sys
import unittest

PACKAGE = Path(sys.argv.pop(1))


class NativeSetup(unittest.TestCase):
    def test_diagnostic_menu(self):
        core = next((PACKAGE / 'Cores').iterdir())
        menu = json.loads((core / 'interact.json').read_text())['interact']['variables']
        self.assertEqual([v['name'] for v in menu], list('SFOMRLWAB'))
        self.assertEqual(len({v['address'] for v in menu}), 9)
        self.assertTrue(all(v['type'] == 'number_u32' and not v['enabled'] for v in menu))

    def test_core_definition_files(self):
        cores = list((PACKAGE / 'Cores').iterdir())
        self.assertEqual(len(cores), 1)
        for name in ('core', 'audio', 'video', 'data', 'input', 'interact', 'variants'):
            with self.subTest(definition=name):
                definition = json.loads((cores[0] / f'{name}.json').read_text())
                self.assertEqual(definition[name]['magic'], 'APF_VER_1')
        definition = json.loads((cores[0] / 'core.json').read_text())
        for variant in definition['core']['cores']:
            self.assertGreater((cores[0] / variant['filename']).stat().st_size, 0)


if __name__ == '__main__':
    unittest.main()
