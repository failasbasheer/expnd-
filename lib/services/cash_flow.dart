import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import 'upcoming.dart';

/// Inclusive start, exclusive end. This keeps a purchase on payday in the new
/// period and avoids counting one transaction in two budgets.
class BudgetPeriod {
  final DateTime start;
  final DateTime end;

  const BudgetPeriod(this.start, this.end);

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

int _serialDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

DateTime _monthlyDay(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day.clamp(1, last));
}

BudgetPeriod budgetPeriodFor(SettingsStore settings, DateTime date) {
  final today = _day(date);
  switch (settings.budgetCycle) {
    case 'payday':
      final thisMonth = _monthlyDay(
        today.year,
        today.month,
        settings.paydayDay,
      );
      final start = today.isBefore(thisMonth)
          ? _monthlyDay(today.year, today.month - 1, settings.paydayDay)
          : thisMonth;
      return BudgetPeriod(
        start,
        _monthlyDay(start.year, start.month + 1, settings.paydayDay),
      );
    case 'weekly':
    case 'fortnightly':
      final length = settings.budgetCycle == 'weekly' ? 7 : 14;
      final anchor = settings.paydayAnchor;
      final elapsed = _serialDay(today) - _serialDay(anchor);
      final cycles = (elapsed / length).floor();
      final start = DateTime(
        anchor.year,
        anchor.month,
        anchor.day + cycles * length,
      );
      return BudgetPeriod(
        start,
        DateTime(start.year, start.month, start.day + length),
      );
    default:
      return BudgetPeriod(
        DateTime(today.year, today.month),
        DateTime(today.year, today.month + 1),
      );
  }
}

/// The next payday is exclusive of today: on payday, the estimate covers the
/// new cycle. For a calendar budget, the configured payday still determines
/// the cash flow horizon.
DateTime nextPaydayFor(SettingsStore settings, DateTime date) {
  final today = _day(date);
  if (settings.budgetCycle == 'weekly' ||
      settings.budgetCycle == 'fortnightly') {
    return budgetPeriodFor(settings, today).end;
  }
  final candidate = _monthlyDay(today.year, today.month, settings.paydayDay);
  return candidate.isAfter(today)
      ? candidate
      : _monthlyDay(today.year, today.month + 1, settings.paydayDay);
}

double budgetSpentInPeriod(
  AppStore store,
  BudgetPeriod period, {
  TransactionCategory? category,
}) {
  return store.transactions
      .where(
        (t) =>
            t.type == TransactionType.expense &&
            period.contains(t.date) &&
            (category == null ||
                (t.category == category && t.customCategoryId == null)),
      )
      .fold(0.0, (total, t) => total + t.amount);
}

class CashFlowEstimate {
  final DateTime nextPayday;
  final double liquidBalance;
  final double reservedForGoals;
  final double upcomingBills;
  final double spendable;
  final List<UpcomingItem> bills;

  /// Projected expenses outside the selected currency or without a matching
  /// cash account. Their amounts cannot safely be added to this currency.
  final List<UpcomingItem> excludedBills;

  const CashFlowEstimate({
    required this.nextPayday,
    required this.liquidBalance,
    required this.reservedForGoals,
    required this.upcomingBills,
    required this.spendable,
    required this.bills,
    required this.excludedBills,
  });
}

/// A conservative estimate from the ledger. Only bank, cash, and savings
/// balances in the selected currency are available; allocations to savings
/// goals and projected bills linked to those accounts are reserved. Expected
/// income is shown elsewhere in Upcoming but is never counted as money
/// available to spend now. Unlinked and foreign-currency bills are disclosed
/// separately because adding their raw amounts would mix unlike currencies.
CashFlowEstimate estimateUntilPayday(
  AppStore store,
  SettingsStore settings, {
  DateTime? from,
}) {
  final today = _day(from ?? DateTime.now());
  final payday = nextPaydayFor(settings, today);
  final horizon = _serialDay(payday) - _serialDay(today);
  final projectedBills =
      projectUpcoming(store, from: today, horizonDays: horizon)
          .where(
            (item) =>
                item.date.isBefore(payday) &&
                item.type == TransactionType.expense,
          )
          .toList();
  final liquidAccounts = store.accounts
      .where(
        (account) =>
            account.currencyCode == settings.currencyCode &&
            account.type != AccountType.credit &&
            account.type != AccountType.investment,
      )
      .toList();
  final includedAccountIds = liquidAccounts
      .map((account) => account.id)
      .toSet();
  final bills = projectedBills
      .where((item) => includedAccountIds.contains(item.accountId))
      .toList();
  final excludedBills = projectedBills
      .where((item) => !includedAccountIds.contains(item.accountId))
      .toList();
  final liquid = liquidAccounts.fold<double>(
    0,
    (total, account) => total + store.balanceFor(account),
  );
  final reserved = liquidAccounts.fold<double>(0, (total, account) {
    final balance = store.balanceFor(account).clamp(0.0, double.infinity);
    return total + store.claimedIn(account).clamp(0.0, balance);
  });
  final billTotal = bills.fold<double>(0, (total, bill) => total + bill.amount);
  return CashFlowEstimate(
    nextPayday: payday,
    liquidBalance: liquid,
    reservedForGoals: reserved,
    upcomingBills: billTotal,
    spendable: liquid - reserved - billTotal,
    bills: bills,
    excludedBills: excludedBills,
  );
}
