#!/usr/bin/env python3
"""Rasterise Natural Earth land polygons into a compact land mask.

The game embeds the output with `include_str!`, so it ships no GeoJSON parser
and no runtime asset load. Run this only when the source data or the mask
resolution changes; the generated file is committed.

    python3 tools/gen_earth_mask.py ne_10m_land.geojson src/core/earth_mask.txt 1024

Width defaults to 1024 and height is always half of it, because the mask is
equirectangular and any other ratio would stretch it.

Source: https://github.com/nvkelso/natural-earth-vector (public domain, CC0).

The mask is equirectangular: column 0 is longitude -180, row 0 is latitude +90.
That projection is why it drops straight onto a wrapping hex map -- longitude is
already cyclic, so the east-west seam needs no special handling.

Resolution is deliberately higher than any map we generate, so a map samples it
by nearest neighbour rather than the mask having to match a map size.

Scanline fill, not point-in-polygon. Testing every cell against every polygon is
O(cells x edges) and takes tens of minutes at 10m detail; intersecting each row
with the edge set once is O(rows x edges) and takes seconds. The even-odd rule
also handles holes -- lakes, inland seas -- without treating them separately,
because a hole's edges flip parity exactly like an outer ring's do.
"""

import json
import sys

WIDTH = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
HEIGHT = WIDTH // 2


def edges(data):
    """Every polygon edge in the file, as (y0, y1, x0, x1)."""
    out = []
    for feature in data["features"]:
        geometry = feature["geometry"]
        if geometry["type"] == "Polygon":
            polys = [geometry["coordinates"]]
        elif geometry["type"] == "MultiPolygon":
            polys = geometry["coordinates"]
        else:
            continue
        for poly in polys:
            for ring in poly:
                for i in range(len(ring)):
                    x0, y0 = ring[i - 1][0], ring[i - 1][1]
                    x1, y1 = ring[i][0], ring[i][1]
                    if y0 != y1:
                        out.append((y0, y1, x0, x1))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = json.load(open(src))
    edge_list = edges(data)

    # Bucket edges by the rows they span, so each row only tests the edges that
    # can actually cross it rather than all of them.
    buckets = [[] for _ in range(HEIGHT)]

    def row_of(lat):
        return (90.0 - lat) * HEIGHT / 180.0

    for y0, y1, x0, x1 in edge_list:
        lo, hi = sorted((row_of(y0), row_of(y1)))
        first = max(0, int(lo))
        last = min(HEIGHT - 1, int(hi) + 1)
        for row in range(first, last + 1):
            buckets[row].append((y0, y1, x0, x1))

    rows = []
    for row in range(HEIGHT):
        # Sample the centre of the row, not its edge.
        lat = 90.0 - (row + 0.5) * 180.0 / HEIGHT

        crossings = []
        for y0, y1, x0, x1 in buckets[row]:
            if (y0 > lat) != (y1 > lat):
                crossings.append(x0 + (lat - y0) * (x1 - x0) / (y1 - y0))
        crossings.sort()

        line = bytearray(b"." * WIDTH)
        # Even-odd: fill between alternating pairs of crossings.
        for i in range(0, len(crossings) - 1, 2):
            xa, xb = crossings[i], crossings[i + 1]
            # Longitude to column, taking cells whose centre lies in the span.
            ca = int((xa + 180.0) * WIDTH / 360.0 - 0.5 + 0.9999)
            cb = int((xb + 180.0) * WIDTH / 360.0 - 0.5)
            for col in range(max(0, ca), min(WIDTH - 1, cb) + 1):
                line[col] = ord("#")
        rows.append(line.decode())

    with open(dst, "w") as f:
        f.write("\n".join(rows) + "\n")

    filled = sum(r.count("#") for r in rows)
    total = WIDTH * HEIGHT
    print(f"{dst}: {WIDTH}x{HEIGHT}, land {filled}/{total} = {filled / total:.1%}")


if __name__ == "__main__":
    main()
