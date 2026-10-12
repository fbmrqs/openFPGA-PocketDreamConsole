#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
rom="${1:-pdc_pink.u2}"
frames="${2:-10}"
mode="${3:-native-latency}"
realtime=0
directory=system
component=system-pink
if [[ "$rom" == *pdc100.bin ]]; then component=system-pdc100;fi
if [ "$mode" = paced ]; then
    realtime=1;directory=system-paced;component="$component-paced"
elif [ "$mode" != native-latency ]; then
    echo 'Expected native-latency or paced mode.' >&2;exit 2
fi
mkdir -p "build/rtl/$directory"
if [ "$frames" -ge 1800 ]; then python3 tools/fpga/evidence.py begin "$component";fi
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_system -GREALTIME="$realtime" +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir "build/rtl/$directory" \
  -CFLAGS "-std=c++20 -O3 -fno-strict-aliasing -I$PWD/third_party/veesem -I$PWD/src" \
  rtl/*.sv "$PWD/tests/rtl/system_differential.cpp" "$PWD/src/pdc.cpp" \
  "$PWD"/third_party/veesem/core/spg200/*.cpp \
  > "build/rtl/$directory-build.log" 2>&1
"build/rtl/$directory/Vpdc_system" "$rom" "$frames" "$mode"
if [ "$frames" -ge 1800 ]; then python3 tools/fpga/evidence.py end "$component";fi
