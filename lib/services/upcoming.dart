import '../models/models.dart';
import '../store/app_store.dart';

/// How far ahead the Upcoming surfaces look. Fixed at a rolling 30 days so a
/// full monthly cycle is always visible no matter where in the month you are.
const int kUpcomingHorizonDays = 30;

enum UpcomingKind { recurring, emi, debt }

/// One projected money movement that hasn't happened yet. These are derived on
/// every read and never persisted — the moment a recurring transaction actually
/// posts, [AppStore.generateRecurring] moves its `nextDueDate` forward and the
/// occurrence simply stops being projected.
class UpcomingItem {
  final DateTime date;
  final String title;

  /// Always positive; direction comes from [type].
  final double amount;
  final TransactionType type;
  final UpcomingKind kind;
  final TransactionCategory category;
  final String? customCategoryId;
  final String? accountId;
  final String subtitle;

  /// Id of the Transaction or Emi this was projected from.
  final String sourceId;

  const UpcomingItem({
    required this.date,
    required this.title,
    required this.amount,
    required this.type,
    required this.kind,
    required this.category,
    required this.subtitle,
    required this.sourceId,
    this.customCategoryId,
    this.accountId,
  });

  bool get isInflow => type == TransactionType.income;

  /// Effect on net worth. A transfer moves money between the user's own
  /// accounts, so it nets to zero — same rule [AppStore.transactionNet] uses.
  double get signedDelta {
    switch (type) {
      case TransactionType.income:
        return amount;
      case TransactionType.expense:
        return -amount;
      case TransactionType.transfer:
        return 0;
    }
  }

  /// EMI installments are informational: the app never posts a Transaction for
  /// them, so they must not move a projected account balance (see
  /// [UpcomingSummary.projectedMonthEnd]).
  bool get affectsBalance => kind != UpcomingKind.emi;
}

/// The headline figures shown above the timeline.
class UpcomingSummary {
  /// Everything leaving over the horizon — expenses plus EMI installments.
  final double committedOutflows;

  /// The EMI slice of [committedOutflows], broken out because it is deliberately
  /// excluded from [projectedMonthEnd] and [safeToSpend].
  final double emiCommitted;

  /// Income due over the horizon.
  final double expectedInflows;

  /// Spendable cash right now. Credit cards are debt rather than money, and an
  /// investment balance isn't cash you can pay a bill with today, so both are
  /// left out. Bank, cash and savings count.
  final double liquidBalance;

  /// [liquidBalance] plus inflows minus outflows falling before the end of the
  /// current calendar month. EMIs are excluded so this stays reconcilable with
  /// the balance the app will actually show you next month.
  final double projectedMonthEnd;

  /// What you can spend today without missing a bill that's already committed
  /// before month end. Deliberately ignores income you haven't received yet, so
  /// it stays conservative. Can go negative — that's the useful signal.
  final double safeToSpend;

  const UpcomingSummary({
    required this.committedOutflows,
    required this.emiCommitted,
    required this.expectedInflows,
    required this.liquidBalance,
    required this.projectedMonthEnd,
    required this.safeToSpend,
  });

  bool get isEmpty => committedOutflows == 0 && expectedInflows == 0;
}

/// Adds [months] to [date], clamping the day to the target month's length so
/// an EMI starting on the 31st lands on Feb 28 rather than rolling into March.
///
/// Note this is intentionally stricter than [RecurrenceRule.nextDate], which
/// lets `DateTime` roll the overflow forward. Recurring projections must mirror
/// `generateRecurring` exactly to stay honest about the date a transaction will
/// really post, so they keep using that rule as-is.
DateTime addMonthsClamped(DateTime date, int months) {
  final targetYear = date.year + ((date.month - 1 + months) ~/ 12);
  final targetMonth = ((date.month - 1 + months) % 12) + 1;
  final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
  return DateTime(
    targetYear,
    targetMonth,
    date.day < lastDay ? date.day : lastDay,
    date.hour,
    date.minute,
    date.second,
  );
}

/// Whole months elapsed between [start] and [asOf]. Mirrors [Emi.monthsPaid]
/// exactly, but as-of an explicit date rather than the wall clock — the model's
/// getter reads `DateTime.now()`, which would make the projection ignore its
/// own [projectUpcoming.from] argument and stop being a pure function.
int monthsElapsed(DateTime start, DateTime asOf) {
  var m = (asOf.year - start.year) * 12 + (asOf.month - start.month);
  if (asOf.day < start.day) m -= 1;
  return m;
}

/// Every projected movement in the next [horizonDays], ascending by date.
///
/// [from] exists for tests; production callers let it default to now.
List<UpcomingItem> projectUpcoming(
  AppStore store, {
  DateTime? from,
  int horizonDays = kUpcomingHorizonDays,
}) {
  final now = from ?? DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(Duration(days: horizonDays));
  final items = <UpcomingItem>[];

  for (final t in store.transactions) {
    if (!t.isRecurring) continue;
    var due = t.nextDueDate;
    if (due == null) continue;
    final rule = t.recurrenceRule;
    // A daily rule whose due date is stale could otherwise spin for a long
    // time; the guard costs nothing and bounds the worst case.
    var guard = 0;
    while (!due!.isAfter(end) && guard++ < 500) {
      if (!due.isBefore(start)) {
        items.add(UpcomingItem(
          date: due,
          title: t.note.trim().isNotEmpty ? t.note.trim() : t.category.raw,
          amount: t.amount,
          type: t.type,
          kind: UpcomingKind.recurring,
          category: t.category,
          customCategoryId: t.customCategoryId,
          accountId: t.accountId,
          // Just the cadence — "Recurring" is redundant on a screen that only
          // ever shows things that haven't happened yet, and dropping it leaves
          // room for the account name instead of truncating it.
          subtitle: rule.raw,
          sourceId: t.id,
        ));
      }
      due = rule.nextDate(due);
    }
  }

  for (final e in store.emis) {
    if (e.tenureMonths <= 0) continue;
    final paid = monthsElapsed(e.startDate, now).clamp(0, e.tenureMonths);
    if (paid >= e.tenureMonths) continue; // fully repaid
    final monthly = e.monthlyAmount;
    // Installment n falls on the nth monthly anniversary of the start date —
    // the first one a month after disbursal, matching how `monthsPaid` counts.
    for (var n = paid + 1; n <= e.tenureMonths; n++) {
      final date = addMonthsClamped(e.startDate, n);
      if (date.isAfter(end)) break;
      if (date.isBefore(start)) continue;
      items.add(UpcomingItem(
        date: date,
        title: e.name.trim().isNotEmpty ? e.name.trim() : 'EMI',
        amount: monthly,
        type: TransactionType.expense,
        kind: UpcomingKind.emi,
        category: TransactionCategory.other,
        accountId: e.accountId,
        subtitle: 'Installment $n of ${e.tenureMonths}',
        sourceId: e.id,
      ));
    }
  }

  // Debts with an agreed monthly repayment. Unlike an EMI these do move a
  // balance — a repayment is recorded as a real transaction — so they project
  // like any other commitment. Only what is still outstanding is scheduled,
  // so a debt nearly paid off stops filling the timeline.
  for (final d in store.debts) {
    final plan = d.monthlyRepayment;
    if (plan == null || plan <= 0 || d.isSettled) continue;
    var left = store.outstandingOn(d);
    if (left <= 0) continue;

    for (var n = 1; n <= 60 && left > 0; n++) {
      final date = addMonthsClamped(d.date, n);
      if (date.isAfter(end)) break;
      // A date already gone by must not eat into what's outstanding: that
      // figure is derived from the repayments actually recorded, so counting
      // the schedule against it too would subtract the same money twice.
      if (date.isBefore(start)) continue;
      final due = left < plan ? left : plan;
      left -= due;
      items.add(UpcomingItem(
        date: date,
        title: d.theyOweMe ? '${d.person} repays' : 'Repay ${d.person}',
        amount: due,
        // They pay me back: money comes in. I pay them back: it goes out.
        type: d.theyOweMe ? TransactionType.income : TransactionType.expense,
        kind: UpcomingKind.debt,
        category: TransactionCategory.other,
        accountId: d.accountId,
        subtitle: 'Monthly repayment',
        sourceId: d.id,
      ));
    }
  }

  items.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.title.compareTo(b.title);
  });
  return items;
}

/// Rolls [items] up into the headline figures. [items] must come from
/// [projectUpcoming] with the same [from].
UpcomingSummary summarizeUpcoming(
  AppStore store,
  List<UpcomingItem> items, {
  DateTime? from,
}) {
  final now = from ?? DateTime.now();
  // First instant of next month — everything strictly before it is "this month".
  final monthEnd = DateTime(now.year, now.month + 1, 1);

  var committed = 0.0;
  var emiCommitted = 0.0;
  var inflows = 0.0;
  var monthDelta = 0.0;
  var monthOutflowsBeforeEnd = 0.0;

  for (final i in items) {
    if (i.isInflow) {
      inflows += i.amount;
    } else if (i.type == TransactionType.expense) {
      committed += i.amount;
      if (i.kind == UpcomingKind.emi) emiCommitted += i.amount;
    }

    if (i.date.isBefore(monthEnd) && i.affectsBalance) {
      monthDelta += i.signedDelta;
      if (i.signedDelta < 0) monthOutflowsBeforeEnd += -i.signedDelta;
    }
  }

  final liquid = store.accounts
      .where((a) =>
          a.type != AccountType.credit && a.type != AccountType.investment)
      .fold(0.0, (s, a) => s + store.balanceFor(a));

  return UpcomingSummary(
    committedOutflows: committed,
    emiCommitted: emiCommitted,
    expectedInflows: inflows,
    liquidBalance: liquid,
    projectedMonthEnd: liquid + monthDelta,
    safeToSpend: liquid - monthOutflowsBeforeEnd,
  );
}

/// Groups [items] into ordered day buckets for the sectioned timeline.
List<({DateTime day, List<UpcomingItem> items})> groupUpcomingByDay(
    List<UpcomingItem> items) {
  final out = <({DateTime day, List<UpcomingItem> items})>[];
  for (final i in items) {
    final day = DateTime(i.date.year, i.date.month, i.date.day);
    if (out.isNotEmpty && out.last.day == day) {
      out.last.items.add(i);
    } else {
      out.add((day: day, items: <UpcomingItem>[i]));
    }
  }
  return out;
}
