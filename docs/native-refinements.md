# Display, sprite priority and compatibility follow-up

The recovery baseline is commit `8338dc7`, tag
`pocket-full-speed-2026-10-12`. Full-speed gameplay and correct audio were confirmed
on Pocket in both PDC30 Pink and PDC100. New source changes require fresh
simulation, four-corner timing, package verification and a Pocket test.

The previous frozen follow-up attempts, `build/native-combined-workspace` and
`build/native-mix-workspace`, stopped at their Oui-Oui smoke gates before FPGA
compilation. Neither completed a display installation: their install statuses
are blocked and `display_install` is null.
The working card core remains unchanged. The next candidate is
`build/native-prefetch-workspace`. Its runner
performs all validation gates, packages both display entries, verifies and
flushes installation only on the previously identified Pocket card, and shows
a window alert for completion, failure or a required card connection. It never
ejects the card. `diagnostic-build-status.json` and
`diagnostic-install-status.json` record the live outcome. A running or packaged
candidate is not a hardware-confirmed result.

This candidate compiles one bitstream for both the display and ROM-library
packages. The display package can install after its original-ROM validation
passes; the library additionally requires all eight per-ROM checks. Each
installation has its own status file and completion alert. A failed library
check does not invalidate an already verified display installation.

## Build timing follow-up

The first candidate, `build/native-display-workspace`, passed all component
checks and six 1,800-frame system runs, including stereo audio and video
comparisons. FPGA fitting and assembly completed, but setup timing failed at
the two slow device corners: −0.536 ns and −0.354 ns. Installation was blocked;
the hardware-confirmed card build was not replaced. The failed workspace and
reports are preserved for comparison. Rechecking its fitted netlist produced
the same failures.

The longest paths run through sound channel advancement and envelope routing.
The timing follow-up calculates the next channel independently of the late
advance decision. It also captures envelope route flags when committing the
amplitude, avoiding another multiplexed register read and comparison on the
next state transition. Neither change adds cycles or changes audio arithmetic,
system clocks or timing constraints. Simulation compares the captured flags
with the actual committed registers; explicit envelope boundary cases supplement
the existing random audio, register and interrupt comparisons.

Only a fresh placement and four-corner timing check can establish that these
changes resolve the physical timing failure. Passing functional simulation is
not evidence of timing closure. The CPU address path also had negative margin
in the failed placement and remains part of the required full timing check.

The second display fit improved the worst margins to −0.238 ns and −0.097 ns,
but still failed. Its remaining reported paths were ADPCM index adjustment,
ramp eligibility and interrupt/call stack address selection. The combined
candidate registers the ADPCM adjustment and clamp in existing decode stages,
captures ramp eligibility before routing, and selects the return-stack address
directly. Decode and CPU instruction cycle counts are unchanged; an inactive
ramp voice takes one additional internal clock. Differential CPU/audio checks
pass, but timing closure still requires the fresh physical fit.

## Library frame-budget diagnosis

The first library attempt passed PDC50 and TMNT through 1,800 frames. Oui-Oui
overflowed the real-time budget at frame 966, and Dora at frame 97. A 100-frame
Dora replay reproduced exactly the same failure. Per-frame measurements showed
substantial ROM fetch waits and no pixel-output stalls near that failure.

A trace of 195,629 graphics-cache requests produced 70,535 misses with the
original direct index. Folding upper address bits into the index with a
four-bit rotation produced 41,798 misses in the same trace. The cache retains
its full tags and existing capacity. Only the dedicated graphics cache enables
this mapping; CPU and shared caches keep their original indexing.

Dora then passed 180 frames with CPU, banking, pixels and stereo audio matching,
with maximum cycle backlog 39,374 instead of overflow at 131,071. Simulated
cache tests and Quartus memory-primitive tests cover alias separation, delayed
reads, atomic line fills and invalidation. Full-length game checks remain
mandatory. The first combined attempt waited for the Oui-Oui replay to pass
frame 966 before starting Quartus. That replay still overflowed at frame 966
with the new cache
mapping, so the combined attempt stopped before compilation. Targeted per-frame
profiling is investigating this separate workload; the Dora result does not
establish compatibility for Oui-Oui. The library checker records every game's outcome rather
than abandoning later games after the first failure.

Oui-Oui also overflowed at frame 966 with the Pocket output buffers removed.
The production-output profile showed no pixel stalls and only ordinary
1,024-word sprite DMA transfers near the failure. CPU cache conflicts contribute,
but replaying 1,490,338 captured line requests showed that a better index alone
would provide limited savings. The sound workload grows to several concurrent
voices in the failing scene; muted voices are rare.

The next candidate combines the per-voice pan multiplication and accumulation
in one internal clock, retaining the same signed widths, shifts and rounding.
It preserves all decoder, phase, envelope, register and interrupt updates.
A dense 16-voice regression matched samples but failed its 125-clock budget
at 135 clocks before the change; it now takes 119 clocks. The complete focused
sound differential still matches 251,851 stereo samples and 288,000
register/IRQ snapshots. This adds a multiply/accumulate timing path, so both
the original Oui-Oui replay and a fresh four-corner physical fit are required.
No performance or timing gate is relaxed.

The mixed-sound candidate still overflowed, now at frame 975. This improved the
failure point but did not resolve the sustained overload. Nothing was compiled
or installed. The next candidate starts an eligible next-opcode read on ALU
retirement, one clock before the old idle-fetch path. Only destinations that
preserve CS:PC use this path; MMIO fetches and other control-flow cases retain
their existing handling. Interrupt decisions still happen after peripherals
settle, and an interrupt can discard the speculative read.

A continuous CPU regression cost 884 clocks before this change and 778 after
it, against an 820-clock budget. The IRQ/FIQ variant checks architectural state,
modeled cycles, stack accesses and discarded reads. It also exposed a stale
`interrupt_entry` flag when prefetch decoding bypassed BOUNDARY; actual opcode
decoding now clears that flag. All 184,035 CPU differential cases pass with
randomized 0–7-clock replies, including early prefetch across operand forms.
Short production-output checks pass for Pink and PDC100 at 20 frames each, and
Dora at 110 frames with maximum modeled backlog 22,712. Those checks retain
CPU/banking/pixel/stereo comparisons and physical output-buffer assertions.
Full system replays and new physical timing remain mandatory.

The display package's compile/install gates now depend on its two original ROMs,
component checks, clock smoke test and four-corner timing. Extra-ROM failures
are recorded independently, so they cannot cancel a valid display update. The
library retains all eight complete readback/system checks; failed or stale
library evidence still blocks its packaging and installation.

The four VideoJet sets each passed an initial 20-frame Pocket-output comparison.
These short checks do not replace their required 1,800-frame validation or
hardware testing.

## Startup and reset picture

Scanout sends a valid 320×240 black raster while loading, checking the ROM or
holding the machine in reset. Video timing starts when the PLLs lock,
independently of machine readiness. PSRAM scanout starts only after a complete
frame has been written. This avoids displaying uninitialized memory without
clearing three full frame buffers over PSRAM.

The framebuffer fixture fills PSRAM with pink data, holds machine reset for a
complete picture, checks black output, checks four ordered game frames, then
resets during display and checks another complete black picture. It covers
producer phase offsets, burst backpressure and independent clocks. Physical
startup behaviour remains to be confirmed.

## Display filters

[Analogue documents 22 filters but permits 16 per core entry](https://www.analogue.co/developer/docs/openfpga/core-definition-files/video-json).
The package provides two entries sharing the same ROM assets and bitstream:

| Entry | Filters beyond Normal |
| --- | --- |
| PocketDreamConsoleFPGATest | CRT, reflective/color/backlit LCD, GBC/GBC+, GBA/SP101, GG/GG+, NGPC/NGPC+, TurboExpress, PC Engine LT, Lynx/Lynx+, Pinball Neon |
| PocketDreamConsoleFPGATestExtra | CRT, grayscale LCD, GB DMG, GBP, GBP Light, reflective/backlit LCD, NGP, Vacuum Fluorescent |

Release packages use the corresponding names without `Test`. These are Pocket
display filters, not extra PDC resolutions. The picture remains 320×240 with
the existing aspect ratio and cadence. Normal is implicit in Pocket's menu.
Filter availability depends on installed firmware.

Monochrome modes require [command `0x00B8`](https://www.analogue.co/developer/docs/openfpga/host-target-commands).
The bridge waits for the video domain to confirm the requested grayscale setting
before returning `0x444D`. Integer luminance `(R + 2G + B) / 4` produces equal
RGB channels without changing game pixels, CPU timing or sound. Tests check
both bridge byte orders, delayed acknowledgement, switching back to color and
actual grayscale scanout.

## Pot Pit shadow priority

User reproduction: PDC30 Pink, wait for startup, select category 3 **Venture**,
select game 4 **Pot Pit**, press Enter twice, then inspect the dog's shadow.

The inherited renderer drew ordinary sprites before blended sprites at each
depth. An earlier shadow could therefore cover a later body. MAME's
[SPG2xx renderer](https://github.com/mamedev/mame/blob/master/src/devices/machine/spg_renderer.cpp)
visits sprites in increasing sprite index within each depth. Both RTL and the
local reference now use that order. Group skipping remains, with four depth
maps instead of eight blend/depth maps.

Independent overlap assertions check a blended black shadow and opaque white
body in both orders, at every depth and opposite ends of sprite RAM. Expected
pixels are specified directly, independently of the modified reference. Random
pixel comparisons and sparse-line timing budgets remain required. This checks
the ordering correction in simulation; Pot Pit still needs physical comparison.

## Other ROM sets

Only **PDC30 Pink and PDC100** are hardware-tested today. The existing installed
core accepts only those two profiles. The separate library candidate adds
eight verified dump profiles; its FPGA timing and per-ROM validation must pass
before their launch entries are installed. Do not bypass integrity checks.

These eleven additional sets appear in
[MAME's PDC driver](https://github.com/mamedev/mame/blob/master/src/mame/tvgames/spg2xx_pdc.cpp).
They are candidates for new profiles, not promised compatible games.

| Set | Dump file | MiB | Required support |
| --- | --- | ---: | --- |
| PDC50 | `pdc50_7050.u3` | 16 | CRC profile; mirrored banking |
| Oui-Oui | `pdc_ouioui.u2` | 16 | CRC profile and validation |
| Teenage Mutant Ninja Turtles | `pdc_turtles.bin` | 8 | Smaller-ROM profile |
| Dora | `pdc_dora_5030.bin` | 8 | Smaller-ROM profile |
| VideoJet TV Games 1 | `29lv160.u2` | 2 | Smaller-ROM profile; different Right input |
| VideoJet TV Games 2 | `29lv320at.u2` | 4 | Smaller-ROM profile; different Right input |
| VideoJet TV Games 3 | `29lv320.u2` | 4 | Smaller-ROM profile; different Right input |
| VideoJet TV Games 4 | `29lv160.u2` | 2 | Smaller-ROM profile; different Right input |
| PDC200 | `pdc200.bin` | 128 | Larger-ROM addressing/banking |
| PDC40 Touch | `pdc_5060.bin` | 64 | Touchscreen/ADC/input profile |
| PDC150 Touch | `pdc5070.bin` | 128 | Larger-ROM banking and touchscreen profile |

The user supplied all eleven archives locally. Their exact member sizes and
SHA-1 identities were verified. Original dump copies are installed under
`Assets/pdc/dumps/<set>/` on the card; those files are archival copies, not launch
entries. The supplied archives are unchanged and ROM data remains Git-ignored.
PDC200, PDC40 Touch and PDC150 Touch are grouped under
`Assets/pdc/dumps/Unsupported/<set>/`, with hashes rechecked after the move.

`tools/rom_library.py` imports these sets reproducibly. PDC50 and Oui-Oui retain
their 16 MiB images. Dora and TMNT retain their 8 MiB images. VideoJet images
are zero-filled to the 8 MiB region used by MAME, rather than repeating data.
VideoJet Right uses GPIO bit 3 instead of bit 7 and its trigger inputs are absent.
The library loader accepts 8/16/64 MiB files, identifies a known startup-bank
CRC from the independent loading tap, and requires both fresh readback sweeps
to match it before starting the CPU. Unknown identities remain blocked.

The eight new profiles require full real-bank readback tests and independent
1,800-frame CPU, banking, video and stereo comparisons using the production
clock and Pocket output buffers. The package checks the ROM hashes, validation
fingerprints and timing evidence again before writing any launch entries.
It uses a separate `PocketDreamLibraryTest` entry. The failed library workspace
`build/native-rom-library-workspace` is preserved, as is the failed combined
workspace. A passing physical fit can produce both packages, but no new fit or
installation has completed.

PDC40 Touch still needs address-bit descrambling and tactile GPIO/ADC controls.
PDC150 Touch and PDC200 need data-bit descrambling and 128 MiB ROM access;
their images are not duplicates that can safely be truncated to 64 MiB.
PDC150 also needs tactile GPIO/ADC controls. These three have no launch entries
until those capabilities exist and are tested. Simply copying the dumps cannot
make the existing core run them.
Other Sunplus consoles do not become compatible simply by sharing the μnSP CPU.

## Save-state feasibility

Save states are possible but remain **unimplemented**. The bridge reports
`savestate_supported=0`; the package must not advertise working Memories yet.

Useful examples are
[budude2's GBC subsystem state bus](https://github.com/budude2/openfpga-GBC/blob/master/src/gb/gb.v)
and [mincer-ray's GBA Pocket integration](https://github.com/mincer-ray/openfpga-GBA/blob/master/src/fpga/core/core_top.sv).
They demonstrate coordinated pause, subsystem serialization and host transfer.
Their console-specific layouts cannot be reused directly for PDC.

A PDC implementation should:

1. Pause at a consistent instruction/frame boundary after pending bus and DMA
   transactions settle. Stop peripheral time as well as the CPU.
2. Serialize CPU state, RAM, bank/GPIO registers, graphics registers and memories,
   timer/IRQ/ADC/UART state, all sound voices and decoder/envelope history, plus
   scheduler/resampler phase.
3. Stage a versioned blob in unused external memory with ROM identity, length
   and checksum. Reject wrong-ROM or corrupt data before changing live state.
4. Restore while paused; invalidate ROM caches, rebuild graphics, reset host
   audio/display FIFOs coherently and resume only when complete.
5. Connect the standard Pocket start/load/query protocol to the serializer.
6. Verify deterministic replay of CPU registers, banking, frames and stereo
   audio in both ROMs, including repeated/cold loads, corrupt files, wrong
   ROM/version and interrupted transfers before enabling Memories.

The baseline uses 88% of logic and 94% of block RAM, so state storage and pause
logic need careful sizing and the same timing gates. This is a separate feature
project rather than a JSON setting for the graphics correction.
