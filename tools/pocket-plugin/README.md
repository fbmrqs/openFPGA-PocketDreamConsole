# Pocket Dream Console ROM preparation

An offline Pocket Plugin for pupdate and Pocket Sync. It prepares supported
local dumps without requiring Python on the user's computer. Source is maintained
here in the core repository; releases are distributed through
[fbmrqs/openFPGA-PocketDreamConsole-plugin](https://github.com/fbmrqs/openFPGA-PocketDreamConsole-plugin).

Download the individual plugin assets through your updater. This source does
not change the FPGA or the released v1.0.0 assets.

## Use

1. Install `fbmrqs.PocketDreamConsole` and this plugin through the updater's
   Plugins page. Updating an existing core does not necessarily display a new
   plugin recommendation; existing users can install it by repository URL.
2. Put supported raw dumps or ZIP archives in `Assets/pdc/import/` on the card.
   Subfolders are supported. The plugin has no general computer file picker.
3. Run the plugin. It automatically identifies, prepares and verifies the inputs,
   then checks all installed ROMs. Verified files appear in `Assets/pdc/common/`.
   Original files stay in the input folder. Nothing is downloaded. A profile
   marked “Not installed” is optional: only supply the profiles you own.

There is no opening menu or per-ROM question. No Python, command-line importer,
manual renaming, trimming or padding is required. Running the plugin once also
creates the intake folder if it is absent.

For automatic preparation during pupdate's **Update All**, enable this plugin's
run-on-update option once, after cores. The equivalent CLI command is:

```sh
pupdate plugins -p /path/to/card --set-auto "Pocket Dream Console ROM preparation"
```

Successful runs also work with pupdate's unattended `-y` option. Add new dumps to
the intake folder before the next update. Recovery that deletes unfinished files
still requires confirmation; unattended cancellation leaves those files intact.

The supported revisions are the same as the [Python importer](../import_roms.py)
and [ROM guide](../../docs/roms.md). PDC100's supported 128 MiB raw dump becomes
an exact 64 MiB `pdc100.rom`; smaller VideoJet dumps are zero-padded to 8 MiB.
Renaming an unprepared dump is insufficient. Unsupported revisions, PDC200 and
Touch models are rejected. BIOS, saves and core files are not modified.

Existing correct outputs are retained. Differing files are never intentionally
replaced: preserve/move a conflicting file into the input folder before retrying.
If a raw 128 MiB file is already named `Assets/pdc/common/pdc100.rom`, move it to
the input folder, then prepare it. The plugin reports this case explicitly.

Use only one updater against the card at a time. Interrupted imports may leave
`.pdc-import-<profile>.part` in the output folder. When preparation fails, the
plugin offers **Remove unfinished imports**. This requires confirmation that no
other updater is running and removes only this plugin's known temporary files.
Originals, final ROMs and unrelated `.part` files are kept. Preparation and
verification retry automatically after confirmed cleanup.

Every output reserves its size plus 16 MiB before writing. FAT/exFAT allocate
this reservation; sparse host filesystems may not, so every actual write is also
checked. Completed output is flushed and read back before publication. Failure
does not roll back other profiles already completed in the same run. Bounds are
4,096 input files/ZIP members and 16 nested input directories. ZIP supports stored
and deflated members; encrypted/other compression formats report an error.

## Build and automated checks

Run from the **core repository root**, with Rust 1.91.1 or newer and Python 3:

```sh
rustup target add wasm32-wasip1
cargo test --manifest-path tools/pocket-plugin/Cargo.toml --locked
cargo clippy --manifest-path tools/pocket-plugin/Cargo.toml --locked --all-targets -- -D warnings
bash tools/pocket-plugin/build.sh
python3 -m venv .deps/pocket-plugin-venv
.deps/pocket-plugin-venv/bin/python -m pip install -r tools/pocket-plugin/host-requirements.txt
.deps/pocket-plugin-venv/bin/python tools/pocket-plugin/tests/wasm.py \
  --wasm tools/pocket-plugin/target/release-assets/plugin.wasm
make check-release
```

`target/release-assets/` contains `plugin.wasm`, `plugin.json`, `LICENSE`,
`THIRD_PARTY_NOTICES.txt` and `SHA256SUMS`. Publish the first two as **individual
release assets**, together with the notices and checksums; a source ZIP is not a
plugin installation. The build remaps local source/cache paths out of the WASM.
Locked crate versions and license texts are included in the artifact workflow.

Private parity, using this repository's ignored original dumps, is separate:

```sh
.deps/pocket-plugin-venv/bin/python tools/pocket-plugin/tests/wasm.py \
  --wasm tools/pocket-plugin/target/release-assets/plugin.wasm \
  --private-root /absolute/path/to/pocket-dc
```

That test exercises the actual release-built WASM for all ten raw inputs and a
ZIP containing all ten, compares every output byte with the Python importer,
checks reference hashes, reruns both preparation/checking, and checks that inputs
remain unchanged. It uses disposable temporary folders. Public CI
uses synthetic Rust fixtures and the actual WASM protocol/negative tests; it
neither contains nor downloads commercial dumps.

`profiles.json` holds only size/hash/recipe metadata. The root package tests check
its source identities and output sizes against the existing importer tables.
When adding a supported revision, obtain its prepared SHA-256 from a verified
reference output and run private parity; no production hash-bypass setting exists.

On POSIX systems, exercise actual WASM write failure, forced termination,
explicit cleanup and retry using a disposable temporary folder:

```sh
.deps/pocket-plugin-venv/bin/python tools/pocket-plugin/tests/storage.py \
  --wasm tools/pocket-plugin/target/release-assets/plugin.wasm \
  --private-root /absolute/path/to/pocket-dc
```

This injects a file-growth limit; it does not simulate an actual full filesystem.
On macOS, add `--exfat` to create and fill a new disposable 256 MiB image instead.
That option requires disk-image creation permission and never selects an existing
disk or Pocket volume.

Both test scripts accept `--scratch-root /path/to/card` to exercise the target
filesystem inside automatically removed test folders. Existing core, ROM, save
and memory files are not used as writable fixtures. The default storage test
does not fill the card; a full-volume test requires the separate disposable image.

## Recorded local validation

On 30 October 2026, the release-built module passed:

- All 16 Rust tests, formatting, and native/WASM Clippy checks.
- All 10 package/import tests and 6 existing native-validation tests.
- Six actual Extism protocol tests and private parity for all ten supported
  dumps, supplied both raw and zipped. Every output byte matched the Python
  importer, prepared sizes/hashes matched, repeat runs were safe, and inputs
  remained unchanged.
- All seven WASM tests above on disposable folders on the connected exFAT SD
  card, including both raw and ZIP inputs. The suite completed in 48.188 seconds.
- File-growth failure and process termination during preparation on exFAT,
  followed by confirmed cleanup and automatic verified PDC100 retry.
- Actual pupdate 5.9.0 on macOS: local plugin discovery, unattended PDC100/raw and
  VideoJet/ZIP preparation, byte/hash verification, safe unattended repeat run,
  and accepting the run-on-update setting. No interactive choice was needed.
- The connected card's ten installed ROMs and public FPGA binary matched their
  reference hashes; all 722 protected core, asset, save and memory files remained
  byte-identical after testing. Temporary folders were removed; the card was
  left mounted with an empty `Assets/pdc/import/` ready for use.

The tested `plugin.wasm` was 476,295 bytes, SHA-256
`30e6488b8c2881c7c227970fcecffe6784086b22c0cedaa06f234d8252c7f86d`.
macOS denied disposable disk-image creation, so the true exFAT full-volume test
remains unverified. The cross-platform CI workflow is included but was not run
on GitHub during this local validation. Physical Pocket gameplay and a complete
pupdate Update All were not exercised by these plugin tests.

## Additional host checks

Headless Extism tests establish the module interface, not a claim that every host
UI has been exercised. Separately test GitHub installation/update in
Pocket Sync, Pocket Sync execution, Windows updater hosts, fresh-core recommendations
and existing-user instructions. Use a disposable exFAT image for full-volume and
forced-interruption checks, then smoke-test the prepared PDC100 file on Pocket.
ez-pocket shares the interface but has separate staging/platform limits; do not
claim untested combinations. Record actual results rather than treating planned
CI or these manual checks as passed.

The next core package emits a strict plugins-only `updaters.json`. Publish the
plugin first, then deliberately version a metadata-only core patch. Preserve the
existing v1.0.0 package and the exact qualified FPGA binary. No core or plugin
release is published by the build script or CI workflow.

The ABI follows [Pocket Plugin](https://github.com/openfpga-library/pocket-plugin).
The [PlayStation plugin](https://github.com/GuardianSoul/openfpga-PlayStation-plugin)
is a useful upstream reference for host interaction and private parity testing.
