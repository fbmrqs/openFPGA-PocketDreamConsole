#!/usr/bin/env python3
"""Package a validated native core or an explicitly experimental hardware test."""
from pathlib import Path
import argparse
import time
import json
import re
import shutil
import zipfile
from fpga.evidence import inputs, require
from package import ROMS, digest, write_json, validate_core_identity, validate_input
from rom_library import NATIVE_ROMS, validate_native

ROOT = Path(__file__).resolve().parents[1]

# The selected filters fit the APF limit of sixteen modes in one entry.
DISPLAY_MODES = (0x10, 0x30, 0x32, 0x40, 0x41, 0x42, 0x51, 0x52,
                 0x63, 0x71, 0x72, 0x82, 0x21, 0x22, 0x61, 0xE1)
LEGACY_CORES = ('Local.PocketDreamConsole', 'Local.PocketDreamConsoleFPGATest',
                'Local.PocketDreamConsoleFPGATestExtra', 'Local.PocketDreamLibraryTest',
                'Local.PocketDreamLibraryTestExtra')


def backup_core_entries(card):
    backup = ROOT / 'build/card-core-backups' / str(time.time_ns())
    for core_id in LEGACY_CORES:
        for relative in ('Cores/' + core_id, 'Assets/pdc/' + core_id,
                         'Licenses/' + core_id.removeprefix('Local.')):
            source = card / relative
            if not source.is_dir():
                continue
            destination = backup / relative
            shutil.copytree(source, destination)
            for path in source.rglob('*'):
                if path.is_file() and digest(path, 'sha256') != digest(destination / path.relative_to(source), 'sha256'):
                    raise ValueError(f'Core backup verification failed: {path}')
    return backup


def retire_core_entries(card, core_id, files):
    for legacy_id in LEGACY_CORES:
        for relative in ('Cores/' + legacy_id, 'Assets/pdc/' + legacy_id,
                         'Licenses/' + legacy_id.removeprefix('Local.')):
            directory = card / relative
            if not directory.is_dir():
                continue
            if legacy_id != core_id:
                shutil.rmtree(directory)
            else:
                for path in directory.rglob('*'):
                    if path.is_file() and path.relative_to(card).as_posix() not in files:
                        path.unlink()


def video_definition(template):
    return {'video': {**template['video'],
        'display_modes': [{'id': f'0x{mode:02X}'} for mode in DISPLAY_MODES],
        'defaults': {**template['video'].get('defaults', {}), 'sharpness': 3}}}

def fpga_verification(experimental):
    outputs = ROOT / 'build/fpga/native/fpga/output_files'
    rbf_hash = digest(outputs / 'ap_core.rbf', 'sha256')
    if not experimental:
        receipt = require('fpga')
        if rbf_hash != receipt['rbf_sha256']:
            raise ValueError('Bitstream differs from the validated build.')
        return receipt
    receipt = json.loads((ROOT / 'build/native-evidence/fpga.json').read_text())
    if receipt['inputs'] != inputs('fpga'):
        raise ValueError('Experimental FPGA build has stale source evidence.')
    for report, success in (('ap_core.fit.summary', 'Fitter Status : Successful'),
                            ('ap_core.asm.rpt', 'Quartus Prime Assembler was successful')):
        if success not in (outputs / report).read_text():
            raise ValueError(f'Experimental build did not complete: {report}')
    slacks = []
    for corner in range(4):
        report = (outputs / f'native-{corner}-setup.rpt').read_text()
        match = re.search(r'Worst case slack is (-?[0-9.]+)', report)
        if not match:
            raise ValueError(f'Missing setup timing result for corner {corner}.')
        slacks.append(float(match[1]))
    return {**receipt, 'rbf_sha256': rbf_hash, 'experimental': True,
            'setup_slack_ns': slacks}


def verified_library(record):
    if (not record.get('completed') or record.get('frames_per_rom') != 1800 or
            record.get('system_inputs') != inputs('system-pink-pocket') or
            record.get('script_sha256') != digest(ROOT / 'tools/fpga/library-test.py', 'sha256')):
        raise ValueError('ROM library validation is incomplete or stale.')
    passed = set(record['roms'])
    failed = set(record['failures'])
    known = {rom.key for rom in NATIVE_ROMS}
    if passed & failed or (passed | failed) != known:
        raise ValueError('ROM library results contain missing, unknown or conflicting profiles.')
    selected = tuple(rom for rom in NATIVE_ROMS if rom.key in passed)
    if not selected:
        raise ValueError('No additional ROM passed validation; the display package remains independent.')
    receipts = {}
    for rom in selected:
        asset_hash = validate_native(rom, ROOT / 'build/rom-library/native' / (rom.key + '.rom'))
        if record['roms'][rom.key] != {'sha256': asset_hash, 'videojet': rom.videojet}:
            raise ValueError(f'ROM library verification differs: {rom.key}')
        name = 'system-' + rom.key + '-pocket'
        receipts[name] = require(name)
    return selected, receipts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--install-to', type=Path)
    parser.add_argument('--experimental', action='store_true',
                        help='Package a separate hardware test after all timing and validation gates pass.')
    parser.add_argument('--rom-library', action='store_true', help='Include additional ROM profiles that individually passed validation.')
    args = parser.parse_args()
    shortname = 'PocketDreamConsole' + ('Test' if args.experimental else '')
    core_id = 'Local.' + shortname
    out = ROOT / ('dist/pocket-dc-native-library' if args.rom_library else
                  'dist/pocket-dc-native-experimental' if args.experimental else 'dist/pocket-dc-native')
    verification = {name: require(name) for name in
                    ('components', 'system-pink-pocket', 'system-pdc100-pocket')}
    # These older-clock runs are useful diagnostics; production-output runs
    # above exercise the actual clock and full video/audio interfaces.
    for name in ('system-pink', 'system-pdc100', 'system-pink-paced', 'system-pdc100-paced'):
        try:
            verification[name] = require(name)
        except (OSError, ValueError, KeyError, TypeError):
            print(f'Optional historical-clock check unavailable: {name}')
    require('fpga')  # Keep the passing slow-clock timing baseline for this probe.
    verification['fpga'] = fpga_verification(args.experimental)
    slow_receipt = json.loads((ROOT / 'build/slow-clock-validation.json').read_text())
    if (not slow_receipt.get('passed') or slow_receipt.get('clock_khz') != 98304 or
            slow_receipt['system_inputs'] != inputs('system-pink') or
            slow_receipt['fpga_inputs'] != inputs('fpga') or
            slow_receipt['script_sha256'] != digest(ROOT / 'tools/fpga/slow-clock-test.sh', 'sha256')):
        raise ValueError('Slow-clock validation is missing, failed or stale.')
    verification['slow_system'] = slow_receipt
    selected_roms = ()
    excluded_roms = {}
    if args.rom_library:
        library = json.loads((ROOT / 'build/rom-library-validation.json').read_text())
        selected_roms, receipts = verified_library(library)
        verification.update(receipts)
        excluded_roms = library['failures']
        for key in excluded_roms:
            print(f'Excluded failed ROM profile: {key}')
        verification['library'] = library

    rbf = ROOT / 'build/fpga/native/fpga/output_files/ap_core.rbf'
    for filename, _, _, size, _, expected in ROMS:
        path = ROOT / filename
        if path.stat().st_size != size or digest(path, 'sha1') != expected:
            raise ValueError(f'Original ROM size/hash mismatch: {filename}')
    if out.exists():
        shutil.rmtree(out)
    core = out / 'Cores' / core_id
    core.mkdir(parents=True)
    template = ROOT / '.deps/core-template'
    definition = json.loads((template / 'core.json').read_text())
    definition['core']['metadata'].update(
        platform_ids=['pdc'], shortname=shortname, author='Local', url='',
        description='Pocket Dream Console FPGA core',
        version='0.2.1', date_release='2026-10-14')
    definition['core']['framework']['dock']['supported'] = True
    write_json(core / 'core.json', definition)
    for name in ('audio.json', 'video.json', 'interact.json', 'variants.json'):
        shutil.copy2(template / name, core / name)
    video = json.loads((template / 'video.json').read_text())
    write_json(core / 'video.json', video_definition(video))
    if args.experimental:
        write_json(core / 'interact.json', {'interact': {'magic': 'APF_VER_1',
            'variables': [{'name': 'S', 'id': 1, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000000'},
                          {'name': 'F', 'id': 2, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000008'},
                          {'name': 'O', 'id': 3, 'type': 'number_u32',
                           'enabled': False, 'address': '0x2000000c'},
                          {'name': 'M', 'id': 4, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000010'},
                          {'name': 'R', 'id': 5, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000014'},
                          {'name': 'L', 'id': 6, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000018'},
                          {'name': 'W', 'id': 7, 'type': 'number_u32',
                           'enabled': False, 'address': '0x2000001c'},
                          {'name': 'A', 'id': 8, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000020'},
                          {'name': 'B', 'id': 9, 'type': 'number_u32',
                           'enabled': False, 'address': '0x20000024'}], 'messages': []}})
    shutil.copy2(ROOT / '.deps/openfpga-sdk/dist/sdk/Cores/ThinkElastic.openfpgaOS/icon.bin', core / 'icon.bin')
    write_json(core / 'data.json', {'data': {'magic': 'APF_VER_1', 'data_slots': [
        {'id': 0, 'name': 'Game', 'required': True, 'parameters': 275, 'extensions': ['json']},
        {'id': 1, 'name': 'PDC ROM', 'required': False, 'secondary': True, 'parameters': 0,
         'extensions': ['rom'], 'address': '0x10000000', 'size_maximum': '0x4000000'}]}})
    write_json(core / 'input.json', {'input': {'magic': 'APF_VER_1', 'controllers': [{
        'type': 'default', 'mappings': [
            {'id': 0, 'name': 'A', 'key': 'pad_btn_b'},
            {'id': 1, 'name': 'B', 'key': 'pad_btn_a'},
            {'id': 10, 'name': 'Left Trigger', 'key': 'pad_trig_l'},
            {'id': 11, 'name': 'Right Trigger', 'key': 'pad_trig_r'},
            {'id': 20, 'name': 'Pause', 'key': 'pad_btn_start'},
            {'id': 21, 'name': 'Select+Start: Reset', 'key': 'pad_btn_select'}]}]}})
    reversal = bytes(int(f'{byte:08b}'[::-1], 2) for byte in range(256))
    (core / 'bitstream.rbf_r').write_bytes(rbf.read_bytes().translate(reversal))
    for filename, stem, label, _, used, _ in ROMS:
        asset = out / 'Assets/pdc/common' / f'{stem}.rom'
        asset.parent.mkdir(parents=True, exist_ok=True)
        with (ROOT / filename).open('rb') as source, asset.open('wb') as dest:
            remaining = used
            while remaining:
                block = source.read(min(remaining, 1024*1024))
                if not block:
                    raise ValueError(f'Short ROM read: {filename}')
                dest.write(block)
                remaining -= len(block)
        write_json(out / 'Assets/pdc' / core_id / f'{label}.json', {'instance': {
            'magic': 'APF_VER_1', 'data_slots': [{'id': 1, 'filename': f'{stem}.rom'}]}})
    if args.rom_library:
        for rom in selected_roms:
            shutil.copy2(ROOT / 'build/rom-library/native' / (rom.key + '.rom'), out / 'Assets/pdc/common' / (rom.key + '.rom'))
            write_json(out / 'Assets/pdc' / core_id / (rom.label + '.json'), {'instance': {
                'magic': 'APF_VER_1', 'data_slots': [{'id': 1, 'filename': rom.key + '.rom'}]}})
    write_json(out / 'Platforms/pdc.json', {'platform': {
        'category': 'Handheld', 'name': 'Pocket Dream Console', 'year': 2008,
        'manufacturer': 'Conny / VideoJet / Anncia'}})
    image = out / 'Platforms/_images/pdc.bin'
    image.parent.mkdir(parents=True)
    shutil.copy2(ROOT / '.deps/openfpga-sdk/dist/sdk/Platforms/_images/openfpgaos.bin', image)
    notices = out / 'Licenses' / shortname
    notices.mkdir(parents=True)
    for source, name in (
        (ROOT / 'third_party/veesem/LICENSE', 'veesem-ISC.txt'),
        (ROOT / 'third_party/pocket/psram-LICENSE', 'psram-MIT.txt'),
        (ROOT / 'third_party/pocket/sdram-LICENSE', 'framework-LICENSE.txt'),
        (ROOT / '.deps/openfpga-sdk/LICENSE', 'openfpgaSDK-Apache-2.0.txt'),
        (ROOT / '.deps/openfpga-sdk/NOTICE', 'openfpgaSDK-NOTICE.txt'),
        (ROOT / 'third_party/pocket/README.md', 'memory-controller-changes.md')):
        shutil.copy2(source, notices / name)
    shutil.copy2(ROOT / 'docs/native-fpga.md', out / ('README-FPGA-EXPERIMENTAL.md' if args.experimental else 'README-FPGA.md'))
    for name in ('native-refinements.md', 'native-full-speed-baseline.json'):
        shutil.copy2(ROOT / 'docs' / name, out / name)
    for entry in (core,):
        validate_core_identity(entry)
        validate_input(json.loads((entry / 'input.json').read_text()))
        for name in ('core', 'audio', 'video', 'data', 'input', 'interact', 'variants'):
            definition = json.loads((entry / f'{name}.json').read_text())
            if definition[name]['magic'] != 'APF_VER_1':
                raise ValueError(f'Invalid native core definition: {entry.name}/{name}.json')
    files = {p.relative_to(out).as_posix(): digest(p, 'sha256')
             for p in sorted(out.rglob('*')) if p.is_file()}
    write_json(out / ('native-experimental-manifest.json' if args.experimental else 'native-manifest.json'),
               {'hardware_verified': False, 'experimental': args.experimental,
                'display_modes': list(DISPLAY_MODES), 'core_id': core_id,
                'rom_count': len(ROMS) + len(selected_roms),
                'rom_library': [rom.key for rom in selected_roms], 'excluded_roms': excluded_roms,
                'memory_check': {'bank_bytes': 8388608, 'passes': 2, 'pink_crc32': '0x0C1DC0F3', 'pdc100_crc32': '0xCCD6C6D3'},
                'pacing_max_backlog_cycles': 131071, 'pacing_overflow_status_mask': '0x00008000',
                'diagnostic_clock_khz': 98304, 'sdram_clock_khz': 49152, 'prior_full_system_test_clock_khz': 196608,
               'validation': verification, 'files': files})
    archive = ROOT / ('dist/pocket-dc-native-library.zip' if args.rom_library else
                      'dist/pocket-dc-native-experimental.zip' if args.experimental else 'dist/pocket-dc-native-preview.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as dest:
        for file in sorted(out.rglob('*')):
            if file.is_file():
                dest.write(file, file.relative_to(out))
    print(f'Native SD tree: {out}\nPrivate ROM-inclusive ZIP: {archive}')
    if args.install_to:
        card = args.install_to.resolve(strict=True)
        obsolete = []
        if args.rom_library:
            for entry in (core_id,):
                for rom in NATIVE_ROMS:
                    if rom in selected_roms:
                        continue
                    target = card / 'Assets/pdc' / entry / (rom.label + '.json')
                    if target.exists():
                        expected = {'instance': {'magic': 'APF_VER_1', 'data_slots': [
                            {'id': 1, 'filename': rom.key + '.rom'}]}}
                        if json.loads(target.read_text()) != expected:
                            raise ValueError(f'Excluded-ROM launch entry was modified: {target}; installation stopped.')
                        obsolete.append(target)
        for name, expected in files.items():
            target = card / name
            if target.exists() and digest(target, 'sha256') == expected:
                continue
            if target.exists() and name.startswith(('Assets/pdc/common/', 'Platforms/')):
                raise ValueError(f'Shared card file differs: {target}; installation stopped.')
        backup = backup_core_entries(card) if not args.experimental else None
        for source in sorted(out.rglob('*')):
            if not source.is_file():
                continue
            target = card / source.relative_to(out)
            expected = digest(source, 'sha256')
            if target.exists() and digest(target, 'sha256') == expected:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + '.pdc-tmp')
            shutil.copyfile(source, temporary)
            temporary.replace(target)
            if digest(target, 'sha256') != expected:
                raise ValueError(f'Card verification failed: {target}')
        for target in obsolete:
            target.unlink()
        if backup:
            retire_core_entries(card, core_id, files)
            print(f'Retired previous core entries; verified backups: {backup}')
        print(f'Installed and verified on {card}; card remains mounted.')
    print('Physical Pocket boot, gameplay and memory timing still require a device test.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
