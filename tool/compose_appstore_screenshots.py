#!/usr/bin/env python3
"""Build the captioned App Store screenshot set from the UI tour output.

Run the tour first (PNGs land in screenshots/):

    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/ui_tour_test.dart \
      -d <iphone-17-pro-max-udid>

then `python3 tool/compose_appstore_screenshots.py`. Capture on a Pro Max —
a 6.3" device gives 1206x2622, which no App Store slot accepts.

Layout is lifted from the shipped 1.0 assets and re-expressed as fractions of
the canvas, so it renders identically at any store size:

    backdrop  #0D0D0D                 eyebrow ink  #FFEB34
    eyebrow   cap-top   104/2778      cap-height    21/2778
    headline  ink-top   188/2778      line advance  89/2778   size 76/1284
    device    x 153/1284   w 978/1284   top 441/2778

Checked against the original: 441 + 978*(2778/1284) = 2557, exactly the
measured bottom of the device image in the 1.0 01_dashboard.png.

ASC exposes a 6.5" slot on this listing and its uploader takes only
1242x2688 or 1284x2778 — the 6.9" set is rendered in case that slot is added.
"""
import os
from PIL import Image, ImageDraw, ImageFont

BG = (13, 13, 13)
GOLD = (255, 235, 52)
WHITE = (255, 255, 255)
FONT = "assets/fonts/NotoSans-Bold.ttf"
TRACK = 0.15          # eyebrow letterspacing, em
RADIUS_F = 44 / 978   # device corner radius as a fraction of device width

SRC = "screenshots"
OUT = "appstore_screenshots"
SIZES = {"6.5in_1284x2778": (1284, 2778), "6.9in_1320x2868": (1320, 2868)}

# (source stem, eyebrow, headline lines, output stem)
SPECS = [
    ("30_shell_home_dark",      "DASHBOARD", ["Your money,", "at a glance"],       "01_dashboard"),
    ("07_upcoming_dark",        "UPCOMING",  ["Know what's due", "before it hits"], "02_upcoming"),
    ("33_shell_plan_dark",      "PLAN",      ["Budgets, goals,", "debts — planned"], "03_plan"),
    ("34_settings_alerts_dark", "REMINDERS", ["A nudge, exactly", "when you need it"], "04_reminders"),
    ("31_shell_analytics_dark", "ANALYTICS", ["See where it", "actually goes"],     "05_analytics"),
    ("32_shell_wallet_dark",    "WALLET",    ["Every account,", "one balance"],     "06_wallet"),
]


def _rules(im, limit=900):
    """Y-spans of the near-full-width hairlines that separate settings rows."""
    w, px = im.width, im.load()
    runs = []
    for y in range(min(limit, im.height)):
        lit = sum(1 for x in range(60, w - 60, 4) if px[x, y][0] > 28)
        if lit > (w - 120) // 4 * 0.85:
            if runs and y == runs[-1][1] + 1:
                runs[-1][1] = y
            else:
                runs.append([y, y])
    return runs


def _trim_clipped_row(im):
    """Drop the half-row the scroll leaves under the pinned header.

    The alerts shot is a scrolled list, so it opens on the tail of whatever
    row the scroll stopped mid-way through. Keep the header, then resume at
    the second hairline so the first full row starts flush beneath it.
    """
    r = _rules(im)
    if len(r) < 2:
        return im
    header_end, resume = r[0][1] + 1, r[1][1] + 1
    if resume - header_end > im.height // 4:   # nothing worth cutting
        return im
    out = Image.new("RGB", (im.width, im.height - (resume - header_end)))
    out.paste(im.crop((0, 0, im.width, header_end)), (0, 0))
    out.paste(im.crop((0, resume, im.width, im.height)), (0, header_end))
    return out


def _fit_cap(target_cap):
    """Smallest point size whose cap-height reaches target_cap px."""
    size = max(1, target_cap)
    for _ in range(60):
        f = ImageFont.truetype(FONT, size)
        bb = f.getbbox("H")
        if bb[3] - bb[1] >= target_cap:
            return f
        size += 1
    return ImageFont.truetype(FONT, size)


def _draw_tracked(draw, text, font, track, cx, ink_top, fill):
    """Centred, letterspaced run anchored by the top of its ink."""
    widths = [draw.textlength(c, font=font) for c in text]
    x = cx - (sum(widths) + track * (len(text) - 1)) / 2
    off = font.getbbox("H")[1]
    for c, w in zip(text, widths):
        draw.text((x, ink_top - off), c, font=font, fill=fill)
        x += w + track


def compose(shot, eyebrow, headline, out_path, W, H):
    head_size = round(76 / 1284 * W)
    dev_x, dev_w = round(153 / 1284 * W), round(978 / 1284 * W)
    dev_top = round(441 / 2778 * H)
    head_top, head_adv = round(188 / 2778 * H), round(89 / 2778 * H)

    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    cx = W / 2

    ef = _fit_cap(round(21 / 2778 * H))
    _draw_tracked(draw, eyebrow, ef, TRACK * ef.size, cx,
                  round(104 / 2778 * H), GOLD)

    # Centre each line on its own ink box, so a trailing comma or a descender
    # doesn't drag the optical centre off-axis.
    hf = ImageFont.truetype(FONT, head_size)
    for i, line in enumerate(headline):
        bb = draw.textbbox((0, 0), line, font=hf)
        draw.text((cx - (bb[2] - bb[0]) / 2 - bb[0],
                   head_top + i * head_adv - bb[1]), line, font=hf, fill=WHITE)

    dev_h = round(dev_w * shot.height / shot.width)
    shot = shot.resize((dev_w, dev_h), Image.LANCZOS)
    mask = Image.new("L", (dev_w, dev_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, dev_w - 1, dev_h - 1), radius=round(RADIUS_F * dev_w), fill=255)
    canvas.paste(shot, (dev_x, dev_top), mask)

    if dev_top + dev_h > H:
        print(f"  ! {out_path}: device overflows by {dev_top + dev_h - H}px")
    canvas.save(out_path)


def main():
    for label, (W, H) in SIZES.items():
        outdir = os.path.join(OUT, label)
        os.makedirs(outdir, exist_ok=True)
        for src, eyebrow, headline, stem in SPECS:
            im = Image.open(os.path.join(SRC, f"{src}.png")).convert("RGB")
            if src.startswith("34_"):
                im = _trim_clipped_row(im)
            out = os.path.join(outdir, f"{stem}.png")
            compose(im, eyebrow, headline, out, W, H)
            print(f"{out}  <- {src}")


if __name__ == "__main__":
    main()
