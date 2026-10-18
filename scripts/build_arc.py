#!/usr/bin/env python3
"""Build the shield display's segmented crescents.

Textures/ShieldArc.tga is the outer crescent (the absorb total);
Textures/ShieldArcInner.tga is a thinner one nested inside it (Mana Shield,
which has no absorb amount, draining with time); Textures/ShieldArcInnermost.tga
is inside that (bubbles: immunities with only a duration). Each is a white
crescent on the right of a transparent square, cut into segments by thin gaps,
with anti-aliased edges, as an uncompressed 32-bit TGA (top-left origin). The
display tints them and fills them from the bottom with vertical StatusBars,
after NaN Shield. A StatusBar fills its whole height, so each crescent is
stretched to span its texture from top to bottom, and the display draws it
at the crescent's own height (span in Shield.lua): a bar then empties
exactly when its value reaches 0, not a segment early. All share one center,
so they line up when drawn that way. Python 3 standard library only; the
output is byte-for-byte deterministic.
"""

import argparse
import math
from pathlib import Path

SIZE = 128
# The crescents are parts of rings whose center lies left of the texture,
# halfway up each crescent.
CENTER_X = 8.0
# Segments: SEGMENT - GAP pixels tall with a GAP pixel gap between them, the
# first at the bottom and the last at the top, so no gap ends a crescent.
SEGMENT = 8.0
GAP = 2.0
# Samples per pixel side for anti-aliasing.
SUPERSAMPLE = 4
TEXTURES = Path(__file__).resolve().parent.parent / "Textures"
# name: (outer radius, inner radius, segments). A crescent is
# segments * SEGMENT - GAP pixels tall, drawn centered in the square.
CRESCENTS = {
    "ShieldArc.tga": (112.0, 96.0, 15),
    "ShieldArcInner.tga": (91.0, 83.0, 12),
    "ShieldArcInnermost.tga": (78.0, 71.0, 9),
}


def height(segments):
    return segments * SEGMENT - GAP


def span(name):
    """The crescent's height as a fraction of the square: Shield.lua's span."""
    return height(CRESCENTS[name][2]) / SIZE


def inside(px, rise, outer, inner, segments):
    """Whether a point is in the crescent; rise is its height above the crescent's foot."""
    if px < CENTER_X or rise % SEGMENT >= SEGMENT - GAP:
        return False
    distance = math.hypot(px - CENTER_X, rise - height(segments) / 2)
    return inner <= distance <= outer


def coverage(x, y, shape):
    """The fraction of pixel (x, y) inside the crescent, stretched to the texture's height."""
    tall = height(shape[2])
    hits = 0
    for sx in range(SUPERSAMPLE):
        for sy in range(SUPERSAMPLE):
            rise = (SIZE - y - (sy + 0.5) / SUPERSAMPLE) / SIZE * tall
            if inside(x + (sx + 0.5) / SUPERSAMPLE - 0.5, rise, *shape):
                hits += 1
    return hits / (SUPERSAMPLE * SUPERSAMPLE)


def build(name="ShieldArc.tga"):
    shape = CRESCENTS[name]
    header = bytes((0, 0, 2)) + bytes(9) + SIZE.to_bytes(2, "little") + SIZE.to_bytes(2, "little") \
        + bytes((32, 0x28))
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            alpha = round(coverage(x, y, shape) * 255)
            # BGRA: white, so the display's vertex color sets the tint.
            pixels += bytes((255, 255, 255, alpha))
    return header + bytes(pixels)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=TEXTURES)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name in CRESCENTS:
        (args.output_dir / name).write_bytes(build(name))


if __name__ == "__main__":
    main()
