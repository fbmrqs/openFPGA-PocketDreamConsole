# Pocket Dream Console for Analogue Pocket

![Isometric grayscale Pocket Dream Console handheld](docs/assets/handheld-banner.png)

A native openFPGA core for Pocket Dream Console and VideoJet TV Games hardware.
The μnSP CPU, SPG200 graphics, sound and board peripherals run in the FPGA.
No software-emulation runtime or external BIOS is required.

**Release: 1.0.1**

**Status:** full-speed gameplay, graphics, audio, A/B controls and sixteen display
filters have been confirmed on a Pocket across ten ROM profiles. This is
functional compatibility for the tested library, not a claim that every game
and hardware edge case is cycle-perfect.

## Install

1. Download the installable `fbmrqs.PocketDreamConsole_*.zip` asset from
   [Releases](https://github.com/fbmrqs/openFPGA-PocketDreamConsole/releases).
   GitHub's **Source code** downloads are for development, not card installation.
2. Merge its `Assets`, `Cores` and `Platforms` folders into the root of your
   Pocket microSD card. Preserve existing folder contents; on macOS use **Merge**
   rather than replacing whole folders.
3. Prepare your own supported dumps with the
   [ROM-preparation plugin](https://github.com/fbmrqs/openFPGA-PocketDreamConsole-plugin).
   Put raw dumps or ZIPs in `Assets/pdc/import/` and run the plugin; verified ROMs
   appear in `Assets/pdc/common/`. The [Python importer](docs/roms.md) remains an
   alternative. **No ROMs are included or downloaded.**
4. Open **openFPGA → Pocket Dream Console → PocketDreamConsole**, then choose a
   game profile. Loading and startup-bank verification take a few seconds.

The package declares Pocket firmware 1.1 or newer. Device testing used firmware
2.7; use a current stable firmware for the sixteen selected display modes.
Dock output is supported, including HDMI video, audio, controller 1 and the
display filters. Save states and sleep/resume are not supported in this release.

## Supported hardware profiles

| Profile | Device status |
| --- | --- |
| PDC30 Pink | Gameplay, graphics and audio confirmed |
| PDC50 | Gameplay, graphics and audio confirmed |
| PDC100 | Gameplay, graphics and audio confirmed |
| Teenage Mutant Ninja Turtles | Gameplay, graphics and audio confirmed |
| Oui-Oui | Gameplay, graphics and audio confirmed |
| Dora | Gameplay, graphics and audio confirmed |
| VideoJet TV Games 1–4 | Gameplay, graphics and audio confirmed for all four |

PDC200, PDC40 Touch and PDC150 Touch are unsupported. Other Sunplus/μnSP ROMs
are not automatically compatible: the chip revision, board wiring, memory map
and peripherals also have to match. See [supported dump hashes](docs/roms.md).

## Controls

| Pocket | Original PDC control |
| --- | --- |
| D-pad | D-pad |
| A | B |
| B | A |
| L / R | Left / right triggers |
| Start | Pause |
| Hold Select + press Start | Reset to the console menu |
| Analogue button | Pocket menu |

The A/B routing is global in the FPGA core and matches the device-confirmed
layout. ROM bytes are not patched. Production Core Settings contain no debug
status, fault, opcode or memory-check readouts.

## Display modes

The normal output is 320 × 240. Pocket's display menu also offers:

| TV / color LCD | Additional handheld looks |
| --- | --- |
| Trinitron | GB DMG |
| Reflective Color LCD | GBP |
| GBC LCD+ | Original NGP |
| Backlit Color LCD | Vacuum Fluorescent |
| Original GBA LCD | GG |
| SP101 | GG+ |
| NGPC+ | TurboExpress |
| PC Engine LT | Lynx+ |

These sixteen modes share one core entry. They are Pocket display treatments;
CPU/game timing is unchanged by the selection.

## Documentation and development

- [ROM preparation and checksums](docs/roms.md)
- [Updater ROM-preparation plugin source and tests](tools/pocket-plugin/README.md)
- [Architecture, dependencies and validation](docs/building.md)
- [Release procedure and updater submission](docs/releasing.md)
- [Release and pupdate research](docs/release-research.md)
- [Changelog](CHANGELOG.md), [contributing](CONTRIBUTING.md), [licenses and credits](NOTICE.md)

`make check-release` runs the ROM-free host checks. Native builds use Quartus
Prime Lite 25.1 with Cyclone V support; full hardware qualification additionally
uses Verilator, Icarus Verilog and local game dumps. See the build guide before
starting a compile. Documentation or menu-only packaging changes reuse the
qualified binary after verifying that all FPGA inputs remain unchanged.

The retired openfpgaOS software target remains in `src/main.cpp` and the legacy
packaging tools for historical reference. It is not part of the native release.
[Earlier software notes](docs/software-emulator.md) and the chronological
[native development record](docs/native-fpga.md) / [refinement record](docs/native-refinements.md)
retain previous failures and superseded measurements.

## ROMs, licensing and provenance

Users supply game dumps they are entitled to use. The release contains only the
core, configuration, launch profiles and notices. It does not download games.
The local importer verifies supported dump sizes and hashes, trims the unused
PDC100 upper half, and zero-pads the smaller VideoJet dumps for the board loader.
Original source files remain untouched.

Project code uses **ISC**. Third-party ISC/MIT notices, the Analogue Pocket
Framework agreement and Intel/Altera FPGA IP terms remain applicable; see
[NOTICE.md](NOTICE.md). Product and game names do not imply endorsement.
The procedural handheld artwork and its generator are described in
[the artwork guide](tools/artwork/README.md). No ROMs,
recordings or commercial game artwork are part of this repository or release.
