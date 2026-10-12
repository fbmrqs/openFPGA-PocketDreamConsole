# Display, sprite priority and compatibility follow-up

The recovery baseline is commit `8338dc7`, tag
`pocket-full-speed-2026-10-12`. Full-speed gameplay and correct audio were confirmed
on Pocket in both PDC30 Pink and PDC100. New source changes require fresh
simulation, four-corner timing, package verification and a Pocket test.

The current frozen follow-up candidate is `build/native-display-timing-workspace`. Its runner
performs all validation gates, packages both display entries, verifies and
flushes installation only on the previously identified Pocket card, and shows
a window alert for completion, failure or a required card connection. It never
ejects the card. `diagnostic-build-status.json` and
`diagnostic-install-status.json` record the live outcome. A running or packaged
candidate is not a hardware-confirmed result.

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

Only **PDC30 Pink and PDC100** are accepted and hardware-tested today. The loader
checks their exact memory CRCs; another dump is intentionally stopped even if
it has the same size. Do not bypass the integrity check to try other ROMs.

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

No publisher-authorized download source was found. No additional commercial
ROMs have been downloaded. Owner-provided dumps or authorized download links
are needed; the user will supply their own dumps. Verify file identities and
test new profiles before packaging.
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
