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
  services/                 backup, reminders, insights, cash flow, subscriptions,
                            reconciliation, receipt OCR, widget/capture bridges
```

## Ported features
Transactions (income/expense/transfer), custom categories, accounts + auto-balance,
recurring transactions, budgets, savings goals, analytics, history search/filter,
biometric lock, receipt photos, clipboard "scan", CSV import/export, light/dark theming,
multi-currency, haptics.

## Money tools

Everything below is plain arithmetic over the local ledger — no network, no account.

- **Spendable until payday**: what's safe to spend before the next payday, after
  upcoming bills. Budgets can follow the calendar month, a monthly payday, or a
  weekly/fortnightly pay cycle (`lib/services/cash_flow.dart`).
- **Plan a purchase**: previews what a purchase would leave after upcoming
  bills, goal savings and the budget — nothing is recorded; **Monthly review** recaps last month
  and exports it as CSV through the share sheet (`lib/services/money_checkup.dart`).
- **Subscriptions**: recurring expenses tagged `subscription`, with annual cost,
  trial end reminders, and conservative suggestions from repeat charges
  (`lib/services/subscriptions.dart`).
- **Reconcile an account**: compare a statement balance with the ledger as of a
  date and spot likely duplicates; it never edits balances
  (`lib/services/reconciliation.dart`).
- **Refunds & reimbursements**: link incoming money to the original purchase and
  track what's still owed back. Returns are ordinary income rows.
- **Receipt scanning**: on-device text recognition pre-fills amount, merchant and
  date from a receipt photo (`lib/services/receipt_ocr.dart`).
- **Hide amounts**: the privacy eye masks every amount and every percentage
  (`formatPercent` in `lib/theme/currencies.dart`), so shares and progress can't
  reveal totals.
- **Getting started**: after first-run wallet setup, a guided screen leads to
  an expense, monthly budget, and daily reminder. Steps complete from saved
  data, and Home offers a small resume button until finished or skipped. Home
  and History transaction filters show totals for the selected rows.

New fields are optional in stored JSON and backups, so older data and backups
still load.

## Platform integrations

The iOS target includes WidgetKit and App Intents code in `ios/ExpndWidget/`
and `ios/Runner/`. The Home Screen widgets lead with what's left of the monthly
budget (never net worth) and bundle the app's Noto Sans; their palette in
`ExpndWidget.swift` mirrors `ExpndColors`. Dart bridges handle widget updates, capture inbox entries,
and local reminders. Platform integration changes require simulator or device
verification in addition to the Dart tests.
The Android home widget opens at 4×3 cells so its three recent transactions fit;
its amounts follow the app's hide-amounts setting. When hidden, SHOW opens the
app and reveals figures after any app lock.

The coach card and category suggestions use Apple's on-device Foundation Models
(`ios/Runner/AppleIntelligenceBridge.swift`, `lib/services/apple_intelligence.dart`)
when Apple Intelligence is available (iOS 26+, eligible hardware such as iPhone 15 Pro/Pro Max or iPhone 16 and later, enabled,
model downloaded, supported language). Other devices, including iPhone 15 and
Android, get the same card labelled "Insights" with rule-based copy built from
the verified facts. Availability is cached and refreshed on resume; identical coach
requests share a bounded, memory-only cache. Failed or ungrounded responses fall
back to calculated insights. The framework is weak-linked, so iOS 17–25 still launch.

Receipt scanning runs on-device over the `com.expnd.app/receipt_ocr` channel:
Apple Vision on iOS (`ios/Runner/ReceiptOcrBridge.swift`) and bundled ML Kit
text recognition on Android (`MainActivity.kt`), so no model download or network
access is needed. Receipt photos are stored by file name under the app's
Documents folder (`lib/services/receipts.dart`) so they survive container moves.

## Personal Android build (optional cloud AI Coach)

Store builds are offline: no API key and no `INTERNET` permission. For
side-loading to a trusted Android phone that lacks Apple Intelligence,
`tool/build_personal_apk.sh` builds an arm64 APK whose AI Coach uses Claude
Haiku 5.5 (`lib/services/cloud_coach.dart`). Only the app's own insight lines
(or a single note, for category suggestions) are sent; any number the model
invents is rejected and the built-in wording is shown instead.

- The key comes from `$EXPND_CLAUDE_KEY`, the macOS Keychain item
  `expnd-gf-claude`, or a hidden prompt. It is compiled into the APK, so use a
  key scoped to a dedicated Anthropic workspace with tight limits and
  prepaid credit, and never publish the APK.
- `EXPND_PERSONAL_BUILD=1` layers `android/app/src/personal/AndroidManifest.xml`
  (grants `INTERNET`) onto the release build; nothing else changes.
- The app also caps requests at 40 a day per phone.
- Updates: send a newer APK and tap Update. Data is kept because every build is
  signed with the same upload key; bump the build number in `pubspec.yaml`.

## Brand assets

The app icon, adaptive/monochrome Android layers, iOS dark/tinted icons, splash and
in-app `E` mark are drawn from one geometry by `tool/generate_brand_assets.py`
(`python3 tool/generate_brand_assets.py`, needs Pillow). Follow the regeneration
order in `assets/icon/README.md`, since `flutter_launcher_icons` overwrites some variants.

## UI conventions

Shared headers and adaptive light/dark surfaces live in `lib/widgets/app_header.dart`
and `lib/theme/expnd_theme.dart`. Page headers use text titles, aligned 44-point
actions, and a neutral profile avatar. `ExpndPageBar` gives pushed entry screens
the same title style. Keep the labeled Add action within the bottom navigation;
reserve strong yellow fills for primary content and submission actions.
Glass headers blur only after scrolling, use opaque surfaces in high-contrast mode,
and suppress transitions when reduced motion is enabled.
Use `MoneyField` for currency-aware amount entry.
Optional transaction controls and settings groups use `DisclosureSection` to keep
common tasks short while retaining advanced controls. History provides search,
transaction types, date range, and expandable category/account/tag filters.
