# Supported ROM dumps

No ROMs are distributed or downloaded. Supply local dumps you are entitled to use.
The importer checks exact sizes and SHA-1 hashes; matching a filename is not enough.

## Import

Download/clone the source tools and use Python 3.11 or newer:

```sh
python3 tools/import_roms.py /path/to/pdc50.zip /path/to/pdc_pink.u2 \
  --output /path/to/card/Assets/pdc/common
```

You may import one game at a time. ZIPs are read without extracting their paths;
raw dumps also work. Existing matching output is accepted, but a differing file
is never overwritten. The source dump/archive remains untouched. If preparing
locally, copy the resulting `.rom` files into the card’s `Assets/pdc/common/`.
Only launch profiles whose corresponding ROM you have supplied. The ROM-free ZIP
contains all ten launcher JSONs, so a missing file produces a load error.

## Exact supported revisions

| Profile | Raw size (bytes) | Source SHA-1 | Prepared filename |
| --- | ---: | --- | --- |
| PDC100 | 134217728 | `cfb4be7877ec263d24063a004c56985db5c0f4e2` | `pdc100.rom` |
| PDC30 Pink | 16777216 | `5b423d589358dd53a2e5765bcb94da2d44200e56` | `pdc30.rom` |
| PDC50 | 16777216 | `81d2ff5af7b6dc5e1f9277b45f259762e7d24cce` | `pdc50.rom` |
| Oui-Oui | 16777216 | `de0695c240fdc2edc67694ceacaed093e6693767` | `ouipdc.rom` |
| Teenage Mutant Ninja Turtles | 8388608 | `7620f1b7aeaec8032faa8eb7552f775e8d6d14ba` | `tmntpdc.rom` |
| Dora | 8388608 | `b6ac8ea186d7c624451dd6121932cecb38c1f25f` | `dorapdc.rom` |
| VideoJet TV Games 1 | 2097152 | `3cf6fddcfdd1f858e775976f690b32deef1de67f` | `vjpp1.rom` |
| VideoJet TV Games 2 | 4194304 | `9b537205808c502cf872e62f9701357ef8e28f3c` | `vjpp2.rom` |
| VideoJet TV Games 3 | 4194304 | `59279e54e5d9ac2f956241e78dffe526b5de14fd` | `vjpp3.rom` |
| VideoJet TV Games 4 | 2097152 | `0ffb606d4ac93da27a671b369800ea71e68452f3` | `vjpp4.rom` |

PDC100 uses the first 64 MiB of its 128 MiB physical dump; the unused upper half
is omitted. VideoJet 1/4 are zero-padded from 2 MiB to 8 MiB, and VideoJet 2/3
from 4 MiB to 8 MiB. Other supported dumps keep their bytes and size. These are
container/loader preparation steps, not game-code patches.

PDC200, PDC40 Touch and PDC150 Touch are unsupported. Keep their dumps separate;
renaming them cannot make them compatible. Other ROM revisions need independent
identification and validation before adding launch profiles.

## Updates and ROM sourcing

The FPGA can load the prepared file without an external BIOS. The core’s startup
CRC checks reject mismatched known profiles; a black screen or load error is not
a reason to bypass verification. Report the profile and source hash instead.

pupdate can update the core after public Library inclusion. Its separate archive
feature does not confer rights to game files. No authorized downloadable PDC ROM
collection was established here, so this release uses local import. Rights-holder
permission, licensed homebrew or original compatible demos could support a future
optional download source. See [release research](release-research.md).
