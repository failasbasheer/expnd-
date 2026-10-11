// History keeps secondary filters compact and preserves active selections when
// the controls are collapsed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/screens/history_view.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';

class _FakeBox implements Box {
  final Map<dynamic, dynamic> _m = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _m[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _m[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _today = DateTime.now();
DateTime _daysAgo(int d) => _today.subtract(Duration(days: d));

Future<AppStore> _seeded() async {
  final store = AppStore(_FakeBox());
  final checking = Account(
    name: 'HDFC Checking',
    type: AccountType.bank,
    currencyCode: 'USD',
    balance: 6400,
  );
  store.addAccount(checking);

  // Two today, three well before it — enough that a date filter has something
  // to exclude.
  store.addTransaction(
    Transaction(
      note: 'Coffee today',
      amount: 4,
      category: TransactionCategory.food,
      type: TransactionType.expense,
      date: _today,
      accountId: checking.id,
      tags: const ['osaka'],
    ),
  );
  store.addTransaction(
    Transaction(
      note: 'Fuel today',
      amount: 62,
      category: TransactionCategory.transport,
      type: TransactionType.expense,
      date: _today,
      accountId: checking.id,
    ),
  );
  for (var i = 1; i <= 3; i++) {
    store.addTransaction(
      Transaction(
        note: 'Older spend $i',
        amount: 20.0 * i,
        category: TransactionCategory.groceries,
        type: TransactionType.expense,
        date: _daysAgo(i + 4),
        accountId: checking.id,
      ),
    );
  }
  return store;
}

Future<void> _pump(
  WidgetTester tester, {
  DateTime? start,
  DateTime? end,
}) async {
  final store = await _seeded();
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.create();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: store),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        debugShowCheckedModeBanner: false,
        home: Material(
          type: MaterialType.transparency,
          child: HistoryView(initialStartDate: start, initialEndDate: end),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _showFilters = find.byTooltip('Show category, account and tag filters');
final _hideFilters = find.byTooltip('Hide category, account and tag filters');

void main() {
  testWidgets('clear filters restores all entries after an empty search', (
    tester,
  ) async {
    await _pump(tester, start: _today, end: _today);
    await tester.enterText(find.byType(TextField).first, 'does not exist');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('5 transactions'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  testWidgets('opens with only search and the type row', (tester) async {
    await _pump(tester);

    // Type segments stay out — they are the filter people reach for most.
    // Found by their spoken names: the shared picker shows caps labels, and
    // INCOME/EXPENSE also label every transaction row in the list below.
    final transfer = find.bySemanticsLabel('Transfer');
    final all = find.bySemanticsLabel('All transactions');
    expect(transfer, findsOneWidget);
    expect(tester.getTopLeft(transfer).dy, tester.getTopLeft(all).dy);

    expect(find.text('Category'), findsNothing);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Tag'), findsNothing);

    expect(_showFilters, findsOneWidget);
  });

  testWidgets('the toggle reveals and hides compact selectors', (tester) async {
    await _pump(tester);

    await tester.tap(_showFilters);
    await tester.pumpAndSettle();

    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(_hideFilters, findsOneWidget);

    await tester.tap(_hideFilters);
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsNothing);
  });

  testWidgets('a filter set while expanded keeps applying once collapsed, '
      'and says so', (tester) async {
    await _pump(tester);

    await tester.tap(_showFilters);
    await tester.pumpAndSettle();

    // Narrow to a tag that only one of the five transactions carries.
    await tester.tap(find.text('Tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#osaka'));
    await tester.pumpAndSettle();
    expect(find.text('1 transaction'), findsOneWidget);

    await tester.tap(_hideFilters);
    await tester.pumpAndSettle();

    // Still filtered — collapsing hides the control, not the effect — and the
    // toggle carries a count so the narrowing is never invisible.
    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('#osaka'), findsNothing);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('an initial date range opens already narrowed to it', (
    tester,
  ) async {
    await _pump(tester, start: _today, end: _today);

    // Only the two transactions dated today survive the seeded range.
    expect(find.text('2 transactions'), findsOneWidget);
    expect(find.text('Coffee today'), findsOneWidget);
    expect(find.text('Older spend 1'), findsNothing);
  });

  testWidgets('with no initial range every transaction is listed', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('5 transactions'), findsOneWidget);
  });
}
