"""Run from the repository root: python scripts/make_stripes.py Textures/Stripes.tga

Write WTF's Textures/Stripes.tga (the DoT prediction block's stripes): 32 x 32, uncompressed 32-bit BGRA,
white diagonal stripes (period 8 px, 4 px wide) at full alpha over gaps at
40% alpha, so a vertex color tints both and the stripes stay visible on any
bar color. It tiles seamlessly (32 is a multiple of the period)."""
import sys

SIZE, PERIOD, WIDTH = 32, 8, 4
STRIPE_ALPHA, GAP_ALPHA = 255, 102

header = bytes((0, 0, 2)) + bytes(9) + SIZE.to_bytes(2, "little") + SIZE.to_bytes(2, "little") + bytes((32, 0x28))
pixels = bytearray()
# Descriptor 0x28: 8 alpha bits, top-left origin, so row 0 is the top.
for y in range(SIZE):
    for x in range(SIZE):
        alpha = STRIPE_ALPHA if (x + y) % PERIOD < WIDTH else GAP_ALPHA
        pixels += bytes((255, 255, 255, alpha))
open(sys.argv[1], "wb").write(header + pixels)
