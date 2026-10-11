# EXPND 1.0.2 (build 8)

Version comes from `pubspec.yaml` (`version: 1.0.2+8`); iOS reads it through
`$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` for both Runner and the
ExpndWidget extension. Build 7 was already uploaded for 1.0.1, so the next upload
must be 8 or higher.

## App Store "What's New" text

Paste as plain text. Under 4000 characters; no headings, bullets or em-dashes.

```
Budget around payday. EXPND now shows what is safe to spend until your next payday, after bills and savings. Your budget can follow the calendar month, your payday, or a weekly or fortnightly pay cycle.

All your subscriptions in one place. See what each one costs you over a year and get a reminder before a free trial ends. EXPND can also spot likely subscriptions in your history, and you decide which ones to track.

Scan a receipt. Add a photo and EXPND fills in the merchant, date and total for you. The reading happens entirely on your phone, and you check everything before it is saved.

New money tools in Plan. Preview what a purchase would leave you with before you buy it, look back on your month and export the review as a CSV file, match an account against your bank statement, and keep track of refunds and money people owe you back.

A fresh look. EXPND has a new icon that also suits dark and tinted home screens, a bolder design, and a quicker, calmer launch.

More privacy. Hiding amounts now hides percentages too, so nothing on screen gives your numbers away.

As always, everything stays on your device. No account, no tracking, no internet needed.
```

## Manual QA before upload

Run these on release builds, not debug.

- [ ] Receipt scan on a real iPhone (Apple Vision): photo with a clear total, a
      crumpled/angled receipt, and a non-receipt photo. Fields pre-fill, nothing
      saves until confirmed, airplane mode still works.
- [ ] Receipt scan on an Android release build (`flutter build apk --release` or
      the AAB via internal sharing): bundled ML Kit works with no network and R8
      has not stripped the recognizer.
- [ ] Payday cycles: switch between calendar, monthly payday, weekly and
      fortnightly. Spendable-until-payday and budget progress update; a payday
      on the 29th to 31st behaves in short months.
- [ ] Reconcile an account: matching and mismatched statement balances, past
      date; balances are never edited and likely duplicates are flagged.
- [ ] Refunds and reimbursements: link a refund to a purchase, mark a
      reimbursement partly and fully repaid; totals and budgets look right.
- [ ] Monthly review CSV export: share sheet opens on iOS and Android, file saves
      to Files / Drive and opens cleanly in Numbers or Sheets with the right
      currency.
- [ ] Plan a purchase: preview never records a transaction.
- [ ] Subscriptions: annual cost, trial reminder fires, suggestions only appear
      after confirming.
- [ ] New icon on the home screen: iOS light, dark and tinted; Android launcher,
      themed (monochrome) icon and splash.
- [ ] Hide amounts: every amount and percentage is masked on Home, Analytics,
      Wallet, Plan, money tools and the widget-facing screens.
- [ ] What's New carousel shows once after updating from 1.0.0 / 1.0.1, never on
      a fresh install, and fits on a small iPhone (SE) in both themes.
- [ ] Upgrade test: install the live 1.0.0 build, add data, update to this
      build; ledger, settings and backups still load.
- [ ] `ls build/ios/ipa/*.ipa` after `flutter build ipa` (its exit code lies),
      and refresh App Store screenshots if the UI changed.
