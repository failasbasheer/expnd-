# EXPND iOS home-screen widget — Xcode finalize steps

All the code is written. These steps register the widget as an Xcode **target**
and attach the App Group capability — they need Xcode's GUI and your Apple
signing account, so they can't be scripted. ~5 minutes.

Open the project first:

```bash
open ios/Runner.xcworkspace
```

## 1. Add the Widget Extension target

1. **File → New → Target… → Widget Extension** → **Next**.
2. Product Name: **ExpndWidget**. Team: your team. **Uncheck** "Include Live
   Activity" and "Include Configuration App Intent". **Finish**.
3. When asked to activate the "ExpndWidget" scheme, click **Cancel** (keep the
   Runner scheme).

Xcode creates an `ExpndWidget` group with a template `ExpndWidget.swift`,
`Info.plist`, and an entitlements file.

## 2. Swap in the real files

The template files it generated are placeholders. Replace them with the ones
already on disk in `ios/ExpndWidget/`:

- Delete the template `ExpndWidget.swift` (Move to Trash) and drag in the
  existing `ios/ExpndWidget/ExpndWidget.swift` — check **ExpndWidget** as the
  target membership.
- In the target's **Build Settings**, set **Info.plist File** to
  `ExpndWidget/Info.plist` (or replace the generated plist's contents with the
  one here — it just needs the `widgetkit-extension` NSExtension entry).
- Set the target's **iOS Deployment Target** to **17.0** or higher
  (`containerBackground` requires iOS 17).

## 3. Add the App Group to BOTH targets

The Flutter app writes the snapshot into a shared App Group; the widget reads
it. Both sides must declare the same group.

For **Runner** and again for **ExpndWidget**:

1. Select the target → **Signing & Capabilities** → **+ Capability** →
   **App Groups**.
2. Add the group **`group.com.expnd.app`** (exact string).

Entitlement files with this group already exist at
`ios/Runner/Runner.entitlements` and `ios/ExpndWidget/ExpndWidget.entitlements`;
adding the capability in Xcode wires them to signing. If Xcode created its own
entitlements files, either point **Code Signing Entitlements** (Build Settings)
at these, or just confirm the group id matches.

> The group id is defined once in code at `WidgetBridge.appGroupId`
> (`lib/services/widget_bridge.dart`). If you ever change it, change it in all
> three places: that constant, both `.entitlements`, and the `appGroupId` in
> `ExpndWidget.swift`.

## 4. Build & run

```bash
flutter run   # on a device or the iOS simulator
```

Then long-press the home screen → **+** → search **EXPND** → add the widget.
It populates as soon as the app has run once (the app pushes a snapshot on
launch and on every change). The **ADD** button / tapping the small widget opens
the app straight into the add-transaction screen via the `expnd://add` deep link
(already added to `Runner/Info.plist`).

## Notes

- The `@main` "top-level code" warning you may see on `ExpndWidget.swift` before
  step 1 is a false positive from analyzing the file outside a target — it goes
  away once the file is compiled as part of the ExpndWidget extension.
- No changes to the Flutter/Dart side are needed; it's platform-agnostic and
  already live (the Android widget uses the same snapshot).
