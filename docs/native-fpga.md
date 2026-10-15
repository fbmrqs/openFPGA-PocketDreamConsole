> Historical development record. For current installation and compatibility, see
> [the README](../README.md); for maintained build instructions, see
> [building.md](building.md). Dated failures and pending statuses below describe
> their recorded revisions and are superseded by later confirmations.

# Native FPGA hardware milestone — 12 October 2026

Fabio confirms that the installed native core runs games at full speed with
perfect sound. Earlier testing confirmed correct graphics, controls and gameplay
in PDC30 Pink and PDC100. This is a hardware-confirmed gameplay milestone;
exhaustive title coverage, long-duration stability, save states and sleep/resume
remain outside the confirmed scope.

The confirmed RTL, reference sources, tests and FPGA tools are frozen in
`build/native-mmio-workspace`. The current source includes the subsequent
[display and sprite refinements](native-refinements.md), which require fresh
validation. Preserve the frozen workspace and its
private package as the recovery baseline. The original slower playable builds
remain preserved separately. [The baseline record](native-full-speed-baseline.json)
contains bitstream hashes, validation receipt hashes, clocks and timing results.

- Quartus fit, assembly and strict timing passed all four corners. Setup margins
  are 0.006, 0.035, 3.984 and 4.352 ns; the smallest margin is narrow.
- Both ROMs passed 1,800-frame unpaced, paced and production-output runs, checking
  CPU state, every rendered pixel and stereo output. Component and clock smoke
  checks also passed; no output FIFO or modeled-time overflow occurred.
- The package was installed, verified and flushed without ejecting the card.
- RBF SHA-256: `2f85fa622cb95b76e9c131f9ed0e121544c291da41c55982831cf4b156ea7158`.
- Pocket entry: **PocketDreamConsoleFPGATest**, version `0.1.0-sprite-groups`.

Current build and verification entry points:

```sh
make rtl-test
make rtl-system-test
make rtl-clock-test
make rtl-pocket-test
PDC_QUARTUS_VOLUME=pdc-quartus-25.1 PDC_QUARTUS_EMULATOR=qemu make fpga
python3 tools/package_native.py --experimental
```

These commands require the pinned SDK/framework, Quartus simulation library,
Verilator, Icarus Verilog, a C++20 compiler, Python 3 and the local ROM dumps.
The native package currently includes private ROM copies. Public release and
pupdate integration still require ROM-free packaging, release identity/metadata
and a license/attribution review. No ROMs or compiled packages are tracked in Git.

The sections below retain the development history. Provisional candidate results
are historical and are superseded by this confirmed baseline.

## First playable Pocket milestone — 12 October 2026

Physical testing of `build/native-sdram-safe-workspace` confirms PDC30 Pink and PDC100
reach splash, menu and gameplay with working controls and recognizable
audio. Pink’s recorded diagnostics show both startup-bank CRC passes succeed
(`M=7`), L/W/A/B all equal `0x0C1DC0F3`, and F/O remain zero. Speed is below normal and music is noisy.
The user reports correct graphics/actions in all games tried in both ROMs.
Long-duration and systematic compatibility coverage remain pending.

Preserved baseline: `build/debug/first-playable-baseline.json`, including the
exact bitstream hash and package location. Future changes use separate
workspaces. This is a playable milestone, not a full compatibility release.

## Rendering/audio refinement tested — 12 October 2026

`build/native-performance-workspace` preserves the working memory clocks and
adds empty sprite-pass skipping plus last-sample hold during audio starvation.
Its verified package was installed and flushed. The user reports a modest
speed improvement and more intelligible music, still slowed with gameplay.
The bitstream SHA-256 is
`0ea24e6ba142b4e1f13c316b59ab6a303c388bea2b881d421e0c3e461a3cc8ac`.
This is the current hardware-tested baseline; preserve its sources and package.

## Real-time candidate in validation — 12 October 2026

`build/native-realtime-workspace` shortens ROM cache hits and shared-bus access,
removes an idle step from quiet timer updates, gives graphics its own ROM cache,
and consumes graphics words on acknowledgment. It retains the proven 98.304 MHz
system clock and 49.152 MHz SDRAM settings. No higher board clock is being used.

A new integration test connects the production audio serializer and framebuffer
to the system at the requested clock ratios, with conservative PSRAM transaction
times. It checks CPU state, every rendered pixel and generated stereo sample
against the reference, and rejects audio starvation, display faults or an
overflowing real-time cycle backlog. The installed refinement fails this test
at frame 12; both ROMs in the new candidate have passed that point. The candidate later
fails the pacing check at Pink frame 490 and PDC100 frame 499. Its FPGA build
was stopped, and it was not installed.
These scripted runs are not exhaustive coverage of every game or proof of
physical audio fidelity. Hardware confirmation is required after installation.

The next workspace, `build/native-throughput-workspace`, adds graphics ROM block
reuse and prepares the next word while drawing. A busy scene snapshot at frame
800 falls from 830,912 to 650,840 renderer clocks with all pixels matching.
This was superseded without an FPGA build or installation. CPU indirect addressing
and a one-clock most-recent ROM-block buffer were then added in
`build/native-streaming-workspace`. Its component checks passed, but the production
output test failed at Pink frame 491. A trace recorded the framebuffer writer
waiting for a pending swap, with a full 1,023-pixel FIFO and 120,050 blocked system
clocks. Raw rendering speed alone therefore did not establish real-time operation.

`build/native-voice-workspace` retains those CPU/cache/renderer changes and adds:

- Ordered triple buffering in external PSRAM, with alternating pixels on the two
  dies and paired parallel reads. It never discards a completed frame or writes
  into the displayed frame. A full queue applies backpressure.
- A sound-channel selector that skips disabled voices while preserving the order
  and complete processing of enabled voices.

The delayed-frame regression fails on the old display and passes on the new one.
Six producer phases and an unrestricted burst producer preserve every displayed
pixel and frame in order without underflow. Sound tests match 223,868 stereo
samples and 256,000 register/IRQ snapshots; a silent update costs 8 clocks instead
of 23. The old frame 491/499 failures are cleared, but the full-system tests
still exceed the real-time backlog at Pink frame 850 and PDC100 frame 836.
No FPGA compilation or installation was performed. Neither change has been
tested on the physical Pocket. All PLL and memory timing settings remain
at the playable baseline values.

`build/native-response-workspace` adds direct forwarding of qualified internal
bus replies to their held owner. External ROM arbitration keeps its registered
reply. RAM access falls from three clocks to two in the system bus regression;
RAM/MMIO readback and owner handoff remain correct, and both ROMs match ten
startup frames at 98.304 MHz. Pink cleared frame 850, but PDC100 exceeded timing credit at frame 857 while
the display was not blocking. No FPGA build or installation was performed.

`build/native-pacing-workspace` retains the measured throughput improvements
and fixes early loss of timing credit during recoverable bursts. The prior
65,535-cycle cap discards virtual time after 2.427 ms. The new 131,071-cycle cap
allows 4.854 ms, below the audio serializer's 256-pair startup reserve of
5.333 ms. A short regression loses time at the old cap and recovers a 3 ms
burst exactly at the new cap; sustained overload still sets a sticky flag.
Status bit 15 records actual pacing overflow; the upper 16-bit backlog readout
still saturates for display. Continuous-output qualification now rejects actual
lost-time overflow, and retains strict audio starvation/overflow, display and
reference-sample checks. Those tests are running; the larger allowance alone
is not proof of full-speed gameplay. No new candidate has been installed.

The detached runner records build/install status in each build workspace.
Installation requires current-source simulation evidence, FPGA timing checks,
package validation, verified SD copies and flushed writes. One macOS window
alert reports readiness, a missing card or failure. The card is not ejected.

# Native Pocket Dream Console FPGA core

The native SystemVerilog implementation recreates the μnSP CPU, SPG200 graphics, sound and board peripherals in Pocket's FPGA. It does not run the C++ emulator on a RISC-V processor. The existing software core remains available separately.

Native RTL and its simulation tests are implemented. Standard packaging requires a successful Cyclone V fit, timing closure and current simulation evidence. Experimental packaging uses a separate diagnostic core identity and requires the same successful timing and current-source verification gates. The installed baseline has now passed physical gameplay testing as recorded above.

## Architecture

`rtl/pdc_system.sv` coordinates the μnSP CPU, internal RAM, three ROM caches,
graphics, 16-channel PCM/ADPCM sound, DMA, GPIO, timers and interrupts. CPU and
graphics ROM hits bypass the shared RAM/MMIO bus. The CPU cache is 32 KiB,
graphics cache 128 KiB and shared sound/DMA cache 16 KiB; each tags the ROM bank.
Cache misses share the SDRAM interface. Internal RAM reads use the arbitration
lookahead for two-clock responses. Graphics/sound MMIO uses registered addresses
and a settling clock; reads take at most five clocks. Payloads stay stable until
acknowledgment, and ignored ROM writes do not alias peripheral registers.

The CPU and peripheral controllers use one-hot states and staged arithmetic.
Instruction timing follows the vendored reference, with a 27 MHz modeled cycle
budget on the requested 98.304 MHz system clock. The requested audio master is
12.288 MHz (8:1 system ratio), SDRAM is 49.152 MHz, and stereo output is 48 kHz.
A maximum 131,071-cycle pacing allowance covers short rendering bursts within
the audio startup reserve; sustained dropped time latches a diagnostic fault.
Safe prefetch overlaps peripheral work while preserving interrupt boundaries,
register aliases and the ordered architectural updates. Unsupported instructions
latch the fault PC and opcode. Component and system tests compare CPU registers,
banking, every rendered pixel and stereo samples with the software reference.

The PPU captures palette, scroll and scanline RAM outputs directly on the clock edge, preserving one-clock reads while allowing the unused collision behavior to map without bypass logic. It stores this data in dedicated FPGA RAM and renders two background layers and 256 sprites into 320×240 RGB555 scanlines, with indexed/bitmap graphics, palette, flips, scrolling, compression and blending as modeled by the reference. Tile addresses, clipping distance/word counts, split clipping-address carries and pixel blending are staged to keep arithmetic out of long combinational paths. Sound-channel eligibility is combined per channel before selection, and the channel selector uses bounded register fanout as described in the [Quartus register duplication guidance](https://www.intel.com/content/www/us/en/docs/programmable/683641/22-3/manual-register-duplication.html). The SPU implements 16 PCM/ADPCM channels, pitch, interpolation, envelopes, ramping, pan, volume and interrupt behavior. Its envelope, pitch and ramp divider tests use bounded lookup logic captured ahead of channel processing. Wave addresses, pitch operands and envelope-read addresses are prepared before their consuming stages. The scheduler serializes SPU register writes and peripheral advancement; simulation rejects writes while the SPU is busy. PCM writes, ADPCM decoding, wave-address advancement, envelope updates and timer ticks complete in separate stages before the CPU resumes. Timer, ADC, UART and watchdog countdown arithmetic splits low and high words across stages while preserving their full counter ranges. Timer expiry is captured before subtraction using its 32768-cycle step granularity, including signed wrap. Watchdog expiry is captured alongside its countdown inputs. GPIO writes decode each port explicitly and finish banking in a separate commit phase. Port-A buffer writes preserve the reference’s raw-value bank decision followed by its masked-output decision; banking remains restricted to code in internal RAM. CPU multiplication, output gain and resampling use private DSP input and output registers. Generic CPU shifts remain outside the multiplier inputs. Resampler DSP outputs pass through a separate fabric register stage before summation. Sound countdown expiry and reload split low-byte borrow/carry from the upper word, including signed wrap, without narrowing the counters. Envelope repeat counts are captured before decrement and writeback. A local watchdog-enable register separates control readback from the countdown write enable. FIFO occupancy is registered in each local clock domain with conservative delay for remote movement; full and empty still use synchronized Gray pointers. Pipelined integer integration converts its 281,250 Hz stereo stream to 48 kHz.

`rtl/pocket/core_top.sv` connects the machine to the official Analogue Platform Framework. Its loader accepts a complete 16 MiB or 64 MiB little-endian ROM, validates sequential addresses and counts, then starts from the final 8 MiB bank. The SDRAM adapter transfers a complete cache line across clock domains once. Sixteen RAM banks let the ROM cache commit that reply in one clock. Tag and word reads use two registered stages, followed by a registered hit decision and two stages of four-way word selection. The timing fixture allows 128 system clocks per miss; a controller burst takes at most 42 memory clocks in the pin-level fixture, and the adapter fixture measures 104 system clocks including clock-domain crossings. A registered reset combines the host reset and Select+Start inputs before distribution. A soft reset preserves the loaded ROM.

The display uses three ordered frame buffers, with alternating pixels distributed across both Pocket PSRAM chips. Complete frames queue in order and the oldest queued frame becomes visible at vertical blanking. Backpressure applies when no free buffer remains; frames are neither dropped nor written over while displayed. A scanout FIFO feeds Pocket video. An independent sample FIFO and I²S serializer provide stereo sound. Clock crossings use Gray pointer FIFOs or synchronized control signals, with local reset release. Interpolation captures its channel operands before multiplication, and ADPCM error accumulation uses separate stages. Sprite prefetch advances independently of culling so skipped sprites still take one clock. Sprite indices and renderer control states commit together to preserve the prefetch address across clock edges; a sparse overlapping-sprite regression checks this ordering.

The memory controllers are vendored with revision and license information in `third_party/pocket/README.md`. The PSRAM writer holds data for two clocks after releasing the write strobe. Counted setup, access and hold intervals cover a 6 ns allowance for FPGA pin delays. Since this interface is asynchronous, TimeQuest audits the complete pin data paths against that allowance at each operating corner. The framework’s PAD interface uses 20-clock pulse segments (about 269 ns); its output data and enable paths have a separate 6 ns physical-delay audit. Local MMIO payloads are captured two clocks before their access pulse. Only their paths into sound/I/O access updates and graphics write-data updates use two-clock setup and the corresponding one-clock hold adjustment. Simulation checks payload stability and transaction identity on every access. Read pipelines, graphics RAM addresses, access controls and other internal paths retain their normal constraints. Reset synchronizer control pins are exempt from recovery/removal; their internal stage-to-stage paths and reset distribution remain timed. FIFO domains use asynchronous crossings even when their clocks come from the same PLL; Gray-code nets retain a separate 3 ns routing bound.

## Verification

```sh
make rtl-test
make rtl-system-test
```

The component suite compares 183,779 CPU cases with randomized memory latency and prefetched instructions, the first 4,096 contiguous boot instructions of each ROM, 481 rendered scanlines, 167,987 stereo samples and 192,000 sound-register/IRQ snapshots and 266,240 timer/ADC register and interrupt snapshots. The timer fixtures cover all divider modes and timebases, preload overflow, counter reset and FIQ selection; external-interrupt mappings are also checked. UART coverage adds 431,792 transmission-duration, countdown, status and IRQ snapshots across baud rates and 10/11-bit words. Another 2,560 watchdog snapshots check expiry, enable and valid/invalid clear commands. GPIO coverage adds 512 writes with input masks, all three ports and PC-gated raw/masked bank decisions. A two-million-clock fixture compares hardware phase/credit arithmetic, negative credit and saturation with the original integer model. It also checks one million resampler inputs, ROM cache behavior, RAM/MMIO/ROM bus response transitions, graphics memory readback across bus-owner handoffs and ignored ROM writes, complete 16/64 MiB loads and reloads, 1,024 delayed ROM reads, invalid/incomplete loads, serialized I²S data and four complete frames across independent clocks and delayed PSRAM transactions. A pin-level SDRAM fixture checks 512 writes and reads, all banks, final addresses, CL3 data, byte order and sixteen-halfword lines. Its worst write takes twenty memory clocks; full ROM loading is exercised with thirty-clock writes at approximately 9 MB/s, above the [documented APF transfer rate of a few MB/s](https://www.analogue.co/developer/docs/openfpga/bus-communication). The physical PSRAM controller fixture checks 512 reads/writes on both dies, address latch and strobe/data intervals; its measured 15-clock reads and 14-clock writes stay within the framebuffer fixture’s delays.

The IO expiry fixture also checks 526,336 full-width cases, including signed wrap and every cycle count. Expiry uses the existing subtraction stage before timer decisions, with no additional instruction latency. Local system/CPU reset registers limit reset distribution, and peripheral advancement uses the CPU cycle count held throughout DMA; the simulation checks that count against the retired instruction. Raw shift operands are prepared during fetch, while PC/status aliases retain their ordered architectural reads. Graphics configuration writes commit on the clock edge and the sound ramp counter retains its bounded 1–13 range.

The sound counter fixture checks 526,336 expiry/reload cases against full-width signed arithmetic, including wrap and every 8-bit debit. The resampler drain fixture permits 32 clocks of pipeline latency and checks every emitted value.

The system suite runs each ROM for 1,800 frames with scripted A and movement inputs, both at unrestricted speed and with hardware pacing enabled. It compares retired CPU registers, banking, every pixel and stereo samples against the vendored emulator. The ROM responder models conservative SDRAM/cache-line delays. Unrestricted runs must stay within the frame clock budget; paced runs must avoid overflowing the modeled cycle backlog. This is a throughput estimate; the final fitted design and physical memory still require validation.

Successful checks produce source fingerprints in `build/native-evidence/`. Packaging requires matching successful component, all six system, requested-clock smoke and FPGA receipts, and verifies the bitstream hash against a successful four-corner timing report. Changing covered sources invalidates the corresponding receipt.

## Quartus on Apple Silicon

The tested toolchain is Quartus Prime Lite 25.1std.0.1129 with Cyclone V support in Docker. The supplied `qinst-lite-linux-25.1std-1129.run` is an online bootstrap installer. Installation downloads only Quartus and Cyclone V and verifies Altera's checksums.

Use a Docker volume for the Linux installation; the installer failed writing its uninstall configuration on the external host filesystem. QEMU is required for compilation here: Rosetta crashed while reading the Cyclone V device database. The QEMU wrappers retain the original ELF tools as `.pdc-elf` files and ensure compiler helpers use the same emulator. The installation's CPU check is bypassed only when the explicit environment variable is set, because Docker exposes ARM `/proc/cpuinfo` to the x86 tool.

```sh
bash tools/fpga/install-quartus.sh \
  $HOME/Downloads/qinst-lite-linux-25.1std-1129.run \
  volume:pdc-quartus-25.1

export PDC_QUARTUS_VOLUME=pdc-quartus-25.1
export PDC_QUARTUS_EMULATOR=qemu
make fpga-template
make fpga
make package-native
```

The installed volume can be reused; do not reinstall it for each build. `make fpga-template` checks the unchanged official template at revision `da3a021b`. Native compilation stages the framework and source files under `build/fpga/native/`. TimeQuest reports clock, constraints, unconstrained paths and worst setup/hold/recovery/removal timing. Timing failures disable both package modes.

Analogue requires [each RBF byte to be bit reversed](https://www.analogue.co/developer/docs/openfpga/packaging-a-core). The package creates `bitstream.rbf_r` from the validated Quartus output.

## Card layout and controls

Once validation passes, the package is `dist/pocket-dc-native-preview.zip`. Merge its folders into the card root, or install and verify directly without ejecting:

```sh
python3 tools/package_native.py --install-to /Volumes/POCKET
```

Use `python3 tools/package_native.py --experimental --install-to /Volumes/POCKET`
to retain the tested `Local.PocketDreamConsoleFPGATest` entry. Both package modes
require current-source passing component, all full-ROM modes, requested-clock
smoke, successful fit/assembly and strict four-corner timing evidence. The
experimental manifest retains the exact verification and bitstream hashes. Experimental Core Settings also shows the read-only `S` (status) hexadecimal register at bridge address `0x20000000`. The legacy `S` status value is byte-reversed by the APF peripheral: reverse its four bytes before decoding (for example, displayed `0x0F01FFFF` means RTL status `0xFFFF010F`). Bits 0–7 indicate ROM ready, machine ready, CPU fault, audio underflow, audio overflow, video underflow, framebuffer write fault and ROM load fault; bits 8–10 hold the ROM bank, and bits 16–31 the modeled cycle backlog. The status register crosses clock domains without an atomic snapshot, so use repeated readings for diagnosis. The diagnostic build additionally shows `F` (fault PC) at `0x20000008` and `O` (opcode) at `0x2000000c`. These values already compensate for APF byte reversal; read them exactly as displayed. The PC is a 22-bit CPU word address. The held fault payload crosses through two synchronizer stages and is captured after a three-stage fault flag; CPU reset clears it before the next fault. These probes do not change CPU execution. Enabling Debug Logging before launch also records the APF boot sequence under `/System/Logs/`. Freezes, missing output or corrupted graphics/audio are possible; record the ROM and observed behaviour for diagnosis.

The native namespace is `Cores/Local.PocketDreamConsoleFPGA`. Game selections are in `Assets/pdc/Local.PocketDreamConsoleFPGA`. Both native and software versions reuse `Assets/pdc/common/pdc30.rom` and `pdc100.rom`. Shared files must match before installation, and other cores are preserved. The package includes private copies of the supplied dumps; originals remain unchanged.

USB SD Access in Tools → Developer mounts the card over Pocket’s USB-C connection. It is useful for replacing the core binary and reading boot logs; large transfers are slow, so installation reuses matching ROMs already on the card. Enable Debug Logging to collect boot reports under `/System/Logs/`. Ordinary USB-C does not provide live FPGA debugging; Analogue documents a separate JTAG connection for that. See [Debugging Aids](https://www.analogue.co/developer/docs/openfpga/debugging-aids) and [Getting Started](https://www.analogue.co/developer/docs/openfpga/getting-started).

| Pocket | PDC |
| --- | --- |
| D-pad | D-pad |
| A / B | A / B |
| L / R | Left / right triggers |
| Start | Pause |
| Hold Select and Start | Reset to the PDC boot menu |

Select the FPGA version under openFPGA → Pocket Dream Console and choose PDC30 Pink or PDC100. For physical verification, check both boot menus, start a game, move, test stereo sound and reset without reloading. Save states, sleep/resume and Dock output are not supported.

## Accuracy limits

The source emulator is a behavioral reference, not a measured physical-chip timing specification. Inherited omissions such as ignored graphics fade/horizontal compression remain. The native random registers use deterministic LFSRs instead of the host emulator's random function; physical randomness is unmeasured. The reference leaves its cached FIQ signal stale after interrupt status is cleared or its enable mask changes; the RTL instead reflects the selected active source immediately. The timer fixture checks that source directly from the reference status and enable registers. CPU cycle counts, display cadence, timers, memory timing and game compatibility need real-device comparison. The diagnostics expose CPU/load/audio/display faults and modeled cycle backlog; they do not prove hardware accuracy.

Native cache word banks use a local fabric address register followed by the Cyclone V RAM address register, giving two-clock reads with an unregistered RAM output. The component suite requires Icarus Verilog and the installed Quartus 25.1 model at `.deps/quartus-sim/altera_mf.v`; its hash is recorded with the component evidence. It compares 9,850 defined randomized reads and exercises both transfer modes against that model. Undefined read/write collisions are excluded only from direct bank comparisons; complete cache requests remain checked. The Pocket system selects complete-line transfers, which eliminates the unused single-word fill logic while keeping the same latency. The sound selector uses a one-hot position alongside its register index, with a simulation invariant, and resampler phase advancement uses fixed increments.

The RAM configuration follows [Altera’s Cyclone V registered-output example](https://community.altera.com/discussions/fpga-device/timing-paths-from-port-b-write-enable-reg-to-an-inferred-simple-dual-port-ram-ou/195994/replies/196002).

CPU operand forms are decoded with opcode capture. Direct multiplication uses fetched operands, with status-register aliases read at decode to retain ordered updates. GPIO uses a registered local copy of the program counter; the same two-clock MMIO stability check covers this payload and its narrowly scoped timing exception. Graphics format registers capture at the attribute/bitmap/sprite states independently of sprite culling, before the renderer consumes them. These changes add no instruction or rendering stages.

Instruction and memory-response latches, peripheral busy signals and graphics readiness commit on clock edges. Prepared instruction controls decode the fetched word directly; one-hot CPU resume states are checked in component and system tests. Graphics clipping uses shifts and addition for its supported pixel formats instead of a combinational DSP multiplier. These changes retain the existing hardware stages; the system model includes the resulting clock-edge handshake visibility.

Pitch eligibility compares the existing registered pitch operands. Component and system tests verify these match the selected channel when the pitch decision is consumed. This removes a channel-array read and comparison from the feedback path without adding controller stages.

CPU instruction totals and elapsed cycle counts commit on clock edges. Graphics horizontal flip, object kind and end offset also use clocked latches. ADC debit/reload operands are captured independently of expiry decisions and are consumed in the existing next stage. CPU, peripheral and rendered-output comparisons cover these stage boundaries.

Internal RAM uses the same two-clock registered memory-bank implementation, with its original 10,240-word depth. Arbitration exposes the held owner’s address one clock before its request, allowing the RAM output register to complete before the existing acknowledgment is consumed. Simulation rejects requests without this lookahead. The RAM fixture checks 8,194 reads, clearing, writes and block boundaries against both RTL and the Quartus RAM model; the system bus fixture additionally checks changing owners and RAM/MMIO transitions.

Sound pitch changes are tracked per channel before selection; the verification invariant checks the selected flag and operands against their channel. Divider eligibility captures during idle, using the same pre-tick counters, so expiry no longer controls a wide register-enable fanout. The four sprite tables request M10K storage with registered read addresses and outputs. Two-ahead sprite prefetch keeps skipped sprites at one clock; blend-pass restart takes one extra clock. [Altera documents asynchronous MLAB reads and synchronous M10K reads](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/embedded-memory-features?contentId=W70RQm9AY4r7x0G9SRTukA); final compilation must confirm the requested mapping. Sprite horizontal position captures independently of culling, using the four fixed half-width biases. ROM cache groups have local word-selection registers, and shared bus address registers limit fanout. These changes use existing stages and are covered by the same differential and memory-model checks.

The CPU cache receives a registered ROM-address classification. Its staged-request mode replaces the initial RAM wait state, keeping the original request-to-reply latency while separating address classification from controller updates. The shared bus still uses the original classification to exclude CPU ROM reads. Component tests exercise both request modes and both transfer modes against RTL and the vendor RAM model; system tests enforce the address-lookahead contract.

CPU multiplication uses one signed 17-by-16-bit product. The registered high bit of the first operand selects signed or unsigned interpretation before the multiplier; the second operand remains signed. Instruction and system comparisons cover both forms without changing execution stages or cycle counts.

Audio accumulation and product assembly use six-bit arithmetic groups with parallel carry propagation. This bounds carry-chain length within the existing stages; one million input samples and full-system stereo comparisons verify identical signed results.

Graphics memory-response and pixel-buffer latches commit on clock edges. The one-hot controller registers retain their stage boundaries through local `preserve` and `dont_retime` attributes; component and system tests verify both current and resume states remain one-hot. [Altera documents the local retiming restriction](https://docs.altera.com/r/docs/683283/18.1/intel-quartus-prime-standard-edition-user-guide-design-compilation/disabling-synthesis-netlist-optimizations-with-dont_retime-attribute). CPU bus-address registers limit fanout to reduce the measured arbitration routing path.

Prefetch validity, fetched instructions, instruction addresses and branch displacement commit on clock edges. Initial fetches use the current program counter directly, retaining the existing request address when capturing the instruction address. The CPU also registers its external-memory region flag alongside the bus address; system arbitration consumes that flag without another address decode. Verification checks its alignment on every active CPU transaction, including prefetched instructions and delayed bus responses.

Sound envelope addresses and repeat flags capture in the existing routing stage independently of its comparison result. Timer-divider flags prepare zero checks for the incremented counter before their decision stage, including all divider values from zero through fourteen and counter-reset writes; verification checks their alignment when consumed. CPU interrupt inputs have local clocked snapshots. System verification rejects any snapshot that differs from an enabled source at an executing instruction boundary. These changes retain the existing instruction and peripheral stages.

Cache controllers use preserved one-hot state bits and clock-edge transitions, checked during cache and full-system tests. CPU operand subtraction and status-carry controls are decoded alongside the instruction; initial fetch operands use the incoming instruction directly. These controls preserve the existing instruction and memory latency.

System and CPU reset registers use bounded fanout replication without changing their clock-edge behavior. This targets the measured reset distribution paths into cache and audio register enables.

CPU shifts use a separate hardware stage. Ordinary memory operands capture directly on bus acknowledgment before ALU execution, removing their previous operand-transfer stage. Architectural instruction cycles and register aliases are checked against the reference; full-system validation separately checks FPGA clock budgets with both ROMs.

Shift operands, amount and shift-register context capture unconditionally before the existing shift stage. Their preserved clock boundaries separate register selection from the barrel shifter without adding another instruction clock. Differential instruction tests cover status/PC aliases and interrupt shift-register contexts.

Routed timing corrections register MAC memory operands with the existing pointer-update lookahead, including equal source/destination aliases. Sprite memory uses local preserved address registers and two-ahead lookahead, separating address selection from RAM readback. Ramp processing advances the channel unconditionally on its entry stage and commits through a captured voice index, keeping eligibility out of the counter enable without adding a stage. GPIO captures the projected masked port during the existing write/commit pair. Resampling splits its middle-product addition into registered six-bit groups and a carry-assembly stage, with validity and sign aligned. Native burst cache replies capture their data unconditionally; non-burst behavior retains its existing handshake. All require matching component, full-ROM and FPGA timing evidence.

Cache and internal RAM word banks keep their two-clock read latency using a preserved local fabric address register followed by the M10K address register, with an unregistered RAM output. This separates address distribution into each bank from its memory-block fanout. The vendor RAM model must verify reads and complete transactions; fitted timing must validate the new memory-output path. Local write addresses retain their existing latency and bounded fanout.

Sprite planes explicitly instantiate M10K RAM with registered addresses and outputs and same-edge writes. The vendor fixture checks the same two-clock read contract independently of graphics inference; graphics tests cover sprite ordering and register readback. Compilation must confirm four sprite M10K banks.

Sound register reads capture the selected register independently for each channel and the global register bank before selecting the addressed channel. The existing MMIO address-settling stages cover the added read pipeline; component tests wait its one-clock contract and system tests verify unchanged acknowledgments. The encoded sound channel counter uses unconditional zero/one arithmetic with the existing reset/advance decisions, reducing the shared enable distribution. CPU stack increment/decrement operands capture before their consuming states and predict a pop that writes its own pointer register; verification checks each consumed value against architectural state. Graphics tile and output memory addresses retain their clock boundaries through local preservation and retiming restrictions. These changes require fresh full simulation and timing evidence.

Arbitration computes the priority choice independently of busy, turnaround and launch; the controller qualifies those phases once before accepting a grant. Held grants and memory output addresses keep their register boundaries and bounded fanout. This preserves the existing transaction stages and payload lifetime while removing duplicated acceptance gating from the priority data path.

The sound address captures the held owner’s bus lookahead one clock before the main memory address, covering the register-read pipeline even when ownership changes. Verification checks three-clock sound-address settling before access. A focused regression alternates DMA and CPU ownership while switching between sound global, channel and pitch registers; it rejects the stale previous-register response.

The two-clock MMIO exception explicitly excludes the new sound-read capture registers. Those addresses must reach the read pipeline in one clock; each corner emits a separate sound-read timing report alongside the complete timing gate. Endpoint checks reject missing channel/global read registers. Access updates retain their proven two-clock payload contract.

Envelope-delay decrement and expiry prepare separately for each voice before channel selection; verification checks both against the consumed channel register. Graphics scroll addition commits before horizontal position negation, adding one clock per active background pass while preserving the line RAM read boundary. Audio accumulation uses a carry-save pair for its recurrent update and combines its boundary sum through two short-group pipeline stages; signed results and consecutive inputs retain the reference contract. GPIO qualifies the already projected or current port at the capture output, keeping the access pulse out of the projection arithmetic. Cache clearing prepares its final-tag flag before consumption and uses unique cases under the verified one-hot state invariant. Full ROM budgets and fitted timing must validate these changes.

Graphics preserves the main one-hot state register and prevents retiming of the resume state, while allowing unused constant resume bits to be removed. Preserving those constant bits created clockless registers in the fitted netlist; the constraint gate rejects any remaining clockless state.

The scroll RAM read output remains inferable as a one-clock M10K read; preserving its external register prevents that mapping. The separately preserved scroll-sum register retains the arithmetic boundary. Synthesis must confirm the scroll RAM and all four sprite planes remain in M10K blocks.

Native compilation audits all eight graphics memories as M10K blocks with their required depths and widths and rejects clockless registers. Under QEMU this gate runs after synthesis before fitting; the final timing validator repeats it for every compiler route. FPGA evidence also fingerprints the mapping validator.

CPU multiplier operands and product capture unconditionally in their existing stages, allowing DSP register packing; consumption remains in the following MAC/write stage. Cache fill addresses use each bank’s already settled local read address, with a consumed-address invariant, removing distribution from the shared pending register; internal RAM retains independent read/write addresses. Sound eligibility captures its channel enable/disable mask before selection and checks the consumed voice against the current register bits. Full ROM and timing evidence remain required.

Address arbitration holds separate owner bits for four-bit address groups, captured on the same grant-acceptance edge. The selected address still uses the held client payload directly, preserving the existing lookahead and transaction timing. Verification checks the selected address against the held owner during launch and active transactions. Fitted timing must confirm the routing benefit.

Fetched operand values and their arithmetic form capture separately during the existing fetch-response interval and remain held after it. The consuming operand selects these captures until an explicit operand transfer replaces them; no instruction stage is added. Differential tests must cover prefetch, register aliases, delayed responses and multiplication, followed by full ROM and fitted timing validation.

Peripheral ticking uses explicit one-hot states and unique-case transitions, verified whenever reset is inactive. The existing timer, ADC, UART, GPIO and watchdog stages and access priority remain unchanged.

The registered memory address and its earlier lookahead use separate grant captures and address muxes. Their values and acceptance edge are identical, but the fitter can place each copy beside its destination instead of routing one mux through distant consumers. Verification requires both addresses to agree with the held owner throughout launch and active transactions.

Sound read selection has one local field/pitch capture per voice plus a global field capture, sampled from the bus lookahead on the same edge as the sound write address. Verification requires every local capture to equal that registered address continuously. The existing read and MMIO transaction latency remains unchanged. The ordinary one-clock timing gate covers all sound read captures, including the local fields.

Graphics map-row values commit on the clock edge before address addition. Sound byte extraction and full-word end detection capture from the acknowledged wave response before decode, with consumed-value checks. Cache tag clearing and fills share registered write payloads; two reset-only drain clocks commit the final clear and flush its tag comparison before requests. A regression holds a request for the final cache line across invalidation and requires a fresh memory fill. Four-bit tag comparisons capture alongside the existing tag read stage before the hit reduction. Cache state hold branches name their one-hot state explicitly. Internal RAM clearing increments its otherwise unused terminal address without a comparison in the counter enable, and DMA prepares its read address independently of its completion decision. UART/watchdog upper words capture independently before countdown consumption. Resampling registers six-bit upper-product sums before carry assembly, adding one audio pipeline clock. Matching component, full-ROM and fitted timing evidence is required.

# Current refinement: 0.1.0-sprite-groups

The previous pacing candidate still overflowed at PDC100 frame 869, without
display backpressure. Increasing the timing allowance did not resolve throughput.
This revision records eligible groups of eight sprites for each layer/blend pass
while clearing each scanline. Empty groups take a two-clock skip and RAM refill,
while occupied groups retain original sprite ordering and rendering semantics.
The eligibility summary resets each line. No clock, sound rate or timing-credit
limit changes in this revision.

A PDC100 frame-850 snapshot rendered identical pixels in 509,058 warm-cache
renderer clocks, versus 551,064 before (42,006 fewer clocks, 7.6%). The focused
sparse-sprite budget failed before the change (943 clocks versus budget 820).
Expanded checks cover group boundaries, all passes, full-range random sprites,
ROM block reuse and the original overlap regression. Full ROM/continuous-output
simulation, FPGA timing and hardware confirmation remain required.


## Quartus syntax repair — 12 October 2026

The sprite-group candidate reached 1,230 continuous-output frames in both ROMs,
but Quartus rejected the framebuffer's implicit generate loop before synthesis.
This workspace explicitly brackets the same two-instance loop with generate /
endgenerate and declares its genvar separately. No logic or clock changes.
The complete simulation suite will rerun against the repaired source, overlapping
FPGA compilation after component checks and the two clock smoke tests pass.
All 1,800-frame receipts and strict timing remain mandatory before installation.


## Routing-congestion retry — 12 October 2026

The preceding candidate passed both 1,800-frame production audio/video runs:
Pink maximum backlog 39,131 modeled cycles; PDC100 40,371. No CPU, pixel or
stereo-sample mismatches or output FIFO faults occurred on those scripted paths.
Synthesis and graphics-memory mapping passed, but fitting stopped on routing
congestion (errors 170143/11802), with 16,396/18,480 ALMs and 288/308 M10Ks.

This retry changes only FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION to ALWAYS.
It preserves all RTL, clocks, physical timing constraints and validation gates.
Completed component/system receipts are reused only after exact source-hash
comparison; the interrupted PDC100 paced test and clock smoke rerun. FPGA
compilation, assembly and all four timing corners must pass before installation.
This compiler option may trade routing use against timing; success is unproven.



## Registered peripheral-address candidate — 12 October 2026

The routing-only retry fitted and assembled successfully (16,156/18,480 ALMs,
288/308 M10Ks), but strict internal setup timing failed: -1.194 ns at slow 85 C
and -0.979 ns at slow 0 C. Other checked internal timing and memory-port budgets
passed. The generated bitstream was blocked from packaging and was not installed.

`build/native-mmio-workspace` feeds graphics and sound from the registered bus
address, leaving RAM's combinational lookahead and fast ROM paths intact. MMIO
prepares its held transaction for one additional clock before access so graphics
RAM and the sound read pipeline settle. MMIO reads are bounded at five clocks;
RAM reads and PPU ROM hits remain bounded at two clocks. The focused bus check
covers all 16 sound channels, changing pitch/data/global/graphics reads across
bus owners, and the existing read/write and ignored-ROM-write checks.

CPU requests select the external-memory classification alongside each source
address, rather than reducing the selected wide address afterward. The existing
classification assertion and CPU/reference differential suite remain mandatory.
The candidate retains all physical clocks, strict timing constraints and routing
optimization. Full component, ROM, paced, production-output and FPGA timing
checks must pass before installation. Additional MMIO latency is included in
those real-time checks. This candidate has not been confirmed on hardware.
