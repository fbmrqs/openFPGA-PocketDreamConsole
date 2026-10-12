"""Verify each imported ROM with the production-clock Pocket output fixture."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from rom_library import NATIVE_ROMS, validate_native
from evidence import inputs

record_path = ROOT / 'build/rom-library-validation.json'
record = {'passed': False, 'frames_per_rom': 1800,
          'system_inputs': inputs('system-pink-pocket'),
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'roms': {}}
record_path.write_text(json.dumps(record, indent=2) + '\n')


def check(rom):
    asset = ROOT / 'build/rom-library/native' / (rom.key + '.rom')
    asset_hash = validate_native(rom, asset)
    log = ROOT / 'build/rom-library' / (rom.key + '.log')
    component = 'system-' + rom.key + '-pocket'
    evidence = [sys.executable, 'tools/fpga/evidence.py']
    with log.open('w') as output:
        subprocess.run([str(ROOT / 'build/rtl/rom-check-full/Vpdc_rom_check'), str(asset)], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)
        subprocess.run(evidence + ['begin', component], cwd=ROOT, check=True)
        command = [str(ROOT / 'build/rtl/system-pocket/Vpdc_system'), str(asset), '1800', 'paced']
        if rom.videojet:
            command.append('videojet')
        subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)
        subprocess.run(evidence + ['end', component], cwd=ROOT, check=True)
    print(f'{rom.label}: full CRC readback and 1,800-frame Pocket output comparison passed', flush=True)
    return rom.key, {'sha256': asset_hash, 'videojet': rom.videojet}


with ThreadPoolExecutor(max_workers=2) as pool:
    for key, result in pool.map(check, NATIVE_ROMS):
        record['roms'][key] = result
        record_path.write_text(json.dumps(record, indent=2) + '\n')
if record['system_inputs'] != inputs('system-pink-pocket'):
    raise ValueError('Sources changed during library validation.')
record['passed'] = True
record_path.write_text(json.dumps(record, indent=2) + '\n')
