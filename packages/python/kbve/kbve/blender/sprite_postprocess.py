#!/usr/bin/env python3
"""Post-process baked sprite frames: bake a soft ground shadow, then stitch.

Runs in normal (non-Blender) python because it needs Pillow. `model_sprites.py`
shells out to it after rendering; it can also be run standalone on any dir of
`frame_NN.png` files.

The shadow is derived from each frame's own alpha silhouette — squashed toward the
contact line, offset along the light direction, blurred, and darkened — then the
ship is composited back on top. No 3D / engine dependency, so it works for any
model the baker can render.

Usage:
    uv run kbve-sprite-postprocess --dir render_flat --res 512 \
        [--shadow-alpha 0.38 --shadow-blur 0.05 --shadow-squash 0.55 \
         --shadow-dx 0.04 --shadow-dy 0.06 --no-shadow]
"""
import argparse
import glob
import math
import os

# Pillow is imported inside the functions that need it, not here. `layout` is
# the sheet grid's one definition and `model_sprites` reads it from inside
# Blender, whose bundled python has no Pillow -- a module-level import would
# make loading this file for that one function raise.


def parse_args():
    p = argparse.ArgumentParser(prog="kbve-sprite-postprocess")
    p.add_argument("--dir", required=True, help="dir of frame_NN.png")
    p.add_argument("--res", type=int, required=True, help="px per frame (square)")
    p.add_argument("--cols", type=int, default=0,
                   help="sheet columns (0 = square auto). Set to anim-frames for a directions x frames grid")
    p.add_argument("--no-shadow", action="store_true", help="skip the baked shadow")
    # shadow knobs are fractions of frame size, so they scale with --res
    p.add_argument("--shadow-alpha", type=float, default=0.45, help="darkness 0..1")
    p.add_argument("--shadow-blur", type=float, default=0.06, help="blur radius / frame")
    p.add_argument("--shadow-squash", type=float, default=0.7, help="vertical flatten 0..1")
    p.add_argument("--shadow-shear", type=float, default=0.15, help="iso ground skew (x per y about base)")
    p.add_argument("--shadow-grow", type=float, default=0.05, help="dilate silhouette / frame (rim halo)")
    p.add_argument("--shadow-dx", type=float, default=0.0, help="x offset / frame (light dir)")
    p.add_argument("--shadow-dy", type=float, default=0.045, help="y offset / frame (toward bottom)")
    # --- foam: a bright line where the subject meets the water ---
    p.add_argument("--foam", action="store_true",
                   help="bake a foam line along the bottom edge of the silhouette")
    p.add_argument("--foam-alpha", type=float, default=0.40, help="foam opacity 0..1")
    p.add_argument("--foam-thickness", type=float, default=0.010,
                   help="width of the foam band / frame")
    p.add_argument("--foam-spread", type=float, default=0.010,
                   help="blur radius / frame; how far the foam feathers out")
    p.add_argument("--foam-lift", type=float, default=0.0,
                   help="shift the foam line up (negative) or down / frame")
    p.add_argument("--foam-color", default="255,255,255", help="foam rgb 0..255")
    p.add_argument("--foam-climb", type=float, default=0.006,
                   help="how far the foam may rise above the waterline / frame")
    return p.parse_args()


def layout(n, cols=0):
    """Sheet grid for `n` frames: (cols, rows).

    The authority on the question, and deliberately the only one. `model_sprites`
    records the grid in its meta.json so a consumer can find a frame without
    re-deriving it, and a second copy of this arithmetic there would be a sheet
    whose description disagreed with its pixels.
    """
    cols = cols if cols > 0 else math.ceil(math.sqrt(n))
    return cols, math.ceil(n / cols)


def bake_shadow(im, res, alpha, blur, squash, shear, grow, dx, dy):
    """Composite a soft iso-ground shadow under one RGBA frame, return new RGBA.

    The silhouette is projected onto the isometric floor: squashed vertically AND
    sheared horizontally about the contact line (so it lies along the ground plane,
    not straight down), dilated so a soft rim haloes out past the hull (reads as a
    grounded contact pool, not a hovering drop shadow), then offset and blurred.
    """
    from PIL import Image, ImageFilter

    a = im.getchannel("A")
    bbox = a.getbbox()
    if not bbox:
        return im  # empty frame
    base = bbox[3]  # contact line = bottom of the silhouette
    odx = dx * res
    ody = dy * res
    # Affine maps output->input. Anchored at `base`:
    #   x' = x - odx - shear * (y - base)   (iso skew along the ground)
    #   y' = base + (y - ody - base) / squash   (flatten toward the floor)
    inv = 1.0 / max(squash, 0.01)
    coeffs = (
        1.0, -shear, -odx + shear * base,
        0.0, inv, base - ody * inv - base * inv,
    )
    mask = a.transform((res, res), Image.AFFINE, coeffs, resample=Image.BILINEAR)
    # dilate so the pool reads slightly larger than the (self-occluding flat) hull
    k = int(grow * res)
    if k > 0:
        mask = mask.filter(ImageFilter.MaxFilter(k * 2 + 1))
    rad = max(1.0, blur * res)
    mask = mask.filter(ImageFilter.GaussianBlur(rad))
    # scale darkness
    mask = mask.point(lambda v: int(v * alpha))
    shadow = Image.new("RGBA", (res, res), (0, 0, 0, 0))
    shadow.putalpha(mask)  # black, mask alpha
    out = Image.alpha_composite(shadow, im)
    return out


def bake_foam(im, res, alpha, thickness, spread, lift, color, climb=0.006):
    """Composite a foam line where the subject cuts the water.

    Two things have to be true at once, and each one alone gets it wrong.

    The band is the silhouette dilated minus the silhouette, which gives a rim
    of constant width that follows the outline however it curves. On its own
    that is an outline effect, not a waterline one: it lights the gunwale, runs
    up the sides and haloes the hull. Fading it by depth is not enough either,
    because the top of a hull is still low in a frame that is mostly rigging.

    So the rim is then gated, per column, to the lowest opaque pixel in that
    column -- which after a waterline clip is exactly where the water meets the
    planking. Foam sits at and below that line and fades out within `climb` of
    rising above it. Per column and not as one band, because the waterline is
    not level: seen bow on it rakes across most of the frame's height.

    Columns whose lowest pixel is not hull are skipped, or the bowsprit and the
    spars would each trail a little foam in mid air. A column qualifies by the
    length of the unbroken run of opaque pixels ending at its lowest one: a hull
    is tens of pixels thick there, a spar is two or three.

    Composited under the subject, so it gathers against the hull rather than
    washing over it.
    """
    import numpy as np
    from PIL import Image, ImageFilter

    a_img = im.getchannel("A")
    a = np.asarray(a_img).astype(np.int16)
    solid = a > 40
    if not solid.any():
        return im

    height, width = solid.shape
    rows = np.arange(height)[:, None]

    # Lowest opaque pixel per column: the waterline, column by column.
    ybot = np.where(solid, rows, -1).max(axis=0)
    present = ybot >= 0

    # How far the opaque run reaches up from there without a gap. The highest
    # non-solid row at or below the bottom is where the run breaks.
    below = rows <= ybot[None, :]
    gap = np.where(~solid & below, rows, -1).max(axis=0)
    run = ybot - gap
    hull = present & (run >= max(int(0.02 * res), 3))
    if not hull.any():
        return im

    # The band itself.
    grow = max(int(thickness * res), 1)
    widened = a_img.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    rim = np.clip(
        np.asarray(widened).astype(np.int16) - a, 0, 255
    ).astype(np.float32)

    # Full strength at and below the waterline, gone shortly above it.
    rise = max(climb * res, 1.0)
    above = (ybot[None, :] - np.arange(height)[:, None]).astype(np.float32)
    gate = np.clip(1.0 - above / rise, 0.0, 1.0)
    gate[:, ~hull] = 0.0

    mask = Image.fromarray(np.clip(rim * gate, 0, 255).astype(np.uint8))
    if lift:
        mask = mask.transform(
            mask.size, Image.AFFINE, (1, 0, 0, 0, 1, -lift * res),
            resample=Image.BILINEAR,
        )
    mask = mask.filter(ImageFilter.GaussianBlur(max(spread * res, 0.5)))
    mask = mask.point(lambda v: int(v * alpha))

    foam = Image.new("RGBA", im.size, (*color, 0))
    foam.putalpha(mask)
    return Image.alpha_composite(foam, im)


def main():
    from PIL import Image

    a = parse_args()
    paths = sorted(glob.glob(os.path.join(a.dir, "frame_*.png")))
    if not paths:
        raise SystemExit("no frame_*.png in " + a.dir)

    frames = []
    for fp in paths:
        im = Image.open(fp).convert("RGBA")
        if a.foam:
            # Before the shadow, so the shadow settles over the foam rather
            # than the foam glowing through it.
            im = bake_foam(
                im, a.res, a.foam_alpha, a.foam_thickness, a.foam_spread,
                a.foam_lift, tuple(int(v) for v in a.foam_color.split(",")),
                a.foam_climb,
            )
            im.save(fp)
        if not a.no_shadow:
            im = bake_shadow(
                im, a.res, a.shadow_alpha, a.shadow_blur, a.shadow_squash,
                a.shadow_shear, a.shadow_grow, a.shadow_dx, a.shadow_dy,
            )
            im.save(fp)  # frames carry the shadow too
        frames.append(im)

    n = len(frames)
    cols, rows = layout(n, a.cols)
    res = a.res
    sheet = Image.new("RGBA", (cols * res, rows * res), (0, 0, 0, 0))
    strip = Image.new("RGBA", (n * res, res), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        r, c = divmod(i, cols)
        sheet.paste(im, (c * res, r * res))
        strip.paste(im, (i * res, 0))
    sheet.save(os.path.join(a.dir, "sheet.png"))
    strip.save(os.path.join(a.dir, "strip.png"))
    print(f"shadow={'off' if a.no_shadow else 'on'} sheet {cols}x{rows} @ {res}px + strip {n}x1")


if __name__ == "__main__":
    main()
