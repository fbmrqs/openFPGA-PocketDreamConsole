# Changelog

## 1.0.0 — 2026-10-15

- Prepare the first ROM-free GitHub release under `fbmrqs.PocketDreamConsole`.
- Confirm PDC30 Pink, PDC50, PDC100, TMNT, Oui-Oui, Dora and VideoJet TV Games 1–4
  on the Pocket, including full-speed gameplay, graphics and audio.
- Retain black startup, corrected mixed-sprite priority, globally swapped A/B
  and the sixteen selected display modes in a single entry.
- Omit diagnostic readouts, retired runtime binaries and borrowed runtime art.
- Include the procedural handheld platform image with the portable layout,
  matching README banner and reproducible Blender generator.
- Add local dump import, source/binary provenance, archive checksums, licensing
  notices, updater metadata, contribution guidance and ROM-free CI checks.

The FPGA binary is the unchanged hardware-confirmed build from source `3d287a2`.
This release changes packaging and documentation only. Save states, sleep/resume,
Dock output and unsupported hardware profiles remain deferred.

## Development builds

Versions 0.1.x–0.2.1 were private software/FPGA development packages. Their dated
results and superseded candidates are preserved in `docs/native-fpga.md` and
`docs/native-refinements.md`. Private ROM-inclusive ZIPs are not public releases.
