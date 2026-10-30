# Changelog

## 1.0.1 — 2026-10-30

- Implement an offline shared updater plugin for preparing/checking the ten
  supported ROM profiles, including PDC100 trimming and VideoJet padding.
- Prepare and verify automatically on normal runs, including unattended pupdate;
  retain confirmation for unfinished-file cleanup and retry automatically after it.
- Add release-built WASM checks and strict plugins-only recommendation metadata.
  The core update changes packaging and instructions; its FPGA binary is
  byte-identical to v1.0.0. Existing v1.0.0 assets remain available unchanged.

## 1.0.0 — 2026-10-29

- Prepare the first ROM-free GitHub release under `fbmrqs.PocketDreamConsole`.
- Confirm PDC30 Pink, PDC50, PDC100, TMNT, Oui-Oui, Dora and VideoJet TV Games 1–4
  on the Pocket, including full-speed gameplay, graphics and audio.
- Retain black startup, corrected mixed-sprite priority, globally swapped A/B
  and the sixteen selected display modes in a single entry.
- Omit diagnostic readouts, retired runtime binaries and borrowed runtime art.
- Include the procedural handheld platform image with the portable layout,
  matching README banner and reproducible Blender generator.
- Correct the platform graphic's stored brightness polarity for Pocket display;
  keep normal PNG colours and add a reference-decoder regression check.
- Add local dump import, source/binary provenance, archive checksums, licensing
  notices, updater metadata, contribution guidance and ROM-free CI checks.

The FPGA binary is the unchanged hardware-confirmed build from source `16f3d84`.
This release changes packaging and documentation only. It enables Dock output,
confirmed on the Dock with HDMI video, audio, controller 1 and every display
filter, and adds a piano author icon. Save states, sleep/resume and unsupported
hardware profiles remain deferred.

## Development builds

Versions 0.1.x–0.2.1 were private software/FPGA development packages. Their dated
results and superseded candidates are preserved in `docs/native-fpga.md` and
`docs/native-refinements.md`. Private ROM-inclusive ZIPs are not public releases.
