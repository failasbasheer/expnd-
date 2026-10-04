# UI/UX review — October 2026

## Changes

- Shared headers with plain action icons, a neutral profile surface, and consistent navigation icons and selected states. The add action uses a subtle accent and an explicit label.
- Single-surface search with an accessible clear action; separate transaction-type row that wraps instead of clipping.
- Currency-aware amount entry with a separate currency symbol and keyboard dismissal.
- Optional transaction controls grouped under More options; settings grouped by task.
- Plan separates budgets, savings, and debt tasks while retaining advanced controls.
- Clear filters restores the complete history; recurring rules remain reachable when no payments are due soon.
- Responsive corrections for financial totals, onboarding, goals, and detail headers.
- Sample seeding adds labeled local examples once without resetting an existing ledger.

## Verification

The unit/widget suite passes 245 tests, including layouts at 320, 375, and 430 pixels,
both themes, and text scaling up to 1.5. A dedicated regression asserts the bottom
navigation stays compact and every navigation control exposes a semantic tap action. Flutter analysis reports no issues.

The iOS screenshot tour covers primary tabs, settings, transaction entry, history,
upcoming payments, transaction detail, account setup, loans, and onboarding.
Screenshots are stored in `screenshots/`.

Repository-wide Dart formatting passes for `lib`, `test`, and `integration_test`.
The completed header pass adds a shared page-bar component for entry and capture
screens, accessible page titles, a single plain privacy control, and consistent
close/add icons. The screenshot tour also checks light-mode settings and both
themes for quick capture and the capture inbox.

Android runtime and manual screen-reader behavior have not been verified in this
pass; automated layout and semantics checks do not replace those checks or
establish that every interaction is perfect.
