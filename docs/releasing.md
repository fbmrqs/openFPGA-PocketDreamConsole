# Preparing a release

The canonical repository is `fbmrqs/openFPGA-PocketDreamConsole`. It is private
during preparation. Publishing a draft or changing repository visibility is a
separate maintainer action; updater inclusion is not yet requested.

## Artifact contract

- One installable ZIP named `fbmrqs.PocketDreamConsole_<version>_<date>.zip`.
- ZIP root contains only `Assets/`, `Cores/` and `Platforms/`.
- Ten launcher JSONs refer to user-supplied files in `Assets/pdc/common/`.
- No ROM, firmware dump, WAV, old runtime or copied author icon.
- Include the procedural seven-tone platform graphic generated from the maintained
  Blender source; validate its native dimensions and portable placement.
- The production `interact.json` has empty variables/messages. JSON has no
  comments; debug readout definitions remain in the private diagnostic packager.
- Licenses, notices, README and updater metadata live under the core directory.
- Separate `SHA256SUMS` and `build-info.json` assets describe archive contents,
  source identity, exact bitstream and source-bound qualification receipts.

This follows [Analogue's packaging convention](https://www.analogue.co/developer/docs/openfpga/packaging-a-core).
The installable asset is distinct from GitHub's automatic source downloads.

## Build locally

1. Update `release/metadata.json`, the changelog and release notes deliberately.
   Keep the namespace stable after publication. Version metadata and the tag
   must agree (`1.0.0` and `v1.0.0`).
2. Run `make check-release`. Inspect `git diff`, check notices and commit changes.
3. Use the frozen workspace containing the qualified FPGA, scene and library
   evidence. No new compile is required when hardware inputs are unchanged.

```sh
python3 tools/release.py --workspace build/native-pin-control-workspace
```

The packager verifies current and frozen source against all required receipts,
all four timing corners, the raw and reversed binary hashes, the completed
workspace identity and private package hashes. It copies only an explicit
public-file allowlist. Unexpected files, changed hardware or missing evidence
stop release creation. The generated ZIP is read back and checked before success.

The first hardware source is `3d287a2`; later documentation and release-tooling
commits do not change the FPGA. `build-info.json` records both hardware source and
packaging commit. The original private receipts are preserved, not rewritten.

Attach the ZIP, `SHA256SUMS` and `build-info.json` to a **draft** GitHub release
targeting the packaging commit, using [v1.0.0 notes](releases/v1.0.0.md). Inspect
the draft while private. Confirm that a clean clone passes `make check-release`.
ROMs and dependency/build directories must be absent from all pushed history.
Do not upload any `pocket-dc-native-library.zip` or other private test package.

## Public launch and pupdate

After deciding to publish, change visibility and publish the draft. Submit the
Library [Add Core form](https://github.com/openfpga-library/analogue-pocket/issues/new?template=ADD-CORE.yml)
with repository `fbmrqs/openFPGA-PocketDreamConsole` and asset filter
`^fbmrqs\.PocketDreamConsole_.*\.zip$`. No submission has been sent automatically.

`release/updaters.json` is copied into the installed core directory and discloses
OpenAI Codex. Old Local identities are deliberately not automatic replacements:
the inspected updater moves the old asset directory after installing the new
one, which can collide with the launch-profile directory already in the ZIP.
Do not add `license.filename`: that field requests an activation key, not an
open-source license notice. Both manual and updater installs can leave old Local
entries in place. Back them up before removing their `Cores/Local.*` and matching
`Assets/pdc/Local.*` directories, and preserve `Assets/pdc/common/`. Remove only
the PDC entries you recognize, after checking the new entry; never other cores.

pupdate installs core releases through the Library inventory. Its asset archive
download mechanism is separate; it does not grant ROM redistribution rights.
This release supplies local dump import only. An automatic source needs explicit
permission or a genuinely redistributable compatible demo/homebrew collection.
See [the source-backed research](release-research.md) for exact mechanisms and
announcement channels. Do not enable or advertise an unlicensed archive.

## License and presentation review

The project's own code is ISC, chosen by the maintainer. Preserve the veesem ISC,
PSRAM MIT, APF and FPGA vendor notices. Do not describe the entire mixed-license
project as unrestricted ISC IP. Review applicable vendor/EULA terms before
redistributing modified framework/IP components. Game ownership alone is not
blanket permission to redistribute a dump, song or title-screen image.

The linked Pocket Library image pack concerns cartridge Library art. No Library
integration or screenshot art is promised for these openFPGA launchers. The procedural handheld artwork is included; its source and export instructions
are maintained under `tools/artwork/`.
