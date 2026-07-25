// Unit tests for the forward projection behind the Upcoming surfaces. The
// numbers here drive a "safe to spend" figure users will act on, so the
// horizon boundaries, recurrence expansion, and the deliberate exclusion of
// EMIs from projected balances all get direct coverage.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/services/upcoming.dart';
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

AppStore _newStore() => AppStore(_FakeBox());

Account _acct({double opening = 0, AccountType type = AccountType.bank}) =>
    Account(
      name: 'Test',
      type: type,
      currencyCode: 'USD',
      balance: opening,
    );

/// A recurring template due on [due]. Mirrors how add_transaction builds one.
Transaction _recurring({
  required double amount,
  required DateTime due,
  RecurrenceRule rule = RecurrenceRule.monthly,
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
    recurrenceRule: rule,
    accountId: accountId,
  );
  t.nextDueDate = due;
  return t;
}

void main() {
  group('projectUpcoming — recurring', () {
    test('non-recurring transactions are never projected', () {
      final s = _newStore();
      s.addTransaction(Transaction(
        amount: 50,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: DateTime(2026, 7, 25),
      ));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items, isEmpty);
    });

    test('a monthly bill inside the horizon yields exactly one occurrence', () {
      final s = _newStore();
      s.addTransaction(_recurring(amount: 1200, due: DateTime(2026, 7, 25)));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.length, 1);
      expect(items.first.amount, 1200);
      expect(items.first.date, DateTime(2026, 7, 25));
      expect(items.first.kind, UpcomingKind.recurring);
      expect(items.first.title, 'Rent');
      expect(items.first.subtitle, 'Monthly');
    });

    test('a weekly bill expands to every occurrence in the window', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 20,
        due: DateTime(2026, 7, 22),
        rule: RecurrenceRule.weekly,
        note: 'Gym',
      ));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      // Jul 22, 29, Aug 5, 12, 19 all fall within 30 days of Jul 21.
      expect(items.map((i) => i.date), [
        DateTime(2026, 7, 22),
        DateTime(2026, 7, 29),
        DateTime(2026, 8, 5),
        DateTime(2026, 8, 12),
        DateTime(2026, 8, 19),
      ]);
    });

    test('biweekly expands correctly', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 30,
        due: DateTime(2026, 7, 21),
        rule: RecurrenceRule.biweekly,
      ));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.map((i) => i.date), [
        DateTime(2026, 7, 21),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 18),
      ]);
    });

    test('occurrences beyond the horizon are excluded', () {
      final s = _newStore();
      s.addTransaction(_recurring(amount: 99, due: DateTime(2026, 9, 1)));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items, isEmpty);
    });

    test('a due date already in the past rolls forward into the window', () {
      final s = _newStore();
      // Stale template that generateRecurring has not caught up on yet.
      s.addTransaction(_recurring(amount: 500, due: DateTime(2026, 5, 10)));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      // Rolls May 10 → Jun 10 → Jul 10 → Aug 10, the first one in range.
      expect(items.length, 1);
      expect(items.first.date, DateTime(2026, 8, 10));
    });

    test('a yearly bill outside the window contributes nothing', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 800,
        due: DateTime(2027, 3, 1),
        rule: RecurrenceRule.yearly,
      ));
      expect(projectUpcoming(s, from: DateTime(2026, 7, 21)), isEmpty);
    });

    test('income templates are projected as inflows', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 3400,
        due: DateTime(2026, 8, 1),
        type: TransactionType.income,
        note: 'Salary',
      ));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.single.isInflow, isTrue);
      expect(items.single.signedDelta, 3400);
    });

    test('a transfer nets to zero against net worth', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 250,
        due: DateTime(2026, 7, 30),
        type: TransactionType.transfer,
        note: 'To savings',
      ));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.single.signedDelta, 0);
    });

    test('an untitled template falls back to its category name', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 10,
        due: DateTime(2026, 7, 25),
        note: '   ',
      ));
      expect(projectUpcoming(s, from: DateTime(2026, 7, 21)).single.title,
          'Rent');
    });
  });

  group('projectUpcoming — EMI', () {
    Emi emi({
      required DateTime start,
      int tenure = 12,
      double principal = 12000,
      double rate = 0,
    }) =>
        Emi(
          accountId: 'acct',
          name: 'Macbook',
          principal: principal,
          annualRate: rate,
          tenureMonths: tenure,
          startDate: start,
        );

    test('projects the next installment on the monthly anniversary', () {
      final s = _newStore();
      // Started Jan 15; by Jul 21 six installments have passed, so #7 is Aug 15.
      s.addEmi(emi(start: DateTime(2026, 1, 15)));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.length, 1);
      expect(items.single.date, DateTime(2026, 8, 15));
      expect(items.single.kind, UpcomingKind.emi);
      expect(items.single.subtitle, 'Installment 7 of 12');
      expect(items.single.amount, closeTo(1000, 0.01));
    });

    test('a completed EMI is not projected', () {
      final s = _newStore();
      s.addEmi(emi(start: DateTime(2024, 1, 15)));
      expect(projectUpcoming(s, from: DateTime(2026, 7, 21)), isEmpty);
    });

    test('installments past the final one are never emitted', () {
      final s = _newStore();
      // Tenure 7 starting Jan 15 → last installment Aug 15, nothing after.
      s.addEmi(emi(start: DateTime(2026, 1, 15), tenure: 7));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.single.subtitle, 'Installment 7 of 7');
    });

    test('a month-end start date clamps instead of rolling over', () {
      // Jan 31 + 1 month must be Feb 28, not Mar 3.
      expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonthsClamped(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(addMonthsClamped(DateTime(2026, 12, 31), 2), DateTime(2027, 2, 28));
    });

    test('a Jan 31 EMI lands on the clamped February date', () {
      final s = _newStore();
      s.addEmi(emi(start: DateTime(2026, 1, 31), tenure: 12));
      final items = projectUpcoming(s, from: DateTime(2026, 2, 1));
      expect(items.single.date, DateTime(2026, 2, 28));
    });
  });

  group('projectUpcoming — ordering', () {
    test('items from both sources interleave in date order', () {
      final s = _newStore();
      s.addTransaction(_recurring(amount: 1200, due: DateTime(2026, 8, 1)));
      s.addTransaction(_recurring(
        amount: 16,
        due: DateTime(2026, 7, 24),
        note: 'Netflix',
      ));
      s.addEmi(Emi(
        accountId: 'acct',
        name: 'Macbook',
        principal: 12000,
        annualRate: 0,
        tenureMonths: 12,
        startDate: DateTime(2026, 1, 28),
      ));
      final items = projectUpcoming(s, from: DateTime(2026, 7, 21));
      expect(items.map((i) => i.title), ['Netflix', 'Macbook', 'Rent']);
    });
  });

  group('summarizeUpcoming', () {
    // NOTE: these leave the templates unattached to an account on purpose. A
    // recurring template is itself a posted transaction, so attaching one would
    // fold its own past occurrence into balanceFor and muddy the arithmetic
    // under test. Projection reads `nextDueDate`, never the account link.
    test('committed outflows include EMIs but projections do not', () {
      final s = _newStore();
      final a = _acct(opening: 5000);
      s.addAccount(a);
      s.addTransaction(_recurring(
        amount: 1200,
        due: DateTime(2026, 7, 25),
      ));
      s.addEmi(Emi(
        accountId: a.id,
        name: 'Macbook',
        principal: 12000,
        annualRate: 0,
        tenureMonths: 12,
        startDate: DateTime(2026, 1, 28),
      ));

      final from = DateTime(2026, 7, 21);
      final items = projectUpcoming(s, from: from);
      final sum = summarizeUpcoming(s, items, from: from);

      // Rent 1200 + EMI 1000 both count as committed.
      expect(sum.committedOutflows, closeTo(2200, 0.01));
      expect(sum.emiCommitted, closeTo(1000, 0.01));
      // But only the rent moves the projected balance.
      expect(sum.liquidBalance, 5000);
      expect(sum.projectedMonthEnd, closeTo(3800, 0.01));
      expect(sum.safeToSpend, closeTo(3800, 0.01));
    });

    test('income raises the projection but never safe-to-spend', () {
      final s = _newStore();
      final a = _acct(opening: 1000);
      s.addAccount(a);
      s.addTransaction(_recurring(amount: 400, due: DateTime(2026, 7, 25)));
      s.addTransaction(_recurring(
        amount: 3000,
        due: DateTime(2026, 7, 28),
        type: TransactionType.income,
        note: 'Salary',
      ));

      final from = DateTime(2026, 7, 21);
      final sum = summarizeUpcoming(s, projectUpcoming(s, from: from), from: from);

      expect(sum.expectedInflows, 3000);
      expect(sum.projectedMonthEnd, closeTo(3600, 0.01));
      // Conservative: unreceived income is ignored.
      expect(sum.safeToSpend, closeTo(600, 0.01));
    });

    test('only movements before month end shift the month-end figures', () {
      final s = _newStore();
      final a = _acct(opening: 1000);
      s.addAccount(a);
      // Due in August — inside the 30-day list, outside the July projection.
      s.addTransaction(_recurring(amount: 400, due: DateTime(2026, 8, 10)));

      final from = DateTime(2026, 7, 21);
      final items = projectUpcoming(s, from: from);
      final sum = summarizeUpcoming(s, items, from: from);

      expect(items.length, 1);
      expect(sum.committedOutflows, 400);
      expect(sum.projectedMonthEnd, 1000);
      expect(sum.safeToSpend, 1000);
    });

    test('credit and investment balances are excluded from liquid cash', () {
      final s = _newStore();
      s.addAccount(_acct(opening: 800));
      s.addAccount(_acct(opening: 1500, type: AccountType.cash));
      s.addAccount(_acct(opening: 4000, type: AccountType.savings));
      // Neither of these is money you can pay a bill with today.
      s.addAccount(_acct(opening: 2500, type: AccountType.credit));
      s.addAccount(_acct(opening: 9000, type: AccountType.investment));
      final from = DateTime(2026, 7, 21);
      final sum = summarizeUpcoming(s, projectUpcoming(s, from: from), from: from);
      expect(sum.liquidBalance, 6300);
    });

    test('safe to spend goes negative when bills exceed cash', () {
      final s = _newStore();
      s.addAccount(_acct(opening: 300));
      s.addTransaction(_recurring(amount: 1200, due: DateTime(2026, 7, 25)));
      final from = DateTime(2026, 7, 21);
      final sum = summarizeUpcoming(s, projectUpcoming(s, from: from), from: from);
      expect(sum.safeToSpend, closeTo(-900, 0.01));
    });

    test('an empty store summarizes to zeroes', () {
      final s = _newStore();
      final from = DateTime(2026, 7, 21);
      final sum = summarizeUpcoming(s, projectUpcoming(s, from: from), from: from);
      expect(sum.isEmpty, isTrue);
      expect(sum.projectedMonthEnd, 0);
    });
  });

  group('groupUpcomingByDay', () {
    test('collapses same-day items into one bucket, in order', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 16,
        due: DateTime(2026, 8, 1, 9),
        note: 'Netflix',
      ));
      s.addTransaction(_recurring(
        amount: 3400,
        due: DateTime(2026, 8, 1, 17),
        type: TransactionType.income,
        note: 'Salary',
      ));
      s.addTransaction(_recurring(
        amount: 1200,
        due: DateTime(2026, 7, 25),
      ));

      final groups =
          groupUpcomingByDay(projectUpcoming(s, from: DateTime(2026, 7, 21)));
      expect(groups.length, 2);
      expect(groups[0].day, DateTime(2026, 7, 25));
      expect(groups[0].items.length, 1);
      expect(groups[1].day, DateTime(2026, 8, 1));
      expect(groups[1].items.length, 2);
    });

    test('empty input yields no groups', () {
      expect(groupUpcomingByDay(const []), isEmpty);
    });
  });

  group('generateRecurring notice', () {
    test('returns what it posted and hands it over exactly once', () {
      final s = _newStore();
      final a = _acct(opening: 0);
      s.addAccount(a);
      s.addTransaction(_recurring(
        amount: 100,
        due: DateTime.now().subtract(const Duration(days: 1)),
        accountId: a.id,
      ));

      final posted = s.generateRecurring();
      expect(posted, hasLength(1));
      expect(posted.single.amount, 100);
      expect(posted.single.isRecurring, isFalse);
      expect(posted.single.accountId, a.id);

      expect(s.takeRecurringNotice(), hasLength(1));
      // Consumed — a rebuild must not show the toast again.
      expect(s.takeRecurringNotice(), isEmpty);
    });

    test('nothing due means nothing posted and no notice', () {
      final s = _newStore();
      s.addTransaction(_recurring(
        amount: 100,
        due: DateTime.now().add(const Duration(days: 5)),
      ));
      expect(s.generateRecurring(), isEmpty);
      expect(s.takeRecurringNotice(), isEmpty);
    });
  });

  group('projectUpcoming — debt repayment plans', () {
    Debt owed({double? plan, bool theyOweMe = true, double amount = 600}) => Debt(
          person: 'Rahul',
          amount: amount,
          theyOweMe: theyOweMe,
          date: DateTime(2026, 1, 15),
          monthlyRepayment: plan,
        );

    test('a debt with no plan is never projected', () {
      final s = _newStore();
      s.addDebt(owed());
      expect(projectUpcoming(s, from: DateTime(2026, 6, 1)), isEmpty);
    });

    test('a plan projects a monthly repayment', () {
      final s = _newStore();
      s.addDebt(owed(plan: 200));
      final items = projectUpcoming(s, from: DateTime(2026, 6, 1));
      expect(items, isNotEmpty);
      expect(items.first.kind, UpcomingKind.debt);
      expect(items.first.amount, closeTo(200, 0.01));
    });

    test('money they owe me comes in; money I owe goes out', () {
      final s = _newStore();
      s.addDebt(owed(plan: 200));
      expect(projectUpcoming(s, from: DateTime(2026, 6, 1)).first.isInflow,
          isTrue);

      final t = _newStore();
      t.addDebt(owed(plan: 200, theyOweMe: false));
      expect(projectUpcoming(t, from: DateTime(2026, 6, 1)).first.isInflow,
          isFalse);
    });

    test('the final instalment is only what is left, not a full one', () {
      final s = _newStore();
      // 500 owed, 200 a month — the third payment should be 100.
      s.addDebt(owed(plan: 200, amount: 500));
      final all = projectUpcoming(s,
          from: DateTime(2026, 1, 16), horizonDays: 365);
      expect(all.length, 3);
      expect(all.last.amount, closeTo(100, 0.01));
    });

    test('a settled debt stops projecting', () {
      final s = _newStore();
      final d = owed(plan: 200);
      d.settledDate = DateTime(2026, 5, 1);
      s.addDebt(d);
      expect(projectUpcoming(s, from: DateTime(2026, 6, 1)), isEmpty);
    });

    test('repayments already made shrink what is still scheduled', () {
      final s = _newStore();
      final d = owed(plan: 200, amount: 600);
      s.addDebt(d);
      s.repayDebt(d, 400, null);
      final all = projectUpcoming(s,
          from: DateTime(2026, 1, 16), horizonDays: 365);
      // Only 200 left, so a single instalment remains.
      expect(all.length, 1);
      expect(all.single.amount, closeTo(200, 0.01));
    });
  });
}
