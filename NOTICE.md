# Licenses and acknowledgments

The project's own source and documentation are available under [ISC](LICENSE).
Third-party material retains its original notices and license. This is a mixed
license project; ISC does not replace the terms of the Pocket framework or FPGA IP.

## Native FPGA core and reference implementation

| Component | Provenance | License / notice |
| --- | --- | --- |
| Sunplus software reference; instruction and peripheral semantics | [Simon Eriksson's veesem](https://github.com/sp1187/veesem/tree/42fb8f07e7418f16ccfb7364127aef2217dda641) | [ISC, copyright 2024–2026 Simon Eriksson](third_party/veesem/LICENSE); [local changes](third_party/veesem/README.md) |
| PSRAM controller | [Adam Gastineau's analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils/tree/78482d1b363606336f4535aa0adc2e957bc20558) | [MIT, copyright 2022 Adam Gastineau](third_party/pocket/psram-LICENSE) |
| APF shell, bridge handler and SDRAM controller | [Analogue core template](https://github.com/open-fpga/core-template/tree/da3a021b1eaf742604d86d8dc9b33a6666263e6a), [openfpgaCore](https://github.com/openfpgaOS/openfpgaCore/tree/618a3eb) | [Analogue Pocket Framework agreement](third_party/pocket/sdram-LICENSE), including its referenced EULA |
| Altera/Intel PLL, memory and I/O primitives | Quartus Prime / Cyclone V IP | [FPGA IP notice](third_party/runtime/LicenseRef-Intel-FPGA-IP.txt); use remains subject to applicable vendor terms |
| Board behavior reference | [MAME PDC driver](https://github.com/mamedev/mame/blob/master/src/mame/tvgames/spg2xx_pdc.cpp) | Consult the upstream file's BSD-3-Clause notice when reusing its source |

Modifications to the vendored memory controllers and bridge handler are recorded
in [third_party/pocket/README.md](third_party/pocket/README.md). The public binary
package retains the applicable notices inside its core directory. Analogue's
framework license is restricted to its products/services; the complete project
must not be described as universally ISC-licensed or hardware-independent IP.

## Historical software target

The retired software target uses the pinned openfpgaSDK and openfpgaOS runtime.
Their Apache-2.0 and component-specific notices remain in `third_party/runtime/`.
Those runtime binaries, their images, and the former developer's icon are not
included in the native public release. Retained GPL notices describe components
of that historical runtime, not a blanket license for the native RTL.

## Game data and presentation

No game ROMs, BIOS dumps, extracted music, screenshots, box art, or copyrighted
title-screen images are distributed. Game and product names identify compatible
hardware/software; no endorsement or affiliation is implied. The public package
omits the previous runtime's author icon and platform image rather than presenting
them as this project's identity. Optional new artwork needs its own provenance.

The README banner, `docs/assets/handheld-banner.png`, is the supplied v4 render
from the local `isometric-handheld` artwork project. Its `build_model.py` builds
editable handheld geometry and seven grayscale materials in Blender, using an
orthographic camera, flat Workbench shading and no antialiasing. The 521 × 165
render is enlarged exactly 3× with nearest-neighbor pixels to 1563 × 495. The
script loads no external textures or models; the illustration has a blank screen.

Development used OpenAI Codex; upstream attribution and licenses remain intact.
Hardware confirmation is user-reported testing, not certification by Analogue,
Conny, VideoJet, Anncia, or game rights holders.
