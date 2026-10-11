import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/store/app_store.dart';

class _Box implements Box {
  final _values = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('a fresh ledger does not invent a previous-month rollover', () {
    final store = AppStore(_Box());
    expect(
      store.effectiveMonthlyBudget(
        1000,
        rollover: true,
        month: DateTime(2026, 6),
      ),
      1000,
    );
    store.addTransaction(
      Transaction(
        note: '',
        amount: 250,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: DateTime(2026, 5, 10),
      ),
    );
    expect(
      store.effectiveMonthlyBudget(
        1000,
        rollover: true,
        month: DateTime(2026, 6),
      ),
      1750,
    );
    expect(
      store.effectiveMonthlyBudget(
        1000,
        rollover: false,
        month: DateTime(2026, 6),
      ),
      1000,
    );
  });

  test(
    'an overpaid credit card preserves a positive net-worth contribution',
    () {
      final store = AppStore(_Box());
      final card = Account(
        name: 'Card',
        type: AccountType.credit,
        currencyCode: 'USD',
        balance: -200,
      );
      store.addAccount(card);
      expect(store.creditUsedFor(card), 0);
      expect(store.netWorthFor(card), 200);
    },
  );

  test('goal allocation caps at the remainder and excludes credit cards', () {
    final store = AppStore(_Box());
    final savings = Account(
      name: 'Savings',
      type: AccountType.savings,
      currencyCode: 'USD',
      balance: 1000,
    );
    final card = Account(
      name: 'Card',
      type: AccountType.credit,
      currencyCode: 'USD',
      balance: 1000,
    );
    store.addAccount(savings);
    store.addAccount(card);
    final goal = SavingsGoal(
      name: 'Trip',
      targetAmount: 500,
      allocatedAmount: 450,
      accountId: savings.id,
    );
    store.addGoal(goal);
    expect(store.availableToAllocate(goal), 50);
    expect(store.allocateToGoal(goal, 200), 50);
    expect(goal.allocatedAmount, 500);
    final creditGoal = SavingsGoal(
      name: 'Invalid holder',
      targetAmount: 500,
      accountId: card.id,
    );
    store.addGoal(creditGoal);
    expect(store.availableToAllocate(creditGoal), 0);
    expect(store.allocateToGoal(creditGoal, 100), 0);
  });
}
