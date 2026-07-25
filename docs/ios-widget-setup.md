# EXPND iOS home-screen widget — how it's wired

The widget is **fully set up and committed** — there are no manual Xcode steps
left. This file documents how the pieces connect, so the next person to touch it
(or to debug a widget that won't populate) doesn't have to reverse-engineer the
project file.

## The moving parts

| Piece | Where |
| --- | --- |
| Xcode target | `ExpndWidgetExtension` (app-extension), embedded in Runner via the *Embed Foundation Extensions* phase and a target dependency |
| SwiftUI widget | `ios/ExpndWidget/ExpndWidget.swift`, `ExpndWidgetBundle.swift` |
| Extension plist | `ios/ExpndWidget/Info.plist` — the `widgetkit-extension` `NSExtension` entry |
| App Group | `group.com.expnd.app`, declared in `ios/Runner/Runner.entitlements` **and** `ios/ExpndWidgetExtension.entitlements` |
| Dart side | `lib/services/widget_bridge.dart` — pushes a flat snapshot on every store change |
| Deep link | `expnd://add` (`CFBundleURLTypes` in `Runner/Info.plist`) opens the add-transaction screen |

The group id is defined once in code at `WidgetBridge.appGroupId`. If it ever
changes, change it in all four places: that constant, the two `.entitlements`
files named in the table above, and the `appGroupId` in `ExpndWidget.swift`.

> ⚠️ There is a **third**, unreferenced copy at
> `ios/ExpndWidget/ExpndWidget.entitlements`. Nothing signs against it — the
> widget target's `CODE_SIGN_ENTITLEMENTS` points at `ExpndWidgetExtension.
> entitlements` in `ios/`. It's byte-identical today, so it's harmless, but it
> sits in the obvious place and editing it instead of the real one changes
> nothing while looking like it should. Edit the file in `ios/`, not this one.

## Two build settings that must stay as they are

Both live on the three `ExpndWidgetExtension` build configurations and both have
bitten this project before:

- **`MARKETING_VERSION = $(FLUTTER_BUILD_NAME)`** and
  **`CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)`.** App Store validation
  rejects an extension whose version doesn't match its host app
  (`ITMS-90473` / `ITMS-90474`). Hardcoding them means every `pubspec.yaml`
  version bump silently breaks the upload, so they read Flutter's values
  instead — which is why these configs have `Flutter/Generated.xcconfig` as
  their base configuration. Don't remove that base configuration.
- **`IPHONEOS_DEPLOYMENT_TARGET = 17.0`.** `containerBackground` requires
  iOS 17. Xcode defaults a new extension target to the current SDK version,
  which would hide the widget from everyone not on the newest iOS.

Verify both after any Xcode-driven change to the project file:

```bash
flutter build ios --release --no-codesign
AX=build/ios/iphoneos/Runner.app/PlugIns/ExpndWidgetExtension.appex
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $AX/Info.plist            # must equal the app's
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $AX/Info.plist # must equal the app's
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' $AX/Info.plist           # 17.0
```

## Trying it

```bash
flutter run   # on a device or the iOS simulator
```

Long-press the home screen → **+** → search **EXPND**. It populates as soon as
the app has run once (the app pushes a snapshot on launch and on every change).
The **ADD** button / tapping the small widget opens the app straight into the
add-transaction screen.

## Notes

- No Dart-side changes are needed to add widget sizes or fields beyond the
  snapshot keys — the bridge is platform-agnostic and the Android widget reads
  the same snapshot.
- An `@main` "top-level code" warning on `ExpndWidget.swift` when it's analyzed
  outside its target is a false positive.
