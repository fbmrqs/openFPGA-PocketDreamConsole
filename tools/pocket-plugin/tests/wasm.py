"""Exercise the actual release-built WASM on temporary card folders.

Private parity: add --private-root /path/to/pocket-dc with its ignored original dumps.
Optional --scratch-root puts disposable fixtures on a chosen filesystem. Existing
card files are never used as writable fixtures. Requires host-requirements.txt.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile

import extism

CRATE = Path(__file__).resolve().parents[1]
PROFILES = json.loads((CRATE / 'profiles.json').read_text())
WASM = CRATE / 'target/wasm32-wasip1/release/plugin.wasm'
PRIVATE = None
SCRATCH_ROOT = None


def digest(path, algorithm='sha256'):
    with path.open('rb') as source:
        return hashlib.file_digest(source, algorithm).hexdigest()


def core(card):
    target = card / 'Cores/fbmrqs.PocketDreamConsole/core.json'
    target.parent.mkdir(parents=True)
    target.write_text(json.dumps({'core': {'metadata': {'author': 'fbmrqs', 'shortname': 'PocketDreamConsole'}}}))


class Host:
    def __init__(self, card, echo=False):
        self.log = []

        @extism.host_fn(name='print_msg', signature=([extism.ValType.I64], [extism.ValType.I64]))
        def capture(plugin, inputs, outputs):
            text = plugin.input_string(inputs[0])
            self.log.append(text)
            if echo:
                print(text, end='', flush=True)

        self.capture = capture
        self.plugin = extism.Plugin({'wasm': [{'path': str(WASM.resolve())}],
            'allowed_paths': {str(card.resolve()): 'pocket'}, 'allowed_hosts': [],
            'memory': {'max_pages': 16384}, 'timeout_ms': 300000}, wasi=True, functions=[capture])

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.plugin.__exit__(*args)

    def call(self, name, value=None):
        return json.loads(self.plugin.call(name, b'' if value is None else json.dumps(value).encode()))

    def action(self, value, name='action'):
        return self.call('handle_response', {'Answer': {'name': name, 'value': value}})

    @property
    def text(self):
        return ''.join(self.log)


@contextmanager
def temporary_host():
    with tempfile.TemporaryDirectory(prefix='pdc-plugin-test-', dir=SCRATCH_ROOT) as tmp:
        card = Path(tmp)
        with Host(card) as host:
            yield card, host


class Protocol(unittest.TestCase):
    def test_normal_run_prepares_the_intake_folder_and_checks_installed_roms_without_a_prompt(self):
        with temporary_host() as (card, host):
            core(card)
            self.assertEqual(host.call('start'), 'Exit')
            self.assertTrue((card / 'Assets/pdc/import').is_dir())
            self.assertIn('10 not installed', host.text)
            self.assertIn('0 failed', host.text)

    def test_kill_exits_without_creating_card_files(self):
        with temporary_host() as (card, host):
            self.assertEqual(host.call('handle_response', 'Kill'), 'Exit')
            self.assertEqual(list(card.iterdir()), [])

    def test_missing_core_stops_without_writes(self):
        with temporary_host() as (card, host):
            self.assertEqual(host.action('Prepare local ROMs'), 'Exit')
            self.assertIn('Install fbmrqs.PocketDreamConsole', host.text)
            self.assertEqual(list(card.iterdir()), [])

    def test_empty_check_and_unsupported_input_report_their_actual_results(self):
        with temporary_host() as (card, host):
            core(card)
            self.assertEqual(host.action('Check installed ROMs'), 'Exit')
            self.assertIn('10 not installed', host.text)
            source = card / 'Assets/pdc/import/not-a-rom.bin'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'not-a-ROM')
            self.assertEqual(host.action('Prepare local ROMs'), 'Exit')
            self.assertIn('1 rejected', host.text)
            self.assertEqual(source.read_bytes(), b'not-a-ROM')
            self.assertEqual(list((card / 'Assets/pdc/common').iterdir()), [])

    def test_cleanup_requires_confirmation_and_keeps_unrelated_files(self):
        with temporary_host() as (card, host):
            core(card)
            output = card / 'Assets/pdc/common'
            output.mkdir(parents=True)
            part = output / '.pdc-import-pdc100.part'
            part.write_bytes(b'interrupted')
            other = output / 'other.part'
            other.write_bytes(b'keep')
            self.assertEqual(host.action('Remove unfinished imports')['Choice']['name'], 'cleanup')
            self.assertTrue(part.exists())
            self.assertEqual(host.action('Cancel', 'cleanup'), 'Exit')
            self.assertTrue(part.exists())
            self.assertEqual(host.action('Remove unfinished imports', 'cleanup'), 'Exit')
            self.assertFalse(part.exists())
            self.assertEqual(other.read_bytes(), b'keep')

    def test_malformed_response_exits_without_changes(self):
        with temporary_host() as (card, host):
            self.assertEqual(host.call('handle_response', {'not': 'an answer'}), 'Exit')
            self.assertIn('Invalid response', host.text)
            self.assertEqual(list(card.iterdir()), [])


class PrivateParity(unittest.TestCase):
    def test_all_ten_raw_dumps_and_zip_members_match_the_python_importer(self):
        if PRIVATE is None:
            self.skipTest('requires --private-root with ignored local ROMs')
        sys.path.insert(0, str(PRIVATE / 'tools'))
        import import_roms
        import package
        import rom_library
        originals = {stem: PRIVATE / name for name, stem, *_ in package.ROMS}
        originals.update({r.key: PRIVATE / 'build/rom-library/dumps' / r.key / r.member for r in rom_library.NATIVE_ROMS})
        self.assertEqual(set(originals), {p['key'] for p in PROFILES})
        with tempfile.TemporaryDirectory(prefix='pdc-plugin-parity-', dir=SCRATCH_ROOT) as tmp:
            root = Path(tmp)
            reference = root / 'reference'
            for path in originals.values():
                import_roms.import_file(path, reference)
            for zipped in (False, True):
                card = root / ('zip-card' if zipped else 'raw-card')
                core(card)
                intake = card / 'Assets/pdc/import'
                intake.mkdir(parents=True)
                if zipped:
                    archive = intake / 'originals.zip'
                    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as out:
                        for key, path in originals.items():
                            out.write(path, '../../' + key + '.bin')
                else:
                    for key, path in originals.items():
                        shutil.copyfile(path, intake / (key + '.original'))
                before = {p.name: digest(p) for p in intake.iterdir()}
                with Host(card) as host:
                    self.assertEqual(host.call('start'), 'Exit')
                    self.assertIn('10 prepared', host.text, host.text)
                    for profile in PROFILES:
                        actual = card / 'Assets/pdc/common' / (profile['key'] + '.rom')
                        expected = reference / actual.name
                        self.assertEqual(actual.stat().st_size, profile['output_size'])
                        self.assertEqual(digest(actual), profile['output_sha256'])
                        with actual.open('rb') as a, expected.open('rb') as b:
                            while chunk := a.read(1024 * 1024):
                                self.assertEqual(chunk, b.read(len(chunk)))
                            self.assertEqual(b.read(1), b'')
                    self.assertEqual(host.action('Check installed ROMs'), 'Exit')
                    self.assertIn('10 already correct', host.text)
                    self.assertEqual(host.call('start'), 'Exit')
                    self.assertIn('0 prepared, 10 already correct', host.text)
                    self.assertEqual(before, {p.name: digest(p) for p in intake.iterdir()})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--wasm', type=Path, default=WASM)
    parser.add_argument('--private-root', type=Path)
    parser.add_argument('--scratch-root', type=Path, help='parent for automatically removed test folders; existing files are not modified')
    args = parser.parse_args()
    WASM = args.wasm
    PRIVATE = args.private_root.resolve() if args.private_root else None
    SCRATCH_ROOT = args.scratch_root.resolve() if args.scratch_root else None
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Protocol)
    if PRIVATE:
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(PrivateParity))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
