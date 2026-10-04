import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/screens/add_transaction.dart';
import 'package:expnd/screens/plan_view.dart';
import 'package:expnd/screens/upcoming_view.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';

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

Future<void> _pump(WidgetTester tester, Widget screen, AppStore store) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1800);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.create();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recurring rules stay reachable when nothing is due in 30 days', (
    tester,
  ) async {
    final store = AppStore(_FakeBox());
    final rule = Transaction(
      note: 'Annual insurance',
      amount: 120,
      category: TransactionCategory.insurance,
      type: TransactionType.expense,
      date: DateTime.now(),
      isRecurring: true,
      recurrenceRule: RecurrenceRule.yearly,
    );
    rule.nextDueDate = DateTime.now().add(const Duration(days: 90));
    store.addTransaction(rule);
    await _pump(tester, const UpcomingView(), store);
    expect(find.text('RECURRING RULES'), findsOneWidget);
    expect(find.text('Annual insurance'), findsOneWidget);
  });

  testWidgets(
    'entry explains missing fields and keeps advanced controls optional',
    (tester) async {
      await _pump(tester, const AddTransactionScreen(), AppStore(_FakeBox()));
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
      expect(find.text('Repeat Transaction'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '25');
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a category to save this transaction'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Repeat Transaction'), findsOneWidget);
      expect(find.text('Split across categories'), findsOneWidget);
    },
  );

  testWidgets('editing reveals saved options and collapse preserves them', (
    tester,
  ) async {
    final store = AppStore(_FakeBox());
    final original = Transaction(
      note: 'Monthly membership',
      amount: 25,
      category: TransactionCategory.subscription,
      type: TransactionType.expense,
      date: DateTime.now(),
      isRecurring: true,
      tags: ['personal'],
    );
    store.addTransaction(original);
    await _pump(tester, AddTransactionScreen(editing: original), store);
    expect(find.text('Repeat Transaction'), findsOneWidget);
    await tester.ensureVisible(find.text('More options'));
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Repeat Transaction'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(store.transactions.single.amount, 30);
    expect(store.transactions.single.isRecurring, isTrue);
    expect(store.transactions.single.tags, ['personal']);
  });

  testWidgets('a category outside the shortlist stays visible while editing', (
    tester,
  ) async {
    final store = AppStore(_FakeBox());
    final uncommon = TransactionCategory.categoriesFor(
      TransactionType.expense,
    ).last;
    final original = Transaction(
      note: '',
      amount: 12,
      category: uncommon,
      type: TransactionType.expense,
      date: DateTime.now(),
    );
    await _pump(tester, AddTransactionScreen(editing: original), store);
    expect(find.text(uncommon.raw), findsOneWidget);
  });

  testWidgets('planning switches tasks while retaining budget input', (
    tester,
  ) async {
    await _pump(tester, const PlanView(), AppStore(_FakeBox()));
    expect(find.text('Category budgets'), findsOneWidget);
    final budget = find.byType(TextField).first;
    await tester.enterText(budget, '2400');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Savings goals'));
    await tester.pumpAndSettle();
    expect(find.text('Category budgets'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Debts & loans'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Budgets'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '2400',
    );
  });
}
