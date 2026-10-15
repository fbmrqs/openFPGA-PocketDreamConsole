# Display, sprite priority and compatibility follow-up

The recovery baseline is commit `8338dc7`, tag
`pocket-full-speed-2026-10-12`. Full-speed gameplay and correct audio were confirmed
on Pocket in both PDC30 Pink and PDC100. New source changes require fresh
simulation, four-corner timing, package verification and a Pocket test.

The latest failed attempt, `build/native-prefetch-workspace`, stopped after Pink
exceeded its playback budget at frame 1,227. Oui-Oui still exceeded its budget
at frame 975. The fitted design independently failed slow-corner setup timing
at −0.747 ns and −0.596 ns. No display or library installation completed. Its
logs and fitted netlist are preserved; the working card core remains unchanged.

The next candidate is `build/native-qualified-workspace`, driven by the tracked
`tools/fpga/run-diagnostic.py`. Independent tests keep running after a failure,
with all outcomes saved. The expensive FPGA compile starts only after both
original ROMs complete their production-clock Pocket-output comparisons,
component correctness checks and clock smoke test. The card is never ejected.

Each installed ROM must have current readback, asset identity and full system
comparison evidence. The library package includes only individually verified
extra profiles and records excluded failures in its manifest. A failed extra
ROM does not cancel a validated display package or other verified extra ROMs.
Known obsolete launch entries for excluded ROMs are removed on update; raw
dumps and custom entries are preserved. Installation remains verified and
flushed, and each completed package has its own status file and window alert.

## Validation policy

CPU/banking/pixel/stereo correctness, startup readback, source/asset integrity,
production-clock playback in the two original ROMs, complete FPGA timing and
card write verification remain installation requirements. Hardware testing is
still required before claiming that a new package works on Pocket.

Synthetic CPU/SPU/PPU/IO speed targets are advisory measurements; a missed
benchmark target alone does not fail component verification. Completion
timeouts and data/interrupt mismatches still fail. Historical 196.608 MHz
system runs are optional diagnostics: the required 98.304 MHz runs cover the
actual timing configuration and production display/audio interfaces. The
library checker collects all eight outcomes, then packaging selects the
verified subset. Stale, incomplete, conflicting or corrupt results are rejected.

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
this mapping; CPU and shared caches keep their original indexing. The initial
candidate enabled it for every ROM, which later proved unsuitable for Pink.

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
The arithmetic and physical timing requirements are preserved. Synthetic
benchmark targets became advisory under the later validation policy above;
actual original-ROM playback requirements remain strict.

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
library checker runs all eight complete readback/system checks; packaging now
includes only the verified subset and excludes failures. Stale or incomplete
results still block packaging.

The four VideoJet sets each passed an initial 20-frame Pocket-output comparison.
These short checks do not replace their required 1,800-frame validation or
hardware testing.

## Pink cache regression and remaining timing paths

A captured Pink workload around frames 1,180–1,299 produced 186 graphics-cache
misses per frame with original indexing, versus 738 with the four-bit fold.
That increases graphics memory waits and is consistent with the later playback
overflow. The fold is now selected only for Dora's approved startup-bank CRC
`0xCEA549AD` and single-bank size. All other profiles retain original indexing.
The cache samples its mode during reset and clears tags before resuming. Tests
switch both ways, including an unchanged requested address across reset, and
check correct data, hits, collisions and fresh fills in simulation and actual
Quartus memory primitives. Pink's full replay must confirm the regression is
resolved; the trace result alone does not establish that.

The latest fit's longest paths include opcode-dependent CPU address selection,
sound register-index decoding and CPU response-to-operand selection. The next
candidate selects prepared operand addresses independently of late opcode
eligibility and predecodes sound field selection before its existing read stage.
Neither adds instruction cycles or changes audio arithmetic. All 184,035 CPU
cases pass, and both direct and lookahead sound reads match 251,851 stereo
samples and 288,000 register/IRQ snapshots. The new sound path checks its
selected word against the original field function on every verified clock.
These functional results do not establish physical timing closure.

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

The final package uses one `Local.PocketDreamConsole` entry with the sixteen
requested filters: Trinitron, Reflective Color LCD, GBC LCD+, Backlit Color LCD,
Original GBA LCD, SP 101, GG, GG+, NGPC+, TurboExpress, PC Engine LT, Lynx+,
GB DMG, GBP, Original NGP and Vacuum Fluorescent. Reflective LCD was listed
twice and is included once. Normal remains implicit in Pocket's menu.

[Analogue's mode table and limit](https://www.analogue.co/developer/docs/openfpga/core-definition-files/video-json)
allow these sixteen modes in a single entry. The picture remains 320×240
with the existing aspect ratio and cadence. The previous Main/Extra split is
retired. The release installer verifies off-card backups before replacing the
old software entry and removing the other PDC test entries. Shared ROMs and
unsupported archival dumps remain untouched.

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
It uses a separate `PocketDreamLibraryTest` entry. Failed workspaces are
preserved. A passing physical fit can produce both packages, but no new
installation has completed; the prefetch attempt completed fitting and failed
timing validation.

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

## Qualification resume: sound timing endpoints

The qualified candidate passed both original 1,800-frame production-output
runs, all component checks, and the PDC50, TMNT and VideoJet 1–4 runs.
Oui-Oui and Dora remain excluded after their independent failures.
Compilation stopped during the post-synthesis constraint audit because the
sound-read exclusions still named the previous local address registers.
The prepared read implementation uses `wave_select` and `pitch_select`
instead. Both selector groups must exist and remain timed for one clock;
the corrected audit verifies them without relaxing their timing.

The hardware-test workspace resumes from the existing mapped design. No HDL,
ROM, simulator or test source changes accompany this constraint correction.
Reused simulation evidence retains its original input hashes and provenance;
only the constraint hash is updated after checking that it is the sole change.
Physical fit, assembly and four-corner timing analysis are rerun. No new
binary or card installation has been confirmed yet.

## CPU and display timing correction

The resumed mapped design fitted and assembled successfully, but its slow
setup corners measured -0.282 ns and -0.334 ns. All four corners passed hold,
recovery, removal, SDRAM pin timing, asynchronous pin-delay budgets, Gray-code
net delay and pulse-width checks. The failing paths included incoming memory
read data through instruction operand-form selection, stack-loop completion
through the bus-address mux, and FIFO occupancy through display address enables.

The next candidate captures register and immediate operands independently,
selects PUSH/POP addresses independently of loop completion, and registers
scanout read/push space decisions with additional FIFO headroom. No modeled
CPU clocks or board memory constraints change. Focused checks passed 184,035
CPU differential cases with the same 778/845-clock continuous streams, complete
RGB/grayscale frames, delayed startup and burst backpressure, and the Pink
10-frame production-output comparison. Full game runs and physical timing
remain required before claiming closure.

The diagnostic runner installs only the combined library package in separate
entries, preserving the hardware-confirmed original core. It prevents duplicate
runners within a workspace. Repairable failures are saved for the authorized
hourly repair-and-retry follow-up; window alerts are reserved for verified
installation or a missing card.

## Graphics, memory-pin and mixer timing correction

The CPU/display candidate completed the original game runs and all six intended
extra-ROM runs; Oui-Oui and Dora still failed independently. The compiled slow
setup corners measured -0.362 ns and -0.356 ns. The previous CPU/scanout paths
were absent from the ten worst paths, while the worst remaining paths included
PSRAM control decode/address presentation, graphics line-word selection, and
incoming CPU cycles through sound sample eligibility into mixer reset enables.
Other audited timing categories passed.

The next candidate registers a one-hot graphics word selector with every tile
address update, retaining the same clock-by-clock buffer consumption. PSRAM
uses a one-hot cycle marker and prepares idle address outputs independently of
request eligibility while chip selects are inactive. Sound clears its mixer
on the existing first channel-dispatch clock rather than the eligibility clock.
None adds a modeled cycle or relaxes the board/pin timing requirements.

Focused graphics checks passed 682 scanlines/218,240 pixels in each of two
ROM-transfer modes, including both sprite blend orders at all depths. Sound
matched 251,851 stereo samples and 288,000 register/IRQ snapshots (8 clocks
for silent updates, 119 for dense updates). Both PSRAM dies passed 512
pin-level read/write cases with unchanged 15-clock reads and 14-clock writes.
Pink and PDC100 matched ten production-output frames with unchanged total
clock counts. Full game validation and physical timing closure remain pending.

## Verified library installation — 14 October 2026

Source commit `9c79abd312d71956419cd18726cd7a6a841b55c0` passed the complete
component checks, both original 1,800-frame Pocket output comparisons, and
PDC50, TMNT and VideoJet 1–4 readback/output comparisons. All four physical
timing corners passed; setup slacks in corner order were [0.213, 0.41, 4.006, 4.496] ns.
Oui-Oui and Dora remain excluded after independent playback failures.

`PocketDreamLibraryTest` and `PocketDreamLibraryTestExtra` were installed on
the pinned SD card. All 53 manifested files were independently rehashed and
writes flushed. The installed reversed bitstream SHA256 is
`f566337bce50ecbf2a4d2861980bc1cbd7ae0ddbf60a51ebad54bb8ce4f4ed6e`.
The original hardware-confirmed `PocketDreamConsoleFPGATest` core is unchanged.
No ejection was performed. The readiness window alert was already displayed.
Hardware testing of the new entries, black startup, display filters, sprite
priority, gameplay and sound is still pending; save states remain unimplemented.

## Device confirmation — 14 October 2026

Fabio confirmed black startup, corrected Pot Pit layering, all filters in both
entries, and full-speed gameplay in PDC30 Pink, PDC50, PDC100, TMNT and
VideoJet TV Games 1–4, with no observed slowdown or graphics issues. The
confirmed bitstream comes from source commit `9c79abd`; this is the preserved
pre-control-swap hardware milestone.

Remaining reports: A/B need swapping globally at the Pocket input boundary.
PDC30 Pink has distortion in the main musical voice, resembling incorrect
pitch bending, throughout Hair Salon (Puzzle), Bunny Pinky (Action),
Beeline 2 and Fun Match 2 (Table), including outside gameplay. Spoken voice
and sound effects seem fine. A specific audio reproduction and fix are pending.
Save states remain a later, unimplemented feature.

## Official entry and controls

The requested final identity is `Local.PocketDreamConsole`, version 0.2.1.
A/B are swapped once at the Pocket controller input boundary in `core_top.sv`;
all ROM profiles inherit it and no ROM bytes change. The controls description
also maps PDC A to Pocket B and PDC B to Pocket A. Input JSON describes the
read-only controls menu and does not change hardware input routing.

This candidate changes no CPU, graphics, sound or framebuffer simulation
source. Their passing full-game results can be reused only after an explicit
audit confirms the sole system-evidence difference is the unmodeled Pocket
top-level button wiring. Component/package policy checks and FPGA compilation
are rerun. Timing and installation must pass for the new binary before the
legacy card entries are retired. The musical lead distortion remains open;
no sound behavior is changed in this controls/packaging update.

## Musical lead reproduction routes

PDC30's categories form a 3×2 grid; Puzzle is selected after startup. Fabio's
routes are Puzzle → confirm → Down → confirm for Hair Salon; Right → confirm
→ Down five times → confirm for Bunny Pinky; Down → confirm → Down → confirm
for Beeline 2; and Down → confirm → Down twice → confirm for Fun Match 2.

`make audio-replay` builds a headless reference capture tool. Run
`build/pdc-audio-replay pdc_pink.u2 hair-salon output.wav output.csv`; the other
scene keys are `bunny-pinky`, `beeline-2` and `fun-match-2`. It records a
48 kHz stereo WAV and per-frame channel waveform/phase/target/pitch-control
state, without a window or screenshots. The scripted route waits until frame
560 for category movement, confirms at 620, selects list items starting at 700
with 20-frame spacing, and confirms at 840 and 1000. Each press lasts two frames.
It captures frames 820–1599. Actual scene identity and whether the reference
reproduces the reported pitch-bend distortion still need listening confirmation.
Reference clips and state traces are private, generated files under
`build/research/music-voice/`; they remain Git-ignored. No sound fix is claimed.

Fabio listened to the Hair Salon reference WAV and confirmed it has no wobble,
while the same scene on the Pocket does. During that scene, the diagnostic
display mostly reads `S=0x0b81ffff`, with intermittent changes. Accounting for
the bridge byte order, the register is `0xffff810b`: the CPU is running without
a fault, the audio underflow and modeled-cycle overflow flags are set, and the
reported processing backlog is saturated. Both flags latch until reset; this
reading alone cannot distinguish a startup event from continuing starvation.

A same-route full-system replay is running at the production 98.304 MHz clock,
with Pocket output clock crossings and ROM-transfer latency. It checks the
processing deadline, FIFO starvation and every resampled stereo pair against
the reference, as well as CPU, banking and video. Its private status and log
are `build/research/music-voice/replay-status.json` and `system-replay.log`.
That replay subsequently failed at frame 887 with a modeled-cycle budget
overflow, after the Hair Salon selection. CPU, banking, pixels and stereo
samples matched the reference up to the failure. Display backpressure accounted
for 17,898 blocked clocks over more than 1.45 billion elapsed clocks; this is
not yet enough evidence to identify the overloaded component. The WAV was not
written because the replay exited at the failure.

A private profiler removes output/reference checking while retaining the same
machine, production clock, ROM latency and button route. It counts scheduler,
peripheral and ROM waits, and saves a Verilator checkpoint at frame 870 for
short repeat measurements. Its active process, source hashes, log and restore
command are recorded under `profile` in `replay-status.json`. This reduced
reproduction must fail independently and its restored state must reproduce the
same failure before drawing performance conclusions. It supplies no release
validation evidence, and no sound fix is confirmed.

The official controls/filter candidate completed compilation but failed the two
slow setup corners at -0.274 ns and -0.188 ns. All other audited categories
passed. The ten worst 85°C paths ran from PSRAM0 cycle-marker bits through the
write/address payload enable mux to the data-pin registers. No candidate was
installed. The next timing correction prepares replicated, local payload
enables one clock ahead, retaining the existing pin-level address/data capture
cycles. Explicit cycle-marker equivalence assertions and 512 reads/writes on
both dies passed, including pin skew, setup, hold and pulse checks; read/write
costs remain 15/14 clocks. Full physical timing still must pass.

## Mixer throughput candidate

The reduced Hair Salon reproduction and its restored frame-870 checkpoint
both overflowed at frame 887, clock 1,453,267,855. At the final measured frame,
graphics cost about 747,950 clocks per frame; sound work rose from roughly
42,776 to 164,800 clocks when the three ADPCM music channels started. The
existing render workload left insufficient room for that increase.

Removing sprite rendering or ROM miss latency independently avoided overflow
through frame 920. Changing the graphics cache index did not help. An early
instruction-start probe initially violated interrupt-snapshot ordering; adding
the necessary snapshot check delayed overflow to frame 913 but did not solve
it. Neither cache nor instruction scheduling is changed in the candidate.

Sound now advances the next channel after capturing its mixing operands while
four valid-tagged arithmetic stages finish interpolation, amplitude, pan and
accumulation. Phase, amplitude and gains travel with their corresponding
sample. The channel loop drains all pending products before output scaling,
preserving channel order and the original truncation points. The dense mixing
budget regression failed at 119 clocks before this change and passes at 59
clocks, below its 65-clock budget. Both register-address configurations matched
251,851 stereo samples and 288,000 register/IRQ snapshots each; silent updates
remain eight clocks.

The production-output differential now accepts the four exact scene names as
its fifth argument. For example,
`bash tools/fpga/pocket-system-test.sh pdc_pink.u2 1800 hair-salon` checks the
actual scene against reference audio, CPU, video, backlog and output FIFOs.
Each scene gets separate source-bound evidence. Full scene/library checks,
physical timing and device listening confirmation remain required. The
controls/PSRAM build is independent and contains no mixer change.

The first full Hair Salon replay of the pipelined mixer still overflowed at
frame 896. All CPU, banking, video and stereo comparisons passed up to that
point; the faster mixer alone provides insufficient headroom. This failed
candidate remains preserved in `build/native-mixer-workspace` and was not
installed or used to start FPGA compilation.

The next candidate also lets the instruction boundary proceed on peripheral
completion instead of waiting for the scheduler's state transition. It requires
all peripheral engines to be idle, no pending line start, a non-retired CPU,
available real-time credit, and equality between the registered and current
IRQ/FIQ state. The interrupt equality preserves the settling clock that the
unrestricted prototype violated. Scheduler sequencing, modeled CPU cycles,
ROM latency and clock rates are retained. Both original ROMs matched ten frames
of CPU, banking, video and stereo execution at the production clock with the
interrupt-order assertions enabled. The full affected-scene checks and all
release qualification gates remain pending.

## Hair Salon deadline confirmation and next timing paths

Source `722ee41` completed the entire 1,800-frame Hair Salon production-output
comparison. CPU, banking, every pixel and every stereo pair matched reference;
no output FIFO faults or processing overflow occurred. Maximum modeled backlog
was 70,709 cycles (2.619 ms), below the 131,071-cycle limit and 256-sample audio
startup reserve. This confirms the original simulated failure is removed for
that scene. Physical audio still needs confirmation. The other original and
music-scene comparisons continue in the frozen scheduler workspace.

The controls-only PSRAM candidate failed slow setup at -0.494/-0.242 ns. The
previous PSRAM payload paths are absent from the worst paths. Remaining failures
include cached opcode bit 11 through fast-form classification into branch-state
enables, and a graphics request through the shared-bus grant/address mux.

The next combined source captures the four fast instruction classes with the
prefetched opcode, using live status flags for branch decisions as before.
Uncached and immediate prefetch completion still classify their current input
word directly. An assertion checks that the stored class matches its opcode.
The shared arbiter captures a new grant's address directly and holds its payload
throughout the transaction, leaving the RAM lookahead address and handshake
latency unchanged. A held-owner assertion checks the captured bus address.

Focused checks passed all 184,035 CPU cases, including idle/early prefetch and
interrupt handling, with unchanged 778/845-clock continuous streams. Both
4,096-instruction boot traces passed. Shared RAM/MMIO/ROM and owner-handoff
checks passed, retaining two-clock RAM and five-clock MMIO budgets. Both
originals also matched ten production-clock full-system frames. This source
requires fresh full scene/library validation and physical timing; existing
changed-source system receipts are not reused.

## Optional ROM success during combined validation

Source `722ee41` passed all four 1,800-frame music-scene comparisons and both
original ROM comparisons. Its fresh library run also passed Oui-Oui's complete
CRC readback and 1,800-frame production-output comparison; the remaining ROMs
are still running. Oui-Oui is therefore qualified for simulation on that source,
but remains without device confirmation and the latest source needs its own
check.

The temporary mixer collectors incorrectly required the passing ROM set to
equal exactly the six previously confirmed extra profiles, rejecting any
additional success. They also rejected the library supervisor's nonzero exit
even when its completed record contained only independently failed optional
ROMs. The collector-only recovery checks completed current-source records,
assets and every required scene/ROM receipt, then requires the six confirmed
profiles as a subset of successes. Additional qualified profiles are accepted;
independent optional failures remain excluded and logged. An incomplete record,
stale evidence or missing confirmed ROM still blocks compilation. The recovery
waits for the original collector to finish and resumes compilation/packaging
without changing HDL, receipts or replaying completed tests. Existing job
history is preserved. No new FPGA package or card installation is ready yet.

Both combined sources (`722ee41` and `71e5834`) subsequently passed both
original ROMs, all four music scenes and all eight extra profiles, including
Oui-Oui and Dora. Each full-system run checked 1,800 production-output frames
against its own frozen source. Neither additional profile has device
confirmation yet. The recovery collectors accepted these completed receipts
without replaying tests or changing their results.

The earlier combined source `722ee41` failed setup timing at -0.389/-0.154 ns
in the two slow corners; its fast corners passed at 4.181/4.489 ns. Hold,
recovery and removal passed in all four corners. The worst path runs from the
graphics memory request through active-grant selection and the lookahead
address mux into the captured shared-bus address. Other slow-corner violations
include SPU register reads into CPU state and SPU channel-register writes.
The failed workspace and reports remain preserved and no package was installed.

Source `71e5834`, which already captures the new bus grant directly, is now
compiling in `build/native-decode-workspace` after the earlier compiler exited.
Its physical timing remains pending; simulation success does not qualify a
bitstream or establish that the physical music distortion is resolved.

## Control-path timing repair

The `71e5834` compilation failed slow setup at -0.446/-0.326 ns; fast setup
passed at 3.717/4.024 ns. The earlier graphics grant path no longer appears
among the reported worst paths. The new report identifies the PSRAM output
enable through its state-case priority, the sound channel's binary eligibility
priority chain, uncached instruction classification after the RAM read mux,
and ROM response matching driving the entire line-capture enable.

The next candidate updates PSRAM OE in a separate marker-controlled process,
preserving pin cycles. Sound eligibility uses the existing one-hot channel
position, parallel prefix grants and an OR encoder instead of binary comparisons
feeding a priority chain. Instruction class ranges are expressed as their exact
bit patterns, with all 65,536 opcode classifications checked against the
previous predicates. ROM response acceptance is registered before writing the
wide line, adding one system clock to a cache miss while retaining its contents,
tag and acknowledgment association. The ROM-adapter regression now enforces the
128-clock production simulation budget under its delayed SDRAM fixture.

Focused PSRAM checks passed 512 transactions with unchanged 15/14-clock
read/write timing. CPU checks passed 184,035 cases and both 4,096-instruction
boot traces, retaining 778/845-clock streams. Both sound register-address modes
matched 251,851 stereo samples and 288,000 register/IRQ snapshots, retaining
59-clock dense and eight-clock silent updates. The ROM adapter passed complete
8/16/64 MiB loads, 1,536 delayed reads, reloads and corruption rejection; worst
miss latency was 105 clocks, below the 128-clock modeled budget. Full
qualification remains pending. The next frozen build will run physical
compilation alongside independent simulations, then require all current-source
receipts, four-corner timing and package validation before installation. This
ordering does not relax any release gate.

Quartus rejected the inline generate-loop `genvar` declaration in `05ee953`
during initial analysis. Source `8fca68a` moves that declaration outside the
loop, matching the syntax already used by the arbiter. A new frozen
`build/native-prefix-workspace` runs fresh compilation and qualification;
independent simulations in the rejected workspace remain running and are not
used as passing receipts for the new source. The declaration change passed
Verilator lint. Compiler acceptance and all release gates still need checking.

Source `8fca68a` completed compilation but failed slow setup at
-0.315/-0.276 ns; fast setup passed at 4.006/4.462 ns. Hold, recovery and
removal passed in all four corners. Its worst reported paths now run from CPU
instruction/register selection through the address-source mux into `bus_addr`.
A sound eligibility path into the channel counter missed by 0.022 ns. Both
original 1,800-frame runs and the Hair Salon/Bunny Pinky scene runs passed;
the remaining independent checks continue in the preserved failed workspace.

The next correction captures the PUSH address alongside the existing stack
increment/decrement lookahead and selects mutually exclusive CPU address sources
with masked OR terms. An assertion checks the prepared address against the
architectural stack register, including aliases. Sound captures the computed
next enabled channel and position, consuming them only when their saved
position/enabled snapshot still matches the current inputs. A changed snapshot
waits for the preparation clock instead of using a stale selection. Sample
arithmetic, pitch, modeled CPU cycles and clock rates are unchanged.

The focused CPU comparison passed 184,035 cases and both 4,096-instruction
boot traces, retaining 778/845-clock streams. Both originals matched ten
production-clock frames with CPU, video, audio and interrupt-order assertions.
Both sound register-address configurations matched all 251,851 samples and
288,000 snapshots each, with unchanged 59/8-clock dense/silent budgets.
Fresh full-system/library comparisons
and physical timing remain mandatory. The next collector defers queued tests
if its compiler fails while allowing already-active independent tests to finish;
deferred tests are never recorded as passing or used to qualify a package.

Source `67cc7a9` failed slow setup at -0.443/-0.127 ns. Its reported worst
paths run from framebuffer read pulses through the PSRAM state-case controls
into byte enables, ADV and DQ output enable. The earlier CPU address path is
absent from those worst paths. Fast setup and all hold/recovery/removal checks
passed. No failed bitstream was packaged or installed.

That source also failed the full Hair Salon production-output comparison at
frame 1,025 with modeled-cycle overflow and display backlog. Every CPU, banking,
pixel and stereo comparison matched until the failure. The registered sound
eligibility introduced extra waiting clocks, despite unchanged arithmetic and
passing unit budgets. Bunny Pinky and Beeline 2 passed; the remaining independent
run continues. The added eligibility wait is removed in the next candidate,
restoring the earlier parallel selector's cycle behavior. Its one-hot position
register gets a local fanout limit instead of a new processing stage. The CPU
stack/address correction remains, with no added CPU clock.

PSRAM ADV, byte-enable and DQ-enable updates now use independent marker-controlled
processes, preserving the exact idle/request/write/read events and avoiding the
unrelated case priority. Focused pin checks passed all 512 transactions with
unchanged 15/14-clock read/write timing. Both sound address modes matched
251,851 stereo samples and 288,000 register/IRQ snapshots each with unchanged
59/8-clock budgets; both originals matched ten production frames after removing
the sound wait. The next frozen collector runs Hair Salon
first alongside Pink, then the other required scenes and profiles. It defers
queued tests on any required failure while retaining active independent checks.
The frame-1,025 failure remains the full-system regression gate; unit checks do
not establish that it is removed, and full-device timing remains mandatory.

Source `3d287a2` completed Hair Salon's full 1,800-frame production-output
regression: 174,005,112 instructions and 2,946,384,587 FPGA clocks matched CPU,
banking, pixels and stereo reference output without FIFO/deadline failure.
Maximum modeled backlog returned to 70,709 cycles, matching the earlier passing
scene. Pink's original full run also passed. This confirms the frame-1,025
simulation regression is removed after restoring selector latency; physical
audio, remaining scene/library qualification and device timing are still pending.

The `3d287a2` physical compilation passed all four required timing corners.
Setup slacks were 0.001, 0.005, 4.184 and 4.495 ns; hold, recovery and removal
also passed in every corner. The frozen-source FPGA receipt was independently
required and its timing record and bitstream hashes matched
`b7bff553bf58d7c615f8aa4c18fe6d0905c4c257d72debcb0a31657968eaa361`.
The reported slow-corner margins are small but positive under the existing
constraints; no constraints or qualification thresholds were relaxed.
PDC100 and Bunny Pinky also completed their full current-source comparisons.
Beeline 2, Fun Match 2 and fresh extra-ROM validation remain before packaging.
Nothing new is installed, and physical audio/control confirmation is pending.
