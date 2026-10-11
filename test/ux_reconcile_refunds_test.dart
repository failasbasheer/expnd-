import 'package:expnd/models/models.dart';
import 'package:expnd/screens/reconciliation_view.dart';
import 'package:expnd/screens/reimbursements_view.dart';
import 'package:expnd/store/app_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

class _Box implements Box {
  final Map<dynamic, dynamic> data = {};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(AppStore store, Widget home) => ChangeNotifierProvider.value(
  value: store,
  child: MaterialApp(home: home),
);

void main() {
  testWidgets('reconciliation explains the difference in plain words', (
    tester,
  ) async {
    final store = AppStore(_Box());
    store.addAccount(
      Account(
        name: 'Bank',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 100,
      ),
    );
    await tester.pumpWidget(_app(store, const ReconciliationView()));
    await tester.enterText(find.byType(TextField), '130');
    await tester.pump();
    await tester.tap(find.text('Compare balances'));
    await tester.pump();
    expect(find.text('Difference to review'), findsOneWidget);
    expect(find.textContaining('more than EXPND'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Nothing has been changed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Nothing has been changed'), findsOneWidget);
    // Comparing never alters the ledger.
    expect(store.balanceFor(store.accounts.first), 100);
  });

  testWidgets('reimbursements empty state tells the user what to do', (
    tester,
  ) async {
    final store = AppStore(_Box());
    await tester.pumpWidget(_app(store, const ReimbursementsView()));
    expect(find.textContaining('Add an expense first'), findsOneWidget);
  });

  testWidgets('stop tracking asks for confirmation first', (tester) async {
    final store = AppStore(_Box());
    final account = Account(
      name: 'Bank',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 0,
    );
    store.addAccount(account);
    final purchase = Transaction(
      note: 'Team lunch',
      amount: 60,
      category: TransactionCategory.food,
      type: TransactionType.expense,
      accountId: account.id,
    );
    store.addTransaction(purchase);
    store.trackReimbursement(purchase, expected: 40, from: 'Alex');
    await tester.pumpWidget(_app(store, const ReimbursementsView()));

    await tester.tap(find.text('Edit tracking'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Stop tracking'));
    await tester.pumpAndSettle();
    expect(find.text('Stop tracking?'), findsOneWidget);
    await tester.tap(find.text('Keep tracking'));
    await tester.pumpAndSettle();
    expect(purchase.reimbursementExpected, 40);

    await tester.tap(find.widgetWithText(TextButton, 'Stop tracking'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stop tracking'));
    await tester.pumpAndSettle();
    expect(purchase.reimbursementExpected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recording a reimbursement posts a linked transaction', (
    tester,
  ) async {
    final store = AppStore(_Box());
    final account = Account(
      name: 'Bank',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 0,
    );
    store.addAccount(account);
    final purchase = Transaction(
      note: 'Taxi',
      amount: 30,
      category: TransactionCategory.transport,
      type: TransactionType.expense,
      accountId: account.id,
    );
    store.addTransaction(purchase);
    store.trackReimbursement(purchase, expected: 30, from: 'Work');
    await tester.pumpWidget(_app(store, const ReimbursementsView()));
    await tester.tap(find.text('Record reimbursement'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pumpAndSettle();
    expect(store.returnedFor(purchase, kind: 'reimbursement'), 30);
    expect(store.balanceFor(account), 0);
    expect(find.text('Reimbursement recorded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('money back for a deleted purchase is kept or deleted', (
    tester,
  ) async {
    final store = AppStore(_Box());
    final account = Account(
      name: 'Bank',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 0,
    );
    store.addAccount(account);
    final purchase = Transaction(
      amount: 20,
      category: TransactionCategory.food,
      type: TransactionType.expense,
      accountId: account.id,
    );
    store.addTransaction(purchase);
    final refund = store.recordPurchaseReturn(
      purchase,
      amount: 5,
      accountId: account.id,
      kind: 'refund',
    );
    final reimbursement = store.recordPurchaseReturn(
      purchase,
      amount: 5,
      accountId: account.id,
      kind: 'refund',
    );
    store.deleteTransaction(purchase);
    await tester.pumpWidget(
      _app(store, ReimbursementsView(purchaseId: purchase.id)),
    );
    expect(find.text('Original purchase deleted'), findsNWidgets(2));
    // Empty purchase note never leaves a blank or "Refund:" title.
    expect(find.text('Refund'), findsNWidgets(2));

    await tester.scrollUntilVisible(
      find.text('Keep as income').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Keep as income').first);
    await tester.pump();
    expect(
      [refund, reimbursement].where((t) => t.relatedPurchaseId == null),
      hasLength(1),
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Delete'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.transactions, hasLength(1));
    expect(store.balanceFor(account), 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both screens fit 320dp at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = AppStore(_Box());
    final account = Account(
      name: 'A very long everyday checking account name',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 123456.78,
    );
    store.addAccount(account);
    final purchase = Transaction(
      note: 'Conference hotel and flights for the annual offsite',
      amount: 98765.43,
      category: TransactionCategory.transport,
      type: TransactionType.expense,
      accountId: account.id,
    );
    store.addTransaction(purchase);
    store.trackReimbursement(purchase, expected: 50000, from: 'Employer Inc');
    Widget scaled(Widget home) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: home,
          ),
        ),
      ),
    );
    await tester.pumpWidget(scaled(const ReimbursementsView()));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(scaled(const ReconciliationView()));
    await tester.scrollUntilVisible(find.byType(TextField),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '1');
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Compare balances'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Compare balances'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
