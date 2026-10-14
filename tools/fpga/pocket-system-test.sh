#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
rom="${1:-pdc_pink.u2}"
frames="${2:-1800}"
scene="${3:-}"
component=system-pink-pocket
if [[ "$rom" == *pdc100.bin ]]; then component=system-pdc100-pocket;fi
if [ -n "$scene" ]; then
    case "$scene" in hair-salon|bunny-pinky|beeline-2|fun-match-2) ;; *) exit 2;; esac
    if [[ "$rom" != *pdc_pink.u2 ]] || [ "$frames" -lt 1800 ]; then exit 2;fi
    component="system-pink-$scene-pocket"
fi
mkdir -p build/rtl/system-pocket build/rtl/output-framebuffer build/rtl/output-audio
if [ "$frames" -ge 1800 ]; then python3 tools/fpga/evidence.py begin "$component";fi
for module in framebuffer audio; do
    verilator --cc --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module "pdc_$module" -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
        --Mdir "build/rtl/output-$module" rtl/pocket/pdc_reset_sync.sv rtl/pocket/pdc_async_fifo.sv \
        "rtl/pocket/pdc_$module.sv" > "build/rtl/output-$module-build.log" 2>&1
done
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_system -GREALTIME=1 -GCLOCK_KHZ=98304 \
    +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
    --Mdir build/rtl/system-pocket \
    -CFLAGS "-std=c++20 -O3 -DPDC_TEST_CLOCK_KHZ=98304 -DPDC_POCKET_OUTPUTS -fno-strict-aliasing -I$PWD/third_party/veesem -I$PWD/src -I$PWD/build/rtl/output-framebuffer -I$PWD/build/rtl/output-audio" \
    -LDFLAGS "$PWD/build/rtl/output-framebuffer/Vpdc_framebuffer__ALL.a $PWD/build/rtl/output-audio/Vpdc_audio__ALL.a" \
    rtl/*.sv "$PWD/tests/rtl/system_differential.cpp" "$PWD/src/pdc.cpp" \
    "$PWD"/third_party/veesem/core/spg200/*.cpp > build/rtl/system-pocket-build.log 2>&1
arguments=("$rom" "$frames" paced)
if [ -n "$scene" ]; then arguments+=("$scene");fi
build/rtl/system-pocket/Vpdc_system "${arguments[@]}"
if [ "$frames" -ge 1800 ]; then python3 tools/fpga/evidence.py end "$component";fi
