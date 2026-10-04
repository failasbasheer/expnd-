# App launcher icons

Place two PNG files here, then generate all platform sizes.

## Required files

| File | Size | Notes |
|------|------|-------|
| `app_icon.png` | 1024×1024 | Full-bleed square. **No transparency** (App Store rejects alpha). Used for iOS + legacy Android. |
| `app_icon_foreground.png` | 1024×1024 | Android adaptive-icon foreground. Logo **centered inside the middle ~66%** with transparent padding — launchers crop/mask the outer edges. |

The adaptive-icon background is a solid brand color (`#0D0D0D`), configured in `pubspec.yaml`.

## Generate

From the project root:

```sh
dart run flutter_launcher_icons
```

This overwrites the icon sets in `android/app/src/main/res/mipmap-*/`
and `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
Re-run it whenever you change either source PNG.

**After generating, restore the hand-maintained pieces it overwrites:**

- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — the generator
  drops the `<monochrome>` layer (Android 13+ themed icons).
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` — the generator
  drops the dark and tinted 1024 appearances.

Use `git checkout` on both files, then update `Icon-App-1024x1024@1x-dark.png`
(the mark on transparent), `Icon-App-1024x1024@1x-tinted.png` (grayscale mark
on transparent) and `drawable/ic_launcher_monochrome.png` (white mark, 432px)
by hand. The launch images (`LaunchImage*.png`, `drawable-*/launch_image.png`)
are the same mark in a 200pt/dp box, matching `lib/screens/splash_screen.dart`.
