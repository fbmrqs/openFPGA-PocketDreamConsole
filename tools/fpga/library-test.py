"""Verify each imported ROM with the production-clock Pocket output fixture."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from rom_library import NATIVE_ROMS, validate_native
from evidence import inputs

record_path = ROOT / 'build/rom-library-validation.json'
record = {'passed': False, 'completed': False, 'frames_per_rom': 1800,
          'system_inputs': inputs('system-pink-pocket'),
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'roms': {}, 'failures': {}}
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
    jobs = {pool.submit(check, rom): rom for rom in NATIVE_ROMS}
    for job in as_completed(jobs):
        rom = jobs[job]
        try:
            key, result = job.result()
            record['roms'][key] = result
        except (subprocess.CalledProcessError, OSError, ValueError) as error:
            log = ROOT / 'build/rom-library' / (rom.key + '.log')
            record['failures'][rom.key] = {'error': str(error), 'log': str(log)}
            print(f'{rom.label}: validation failed; see {log}', flush=True)
        record_path.write_text(json.dumps(record, indent=2) + '\n')
if record['system_inputs'] != inputs('system-pink-pocket'):
    raise ValueError('Sources changed during library validation.')
record['completed'] = True
record['passed'] = not record['failures']
record_path.write_text(json.dumps(record, indent=2) + '\n')
if record['failures']:
    raise SystemExit('ROM validation failed: ' + ', '.join(record['failures']))
