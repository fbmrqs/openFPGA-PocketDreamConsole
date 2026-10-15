# Handheld artwork

The procedural Blender model originates from the supplied `isometric-handheld`
project. The portable layout follows the supplied 521 × 165 examples: left edge
x=131, width 118 pixels and bottom baseline y=137. The current model's nonwhite
bounds are `(131, 68, 249, 137)`; the device geometry determines its top edge.

The orthographic camera uses a 30.4 scale, horizontal shift `70.5/521` and vertical
shift `21/521`. Flat Workbench shading, seven grayscale materials and disabled
antialiasing preserve the pixel style. Small geometric details snap to the native
pixel grid after camera placement. No texture/model imports are used.

With Blender 5.0 and Python/Pillow available:

```sh
blender --background --python tools/artwork/build_model.py
python3 tools/artwork/export.py build/artwork/pdc.png
```

The Blender script retains editable `.blend` and `.glb` files under ignored
`build/artwork/`. The exporter checks dimensions, palette and placement, writes
the native PNG and exact nearest-neighbor 3× README banner under `docs/assets/`,
and writes `release/pdc-platform.bin`. That public graphic is the sole exception
to the repository's binary-dump exclusion. It is 171,930 bytes: rotated 90°
counterclockwise, with one brightness byte followed by zero for each pixel.
The release packager validates this format and includes it in
`Platforms/_images/pdc.bin`; it does not change the FPGA binary.
