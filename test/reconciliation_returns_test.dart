import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:expnd/screens/reconciliation_view.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/services/reconciliation.dart';
import 'package:expnd/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _Box implements Box {
  final Map<dynamic, dynamic> data = {};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('comparison enables as balance is typed and supports overdrafts', (tester) async {
    final store = AppStore(_Box());
    store.addAccount(Account(name: 'Bank', type: AccountType.bank,
        currencyCode: 'USD', balance: -20));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store,
      child: const MaterialApp(home: ReconciliationView())));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,
        'Compare balances')).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '20');
    await tester.pump();
    await tester.tap(find.text('Negative balance'));
    await tester.pump();
    await tester.tap(find.text('Compare balances'));
    await tester.pump();
    expect(find.text('Balances match'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '25');
    await tester.pump();
    expect(find.text('Balances match'), findsNothing);
  });

  test(
    'reconciliation uses entries through statement date and flags repeats',
    () {
      final store = AppStore(_Box());
      final account = Account(
        name: 'Bank',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 100,
      );
      store.addAccount(account);
      for (final day in [1, 2]) {
        store.addTransaction(
          Transaction(
            note: 'Coffee',
            amount: 5,
            category: TransactionCategory.food,
            type: TransactionType.expense,
            date: DateTime(2026, 6, day),
            accountId: account.id,
          ),
        );
      }
      store.addTransaction(
        Transaction(
          note: 'Later',
          amount: 10,
          category: TransactionCategory.food,
          type: TransactionType.expense,
          date: DateTime(2026, 6, 4),
          accountId: account.id,
        ),
      );
      final result = reconcileAccount(
        store: store,
        account: account,
        statementBalance: 95,
        statementDate: DateTime(2026, 6, 2),
      );
      expect(result.ledgerBalance, 90);
      expect(result.difference, 5);
      expect(result.possibleDuplicates, hasLength(1));
    },
  );

  test('partial reimbursement and refund are real linked income', () {
    final store = AppStore(_Box());
    final account = Account(
      name: 'Bank',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 100,
    );
    store.addAccount(account);
    final purchase = Transaction(
      note: 'Train',
      amount: 40,
      category: TransactionCategory.transport,
      type: TransactionType.expense,
      accountId: account.id,
    );
    store.addTransaction(purchase);
    store.trackReimbursement(purchase, expected: 30, from: 'Work');
    store.recordPurchaseReturn(
      purchase,
      amount: 10,
      accountId: account.id,
      kind: 'reimbursement',
    );
    store.recordPurchaseReturn(
      purchase,
      amount: 5,
      accountId: account.id,
      kind: 'refund',
    );
    expect(store.balanceFor(account), 75);
    expect(store.reimbursementOutstanding(purchase), 20);
    expect(store.returnedFor(purchase, kind: 'refund'), 5);
    expect(
      () => store.recordPurchaseReturn(
        purchase,
        amount: 26,
        accountId: account.id,
        kind: 'refund',
      ),
      throwsArgumentError,
    );
    expect(Transaction.fromJson(purchase.toJson()).reimbursementFrom, 'Work');
    expect(
      Transaction.fromJson(purchase.toJson()).subscriptionTrialEndDate,
      isNull,
    );
    expect(
      () => store.recordPurchaseReturn(
        purchase,
        amount: 21,
        accountId: account.id,
        kind: 'reimbursement',
      ),
      throwsArgumentError,
    );
  });

  test('old transaction JSON loads without new fields', () {
    final original = Transaction(
      amount: 12,
      category: TransactionCategory.other,
      type: TransactionType.expense,
    );
    final json = original.toJson()
      ..remove('relatedPurchaseId')
      ..remove('relatedPurchaseKind')
      ..remove('reimbursementExpected')
      ..remove('reimbursementFrom')
      ..remove('subscriptionTrialEndDate');
    final restored = Transaction.fromJson(json);
    expect(restored.reimbursementExpected, isNull);
    expect(restored.relatedPurchaseId, isNull);
    expect(restored.subscriptionTrialEndDate, isNull);
  });
}
