"""ROM-free regression checks for public packaging and local import."""
import hashlib
import json
from pathlib import Path
import sys
import subprocess
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
    def test_platform_background_matches_reference_decoder_polarity(self):
        data = (ROOT / 'release/pdc-platform.bin').read_bytes()
        # The upstream Library decoder uses 255 - stored brightness.
        # The supplied artwork has a white canvas, including all four corners.
        for x, y in ((0, 0), (520, 0), (0, 164), (520, 164)):
            index = ((520 - x) * 165 + y) * 2
            self.assertEqual(255 - data[index], 255)

    def setUp(self):
        self.metadata = json.loads((ROOT / 'release/metadata.json').read_text())
        self.metadata['bitstream_sha256'] = hashlib.sha256(b'qualified-fpga').hexdigest()
        self.core = 'Cores/' + self.metadata['author'] + '.' + self.metadata['shortname'] + '/'

    def fixture(self, directory):
        package = Path(directory)
        old = package / 'Cores/Local.PocketDreamConsole'
        old.mkdir(parents=True)
        definitions = {
            'core': {'metadata': {}, 'cores': [{'filename': 'bitstream.rbf_r'}],
                     'framework': {'sleep_supported': False, 'dock': {'supported': False, 'analog_output': False}}},
            'data': {'data_slots': [{'id': 1, 'size_maximum': '0x4000000'}]},
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
            self.assertEqual(json.loads(files[self.core + 'updaters.json']), {
                'plugins': ['https://github.com/fbmrqs/openFPGA-PocketDreamConsole-plugin']})
            self.assertNotIn(b'PRIVATE-GAME-MUST-NOT-SHIP', files.values())
            # Only the piano author icon ships, never an older runtime icon.
            self.assertEqual([name for name in files if name.endswith('icon.bin')], [self.core + 'icon.bin'])
            self.assertEqual(files[self.core + 'icon.bin'], (release.ROOT / 'release/author-icon.bin').read_bytes())
            self.assertTrue(json.loads(files[self.core + 'core.json'])['core']['framework']['dock']['supported'])
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
                {'Platforms/_images/pdc.bin': b'unexpected-game-data'},
                {self.core + 'core.json': release.encoded({'core': {'metadata': {}}})},
                {self.core + 'updaters.json': release.encoded({'license': {'filename': 'LICENSE'}})},
                {self.core + 'updaters.json': release.encoded({'previous': []})}]
            bad_inputs += [
                {self.core + 'data.json': release.encoded({'data': {'magic': 'APF_VER_1', 'data_slots': [{'id': 1, 'size_maximum': '0x8000000'}]}})},
                {self.core + 'updaters.json': release.encoded({'plugins': []})},
                {self.core + 'updaters.json': release.encoded({'plugins': ['https://example.invalid/plugin']})},
                {self.core + 'updaters.json': release.encoded({'plugins': ['https://github.com/fbmrqs/openFPGA-PocketDreamConsole-plugin'], 'previous': []})}]
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

    def test_metadata_patch_preserves_the_published_hardware_and_rejects_unbound_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            (source / 'README.md').write_text('original')
            subprocess.run(['git', '-C', str(source), 'add', 'README.md'], check=True)
            subprocess.run(['git', '-C', str(source), '-c', 'user.name=Test',
                            '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'baseline'], check=True)
            revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
            previous = {**self.metadata, 'version': '1.0.0', 'date_release': '2026-10-29'}
            files = release.release_files(*self.fixture(root / 'package'), previous)
            del files[self.core + 'updaters.json']
            baseline = root / 'baseline'
            baseline.mkdir()
            archive = baseline / 'baseline.zip'
            release.write_archive(archive, files)
            info = {**previous, 'packaging_commit': revision, 'roms_included': False,
                    'diagnostic_menu': False, 'qualified_profiles': list(release.PROFILES),
                    'validation_receipt_sha256': {'components': '0' * 64},
                    'files': {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}}
            info_path = baseline / 'build-info.json'
            info_path.write_bytes(release.encoded(info))
            metadata = {**self.metadata, 'version': '1.0.1', 'date_release': '2026-10-30',
                        'metadata_baseline': {'archive': archive.name,
                            'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                            'build_info_sha256': hashlib.sha256(info_path.read_bytes()).hexdigest()}}
            (source / 'README.md').write_text('new instructions')
            patched, original_info = release.metadata_patch(baseline, metadata, source)
            self.assertEqual(original_info['packaging_commit'], revision)
            self.assertEqual({name for name in set(files) | set(patched) if files.get(name) != patched.get(name)},
                             {self.core + 'README.md', self.core + 'core.json', self.core + 'updaters.json'})
            self.assertEqual(patched[self.core + 'bitstream.rbf_r'], b'qualified-fpga')
            with self.assertRaises(ValueError):
                release.metadata_patch(baseline, {**metadata, 'bitstream_sha256': 'f' * 64}, source)
            archive.write_bytes(archive.read_bytes() + b'tampered')
            with self.assertRaises(ValueError):
                release.metadata_patch(baseline, metadata, source)
            release.write_archive(archive, files)
            (source / 'README.md').rename(source / 'hardware.sv')
            subprocess.run(['git', '-C', str(source), 'add', '.'], check=True)
            with self.assertRaises(ValueError):
                release.metadata_patch(baseline, metadata, source)


class LocalImport(unittest.TestCase):
    def test_plugin_has_no_network_capability(self):
        manifest = json.loads((ROOT / 'tools/pocket-plugin/plugin.json').read_text())
        self.assertEqual(manifest['allowed_hosts'], [])
        self.assertLessEqual(len(manifest['name']), 200)
        self.assertLessEqual(len(manifest['description']), 8000)

    def test_plugin_profiles_match_the_existing_supported_revisions(self):
        profiles = json.loads((ROOT / 'tools/pocket-plugin/profiles.json').read_text())
        expected = {stem: (size, sha1, used) for _, stem, _, size, used, sha1 in import_roms.ROMS}
        expected.update({r.key: (r.size, r.sha1, r.native_size) for r in import_roms.NATIVE_ROMS})
        self.assertEqual({p['key']: (p['source_size'], p['source_sha1'], p['output_size']) for p in profiles}, expected)
        self.assertEqual(len(profiles), 10)
        for profile in profiles:
            self.assertRegex(profile['output_sha256'], r'^[0-9a-f]{64}$')

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
        self.assertFalse(check_repository.private_path('release/pdc-platform.bin'))
        self.assertTrue(check_repository.private_path('release/other.bin'))


if __name__ == '__main__':
    unittest.main()
