import 'package:expnd/models/models.dart';
import 'package:expnd/services/money_checkup.dart';
import 'package:expnd/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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

void main() {
  test(
    'purchase preview subtracts bills and reserved goals without posting',
    () {
      final store = AppStore(_FakeBox());
      final account = Account(
        name: 'Bank',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 1000,
      );
      store.addAccount(account);
      final bill = Transaction(
        amount: 200,
        category: TransactionCategory.rent,
        type: TransactionType.expense,
        accountId: account.id,
        date: DateTime(2026, 9, 1),
        isRecurring: true,
      );
      bill.nextDueDate = DateTime(2026, 10, 20);
      store.addTransaction(bill);
      final before = store.transactions.length;
      final result = previewPurchase(
        store,
        amount: 100,
        monthlyBudget: 500,
        budgetRollover: false,
        now: DateTime(2026, 10, 9),
      );
      expect(result.availableAfterBills, 600);
      expect(result.afterPurchase, 500);
      expect(store.transactions.length, before);
    },
  );

  test('monthly review compares months and lists annual bills', () {
    final store = AppStore(_FakeBox());
    store.addTransaction(
      Transaction(
        amount: 30,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 12),
      ),
    );
    store.addTransaction(
      Transaction(
        amount: 50,
        category: TransactionCategory.other,
        type: TransactionType.expense,
        date: DateTime(2026, 10, 3),
      ),
    );
    store.addTransaction(
      Transaction(
        amount: 120,
        category: TransactionCategory.subscription,
        type: TransactionType.expense,
        date: DateTime(2026, 10, 5),
        isRecurring: true,
        recurrenceRule: RecurrenceRule.yearly,
      ),
    );
    final review = monthlyReview(store, month: DateTime(2026, 10));
    expect(review.spent, 170);
    expect(review.previousSpent, 30);
    expect(review.uncategorizedCount, 1);
    expect(review.annualBills, hasLength(1));
  });

  test('purchase preview counts accounts whatever code they carry', () {
    // One app-wide currency: a legacy account stamped with another code is
    // still the user's money and must not silently drop out of the preview.
    final store = AppStore(_FakeBox());
    store.addAccount(
      Account(
        name: 'Bank',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 400,
      ),
    );
    store.addAccount(
      Account(
        name: 'Old wallet',
        type: AccountType.cash,
        currencyCode: 'INR',
        balance: 100,
      ),
    );
    final result = previewPurchase(
      store,
      amount: 50,
      monthlyBudget: 0,
      budgetRollover: false,
      now: DateTime(2026, 10, 9),
    );
    expect(result.cash, 500);
    expect(result.afterPurchase, 450);
  });

  test('monthly review CSV is one escaped, formula-safe table', () {
    final store = AppStore(_FakeBox());
    store.addTransaction(
      Transaction(
        amount: 80,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: DateTime(2026, 10, 3),
      ),
    );
    final bill = Transaction(
      note: '=HYPERLINK("x"), yearly',
      amount: 120,
      category: TransactionCategory.subscription,
      type: TransactionType.expense,
      date: DateTime(2026, 1, 5),
      isRecurring: true,
      recurrenceRule: RecurrenceRule.yearly,
    );
    bill.nextDueDate = DateTime(2027, 1, 5);
    store.addTransaction(bill);
    final review = monthlyReview(store, month: DateTime(2026, 10));
    final csv = monthlyReviewCsv(
      review,
      month: DateTime(2026, 10),
      currencyCode: 'JPY',
      goals: [
        SavingsGoal(name: 'Trip', targetAmount: 900, allocatedAmount: 300),
      ],
    );
    final lines = csv.trim().split('\n');
    expect(lines.first, 'Section,Item,Amount,Detail');
    expect(lines, contains('Summary,Month,,2026-10'));
    expect(lines, contains('Summary,Currency,,JPY'));
    // JPY has no minor unit, so amounts carry no decimals.
    expect(lines, contains('Summary,Spent,80,'));
    expect(lines, contains('Category,Food,80,100.0% of spending'));
    expect(lines, contains('Savings goal,Trip,300,of 900 target'));
    // Quoted for the comma, neutralised so a spreadsheet won't run it.
    expect(
      lines,
      contains(
        'Annual bill,"\'=HYPERLINK(""x""), yearly",120,Next due 2027-01-05',
      ),
    );
  });
}
