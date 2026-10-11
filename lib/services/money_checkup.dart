import '../models/models.dart';
import '../services/cash_flow.dart';
import '../services/upcoming.dart';
import '../store/app_store.dart';
import '../theme/currencies.dart';

/// A hypothetical purchase. No ledger entry is created by this calculation.
class PurchasePreview {
  final double availableAfterBills;
  final double afterPurchase;
  final double budgetAfterPurchase;
  final double reservedForGoals;
  final int excludedBills;

  /// The parts of [availableAfterBills], so the screen can show how the
  /// figure was derived: [cash] − [upcomingBills] − [reservedForGoals].
  final double cash;
  final double upcomingBills;

  const PurchasePreview({
    required this.availableAfterBills,
    required this.afterPurchase,
    required this.budgetAfterPurchase,
    required this.reservedForGoals,
    this.excludedBills = 0,
    this.cash = 0,
    this.upcomingBills = 0,
  });
}

PurchasePreview previewPurchase(
  AppStore store, {
  required double amount,
  required double monthlyBudget,
  required bool budgetRollover,
  BudgetPeriod? budgetPeriod,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final monthEnd = DateTime(today.year, today.month + 1);
  final days = monthEnd
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  // One app-wide currency: every cash-like account counts, whatever code an
  // older record happens to carry.
  final liquidAccounts = store.accounts.where((a) =>
      a.type != AccountType.credit && a.type != AccountType.investment).toList();
  final ids = liquidAccounts.map((a) => a.id).toSet();
  final projected = projectUpcoming(store, from: today, horizonDays: days)
      .where((item) => item.date.isBefore(monthEnd) &&
          item.type == TransactionType.expense).toList();
  final bills = projected.where((item) => ids.contains(item.accountId))
      .fold(0.0, (sum, item) => sum + item.amount);
  final cash = liquidAccounts.fold(0.0, (sum, a) => sum + store.balanceFor(a));
  final reserved = liquidAccounts.fold(0.0, (sum, a) => sum +
      store.claimedIn(a).clamp(0.0, store.balanceFor(a).clamp(0.0, double.infinity)));
  final available = cash - bills - reserved;
  final budget = budgetPeriod == null
      ? store.effectiveMonthlyBudget(
          monthlyBudget,
          rollover: budgetRollover,
          month: today,
        )
      : monthlyBudget;
  return PurchasePreview(
    availableAfterBills: available,
    afterPurchase: available - amount,
    budgetAfterPurchase: budget -
        (budgetPeriod == null
            ? store.spentInMonth(today)
            : budgetSpentInPeriod(store, budgetPeriod)) -
        amount,
    reservedForGoals: reserved,
    excludedBills: projected.where((item) => !ids.contains(item.accountId)).length,
    cash: cash,
    upcomingBills: bills,
  );
}

class MonthlyReview {
  final double spent;
  final double previousSpent;
  final int uncategorizedCount;
  final int transactionCount;
  final List<MapEntry<TransactionCategory, double>> categories;
  final List<Transaction> annualBills;

  const MonthlyReview({
    required this.spent,
    required this.previousSpent,
    required this.uncategorizedCount,
    required this.transactionCount,
    required this.categories,
    required this.annualBills,
  });
}

MonthlyReview monthlyReview(AppStore store, {DateTime? month}) {
  final date = month ?? DateTime.now();
  final start = DateTime(date.year, date.month);
  final end = DateTime(date.year, date.month + 1);
  final previous = DateTime(date.year, date.month - 1);
  final totals = <TransactionCategory, double>{};
  var spent = 0.0;
  var previousSpent = 0.0;
  var uncategorized = 0;
  var count = 0;
  for (final t in store.transactions) {
    if (t.type != TransactionType.expense) continue;
    if (!t.date.isBefore(start) && t.date.isBefore(end)) {
      count++;
      spent += t.amount;
      totals.update(t.category, (v) => v + t.amount, ifAbsent: () => t.amount);
      if (t.category == TransactionCategory.other &&
          t.customCategoryId == null) {
        uncategorized++;
      }
    } else if (!t.date.isBefore(previous) && t.date.isBefore(start)) {
      previousSpent += t.amount;
    }
  }
  final categories = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final annualBills =
      store.transactions
          .where(
            (t) => t.isRecurring && t.recurrenceRule == RecurrenceRule.yearly,
          )
          .where((t) => t.type == TransactionType.expense)
          .toList()
        ..sort(
          (a, b) =>
              (a.nextDueDate ?? a.date).compareTo(b.nextDueDate ?? b.date),
        );
  return MonthlyReview(
    spent: spent,
    previousSpent: previousSpent,
    uncategorizedCount: uncategorized,
    transactionCount: count,
    categories: categories,
    annualBills: annualBills,
  );
}

/// The review as a spreadsheet-friendly CSV: one `Section,Item,Amount,Detail`
/// table, so it sorts and filters without splitting into several sheets.
/// Amounts are plain numbers in the app's currency (never masked or
/// symbol-formatted), and dates are ISO 8601. Nothing leaves the device
/// unless the user shares the file.
String monthlyReviewCsv(
  MonthlyReview review, {
  required DateTime month,
  required String currencyCode,
  List<SavingsGoal> goals = const [],
}) {
  final digits = currencyDecimalDigits(currencyCode);
  String amount(double value) => value.toStringAsFixed(digits);
  String cell(String value) {
    // A leading =, +, - or @ would run as a formula in a spreadsheet.
    final safe = RegExp(r'^[=+\-@]').hasMatch(value) ? "'$value" : value;
    final escaped = safe.replaceAll('"', '""');
    return RegExp(r'[,"\r\n]').hasMatch(safe) ? '"$escaped"' : escaped;
  }

  String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final buf = StringBuffer('Section,Item,Amount,Detail\n');
  void row(String section, String item, String value, [String detail = '']) =>
      buf.write(
        '${cell(section)},${cell(item)},$value,${cell(detail)}\n',
      );

  final monthLabel =
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
  row('Summary', 'Month', '', monthLabel);
  row('Summary', 'Currency', '', currencyCode);
  row('Summary', 'Spent', amount(review.spent));
  row('Summary', 'Spent last month', amount(review.previousSpent));
  row(
    'Summary',
    'Change from last month',
    amount(review.spent - review.previousSpent),
  );
  row('Summary', 'Expenses recorded', '${review.transactionCount}');
  row('Summary', 'Expenses in Other', '${review.uncategorizedCount}');
  for (final entry in review.categories) {
    final share = review.spent > 0 ? entry.value / review.spent * 100 : 0.0;
    row(
      'Category',
      entry.key.raw,
      amount(entry.value),
      '${share.toStringAsFixed(1)}% of spending',
    );
  }
  for (final goal in goals) {
    row(
      'Savings goal',
      goal.name,
      amount(goal.allocatedAmount),
      'of ${amount(goal.targetAmount)} target',
    );
  }
  for (final bill in review.annualBills) {
    row(
      'Annual bill',
      bill.note.isEmpty ? bill.category.raw : bill.note,
      amount(bill.amount),
      'Next due ${date(bill.nextDueDate ?? bill.date)}',
    );
  }
  return buf.toString();
}
