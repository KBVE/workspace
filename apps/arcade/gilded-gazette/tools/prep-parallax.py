#!/usr/bin/env python3
"""Downscale the Parallax Forest layers into godot/assets/backdrop/.

Source: Digital Moon Studio, "Parallax Forest Background (Seamless)".

This script is to reduce the VRAM usage of the source material.

    python3 tools/prep-parallax.py "~/Downloads/Parallax Forest Background (Seamless)-2"
"""
import os
import sys
import glob

from PIL import Image

WIDTH = 1024
HEIGHT = 576
OUT = "godot/assets/backdrop"


def main(src):
    src = os.path.expanduser(src)
    layers = sorted(glob.glob(os.path.join(src, "Parallax Forest Background - Blue", "*.png")))
    if not layers:
        raise SystemExit(f"no layers found under {src}")
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for f in layers:
        name = os.path.basename(f).lower()
        im = Image.open(f).convert("RGBA").resize((WIDTH, HEIGHT), Image.LANCZOS)
        dst = os.path.join(OUT, name)
        im.save(dst, optimize=True)
        total += os.path.getsize(dst)
        # a resize must not break the horizontal wrap
        px = im.load()
        col = lambda x: [px[x, y] for y in range(HEIGHT)]
        mad = lambda a, b: sum(abs(i - j) for u, v in zip(a, b) for i, j in zip(u, v)) / (len(a) * 4)
        wrap, near = mad(col(WIDTH - 1), col(0)), mad(col(600), col(601))
        flag = "seamless" if wrap <= max(near * 3, 1.0) else "SEAM"
        print(f"  {name:20} {WIDTH}x{HEIGHT}  wrap {wrap:5.2f} vs {near:5.2f}  {flag}")
    print(f"  total on disk {total / 1048576:.2f} MB")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/Parallax Forest Background (Seamless)-2")
