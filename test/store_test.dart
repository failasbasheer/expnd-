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
      store.addTransaction(Transaction(
        amount: 200,
        category: TransactionCategory.salary,
        type: TransactionType.income,
      )..accountId = a.id);
      store.addTransaction(Transaction(
        amount: 30,
        category: TransactionCategory.food,
        type: TransactionType.expense,
      )..accountId = a.id);
      // 50 + 200 - 30
      expect(store.balanceFor(a), 220);
    });

    test('transfer moves value between accounts and preserves net worth', () {
      final store = _newStore();
      final from = _acct(opening: 500);
      final to = _acct(opening: 0);
      store.addAccount(from);
      store.addAccount(to);
      store.addTransaction(Transaction(
        amount: 120,
        category: TransactionCategory.other,
        type: TransactionType.transfer,
      )
        ..accountId = from.id
        ..toAccountId = to.id);

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
      final generated =
          store.transactions.where((t) => !t.isRecurring).toList();
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

  group('RecurrenceRule.nextDate', () {
    final base = DateTime(2026, 1, 15, 9, 30);
    test('daily', () => expect(RecurrenceRule.daily.nextDate(base), DateTime(2026, 1, 16, 9, 30)));
    test('weekly', () => expect(RecurrenceRule.weekly.nextDate(base), DateTime(2026, 1, 22, 9, 30)));
    test('biweekly', () => expect(RecurrenceRule.biweekly.nextDate(base), DateTime(2026, 1, 29, 9, 30)));
    test('monthly', () => expect(RecurrenceRule.monthly.nextDate(base), DateTime(2026, 2, 15, 9, 30)));
    test('yearly', () => expect(RecurrenceRule.yearly.nextDate(base), DateTime(2027, 1, 15, 9, 30)));
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
      final b = CategoryBudget(category: TransactionCategory.transport, limit: 80);
      final copy = CategoryBudget.fromJson(b.toJson());
      expect(copy.category, TransactionCategory.transport);
      expect(copy.limit, 80);
    });

    test('SavingsGoal preserves progress', () {
      final g = SavingsGoal(name: 'Trip', targetAmount: 1000, currentAmount: 250);
      final copy = SavingsGoal.fromJson(g.toJson());
      expect(copy.progress, 0.25);
      expect(copy.name, 'Trip');
    });

    test('CustomCategory applicable type', () {
      final c = CustomCategory(
          name: 'Coffee', emoji: '☕', typeRaw: 'Expense', colorHex: 'F97316');
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
