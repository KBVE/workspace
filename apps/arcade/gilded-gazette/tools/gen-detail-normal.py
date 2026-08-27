#!/usr/bin/env python3
"""Tiling detail normal for the carriage shader based upon kbve's detail noramls.

Why it exists? the carriage atlas gives 59 (about~ depends I did switch) texels/m over 697 m2 of surface, and no atlas size fixes that inside a web budget, thus ducking lag!!!!
The solution? UV density is uniform across the model, so sampling this at UV * k lands at a const phys freq && helps with the atlas rez.

Fractal value noise, NOT sine harmonics, then blurred on a 3x3 tiling and cropped so every octave wraps, most of this code is from kbve pip package, just scoped down and tweaked.
usage here -> python3 tools/gen-detail-normal.py godot/assets/train/detail_normal.png or probably ./kbve.sh calls to nx's uv, that will give you even better performance but that stuff is black magic wizard shit.
"""

from __future__ import annotations

import random
import sys
from pathlib import Path
from typing import Final, TypeAlias

import numpy as np
from numpy.typing import NDArray
from PIL import Image, ImageFilter

Octave: TypeAlias = tuple[float, float]  # &(blur radius, weight)
HeightMap: TypeAlias = NDArray[np.float64]  # &(N, N) in roughly [-1, 1]

N: Final = 512
SEED: Final = 31
SLOPE: Final = 1.5
OCTAVES: Final[tuple[Octave, ...]] = ((1.0, 1.0), (2.5, 0.7), (6.0, 0.45), (14.0, 0.28))


def to_u8(values: NDArray[np.float64]) -> NDArray[np.uint8]:
    # &truncating cast, not round -> keeps output byte-identical to the list build
    return np.clip(values, 0, 255).astype(np.uint8)


def tiled_blur(values: HeightMap, radius: float) -> HeightMap:
    """Blur across a 3x3 tiling and crop the centre, so the result wraps."""
    tile = Image.fromarray(to_u8(128.0 + values * 127.0), "L")
    big = Image.new("L", (N * 3, N * 3))
    for i in range(3):
        for j in range(3):
            big.paste(tile, (i * N, j * N))
    mid = big.filter(ImageFilter.GaussianBlur(radius)).crop((N, N, N * 2, N * 2))
    return (np.asarray(mid, dtype=np.float64) - 128.0) / 127.0


def heightmap() -> HeightMap:
    # &local Random -> no global RNG mutation; gauss stream keeps the field reproducible
    rng = random.Random(SEED)
    base = np.fromiter((rng.gauss(0.0, 1.0) for _ in range(N * N)), np.float64, N * N)
    base = base.reshape(N, N)

    field = np.zeros((N, N), dtype=np.float64)
    for radius, weight in OCTAVES:
        octave = tiled_blur(base, radius)
        peak = max(1e-6, float(np.abs(octave).max()))
        field += (octave / peak) * weight
    return field / sum(weight for _, weight in OCTAVES)


def normal_map(field: HeightMap) -> Image.Image:
    # &np.roll wraps -> the (x +- 1) % N sampling, vectorised
    dx = np.roll(field, -1, axis=1) - np.roll(field, 1, axis=1)
    dy = np.roll(field, -1, axis=0) - np.roll(field, 1, axis=0)

    nx = -dx * SLOPE
    ny = -dy * SLOPE
    m = np.sqrt(nx * nx + ny * ny + 1.0)

    rgb = np.stack((nx / m, ny / m, 1.0 / m), axis=-1)
    return Image.fromarray(to_u8((rgb * 0.5 + 0.5) * 255.0), "RGB")


def main(out: Path) -> None:
    normal_map(heightmap()).save(out)
    print(f"wrote {out} ({N}x{N})")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("godot/assets/train/detail_normal.png"))
