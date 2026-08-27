#!/usr/bin/env python3
"""Front-page art for the itch.io listing: a 960x400 header and a 630x500 capsule.

Inspired upon PyRen style of logic.

This tool is to help quickly screenshot in game scenes, then prepare them for the various sizes.

The store page is the first page of the Gazette.
- Same paper color schema, @h0lybyte todo: grad.
- Same ink and rules as vite/src/paper/paper.module.css
- Keeping the listing and the game read as one printing, unified.

Screenshots go through an engraving pass before they land on the paper:
- a 1906 press prints halftone
- rendered photographs with a raw render dropped on a paper wash reads as a mistake. 
- Plates come from godot/tools/itch_capture.gd; without them the paper still composes, it just runs the block empty.

Runnin commands for them:
    godot --path godot res://scenes/tools/itch_capture.tscn
    python3 tools/gen-itch-art.py
"""
import io
import json
import os
import random
import subprocess
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

PAPER_LIGHT = (242, 234, 214)
PAPER_MID = (230, 220, 194)
PAPER_DARK = (220, 209, 180)
PANEL = (226, 216, 189)
INK = (23, 21, 18)
INK_MUTED = (85, 80, 63)
ACCENT = (107, 32, 24)
GILT = (176, 141, 63)

MASTHEAD = "The Gilded Gazette"

# .mastTitle in paper.module.css: Georgia 700, small-caps, tracked 0.06em kinda kept in step by hand, and it is the tracking that keeps Georgia's "tt" from reading as "ll".
MASTHEAD_TRACKING = 0.06
HEADLINE = "TRUST NO ONE ABOARD"
DATELINE = "Sunday, October 14, 1906"
ISSUE = "No. 4,182"
PRICE = "Price Two Pence"

# The page background tiles, so it is cut small; the embed backdropd is sized to the widest common desktop and scaled down by the browser, never up.
BACKGROUND_TILE = 512
EMBED_SIZE = (1920, 1080)

# One clipping per section of the store page, then prose lives here, not in the layout: the layout is the press, and swapping an article should not touch it.
CLIPPINGS = [
    {
        "name": "article-teaser",
        "layout": "stub",
        "kicker": "LATE EDITION",
        "headline": "A BODY BEFORE THE BORDER",
        "deck": "The manifest is short by a name. Nobody will say whose.",
        "caption": "The 8:40 out of Aldermoor",
        "body": [
            "The Order says the carriage is secure. The Order also keeps the rear "
            "cars locked from the outside, and will not say by whose hand.",
        ],
    },
    {
        "name": "banner-permits",
        "layout": "banner",
        "headline": "ELVES NOT ALLOWED WITHOUT PERMITS",
        "deck": "Permits issued at Aldermoor. Nowhere else on this line.",
    },
    {
        "name": "banner-goblins",
        "layout": "banner",
        "headline": "GOBLINS ARE BANNED",
        "deck": "And will be slain by law. The Order is held blameless.",
        "alarm": True,
        "sigil": "godot/assets/decal/goblin.svg",
    },
    {
        "name": "notice-order",
        "layout": "notice",
        "kicker": "BY ORDER OF THE KNIGHTS OF THE NORTHERN LINE",
        "headline": "NOTICE TO PASSENGERS",
        "clauses": [
            "Elves not allowed without permits. Permits are issued at Aldermoor and "
            "nowhere else on this line.",
            "Goblins are banned, and will be slain by law. The Order is held blameless "
            "in the carrying out of it.",
            "The rear cars are reserved for the older bloods and are locked between "
            "stations for the comfort of all.",
            "Passengers are reminded that the Order's word is the record, and the "
            "record is not open to reading.",
        ],
        "foot": "Posted in every carriage by law.",
    },
    {
        "name": "article-aboard",
        "kicker": "LATE EDITION \u2014 THE NORTHERN LINE",
        "headline": "ABOARD THE EXPRESS",
        "deck": "Mysterious Woman Seen Walking the Aisle",
        "caption": "Car No. 4, an hour before the border",
        "body": [
            "The 8:40 out of Aldermoor carried a full carriage, four knights of the "
            "Order in the forward car, and one passenger whose name appears on no "
            "manifest this office has been permitted to read.",
            "She was seen at the water urn shortly before ten. She was seen again at "
            "the guard's van, where the lamp was later found unlit. Between those two "
            "hours the Order's own log records nothing at all, which is itself a "
            "record of a kind.",
            "The Order maintains that the carriage is secure and that questions of "
            "lineage are matters of safety, not sentiment. Passengers of the older "
            "bloods travel in the rear cars, as the schedule requires. The schedule "
            "does not say why the rear cars are locked from the outside.",
            "This paper takes no position beyond the obvious one: somebody on this "
            "train is lying, and the border is four hours out.",
        ],
    },
]

PLATE_DIR = "godot/reports/itch"
# Under vite/public so the store art ships with the build and is reachable by URL,
# rather than sitting in a folder at the repo root that nothing serves.
OUT_DIR = "vite/public/itch"

# The same sheet is printed three times. The store page gets the full plate; the modal
# React opens gets a web copy; the poster hanging in the carriage wears a small one,
# because it is read through a modal rather than off the wall and a wall texture at
# store resolution is a megabyte of VRAM nobody looks at.
SHIPPED = "godot/data/content.gen.json"
WEB_DIR = "vite/public/notices"
WEB_WIDTH = 1000
TEXTURE_DIR = "godot/assets/notices"
TEXTURE_WIDTH = 512

SERIF = "/System/Library/Fonts/Supplemental/Georgia.ttf"
SERIF_BOLD = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SERIF_ITALIC = "/System/Library/Fonts/Supplemental/Georgia Italic.ttf"
FALLBACK = "/System/Library/Fonts/Supplemental/Times New Roman.ttf"


def font(path, size):
    for candidate in (path, SERIF_BOLD, FALLBACK):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def small_caps(text, size):
    """Georgia has no small-cap face, so the sheet's font-variant is cut by hand."""
    caps = font(SERIF_BOLD, size)
    small = font(SERIF_BOLD, int(size * 0.76))
    return [(c.upper(), caps if c.isupper() or not c.isalpha() else small) for c in text]


def glyph_width(glyphs, tracking):
    return sum(f.getlength(c) for c, f in glyphs) + tracking * max(0, len(glyphs) - 1)


def tracked(draw, xy, glyphs, fill, tracking, anchor="ma"):
    """Letter by letter: the sheet tracks the masthead at 0.06em and PIL will not.

    Every glyph sits on one baseline. Anchoring each to its own ascender instead drops
    the full-size caps below the small ones, since the two faces are different sizes.
    """
    x, y = xy
    if anchor[0] == "m":
        x -= glyph_width(glyphs, tracking) / 2
    elif anchor[0] == "r":
        x -= glyph_width(glyphs, tracking)
    baseline = y + max(f.getmetrics()[0] for _, f in glyphs)
    for c, f in glyphs:
        draw.text((x, baseline), c, font=f, fill=fill, anchor="ls")
        x += f.getlength(c) + tracking


def masthead(width, ceiling):
    """Largest size the nameplate still fits in, with its tracking counted in."""
    size = ceiling
    while size > 10:
        glyphs = small_caps(MASTHEAD, size)
        tracking = size * MASTHEAD_TRACKING
        if glyph_width(glyphs, tracking) <= width:
            return glyphs, tracking, size
        size -= 1
    return small_caps(MASTHEAD, 10), 10 * MASTHEAD_TRACKING, 10


def fitted(path, text, width, ceiling):
    size = ceiling
    while size > 8:
        f = font(path, size)
        if f.getlength(text) <= width:
            return f
        size -= 1
    return font(path, 8)


def paper(size):
    """The sheet's radial wash, centred on the top edge like the CSS gradient."""
    w, h = size
    base = Image.new("RGB", size, PAPER_MID)
    px = base.load()
    for y in range(h):
        for x in range(w):
            dx = (x - w / 2) / (w * 0.6)
            dy = y / (h * 0.9)
            t = min(1.0, (dx * dx + dy * dy) ** 0.5)
            a, b = (PAPER_LIGHT, PAPER_MID) if t < 0.6 else (PAPER_MID, PAPER_DARK)
            k = t / 0.6 if t < 0.6 else (t - 0.6) / 0.4
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
    return base


def grain(im, strength=7, seed=1906):
    """Paper tooth. Cheap and monochrome: coloured noise reads as jpeg rot."""
    rng = random.Random(seed)
    noise = Image.new("L", im.size)
    noise.putdata([128 + rng.randint(-strength, strength) for _ in range(im.size[0] * im.size[1])])
    noise = noise.filter(ImageFilter.GaussianBlur(0.4))
    return Image.blend(im, Image.merge("RGB", (noise, noise, noise)), 0.10)


def engrave(plate, size):
    """Screenshot to press block: crop to the frame, halftone it, print it in ink."""
    src = ImageOps.fit(plate.convert("RGB"), size, Image.LANCZOS, centering=(0.5, 0.45))
    gray = ImageOps.autocontrast(src.convert("L"), cutoff=2)
    gray = ImageEnhance.Contrast(gray).enhance(1.25)
    dots = gray.convert("1", dither=Image.FLOYDSTEINBERG).convert("L")
    # all dots is unreadable at capsule scale, no dots is a photograph: half of each
    mixed = Image.blend(gray, dots, 0.45)
    return ImageOps.colorize(mixed, black=INK, white=PAPER_LIGHT)


def block(canvas, box, plate, caption=None):
    """Frames the engraving in the panel fill and rule the sheet uses everywhere."""
    x0, y0, x1, y1 = box
    draw = ImageDraw.Draw(canvas)
    draw.rectangle(box, fill=PANEL, outline=INK, width=1)
    inner = (x0 + 5, y0 + 5, x1 - 5, y1 - 5)
    if plate is not None:
        canvas.paste(engrave(plate, (inner[2] - inner[0], inner[3] - inner[1])), inner[:2])
        draw.rectangle(inner, outline=INK, width=1)
    else:
        draw.text(((x0 + x1) / 2, (y0 + y1) / 2), "[ plate not set ]", font=font(SERIF_ITALIC, 14),
                  fill=INK_MUTED, anchor="mm")
    if caption:
        f = font(SERIF_ITALIC, 13)
        strip = draw.textbbox((0, 0), caption, font=f)[3] + 6
        draw.rectangle((inner[0], inner[3] - strip, inner[2], inner[3]), fill=(*INK, 255))
        draw.text(((inner[0] + inner[2]) / 2, inner[3] - strip / 2 - 1), caption, font=f,
                  fill=PAPER_LIGHT, anchor="mm")


def rules(draw, y, x0, x1, gap=3, colour=INK):
    """The double rule under the masthead. Two hairlines, never one thick line."""
    draw.line((x0, y, x1, y), fill=colour, width=1)
    draw.line((x0, y + gap, x1, y + gap), fill=colour, width=1)


def header(plate):
    w, h = 960, 400
    canvas = paper((w, h))
    draw = ImageDraw.Draw(canvas)
    m = 30

    glyphs, tracking, size = masthead(w - m * 2, 84)
    tracked(draw, (w / 2, m - 4), glyphs, INK, tracking)
    y = m + size + 8
    rules(draw, y, m, w - m)

    meta = font(SERIF, 15)
    y += 12
    draw.text((m, y), ISSUE, font=meta, fill=INK_MUTED)
    draw.text((w / 2, y), DATELINE, font=meta, fill=INK, anchor="ma")
    draw.text((w - m, y), PRICE, font=meta, fill=INK_MUTED, anchor="ra")
    y += 26
    draw.line((m, y, w - m, y), fill=GILT, width=2)

    y += 14
    block(canvas, (m, y, w - m, h - m - 30), plate, caption=None)

    kicker = font(SERIF_BOLD, 20)
    draw.text((w / 2, h - m - 20), HEADLINE, font=kicker, fill=ACCENT, anchor="ma")
    return grain(canvas)


def capsule(plate):
    """Read at thumbnail size first: masthead, one headline, one block, nothing else."""
    w, h = 630, 500
    canvas = paper((w, h))
    draw = ImageDraw.Draw(canvas)
    m = 24

    glyphs, tracking, size = masthead(w - m * 2, 58)
    tracked(draw, (w / 2, m), glyphs, INK, tracking)
    y = m + size + 6
    rules(draw, y, m, w - m)
    y += 10
    draw.text((w / 2, y), DATELINE, font=font(SERIF, 13), fill=INK_MUTED, anchor="ma")
    y += 24
    draw.line((m, y, w - m, y), fill=GILT, width=2)

    y += 12
    block(canvas, (m, y, w - m, h - 96), plate, caption="Car No. 4, before the border")

    head = fitted(SERIF_BOLD, HEADLINE, w - m * 2, 44)
    draw.text((w / 2, h - 88), HEADLINE, font=head, fill=INK, anchor="ma")
    sub = "A murder, a border, and no honest word between them."
    draw.text((w / 2, h - 40), sub, font=font(SERIF_ITALIC, 16), fill=INK_MUTED, anchor="ma")
    return grain(canvas, seed=1907)


def wrapped(draw, text, f, width):
    """Greedy wrap. A column is narrow enough that nothing cleverer earns its keep."""
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=f) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def justify(draw, xy, line, f, width, fill, last=False):
    """Spreads a line to the column edge. The last line of a paragraph is left alone."""
    words = line.split()
    if last or len(words) == 1:
        draw.text(xy, line, font=f, fill=fill)
        return
    slack = width - sum(draw.textlength(w, font=f) for w in words)
    gap = slack / (len(words) - 1)
    x, y = xy
    for w in words:
        draw.text((x, y), w, font=f, fill=fill)
        x += draw.textlength(w, font=f) + gap


def column(draw, box, paragraphs, f, leading, fill=INK):
    """Sets paragraphs into a column and hands back what would not fit."""
    x0, y0, x1, y1 = box
    y = y0
    for i, para in enumerate(paragraphs):
        lines = wrapped(draw, para, f, x1 - x0)
        for j, line in enumerate(lines):
            if y + leading > y1:
                return paragraphs[i:] if j == 0 else [" ".join(lines[j:])] + paragraphs[i + 1:]
            justify(draw, (x0, y), line, f, x1 - x0, fill, last=(j == len(lines) - 1))
            y += leading
        y += leading * 0.35
    return []


def clipping(spec, plate):
    """A cut-out article: nameplate, headline, deck, two columns and a press block."""
    w, h = 960, 620
    canvas = paper((w, h))
    draw = ImageDraw.Draw(canvas)
    m = 34

    glyphs, tracking, size = masthead(w - m * 2, 40)
    tracked(draw, (w / 2, m - 2), glyphs, INK, tracking)
    y = m + size + 4
    rules(draw, y, m, w - m)
    y += 14

    draw.text((w / 2, y), spec["kicker"], font=font(SERIF_BOLD, 12), fill=ACCENT, anchor="ma")
    y += 24
    head = fitted(SERIF_BOLD, spec["headline"], w - m * 2, 58)
    draw.text((w / 2, y), spec["headline"], font=head, fill=INK, anchor="ma")
    y += head.getmetrics()[0] + 6
    draw.text((w / 2, y), spec["deck"], font=font(SERIF_ITALIC, 21), fill=INK_MUTED, anchor="ma")
    y += 34
    draw.line((m, y, w - m, y), fill=GILT, width=2)
    y += 16

    plate_w = 336
    body_right = w - m - plate_w - 22
    block(canvas, (body_right + 22, y, w - m, y + 250), plate, caption=spec.get("caption"))

    gutter = 20
    col_w = (body_right - m - gutter) / 2
    body = font(SERIF, 15)
    left = (m, y, m + col_w, h - m)
    rest = column(draw, left, spec["body"], body, 21)
    draw.line((m + col_w + gutter / 2, y, m + col_w + gutter / 2, h - m), fill=INK, width=1)
    right = (m + col_w + gutter, y, body_right, h - m)
    column(draw, right, rest, body, 21)
    return grain(canvas, seed=1909)


def stub(spec, plate):
    """The short cut: what a reader sees before deciding to read the long one.

    No nameplate. At the top of a store page the masthead is already overhead in the
    header image, and printing it twice reads as a template rather than a paper.
    """
    w, h = 760, 260
    canvas = paper((w, h))
    draw = ImageDraw.Draw(canvas)
    m = 22
    plate_w = 232

    block(canvas, (m, m, m + plate_w, h - m), plate, caption=None)
    x0 = m + plate_w + 22
    x1 = w - m

    draw.text((x0, m + 2), spec["kicker"], font=font(SERIF_BOLD, 11), fill=ACCENT)
    y = m + 22
    head = fitted(SERIF_BOLD, spec["headline"], x1 - x0, 34)
    draw.text((x0, y), spec["headline"], font=head, fill=INK)
    y += head.getmetrics()[0] + 8
    draw.line((x0, y, x1, y), fill=GILT, width=2)
    y += 10
    for line in wrapped(draw, spec["deck"], font(SERIF_ITALIC, 17), x1 - x0):
        draw.text((x0, y), line, font=font(SERIF_ITALIC, 17), fill=INK_MUTED)
        y += 22
    y += 6
    column(draw, (x0, y, x1, h - m), spec["body"], font(SERIF, 14), 20)
    return grain(canvas, seed=1910)


def sigil(path, size, colour, ground):
    """The decal, struck through: the prohibition sign the Order stencils on the doors.

    Rasterised through ImageMagick because PIL reads no SVG. Without magick on the
    machine the banner still prints, it just prints without the stencil.
    """
    try:
        raw = subprocess.run(["magick", "-background", "none", "-density", "600", path,
                              "-resize", f"{size}x{size}", "png:-"],
                             capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        print(f"  magick missing or failed, no sigil from {path}")
        return None
    art = Image.open(io.BytesIO(raw)).convert("RGBA")
    # the decal's viewBox is taller than its art, which parks the figure off centre
    art = art.crop(art.getbbox())
    fit = int(size * 0.58)
    art.thumbnail((fit, fit), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", art.size, colour + (255,)),
                 ((size - art.size[0]) // 2, (size - art.size[1]) // 2), art)

    draw = ImageDraw.Draw(canvas)
    pad = int(size * 0.04)
    ring = int(size * 0.055)
    draw.ellipse((pad, pad, size - pad, size - pad), outline=ground + (255,), width=ring + 6)
    draw.ellipse((pad, pad, size - pad, size - pad), outline=colour + (255,), width=ring)
    # the bar runs corner to corner of the ring, not of the box, or it overshoots
    r = (size - pad * 2) / 2 - ring / 2
    cx = cy = size / 2
    dx = dy = r * 0.7071
    draw.line((cx - dx, cy + dy, cx + dx, cy - dy), fill=ground + (255,), width=ring + 6)
    draw.line((cx - dx, cy + dy, cx + dx, cy - dy), fill=colour + (255,), width=ring)
    return canvas


def banner(spec, _plate):
    """A pasted strip. Reversed type, because the Order does not ask twice.

    The alarm ones print in the accent red the sheet keeps for losses and warnings;
    the rest print in ink, so the red still means something when it turns up.
    """
    w, h = 960, 140
    ground = ACCENT if spec.get("alarm") else INK
    canvas = Image.new("RGB", (w, h), ground)
    draw = ImageDraw.Draw(canvas)

    # sawn edge top and bottom: a strip torn off a longer sheet, not a web button
    tooth = 10
    for x in range(0, w, tooth * 2):
        draw.polygon([(x, 0), (x + tooth, 0), (x, 7)], fill=PAPER_MID)
        draw.polygon([(x, h), (x + tooth, h), (x + tooth, h - 7)], fill=PAPER_MID)

    m = 26
    left = m
    if spec.get("sigil"):
        stencil = sigil(spec["sigil"], h - 30, PAPER_LIGHT, ground)
        if stencil is not None:
            canvas.paste(stencil, (m, 15), stencil)
            left = m + stencil.size[0] + 18
    mid = (left + w - m) / 2

    head = fitted(SERIF_BOLD, spec["headline"], w - m - left, 46)
    draw.text((mid, 34), spec["headline"], font=head, fill=PAPER_LIGHT, anchor="ma")
    y = 34 + head.getmetrics()[0] + 8
    draw.line((left + 30, y, w - m - 30, y), fill=GILT, width=1)
    draw.text((mid, y + 10), spec["deck"], font=font(SERIF_ITALIC, 16), fill=PAPER_DARK,
              anchor="ma")
    return grain(canvas, strength=5, seed=1912)


def notice(spec, _plate):
    """A posted bylaw, not an article: no image, no columns, and no byline to argue with.

    It is set the way the Order would set it. The paper only reprints it, and prints
    underneath how long it stayed on the wall.
    """
    w, h = 760, 300
    canvas = paper((w, h))
    draw = ImageDraw.Draw(canvas)
    m = 20
    draw.rectangle((m, m, w - m, h - m), outline=INK, width=3)
    draw.rectangle((m + 6, m + 6, w - m - 6, h - m - 6), outline=INK, width=1)
    pad = m + 26

    draw.text((w / 2, pad), spec["kicker"], font=font(SERIF_BOLD, 11), fill=INK_MUTED, anchor="ma")
    y = pad + 20
    glyphs = small_caps(spec["headline"], 30)
    tracked(draw, (w / 2, y), glyphs, INK, 30 * MASTHEAD_TRACKING)
    y += 42
    rules(draw, y, pad, w - pad)
    y += 16

    clause = font(SERIF, 14)
    for i, text in enumerate(spec["clauses"], 1):
        for j, line in enumerate(wrapped(draw, text, clause, w - pad * 2 - 22)):
            if j == 0:
                draw.text((pad, y), f"{i}.", font=font(SERIF_BOLD, 14), fill=ACCENT)
            draw.text((pad + 22, y), line, font=clause, fill=INK)
            y += 19
        y += 5

    draw.text((w / 2, h - m - 30), spec["foot"], font=font(SERIF_ITALIC, 13), fill=INK_MUTED,
              anchor="ma")
    return grain(canvas, seed=1911)


def background():
    """Seamless paper tile for the page background. No gradient: a wash cannot repeat.

    Grain is per pixel and wraps by construction; the fibre blur would not, so it is
    blurred on a 3x3 tiling and cut back out of the middle.
    """
    n = BACKGROUND_TILE
    rng = random.Random(1906)
    tile = Image.new("L", (n, n))
    tile.putdata([128 + rng.randint(-16, 16) for _ in range(n * n)])
    wide = Image.new("L", (n * 3, n * 3))
    for ty in range(3):
        for tx in range(3):
            wide.paste(tile, (tx * n, ty * n))
    fibre = wide.filter(ImageFilter.GaussianBlur(1.6)).crop((n, n, n * 2, n * 2))
    fibre = ImageOps.autocontrast(fibre, cutoff=1)
    paper_tile = ImageOps.colorize(fibre, black=PAPER_DARK, white=PAPER_LIGHT)
    return Image.blend(paper_tile, Image.new("RGB", (n, n), PAPER_MID), 0.55)


def embed():
    """Backdrop behind the game frame. Quiet in the middle: the game is what sits there.

    The vignette is what does the work. It pushes the eye into the centre of the page
    and keeps the frame's edge legible against the paper on either side of it.
    """
    w, h = EMBED_SIZE
    canvas = paper((w, h))
    shade = Image.new("L", (w, h))
    px = shade.load()
    # radial, not the max of the axes: a box falloff creases along the diagonals
    reach = ((w / 2) ** 2 + (h / 2) ** 2) ** 0.5
    for y in range(h):
        for x in range(w):
            r = (((x - w / 2) ** 2 + (y - h / 2) ** 2) ** 0.5) / reach
            t = max(0.0, (r - 0.45) / 0.55)
            px[x, y] = int(150 * min(1.0, t * t))
    canvas = Image.composite(Image.new("RGB", (w, h), INK), canvas, shade)

    draw = ImageDraw.Draw(canvas)
    m = 26
    draw.rectangle((m, m, w - m, h - m), outline=PAPER_DARK, width=1)
    draw.rectangle((m + 6, m + 6, w - m - 6, h - m - 6), outline=GILT, width=1)
    return grain(canvas, strength=5, seed=1908)


def wrap_check(tile):
    """A tile that does not wrap is worse than no tile: itch repeats it edge to edge."""
    px = tile.convert("L").load()
    n = tile.size[0]
    col = lambda x: [px[x, y] for y in range(n)]
    mad = lambda a, b: sum(abs(i - j) for i, j in zip(a, b)) / len(a)
    wrap, near = mad(col(n - 1), col(0)), mad(col(n // 2), col(n // 2 + 1))
    return "seamless" if wrap <= max(near * 3, 1.0) else "SEAM", wrap, near


def shipped():
    """Which sheets hang in the train, by notice id, out of the compiled content.

    Read rather than listed here: shared/data/notices already says which image each
    posting wears, and a second list would be a second thing to keep in step.
    """
    if not os.path.exists(SHIPPED):
        print(f"  no {SHIPPED}, nothing shipped into the game (run npm run gen)")
        return {}
    with open(SHIPPED) as f:
        return {n["image"]: n["id"] for n in json.load(f).get("notices", [])}


def ship(im, notice_id):
    """Writes the web copy and the in-world texture for one posted notice."""
    for directory, width in ((WEB_DIR, WEB_WIDTH), (TEXTURE_DIR, TEXTURE_WIDTH)):
        os.makedirs(directory, exist_ok=True)
        scaled = im.resize((width, max(1, round(im.size[1] * width / im.size[0]))),
                           Image.LANCZOS) if im.size[0] > width else im.copy()
        dst = os.path.join(directory, f"{notice_id}.png")
        scaled.save(dst, optimize=True)
        print(f"    -> {dst} {scaled.size[0]}x{scaled.size[1]}"
              f"  {os.path.getsize(dst) / 1024:.0f} KB")


def load(name):
    path = os.path.join(PLATE_DIR, f"{name}.png")
    if not os.path.exists(path):
        print(f"  no plate at {path}, running the block empty")
        return None
    return Image.open(path)


def main(out=OUT_DIR):
    os.makedirs(out, exist_ok=True)
    posted = shipped()
    jobs = [("header", header), ("capsule", capsule),
            ("background", lambda _: background()), ("embed-bg", lambda _: embed())]
    jobs += [(spec["name"], lambda plate, spec=spec: {"stub": stub, "notice": notice, "banner": banner}.get(spec.get("layout"), clipping)(spec, plate))
             for spec in CLIPPINGS]
    for name, build in jobs:
        im = build(load("header") if name.startswith("article")
                   else load(name) if name in ("header", "capsule") else None)
        dst = os.path.join(out, f"{name}.png")
        im.save(dst, optimize=True)
        note = ""
        if name == "background":
            flag, wrap, near = wrap_check(im)
            note = f"  wrap {wrap:4.2f} vs {near:4.2f}  {flag}"
        print(f"  {name:14} {im.size[0]}x{im.size[1]}  {os.path.getsize(dst) / 1024:.0f} KB  {dst}{note}")
        if name in posted:
            ship(im, posted[name])


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else OUT_DIR)
