# Building and validation

## Repository map

| Path | Purpose |
| --- | --- |
| `rtl/` | μnSP CPU, memory/bus, graphics, sound, I/O, scheduling and resampling |
| `rtl/pocket/` | Pocket bridge, clock/reset, loader, framebuffer, audio and debug support |
| `src/`, `third_party/veesem/` | Software reference and historical software frontend |
| `tests/rtl/` | Component, pin-level, CPU/reference and full production-output fixtures |
| `tools/fpga/` | Build, simulation, timing and source-bound evidence tools |
| `tools/release.py`, `release/` | Public ROM-free packaging and release identity |
| `tools/import_roms.py` | Local dump verification and preparation |
| `docs/` | Maintained guides plus explicitly historical development records |
| `.deps/`, `build/`, `dist/` | Ignored dependencies, private evidence and generated output |

The system runs at 98.304 MHz with 49.152 MHz SDRAM. A hardware μnSP CPU shares
memory with graphics, sound and DMA. Graphics render 320 × 240 into a PSRAM
framebuffer; ordered triple buffering decouples production from display. The sound
engine mixes sixteen PCM/ADPCM channels and resamples its output to 48 kHz stereo.
The reference model is a development oracle; it is not running on the Pocket.

## Dependencies

Host tooling needs Python **3.11+**, Git, make and a C++20 compiler. Simulation
also needs Verilator, Icarus Verilog and Quartus's `altera_mf.v` simulation library.
FPGA compilation needs **Quartus Prime Lite 25.1 with Cyclone V support**. Vendor
tools and simulation libraries are not redistributed.

```sh
python3 tools/bootstrap.py --native
# Copy <quartus>/eda/sim_lib/altera_mf.v to .deps/quartus-sim/altera_mf.v
make check-release
make headless
```

The native bootstrap fetches the exact Analogue template revision
`da3a021b1eaf742604d86d8dc9b33a6666263e6a`. The vendored memory-controller
provenance is recorded in `third_party/pocket/README.md`; the software reference
is pinned in `third_party/veesem/README.md`. The historical RISC-V target instead
uses `python3 tools/bootstrap.py` and `make software`; it is not required here.

## Native checks and compilation

The full suite needs private PDC30 Pink and PDC100 dumps at `pdc_pink.u2` and
`pdc100.bin`, with the exact hashes in [roms.md](roms.md). These files remain
ignored. Additional profile validation consumes the local prepared ROM library.

```sh
make rtl-test
make rtl-clock-test
make rtl-pocket-test
make fpga
```

`make rtl-test` covers CPU semantics, boot traces, sound, graphics, bus/RAM,
resampling and physical SDRAM/PSRAM transactions. `rtl-clock-test` exercises
production-clock startup; `rtl-pocket-test` compares both original ROMs over
1,800 frames, including CPU state, every pixel and stereo output through the
production FIFO/serializer interfaces. Lost cycle credit and FIFO faults fail
qualification. `tools/fpga/library-test.py` validates extra profiles separately;
failed optional profiles must be excluded rather than advertised as working.

The four sound regression routes and corresponding 1,800-frame commands are
retained in [native-refinements.md](native-refinements.md). They cover Hair Salon,
Bunny Pinky, Beeline 2 and Fun Match 2. They are required for this release.

With native `quartus_sh` on PATH, `make fpga` runs the compiler directly. The
existing Docker/QEMU paths are optional alternatives, not requirements for x86
hosts. Their installation helpers live under `tools/fpga/`; do not redistribute
the vendor installer or container contents. Emulating the x86 compiler on Apple
Silicon can be substantially slower than a native x86 host.

## Qualification discipline

`tools/fpga/evidence.py` records input hashes and rejects stale receipts.
Changed CPU, SPU, graphics, scheduling or memory logic requires fresh relevant
system comparisons. Passing simulation does not establish physical timing;
passing synthesis does not establish functional correctness.

Four-corner setup, hold, recovery and removal checks must pass without weakening
constraints. Keep failed workspaces and their exact reports. Test a replacement
package on a device before promoting its hardware compatibility claims.

The hardware-confirmed RTL source is `3d287a2`; the release repackages its exact
binary. Its four setup margins are 0.001, 0.005, 4.184 and 4.495 ns. All other
required timing checks passed. The small slow-corner margins are disclosed;
qualification is tied to that exact build, not extrapolated to new source.

Use [the release procedure](releasing.md) for public artifacts. The historical
`tools/package.py` and `tools/package_native.py` assemble **private ROM-inclusive**
test packages and must never be used as public release assets.
