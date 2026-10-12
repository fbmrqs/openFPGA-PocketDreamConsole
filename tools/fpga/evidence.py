"""Bind successful verification to the exact source files that were checked."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'build/native-evidence'


def inputs(component):
    paths = set((ROOT / 'rtl').glob('*.sv'))
    paths.add(ROOT / 'tools/fpga/evidence.py')
    if component.startswith('system-'):
        paths.update((ROOT / 'src').glob('*.[ch]*'))
        paths.add(ROOT / 'tests/rtl/system_differential.cpp')
        paths.add(ROOT / 'tests/rtl/pocket_outputs.h')
        paths.add(ROOT / 'tools/fpga/pocket-system-test.sh')
        paths.add(ROOT / 'tools/fpga/system-test.sh')
        if component.endswith('-pocket'):
            paths.update((ROOT / 'rtl/pocket').glob('*'))
    else:
        paths.update((ROOT / 'rtl/pocket').glob('*'))
        paths.update((ROOT / 'third_party/pocket').glob('*'))
        if component == 'components':
            paths.update((ROOT / 'tests/rtl').glob('*'))
            paths.add(ROOT / '.deps/core-template/src/fpga/apf/common.v')
            paths.add(ROOT / '.deps/quartus-sim/altera_mf.v')
            paths.add(ROOT / 'tools/fpga/cache-vendor-test.sh')
            paths.update(ROOT / 'tools/fpga' / name for name in ('test.sh', 'boot_fixtures.py'))
        elif component == 'fpga':
            paths.update(ROOT / 'tools/fpga' / name for name in
                         ('quartus.sh', 'prepare-native.py', 'run-qemu.sh', 'enable-qemu.sh', 'validate-timing.tcl', 'validate-mapping.tcl'))
            template = ROOT / '.deps/core-template/src/fpga'
            paths.update(p for p in template.rglob('*') if p.is_file() and
                         p.suffix in ('.v', '.sv', '.qip', '.qsf', '.sdc', '.tcl'))
        else:
            raise ValueError(f'Unknown verification component: {component}')
    if component != 'fpga':
        paths.update(p for p in (ROOT / 'third_party/veesem').rglob('*')
                     if p.is_file() and p.suffix in ('.cpp', '.h'))
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths) if p.is_file()}


def require(component):
    receipt = json.loads((DIRECTORY / f'{component}.json').read_text())
    if not receipt.get('passed') or receipt['inputs'] != inputs(component):
        raise ValueError(f'{component} validation is missing, failed or stale; rerun its make target.')
    return receipt


def main():
    action, component = sys.argv[1:]
    DIRECTORY.mkdir(parents=True, exist_ok=True)
    path = DIRECTORY / f'{component}.json'
    if action == 'begin':
        receipt = {'passed': False, 'inputs': inputs(component)}
        if component == 'fpga':
            (ROOT / 'build/fpga/native/fpga/output_files/native-timing-pass.json').unlink(missing_ok=True)
    elif action == 'end':
        receipt = json.loads(path.read_text())
        if receipt['inputs'] != inputs(component):
            raise ValueError('Sources changed during validation; rerun it.')
        receipt['passed'] = True
        if component == 'fpga':
            bitstream = ROOT / 'build/fpga/native/fpga/output_files/ap_core.rbf'
            rbf_hash = hashlib.sha256(bitstream.read_bytes()).hexdigest()
            timing_path = bitstream.parent / 'native-timing-pass.json'
            timing = json.loads(timing_path.read_text())
            if not timing.get('passed') or timing.get('corners') != 4 or timing.get('rbf_sha256') != rbf_hash:
                raise ValueError('FPGA timing validation is missing, failed or does not match the bitstream.')
            receipt['rbf_sha256'] = rbf_hash
            receipt['timing_sha256'] = hashlib.sha256(timing_path.read_bytes()).hexdigest()
    else:
        raise ValueError('Expected begin or end.')
    path.write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
