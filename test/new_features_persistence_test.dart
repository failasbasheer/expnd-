// Persistence and backup compatibility for the refunds/reimbursements,
// subscriptions manager and payday budget-cycle features. Stored Hive JSON
// and backup files written before these features must keep loading, and the
// new metadata must survive both a relaunch and a backup round trip.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/services/backup.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';

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

/// A transaction exactly as 1.0.0 wrote it: none of the new keys present.
Map<String, dynamic> _legacyTransactionJson() => {
  'id': 'legacy-1',
  'note': 'Netflix',
  'amount': 15.49,
  'category': 'entertainment',
  'type': 'expense',
  'date': DateTime(2026, 3, 4).millisecondsSinceEpoch,
  'isRecurring': true,
  'recurrenceRuleRaw': 'monthly',
  'nextDueDate': DateTime(2026, 4, 4).millisecondsSinceEpoch,
  'photoPath': null,
  'customCategoryId': null,
  'accountId': 'acc-1',
  'toAccountId': null,
};

Map<String, dynamic> _legacyAccountJson() => Account(
  id: 'acc-1',
  name: 'Checking',
  type: AccountType.bank,
  currencyCode: 'USD',
  balance: 500,
).toJson();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('expnd-new-features-test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  ({AppStore store, Account bank, Transaction purchase, Transaction sub})
  populate(AppStore store) {
    final bank = Account(
      name: 'Checking',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 1000,
    );
    store.addAccount(bank);
    final purchase = Transaction(
      note: 'Conference hotel',
      amount: 300,
      category: TransactionCategory.shopping,
      type: TransactionType.expense,
    )..accountId = bank.id;
    store.addTransaction(purchase);
    store.trackReimbursement(purchase, expected: 250, from: 'Employer');
    store.recordPurchaseReturn(
      purchase,
      amount: 100,
      accountId: bank.id,
      kind: 'reimbursement',
    );
    store.recordPurchaseReturn(
      purchase,
      amount: 20,
      accountId: bank.id,
      kind: 'refund',
    );
    final sub = Transaction(
      note: 'Music',
      amount: 9.99,
      category: TransactionCategory.entertainment,
      type: TransactionType.expense,
      isRecurring: true,
      tags: ['subscription'],
      subscriptionTrialEndDate: DateTime(2026, 11, 1),
    )..accountId = bank.id;
    store.addTransaction(sub);
    return (store: store, bank: bank, purchase: purchase, sub: sub);
  }

  group('Transaction JSON', () {
    test('new metadata round-trips through toJson/fromJson', () {
      final t = Transaction(
        note: 'Refund: Shoes',
        amount: 40,
        category: TransactionCategory.shopping,
        type: TransactionType.income,
        relatedPurchaseId: 'p-1',
        relatedPurchaseKind: 'refund',
        reimbursementExpected: 12.5,
        reimbursementFrom: 'Sam',
        subscriptionTrialEndDate: DateTime(2026, 12, 24),
      );
      final back = Transaction.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map,
      );
      expect(back.relatedPurchaseId, 'p-1');
      expect(back.relatedPurchaseKind, 'refund');
      expect(back.reimbursementExpected, 12.5);
      expect(back.reimbursementFrom, 'Sam');
      expect(back.subscriptionTrialEndDate, DateTime(2026, 12, 24));
    });

    test('legacy JSON without the new keys decodes with null defaults', () {
      final t = Transaction.fromJson(_legacyTransactionJson());
      expect(t.relatedPurchaseId, isNull);
      expect(t.relatedPurchaseKind, isNull);
      expect(t.reimbursementExpected, isNull);
      expect(t.reimbursementFrom, isNull);
      expect(t.subscriptionTrialEndDate, isNull);
      expect(t.tags, isEmpty);
      expect(t.amount, 15.49);
    });

    test('a malformed optional value drops only that annotation', () {
      final t = Transaction.fromJson({
        ..._legacyTransactionJson(),
        'reimbursementExpected': 'lots',
        'subscriptionTrialEndDate': 'soon',
        'relatedPurchaseId': 42,
      });
      expect(t.reimbursementExpected, isNull);
      expect(t.subscriptionTrialEndDate, isNull);
      expect(t.relatedPurchaseId, isNull);
      expect(t.note, 'Netflix');
    });
  });

  group('Hive persistence', () {
    test('reimbursement links and trial dates survive a relaunch', () {
      final box = _FakeBox();
      final s = populate(AppStore(box));
      final reloaded = AppStore(box);

      final purchase = reloaded.transactions.firstWhere(
        (t) => t.id == s.purchase.id,
      );
      expect(purchase.reimbursementExpected, 250);
      expect(purchase.reimbursementFrom, 'Employer');
      expect(reloaded.returnedFor(purchase, kind: 'reimbursement'), 100);
      expect(reloaded.returnedFor(purchase, kind: 'refund'), 20);
      expect(reloaded.reimbursementOutstanding(purchase), 150);
      expect(
        reloaded.transactions
            .firstWhere((t) => t.id == s.sub.id)
            .subscriptionTrialEndDate,
        DateTime(2026, 11, 1),
      );
    });

    test('returns are ordinary income; Account.balance is untouched', () {
      final s = populate(AppStore(_FakeBox()));
      expect(s.bank.balance, 1000);
      // 1000 opening − 300 − 9.99 + 100 + 20.
      expect(s.store.balanceFor(s.bank), closeTo(810.01, 1e-9));
    });

    test('posting a subscription early keeps its tag', () {
      final s = populate(AppStore(_FakeBox()));
      s.sub.nextDueDate = DateTime.now().add(const Duration(days: 3));
      final posted = s.store.postRecurringNow(s.sub);
      expect(posted.tags, ['subscription']);
      expect(posted.isRecurring, isFalse);
    });

    test('a box written before these features still loads', () {
      final box = _FakeBox()
        ..put('transactions', jsonEncode([_legacyTransactionJson()]))
        ..put('accounts', jsonEncode([_legacyAccountJson()]));
      final store = AppStore(box);
      expect(store.transactions, hasLength(1));
      expect(store.reimbursablePurchases, isEmpty);
      expect(store.returnsFor(store.transactions.single), isEmpty);
    });
  });

  group('Backup', () {
    test('new transaction metadata round-trips through a backup', () async {
      final s = populate(AppStore(_FakeBox()));
      final settings = await SettingsStore.create();
      final json = jsonEncode(buildBackup(s.store, settings));

      final target = AppStore(_FakeBox());
      await restoreBackup(json, target, settings, tmp);

      final purchase = target.transactions.firstWhere(
        (t) => t.id == s.purchase.id,
      );
      expect(purchase.reimbursementExpected, 250);
      expect(purchase.reimbursementFrom, 'Employer');
      expect(target.returnsFor(purchase), hasLength(2));
      expect(
        target.transactions
            .firstWhere((t) => t.id == s.sub.id)
            .subscriptionTrialEndDate,
        DateTime(2026, 11, 1),
      );
    });

    test('budget cycle and payday settings round-trip', () async {
      final settings = await SettingsStore.create();
      settings.budgetCycle = 'fortnightly';
      settings.paydayDay = 25;
      settings.paydayAnchor = DateTime(2026, 10, 2);
      final json = jsonEncode(buildBackup(AppStore(_FakeBox()), settings));

      // Restore onto a fresh device's preferences.
      SharedPreferences.setMockInitialValues({});
      final fresh = await SettingsStore.create();
      expect(fresh.budgetCycle, 'calendar');
      expect(fresh.paydayConfigured, isFalse);

      await restoreBackup(json, AppStore(_FakeBox()), fresh, tmp);
      expect(fresh.budgetCycle, 'fortnightly');
      expect(fresh.paydayDay, 25);
      expect(fresh.paydayAnchor, DateTime(2026, 10, 2));
      expect(fresh.paydayConfigured, isTrue);
    });

    test('an unconfigured payday is not invented by a backup', () async {
      final settings = await SettingsStore.create();
      final snap = settings.backupSnapshot();
      expect(snap['budgetCycle'], 'calendar');
      expect(snap.containsKey('paydayDay'), isFalse);
      expect(snap.containsKey('paydayAnchor'), isFalse);
    });

    test('a timestamped payday anchor is stored date-only', () async {
      final settings = await SettingsStore.create();
      settings.applyBackup({
        'budgetCycle': 'weekly',
        'paydayAnchor': '2026-10-02T23:30:00.000',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('paydayAnchor'), '2026-10-02');
      expect(settings.paydayAnchor, DateTime(2026, 10, 2));
    });

    test('invalid cycle values in a backup are ignored', () async {
      final settings = await SettingsStore.create();
      settings.applyBackup({
        'budgetCycle': 'hourly',
        'paydayDay': 99,
        'paydayAnchor': 'not a date',
      });
      expect(settings.budgetCycle, 'calendar');
      expect(settings.paydayDay, 31);
      expect(settings.paydayAnchor, DateTime(2020, 1, 6));
    });

    test('a 1.0.0 backup without any new keys still imports', () async {
      final legacy = jsonEncode({
        'format': backupFormat,
        'version': 1,
        'exportedAt': '2026-07-21T10:00:00.000',
        'photosEmbedded': true,
        'settings': {
          'currencyCode': 'USD',
          'monthlyBudget': 1200.0,
          'userName': 'Alex',
          'budgetRollover': false,
        },
        'transactions': [_legacyTransactionJson()],
        'accounts': [_legacyAccountJson()],
        'customCategories': [],
        'categoryBudgets': [],
        'savingsGoals': [],
        'emis': [],
        'debts': [],
        'accountOrder': [],
        'photos': {},
      });
      final store = AppStore(_FakeBox());
      final settings = await SettingsStore.create();
      final summary = await restoreBackup(legacy, store, settings, tmp);

      expect(summary.transactions, 1);
      expect(summary.accounts, 1);
      final t = store.transactions.single;
      expect(t.reimbursementExpected, isNull);
      expect(t.subscriptionTrialEndDate, isNull);
      expect(settings.budgetCycle, 'calendar');
      expect(settings.paydayConfigured, isFalse);
      expect(settings.monthlyBudget, 1200);
    });
  });
}
