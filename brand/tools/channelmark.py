"""The two channel treatments of the CleanJibe mark, as image operations.

One mark, three channels (docs/channels.md, "Telling the channels apart"):

  release   the mark as drawn in brand/icon-square.svg
  beta      the same mark with a red BETA label in its upper right corner
  dev       the mark mirrored left-to-right, so the wing sits upper RIGHT

Jan's brief (14 Sep 2026): a phone with the beta and the dev app side by side, or a watch
with two CleanJibe builds on it, should tell them apart at a glance without reading a name.
The label is red because nothing else in the mark is; the mirror keeps every colour and
every proportion, so the dev app still looks like CleanJibe and never like a different app.

This module is the one place the treatments are defined. brand/tools/make_channel_marks.py
applies them to the tile and the full-bleed square for iOS and the Garmin launcher icons;
garmin/tools/make_brand_mark.py applies them to the watch's ink-only cuts. Both import from
here so the label is the same red, the same face and the same proportions everywhere.
"""

from PIL import Image, ImageDraw, ImageFont, ImageOps

# iOS system red, chosen for the same reason it is the system's: it reads on a dark ground
# and on a light one, and it is nowhere else in the mark.
LABEL_RGB = (0xFF, 0x3B, 0x30)
LABEL_TEXT = "BETA"
LABEL_TEXT_RGB = (0xFF, 0xFF, 0xFF)

# The face is Helvetica Bold from the system bundle: index 1 of the .ttc. No download, no
# dependency, and it is the face the mark's own wordmark is set in on the phone (SF is
# Helvetica's descendant and the two are indistinguishable at label sizes).
FONT_PATH = "/System/Library/Fonts/Helvetica.ttc"
FONT_INDEX = 1

# Below this label HEIGHT in pixels the word is a smear; the label becomes a plain red block
# with the same outline, which still says "not the release" on a 40 px launcher icon.
MIN_TEXT_LABEL_PX = 14


def mirror(img):
    """The dev treatment: left becomes right. Gradients flip with the ink, as they would in
    an SVG `scale(-1 1)`, so the wing is still the light end of the ramp."""
    return ImageOps.mirror(img)


def _font(px):
    return ImageFont.truetype(FONT_PATH, px, index=FONT_INDEX)


def label_size(height):
    """The label's (width, height) for a given height: the word at 0.62 of the height with
    0.45 of a height of padding each side; or, below the text threshold, a 1.9:1 block."""
    height = int(round(height))
    if height < MIN_TEXT_LABEL_PX:
        return int(round(height * 1.9)), height
    font = _font(max(1, int(round(height * 0.62))))
    l, t, r, b = font.getbbox(LABEL_TEXT)
    return int(round((r - l) + height * 0.9)), height


def draw_label(img, box_top_right, height, supersample=4):
    """Paint the beta label with its TOP-RIGHT corner at `box_top_right`, `height` px tall.

    Drawn at `supersample` x and resampled down so the rounded corners and the letterforms
    are anti-aliased on every size, the 1024 px App Store icon and the 40 px launcher alike.
    Returns the same image, modified in place."""
    w, h = label_size(height)
    x1, y0 = box_top_right
    x0, y1 = x1 - w, y0 + h
    ss = supersample
    layer = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=int(h * ss * 0.28),
                        fill=LABEL_RGB + (255,))
    if h >= MIN_TEXT_LABEL_PX:
        font = _font(int(round(h * 0.62 * ss)))
        l, t, r, b = font.getbbox(LABEL_TEXT)
        tx = (w * ss - (r - l)) / 2 - l
        ty = (h * ss - (b - t)) / 2 - t
        d.text((tx, ty), LABEL_TEXT, font=font, fill=LABEL_TEXT_RGB + (255,))
    layer = layer.resize((w, h), Image.LANCZOS)
    base = img if img.mode == "RGBA" else img.convert("RGBA")
    base.alpha_composite(layer, (int(x0), int(y0)))
    if base is not img:
        img.paste(base.convert(img.mode))
    return img


def label_for_square(img, inset=0.086, height=0.146):
    """The beta label on a square icon (a tile, or the full-bleed square iOS masks itself):
    top-right, inset by `inset` of the side, `height` of the side tall. At 1024 px that is
    an 88 px margin and a 150 px label, whose outer corner sits 197 px from the centre of
    the 229 px corner circle iOS cuts — inside the mask with room to spare."""
    side = img.width
    return draw_label(img, (side - side * inset, side * inset), side * height)


def label_for_circle(img, radius_frac=0.955, height=0.146):
    """The beta label on an icon watchOS masks to a CIRCLE: the box's outer corner is put
    on the 45-degree line at `radius_frac` of the radius, so the whole label is inside the
    circle and still in the empty upper-right air of the mark."""
    side = img.width
    r = side / 2 * radius_frac
    c = side / 2
    x1 = c + r * 0.7071
    y0 = c - r * 0.7071
    return draw_label(img, (x1, y0), side * height)
