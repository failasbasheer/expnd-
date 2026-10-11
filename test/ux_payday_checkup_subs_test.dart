import 'package:expnd/models/models.dart';
import 'package:expnd/screens/cash_flow_view.dart';
import 'package:expnd/screens/money_checkup_view.dart';
import 'package:expnd/screens/subscriptions_view.dart';
import 'package:expnd/services/money_checkup.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/theme/expnd_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBox implements Box {
  final Map<dynamic, dynamic> _values = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => _values[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<(AppStore, SettingsStore)> _stores() async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore(await SharedPreferences.getInstance());
  settings.currencyCode = 'USD';
  final store = AppStore(_FakeBox());
  store.addAccount(
    Account(
      name: 'Bank',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 1000,
    ),
  );
  return (store, settings);
}

/// Pushes [screen] over a launcher page so the close action is present.
Future<void> _pump(
  WidgetTester tester,
  AppStore store,
  SettingsStore settings,
  Widget screen, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(
        theme: buildExpndTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('purchase preview exposes the parts of the available figure', () async {
    final (store, _) = await _stores();
    final preview = previewPurchase(
      store,
      amount: 100,
      monthlyBudget: 0,
      budgetRollover: false,
    );
    expect(preview.cash, 1000);
    expect(
      preview.availableAfterBills,
      preview.cash - preview.upcomingBills - preview.reservedForGoals,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('purchase preview shows its calculation ($brightness, 2x)', (
      tester,
    ) async {
      final (store, settings) = await _stores();
      await _pump(
        tester,
        store,
        settings,
        const PurchasePreviewView(),
        brightness: brightness,
        textScale: 2,
      );
      expect(find.bySemanticsLabel('Close plan a purchase'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '250');
      await tester.pumpAndSettle();
      expect(find.text('Cash and savings balances'), findsOneWidget);
      expect(find.text('Available before purchase'), findsOneWidget);
      expect(find.text('This purchase'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Close plan a purchase'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  }

  testWidgets('until payday fits 320dp at 2x text once configured', (
    tester,
  ) async {
    final (store, settings) = await _stores();
    settings.paydayDay = 25;
    await _pump(tester, store, settings, const CashFlowView(), textScale: 2);
    expect(find.text('Available to spend'), findsOneWidget);
    expect(find.bySemanticsLabel('Close until payday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly review guides an empty month', (tester) async {
    final (store, settings) = await _stores();
    await _pump(
      tester,
      store,
      settings,
      const MonthlyReviewView(),
      brightness: Brightness.dark,
      textScale: 2,
    );
    expect(find.textContaining('No expenses recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tracking a recurring payment can be undone', (tester) async {
    final (store, settings) = await _stores();
    final payment = Transaction(
      note: 'Music',
      amount: 10,
      category: TransactionCategory.other,
      type: TransactionType.expense,
      date: DateTime.now(),
      isRecurring: true,
      nextDueDate: DateTime.now().add(const Duration(days: 20)),
    );
    store.addTransaction(payment);
    await _pump(tester, store, settings, const SubscriptionManagerView());
    expect(find.bySemanticsLabel('Close subscriptions'), findsOneWidget);
    await tester.tap(find.text('Track'));
    await tester.pumpAndSettle();
    expect(payment.tags, contains('subscription'));
    expect(find.textContaining('a month'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(payment.tags, isNot(contains('subscription')));
  });
}
