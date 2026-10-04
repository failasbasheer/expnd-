# EXPND — Flutter

A Flutter port of the ONYX personal-finance iOS app (originally SwiftUI + SwiftData).
Runs on **iOS and Android** from one codebase, preserving the original **NeoPOP**
(CRED-style) design system.

## Running

```bash
flutter pub get
flutter run          # pick a device/simulator
```

Requires Flutter 3.44+ and iOS 17+. iOS builds need CocoaPods (`brew install cocoapods`).

For a local preview with sample accounts, transactions, budgets, and goals:

```bash
flutter run --dart-define=EXPND_SEED_DEMO=true
```

Sample data is added once and preserves existing entries. Use a simulator for previews.

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
    home_shell.dart         labeled tab bar + add action + dashboard + TransactionRow
    add_transaction.dart    add/edit flow, categories, scan, create-category
    account_setup.dart      onboarding, add/edit account, account card
    wallet_view.dart        net worth, Apple Wallet–style card stack, account details
    history_view.dart       search, filters, day-grouped list
    analytics_view.dart     trend / bar / donut / top-categories charts
    plan_view.dart          budgets, savings goals, debts and loans
    settings_view.dart      profile, grouped preferences, import/export
```

## Ported features
Transactions (income/expense/transfer), custom categories, accounts + auto-balance,
recurring transactions, budgets, savings goals, analytics, history search/filter,
biometric lock, receipt photos, clipboard "scan", CSV import/export, light/dark theming,
multi-currency, haptics.

## Platform integrations

The iOS target includes WidgetKit and App Intents code in `ios/ExpndWidget/`
and `ios/Runner/`. The Home Screen widgets lead with what's left of the monthly
budget (never net worth) and bundle the app's Noto Sans; their palette in
`ExpndWidget.swift` mirrors `ExpndColors`. Dart bridges handle widget updates, capture inbox entries,
and local reminders. Platform integration changes require simulator or device
verification in addition to the Dart tests.

The coach card and category suggestions use Apple's on-device Foundation Models
(`ios/Runner/AppleIntelligenceBridge.swift`, `lib/services/apple_intelligence.dart`)
when Apple Intelligence is available (iOS 26+, iPhone 15 Pro or newer, enabled,
model downloaded, supported language). Other devices, including iPhone 15 and
Android, get the same card labelled "Insights" with rule-based copy built from
the verified facts. The framework is weak-linked, so iOS 17–25 still launch.

## UI conventions

Shared headers and adaptive light/dark surfaces live in `lib/widgets/app_header.dart`
and `lib/theme/expnd_theme.dart`. Page headers use text titles, aligned 44-point
actions, and a neutral profile avatar. `ExpndPageBar` gives pushed entry screens
the same title style. Keep the labeled Add action within the bottom navigation;
reserve strong yellow fills for primary content and submission actions.
Use `MoneyField` for currency-aware amount entry.
Optional transaction controls and settings groups use `DisclosureSection` to keep
common tasks short while retaining advanced controls. History provides search,
transaction types, date range, and expandable category/account/tag filters.
