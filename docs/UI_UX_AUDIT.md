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

## Follow-up audit

- Fixed narrow-screen and enlarged-text overflow in Home spending, analytics legends,
  Wallet summaries, recurring-payment rows, and history amounts and notes.
- Layout tests use current transactions and scroll through the content rather than
  checking only the initial viewport. Coaching sheets scroll within screen bounds.
- Glass headers clip their blur, enable it after scrolling, restore their scrolled
  state, and use opaque high-contrast surfaces and reduced-motion transitions.
- Coach availability and identical requests are cached; unsupported devices receive
  calculated Insights. Stale category suggestions are discarded after note edits.
- Insights exclude future transactions, compare matching portions of months, and
  avoid early-month pace warnings unless the budget is already exceeded.
- Regression checks cover fresh-ledger rollover, credit-card overpayments, and goal
  allocation caps alongside currency-input tests.
- Long debt, goal, loan, EMI, and credit values now wrap or constrain within their
  cards at narrow widths and larger text sizes. Plan no longer doubles the currency
  symbol or truncates a second copy of the budget amount inside its gauge.
- Analytics uses quieter, full-height period and account controls. The empty loan
  form starts with the fields; its estimate appears once there is enough input.
- A negative monthly net uses a neutral Home surface with a red number and small
  status accent, so a small deficit does not turn the entire main card red.
- Glass surfaces use readable tints over underlying content, while tab transitions
  and entry animation respect reduced-motion preferences.

## Screen review

The screenshot tour covers Home, Analytics, Wallet, Plan, Settings, transaction
entry and detail, History/search, Upcoming, loans, account setup, quick capture,
and the capture inbox. The most important issues were dense filter outlines,
duplicate currency marks, financial rows clipped by long values, a loan form
led by an empty estimate, and Home's disproportionate deficit color. Those are
fixed above. The app keeps advanced transaction and planning controls reachable
through clear secondary actions rather than putting them all on the first screen.

Remaining opportunities are editorial: Analytics still restates the same net
figure in its summary, insight card, and chart heading. A later content pass
could choose one explanation to show first and retain the chart detail below.
Manual VoiceOver and TalkBack review, Android visual inspection, and real-device
Apple model output still need device-specific verification.

## Verification

The unit/widget suite passes all 292 tests, including layouts at 320, 375, and 430 pixels,
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

The follow-up iOS simulator tour passed all 22 checks. Native-channel tests cover
availability changes, request coalescing, grounded-response fallback, and retry.
Actual Apple model inference on eligible hardware remains unverified; simulator
and mocked-channel checks cannot establish real-device generation quality.
