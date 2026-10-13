#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
library=.deps/quartus-sim/altera_mf.v
if [ ! -f "$library" ]; then
    echo 'Copy Quartus 25.1 eda/sim_lib/altera_mf.v into .deps/quartus-sim/ before running native tests.' >&2
    exit 1
fi
mkdir -p build/rtl/cache-vendor
cat > build/rtl/cache-vendor/memory_tb.v <<'WRAPPER'
`timescale 1ns/1ps
`include "memory_tb.sv"
WRAPPER
iverilog -g2012 -DALTERA_RESERVED_QIS -s cache_bank_vendor_tb -o build/rtl/cache-vendor/bank.vvp \
    rtl/pdc_rom_cache.sv tests/rtl/cache_bank_vendor_tb.sv "$library" > build/rtl/cache-vendor/bank-build.log 2>&1
vvp build/rtl/cache-vendor/bank.vvp
iverilog -g2012 -DALTERA_RESERVED_QIS -s cache_bank_vendor_tb -Pcache_bank_vendor_tb.TEST_SPRITES=1 \
    -o build/rtl/cache-vendor/sprites.vvp rtl/pdc_ppu.sv tests/rtl/cache_bank_vendor_tb.sv "$library" \
    >build/rtl/cache-vendor/sprites-build.log 2>&1
vvp build/rtl/cache-vendor/sprites.vvp
for mode in 0 1; do
    for staged in 0 1; do
        iverilog -g2012 -DALTERA_RESERVED_QIS -DPDC_VERIFY_MMIO_CYCLES -I tests/rtl -s memory_tb \
            -Pmemory_tb.BURST_LINES="$mode" -Pmemory_tb.REQUEST_STAGED="$staged" \
            -o "build/rtl/cache-vendor/cache-$mode-$staged.vvp" rtl/pdc_rom_cache.sv \
            build/rtl/cache-vendor/memory_tb.v "$library" > "build/rtl/cache-vendor/cache-$mode-$staged-build.log" 2>&1
        vvp "build/rtl/cache-vendor/cache-$mode-$staged.vvp"
    done
done

iverilog -g2012 -DALTERA_RESERVED_QIS -DPDC_VERIFY_MMIO_CYCLES -I tests/rtl -s memory_tb \
    -Pmemory_tb.BURST_LINES=1 -Pmemory_tb.REQUEST_STAGED=1 -Pmemory_tb.HASH_INDEX=1 \
    -o build/rtl/cache-vendor/hashed.vvp rtl/pdc_rom_cache.sv build/rtl/cache-vendor/memory_tb.v "$library" \
    >build/rtl/cache-vendor/hashed-build.log 2>&1
vvp build/rtl/cache-vendor/hashed.vvp

for mode in 0 1; do
    iverilog -g2012 -DALTERA_RESERVED_QIS -DPDC_VERIFY_MMIO_CYCLES -I tests/rtl -s memory_tb \
        -Pmemory_tb.BURST_LINES="$mode" -Pmemory_tb.FAST_LINE=1 \
        -o "build/rtl/cache-vendor/front-$mode.vvp" rtl/pdc_rom_cache.sv \
        build/rtl/cache-vendor/memory_tb.v "$library" > "build/rtl/cache-vendor/front-$mode-build.log" 2>&1
    vvp "build/rtl/cache-vendor/front-$mode.vvp"
done

iverilog -g2012 -DALTERA_RESERVED_QIS -DPDC_VERIFY_MMIO_CYCLES -s ram_tb \
    -o build/rtl/cache-vendor/ram "$library" rtl/pdc_ram.sv rtl/pdc_rom_cache.sv tests/rtl/ram_tb.sv \
    >build/rtl/cache-vendor/ram-build.log 2>&1
vvp build/rtl/cache-vendor/ram
