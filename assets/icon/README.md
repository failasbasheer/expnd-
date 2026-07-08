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
