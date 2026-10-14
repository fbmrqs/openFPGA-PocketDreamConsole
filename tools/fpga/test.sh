#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/rtl/cpu
python3 tools/fpga/evidence.py begin components
python3 -m unittest discover -s tests -p native_validation.py
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_rom_check -GBANK_WORDS_BITS=8 "-GVECTOR_LINE=22'h000030" -GSINGLE_CRC=1553444405 -GPINK_CRC=891097517 -GPDC100_CRC=2605946556 \
  --Mdir build/rtl/rom-check -CFLAGS '-std=c++20 -O2' \
  rtl/pocket/pdc_rom_check.sv "$PWD/tests/rtl/rom_check.cpp" > build/rtl/rom-check-build.log 2>&1
build/rtl/rom-check/Vpdc_rom_check
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_rom_check \
  --Mdir build/rtl/rom-check-full -CFLAGS '-std=c++20 -O2' \
  rtl/pocket/pdc_rom_check.sv "$PWD/tests/rtl/rom_check.cpp" > build/rtl/rom-check-full-build.log 2>&1
build/rtl/rom-check-full/Vpdc_rom_check pdc_pink.u2
build/rtl/rom-check-full/Vpdc_rom_check pdc100.bin
verilator --binary --timing --top-module memory_debug_tb -Wno-TIMESCALEMOD \
  --Mdir build/rtl/memory-debug rtl/pocket/pdc_memory_debug.sv tests/rtl/memory_debug_tb.sv \
  > build/rtl/memory-debug-build.log 2>&1
build/rtl/memory-debug/Vmemory_debug_tb
verilator --binary --timing --top-module fault_debug_tb -Wno-TIMESCALEMOD \
  --Mdir build/rtl/fault-debug rtl/pocket/pdc_fault_debug.sv tests/rtl/fault_debug_tb.sv \
  > build/rtl/fault-debug-build.log 2>&1
build/rtl/fault-debug/Vfault_debug_tb
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --public-flat-rw --top-module unsp_cpu +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/cpu \
  -CFLAGS "-std=c++20 -O2 -DPDC_CPU_TRACE -fno-strict-aliasing -I$PWD/third_party/veesem" \
  rtl/unsp_cpu.sv "$PWD/tests/rtl/cpu_differential.cpp" "$PWD/third_party/veesem/core/spg200/cpu.cpp" \
  > build/rtl/cpu-build.log 2>&1
build/rtl/cpu/Vunsp_cpu

python3 tools/fpga/boot_fixtures.py
mkdir -p build/rtl/boot
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --public-flat-rw --top-module unsp_cpu +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/boot \
  -CFLAGS "-std=c++20 -O2 -DPDC_CPU_TRACE -fno-strict-aliasing -I$PWD/third_party/veesem" \
  rtl/unsp_cpu.sv "$PWD/tests/rtl/cpu_boot.cpp" "$PWD/third_party/veesem/core/spg200/cpu.cpp" \
  > build/rtl/boot-build.log 2>&1
build/rtl/boot/Vunsp_cpu build/rtl/pink-boot.txt
build/rtl/boot/Vunsp_cpu build/rtl/pdc100-boot.txt
mkdir -p build/rtl/ppu
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_ppu +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/ppu \
  -CFLAGS "-std=c++20 -O2 -fno-strict-aliasing -I$PWD/third_party/veesem" \
  rtl/pdc_ppu.sv "$PWD/tests/rtl/ppu_differential.cpp" \
  "$PWD/third_party/veesem/core/spg200/ppu.cpp" \
  "$PWD/third_party/veesem/core/spg200/cpu.cpp" \
  "$PWD/third_party/veesem/core/spg200/irq.cpp" \
  > build/rtl/ppu-build.log 2>&1
build/rtl/ppu/Vpdc_ppu
mkdir -p build/rtl/spu
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_spu +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/spu \
  -CFLAGS "-std=c++20 -O2 -fno-strict-aliasing -I$PWD/third_party/veesem -I$PWD/src" \
  rtl/pdc_spu.sv "$PWD/tests/rtl/spu_differential.cpp" "$PWD/src/pdc.cpp" \
  "$PWD"/third_party/veesem/core/spg200/*.cpp \
  > build/rtl/spu-build.log 2>&1
build/rtl/spu/Vpdc_spu
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_spu -GADDRESS_LOOKAHEAD=1 +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/spu-lookahead \
  -CFLAGS "-std=c++20 -O2 -fno-strict-aliasing -I$PWD/third_party/veesem -I$PWD/src" \
  rtl/pdc_spu.sv "$PWD/tests/rtl/spu_differential.cpp" "$PWD/src/pdc.cpp" \
  "$PWD"/third_party/veesem/core/spg200/*.cpp >build/rtl/spu-lookahead-build.log 2>&1
build/rtl/spu-lookahead/Vpdc_spu
verilator --binary --timing --top-module spu_counter_tb -Wno-PINMISSING -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
  --Mdir build/rtl/spu-counter rtl/pdc_spu.sv tests/rtl/spu_counter_tb.sv > build/rtl/spu-counter-build.log 2>&1
build/rtl/spu-counter/Vspu_counter_tb
mkdir -p build/rtl/io
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --public-flat-rw --top-module pdc_io +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/io \
  -CFLAGS "-std=c++20 -O2 -fno-strict-aliasing -I$PWD/third_party/veesem -I$PWD/src" \
  rtl/pdc_io.sv "$PWD/tests/rtl/io_differential.cpp" "$PWD/src/pdc.cpp" \
  "$PWD"/third_party/veesem/core/spg200/*.cpp \
  > build/rtl/io-build.log 2>&1
build/rtl/io/Vpdc_io
verilator --binary --timing --top-module io_debit_tb -Wno-PINMISSING -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
  --Mdir build/rtl/io-debit rtl/pdc_io.sv tests/rtl/io_debit_tb.sv > build/rtl/io-debit-build.log 2>&1
build/rtl/io-debit/Vio_debit_tb
mkdir -p build/rtl/resampler
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pdc_resampler \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/resampler \
  -CFLAGS "-std=c++20 -O2 -I$PWD/third_party/veesem -I$PWD/src" \
  rtl/pdc_resampler.sv "$PWD/tests/rtl/resampler_differential.cpp" \
  > build/rtl/resampler-build.log 2>&1
build/rtl/resampler/Vpdc_resampler
verilator --binary --timing --top-module memory_tb +define+PDC_POISON_COLLISIONS -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
  --Mdir build/rtl/memory rtl/pdc_rom_cache.sv tests/rtl/memory_tb.sv \
  > build/rtl/memory-build.log 2>&1
build/rtl/memory/Vmemory_tb
verilator --binary --timing --top-module memory_tb -GBURST_LINES=1 +define+PDC_POISON_COLLISIONS -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
  --Mdir build/rtl/memory-burst rtl/pdc_rom_cache.sv tests/rtl/memory_tb.sv > build/rtl/memory-burst-build.log 2>&1
build/rtl/memory-burst/Vmemory_tb
verilator --binary --timing --top-module ram_tb +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD --Mdir build/rtl/ram \
  rtl/pdc_ram.sv rtl/pdc_rom_cache.sv tests/rtl/ram_tb.sv >build/rtl/ram-build.log 2>&1
build/rtl/ram/Vram_tb
for mode in 0 1; do
    verilator --binary --timing --top-module memory_tb -GBURST_LINES="$mode" -GREQUEST_STAGED=1 \
      +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
      --Mdir "build/rtl/memory-staged-$mode" rtl/pdc_rom_cache.sv tests/rtl/memory_tb.sv \
      >"build/rtl/memory-staged-$mode-build.log" 2>&1
    "build/rtl/memory-staged-$mode/Vmemory_tb"
done
bash tools/fpga/cache-vendor-test.sh
verilator --binary --timing --top-module memory_tb -GBURST_LINES=1 -GREQUEST_STAGED=1 -GHASH_INDEX=1 \
  +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
  --Mdir build/rtl/memory-hashed rtl/pdc_rom_cache.sv tests/rtl/memory_tb.sv >build/rtl/memory-hashed-build.log 2>&1
build/rtl/memory-hashed/Vmemory_tb
verilator --binary --timing --top-module system_bus_tb +define+PDC_POISON_COLLISIONS +define+PDC_VERIFY_MMIO_CYCLES \
  -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-BLKSEQ --Mdir build/rtl/system-bus \
  rtl/*.sv tests/rtl/system_bus_tb.sv > build/rtl/system-bus-build.log 2>&1
build/rtl/system-bus/Vsystem_bus_tb
verilator --binary --timing --top-module pacing_tb +define+PDC_POISON_COLLISIONS \
  -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-BLKSEQ --Mdir build/rtl/pacing \
  rtl/*.sv tests/rtl/pacing_tb.sv > build/rtl/pacing-build.log 2>&1
build/rtl/pacing/Vpacing_tb
verilator --binary --timing --top-module pacing_burst_tb +define+PDC_POISON_COLLISIONS \
  -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-BLKSEQ --Mdir build/rtl/pacing-burst \
  rtl/*.sv tests/rtl/pacing_burst_tb.sv > build/rtl/pacing-burst-build.log 2>&1
build/rtl/pacing-burst/Vpacing_burst_tb
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module rom_path_tb \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir build/rtl/rom-path -CFLAGS '-std=c++20 -O2' \
  rtl/pocket/pdc_reset_sync.sv rtl/pocket/pdc_async_fifo.sv rtl/pocket/pdc_rom_store.sv \
  rtl/pocket/pdc_rom_check.sv tests/rtl/rom_path_tb.sv "$PWD/tests/rtl/rom_store.cpp" \
  > build/rtl/rom-path-build.log 2>&1
build/rtl/rom-path/Vrom_path_tb
for definition in 'pdc_audio pocket-audio pocket_audio' 'pdc_framebuffer framebuffer pocket_framebuffer'; do
    read -r module directory fixture <<< "$definition"
    verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module "$module" \
        -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --Mdir "build/rtl/$directory" \
        -CFLAGS '-std=c++20 -O2' \
        rtl/pocket/pdc_reset_sync.sv rtl/pocket/pdc_async_fifo.sv "rtl/pocket/$module.sv" \
        "$PWD/tests/rtl/$fixture.cpp" > "build/rtl/$directory-build.log" 2>&1
    "build/rtl/$directory/V$module"
done
for phase in 300000 600000 1200000 3000000 6000000; do build/rtl/framebuffer/Vpdc_framebuffer "$phase"; done
build/rtl/framebuffer/Vpdc_framebuffer 600000 burst
build/rtl/framebuffer/Vpdc_framebuffer 600000 grayscale
verilator --binary --timing --top-module display_mode_tb -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-WIDTH -Wno-COMBDLY -Wno-MULTIDRIVEN -Wno-INITIALDLY -Wno-CASEX -Wno-CASEINCOMPLETE \
  --Mdir build/rtl/display-mode .deps/core-template/src/fpga/apf/common.v \
  third_party/pocket/pdc_bridge_cmd.v tests/rtl/display_mode_tb.sv \
  > build/rtl/display-mode-build.log 2>&1
build/rtl/display-mode/Vdisplay_mode_tb
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pocket_sdram_tb \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-COMBDLY -Wno-MULTIDRIVEN --Mdir build/rtl/pocket-sdram \
  -CFLAGS '-std=c++20 -O2' \
  .deps/core-template/src/fpga/apf/common.v third_party/pocket/io_sdram.v \
  tests/rtl/pocket_sdram_tb.sv "$PWD/tests/rtl/pocket_sdram.cpp" \
  > build/rtl/pocket-sdram-build.log 2>&1
for access_ticks in 10 16 22; do build/rtl/pocket-sdram/Vpocket_sdram_tb "$access_ticks"; done
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pocket_sdram_tb "-GREFRESH_INTERVAL=10'd368" \
  -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-COMBDLY -Wno-MULTIDRIVEN --Mdir build/rtl/pocket-sdram-slow \
  -CFLAGS '-std=c++20 -O2' .deps/core-template/src/fpga/apf/common.v third_party/pocket/io_sdram.v \
  tests/rtl/pocket_sdram_tb.sv "$PWD/tests/rtl/pocket_sdram.cpp" > build/rtl/pocket-sdram-slow-build.log 2>&1
for access_ticks in 10 16 22; do build/rtl/pocket-sdram-slow/Vpocket_sdram_tb "$access_ticks" 80; done
verilator --cc --exe --build -j 8 -MAKEFLAGS 'OPT_FAST=-O3' --top-module pocket_psram_tb \
  +define+PDC_VERIFY_MMIO_CYCLES -Wno-WIDTH -Wno-REALCVT -Wno-UNUSEDSIGNAL --Mdir build/rtl/pocket-psram \
  -CFLAGS '-std=c++20 -O2' \
  third_party/pocket/psram.sv tests/rtl/pocket_psram_tb.sv "$PWD/tests/rtl/pocket_psram.cpp" \
  > build/rtl/pocket-psram-build.log 2>&1
build/rtl/pocket-psram/Vpocket_psram_tb
python3 tools/fpga/evidence.py end components
