import '../models/models.dart';

/// Subscription data is derived from the existing local ledger. A recurring
/// expense becomes a subscription when the user marks it with this tag.
const subscriptionTag = 'subscription';

bool isSubscription(Transaction transaction) =>
    transaction.type == TransactionType.expense &&
    transaction.isRecurring &&
    transaction.tags.any((tag) => tag.toLowerCase() == subscriptionTag);

double annualSubscriptionCost(Transaction transaction) {
  final periods = switch (transaction.recurrenceRule) {
    RecurrenceRule.daily => 365.0,
    RecurrenceRule.weekly => 52.0,
    RecurrenceRule.biweekly => 26.0,
    RecurrenceRule.monthly => 12.0,
    RecurrenceRule.yearly => 1.0,
  };
  return transaction.amount * periods;
}

String _merchantKey(String note) => note
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'\b(monthly|annual|yearly|payment|charge)\b'), '')
    .trim();

/// Finds likely subscriptions locally. Suggestions are deliberately conservative:
/// at least three similar expense rows, a monthly or yearly cadence, and
/// amounts within 10%. Nothing is changed until the user confirms it.
List<SubscriptionSuggestion> suggestSubscriptions(
  Iterable<Transaction> transactions, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final groups = <String, List<Transaction>>{};
  for (final transaction in transactions) {
    if (transaction.type != TransactionType.expense ||
        transaction.isRecurring ||
        transaction.note.trim().isEmpty ||
        transaction.date.isAfter(today) ||
        today.difference(transaction.date).inDays > 1100) {
      continue;
    }
    final key = _merchantKey(transaction.note);
    if (key.length < 3) continue;
    groups.putIfAbsent(key, () => []).add(transaction);
  }

  final suggestions = <SubscriptionSuggestion>[];
  for (final entry in groups.entries) {
    final rows = entry.value..sort((a, b) => a.date.compareTo(b.date));
    if (rows.length < 3) continue;
    final recent = rows.last;
    if (today.difference(recent.date).inDays > 400) continue;
    final nearAmount = rows.where((row) {
      final tolerance = recent.amount.abs() * 0.1;
      return (row.amount - recent.amount).abs() <= tolerance;
    }).toList();
    if (nearAmount.length < 3) continue;
    final gaps = <int>[];
    for (var index = 1; index < nearAmount.length; index++) {
      gaps.add(
        nearAmount[index].date.difference(nearAmount[index - 1].date).inDays,
      );
    }
    final monthly = gaps.every((gap) => gap >= 25 && gap <= 35);
    final yearly = gaps.every((gap) => gap >= 350 && gap <= 380);
    if (!monthly && !yearly) continue;
    if (today.difference(recent.date).inDays > (monthly ? 65 : 400)) {
      continue;
    }
    suggestions.add(
      SubscriptionSuggestion(
        merchant: recent.note.trim(),
        amount: recent.amount,
        recurrenceRule: monthly
            ? RecurrenceRule.monthly
            : RecurrenceRule.yearly,
        lastTransaction: recent,
        count: nearAmount.length,
      ),
    );
  }
  suggestions.sort(
    (a, b) => b.lastTransaction.date.compareTo(a.lastTransaction.date),
  );
  return suggestions;
}

class SubscriptionSuggestion {
  final String merchant;
  final double amount;
  final RecurrenceRule recurrenceRule;
  final Transaction lastTransaction;
  final int count;

  const SubscriptionSuggestion({
    required this.merchant,
    required this.amount,
    required this.recurrenceRule,
    required this.lastTransaction,
    required this.count,
  });
}
