#!/usr/bin/env python3
"""Renders the Google Play store-listing graphics from the brand mark.

    python3 tool/generate_play_assets.py

writes play_assets/icon_512.png (512x512, full-bleed ink, the mark at the
app icon's 55% height — Play applies its own mask) and
play_assets/feature_graphic_1024x500.png (1024x500, no alpha). The mark's
geometry comes from tool/generate_brand_assets.py's render(), so there is
still one source of truth. Requires Pillow.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_brand_assets import (  # noqa: E402
    GOLD,
    GOLD_DARK,
    INK,
    ROOT,
    WHITE,
    render,
    save,
)

FONT = ROOT / "assets/fonts/NotoSans-Bold.ttf"
TAGLINE = "Private, offline money tracking"
WORDMARK = "EXPND"

FG_W, FG_H = 1024, 500
MARGIN_X = 112          # generous left/right safe area
MARK_BOX = 360          # square render box; the mark is 55% of it (~198px)
GAP = 64                # mark ink -> wordmark
WORD_CAP = 92           # wordmark cap-height, px
WORD_TRACK = 0.18       # em
TAG_CAP = 23            # tagline cap-height, px
TAG_GAP = 40            # wordmark baseline -> tagline cap-top


def _fit_cap(target_cap):
    """Smallest point size whose cap-height reaches target_cap px."""
    size = max(1, target_cap)
    while True:
        f = ImageFont.truetype(str(FONT), size)
        bb = f.getbbox("H")
        if bb[3] - bb[1] >= target_cap:
            return f
        size += 1


def _tracked_width(draw, text, font, track):
    widths = [draw.textlength(c, font=font) for c in text]
    return sum(widths) + track * (len(text) - 1), widths


def _draw_tracked(draw, text, font, track, x, cap_top, fill):
    _, widths = _tracked_width(draw, text, font, track)
    off = font.getbbox("H")[1]
    for c, w in zip(text, widths):
        draw.text((x, cap_top - off), c, font=font, fill=fill)
        x += w + track


def icon():
    return render(512, GOLD, GOLD_DARK, background=INK)


def feature_graphic():
    canvas = Image.new("RGBA", (FG_W, FG_H), INK)
    draw = ImageDraw.Draw(canvas)

    mark = render(MARK_BOX, GOLD, GOLD_DARK)
    bbox = mark.getbbox()  # ink bounds of face + edge
    mark = mark.crop(bbox)

    wf = _fit_cap(WORD_CAP)
    wtrack = WORD_TRACK * wf.size
    tf = _fit_cap(TAG_CAP)
    word_w, _ = _tracked_width(draw, WORDMARK, wf, wtrack)
    tag_w = draw.textlength(TAGLINE, font=tf)
    text_w = max(word_w, tag_w)

    # Centre the lockup (mark + gap + text) horizontally, never inside the
    # margins; centre it vertically on the text block / mark heights.
    total_w = mark.width + GAP + text_w
    x0 = max(MARGIN_X, round((FG_W - total_w) / 2))
    assert x0 + total_w <= FG_W - MARGIN_X + 1, "lockup overflows margins"
    canvas.alpha_composite(mark, (x0, round((FG_H - mark.height) / 2)))

    block_h = WORD_CAP + TAG_GAP + TAG_CAP
    word_top = round((FG_H - block_h) / 2)
    tx = x0 + mark.width + GAP
    _draw_tracked(draw, WORDMARK, wf, wtrack, tx, word_top, WHITE)
    tag_top = word_top + WORD_CAP + TAG_GAP
    draw.text((tx, tag_top - tf.getbbox("H")[1]), TAGLINE, font=tf, fill=GOLD)
    return canvas


def main():
    save(icon(), "play_assets/icon_512.png")
    save(feature_graphic(), "play_assets/feature_graphic_1024x500.png", rgb=True)


if __name__ == "__main__":
    main()
