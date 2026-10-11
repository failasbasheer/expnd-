#!/usr/bin/env python3
"""Renders every EXPND brand mark from one geometry.

The mark is a flat NeoPOP "E": a solid gold face over a solid gold-dark
offset edge, crisp corners, no gradient or glow. The same proportions are
drawn at runtime by `_PopEPainter` in lib/screens/splash_screen.dart, so the
native launch screen hands off to the Flutter splash without a visible seam.

Usage (from the project root):

    python3 tool/generate_brand_assets.py
    dart run flutter_launcher_icons

then restore the hand-maintained files the icon generator overwrites (see
assets/icon/README.md) and run this script again, which rewrites the dark,
tinted and monochrome variants on top. Requires Pillow.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

GOLD = (255, 232, 31, 255)
GOLD_DARK = (184, 163, 0, 255)
INK = (13, 13, 13, 255)
WHITE = (255, 255, 255, 255)
GREY = (150, 150, 150, 255)

# Geometry in units of the E's own height (1.0). Keep in sync with the Dart
# painter's constants.
STROKE = 0.22
WIDTH = 0.80
MID_ARM = 0.82  # of WIDTH
RADIUS = 0.03
DEPTH = 0.07
# Fraction of the canvas the whole mark (face + edge) occupies vertically —
# what every existing launch/icon asset uses.
MARK_HEIGHT = 0.55

SUPERSAMPLE = 4


def render(size, face, edge=None, background=None, mark_height=MARK_HEIGHT):
    """Returns a size x size RGBA image of the mark, centred."""
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), background or (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    depth_units = DEPTH if edge else 0.0
    h = s * mark_height / (1 + depth_units)
    w = h * WIDTH
    d = h * depth_units
    x0 = (s - (w + d)) / 2
    y0 = (s - (h + d)) / 2

    def e(dx, dy, color):
        t = h * STROKE
        r = h * RADIUS
        x, y = x0 + dx, y0 + dy
        boxes = [
            (x, y, x + t, y + h),  # spine
            (x, y, x + w, y + t),  # top arm
            (x, y + (h - t) / 2, x + w * MID_ARM, y + (h + t) / 2),  # middle
            (x, y + h - t, x + w, y + h),  # bottom arm
        ]
        for box in boxes:
            draw.rounded_rectangle(box, radius=r, fill=color)

    if edge:
        e(d, d, edge)
    e(0, 0, face)
    return img.resize((size, size), Image.LANCZOS)


def save(img, rel, rgb=False):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    (img.convert("RGB") if rgb else img).save(path)
    print("wrote", rel)


def main():
    # Sources for flutter_launcher_icons.
    save(render(1024, GOLD, GOLD_DARK, background=INK), "assets/icon/app_icon.png", rgb=True)
    save(render(1024, GOLD, GOLD_DARK), "assets/icon/app_icon_foreground.png")

    # In-app brand image (privacy cover).
    save(render(600, GOLD, GOLD_DARK), "assets/brand/expnd_E.png")

    # Native launch screens: the mark in a 200pt/dp box.
    for scale, name in [(1, ""), (2, "@2x"), (3, "@3x")]:
        save(
            render(200 * scale, GOLD, GOLD_DARK),
            f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{name}.png",
        )
    for density, px in [("mdpi", 200), ("hdpi", 300), ("xhdpi", 400), ("xxhdpi", 600), ("xxxhdpi", 800)]:
        save(
            render(px, GOLD, GOLD_DARK),
            f"android/app/src/main/res/drawable-{density}/launch_image.png",
        )

    # iOS 18 dark and tinted appearances (transparent; the system supplies
    # the backdrop). Tinted is greyscale so the system tint reads cleanly.
    icons = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    save(render(1024, GOLD, GOLD_DARK), f"{icons}/Icon-App-1024x1024@1x-dark.png")
    save(render(1024, WHITE, GREY), f"{icons}/Icon-App-1024x1024@1x-tinted.png")

    # Android 13+ themed icon: a single-colour silhouette, no edge.
    save(
        render(432, WHITE, mark_height=0.52),
        "android/app/src/main/res/drawable/ic_launcher_monochrome.png",
    )


if __name__ == "__main__":
    main()
