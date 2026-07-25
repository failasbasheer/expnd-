// Event alerts fire off something happening — a bill landing, a budget crossed,
// a goal funded. These tests pin the two things that make them trustworthy:
// they warn about the right movements (money going out, not in), and a
// "this is true now" alert announces a crossing exactly once, never twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/services/alerts.dart';
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
  final now = DateTime(2026, 6, 15);
  AppStore store() => AppStore(_FakeBox());

  Transaction recurring({
    required double amount,
    required DateTime due,
    TransactionType type = TransactionType.expense,
    String note = 'Rent',
    String? accountId,
  }) {
    final t = Transaction(
      amount: amount,
      category: type == TransactionType.income
          ? TransactionCategory.salary
          : TransactionCategory.rent,
      type: type,
      date: due,
      note: note,
      isRecurring: true,
      recurrenceRule: RecurrenceRule.monthly,
      accountId: accountId,
    );
    t.nextDueDate = due;
    return t;
  }

  group('dueSoonAlerts', () {
    test('warns the night before an outflow, tagged to its account', () {
      final s = store();
      final acc = Account(
          name: 'Checking',
          type: AccountType.bank,
          currencyCode: 'USD',
          balance: 0);
      s.addAccount(acc);
      s.addTransaction(recurring(
          amount: 1200,
          due: now.add(const Duration(days: 3)),
          accountId: acc.id));

      final alerts = dueSoonAlerts(s, 'USD', from: now, hour: 21, minute: 0);

      expect(alerts, hasLength(1));
      final a = alerts.single;
      // Fires the evening before, at the reminder time.
      expect(a.fireAt, DateTime(2026, 6, 17, 21, 0));
      expect(a.title, 'Rent due tomorrow');
      expect(a.body, contains('Checking'));
    });

    test('ignores inflows — "money is coming" needs no action', () {
      final s = store();
      s.addTransaction(recurring(
        amount: 3000,
        due: now.add(const Duration(days: 2)),
        type: TransactionType.income,
        note: 'Salary',
      ));
      expect(dueSoonAlerts(s, 'USD', from: now), isEmpty);
    });

    test('drops a bill whose warning window has already closed', () {
      final s = store();
      // Due today: the "night before" is last night, already gone. A short
      // horizon keeps next month's installment out of it so this occurrence
      // stands alone.
      s.addTransaction(recurring(amount: 50, due: now));
      expect(dueSoonAlerts(s, 'USD', from: now, horizonDays: 5), isEmpty);
    });
  });

  group('over budget', () {
    void spend(AppStore s, double amount) => s.addTransaction(Transaction(
          amount: amount,
          category: TransactionCategory.food,
          type: TransactionType.expense,
          date: now,
        ));

    test('newly over when the month passes the budget and unannounced', () {
      final s = store();
      spend(s, 500);
      expect(
          newlyOverBudget(s,
              monthlyBudget: 300, lastAlertedMonth: 0, from: now),
          isTrue);
      final alert = overBudgetAlert(s, 'USD',
          monthlyBudget: 300, lastAlertedMonth: 0, from: now);
      expect(alert, isNotNull);
      expect(alert!.title, 'Over budget');
    });

    test('stays quiet once this month has already been flagged', () {
      final s = store();
      spend(s, 500);
      expect(
          newlyOverBudget(s,
              monthlyBudget: 300,
              lastAlertedMonth: yyyymm(now),
              from: now),
          isFalse);
      expect(
          overBudgetAlert(s, 'USD',
              monthlyBudget: 300, lastAlertedMonth: yyyymm(now), from: now),
          isNull);
    });

    test('no budget set means nothing to be over', () {
      final s = store();
      spend(s, 9999);
      expect(
          newlyOverBudget(s,
              monthlyBudget: 0, lastAlertedMonth: 0, from: now),
          isFalse);
    });
  });

  group('goal reached', () {
    SavingsGoal fund(AppStore s, double target, double allocated,
        {String name = 'New phone'}) {
      final g = SavingsGoal(
          name: name, targetAmount: target, allocatedAmount: allocated);
      s.addGoal(g);
      return g;
    }

    test('a fully funded, uncelebrated goal is returned once', () {
      final s = store();
      final g = fund(s, 1000, 1000);
      expect(newlyReachedGoals(s, const []).map((e) => e.id), [g.id]);
      // Already celebrated → silent.
      expect(newlyReachedGoals(s, [g.id]), isEmpty);
    });

    test('a goal short of its target is not celebrated', () {
      final s = store();
      fund(s, 1000, 400);
      expect(newlyReachedGoals(s, const []), isEmpty);
    });

    test('the copy names the goal', () {
      final g = SavingsGoal(name: 'Emergency fund', targetAmount: 500);
      final alert = goalReachedAlert(g, 'USD');
      expect(alert.title, contains('Goal reached'));
      expect(alert.body, contains('Emergency fund'));
    });
  });
}
