# EXPND Agent Guide

These instructions apply to the entire repository. EXPND is a private, offline-first
Flutter personal-finance app for iOS and Android. User instructions take precedence;
otherwise preserve the privacy model and conventions below.

## Working Agreement

- Run `git status --short`; preserve unrelated and pre-existing changes.
- Read the implementation and nearby tests before changing behavior.
- Keep changes focused; avoid opportunistic rewrites and dependency upgrades.
- Do not commit, push, publish, upload builds, or alter signing unless explicitly asked.

## Architecture

- `lib/store/`: `AppStore` ledger/Hive persistence and `SettingsStore` preferences.
- `lib/models/`: persisted entities and serialization contracts.
- `lib/services/`: backup, reminders, statements, insights, capture, and widget bridges.
- `lib/screens/`: feature UI; `lib/theme/` and `lib/widgets/`: shared NeoPOP primitives.
- `ios/ExpndWidget/` and `ios/Runner/`: WidgetKit, App Intents, App Group capture, and
  platform channels; `android/app/src/main/`: Android native integration.

## Implementation Rules

- Follow `flutter_lints`, format with `dart format`, and keep persistence out of widgets.
- Use `provider`/`ChangeNotifier` for shared state.
- Keep stored Hive JSON and backup imports backward compatible; test migrations.
- Use `lib/theme/currencies.dart`; never hard-code symbols or locale assumptions.
- Preserve light/dark themes, small-screen layouts, accessibility, and async mounted checks.
- Synchronize App Group IDs, queue/widget keys, URL schemes, and channel names across Dart,
  Swift, entitlements, plists, and Android configuration.
- Do not add analytics, remote APIs, cloud storage, or sensitive-data logging without
  explicit approval. Never edit `build/`, `.dart_tool/`, or generated plugin files.

## Verification

Run the narrowest relevant test while iterating. Before handing off code changes, run:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

Also run the relevant integration test or platform build for navigation, native bridges,
widgets, notifications, entitlements, manifests, or platform changes. Report omitted checks.

Update `README.md` when setup, architecture, features, or platform requirements change.
This is the canonical guidance; tool-specific files should only reference it.
