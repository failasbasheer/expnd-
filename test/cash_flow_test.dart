import 'package:expnd/models/models.dart';
import 'package:expnd/services/cash_flow.dart';
import 'package:expnd/services/alerts.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:expnd/screens/cash_flow_view.dart';
import 'package:expnd/theme/expnd_theme.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBox implements Box {
  final Map<dynamic, dynamic> data = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<SettingsStore> _settings() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsStore(await SharedPreferences.getInstance());
}

void main() {
  testWidgets('payday setup reveals the estimate after confirming the date', (
    tester,
  ) async {
    final settings = await _settings();
    final store = AppStore(_FakeBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          theme: buildExpndTheme(Brightness.light),
          home: const CashFlowView(),
        ),
      ),
    );
    expect(find.text('Set your payday'), findsOneWidget);
    expect(find.text('Available to spend'), findsNothing);
    final confirm = find.text('Confirm day ${settings.paydayDay} as my payday');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(settings.paydayConfigured, isTrue);
    expect(find.text('Set your payday'), findsNothing);
    expect(find.text('Available to spend'), findsOneWidget);
  });

  test(
    'budget alerts use payday period spending and deduplicate that period',
    () {
      final store = AppStore(_FakeBox());
      final period = BudgetPeriod(
        DateTime(2026, 9, 25),
        DateTime(2026, 10, 25),
      );
      store.addTransaction(
        Transaction(
          amount: 150,
          category: TransactionCategory.food,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 26),
        ),
      );
      final now = DateTime(2026, 10, 9);
      expect(
        overBudgetAlert(
          store,
          'USD',
          monthlyBudget: 100,
          lastAlertedMonth: 0,
          period: period,
          from: now,
        ),
        isNotNull,
      );
      expect(
        overBudgetAlert(
          store,
          'USD',
          monthlyBudget: 100,
          lastAlertedMonth: budgetAlertKey(now, period: period),
          period: period,
          from: now,
        ),
        isNull,
      );
      expect(
        overBudgetAlert(
          store,
          'USD',
          monthlyBudget: 100,
          lastAlertedMonth: 0,
          from: now,
        ),
        isNull,
      );
    },
  );

  test('existing users retain calendar month budgets', () async {
    final settings = await _settings();
    expect(settings.paydayConfigured, isFalse);
    final period = budgetPeriodFor(settings, DateTime(2026, 2, 20));
    expect(period.start, DateTime(2026, 2));
    expect(period.end, DateTime(2026, 3));
  });

  test('payday setup tracks the selected cycle', () async {
    final settings = await _settings();
    settings.paydayDay = 9;
    expect(settings.paydayConfigured, isTrue);
    settings.budgetCycle = 'fortnightly';
    expect(settings.paydayConfigured, isFalse);
    settings.paydayAnchor = DateTime(2026, 10, 9);
    expect(settings.paydayConfigured, isTrue);
    final backup = settings.backupSnapshot();
    expect(backup['paydayDay'], 9);
    expect(backup['paydayAnchor'], '2026-10-09');
  });

  test('payday period clamps the 31st in shorter months', () async {
    final settings = await _settings();
    settings.budgetCycle = 'payday';
    settings.paydayDay = 31;
    final period = budgetPeriodFor(settings, DateTime(2026, 2, 15));
    expect(period.start, DateTime(2026, 1, 31));
    expect(period.end, DateTime(2026, 2, 28));
    expect(
      nextPaydayFor(settings, DateTime(2026, 2, 28)),
      DateTime(2026, 3, 31),
    );
  });

  test('weekly and fortnightly periods work before an anchor', () async {
    final settings = await _settings();
    settings.paydayAnchor = DateTime(2026, 10, 9);
    settings.budgetCycle = 'weekly';
    expect(
      budgetPeriodFor(settings, DateTime(2026, 10, 8)).start,
      DateTime(2026, 10, 2),
    );
    settings.budgetCycle = 'fortnightly';
    expect(
      budgetPeriodFor(settings, DateTime(2026, 10, 8)).start,
      DateTime(2026, 9, 25),
    );
    expect(
      budgetPeriodFor(settings, DateTime(2026, 10, 9)).end,
      DateTime(2026, 10, 23),
    );
  });

  test(
    'spendable reserves goals and bills but excludes future income',
    () async {
      final settings = await _settings();
      settings.paydayDay = 15;
      final store = AppStore(_FakeBox());
      final bank = Account(
        name: 'Bank',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 1300,
      );
      store.addAccount(bank);
      store.addGoal(
        SavingsGoal(
          name: 'Holiday',
          targetAmount: 500,
          allocatedAmount: 200,
          accountId: bank.id,
        ),
      );
      final rent = Transaction(
        amount: 300,
        category: TransactionCategory.rent,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 12),
        isRecurring: true,
        note: 'Rent',
        accountId: bank.id,
      );
      rent.nextDueDate = DateTime(2026, 10, 12);
      store.addTransaction(rent);
      final salary = Transaction(
        amount: 2000,
        category: TransactionCategory.salary,
        type: TransactionType.income,
        date: DateTime(2026, 10, 14),
        isRecurring: true,
      );
      salary.nextDueDate = DateTime(2026, 10, 14);
      store.addTransaction(salary);
      final result = estimateUntilPayday(
        store,
        settings,
        from: DateTime(2026, 10, 9),
      );
      expect(result.nextPayday, DateTime(2026, 10, 15));
      expect(result.liquidBalance, 1000);
      expect(result.reservedForGoals, 200);
      expect(result.upcomingBills, 300);
      expect(result.spendable, 500);
      expect(result.excludedBills, isEmpty);
    },
  );

  test(
    'estimate separates account currencies and discloses unknown bills',
    () async {
      final settings = await _settings();
      settings.currencyCode = 'USD';
      settings.paydayDay = 15;
      final store = AppStore(_FakeBox());
      final dollars = Account(
        name: 'USD cash',
        type: AccountType.cash,
        currencyCode: 'USD',
        balance: 1100,
      );
      final euros = Account(
        name: 'EUR bank',
        type: AccountType.bank,
        currencyCode: 'EUR',
        balance: 5200,
      );
      store.addAccount(dollars);
      store.addAccount(euros);
      Transaction bill(String name, double amount, String? accountId) {
        final transaction = Transaction(
          amount: amount,
          category: TransactionCategory.other,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 12),
          isRecurring: true,
          note: name,
          accountId: accountId,
        );
        transaction.nextDueDate = DateTime(2026, 10, 12);
        return transaction;
      }

      store.addTransaction(bill('USD bill', 100, dollars.id));
      store.addTransaction(bill('EUR bill', 200, euros.id));
      store.addTransaction(bill('Unlinked bill', 50, null));
      final estimate = estimateUntilPayday(
        store,
        settings,
        from: DateTime(2026, 10, 9),
      );
      expect(estimate.liquidBalance, 1000);
      expect(estimate.upcomingBills, 100);
      expect(estimate.spendable, 900);
      expect(estimate.bills.map((bill) => bill.title), ['USD bill']);
      expect(estimate.excludedBills.map((bill) => bill.title), [
        'EUR bill',
        'Unlinked bill',
      ]);
    },
  );

  test('budget period includes start and excludes next payday', () async {
    final settings = await _settings();
    settings.budgetCycle = 'payday';
    settings.paydayDay = 9;
    final period = budgetPeriodFor(settings, DateTime(2026, 10, 9));
    final store = AppStore(_FakeBox());
    for (final day in [8, 9]) {
      store.addTransaction(
        Transaction(
          amount: 10,
          category: TransactionCategory.food,
          type: TransactionType.expense,
          date: DateTime(2026, 11, day),
        ),
      );
    }
    expect(budgetSpentInPeriod(store, period), 10);
  });
}
