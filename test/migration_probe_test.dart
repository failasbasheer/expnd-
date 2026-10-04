// Probe: can a store written by the SHIPPED 1.0.0 build be opened by this one?
//
// The payload below is hand-built to match 1.0.0's toJson output exactly — the
// keys it wrote, and only those keys. Nothing newer appears in it, so anything
// this build needs and 1.0.0 never stored has to survive being absent.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:expnd/models/models.dart';
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

const _checkingId = 'acct-checking-1';
const _cardId = 'acct-card-1';

/// Exactly what 1.0.0 would have left in the 'onyx' box.
_FakeBox _shipped_1_0_0() {
  final box = _FakeBox();

  box._m['accounts'] = jsonEncode([
    {
      'id': _checkingId,
      'name': 'HDFC Checking',
      'type': 'Bank',
      'currencyCode': 'USD',
      'balance': 6400.0,
      'colorHex': 'F7C948',
      'createdAt': DateTime(2026, 1, 4).millisecondsSinceEpoch,
      'creditLimit': null,
      'cardDigits': null,
    },
    {
      'id': _cardId,
      'name': 'ICICI Amazon Pay',
      'type': 'Credit Card',
      'currencyCode': 'USD',
      'balance': 1840.0,
      'colorHex': 'EE4D37',
      'createdAt': DateTime(2026, 2, 1).millisecondsSinceEpoch,
      'creditLimit': 15000.0,
      'cardDigits': '4321',
    },
  ]);

  box._m['transactions'] = jsonEncode([
    {
      'id': 'tx-1',
      'note': 'Salary',
      'amount': 5000.0,
      'category': 'Salary',
      'type': 'Income',
      'date': DateTime(2026, 7, 1).millisecondsSinceEpoch,
      'isRecurring': false,
      'recurrenceRuleRaw': 'Monthly',
      'nextDueDate': null,
      'photoPath': null,
      'customCategoryId': null,
      'accountId': _checkingId,
      'toAccountId': null,
    },
    {
      'id': 'tx-2',
      'note': 'Weekly shop',
      'amount': 120.5,
      'category': 'Groceries',
      'type': 'Expense',
      'date': DateTime(2026, 7, 12).millisecondsSinceEpoch,
      'isRecurring': false,
      'recurrenceRuleRaw': 'Monthly',
      'nextDueDate': null,
      'photoPath': null,
      'customCategoryId': null,
      'accountId': _checkingId,
      'toAccountId': null,
    },
    {
      'id': 'tx-3',
      'note': 'Card payment',
      'amount': 500.0,
      'category': 'Other',
      'type': 'Transfer',
      'date': DateTime(2026, 7, 15).millisecondsSinceEpoch,
      'isRecurring': false,
      'recurrenceRuleRaw': 'Monthly',
      'nextDueDate': null,
      'photoPath': null,
      'customCategoryId': null,
      'accountId': _checkingId,
      'toAccountId': _cardId,
    },
    {
      'id': 'tx-4',
      'note': 'Rent',
      'amount': 1200.0,
      'category': 'Rent',
      'type': 'Expense',
      'date': DateTime(2026, 7, 28).millisecondsSinceEpoch,
      'isRecurring': true,
      'recurrenceRuleRaw': 'Monthly',
      'nextDueDate': DateTime(2026, 8, 28).millisecondsSinceEpoch,
      'photoPath': '/var/mobile/receipt.jpg',
      'customCategoryId': null,
      'accountId': _checkingId,
      'toAccountId': null,
    },
  ]);

  box._m['customCategories'] = jsonEncode([
    {
      'id': 'cc-1',
      'name': 'Pet care',
      'emoji': '🐕',
      'typeRaw': 'Expense',
      'colorHex': '06C270',
    },
  ]);

  box._m['categoryBudgets'] = jsonEncode([
    {'id': 'b-1', 'categoryRaw': 'Groceries', 'limit': 400.0},
  ]);

  // The pre-rename field name, which is the whole point of the check.
  box._m['savingsGoals'] = jsonEncode([
    {
      'id': 'g-1',
      'name': 'Japan trip',
      'targetAmount': 3000.0,
      'currentAmount': 750.0,
      'iconName': 'star.fill',
      'colorHex': 'F7C948',
      'createdDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
    },
  ]);

  box._m['emis'] = jsonEncode([
    {
      'id': 'emi-1',
      'accountId': _cardId,
      'name': 'iPhone 17 Pro',
      'principal': 4800.0,
      'annualRate': 14.0,
      'tenureMonths': 6,
      'startDate': DateTime(2026, 6, 1).millisecondsSinceEpoch,
    },
  ]);

  return box;
}

void main() {
  group('a 1.0.0 store opened by this build', () {
    test('loads without throwing and keeps every record', () {
      final store = AppStore(_shipped_1_0_0());

      expect(store.accounts, hasLength(2));
      expect(store.transactions, hasLength(4));
      expect(store.customCategories, hasLength(1));
      expect(store.budgets, hasLength(1));
      expect(store.goals, hasLength(1));
      expect(store.emis, hasLength(1));
    });

    test('carries the goal amount across the field rename', () {
      final store = AppStore(_shipped_1_0_0());
      // 1.0.0 wrote this as 'currentAmount'. Reset to 0 here would look to the
      // user exactly like the update ate their savings progress.
      expect(store.goals.single.allocatedAmount, 750.0);
      expect(store.goals.single.targetAmount, 3000.0);
      expect(store.goals.single.name, 'Japan trip');
    });

    test('defaults every field 1.0.0 never stored', () {
      final store = AppStore(_shipped_1_0_0());
      for (final t in store.transactions) {
        expect(t.tags, isEmpty, reason: 'tags post-date 1.0.0');
        expect(t.splitGroupId, isNull);
        expect(t.debtId, isNull);
      }
      // Collections whose box keys did not exist in 1.0.0 at all.
      expect(store.debts, isEmpty);
      expect(store.goals.single.accountId, isNull);
    });

    test('preserves the detail inside a record, not just the count', () {
      final store = AppStore(_shipped_1_0_0());
      final rent = store.transactions.firstWhere((t) => t.id == 'tx-4');

      expect(rent.note, 'Rent');
      expect(rent.amount, 1200.0);
      expect(rent.category, TransactionCategory.rent);
      expect(rent.type, TransactionType.expense);
      expect(rent.isRecurring, isTrue);
      expect(rent.recurrenceRule, RecurrenceRule.monthly);
      expect(rent.nextDueDate, DateTime(2026, 8, 28));
      expect(rent.photoPath, '/var/mobile/receipt.jpg');
      expect(rent.accountId, _checkingId);

      final transfer = store.transactions.firstWhere((t) => t.id == 'tx-3');
      expect(transfer.type, TransactionType.transfer);
      expect(transfer.toAccountId, _cardId);

      final card = store.accounts.firstWhere((a) => a.id == _cardId);
      expect(card.type, AccountType.credit);
      expect(card.creditLimit, 15000.0);
      expect(card.cardDigits, '4321');
    });

    test('still computes the balance the user last saw', () {
      final store = AppStore(_shipped_1_0_0());
      final checking = store.accounts.firstWhere((a) => a.id == _checkingId);

      // Opening 6400, +5000 salary, -120.50 shop, -1200 rent, -500 transferred
      // out to the card.
      expect(store.balanceFor(checking), closeTo(9579.5, 0.001));
    });

    test('an account order written before that key existed is not lost', () {
      final store = AppStore(_shipped_1_0_0());
      // 1.0.0 had no 'accountOrder' key. Both accounts must still be listed.
      expect(
        store.accounts.map((a) => a.id),
        containsAll([_checkingId, _cardId]),
      );
    });
  });
}
