// Insights are sentences shown beside someone's money, so every one has to be
// arithmetic they could redo by hand. These tests pin the thresholds — when a
// line appears, when it stays quiet — because a nag that fires on noise is
// worse than saying nothing at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/services/insights.dart';
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
  // Mid-month so budget-pace maths has a meaningful elapsed fraction, and far
  // enough in that the "too early to say" guard has passed.
  final now = DateTime(2026, 6, 15);

  AppStore store() => AppStore(_FakeBox());

  void spend(
    AppStore s,
    double amount,
    DateTime date, {
    TransactionCategory cat = TransactionCategory.food,
    String note = '',
  }) {
    s.addTransaction(
      Transaction(
        note: note,
        amount: amount,
        category: cat,
        type: TransactionType.expense,
        date: date,
      ),
    );
  }

  List<Insight> run(AppStore s, {double budget = 0}) =>
      buildInsights(s, 'USD', from: now, monthlyBudget: budget);

  bool has(List<Insight> list, String fragment) =>
      list.any((i) => i.title.contains(fragment));

  group('an empty ledger', () {
    test('says nothing rather than inventing something', () {
      expect(run(store()), isEmpty);
    });
  });

  group('budget pace', () {
    test('flags being already over the limit', () {
      final s = store();
      spend(s, 1200, DateTime(2026, 6, 10));
      final out = run(s, budget: 1000);
      expect(has(out, 'Over budget by'), isTrue);
      expect(out.first.tone, InsightTone.warn);
    });

    test('flags a pace that will overshoot before month end', () {
      final s = store();
      // Half the month gone, 80% of the budget spent.
      spend(s, 800, DateTime(2026, 6, 10));
      final out = run(s, budget: 1000);
      expect(has(out, 'On pace to overspend'), isTrue);
    });

    test('reassures when the pace lands under', () {
      final s = store();
      spend(s, 200, DateTime(2026, 6, 10));
      final out = run(s, budget: 1000);
      expect(has(out, 'On track to finish'), isTrue);
      expect(
        out.firstWhere((i) => i.title.contains('On track')).tone,
        InsightTone.good,
      );
    });

    test('stays quiet about pace when no budget is set', () {
      final s = store();
      spend(s, 800, DateTime(2026, 6, 10));
      final out = run(s);
      expect(has(out, 'On pace'), isFalse);
      expect(has(out, 'On track'), isFalse);
    });
  });

  test('early-month pace is quiet unless the budget is already exceeded', () {
    final s = store();
    spend(s, 700, DateTime(2026, 6, 1));
    final out = buildInsights(
      s,
      'USD',
      from: DateTime(2026, 6, 2),
      monthlyBudget: 1000,
    );
    expect(has(out, 'On pace'), isFalse);
    spend(s, 400, DateTime(2026, 6, 2));
    expect(
      has(
        buildInsights(
          s,
          'USD',
          from: DateTime(2026, 6, 2),
          monthlyBudget: 1000,
        ),
        'Over budget',
      ),
      isTrue,
    );
  });

  test('future entries do not inflate spending or conceal a stale ledger', () {
    final s = store();
    spend(s, 20, DateTime(2026, 6, 1));
    spend(s, 5000, DateTime(2026, 6, 25));
    final out = run(s, budget: 1000);
    expect(has(out, 'Over budget'), isFalse);
    expect(has(out, 'On pace'), isFalse);
    expect(has(out, 'Nothing logged in 14 days'), isTrue);
  });

  test('category comparison uses the same elapsed days of prior months', () {
    final s = store();
    for (final month in [3, 4, 5]) {
      spend(s, 100, DateTime(2026, month, 10));
      spend(s, 900, DateTime(2026, month, 25));
    }
    spend(s, 100, DateTime(2026, 6, 10));
    expect(has(run(s), 'Food is'), isFalse);
  });

  group('category vs its own average', () {
    void threeQuietMonths(AppStore s, double each) {
      for (final m in [3, 4, 5]) {
        spend(s, each, DateTime(2026, m, 12));
      }
    }

    test('reports a real rise', () {
      final s = store();
      threeQuietMonths(s, 100);
      spend(s, 200, DateTime(2026, 6, 5)); // double the average
      final out = run(s);
      expect(has(out, 'Food is up'), isTrue);
    });

    test('reports a real fall as good news', () {
      final s = store();
      threeQuietMonths(s, 200);
      spend(s, 50, DateTime(2026, 6, 5));
      final out = run(s);
      final hit = out.firstWhere((i) => i.title.contains('Food is down'));
      expect(hit.tone, InsightTone.good);
    });

    test('ignores a swing too small to be a finding', () {
      final s = store();
      threeQuietMonths(s, 100);
      spend(s, 110, DateTime(2026, 6, 5)); // +10%
      expect(has(run(s), 'Food is'), isFalse);
    });

    test('stays quiet for a category with no history to compare against', () {
      final s = store();
      spend(s, 500, DateTime(2026, 6, 5));
      expect(has(run(s), 'Food is'), isFalse);
    });
  });

  group('stale ledger', () {
    test('points out a gap since the last entry', () {
      final s = store();
      spend(s, 20, DateTime(2026, 6, 1)); // 14 days before "now"
      expect(has(run(s), 'Nothing logged in 14 days'), isTrue);
    });

    test('says nothing when the ledger is current', () {
      final s = store();
      spend(s, 20, DateTime(2026, 6, 14));
      expect(has(run(s), 'Nothing logged'), isFalse);
    });
  });

  group('one big purchase', () {
    test('calls out a month dominated by a single expense', () {
      final s = store();
      spend(s, 900, DateTime(2026, 6, 3), note: 'Laptop');
      spend(s, 50, DateTime(2026, 6, 4));
      spend(s, 50, DateTime(2026, 6, 5));
      final out = run(s);
      final hit = out.firstWhere((i) => i.title.contains('one purchase'));
      expect(hit.detail, contains('Laptop'));
    });

    test('stays quiet when spending is spread out', () {
      final s = store();
      for (var d = 1; d <= 6; d++) {
        spend(s, 100, DateTime(2026, 6, d));
      }
      expect(has(run(s), 'one purchase'), isFalse);
    });
  });

  group('ordering', () {
    test('the most urgent thing comes first', () {
      final s = store();
      spend(s, 1200, DateTime(2026, 6, 10));
      final out = run(s, budget: 1000);
      expect(out.first.title, contains('Over budget'));
    });
  });

  group('reminder bodies', () {
    test('always fills the queue, even with nothing to report', () {
      final bodies = buildReminderBodies(store(), 'USD', from: now, count: 7);
      expect(bodies.length, 7);
      expect(
        bodies.toSet().length,
        greaterThan(1),
        reason: 'a week of identical nudges is what gets notifications muted',
      );
    });

    test('leads with the user\'s own figures when there are some', () {
      final s = store();
      spend(s, 1200, DateTime(2026, 6, 10));
      final bodies = buildReminderBodies(
        s,
        'USD',
        from: now,
        monthlyBudget: 1000,
        count: 7,
      );
      expect(bodies.first, contains('Over budget'));
      expect(bodies.length, 7);
    });
  });
}
