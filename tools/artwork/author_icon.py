#!/usr/bin/env python3
"""Draw the C–C♯–D–D♯–E author mark on Pocket's 2×2 pixel grid."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[2]


def main():
    # Logical 18×18 canvas, exported as 36×36 without antialiasing.
    image = Image.new('L', (18, 18), 255)
    draw = ImageDraw.Draw(image)
    draw.rectangle((2, 3, 15, 14), fill=0)
    draw.rectangle((1, 4, 16, 13), fill=0)
    for left in (2, 7, 12):
        draw.rectangle((left, 4, left + 3, 13), fill=255)
    for left in (5, 10):
        draw.rectangle((left, 4, left + 2, 9), fill=0)
    image = image.resize((36, 36), Image.Resampling.NEAREST)
    assets = ROOT / 'docs/assets'
    image.save(assets / 'author-piano.png')
    rectangles = []
    for y in range(0, 36, 2):
        for x in range(0, 36, 2):
            if image.getpixel((x, y)) == 0:
                rectangles.append(f'  <rect x="{x}" y="{y}" width="2" height="2"/>')
    (assets / 'author-piano.svg').write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36" shape-rendering="crispEdges">\n'
        '  <title>Piano keys C, C sharp, D, D sharp, E</title>\n'
        '  <rect width="36" height="36" fill="white"/>\n' + '\n'.join(rectangles) + '\n</svg>\n')
    output = ROOT / 'build/artwork/author-piano'
    output.mkdir(parents=True, exist_ok=True)
    # APF: counterclockwise scan, brightness in the upper byte, low byte zero.
    # Match the pinned APF template: brightness byte first, then zero.
    # Dark marks in the preview become on pixels against an off background.
    rotated = ImageOps.invert(image).transpose(Image.Transpose.ROTATE_90)
    data = bytearray(36 * 36 * 2)
    data[::2] = rotated.tobytes()
    (output / 'icon.bin').write_bytes(data)
    decoded = ImageOps.invert(Image.frombytes('L', (36, 36), bytes(data[::2]))
                             .transpose(Image.Transpose.ROTATE_270))
    if decoded.tobytes() != image.tobytes() or set(image.tobytes()) != {0, 255}:
        raise ValueError('Author icon orientation/palette round trip failed.')
    preview = Image.new('L', (432, 216), 255)
    preview.paste(image.resize((216, 216), Image.Resampling.NEAREST), (0, 0))
    preview.paste(ImageOps.invert(image).resize((216, 216), Image.Resampling.NEAREST), (216, 0))
    preview.save(output / 'preview.png')
    print(f'Exported 36×36 piano icon, SVG, two-polarity preview and {len(data)}-byte APF icon.')


if __name__ == '__main__':
    main()
