# Pocket Dream Console on Analogue Pocket

A native FPGA implementation of the μnSP CPU, SPG200 graphics, sound and board
peripherals for PDC30 Pink and PDC100. On 12 October 2026, Pocket gameplay was
confirmed at **full speed with clean audio**, following successful simulation,
FPGA timing, verified installation and physical testing.

The tested Pocket entry is **PocketDreamConsoleFPGATest**, version
`0.1.0-sprite-groups`. The main RTL and build tools match that installed build.
See the [native FPGA guide](docs/native-fpga.md) for architecture, prerequisites,
verification and build commands, and the [baseline record](docs/native-full-speed-baseline.json)
for exact hashes and recovery paths. Save states, sleep/resume and exhaustive
compatibility testing remain pending.

The working local package is preserved in
`build/native-mmio-workspace/dist/pocket-dc-native-experimental`.
It contains private ROM copies and is excluded from Git, together with dumps,
generated binaries, logs and dependency checkouts. Public release and pupdate
integration are still pending.

## Earlier software emulator

The sections below describe the original experimental software emulator running
on the openfpgaOS RISC-V FPGA runtime. This is separate from the native FPGA core
confirmed above; its historical speed results do not describe the native build.

Version 0.1.2 is confirmed to boot on Pocket firmware 2.7, with very slow emulation reported on the device. Matching the core metadata's author and shortname to its `Local.PocketDreamConsole` folder resolved the setup failure. The overlong control label corrected in 0.1.1 was not the cause.

Version 0.1.3 enables link-time optimization and fast RAM/ROM read paths. In three alternating desktop PDC30 benchmarks of 1,800 frames, median CPU time fell from 3.527 seconds (O3) to 2.587 seconds (O3 with these optimizations), about 27% less CPU time. This is a desktop comparison, not a Pocket speed measurement. Both ROMs preserve the prior headless frame hashes, program counters, bank transitions and audio activity over 1,800 frames with simulated button presses. The optimized build still needs a Pocket test; real-time performance, video appearance, audio quality and the full game libraries remain unverified.

## Install the prepared build

1. Use Pocket firmware **2.2 or newer**, as required by the bundled runtime.
2. Unzip `dist/pocket-dc-experimental.zip`.
3. Merge its `Cores`, `Assets`, and `Platforms` folders into the root of a FAT32/exFAT microSD card. Keep each folder's contents when merging.
4. Insert the card, then open **openFPGA → Pocket Dream Console**.
5. Select **PDC100** or **PDC30 Pink** and run it. ROM bank loading can delay startup and game changes.

The ZIP contains copies of the local ROMs for personal testing. The original dumps stay untouched. Use the existing Analogue button to open the Pocket menu and exit.

| Pocket control | PDC control |
| --- | --- |
| D-pad | D-pad |
| A / B | A / B |
| L / R | Left / right triggers |
| Start | Pause |
| Hold Select, press Start | Reset to the PDC boot menu |

Save states and sleep/resume are not implemented.

## Rebuild

Python 3, make, a C++20 host compiler, Git, and a RISC-V bare-metal GCC toolchain with `rv32imafc/ilp32f` support are required. On macOS, the tested compiler is Homebrew `riscv64-elf-gcc` 16.2.0.

```sh
python3 tools/bootstrap.py
HOMEBREW_NO_INSTALL_CLEANUP=1 brew install riscv64-elf-gcc
make -j4
make check
make package
```

The build uses the host cross-compiler (`USE_SDK_CONTAINER=0`). The pinned SDK supplies matching prebuilt FPGA/runtime binaries and musl. No Quartus installation or FPGA synthesis is required for this route. `make headless` builds the independent desktop harness without linking the SDK runtime.

```sh
./build/pdc-headless pdc_pink.u2 1800
./build/pdc-headless pdc100.bin 1800
```

The harness does not open a window or capture screenshots. It reports program counters, frame hashes, bank loads, and non-silent audio samples. After boot it sends A presses and movement to exercise the game menu. These checks establish execution and activity, not complete emulation accuracy.

## Trace the CPU for native FPGA development

```sh
make trace
mkdir -p build/traces
./build/pdc-trace pdc_pink.u2 1800 build/traces/pink
./build/pdc-trace pdc100.bin 1800 build/traces/pdc100
```

Each command creates a JSONL execution trace and a JSON summary. Output paths must be new. The trace records CPU registers, status flags, shift buffers, interrupt state, modeled cycles, CPU bus reads/writes, and active ROM banks. It retains the first 4,096 CPU steps, the first occurrence of every executed opcode, every bank change, and the first 16 interrupt entries. The summary counts opcodes and CPU writes to the memory-mapped peripheral region across the full run. The scripted inputs match the headless harness.

Tracing is compiled only into the host tool with `PDC_CPU_TRACE`; it is absent from the Pocket build. These observations provide a software reference for the native hardware CPU. They do not measure the physical chip's timing, include peripheral-issued memory requests, or establish complete instruction and game coverage.

REA 6.2.0 process capture was used to record both 1,800-frame trace runs. The evidence bundle and sampled traces are in `build/rea-pdc/`. REA's Hopper route rejected the headerless PDC ROM format, so no Hopper disassembly or decompilation of the ROMs was performed. The [existing Ghidra μnSP module](https://github.com/SamuelWAnderson45/ghidra-unSP) is a possible analysis aid, but its documented instruction and addressing limitations require checking results against the emulator.

## ROMs and architecture

| Dump | Identity | Source SHA-1 | Active ROM |
| --- | --- | --- | --- |
| `pdc100.bin` | PDC100, Conny / Anncia, US | `cfb4be7877ec263d24063a004c56985db5c0f4e2` | First 64 MiB of the 128 MiB dump |
| `pdc_pink.u2` | PDC30 Pink, Conny / VideoJet, France | `5b423d589358dd53a2e5765bcb94da2d44200e56` | Entire 16 MiB dump |

These identities, the ignored PDC100 upper half, active-high GPIO controls, 8 MiB ROM banks, reset from the final bank, and port A banking workaround follow [MAME's PDC driver](https://github.com/mamedev/mame/blob/master/src/mame/tvgames/spg2xx_pdc.cpp). The source words are little-endian; MAME's `ROM_LOAD16_WORD_SWAP` converts them for its big-endian CPU bus.

`src/pdc.*` adapts the board to the vendored [veesem Sunplus emulator](https://github.com/sp1187/veesem). Only one 8 MiB bank is resident, so PDC100 does not consume all of Pocket's 64 MiB SDRAM. Bank changes synchronously load from the data file. `src/main.cpp` presents RGB555 frames and maps Pocket inputs; `src/audio.h` integrates the emulator's 281,250 Hz unsigned stereo output into 48 kHz signed stereo. `tools/package.py` verifies the original ROM hashes, ELF architecture, pinned SDK, and matching runtime manifest before assembling the SD tree.

The SDK is pinned to [openfpgaSDK `a408ddc`](https://github.com/openfpgaOS/openfpgaSDK/tree/a408ddc12aed0dfaa4aa22c06af82f829db77126); its runtime manifest identifies [openfpgaCore `618a3eb`](https://github.com/openfpgaOS/openfpgaCore/tree/618a3eb). Upstream emulator notices and local modifications are recorded in `third_party/veesem/`. Runtime notices and licensing references are retained in the package's `Licenses/PocketDreamConsole` folder.

The [Analogue development SDK](https://www.analogue.co/developer/docs/openfpga/getting-started) provides the framework for the native implementation in `rtl/`. See [native FPGA architecture, validation and card layout](docs/native-fpga.md). The software build described above reuses the existing FPGA runtime.
