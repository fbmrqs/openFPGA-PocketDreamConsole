# Vendored Sunplus emulator

Source: [sp1187/veesem](https://github.com/sp1187/veesem/tree/42fb8f07e7418f16ccfb7364127aef2217dda641), revision `42fb8f07e7418f16ccfb7364127aef2217dda641`.
Copyright © 2024–2026 Simon Eriksson. ISC license, retained in `LICENSE`.
Only `src/core/common.h` and `src/core/spg200/` are included.

Local changes:

- Rename `.cc` to `.cpp` for the openfpgaOS build rules.
- Replace C++ standard library containers with fixed storage and views in `core/portable.h`; the Pocket SDK provides musl and a minimal C++ ABI but no libstdc++.
- Use C stdio for fatal diagnostics and register dumps; log the unknown ALU opcode before aborting.
- Expose the CPU's program counter to the PDC board adapter.
- Add optional host-only CPU state and bus observation under `PDC_CPU_TRACE`, used by `tools/trace.cpp` to record a software reference for FPGA development.
- Forward unmasked port A buffer writes to the PDC adapter, matching MAME's workaround for bank switching from internal RAM. Normal GPIO direction/mask handling is retained for other operations.
- Correct the audio buffer wrap condition to prevent an out-of-bounds write.
- Handle common RAM and ROM reads before dispatching peripheral register reads, preserving address masking and external-memory decoding.

The core runs with `-fno-strict-aliasing`, as its upstream register and pixel implementations rely on union overlays.
