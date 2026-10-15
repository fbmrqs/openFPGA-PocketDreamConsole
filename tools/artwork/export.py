#!/usr/bin/env python3
"""Export the Blender render as a pixel banner and Pocket platform image."""
import argparse
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
PALETTE = {0, 41, 88, 143, 185, 242, 255}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('render', type=Path)
    args = parser.parse_args()
    with Image.open(args.render) as source:
        image = source.convert('RGB')
    if image.size != (521, 165):
        raise ValueError('The native platform render must be 521 × 165.')
    pixels = image.load()
    if any(r != g or g != b or r not in PALETTE
           for y in range(image.height) for x in range(image.width)
           for r, g, b in [pixels[x, y]]):
        raise ValueError('The native render must use the seven grayscale tones without antialiasing.')
    bounds = ImageChops.difference(image, Image.new('RGB', image.size, 'white')).getbbox()
    if bounds is None or bounds[0] != 131 or bounds[2] - bounds[0] != 118 or bounds[3] != 137:
        raise ValueError('Portable placement must retain x=131, width=118 and bottom baseline y=137.')
    assets = ROOT / 'docs/assets'
    assets.mkdir(parents=True, exist_ok=True)
    image.save(assets / 'handheld-platform.png')
    image.resize((1563, 495), Image.Resampling.NEAREST).save(assets / 'handheld-banner.png')
    # APF stores pixels rotated counterclockwise, with brightness then a zero byte.
    rotated = image.transpose(Image.Transpose.ROTATE_90).convert('L')
    data = bytearray(rotated.width * rotated.height * 2)
    data[::2] = rotated.tobytes()
    (ROOT / 'release/pdc-platform.bin').write_bytes(data)
    print(f'Exported native platform image, exact 3× banner and {len(data)}-byte APF graphic.')


if __name__ == '__main__':
    main()
