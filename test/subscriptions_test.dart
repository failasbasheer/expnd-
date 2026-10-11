import 'package:expnd/models/models.dart';
import 'package:expnd/services/subscriptions.dart';
import 'package:expnd/services/alerts.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction payment(String note, double amount, DateTime date) => Transaction(
  note: note,
  amount: amount,
  date: date,
  category: TransactionCategory.other,
  type: TransactionType.expense,
);

void main() {
  test('finds annual charges across three years', () {
    final rows = [
      payment('Backup', 30, DateTime(2024, 3, 1)),
      payment('Backup', 30, DateTime(2025, 3, 1)),
      payment('Backup', 30, DateTime(2026, 3, 1)),
    ];
    final suggestions = suggestSubscriptions(rows, now: DateTime(2026, 3, 20));
    expect(suggestions.single.recurrenceRule, RecurrenceRule.yearly);
  });

  test('does not recommend stale monthly charges', () {
    final rows = [
      payment('Music', 10, DateTime(2026, 1, 1)),
      payment('Music', 10, DateTime(2026, 2, 1)),
      payment('Music', 10, DateTime(2026, 3, 1)),
    ];
    expect(suggestSubscriptions(rows, now: DateTime(2026, 9)), isEmpty);
  });

  test('annual cost follows the recurrence period', () {
    final monthly = payment('Music', 10, DateTime(2026, 1));
    monthly.isRecurring = true;
    monthly.tags.add(subscriptionTag);
    expect(isSubscription(monthly), isTrue);
    expect(annualSubscriptionCost(monthly), 120);
    monthly.recurrenceRule = RecurrenceRule.yearly;
    expect(annualSubscriptionCost(monthly), 10);
  });

  test('suggests repeated monthly charges without changing the ledger', () {
    final rows = [
      payment('Music monthly', 9.99, DateTime(2026, 1, 15)),
      payment('Music payment', 9.99, DateTime(2026, 2, 15)),
      payment('Music charge', 10.49, DateTime(2026, 3, 15)),
    ];
    final suggestions = suggestSubscriptions(rows, now: DateTime(2026, 3, 20));
    expect(suggestions, hasLength(1));
    expect(suggestions.single.recurrenceRule, RecurrenceRule.monthly);
    expect(rows.every((row) => !row.isRecurring), isTrue);
  });

  test('does not suggest irregular charges', () {
    final rows = [
      payment('Market', 30, DateTime(2026, 1, 1)),
      payment('Market', 31, DateTime(2026, 1, 8)),
      payment('Market', 29, DateTime(2026, 2, 25)),
    ];
    expect(suggestSubscriptions(rows, now: DateTime(2026, 3)), isEmpty);
  });

  test('reminds before a tracked trial ends without claiming cancellation', () {
    final transaction = payment('Streaming', 8, DateTime(2026, 3, 1));
    transaction.isRecurring = true;
    transaction.tags.add(subscriptionTag);
    transaction.subscriptionTrialEndDate = DateTime(2026, 3, 20);
    final alerts = trialEndAlerts([transaction], from: DateTime(2026, 3, 10));
    expect(alerts, hasLength(1));
    expect(alerts.single.fireAt, DateTime(2026, 3, 17, 21));
    expect(alerts.single.body, contains('Review'));
    expect(trialEndAlerts([transaction], from: DateTime(2026, 3, 18)), isEmpty);
  });
}
