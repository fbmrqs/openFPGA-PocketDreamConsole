#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/rtl/system-slow
python3 - <<'PY'
import hashlib,json,sys
from pathlib import Path
sys.path.insert(0,'tools/fpga')
from evidence import inputs
Path('build/slow-clock-validation.json').write_text(json.dumps({'passed':False,'clock_khz':98304,'realtime':True,'frames_per_rom':10,'system_inputs':inputs('system-pink'),'fpga_inputs':inputs('fpga'),'script_sha256':hashlib.sha256(Path('tools/fpga/slow-clock-test.sh').read_bytes()).hexdigest()},indent=2)+'\n')
PY
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_system -GREALTIME=1 -GCLOCK_KHZ=98304 +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/system-slow \
  -CFLAGS "-std=c++20 -O3 -DPDC_TEST_CLOCK_KHZ=98304 -fno-strict-aliasing -I$PWD/third_party/veesem -I$PWD/src" \
  rtl/*.sv "$PWD/tests/rtl/system_differential.cpp" "$PWD/src/pdc.cpp" \
  "$PWD"/third_party/veesem/core/spg200/*.cpp > build/rtl/system-slow-build.log 2>&1
# Compare execution/video/audio at the reduced clock; backlog saturation is
# expected when this diagnostic cannot keep up with the original game speed.
build/rtl/system-slow/Vpdc_system pdc_pink.u2 10 native-latency
build/rtl/system-slow/Vpdc_system pdc100.bin 10 native-latency
python3 - <<'PY'
import hashlib,json,sys
from pathlib import Path
sys.path.insert(0,'tools/fpga')
from evidence import inputs
p=Path('build/slow-clock-validation.json');d=json.loads(p.read_text())
assert d['system_inputs']==inputs('system-pink') and d['fpga_inputs']==inputs('fpga')
assert d['script_sha256']==hashlib.sha256(Path('tools/fpga/slow-clock-test.sh').read_bytes()).hexdigest()
d['passed']=True;p.write_text(json.dumps(d,indent=2)+'\n')
PY
