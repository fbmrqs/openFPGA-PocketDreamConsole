# Pocket release and updater research

Checked **15 October 2026** against upstream documentation, source and release ZIP directory listings. The repository is staged privately; no public release, community announcement or ROM download is part of this work.

## Recommended first release

Publish a ROM-free core ZIP and its matching source tag. Include the FPGA bitstream, APF configuration, platform artwork with a known redistribution basis, launch profiles, required notices and installation instructions. Users supply their own lawfully obtained dumps. Add a checksum-based local importer so filenames and supported revisions can be checked without downloading games. This follows the separation used by existing Pocket releases: the GBA core tells users to add BIOS and games themselves. [Spiritualized GBA installation](https://github.com/spiritualized1997/openFPGA-GBA#installation)

Do not describe the core as exhaustively cycle-perfect. The established evidence supports functional parity on the ten device-tested ROM profiles. State the actual tested hardware, audio/control/filter coverage and limitations, including the absence of save states. Keep private commercial ROMs, extracted data, WAVs and unlicensed screenshots out of source history and release assets.

## Release ZIP conventions and examples

A Pocket core is a bitstream plus JSON definitions. Analogue defines metadata, slots, input, audio, video and interaction files separately. Use the official names and schemas; JSON cannot contain commented-out debug entries. Remove diagnostic entries from the production menu and retain their definitions in development tooling if useful. [Analogue core definitions](https://www.analogue.co/developer/docs/openfpga/core-definition-files)

Two upstream release assets were inspected in memory, without retaining their contents:

| Core | Published release asset | ZIP root |
| --- | --- | --- |
| agg23 SNES 0.4.4 | `agg23.SNES_0.4.4_2024-09-16.zip` | `Assets/`, `Cores/`, `Platforms/` |
| Spiritualized GBA 1.2.0 | `Spiritualized_GBA_1.2.0_2022_08_25.zip` | `Assets/`, `Cores/`, `Platforms/`, readme |

Both have a core directory, APF JSON, reversed FPGA images and platform metadata/art under those roots, with empty common asset directories rather than bundled commercial games. Follow this arrangement with no enclosing project directory. The downloadable ZIP must be a GitHub Release asset; GitHub's automatically generated source archives are not installable core packages. [SNES release](https://github.com/agg23/openfpga-SNES/releases/tag/0.4.4), [GBA release](https://github.com/spiritualized1997/openFPGA-GBA/releases/tag/v1.2.0)

The SNES workflow separates synthesis and packaging, reverses the bitstream and uploads an installable release ZIP. Its pull-request path avoids publishing a release. For this project, keep the existing qualified bitstream and source-bound validation rather than recompiling an unchanged FPGA solely for documentation or menu cleanup. Release packaging should fail if required licensing or qualification evidence is missing. [Pinned SNES workflow](https://github.com/agg23/openfpga-SNES/blob/ad9fed4e9cbeee56f624ffcffc6477b2908daa3d/.github/workflows/build.yml)

Recommended published assets are one clearly named installable ZIP plus `SHA256SUMS`. If additional artifacts are attached, use an explicit ZIP-only asset filter when requesting inventory inclusion. Release notes should describe supported dumps and placement, firmware requirements, controls, filters, known limitations and source/build identification. Merging directories is necessary on macOS; blindly replacing an existing `Assets` or `Cores` directory can remove unrelated files. [SNES installation instructions](https://github.com/agg23/openfpga-SNES/releases/tag/0.4.4)

## Getting into pupdate

The old `openfpga-cores-inventory/analogue-pocket` repository redirects to **openfpga-library/analogue-pocket**, which backs the user's supplied [openFPGA Library](https://openfpga-library.github.io/analogue-pocket/). Its documented onboarding is an **Add Core issue**, providing the public GitHub repository. The issue form accepts an asset-filter regular expression for releases with several assets, or a repository path when distributing a ZIP directly from repository files. Having prepared metadata locally does not mean a core has been accepted or listed. [Library onboarding](https://github.com/openfpga-library/analogue-pocket#adding-a-new-core), [pinned issue form](https://github.com/openfpga-library/analogue-pocket/blob/f01e881341f4c8ba9e43e446e2d650230dcca766/.github/ISSUE_TEMPLATE/ADD-CORE.yml)

Current pupdate reads the Library v3 catalog, resolves the selected release and installs its `download_url`. Its local-catalog option reads `cores.json` and `platforms.json` beside pupdate. The normal public route is publishing the core release and submitting the Library issue, rather than requiring every user to edit an updater's source. [Pinned catalog/install implementation](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/services/CoresService.cs)

For this first release, do **not** populate `previous` automatically. The inspected pupdate calls `ReplaceCheck` after extraction; its replacement method uses `Directory.Move` on the old asset folder without merging into an existing destination. This package already creates the new launcher directory, so an installed Local predecessor can collide. Use backed-up manual retirement until an updater revision supports this case. [Pinned replacement implementation](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/services/CoresService.Replace.cs)

The optional core-directory `updaters.json` supports `previous` migration objects (each has `author`, `shortname`, `platform_id`) and `declare_ai`, an array naming AI tools used in development. Its `license.filename` field refers to an activation-key requirement, **not** the source-code license; omit it for this core. Preserve transparent development provenance. Current pupdate has user-selectable AI labels/filtering; inclusion is not a promise that every user's configuration will show the core. [Pinned updater metadata schema](https://github.com/openfpga-library/analogue-pocket/blob/f01e881341f4c8ba9e43e446e2d650230dcca766/.github/workflows/updater/lib/analogue/updaters.rb), [license requirement implementation](https://github.com/openfpga-library/analogue-pocket/blob/f01e881341f4c8ba9e43e446e2d650230dcca766/.github/workflows/updater/lib/inventory/release.rb), [pupdate filter documentation](https://github.com/mattpannella/pupdate#ai-generated-core-filter-experimental)

## How pupdate actually gets assets

Core installation and asset retrieval are separate operations. pupdate checks named slots in `data.json` and instance JSON, skips save files and blacklisted names, and searches the configured archive index. Instance slots resolve into `Assets/<platform>/common/`, preserving slot subdirectories. Named data slots may use the core-specific asset folder. A separate enabled core-specific archive stage can download a filtered set into `common/` and extract ZIP/7z files. This is not a ROM license or a universal game-search service. [Pinned download implementation](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/services/CoresService.Download.cs)

Archive lookup tries the platform/subdirectory filename, subdirectory filename, platform filename and bare filename. Standard archives use Internet Archive metadata and download endpoints. Custom archives supply an index URL and a base file URL; optional CRC validation checks the downloaded file, while MD5 also supports caching. A checksum identifies data; it does not establish permission. [Pinned archive implementation](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/services/ArchiveService.cs)

For a **future explicitly licensed** download collection, this is a schema-shaped example to add to the user's existing `archives` array, not a working source or a default configuration:

```json
{
  "name": "fbmrqs.PocketDreamConsole",
  "type": "core_specific_custom_archive",
  "archive_name": "pocketdream-authorized-v1",
  "url": "https://example.invalid/authorized-assets",
  "index": "index.json",
  "files": ["licensed-demo.bin"],
  "enabled": false,
  "one_time": false
}
```

`name` matches the actual published core ID. `archive_name` is also used as an in-memory/cache identity, so give it a distinct stable value. The type can instead be `core_specific_archive` with an Internet Archive item identifier in `archive_name`. `files` and `file_extensions` are alternative filters; do not set both. Other supported fields include `archive_folder`, `has_instance_jsons`, `complete` and the shown enable/one-time controls. [Pinned archive settings model](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/models/Settings/Archive.cs)

The custom index uses an object with a `files` array, with each file containing `name`, `md5`, `crc32` and optionally `source`; the surrounding model also accepts `files_count` and `item_last_updated`. Values must describe actual authorized bytes. [Archive index model](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/models/Archive/Archive.cs), [file model](https://github.com/mattpannella/pupdate/blob/a9b44d2e8762a5bb97340d1f6b91415f096c7afa/src/models/Archive/File.cs)

No rights-cleared download source for the commercial PDC dumps was established by this research. For the first release, recommend manual/local import only. Future options are written permission from rights holders, explicitly redistributable homebrew or original test/demo ROMs with a compatible license. Do not substitute a third-party mirror for that permission.

## Copyright and art

Moving a ROM to another server, naming an Internet Archive item or fetching it through pupdate does not itself grant redistribution rights. UK guidance distinguishes owning a copy from permission to copy, distribute or publish protected material. Apply the same review to title-screen art and music. The exact position for dumping, interoperability and publication depends on the facts and jurisdiction; no blanket legality claim is made here. [UK copyright overview](https://www.gov.uk/copyright/overview), [using somebody else's material](https://www.gov.uk/using-somebody-elses-intellectual-property/copyright)

The supplied Reddit post concerns title-screen images for the Pocket **cartridge Library** detail screen, copied under `System/Library/Images`. It is not a source of game programs, a core inventory or evidence that arbitrary openFPGA launchers gain Library entries. Treat it as presentation inspiration; use original project art or obtain permission for anything included in the release. [Original Library image-set announcement](https://www.reddit.com/r/AnalogueInc/comments/wbcvpp/analogue_pocket_library_image_set/)

## Where to announce

1. Publish one canonical GitHub release with installation instructions and an issue template for firmware, ROM hash/profile, game/scene and reproduction steps.
2. Request Library inclusion through its Add Core issue; this is the practical discovery/updater route.
3. Announce in **r/AnaloguePocket**, which already hosts core releases. Link the release and a short device demonstration. Its rules prohibit requesting or sharing ROM-download information. **r/fpgagaming** and **r/AnalogueInc** are also linked by that community and are reasonable secondary audiences; check each community's rules before posting. [Community and rules](https://www.reddit.com/r/AnaloguePocket/)
4. Link the same release from YouTube demonstrations. Show the device, supported hardware families, controls and a few representative games; clearly state that ROMs are supplied separately.

FPGAming Discord is mentioned in older developer discussions, but this check did not verify a current first-party invite or channel policy. Obtain a current invite through the community rather than publishing an unverified invitation. No announcement messages were sent.

## Source snapshots

- pupdate: `a9b44d2e8762a5bb97340d1f6b91415f096c7afa`.
- openFPGA Library: `f01e881341f4c8ba9e43e446e2d650230dcca766`.
- SNES workflow: `ad9fed4e9cbeee56f624ffcffc6477b2908daa3d`; released ZIP inspected at tag `0.4.4`.
- Spiritualized GBA: `61ce0c8d3c77c65ff1e28fcfa587173b44eb03fa`; released ZIP inspected at tag `v1.2.0`.

These upstream details can change. Recheck inventory submission and updater configuration when the public release is actually published.
