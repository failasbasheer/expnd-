# EXPND — Flutter

A Flutter port of the ONYX personal-finance iOS app (originally SwiftUI + SwiftData).
Runs on **iOS and Android** from one codebase, preserving the original **NeoPOP**
(CRED-style) design system.

## Running

```bash
flutter pub get
flutter run          # pick a device/simulator
```

Requires Flutter 3.44+. iOS needs CocoaPods (`brew install cocoapods`).

## Architecture

| Concern | Original (iOS) | This Flutter app |
|---|---|---|
| State / queries | SwiftData `@Model` + `@Query` | `provider` + `ChangeNotifier` (`AppStore`) |
| Persistence | SwiftData store | **Hive** box, entities stored as JSON |
| Settings | `@AppStorage` | `shared_preferences` (`SettingsStore`) |
| Design system | `Theme.swift` NeoPOP | `lib/widgets/neopop.dart` + `lib/theme/` |
| Icons | SF Symbols | `lib/theme/sf_icons.dart` (SF→Material map) |
| Biometric lock | `LocalAuthentication` | `local_auth` |
| Charts | Swift Charts | `fl_chart` |
| Receipt photos | `PhotosPicker` + `Data` | `image_picker` + file paths |
| CSV export/import | `UIActivityViewController` / `fileImporter` | `share_plus` / `file_picker` |

### Layout

```
lib/
  main.dart                 app root, theming, lock gate, onboarding trigger
  models/models.dart        enums + Transaction/Account/CustomCategory/Budget/Goal
  store/
    app_store.dart          reactive data layer + Hive persistence
    settings_store.dart     @AppStorage equivalents + Haptics gate
  theme/
    expnd_theme.dart         adaptive NeoPOP palette
    sf_icons.dart           SF Symbol → IconData map
    currencies.dart         supported currencies + formatting
  widgets/neopop.dart       NeoPopElevated / NeoPopButton / NeoPopShine / NeoPopTag
  screens/
    home_shell.dart         custom tab bar + FAB + dashboard + TransactionRow
    add_transaction.dart    add/edit flow, categories, scan, create-category
    account_setup.dart      onboarding, add/edit account, account card
    wallet_view.dart        net worth, Apple Wallet–style card stack, account details
    history_view.dart       search, filters, day-grouped list
    analytics_view.dart     trend / bar / donut / top-categories charts
    profile_view.dart       stats, budget, goals, settings, CSV import/export
```

## Ported features
Transactions (income/expense/transfer), custom categories, accounts + auto-balance,
recurring transactions, budgets, savings goals, analytics, history search/filter,
biometric lock, receipt photos, clipboard "scan", CSV import/export, light/dark theming,
multi-currency, haptics.

## Not yet ported (iOS-specific, deferred)
- **Home-screen widget** (`EXPNDWidget`) — would use `home_widget` + native widget code.
- **Siri / App Intents** SMS scanner — Android has no direct equivalent; would need
  a share-intent + platform channel.
- **Deep links** (`xpnd://scan`) — add via `app_links`.
- **Local notification scheduling** — the daily-reminder toggle persists, but wiring the
  actual schedule needs `flutter_local_notifications` + platform setup.
