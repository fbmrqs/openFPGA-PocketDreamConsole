# Pocket ROM preparation plugin research

Research snapshot from **30 October 2026**, before implementation, checked against upstream source and release metadata. The implemented source, automated checks and remaining release checks are now documented in [the plugin guide](../tools/pocket-plugin/README.md). The sections below retain the research-stage recommendations and host limitations.

## Recommendation

The shared **Pocket Plugin** contract is a practical route for making the existing local ROM preparation workflow available in pupdate and Pocket Sync. It uses Extism WebAssembly with a JSON sidecar. Both hosts implement the same functions, messages and filesystem mounts. Rust is the reference language; PlayStation provides a working example. [Common contract and example](https://github.com/openfpga-library/pocket-plugin/tree/39dae308f7db00d77a4314fc76ad5d8d5b09b81b), [PlayStation plugin](https://github.com/GuardianSoul/openfpga-PlayStation-plugin/tree/f690d399d4b354c07901b9ac590fe8cfddbbc918)

Use an offline plugin with `allowed_hosts: []` and retain the Python importer. Add recommendations after publishing a usable plugin release. There is no standard file picker: dumps must already be accessible through `pocket/`; entering a computer path does not grant access. [pupdate mounts and execution](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/PluginService.cs#L391), [Pocket Sync mounts and execution](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/commands/plugins.rs#L138)

ez-pocket also implements this contract, with staging and platform caveats. [ez-pocket plugin documentation](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/docs/POCKET-PLUGINS.md)

## Host findings

### Runtime and interface

The common example is a Rust `cdylib`, using `extism-pdk = "1.3.0"`, Serde and the `wasm32-wasip1` target. Its documented build is `cargo build -p plugin --target wasm32-wasip1`; the release workflow adds `--release`. The same `.wasm` artifact runs under each host's Extism runtime; users do not need Rust to run it. Other languages can implement the contract, but there is no generated cross-language schema. [Example Cargo manifest](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/plugin/Cargo.toml), [release workflow](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/.github/workflows/add_to_release.yml), [contract documentation](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/README.md#flow)

The plugin exports `start()` and, when interactive, `handle_response(input)`, returning JSON messages. Hosts provide `print_msg` and `open_url` through Extism pointer inputs/outputs. Mounts are `pocket/` for the target and `host/` for private persistent data; `locale` is passed as configuration. There is no arbitrary native process or Python interpreter capability. [Reference plugin ABI](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/plugin/src/lib.rs), [pupdate host](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/PluginService.cs#L391), [Pocket Sync host](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/commands/plugins.rs)

The actual Serde wire format is:

```json
{"Choice":{"name":"prepare","query":"Prepare supported ROMs?","choices":["Prepare","Exit"]}}
{"Text":{"name":"value","query":"Enter a value"}}
{"Answer":{"name":"prepare","value":"Prepare"}}
"Kill"
"Exit"
```

Each line is a separate message. `Choice`/`Text`/`Exit` come from the plugin; `Answer`/`Kill` from the host. **`Kill` and `Exit` are JSON strings**. The common README shows an object-shaped Kill example; follow the Rust source and tested string encoding. [Reference enums](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/plugin/src/lib.rs#L5), [ez-pocket protocol parser and Kill](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Services/PocketPluginRuntime.cs#L56), [protocol tests](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Tests/PocketPluginTests.cs#L25)

Use temporary output files followed by a checked rename, and leave source dumps intact. This matters because pupdate and Pocket Sync mount the selected target directly. A plugin can modify the whole mounted target; the runtime does not restrict it to its own core's `Assets` directory. pupdate applies a five-minute timeout per invocation. Pocket Sync supplies a cancellation handle; a cancellation or failure cannot be assumed to roll back writes already made. [pupdate runtime](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/PluginService.cs#L389), [Pocket Sync runtime and cancellation](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/commands/plugins.rs)

### Manifest and release assets

A minimal manifest suitable for all three inspected hosts is:

```json
{
  "name": "Pocket Dream Console ROM preparation",
  "description": "Prepares supported local ROM dumps for Pocket Dream Console.",
  "allowed_hosts": []
}
```

Include a name, description and empty hosts array. `logo_url` is optional in pupdate/Pocket Sync. ez-pocket caps name/description lengths at 200/8,000 characters. No inspected model defines an API version, minimum host version or plugin version field. [Reference sidecar](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/plugin/plugin.json), [pupdate model](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/models/Plugins/PluginManifest.cs), [Pocket Sync model](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/commands/plugins.rs#L16), [ez-pocket model](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Models/PocketPlugin.cs), [ez-pocket validation](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Services/PocketPluginService.cs#L344)

Publish **individual GitHub Release assets named exactly `plugin.wasm` and `plugin.json`**. A source archive or a ZIP containing the pair is insufficient for the inspected installers. They resolve the repository's latest published release and find those two assets; keep the latest release usable for plugin clients. All three implementations use the release **tag** (`tag_name`), despite older documentation mentioning the title. A dedicated plugin repository separates this latest-release endpoint from core releases. [pupdate installer](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/PluginService.cs#L142), [Pocket Sync installer](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/commands/plugins.rs#L217), [ez-pocket installer](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Services/PocketPluginService.cs#L73), [PlayStation release workflow](https://github.com/GuardianSoul/openfpga-PlayStation-plugin/blob/f690d399d4b354c07901b9ac590fe8cfddbbc918/.github/workflows/release.yml)

All three installers ultimately use GitHub's `/releases/latest` endpoint, which excludes draft releases and prereleases. A prerelease-only plugin repository is therefore unsuitable for testing their normal install flow. Finish local artifact tests first; a later full installer test can use a dedicated test repository with a published full release and the exact two assets. Publishing that test release is a separate action; none was performed here. [pupdate latest endpoint](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/GithubApiService.cs#L33), [GitHub latest-release semantics](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)

### Host versions and behavior

| Host | Verified upstream version milestones | Installation and operation |
| --- | --- | --- |
| pupdate | Plugin support appeared in **4.12.0**. **5.9.0** adds the plugin CLI, catalog, optional Update All execution and core recommendations. Use 5.9.0 or newer for the proposed recommendation flow. | Pocket Extras → Plugins → Install from GitHub accepts a repository URL or `owner/repo`. Plugins normally live beside pupdate, with a configurable directory. Runs operate on the selected target directly. |
| Pocket Sync | Plugin support appeared in **6.0.0**; **6.1.1** fixes plugins in the built/signed macOS app. **7.1.0** adds core-info plugin install/run; **7.1.1** adds core suggestions to the Plugins view. Use 7.1.1 or newer for the complete recommendation UI. | Plugins → Add accepts a repository URL. Configured plugins are installed or checked for updates when the plugin list is loaded/refreshed. Running is a separate action in a plugin window, operating on the selected target directly. |
| ez-pocket | **0.1.15** introduces initial Pocket Plugin support. Current inspected release is **0.1.18**. | Dashboard → Pocket Plugins: install by repository, then Run and Review. Changes run against a complete local copy and require a separate Apply action. No automatic execution, automatic plugin updating, plugin catalog or documented core recommendation flow. |

Sources: [pupdate 4.12.0](https://github.com/mattpannella/pupdate/releases/tag/4.12.0), [pupdate 5.9.0](https://github.com/mattpannella/pupdate/releases/tag/5.9.0), [pupdate operating instructions](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/README.md#plugins), [Pocket Sync 6.0.0](https://github.com/neil-morrison44/pocket-sync/releases/tag/v6.0.0), [Pocket Sync macOS fix](https://github.com/neil-morrison44/pocket-sync/releases/tag/v6.1.1), [Pocket Sync 7.1.0](https://github.com/neil-morrison44/pocket-sync/releases/tag/v7.1.0), [Pocket Sync 7.1.1](https://github.com/neil-morrison44/pocket-sync/releases/tag/v7.1.1), [plugin list refresh implementation](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src/jotai/plugins/selectors.ts), [ez-pocket initial release](https://github.com/kewalker/ez-pocket/releases/tag/v0.1.15), [ez-pocket current release](https://github.com/kewalker/ez-pocket/releases/tag/v0.1.18), [ez-pocket operating instructions](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/docs/POCKET-PLUGINS.md)

ez-pocket copies at most **64 GiB / 200,000 files**, requiring space for the target, output and backups. Calls have a five-minute timeout and 1 GiB memory cap; manifest/module limits are 64 KiB/64 MiB. Saves, Memories and root firmware writes are blocked. Windows x64 runtime tests and a synthetic PlayStation-plugin smoke test are documented; macOS/Linux plugin testing remains outstanding, and mobile is unsupported. [ez-pocket limits and validation evidence](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/docs/POCKET-PLUGINS.md), [runtime limits](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Services/PocketPluginRuntime.cs#L23)

### Core recommendation metadata

Put the following JSON in **`Cores/fbmrqs.PocketDreamConsole/updaters.json`** within the installable core ZIP. `OWNER/PLUGIN_REPOSITORY` is a placeholder for the eventual published plugin repository, not an existing plugin:

```json
{
  "plugins": ["https://github.com/OWNER/PLUGIN_REPOSITORY"]
}
```

The field is an optional array of repository URL strings. This is separate from `plugin.json` and pupdate's catalog. The PlayStation core's packager writes exactly this `plugins` shape into its core folder. Use the same canonical HTTPS URL throughout: Pocket Sync's UI compares URL strings directly when deciding whether a suggested plugin is installed. [PlayStation packaging](https://github.com/GuardianSoul/openfpga-PlayStation/blob/458d985dec8d239bda18bdf8dc980fb4e8935c5f/scripts/package_release.py#L110), [pupdate metadata model](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/models/Updater/Updaters.cs), [Pocket Sync metadata model](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/core_json_files/updaters.rs), [Pocket Sync suggestion comparison](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src/components/plugins/index.tsx#L65)

pupdate collects recommendations **only when a core transitions from absent to installed**. It reads both inventory metadata and the installed core's `updaters.json`, deduplicates repository references and offers installation for missing plugins. In an unattended run it prints an installation hint; it does not install recommendations automatically. Installing the recommended plugin does not imply running it or enabling automatic execution. Existing core users who update to a release introducing this metadata need explicit plugin installation instructions because this first-install prompt will not appear for them. [pupdate recommendation collection and resolution](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/CoreUpdaterService.cs#L337), [recommendation tests](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/tests/pupdate.Tests/Integration/CoreUpdaterServicePluginTests.cs#L291)

Pocket Sync reads the installed `Cores/<core>/updaters.json` and offers the referenced plugin in the core info view; its Plugins view also lists uninstalled suggestions. This is an install/run affordance rather than a guaranteed prompt at core-install time. ez-pocket's inspected plugin implementation and documentation expose manual repository installation; they do not establish support for recommendations from `updaters.json`. [Pocket Sync core metadata loading](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src/jotai/cores/selectors.ts#L64), [core info UI](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src/components/cores/info/installed.tsx#L312), [plugin mini item](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src/components/plugins/miniItem/index.tsx), [ez-pocket manual workflow](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/docs/POCKET-PLUGINS.md)

The current Library schema/class does not model `plugins`. Do not depend on catalog propagation: include the file in the installed ZIP, which both hosts read directly. [Pinned Library metadata schema/class](https://github.com/openfpga-library/analogue-pocket/blob/d9d3f4b60b7ce5e1e33f2f49c06bafafecccf4a1/.github/workflows/updater/lib/analogue/updaters.rb)

The local packager rejects extra `updaters.json` files. Add a narrow, validated **plugins-only** allowance and package tests. Preserve v1.0.0; a future metadata patch can reuse its qualified bitstream when qualified build inputs remain unchanged. [Current package rules](../tools/release.py), [current release tests](../tests/test_release.py)

Catalog inclusion is optional. pupdate's separate `plugins.json` catalog accepts entries containing `id`, `repo`, `name`, `author`, `description`, `tags`, `requires_input`, suggested `phase` and `links`; its documented submission route is a pull request. Repository URLs work without catalog inclusion. [Catalog and example](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/plugins.json), [catalog model](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/models/Plugins/PluginCatalog.cs)

## Testing without a connected Pocket

The common repository supplies a CLI demo host that runs a locally built pair of plugin files and accepts separate target and host folders. Run it against disposable temporary folders:

```sh
cargo run -p demo_host -- --folder-plugin /ABS/PLUGIN-DIRECTORY --pocket-path /ABS/TEMP-CARD --host-folder /ABS/TEMP-HOST --log-level trace
```

The demo host is interactive and honors manifest hosts. [Demo host arguments and runtime](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/demo_host/src/main.rs), [documented test command](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/README.md#to-test-other-plugins)

The PlayStation Python host mounts a folder as `pocket/`, prints logs, accepts repeated `--answer` and logs URLs without opening them. It needs Python `extism`. It handles only `Choice`, matches prefixes and defaults missing answers to the first choice. Extend a PDC harness to fail missing answers and exercise `Kill`. [Headless host source](https://github.com/GuardianSoul/openfpga-PlayStation-plugin/blob/f690d399d4b354c07901b9ac590fe8cfddbbc918/host/run_plugin.py)

pupdate 5.9.0 adds a real CLI execution path:

```sh
pupdate plugins -p /ABS/TEMP-CARD -l
pupdate plugins -p /ABS/TEMP-CARD -r "Pocket Dream Console ROM preparation"
pupdate plugins -p /ABS/TEMP-CARD -r "Pocket Dream Console ROM preparation" -y
```

These examples assume an already installed/local-discovered plugin. For local discovery, place `plugin.wasm` and `plugin.json` together in one child directory of pupdate's configured plugin directory; its `Discover()` method reads those child directories without requiring GitHub metadata. Set `config.plugins_directory` to an isolated test location in the test settings. There is **no** `plugins --install /local/path` or direct `.wasm` run argument: `--install` accepts only repository references, while `--run` resolves an already discovered plugin by display name or directory name. pupdate's private data root is separately fixed under the current user's LocalApplicationData `pupdate/plugin_data`; choosing a temporary card alone does not isolate that storage. [Discovery implementation](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/PluginService.cs#L42), [configured directories](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/helpers/ServiceHelper.cs#L94), [CLI dispatch](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/partials/Program.Plugins.cs)

`-y` answers interactive prompts with Kill; use it to test cancellation/unattended behavior, not to approve preparation. Redirected input also triggers cancellation behavior when no prompt handler is attached. Isolate the plugin directory, private data and settings as well as the target during a host smoke test. No stable headless Pocket Sync plugin CLI or supported local-folder installer was established by the inspected sources. Its supported add/install flow expects a real GitHub latest release; the Tauri command implementation can guide a contract harness without automating its UI. [CLI documentation](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/CLI.md), [unattended runtime behavior](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/src/services/PluginService.cs#L380), [Pocket Sync command](https://github.com/neil-morrison44/pocket-sync/blob/ad53e009e82963e6799cda54a60ec76a796fe30f/src-tauri/src/commands/plugins.rs)

Extend the existing importer tests and add real-WASM protocol/output tests, cancellation, repeat runs and source preservation. Compare against independently expected bytes as well as the Python importer. Keep host/platform smoke tests separate from headless ABI tests. Upstream has useful precedents for recommendation behavior, staged writes and native cancellation. [Existing importer tests](../tests/test_release.py), [pupdate recommendation tests](https://github.com/mattpannella/pupdate/blob/92ea3e80ca41b4a4d8023734ebab887ba5c39e52/tests/pupdate.Tests/Integration/CoreUpdaterServicePluginTests.cs), [ez-pocket native tests](https://github.com/kewalker/ez-pocket/blob/db74955385a4fc21fbe63598aea7522d5d614a5b/Tests/PocketPluginRuntimeTests.cs)

The format relies on source-level agreement rather than an explicit negotiated API version. At this research snapshot, no PDC plugin had been built or tested. Subsequent implementation and actual validation results are recorded in [the plugin guide](../tools/pocket-plugin/README.md).

## Proposed PDC implementation

This is a host-side usability improvement, not a reason to change the FPGA loader. The current loader permits `0x4000000` bytes (64 MiB). The importer accepts the exact supported 128 MiB PDC100 dump and keeps its first 64 MiB. Thus a raw dump renamed to `pdc100.rom` can exceed the limit even though the prepared file works. The commenter's actual file size has not been supplied, so this remains an explanation to check, not a reproduced diagnosis of their particular failure. [Loader definition](../tools/package_native.py), [importer](../tools/import_roms.py), [supported sizes and hashes](roms.md)

Use a small, separately versioned plugin repository. Rust with the reference Extism PDK is a practical choice: its runtime does not require users to install Python, and the common ABI and PlayStation example are available for comparison. Reuse only the small host/message pattern needed here; CD conversion, BIOS detection and multi-disc save handling are unrelated to PDC. Keep the current Python importer as a supported fallback and an independent comparison implementation. [Reference runtime](https://github.com/openfpga-library/pocket-plugin/tree/39dae308f7db00d77a4314fc76ad5d8d5b09b81b), [PlayStation implementation and headless testing](https://github.com/GuardianSoul/openfpga-PlayStation-plugin/tree/f690d399d4b354c07901b9ac590fe8cfddbbc918)

The first version should offer **Prepare local ROMs**, **Check installed ROMs**, and **Exit**, with the folder instructions visible in the menu. Proposed input placement is `Assets/pdc/import/`; outputs remain in `Assets/pdc/common/`, matching all ten existing launcher JSONs. Accept raw files and ZIP archives. Identify by exact supported size and hash, not extension, archive name or member name. Do not add a ROM downloader. Generate the plugin's profile data from the existing verified definitions, and make CI detect drift, rather than maintaining a second unrelated list. [Current profile definitions](../tools/package.py), [additional native profiles](../tools/rom_library.py), [release launchers](../tools/release.py)

| Profiles | Verified raw input | Prepared output |
| --- | ---: | ---: |
| PDC100 | 128 MiB | First 64 MiB, exactly 67,108,864 bytes |
| PDC30 Pink, PDC50, Oui-Oui | 16 MiB | Unchanged, 16 MiB |
| TMNT, Dora | 8 MiB | Unchanged, 8 MiB |
| VideoJet 1 and 4 | 2 MiB | Zero-padded to 8 MiB |
| VideoJet 2 and 3 | 4 MiB | Zero-padded to 8 MiB |

These recipes apply only after matching the supported original revision. PDC200 and Touch models remain unsupported. A same-sized unknown image must be rejected rather than truncated or padded speculatively. Checking an already prepared PDC100 file requires a trusted prepared-file hash: its 64 MiB size alone cannot establish identity, and the original 128 MiB hash cannot be recovered from it. Record prepared-file hashes from the verified reference outputs without distributing any ROM bytes. [Existing import rules](../tools/import_roms.py), [supported revisions and exclusions](roms.md)

Stream hashing, ZIP decoding and output rather than keeping several complete 128 MiB copies in WASM memory. Bound decoded member sizes to supported sizes and never extract archive paths: use fixed output filenames from the profile table. Leave originals intact, check available space before writing, create an owned temporary file, flush and verify its bytes, then publish the final filename. Report progress and a final prepared/already-correct/rejected/failed summary. Existing matching output should be a no-op; conflicting output must remain untouched. [Current no-overwrite and archive behavior](../tools/import_roms.py), [verified writes](../tools/rom_library.py), [upstream advice on interrupted writes](https://github.com/openfpga-library/pocket-plugin/blob/39dae308f7db00d77a4314fc76ad5d8d5b09b81b/README.md#tips)

Specifically detect a 128 MiB `Assets/pdc/common/pdc100.rom` and explain the correction: move that raw file into the input folder, then prepare it. Do not silently overwrite the only original or raise the loader limit. Keep a guided backup-and-replace repair out of the first version unless its interruption/recovery behavior is separately implemented and tested. Changes should remain confined to this core's documented import/output paths, leaving other cores, saves and user settings untouched. These are proposed plugin requirements, not features already implemented.

## PDC acceptance and test plan

Extend the current ROM-free importer/package tests; retain their existing checks for exact identity, padding, trimming, archive traversal, repeat runs and refusing differing output. Their synthetic fixtures are useful algorithm tests, but they do not establish that the final WASM supports every real profile. Do not introduce a production runtime option that disables hash verification to make tests pass. [Existing regression tests](../tests/test_release.py)

| Layer | Required test and acceptance evidence |
| --- | --- |
| Public unit tests | Synthetic profile fixtures exercise exact hash/size matching, identity copy, prefix trimming and zero padding. Same-size wrong data, truncated input and unsupported profiles are rejected. |
| ZIP input | Stored/deflated members, multiple supported profiles, renamed members and duplicate entries are deterministic. Corrupt/encrypted/oversized entries produce useful errors. Traversal filenames cannot write outside the fixed output directory. Bound actual decompressed bytes, not just the ZIP directory's declared sizes. |
| Existing data | Correct output is unchanged on rerun. Conflicting output is not overwritten. Misnamed raw PDC100 gets an actionable message. Sources, unrelated files, saves and other cores have identical hashes before and after. |
| Interruption and storage | On a disposable exFAT disk image, test insufficient space, a write failure, timeout/termination during each write phase, and rerun cleanup. A final `.rom` is either verified complete or absent; temporary cleanup affects only files owned by the plugin. |
| Actual WASM protocol | Exercise `start`, choices, invalid answers and string `Kill`/`Exit` through an Extism host on temporary card/host folders. Verify logs, no network capability, correct mounted paths, spaces/non-ASCII names and safe exit with a missing core or empty input folder. |
| Private ten-profile parity | Use the exact supported local raw dumps and ZIPs in ignored fixtures. Run the existing Python importer and the **release-built WASM** on separate temporary cards; compare every prepared byte and filename, plus independently expected hashes, sizes and padding. Do not upload ROMs or generated game files as CI artifacts. |
| Critical PDC100 case | The supported 134,217,728-byte raw dump produces a 67,108,864-byte output matching the established reference. The original's hash is unchanged. The resulting output fits the packaged loader limit, while the unprepared input does not. |
| Real host smoke tests | Run the same built plugin in pupdate and Pocket Sync on macOS and Windows. Separately verify fresh-core recommendations, explicit installation for existing users, manual run, repeat run and plugin update. Test ez-pocket's Review/Apply flow separately and record its platform/staging limits; do not advertise an untested host/platform combination. |
| Packaging | Run `make check-release` after the packaging changes. Verify the exact plugins-only recommendation, rejection of unexpected updater fields/URLs, unchanged ten launchers and loader limit, ROM-free ZIP, notices/checksums, and unchanged hardware bitstream. |
| Pocket smoke test | After automated checks, use backed-up prepared files on the device: PDC100 menu, start an action game, controls and audio, reset, then PDC50/TMNT and one padded VideoJet profile. Record firmware and prepared-file hashes. This verifies the preparation/install path, not a new claim of FPGA or game-wide qualification. |

The PlayStation project's test strategy is an appropriate precedent: its tests run the script and plugin on separate fixture cards and compare results. PDC needs the same end-to-end comparison with much smaller domain scope. Headless ABI tests do not replace actual host UI/install tests, and host tests do not replace checking the prepared ROM on Pocket. [PlayStation plugin tests](https://github.com/GuardianSoul/openfpga-PlayStation/blob/458d985dec8d239bda18bdf8dc980fb4e8935c5f/tests/test_pocket_plugin.py)

## Suggested delivery order

1. Implement the offline preparation/check engine and public synthetic tests; keep the CLI working.
2. Build the WASM, run headless protocol tests, then compare all ten private reference outputs byte for byte. Measure memory and elapsed time against the hosts' invocation limits, including the 128 MiB PDC100 case.
3. Run real pupdate/Pocket Sync smoke tests. Use local plugin discovery where supported; use a dedicated test repository's published non-prerelease only when testing the actual GitHub installation flow. Test ez-pocket separately rather than assuming compatibility from the ABI alone.
4. Publish the usable plugin release with the exact two assets, then make a deliberate metadata/documentation-only core patch that adds the validated `updaters.json` recommendation. Preserve the published v1.0.0 package and qualified bitstream; do not replace existing public assets silently. Reuse hardware evidence only after verifying its actual dependencies are unchanged. [Current release process](releasing.md), [bitstream/package validation](../tools/release.py)
5. Document both the recommendation path for new installs and the manual plugin installation/run steps for existing users. Keep local dump preparation separate from ROM sourcing. Announce the plugin only after these tests pass.

The PDC Library submission, issue **1887**, was still open with no comments when checked during this research. Plugin development and local testing do not require waiting for that issue to close; catalog installation and plugin preparation are separate stages. [Current submission](https://github.com/openfpga-library/analogue-pocket/issues/1887)
