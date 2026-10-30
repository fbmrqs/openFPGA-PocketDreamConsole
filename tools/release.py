#!/usr/bin/env python3
"""Create a ROM-free release from a qualified, unchanged FPGA workspace."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

from fpga.evidence import inputs
from package import digest
from package_native import DISPLAY_MODES
from rom_library import NATIVE_ROMS

ROOT = Path(__file__).resolve().parents[1]
CORE_FILES = ('core.json', 'audio.json', 'video.json', 'data.json', 'input.json',
              'interact.json', 'variants.json', 'bitstream.rbf_r')
PROFILES = {'pdc30': 'PDC30 Pink', 'pdc100': 'PDC100',
            **{rom.key: rom.label for rom in NATIVE_ROMS}}
SCENES = ('hair-salon', 'bunny-pinky', 'beeline-2', 'fun-match-2')


def validate_platform_image(data):
    pixels = bytes(255 - value for value in data[::2])
    if len(data) != 521 * 165 * 2 or any(data[1::2]) or not set(pixels) <= {0, 41, 88, 143, 185, 242, 255}:
        raise ValueError('Invalid seven-tone 521 × 165 APF platform graphic.')
    points = [(520 - index // 165, index % 165)
              for index, value in enumerate(pixels) if value != 255]
    if not points or (min(x for x, y in points), max(x for x, y in points), max(y for x, y in points)) != (131, 248, 136):
        raise ValueError('Platform graphic differs from the portable left edge, width or baseline.')


def encoded(value):
    return (json.dumps(value, indent=2) + '\n').encode()


def verify_workspace(workspace, metadata):
    package = workspace / 'dist/pocket-dc-native-library'
    manifest = json.loads((package / 'native-manifest.json').read_text())
    if manifest['experimental'] or manifest['excluded_roms'] or manifest['rom_count'] != len(PROFILES):
        raise ValueError('The public release requires the complete qualified library.')
    components = ['components', 'fpga', 'system-pink-pocket', 'system-pdc100-pocket']
    components += ['system-pink-' + scene + '-pocket' for scene in SCENES]
    components += ['system-' + rom.key + '-pocket' for rom in NATIVE_ROMS]
    receipt_hashes = {}
    for component in components:
        path = workspace / 'build/native-evidence' / (component + '.json')
        receipt = json.loads(path.read_text())
        if not receipt.get('passed') or receipt['inputs'] != inputs(component):
            raise ValueError(f'Missing, failed or changed-source evidence: {component}')
        for relative, expected in receipt['inputs'].items():
            if digest(workspace / relative, 'sha256') != expected:
                raise ValueError(f'Frozen source differs: {relative}')
        receipt_hashes[component] = digest(path, 'sha256')
    fpga = json.loads((workspace / 'build/native-evidence/fpga.json').read_text())
    output = workspace / 'build/fpga/native/fpga/output_files'
    timing = output / 'native-timing-pass.json'
    record = json.loads(timing.read_text())
    if (record.get('passed') is not True or record.get('corners') != 4 or
            record['rbf_sha256'] != metadata['raw_rbf_sha256'] or
            fpga['rbf_sha256'] != metadata['raw_rbf_sha256'] or
            fpga['timing_sha256'] != digest(timing, 'sha256') or
            digest(output / 'ap_core.rbf', 'sha256') != metadata['raw_rbf_sha256']):
        raise ValueError('Four-corner timing evidence does not match the bitstream.')
    # Verify every private package input, but only copy explicitly allowed files below.
    for relative, expected in manifest['files'].items():
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts or digest(package / path, 'sha256') != expected:
            raise ValueError(f'Private package integrity mismatch: {relative}')
    old_core = package / 'Cores' / manifest['core_id']
    if digest(old_core / 'bitstream.rbf_r', 'sha256') != metadata['bitstream_sha256']:
        raise ValueError('Bitstream differs from the hardware-confirmed release baseline.')
    status = json.loads((workspace / 'diagnostic-build-status.json').read_text())
    if status.get('state') != 'complete' or status.get('source_commit') != metadata['workspace_source_commit']:
        raise ValueError('Workspace completion/source identity differs from the release baseline.')
    return old_core, package, receipt_hashes


def release_readme(metadata):
    readme = (ROOT / 'README.md').read_text()
    base_url = 'https://github.com/' + metadata['repository'] + '/blob/v' + metadata['version'] + '/'
    return re.sub(r'\]\((?!https?://)([^)]+)\)',
                  lambda match: '](' + base_url + match[1] + ')', readme).encode()


def release_files(old_core, package, metadata):
    core_id = metadata['author'] + '.' + metadata['shortname']
    prefix = 'Cores/' + core_id + '/'
    files = {prefix + name: (old_core / name).read_bytes() for name in CORE_FILES}
    definition = json.loads(files[prefix + 'core.json'])
    definition['core']['metadata'].update(
        author=metadata['author'], shortname=metadata['shortname'],
        url='https://github.com/' + metadata['repository'],
        version=metadata['version'], date_release=metadata['date_release'])
    definition['core']['framework']['dock']['supported'] = True
    files[prefix + 'core.json'] = encoded(definition)
    # Diagnostic readouts stay in the development packager; release menus are empty.
    files[prefix + 'interact.json'] = (ROOT / 'release/interact.json').read_bytes()
    files[prefix + 'README.md'] = release_readme(metadata)
    files[prefix + 'updaters.json'] = encoded({
        'plugins': ['https://github.com/' + metadata['repository'] + '-plugin']})
    for stem, label in PROFILES.items():
        files[f'Assets/pdc/{core_id}/{label}.json'] = encoded({'instance': {
            'magic': 'APF_VER_1', 'data_slots': [{'id': 1, 'filename': stem + '.rom'}]}})
    files['Platforms/pdc.json'] = (package / 'Platforms/pdc.json').read_bytes()
    files['Platforms/_images/pdc.bin'] = (ROOT / 'release/pdc-platform.bin').read_bytes()
    files[prefix + 'icon.bin'] = (ROOT / 'release/author-icon.bin').read_bytes()
    for source, name in (
        ('LICENSE', 'LICENSE'), ('NOTICE.md', 'NOTICE.md'),
        ('third_party/veesem/LICENSE', 'veesem-ISC.txt'),
        ('third_party/pocket/psram-LICENSE', 'psram-MIT.txt'),
        ('third_party/pocket/sdram-LICENSE', 'Analogue-Pocket-Framework.txt'),
        ('third_party/runtime/LicenseRef-Intel-FPGA-IP.txt', 'Intel-FPGA-IP.txt'),
        ('third_party/pocket/README.md', 'memory-controller-changes.md')):
        files[prefix + 'licenses/' + name] = (ROOT / source).read_bytes()
    validate_release(files, metadata)
    return files


def metadata_patch(baseline, metadata, source_root=ROOT):
    """Change only version/date, README and plugin recommendation in a pinned release."""
    pin = metadata['metadata_baseline']
    if Path(pin['archive']).name != pin['archive']:
        raise ValueError('Baseline archive must be a filename.')
    archive = baseline / pin['archive']
    info_path = baseline / 'build-info.json'
    if (digest(archive, 'sha256') != pin['archive_sha256'] or
            digest(info_path, 'sha256') != pin['build_info_sha256']):
        raise ValueError('Published baseline hashes differ from the pinned release.')
    info = json.loads(info_path.read_text())
    for key in ('repository', 'author', 'shortname', 'hardware_source_commit',
                'workspace_source_commit', 'bitstream_sha256', 'raw_rbf_sha256'):
        if info[key] != metadata[key]:
            raise ValueError(f'Metadata patch changes qualified identity: {key}')
    old_version, new_version = info['version'].split('.'), metadata['version'].split('.')
    if (len(old_version) != 3 or len(new_version) != 3 or
            old_version[:2] != new_version[:2] or int(new_version[2]) <= int(old_version[2])):
        raise ValueError('Metadata-only releases require an increasing patch version.')
    if (info.get('roms_included') is not False or info.get('diagnostic_menu') is not False or
            info.get('qualified_profiles') != list(PROFILES) or
            not info.get('validation_receipt_sha256')):
        raise ValueError('Baseline is not the complete ROM-free qualified release.')
    revision = info['packaging_commit']
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Invalid baseline source revision.')
    changed = subprocess.check_output(['git', '-C', str(source_root), 'diff',
                                       '--name-only', revision, '--'], text=True).splitlines()
    allowed = {'.gitignore', 'README.md', 'CHANGELOG.md', 'release/metadata.json',
               'tools/release.py', 'tests/test_release.py', '.github/workflows/plugin.yml'}
    if any(name not in allowed and not name.startswith(('docs/', 'tools/pocket-plugin/'))
           for name in changed):
        raise ValueError('Source changes exceed documentation, plugin and metadata packaging scope.')
    with zipfile.ZipFile(archive) as zipped:
        entries = zipped.infolist()
        if (len({entry.filename for entry in entries}) != len(entries) or
                sum(entry.file_size for entry in entries) > 128 * 1024 * 1024):
            raise ValueError('Invalid baseline ZIP inventory or size.')
        original = {entry.filename: zipped.read(entry) for entry in entries}
    if {name: hashlib.sha256(data).hexdigest() for name, data in original.items()} != info['files']:
        raise ValueError('Baseline ZIP contents differ from its published build information.')
    core = 'Cores/' + metadata['author'] + '.' + metadata['shortname'] + '/'
    definition = json.loads(original[core + 'core.json'])
    for key in ('author', 'shortname', 'version', 'date_release'):
        if definition['core']['metadata'][key] != info[key]:
            raise ValueError('Baseline core identity differs from its build information.')
    definition['core']['metadata'].update(version=metadata['version'], date_release=metadata['date_release'])
    files = {**original, core + 'core.json': encoded(definition),
             core + 'README.md': release_readme(metadata),
             core + 'updaters.json': encoded({
                 'plugins': ['https://github.com/' + metadata['repository'] + '-plugin']})}
    validate_release(files, metadata)
    return files, info


def validate_release(files, metadata):
    core_id = metadata['author'] + '.' + metadata['shortname']
    core = 'Cores/' + core_id + '/'
    allowed = {core + name for name in CORE_FILES} | {'Platforms/pdc.json'}
    allowed.add('Platforms/_images/pdc.bin')
    allowed |= {core + 'README.md', core + 'icon.bin', core + 'updaters.json'}
    allowed |= {f'Assets/pdc/{core_id}/{label}.json' for label in PROFILES.values()}
    allowed |= {core + 'licenses/' + name for name in (
        'LICENSE', 'NOTICE.md', 'veesem-ISC.txt', 'psram-MIT.txt',
        'Analogue-Pocket-Framework.txt', 'Intel-FPGA-IP.txt', 'memory-controller-changes.md')}
    if set(files) != allowed:
        raise ValueError('Archive contains missing or unexpected files; ROMs are never permitted.')
    validate_platform_image(files['Platforms/_images/pdc.bin'])
    if len(files[core + 'icon.bin']) != 36 * 36 * 2:
        raise ValueError('Author icon must be a 36 x 36 APF image.')
    for name, data in files.items():
        if name.endswith('.json'):
            json.loads(data)
    if json.loads(files[core + 'updaters.json']) != {
            'plugins': ['https://github.com/' + metadata['repository'] + '-plugin']}:
        raise ValueError('Updater metadata must contain only the canonical ROM-preparation plugin.')
    for name in CORE_FILES:
        if name.endswith('.json'):
            key = name.removesuffix('.json')
            if json.loads(files[core + name])[key].get('magic') != 'APF_VER_1':
                raise ValueError(f'Invalid APF definition: {name}')
    slots = json.loads(files[core + 'data.json'])['data']['data_slots']
    rom_slots = [slot for slot in slots if slot.get('id') == 1]
    if len(rom_slots) != 1 or rom_slots[0].get('size_maximum') != '0x4000000':
        raise ValueError('ROM loader limit must remain the qualified 64 MiB.')
    menu = json.loads(files[core + 'interact.json'])['interact']
    if menu != {'magic': 'APF_VER_1', 'variables': [], 'messages': []}:
        raise ValueError('Release contains diagnostic settings.')
    definition = json.loads(files[core + 'core.json'])['core']
    for key in ('author', 'shortname', 'version', 'date_release'):
        if definition['metadata'][key] != metadata[key]:
            raise ValueError(f'Release identity mismatch: {key}')
    framework = definition['framework']
    if not framework['dock']['supported'] or framework['dock']['analog_output'] or framework['sleep_supported']:
        raise ValueError('Release must support digital Dock output without sleep or analog output.')
    if definition['metadata']['url'] != 'https://github.com/' + metadata['repository']:
        raise ValueError('Repository URL differs from release identity.')
    if hashlib.sha256(files[core + 'bitstream.rbf_r']).hexdigest() != metadata['bitstream_sha256']:
        raise ValueError('Release bitstream differs from the hardware-confirmed binary.')
    modes = json.loads(files[core + 'video.json'])['video']['display_modes']
    if [int(mode['id'], 16) for mode in modes] != list(DISPLAY_MODES):
        raise ValueError('Release display filters differ from the selected sixteen modes.')
    controls = json.loads(files[core + 'input.json'])['input']['controllers'][0]['mappings']
    keys = {item['name']: item['key'] for item in controls}
    if (keys['A'], keys['B']) != ('pad_btn_b', 'pad_btn_a'):
        raise ValueError('Release control mapping differs from the confirmed A/B swap.')
    for stem, label in PROFILES.items():
        instance = json.loads(files[f'Assets/pdc/{core_id}/{label}.json'])
        if instance != {'instance': {'magic': 'APF_VER_1', 'data_slots': [{'id': 1, 'filename': stem + '.rom'}]}}:
            raise ValueError(f'Invalid ROM launcher: {stem}')


def write_archive(path, files):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--workspace', type=Path)
    source.add_argument('--baseline', type=Path, help='directory containing the pinned published ZIP and build-info.json for a metadata-only patch')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/release')
    args = parser.parse_args()
    if subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], text=True).strip():
        raise ValueError('Commit the release inputs before packaging so build-info identifies their exact revision.')
    metadata = json.loads((ROOT / 'release/metadata.json').read_text())
    if not re.fullmatch(r'[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+', metadata['repository']):
        raise ValueError('Invalid repository identity.')
    if args.baseline:
        files, previous = metadata_patch(args.baseline.resolve(), metadata)
        receipts = previous['validation_receipt_sha256']
    else:
        old_core, package, receipts = verify_workspace(args.workspace.resolve(), metadata)
        files = release_files(old_core, package, metadata)
    args.output.mkdir(parents=True, exist_ok=True)
    name = f"{metadata['author']}.{metadata['shortname']}_{metadata['version']}_{metadata['date_release']}.zip"
    archive = args.output / name
    write_archive(archive, files)
    with zipfile.ZipFile(archive) as check:
        validate_release({name: check.read(name) for name in check.namelist()}, metadata)
    revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    info = {**metadata, 'packaging_commit': revision, 'roms_included': False,
            'diagnostic_menu': False, 'qualified_profiles': list(PROFILES),
            'validation_receipt_sha256': receipts,
            'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}}
    if args.baseline:
        info.update(release_type='metadata-only', qualification_from_release='v' + previous['version'],
                    baseline_packaging_commit=previous['packaging_commit'])
    info_path = args.output / 'build-info.json'
    info_path.write_bytes(encoded(info))
    (args.output / 'SHA256SUMS').write_text(''.join(
        f'{digest(path, "sha256")}  {path.name}\n' for path in (archive, info_path)))
    print(f'ROM-free release: {archive}\nVerified files: {len(files)}; unchanged hardware bitstream.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
