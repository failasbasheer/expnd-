// A statement is something a person reads and may hand to someone else, so
// the figures in it have to be right and the shape has to survive an empty
// month, a long payee name and a category that dominates the total.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/services/statement.dart';
import 'package:expnd/store/app_store.dart';

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

void main() {
  final june = DateTime(2026, 6);
  final generated = DateTime(2026, 7, 1);

  AppStore store() => AppStore(_FakeBox());

  void add(
    AppStore s,
    double amount,
    int day, {
    TransactionType type = TransactionType.expense,
    TransactionCategory cat = TransactionCategory.food,
    String note = '',
  }) {
    s.addTransaction(
      Transaction(
        note: note,
        amount: amount,
        category: cat,
        type: type,
        date: DateTime(2026, 6, day),
      ),
    );
  }

  String run(AppStore s) =>
      buildMonthlyStatement(s, 'USD', june, generatedAt: generated);

  test('an empty month says so instead of printing empty tables', () {
    final out = run(store());
    expect(out, contains('No transactions recorded this month'));
    expect(out, isNot(contains('SPENDING BY CATEGORY')));
  });

  test('totals income, expenses and the net between them', () {
    final s = store();
    add(s, 3000, 1, type: TransactionType.income);
    add(s, 400, 5);
    add(s, 100, 6);
    final out = run(s);

    expect(out, contains('SUMMARY'));
    expect(out, contains('3,000.00')); // income
    expect(out, contains('500.00')); // expenses
    expect(out, contains('2,500.00')); // net
    expect(out, contains('Transactions'));
  });

  test('breaks spending down by category with a share of the total', () {
    final s = store();
    add(s, 750, 2, cat: TransactionCategory.rent);
    add(s, 250, 3, cat: TransactionCategory.food);
    final out = run(s);

    expect(out, contains('SPENDING BY CATEGORY'));
    expect(out, contains('Rent'));
    // 750 of 1000 is 75% of the month's spending.
    expect(out, contains('75%'));
    // Biggest first, so the eye lands on what actually cost money.
    expect(out.indexOf('Rent'), lessThan(out.indexOf('Food')));
  });

  test('only counts the month asked for', () {
    final s = store();
    add(s, 100, 5);
    s.addTransaction(
      Transaction(
        amount: 9999,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: DateTime(2026, 5, 20), // the month before
      ),
    );
    expect(run(s), isNot(contains('9,999')));
  });

  test('lists every transaction under its own day', () {
    final s = store();
    add(s, 12, 4, note: 'Coffee');
    add(s, 30, 4, note: 'Lunch');
    add(s, 60, 9, note: 'Petrol');
    final out = run(s);

    expect(out, contains('TRANSACTIONS'));
    expect(out, contains('Coffee'));
    expect(out, contains('Petrol'));
    // One heading per day, not per transaction.
    expect('Jun 4, 2026'.allMatches(out).length, 1);
  });

  test('signs each line by direction', () {
    final s = store();
    add(s, 500, 2, type: TransactionType.income, note: 'Salary');
    add(s, 40, 3, note: 'Groceries');
    final out = run(s);
    expect(out, contains('+'));
    expect(out, contains('-'));
  });

  test('a long payee is truncated rather than breaking the column', () {
    final s = store();
    add(s, 40, 3, note: 'A' * 90);
    for (final line in run(s).split('\n')) {
      expect(
        line.length,
        lessThanOrEqualTo(48),
        reason: 'columns must stay aligned in a monospaced viewer',
      );
    }
  });

  test('carries the name when there is one', () {
    final s = store();
    add(s, 40, 3);
    final out = buildMonthlyStatement(
      s,
      'USD',
      june,
      userName: 'Failas',
      generatedAt: generated,
    );
    expect(out, contains('Failas'));
    expect(out, contains('June 2026'));
  });
}
