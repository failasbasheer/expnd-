import 'package:expnd/models/models.dart';
import 'package:expnd/theme/currencies.dart';
import 'package:expnd/theme/expnd_theme.dart';
import 'package:expnd/widgets/filter_totals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(TransactionType type, double amount) => Transaction(
  amount: amount,
  category: type == TransactionType.income
      ? TransactionCategory.salary
      : TransactionCategory.food,
  type: type,
  date: DateTime(2026, 10, 5),
);

Future<void> _pump(WidgetTester tester, List<Transaction> txns) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildExpndTheme(Brightness.dark),
        home: Scaffold(
          body: FilterTotals(transactions: txns, currencyCode: 'USD'),
        ),
      ),
    );

void main() {
  tearDown(() => AmountPrivacy.hidden = false);

  testWidgets('mixed list shows in, out and net', (tester) async {
    await _pump(tester, [
      _t(TransactionType.income, 1000),
      _t(TransactionType.expense, 250.5),
      _t(TransactionType.transfer, 999),
    ]);
    expect(find.textContaining('+\$1,000.00'), findsOneWidget);
    expect(find.textContaining('−\$250.50'), findsOneWidget);
    // Transfers are neither income nor spending.
    expect(find.textContaining('+\$749.50'), findsOneWidget);
  });

  testWidgets('a single-type filter shows just that total', (tester) async {
    await _pump(tester, [
      _t(TransactionType.expense, 40),
      _t(TransactionType.expense, 60),
    ]);
    expect(find.textContaining('−\$100.00'), findsOneWidget);
    expect(find.textContaining('NET'), findsNothing);
    expect(find.textContaining('IN '), findsNothing);
  });

  testWidgets('totals hide with the amounts', (tester) async {
    AmountPrivacy.hidden = true;
    await _pump(tester, [_t(TransactionType.expense, 60)]);
    expect(find.textContaining('60'), findsNothing);
  });
}
