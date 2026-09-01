#!/usr/bin/env python3
"""Cut the watch's brand mark from the master brand artwork (brand/icon-tile.svg).

The launcher icon is a TILE — a rounded square of #0A1E30 with the mark on it. A tile is
wrong on a watch screen the app has just cleared to COLOR_BLACK: it would read as a sticker
stuck on the page. What ships here is the tile's CONTENT on the page's own black, at each
display class's own size, in that class's own colours.

TWO SCREENS, TWO WEIGHTS. `brand_mark` is the start page's, sized to the air above the
wordmark. `brand_badge` is the post-save verdict page's, sized to the LINE it sits on — it
rides beside the SAVED eyebrow. Both are the TRACK AND WING ONLY.

The master carries two water lines again, low in the tile under the whole mark. They do not
come here. They are the tile's horizon — they read as the surface the track is drawn on
because the tile gives them a ground to sit on, and this cut has no tile: it is the mark's
own ink on a page the app already cleared to black. Two white lines under it would be two
white lines, not water. And the badge is 16-19 px TALL; there is no size at which a 3-unit
hairline under it survives, least of all on 8 bpp where white is 0xFFFFFF and shouts.

Two flavours, because the shipped products are not one display family
(garmin/source/ui/Ink.mc):

  amoled  16 bpp, 390-454 px glass. The master, gradients and all.
  mip      8 bpp, 240-280 px glass, {00,55,AA,FF}^3 and no true black. A FLAT cut: the
           gradient becomes a three-step ramp of exact palette entries, and the whole thing
           is quantised here — nearest entry, NO dither — so the firmware has nothing left
           to guess at. `dithering="none"` in drawables.xml is the belt to this file's
           braces.

Both cuts are OPAQUE on #000000 rather than transparent. Every screen that draws the mark
has already cleared to COLOR_BLACK, so the black is the page; and the MIP products report
alphaBlendingSupport=false, which makes "no alpha at all" the one rendition whose result is
not a firmware detail.

The MIP palette entries were picked to avoid every collision DesignTokens.mc lists: the
brand's own #35C4F0 quantises to 0x55AAFF, which on 8 bpp is ALREADY effort.takeoff,
effort.splash and phase.flying at once — a fourth meaning on that one entry is exactly the
thing that file exists to prevent. The ramp used instead (0x00FFFF -> 0x00FFAA -> 0xAAFF55,
wing 0xAAFF55) collides with no token.

Usage:  python3 garmin/tools/make_brand_mark.py        # rewrites every brand_mark.png
"""

import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GARMIN = os.path.dirname(HERE)

SS = 12                      # supersample factor: the 100-unit artwork is rasterised at 1200
FLAT = 48                    # segments per quadratic bezier

# ---- the artwork, transcribed from brand/icon-tile.svg (viewBox 0 0 100 100) ----
# Kept as data rather than parsed: this is two paths, and a general SVG parser to read them
# would be the larger thing to maintain. They must be copied over verbatim whenever the SVG
# changes — the SVG's own header says so from the other side.
#
# The track is one jibe: an entry leg, the loop taken the LONG way round, and an exit leg
# that crosses the entry and leaves upwind. Both legs are tangents to the loop, so the
# flattened polyline below joins them smoothly and a round-joined stroke needs no help.

TRACK = ("M", (16.83, 52.55), "L", (71.77, 47.75), "Q", (76.81, 47.3), (81, 50.13),
         "Q", (85.19, 52.96), (86.67, 57.79), "Q", (88.14, 62.63), (86.25, 67.32),
         "Q", (84.36, 72), (79.94, 74.45), "Q", (75.51, 76.91), (70.53, 76.03),
         "Q", (65.56, 75.15), (62.24, 71.33), "L", (29.81, 34.03))
TRACK_W = 8.0
TRACK_STOPS = [(0.0, (0x35, 0xC4, 0xF0)), (0.6, (0x2E, 0xE6, 0xA8)), (1.0, (0xB9, 0xFF, 0x66))]

WING = ("M", (50, 20), "Q", (74, 22), (92, 46), "Q", (70, 38), (58, 42), "Q", (52, 44), (50, 52),
        "Q", (48, 44), (42, 42), "Q", (30, 38), (8, 46), "Q", (26, 22), (50, 20))
WING_STOPS = [(0.0, (0x2E, 0xE6, 0xA8)), (1.0, (0xB9, 0xFF, 0x66))]
MAST = ((50, 23), (50, 49))
MAST_W = 3.0
MAST_RGB = (0x0A, 0x1E, 0x30)
MAST_A = 0.75

# group transform: translate(25.12,28.64) rotate(-30) scale(0.51) translate(-50,-36)
WING_XFORM = (25.12, 28.64, -30.0, 0.51, -50.0, -36.0)

# The 8 bpp palette every MIP product snaps to, and the flat ramp the mark uses inside it.
MIP_LEVELS = (0x00, 0x55, 0xAA, 0xFF)
MIP_TRACK = [(0.0, (0x00, 0xFF, 0xFF)), (0.5, (0x00, 0xFF, 0xAA)), (1.0, (0xAA, 0xFF, 0x55))]
MIP_WING = [(0.0, (0xAA, 0xFF, 0x55)), (1.0, (0xAA, 0xFF, 0x55))]
MIP_MAST_RGB = (0x00, 0x00, 0x00)

# Where each cut goes, and how big. The directories are the launcher-icon qualifier dirs the
# jungle already maps every product to, and that mapping happens to be exactly the partition
# the mark needs (see garmin/monkey.jungle). The mark is cropped to its own ink first (the
# tile's rounded-square padding is the tile's, not the mark's).
#
# THE NUMBER BELOW IS THE CUT'S HEIGHT, and it used to be its width. The old artwork was a
# flat hairpin, half again as wide as it was tall; the jibe loop drawn upright was very
# nearly square, and turning it down to 22 deg has laid it back out to 1.34:1. Through all
# of that the binding constraint on both screens has been the VERTICAL air — that is what
# `Brand.fits()` measures and what the layout suite asserts. Sizing by height keeps the one
# dimension the pages were laid out against exactly where it was, on every product, and lets
# the width be whatever the artwork currently is.
#
# TWO cuts per directory, not one, because the two screens want different weights and a
# bitmap does not scale. `brand_mark` is the start page's, sized to the air above the
# wordmark; `brand_badge` is the verdict page's, sized to the LINE it sits on — the SAVED
# eyebrow — so the pair reads as one piece of ink at the height of the word rather than as a
# logo that has wandered into the number's space. Measured on the fenix 8: the 46 px mark
# centred on that eyebrow reaches the top of the giant's digits, and the 19 px badge sits
# exactly inside the word's own band.
TARGETS = [
    ("resources",        "brand_mark",  46, "amoled"),   # the six 454 px AMOLED products
    ("resources",        "brand_badge", 19, "amoled"),
    ("resources-icon60", "brand_mark",  41, "amoled"),   # epix 2 / MARQ 2 / fenix 8 43 mm
    ("resources-icon60", "brand_badge", 17, "amoled"),
    ("resources-icon54", "brand_mark",  41, "amoled"),   # fr570 42 mm, 390 px
    ("resources-icon54", "brand_badge", 17, "amoled"),
    ("resources-icon40", "brand_mark",  22, "mip"),      # the thirteen 8 bpp, 240-280 px
    ("resources-icon40", "brand_badge", 16, "mip"),
]


def flatten(path):
    """A path description -> a list of (x, y) points."""
    pts = []
    i = 0
    cur = None
    while i < len(path):
        op = path[i]
        if op == "M":
            cur = path[i + 1]
            pts.append(cur)
            i += 2
        elif op == "L":
            cur = path[i + 1]
            pts.append(cur)
            i += 2
        elif op == "Q":
            c, e = path[i + 1], path[i + 2]
            for k in range(1, FLAT + 1):
                t = k / FLAT
                u = 1.0 - t
                pts.append((u * u * cur[0] + 2 * u * t * c[0] + t * t * e[0],
                            u * u * cur[1] + 2 * u * t * c[1] + t * t * e[1]))
            cur = e
            i += 3
        else:
            raise ValueError(op)
    return pts


def xform(pts, tf):
    tx, ty, deg, s, px, py = tf
    r = math.radians(deg)
    cos, sin = math.cos(r), math.sin(r)
    out = []
    for x, y in pts:
        x, y = (x + px) * s, (y + py) * s
        x, y = x * cos - y * sin, x * sin + y * cos
        out.append((x + tx, y + ty))
    return out


def mask_stroke(size, pts, width):
    """A round-capped, round-joined stroke of `pts` as an L mask at supersample scale."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    w = width * SS
    sp = [(x * SS, y * SS) for x, y in pts]
    d.line(sp, fill=255, width=int(round(w)), joint="curve")
    r = w / 2.0
    for x, y in (sp[0], sp[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return m


def mask_fill(size, pts):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return m


def gradient(size, stops, x0, x1):
    """A horizontal multi-stop ramp across [x0, x1] in artwork units, as an RGB image."""
    g = Image.new("RGB", (size, size))
    px = g.load()
    span = max(x1 - x0, 1e-6)
    row = []
    for x in range(size):
        t = min(max((x / SS - x0) / span, 0.0), 1.0)
        lo, hi = stops[0], stops[-1]
        for a, b in zip(stops, stops[1:]):
            if a[0] <= t <= b[0]:
                lo, hi = a, b
                break
        k = 0.0 if hi[0] == lo[0] else (t - lo[0]) / (hi[0] - lo[0])
        row.append(tuple(int(round(lo[1][c] + k * (hi[1][c] - lo[1][c]))) for c in range(3)))
    for y in range(size):
        for x in range(size):
            px[x, y] = row[x]
    return g


def paint(img, mask, rgb_img, alpha=1.0):
    if alpha < 1.0:
        mask = mask.point(lambda v: int(round(v * alpha)))
    img.paste(rgb_img, (0, 0), mask)


def render(tall, flavour):
    size = 100 * SS
    img = Image.new("RGB", (size, size), (0, 0, 0))

    track = flatten(TRACK)
    tx0 = min(p[0] for p in track)
    tx1 = max(p[0] for p in track)
    stops = MIP_TRACK if flavour == "mip" else TRACK_STOPS
    paint(img, mask_stroke(size, track, TRACK_W), gradient(size, stops, tx0, tx1))

    wing = flatten(WING)
    wx0 = min(p[0] for p in wing)
    wx1 = max(p[0] for p in wing)
    wstops = MIP_WING if flavour == "mip" else WING_STOPS
    wg = gradient(size, wstops, *[p[0] for p in xform([(wx0, 0), (wx1, 0)], WING_XFORM)])
    paint(img, mask_fill(size, xform(wing, WING_XFORM)), wg)

    mast_rgb = MIP_MAST_RGB if flavour == "mip" else MAST_RGB
    mast = Image.new("RGB", (size, size), mast_rgb)
    paint(img, mask_stroke(size, xform(list(MAST), WING_XFORM), MAST_W * WING_XFORM[3]),
          mast, 1.0 if flavour == "mip" else MAST_A)

    box = img.getbbox()                    # the ink, without the tile's own padding
    img = img.crop(box)
    w = max(1, int(round(tall * img.width / float(img.height))))
    img = img.resize((w, tall), Image.LANCZOS)
    if flavour == "mip":
        img = quantise(img)
    return img


def quantise(img):
    """Snap every pixel to its nearest {00,55,AA,FF}^3 entry. Nearest, never dithered."""
    lut = []
    for v in range(256):
        lut.append(min(MIP_LEVELS, key=lambda L: abs(L - v)))
    return Image.merge("RGB", [ch.point(lut) for ch in img.split()])


def main():
    for d, name, tall, flavour in TARGETS:
        out = os.path.join(GARMIN, d, "drawables", name + ".png")
        img = render(tall, flavour)
        img.save(out, optimize=True)
        print(f"{out}  {img.width}x{img.height}  {flavour}  {os.path.getsize(out)} B")
    return 0


if __name__ == "__main__":
    sys.exit(main())
