// Unit tests for the money-critical logic: account balances (the
// transactions-authoritative model), transfers, recurring generation, and
// category budgets. These are the highest-risk paths in a finance app, so
// they get direct coverage independent of any UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/theme/currencies.dart';

/// A throwaway in-memory stand-in for a Hive [Box] so [AppStore] can be built
/// without touching disk. Only get/put are exercised by the store; everything
/// else routes through noSuchMethod.
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

Account _acct({double opening = 0, String currency = 'USD'}) => Account(
  name: 'Test',
  type: AccountType.bank,
  currencyCode: currency,
  balance: opening,
);

void main() {
  group('balance model', () {
    test('opening balance with no transactions', () {
      final store = _newStore();
      final a = _acct(opening: 100);
      store.addAccount(a);
      expect(store.balanceFor(a), 100);
    });

    test('income adds, expense subtracts', () {
      final store = _newStore();
      final a = _acct(opening: 50);
      store.addAccount(a);
      store.addTransaction(
        Transaction(
          amount: 200,
          category: TransactionCategory.salary,
          type: TransactionType.income,
        )..accountId = a.id,
      );
      store.addTransaction(
        Transaction(
          amount: 30,
          category: TransactionCategory.food,
          type: TransactionType.expense,
        )..accountId = a.id,
      );
      // 50 + 200 - 30
      expect(store.balanceFor(a), 220);
    });

    test('transfer moves value between accounts and preserves net worth', () {
      final store = _newStore();
      final from = _acct(opening: 500);
      final to = _acct(opening: 0);
      store.addAccount(from);
      store.addAccount(to);
      store.addTransaction(
        Transaction(
            amount: 120,
            category: TransactionCategory.other,
            type: TransactionType.transfer,
          )
          ..accountId = from.id
          ..toAccountId = to.id,
      );

      expect(store.balanceFor(from), 380);
      expect(store.balanceFor(to), 120);
      // Total net worth unchanged by an internal transfer.
      expect(store.balanceFor(from) + store.balanceFor(to), 500);
    });

    test('deleting an account nullifies its transaction references', () {
      final store = _newStore();
      final a = _acct(opening: 0);
      store.addAccount(a);
      final t = Transaction(
        amount: 10,
        category: TransactionCategory.food,
        type: TransactionType.expense,
      )..accountId = a.id;
      store.addTransaction(t);

      store.deleteAccount(a);
      expect(store.accounts, isEmpty);
      // The transaction survives but is detached.
      expect(store.transactions.single.accountId, isNull);
    });
  });

  group('recurring generation', () {
    test('posts a due monthly template and advances the next due date', () {
      final store = _newStore();
      final a = _acct(opening: 0);
      store.addAccount(a);

      final start = DateTime.now().subtract(const Duration(days: 40));
      final template = Transaction(
        amount: 15,
        category: TransactionCategory.subscription,
        type: TransactionType.expense,
        date: start,
        isRecurring: true,
        recurrenceRule: RecurrenceRule.monthly,
      )..accountId = a.id;
      store.addTransaction(template);

      final before = store.transactions.length;
      store.generateRecurring();
      final after = store.transactions.length;

      // At least one occurrence became due in the last 40 days.
      expect(after, greaterThan(before));
      // Next due date is now in the future.
      expect(template.nextDueDate!.isAfter(DateTime.now()), isTrue);
      // Generated occurrences are attached to the same account.
      final generated = store.transactions
          .where((t) => !t.isRecurring)
          .toList();
      expect(generated, isNotEmpty);
      expect(generated.every((t) => t.accountId == a.id), isTrue);
    });

    test('does not post a template whose next due date is in the future', () {
      final store = _newStore();
      final template = Transaction(
        amount: 15,
        category: TransactionCategory.subscription,
        type: TransactionType.expense,
        date: DateTime.now(),
        isRecurring: true,
        recurrenceRule: RecurrenceRule.monthly,
      );
      store.addTransaction(template);
      final before = store.transactions.length;
      store.generateRecurring();
      expect(store.transactions.length, before);
    });
  });

  group('category budgets', () {
    test('set, update, and clear a budget', () {
      final store = _newStore();
      store.setBudget(TransactionCategory.food, 300);
      expect(store.budgets.single.limit, 300);

      store.setBudget(TransactionCategory.food, 450);
      expect(store.budgets.single.limit, 450);

      // A non-positive limit removes it.
      store.setBudget(TransactionCategory.food, 0);
      expect(store.budgets, isEmpty);
    });
  });

  // Rollover is what makes a budget behave like an envelope instead of a
  // number that forgets everything on the 1st.
  group('budget rollover', () {
    final thisMonth = DateTime(2026, 7, 15);
    final lastMonth = DateTime(2026, 6, 15);

    AppStore storeWithSpend(DateTime when, double amount) {
      final store = _newStore();
      store.addTransaction(
        Transaction(
          amount: amount,
          category: TransactionCategory.food,
          type: TransactionType.expense,
          date: when,
        ),
      );
      return store;
    }

    test('underspending last month raises this month', () {
      final store = storeWithSpend(lastMonth, 300); // 200 unspent of 500
      expect(store.rolledOverLimit(500, thisMonth), 700);
    });

    test('overspending last month eats into this month', () {
      final store = storeWithSpend(lastMonth, 650); // 150 over
      expect(store.rolledOverLimit(500, thisMonth), 350);
    });

    test('a wildly overspent month floors at zero, never negative', () {
      final store = storeWithSpend(lastMonth, 5000);
      // Progress divides by the limit, so a negative would invert the gauge.
      expect(store.rolledOverLimit(500, thisMonth), 0);
    });

    test('rollover only looks at the month immediately before', () {
      final store = storeWithSpend(DateTime(2026, 5, 15), 0.01);
      // May is two months back; June had no spend at all.
      expect(store.rolledOverLimit(500, thisMonth), 1000);
    });

    test('per-category rollover ignores other categories', () {
      final store = storeWithSpend(lastMonth, 400); // food
      store.addTransaction(
        Transaction(
          amount: 900,
          category: TransactionCategory.shopping,
          type: TransactionType.expense,
          date: lastMonth,
        ),
      );
      expect(
        store.rolledOverLimit(
          500,
          thisMonth,
          category: TransactionCategory.food,
        ),
        600,
      ); // 500 + (500 - 400)
    });

    test('the overage warning respects the rolled-over limit', () {
      final store = storeWithSpend(lastMonth, 100); // 400 unspent of 500
      store.setBudget(TransactionCategory.food, 500);
      final t = Transaction(
        amount: 600,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: thisMonth,
      );
      store.addTransaction(t);

      // Flat: 600 spent against 500 is over.
      expect(store.categoryBudgetOverage(t), isNotNull);
      // With rollover the limit is 900, so it isn't.
      expect(store.categoryBudgetOverage(t, rollover: true), isNull);
    });
  });

  // Manual entry is the whole product, so repeat payees must fill themselves in.
  group('payee suggestions', () {
    AppStore storeWithPayees() {
      final store = _newStore();
      void log(String note, TransactionCategory cat, DateTime date) {
        store.addTransaction(
          Transaction(
            note: note,
            amount: 10,
            category: cat,
            type: TransactionType.expense,
            date: date,
          ),
        );
      }

      log('Blue Bottle', TransactionCategory.food, DateTime(2026, 5, 1));
      log('Blue Bottle', TransactionCategory.groceries, DateTime(2026, 7, 1));
      log(
        'Bluesmith Garage',
        TransactionCategory.transport,
        DateTime(2026, 6, 1),
      );
      log('Uniqlo', TransactionCategory.shopping, DateTime(2026, 6, 2));
      return store;
    }

    test('matches on a partial payee name', () {
      final out = storeWithPayees().payeeSuggestions('blu');
      expect(
        out.map((t) => t.note),
        containsAll(['Blue Bottle', 'Bluesmith Garage']),
      );
    });

    test('offers the most recent version of a repeated payee', () {
      final out = storeWithPayees().payeeSuggestions('blue bot');
      expect(out.length, 1); // deduped
      // The newer entry wins, so a recategorised payee stays recategorised.
      expect(out.single.category, TransactionCategory.groceries);
    });

    test('an empty query suggests nothing', () {
      expect(storeWithPayees().payeeSuggestions('  '), isEmpty);
    });

    test('an exact match suggests nothing — there is nothing left to fill', () {
      expect(storeWithPayees().payeeSuggestions('Uniqlo'), isEmpty);
    });

    test('transfers are not payees', () {
      final store = _newStore();
      store.addTransaction(
        Transaction(
          note: 'To Emergency Fund',
          amount: 500,
          category: TransactionCategory.other,
          type: TransactionType.transfer,
        ),
      );
      expect(store.payeeSuggestions('emerg'), isEmpty);
    });
  });

  // A goal moves no money: it ring-fences part of a balance that already
  // exists in an account. EXPND has no bank feed, so any transaction it
  // invented would put its balances permanently out of step with the real
  // bank — these tests pin that goals never write one.
  group('savings goals', () {
    (AppStore, Account, Account, SavingsGoal) goalFixture() {
      final store = _newStore();
      final checking = _acct(opening: 1000);
      final savings = Account(
        name: 'Savings',
        type: AccountType.savings,
        currencyCode: 'USD',
        balance: 500,
      );
      store.addAccount(checking);
      store.addAccount(savings);
      final g = SavingsGoal(
        name: 'Trip',
        targetAmount: 1000,
        allocatedAmount: 100,
        accountId: savings.id,
      );
      store.addGoal(g);
      return (store, checking, savings, g);
    }

    test('setting money aside writes no transaction and moves no balance', () {
      final (store, checking, savings, g) = goalFixture();
      store.allocateToGoal(g, 200);

      expect(store.transactions, isEmpty); // nothing invented
      expect(store.balanceFor(savings), 500); // still what the bank shows
      expect(store.balanceFor(checking), 1000);
      expect(g.allocatedAmount, 300);
      expect(store.progressForGoal(g), 0.3);
    });

    test('a goal cannot claim money the account does not hold', () {
      final (store, _, savings, g) = goalFixture();
      // savings holds 500, of which 100 is already claimed.
      final applied = store.allocateToGoal(g, 9999);
      expect(applied, 400);
      expect(g.allocatedAmount, 500);
      expect(store.unallocatedIn(savings), 0);
    });

    test('claims and the remainder always sum to the real balance', () {
      final (store, _, savings, g) = goalFixture();
      final second = SavingsGoal(
        name: 'Camera',
        targetAmount: 800,
        allocatedAmount: 150,
        accountId: savings.id,
      );
      store.addGoal(second);

      expect(
        store.claimedIn(savings) + store.unallocatedIn(savings),
        store.balanceFor(savings),
      );
    });

    test('unclaimed reflects what no goal has spoken for', () {
      final (store, _, savings, g) = goalFixture();
      store.allocateToGoal(g, 150);
      expect(store.unallocatedIn(savings), 250); // 500 - 250
    });

    test('spending set-aside money shows up as over-allocation', () {
      final (store, _, savings, g) = goalFixture();
      store.allocateToGoal(g, 400); // all 500 claimed
      // A real withdrawal the user actually made, recorded normally.
      store.addTransaction(
        Transaction(
          amount: 200,
          category: TransactionCategory.shopping,
          type: TransactionType.expense,
        )..accountId = savings.id,
      );

      expect(store.balanceFor(savings), 300);
      expect(store.unallocatedIn(savings), -200);
      expect(store.overAllocatedAccounts, contains(savings));
    });

    test('releasing hands the claim back without touching the balance', () {
      final (store, _, savings, g) = goalFixture();
      store.allocateToGoal(g, 300);
      store.releaseFromGoal(g);

      expect(g.allocatedAmount, 0);
      expect(store.unallocatedIn(savings), 500);
      expect(store.balanceFor(savings), 500); // untouched throughout
      expect(store.transactions, isEmpty);
    });

    test('an unlinked goal can set nothing aside', () {
      final store = _newStore();
      final checking = _acct(opening: 1000);
      store.addAccount(checking);
      final g = SavingsGoal(name: 'Someday', targetAmount: 500);
      store.addGoal(g);

      expect(store.allocateToGoal(g, 100), 0);
      expect(g.allocatedAmount, 0);
      expect(store.transactions, isEmpty);
      expect(store.balanceFor(checking), 1000);
    });

    test('deleting a goal releases its claim and keeps the money', () {
      final (store, _, savings, g) = goalFixture();
      store.allocateToGoal(g, 200);
      store.deleteGoal(g);

      expect(store.goals, isEmpty);
      expect(store.balanceFor(savings), 500); // money stayed put
      expect(store.unallocatedIn(savings), 500); // and is free again
    });
  });

  group('tags', () {
    AppStore taggedStore() {
      final store = _newStore();
      void log(
        String note,
        double amount,
        List<String> tags, {
        TransactionType type = TransactionType.expense,
      }) {
        store.addTransaction(
          Transaction(
            note: note,
            amount: amount,
            category: TransactionCategory.food,
            type: type,
            tags: tags,
          ),
        );
      }

      log('Flights', 800, ['Japan', 'travel']);
      log('Hotel', 400, ['Japan']);
      log('Refund', 100, ['Japan'], type: TransactionType.income);
      log('Lunch', 20, ['work']);
      return store;
    }

    test('lists tags most-used first', () {
      expect(taggedStore().allTags, ['Japan', 'travel', 'work']);
    });

    test('what a tag cost nets refunds against it', () {
      // 800 + 400 spent, 100 came back.
      expect(taggedStore().spentOnTag('Japan'), 1100);
    });

    test('tag lookup is case-insensitive', () {
      expect(taggedStore().transactionsWithTag('japan').length, 3);
    });

    test('renaming merges into an existing tag without duplicating it', () {
      final store = taggedStore();
      store.renameTag('travel', 'Japan');
      final flights = store.transactions.firstWhere((t) => t.note == 'Flights');
      expect(flights.tags, ['Japan']);
      expect(store.allTags, ['Japan', 'work']);
    });

    test('deleting a tag leaves the transactions alone', () {
      final store = taggedStore();
      final before = store.transactions.length;
      store.deleteTag('Japan');
      expect(store.transactions.length, before);
      expect(store.allTags, ['travel', 'work']);
    });
  });

  // A split is several ordinary transactions sharing a group id — deliberately
  // not a special row type, so budgets and charts count them without knowing.
  group('splits', () {
    test('each line counts as a normal transaction', () {
      final store = _newStore();
      final a = _acct(opening: 500);
      store.addAccount(a);
      store.addSplit(
        lines: [
          (amount: 48, category: TransactionCategory.groceries, note: 'food'),
          (amount: 16, category: TransactionCategory.shopping, note: 'soap'),
        ],
        type: TransactionType.expense,
        date: DateTime(2026, 7, 4),
        accountId: a.id,
      );

      expect(store.transactions.length, 2);
      expect(store.balanceFor(a), 500 - 64);
      // Each line lands in its own category budget, which is the point.
      expect(
        store.spentInMonth(
          DateTime(2026, 7),
          category: TransactionCategory.groceries,
        ),
        48,
      );
      expect(
        store.spentInMonth(
          DateTime(2026, 7),
          category: TransactionCategory.shopping,
        ),
        16,
      );
    });

    test('the rows are linked and zero-amount lines are dropped', () {
      final store = _newStore();
      final made = store.addSplit(
        lines: [
          (amount: 10, category: TransactionCategory.food, note: ''),
          (amount: 0, category: TransactionCategory.other, note: 'empty'),
        ],
        type: TransactionType.expense,
        date: DateTime(2026, 7, 4),
      );
      expect(made.length, 1);
      expect(store.splitRows(made.first.splitGroupId!).length, 1);
    });

    test('deleting a split takes the whole receipt', () {
      final store = _newStore();
      final made = store.addSplit(
        lines: [
          (amount: 48, category: TransactionCategory.groceries, note: ''),
          (amount: 16, category: TransactionCategory.shopping, note: ''),
        ],
        type: TransactionType.expense,
        date: DateTime(2026, 7, 4),
      );
      store.deleteSplit(made.first.splitGroupId!);
      expect(store.transactions, isEmpty);
    });
  });

  // Lending is a real movement, so the cash leaving an account is an ordinary
  // transaction. The Debt only tracks who owes what.
  group('debts', () {
    (AppStore, Account, Debt) lentFixture() {
      final store = _newStore();
      final a = _acct(opening: 1000);
      store.addAccount(a);
      final d = Debt(
        person: 'Rahul',
        amount: 500,
        theyOweMe: true,
        accountId: a.id,
      );
      store.addDebt(d);
      return (store, a, d);
    }

    test('outstanding starts at the full amount', () {
      final (store, _, d) = lentFixture();
      expect(store.outstandingOn(d), 500);
      expect(store.owedToMe, 500);
      expect(store.owedByMe, 0);
    });

    test('a repayment moves real money and lowers what is outstanding', () {
      final (store, a, d) = lentFixture();
      store.repayDebt(d, 200, a.id);

      expect(store.outstandingOn(d), 300);
      expect(store.balanceFor(a), 1200); // the money actually came back
      expect(store.transactions.single.type, TransactionType.income);
    });

    test('borrowing repays outward', () {
      final store = _newStore();
      final a = _acct(opening: 1000);
      store.addAccount(a);
      final d = Debt(person: 'Amy', amount: 300, theyOweMe: false);
      store.addDebt(d);
      store.repayDebt(d, 100, a.id);

      expect(store.balanceFor(a), 900); // money went out
      expect(store.owedByMe, 200);
      expect(store.owedToMe, 0);
    });

    test('repaying in full settles it automatically', () {
      final (store, a, d) = lentFixture();
      store.repayDebt(d, 500, a.id);
      expect(d.isSettled, isTrue);
      expect(store.outstandingOn(d), 0);
      expect(store.owedToMe, 0);
    });

    test('deleting a repayment reconciles the debt', () {
      final (store, a, d) = lentFixture();
      final t = store.repayDebt(d, 200, a.id);
      expect(store.outstandingOn(d), 300);
      store.deleteTransaction(t);
      expect(store.outstandingOn(d), 500); // derived, so it comes back
    });

    test('deleting a debt keeps the money that really moved', () {
      final (store, a, d) = lentFixture();
      store.repayDebt(d, 200, a.id);
      store.deleteDebt(d);

      expect(store.debts, isEmpty);
      expect(store.balanceFor(a), 1200); // repayment stands
      expect(store.transactions.single.debtId, isNull);
    });

    test('settling by hand closes it even if it was short', () {
      final (store, a, d) = lentFixture();
      store.repayDebt(d, 490, a.id); // the last tenner is forgiven
      d.settledDate = DateTime.now();
      store.updateDebt();
      expect(store.outstandingOn(d), 0);
      expect(store.owedToMe, 0);
    });
  });

  group('RecurrenceRule.nextDate', () {
    final base = DateTime(2026, 1, 15, 9, 30);
    test(
      'daily',
      () => expect(
        RecurrenceRule.daily.nextDate(base),
        DateTime(2026, 1, 16, 9, 30),
      ),
    );
    test(
      'weekly',
      () => expect(
        RecurrenceRule.weekly.nextDate(base),
        DateTime(2026, 1, 22, 9, 30),
      ),
    );
    test(
      'biweekly',
      () => expect(
        RecurrenceRule.biweekly.nextDate(base),
        DateTime(2026, 1, 29, 9, 30),
      ),
    );
    test(
      'monthly',
      () => expect(
        RecurrenceRule.monthly.nextDate(base),
        DateTime(2026, 2, 15, 9, 30),
      ),
    );
    test(
      'yearly',
      () => expect(
        RecurrenceRule.yearly.nextDate(base),
        DateTime(2027, 1, 15, 9, 30),
      ),
    );
  });

  group('model JSON round-trips', () {
    test('Account', () {
      final a = _acct(opening: 42.5);
      final copy = Account.fromJson(a.toJson());
      expect(copy.id, a.id);
      expect(copy.balance, 42.5);
      expect(copy.type, a.type);
      expect(copy.currencyCode, 'USD');
    });

    test('Transaction with recurrence', () {
      final t = Transaction(
        note: 'Rent',
        amount: 1200,
        category: TransactionCategory.rent,
        type: TransactionType.expense,
        isRecurring: true,
        recurrenceRule: RecurrenceRule.monthly,
      );
      final copy = Transaction.fromJson(t.toJson());
      expect(copy.amount, 1200);
      expect(copy.recurrenceRule, RecurrenceRule.monthly);
      expect(copy.isRecurring, isTrue);
      expect(copy.nextDueDate, isNotNull);
    });

    test('CategoryBudget', () {
      final b = CategoryBudget(
        category: TransactionCategory.transport,
        limit: 80,
      );
      final copy = CategoryBudget.fromJson(b.toJson());
      expect(copy.category, TransactionCategory.transport);
      expect(copy.limit, 80);
    });

    test('SavingsGoal keeps its allocation and holding account', () {
      final g = SavingsGoal(
        name: 'Trip',
        targetAmount: 1000,
        allocatedAmount: 250,
        accountId: 'acct-1',
      );
      final copy = SavingsGoal.fromJson(g.toJson());
      expect(copy.allocatedAmount, 250);
      expect(copy.accountId, 'acct-1');
      expect(copy.name, 'Trip');
    });

    // 1.0.0 shipped goals with a hand-maintained 'currentAmount', and a build
    // in between called it 'openingAmount'. Neither must open to a goal reset
    // to zero.
    test('SavingsGoal migrates both legacy amount fields', () {
      Map<String, Object> stored(String key, double value) => {
        'id': 'g1',
        'name': 'Trip',
        'targetAmount': 1000.0,
        key: value,
        'iconName': 'star.fill',
        'colorHex': 'F7C948',
        'createdDate': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      };

      expect(
        SavingsGoal.fromJson(stored('currentAmount', 400)).allocatedAmount,
        400,
      );
      expect(
        SavingsGoal.fromJson(stored('openingAmount', 250)).allocatedAmount,
        250,
      );
      expect(
        SavingsGoal.fromJson(stored('currentAmount', 400)).accountId,
        isNull,
      );
    });

    test('CustomCategory applicable type', () {
      final c = CustomCategory(
        name: 'Coffee',
        emoji: '☕',
        typeRaw: 'Expense',
        colorHex: 'F97316',
      );
      final copy = CustomCategory.fromJson(c.toJson());
      expect(copy.applicableType, TransactionType.expense);
    });
  });

  // The app uses one currency everywhere (chosen at setup). formatCurrency must
  // still honour each currency's own minor-unit convention.
  group('currency formatting', () {
    test('formatCurrency uses the currency\'s own decimal places', () {
      expect(formatCurrency(1000, 'JPY'), '¥1,000');
      expect(formatCurrency(1000, 'KRW'), '₩1,000');
      expect(formatCurrency(1.5, 'KWD'), 'KWD1.500');
      expect(formatCurrency(1.5, 'USD'), '\$1.50');
    });
  });
}
