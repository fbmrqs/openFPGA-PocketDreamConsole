"""ROM-free regression checks for public packaging and local import."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_repository
import import_roms
import release


class PublicPackage(unittest.TestCase):
    def setUp(self):
        self.metadata = json.loads((ROOT / 'release/metadata.json').read_text())
        self.metadata['bitstream_sha256'] = hashlib.sha256(b'qualified-fpga').hexdigest()
        self.core = 'Cores/' + self.metadata['author'] + '.' + self.metadata['shortname'] + '/'

    def fixture(self, directory):
        package = Path(directory)
        old = package / 'Cores/Local.PocketDreamConsole'
        old.mkdir(parents=True)
        definitions = {
            'core': {'metadata': {}, 'cores': [{'filename': 'bitstream.rbf_r'}]},
            'video': {'display_modes': [{'id': hex(mode)} for mode in release.DISPLAY_MODES]},
            'input': {'controllers': [{'mappings': [{'name': 'A', 'key': 'pad_btn_b'},
                                                   {'name': 'B', 'key': 'pad_btn_a'}]}]},
            'interact': {'variables': [{'name': 'S', 'address': '0x20000000'}]}}
        for name in release.CORE_FILES:
            if name.endswith('.rbf_r'):
                data = b'qualified-fpga'
            else:
                data = release.encoded({name[:-5]: {'magic': 'APF_VER_1', **definitions.get(name[:-5], {})}})
            (old / name).write_bytes(data)
        (old / 'icon.bin').write_bytes(b'old-author-art')
        (package / 'Platforms').mkdir()
        (package / 'Platforms/pdc.json').write_bytes(release.encoded({'platform': {'name': 'Pocket Dream Console'}}))
        private = package / 'Assets/pdc/common/game.rom'
        private.parent.mkdir(parents=True)
        private.write_bytes(b'PRIVATE-GAME-MUST-NOT-SHIP')
        return old, package

    def test_real_packaging_excludes_roms_old_art_and_debug_menu(self):
        with tempfile.TemporaryDirectory() as directory:
            files = release.release_files(*self.fixture(directory), self.metadata)
            self.assertNotIn(b'PRIVATE-GAME-MUST-NOT-SHIP', files.values())
            self.assertFalse(any(name.endswith('icon.bin') for name in files))
            menu = json.loads(files[self.core + 'interact.json'])['interact']
            self.assertEqual(menu['variables'], [])
            archive = Path(directory) / 'release.zip'
            release.write_archive(archive, files)
            first = archive.read_bytes()
            release.write_archive(archive, files)
            self.assertEqual(first, archive.read_bytes())
            with zipfile.ZipFile(archive) as check:
                self.assertEqual({name.split('/')[0] for name in check.namelist()}, {'Cores', 'Assets', 'Platforms'})
                release.validate_release({name: check.read(name) for name in check.namelist()}, self.metadata)

    def test_rejects_unexpected_rom_debug_codes_changed_binary_and_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            files = release.release_files(*self.fixture(directory), self.metadata)
            bad_inputs = [
                {'Assets/pdc/common/game.rom': b'private'},
                {self.core + 'interact.json': release.encoded({'interact': {'magic': 'APF_VER_1', 'variables': [{'name': 'O'}], 'messages': []}})},
                {self.core + 'bitstream.rbf_r': b'unqualified'},
                {self.core + 'core.json': release.encoded({'core': {'metadata': {}}})},
                {self.core + 'updaters.json': release.encoded({'declare_ai': ['OpenAI Codex'], 'license': {'filename': 'LICENSE'}})},
                {self.core + 'updaters.json': release.encoded({'declare_ai': ['OpenAI Codex'], 'previous': []})}]
            for change in bad_inputs:
                with self.subTest(change=list(change)), self.assertRaises((ValueError, KeyError)):
                    release.validate_release({**files, **change}, self.metadata)

    def test_changed_or_failed_source_evidence_stops_release(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            path = workspace / 'dist/pocket-dc-native-library/native-manifest.json'
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({'experimental': False, 'excluded_roms': {}, 'rom_count': len(release.PROFILES)}))
            receipt = workspace / 'build/native-evidence/components.json'
            receipt.parent.mkdir(parents=True)
            for record in ({'passed': False, 'inputs': {}}, {'passed': True, 'inputs': {'stale': 'hash'}}):
                receipt.write_text(json.dumps(record))
                with patch.object(release, 'inputs', return_value={'current': 'hash'}), self.assertRaises(ValueError):
                    release.verify_workspace(workspace, self.metadata)


class LocalImport(unittest.TestCase):
    def test_hash_validation_padding_and_archive_paths(self):
        data = b'original-user-dump'
        rom = SimpleNamespace(key='demo', size=len(data), sha1=hashlib.sha1(data).hexdigest(), native_size=32)
        with patch.object(import_roms, 'ROMS', ()), patch.object(import_roms, 'NATIVE_ROMS', (rom,)):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / 'input.zip'
                with zipfile.ZipFile(archive, 'w') as out:
                    out.writestr('../../outside.bin', data)
                self.assertEqual(import_roms.import_file(archive, root / 'output'), ['demo'])
                self.assertEqual((root / 'output/demo.rom').read_bytes(), data + bytes(32-len(data)))
                self.assertFalse((root / 'outside.bin').exists())
                self.assertEqual(import_roms.import_file(archive, root / 'output'), ['demo'])
                (root / 'output/demo.rom').write_bytes(b'different-existing-file')
                with self.assertRaises(ValueError):
                    import_roms.import_file(archive, root / 'output')
            with self.assertRaises(ValueError):
                import_roms.identify(data[:-1] + b'!')

    def test_pdc100_upper_half_trimming(self):
        data = b'active-region-unused-region'
        with patch.object(import_roms, 'ROMS', [('input.bin', 'pdc100', 'PDC100', len(data), 13, hashlib.sha1(data).hexdigest())]):
            self.assertEqual(import_roms.identify(data), ('pdc100', data[:13]))

    def test_public_source_rejects_private_artifacts(self):
        for name in ('rom.bin', 'private.wav', 'build/status.json', '.env', 'dump.u2'):
            self.assertTrue(check_repository.private_path(name))
        self.assertFalse(check_repository.private_path('rtl/pdc_system.sv'))


if __name__ == '__main__':
    unittest.main()
