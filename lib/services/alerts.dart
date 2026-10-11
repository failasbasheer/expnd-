import '../models/models.dart';
import '../store/app_store.dart';
import '../theme/currencies.dart';
import 'upcoming.dart';
import 'cash_flow.dart';
import 'subscriptions.dart';

/// Event alerts: the notifications that fire off something *happening* rather
/// than the clock reaching a set hour.
///
/// Same rules as the rest of this app — pure arithmetic over the store, no
/// network, no plugin. Everything here returns plain data so it can be unit
/// tested the way [buildInsights] and [projectUpcoming] are; the on-device
/// scheduling that turns this data into notifications lives in
/// `reminders.dart`, which is the only part that touches the OS.
///
/// Two shapes of alert:
///  - **Scheduled** — a known future date (a bill landing). [dueSoonAlerts]
///    returns one per upcoming outflow, timed for the evening before.
///  - **State** — a condition that is already true right now (over budget, a
///    goal funded). These can't be scheduled ahead, so they're detected on the
///    spot and fired once, deduped by a marker the caller persists.

/// A notification to schedule for a specific future moment.
class DueAlert {
  final DateTime fireAt;
  final String title;
  final String body;
  const DueAlert({
    required this.fireAt,
    required this.title,
    required this.body,
  });
}

/// A "this is true now" notification to show immediately.
class StateAlert {
  final String title;
  final String body;
  const StateAlert(this.title, this.body);
}

/// One reminder per upcoming **outflow** — a bill, an EMI installment, a
/// repayment going out — timed to land [leadDays] before it's due, at
/// [hour]:[minute] (the user's reminder time).
///
/// Inflows are left out: "money is about to arrive" isn't something you need to
/// act on before it happens. Capped at [cap] so a busy month can't blow past
/// iOS's 64-pending-notification ceiling. Alerts whose fire time has already
/// passed are dropped, so the list is always safe to hand straight to the
/// scheduler.
///
/// The relative wording ("due tomorrow") is phrased against [leadDays], not the
/// gap from now — the text is baked when it's scheduled but read when it fires,
/// and at fire time the bill really is [leadDays] away.
List<DueAlert> dueSoonAlerts(
  AppStore store,
  String code, {
  DateTime? from,
  int leadDays = 1,
  int hour = 21,
  int minute = 0,
  int cap = 15,
  int horizonDays = kUpcomingHorizonDays,
}) {
  final now = from ?? DateTime.now();
  final items = projectUpcoming(
    store,
    from: now,
    horizonDays: horizonDays,
  ).where((i) => !i.isInflow).toList();

  final when = leadDays == 1 ? 'tomorrow' : 'in $leadDays days';
  final out = <DueAlert>[];
  for (final i in items) {
    final day = DateTime(
      i.date.year,
      i.date.month,
      i.date.day,
    ).subtract(Duration(days: leadDays));
    final fireAt = DateTime(day.year, day.month, day.day, hour, minute);
    if (!fireAt.isAfter(now)) continue; // the warning window has already closed

    final acct = store.accountFor(i.accountId)?.name;
    final money = formatCurrency(i.amount, code);
    out.add(
      DueAlert(
        fireAt: fireAt,
        title: '${i.title} due $when',
        body: acct == null || acct.isEmpty ? money : '$money — $acct',
      ),
    );
    if (out.length >= cap) break;
  }
  return out;
}

/// Local reminders three days before a tracked trial ends. The date is shown
/// as a review prompt because ending tracking inside EXPND cannot cancel a
/// subscription with its provider.
List<DueAlert> trialEndAlerts(
  Iterable<Transaction> transactions, {
  DateTime? from,
  int leadDays = 3,
  int hour = 21,
  int minute = 0,
}) {
  final now = from ?? DateTime.now();
  final alerts = <DueAlert>[];
  for (final transaction in transactions) {
    if (!isSubscription(transaction)) continue;
    final end = transaction.subscriptionTrialEndDate;
    if (end == null) continue;
    final day = DateTime(
      end.year,
      end.month,
      end.day,
    ).subtract(Duration(days: leadDays));
    final fireAt = DateTime(day.year, day.month, day.day, hour, minute);
    if (!fireAt.isAfter(now)) continue;
    final name = transaction.note.trim().isEmpty
        ? transaction.category.raw
        : transaction.note.trim();
    alerts.add(
      DueAlert(
        fireAt: fireAt,
        title: '$name trial ends in $leadDays days',
        body: 'Review the subscription before the trial ends.',
      ),
    );
  }
  alerts.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return alerts;
}

/// Whether the month's spending has just crossed [monthlyBudget] and hasn't
/// been announced yet. [lastAlertedMonth] is the `yyyymm` an alert last fired
/// for, so a month already flagged stays quiet no matter how far over it goes.
bool newlyOverBudget(
  AppStore store, {
  required double monthlyBudget,
  required int lastAlertedMonth,
  BudgetPeriod? period,
  DateTime? from,
}) {
  if (monthlyBudget <= 0) return false;
  final now = from ?? DateTime.now();
  if (budgetAlertKey(now, period: period) == lastAlertedMonth) return false;
  final spent = period == null
      ? store.spentInMonth(now)
      : budgetSpentInPeriod(store, period);
  return spent > monthlyBudget;
}

/// `yyyymm` for [d] — the key [newlyOverBudget] dedups on and the caller stores.
int yyyymm(DateTime d) => d.year * 100 + d.month;

int budgetAlertKey(DateTime date, {BudgetPeriod? period}) => period == null
    ? yyyymm(date)
    : period.start.year * 10000 + period.start.month * 100 + period.start.day;

/// The over-budget notification, or null when it isn't due (see
/// [newlyOverBudget]).
StateAlert? overBudgetAlert(
  AppStore store,
  String code, {
  required double monthlyBudget,
  required int lastAlertedMonth,
  BudgetPeriod? period,
  DateTime? from,
}) {
  if (!newlyOverBudget(
    store,
    monthlyBudget: monthlyBudget,
    lastAlertedMonth: lastAlertedMonth,
    period: period,
    from: from,
  )) {
    return null;
  }
  final now = from ?? DateTime.now();
  final spent = period == null
      ? store.spentInMonth(now)
      : budgetSpentInPeriod(store, period);
  final over = spent - monthlyBudget;
  final end = period?.end ?? DateTime(now.year, now.month + 1);
  final left =
      end.difference(DateTime(now.year, now.month, now.day)).inDays - 1;
  return StateAlert(
    'Over budget',
    'You\'ve passed ${formatCurrency(monthlyBudget, code)} — '
        '${formatCurrency(over, code)} over, with $left '
        '${left == 1 ? 'day' : 'days'} still to go.',
  );
}

/// Goals that are fully funded but haven't been celebrated yet. [celebrated] is
/// the set of goal ids already announced; the caller adds the returned ids to
/// it so each goal only ever gets one 🎉.
List<SavingsGoal> newlyReachedGoals(AppStore store, List<String> celebrated) {
  final done = celebrated.toSet();
  return store.goals
      .where(
        (g) =>
            g.targetAmount > 0 &&
            store.progressForGoal(g) >= 1.0 &&
            !done.contains(g.id),
      )
      .toList();
}

/// The congratulations notification for a funded [goal].
StateAlert goalReachedAlert(SavingsGoal goal, String code) => StateAlert(
  'Goal reached 🎉',
  '"${goal.name}" is fully funded at '
      '${formatCurrency(goal.targetAmount, code)}. Nice work.',
);
