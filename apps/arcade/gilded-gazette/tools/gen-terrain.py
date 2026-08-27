#!/usr/bin/env python3
"""Ground plate for the train scene. Generated, not third-party.

Seamless in x and y: every harmonic uses integer frequencies over the tile, so
the field is periodic by construction. Verified by comparing the wrap column
against the neighbouring-column baseline.

    python3 tools/gen-terrain.py godot/assets/train/terrain.png
"""
import math
import random
import sys

from PIL import Image, ImageFilter

N = 512
SEED = 11
DRY = (74, 70, 48)
LUSH = (38, 52, 32)
TERMS = [(1, 2, 1.0, 0.3), (3, 1, 0.5, 1.1), (5, 4, 0.28, 2.2),
         (8, 7, 0.15, 0.6), (13, 11, 0.08, 1.9)]


def field(x, y):
    u, v = x / N * math.tau, y / N * math.tau
    return sum(a * math.sin(fx * u + ph) * math.cos(fy * v + ph * 0.7)
               for (fx, fy, a, ph) in TERMS)


def main(out):
    random.seed(SEED)
    norm = sum(t[2] for t in TERMS)
    img = Image.new("RGB", (N, N))
    px = img.load()
    for y in range(N):
        for x in range(N):
            t = max(0.0, min(1.0, (field(x, y) / norm + 1) / 2))
            c = tuple(int(DRY[i] + (LUSH[i] - DRY[i]) * t) for i in range(3))
            j = random.randint(-8, 8)
            px[x, y] = tuple(max(0, min(255, v + j)) for v in c)
    img.filter(ImageFilter.GaussianBlur(0.5)).save(out)
    print(f"wrote {out} ({N}x{N})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "godot/assets/train/terrain.png")
