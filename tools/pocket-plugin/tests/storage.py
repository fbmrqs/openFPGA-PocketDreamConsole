"""WASM write-failure and interruption checks on disposable folders/images only."""
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

import wasm


@contextmanager
def target(root, exfat):
    mount = root / 'card'
    mount.mkdir()
    if not exfat:
        yield mount
        return
    image = root / 'test.dmg'
    modern = subprocess.run(['diskutil', 'image', 'create', 'blank', '-help'], capture_output=True)
    if modern.returncode == 0 and b'--fs' in modern.stdout:
        create = ['diskutil', 'image', 'create', 'blank', '--size', '268435456', '--fs', 'ExFAT', '--volumeName', 'PDCPluginTest', str(image)]
    else:
        create = ['hdiutil', 'create', '-size', '256m', '-fs', 'ExFAT', '-volname', 'PDCPluginTest', str(image)]
    result = subprocess.run(create, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Disposable image creation failed: ' + result.stderr.strip())
    subprocess.run(['hdiutil', 'attach', '-nobrowse', '-mountpoint', str(mount), str(image)], check=True, capture_output=True)
    try:
        info = plistlib.loads(subprocess.check_output(['diskutil', 'info', '-plist', str(mount)]))
        assert info['VolumeName'] == 'PDCPluginTest' and info['FilesystemType'] == 'exfat'
        assert Path(info['MountPoint']).resolve() == mount.resolve()
        yield mount
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', required=True, type=Path)
    parser.add_argument('--wasm', type=Path, default=wasm.CRATE / 'target/release-assets/plugin.wasm')
    parser.add_argument('--exfat', action='store_true', help='macOS only: create a fresh disposable 256 MiB disk image')
    parser.add_argument('--scratch-root', type=Path, help='parent for an automatically removed test folder; existing files are not modified')
    args = parser.parse_args()
    if sys.platform == 'win32' or (args.exfat and sys.platform != 'darwin'):
        raise SystemExit('Default failure injection needs POSIX resource limits; --exfat needs macOS disk-image permission.')
    wasm.WASM = args.wasm.resolve()
    original = args.private_root.resolve() / 'pdc100.bin'
    profile = next(p for p in wasm.PROFILES if p['key'] == 'pdc100')
    assert original.stat().st_size == profile['source_size']
    assert wasm.digest(original, 'sha1') == profile['source_sha1']
    with tempfile.TemporaryDirectory(prefix='pdc-plugin-storage-', dir=args.scratch_root) as tmp, target(Path(tmp), args.exfat) as card:
        wasm.core(card)
        intake = card / 'Assets/pdc/import'
        intake.mkdir(parents=True)
        source = intake / 'pdc100.bin'
        shutil.copyfile(original, source)
        output = card / 'Assets/pdc/common/pdc100.rom'
        code = '''import sys, signal
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import wasm
if sys.argv[4] == 'limit':
    import resource
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (64*1024*1024, 64*1024*1024))
wasm.WASM = Path(sys.argv[2])
with wasm.Host(Path(sys.argv[3]), echo=True) as host:
    host.call('start')
'''
        argv = [sys.executable, '-u', '-c', code, str(Path(__file__).parent), str(wasm.WASM), str(card)]
        if args.exfat:
            filler = card / 'test-filler'
            with filler.open('wb') as out:
                while shutil.disk_usage(card).free > 70 * 1024 * 1024:
                    out.write(bytes(1024 * 1024))
            mode = 'normal'
        else:
            mode = 'limit'
        failed = subprocess.run(argv + [mode], capture_output=True, text=True, timeout=300)
        assert failed.returncode == 0 and '1 failed' in failed.stdout, failed.stdout + failed.stderr
        assert not output.exists()
        assert wasm.digest(source, 'sha1') == profile['source_sha1']
        if args.exfat:
            filler.unlink()
        child = subprocess.Popen(argv + ['normal'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        reached_write = False
        try:
            for line in child.stdout:
                if line.startswith('Preparing PDC100:'):
                    reached_write = True
                    child.kill()
                    break
            child.wait(timeout=30)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
        assert reached_write and child.returncode == -9
        assert not output.exists()
        assert (output.parent / '.pdc-import-pdc100.part').is_file()
        assert wasm.digest(source, 'sha1') == profile['source_sha1']
        with wasm.Host(card) as host:
            menu = host.call('start')['Choice']
            assert menu['name'] == 'action' and menu['choices'] == ['Remove unfinished imports', 'Exit']
            assert (output.parent / '.pdc-import-pdc100.part').is_file()
            assert host.action('Remove unfinished imports')['Choice']['name'] == 'cleanup'
            assert host.action('Remove unfinished imports', 'cleanup') == 'Exit'
            assert '1 prepared' in host.text, host.text
        assert output.stat().st_size == profile['output_size']
        assert wasm.digest(output) == profile['output_sha256']
        assert wasm.digest(source, 'sha1') == profile['source_sha1']
        print(json.dumps({'filesystem': 'disposable exFAT image' if args.exfat else 'temporary host folder',
                          'failure_test': 'full volume' if args.exfat else 'file growth denied by resource limit',
                          'write_failure_rejected': True, 'forced_write_interruption_returncode': child.returncode,
                          'cleanup_and_retry_passed': True, 'original_preserved': True,
                          'prepared_bytes': output.stat().st_size}, indent=2))


if __name__ == '__main__':
    main()
