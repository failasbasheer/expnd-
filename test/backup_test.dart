// EXPND stores everything on-device with no sync, so the backup file is the
// only path by which data survives a lost phone or a reinstall. These tests
// cover the two things that matter: a backup must be complete, and a restore
// must never leave the store half-written.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('expnd-backup-test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<SettingsStore> newSettings() async => SettingsStore.create();
  AppStore newStore() => AppStore(_FakeBox());

  /// A store with one of everything, so "complete" is actually testable.
  ({AppStore store, Account checking, Account savings}) populate(
    AppStore store,
  ) {
    final checking = Account(
      name: 'Checking',
      type: AccountType.bank,
      currencyCode: 'USD',
      balance: 1000,
    );
    final savings = Account(
      name: 'Savings',
      type: AccountType.savings,
      currencyCode: 'USD',
      balance: 5000,
    );
    store.addAccount(checking);
    store.addAccount(savings);

    store.addTransaction(
      Transaction(
        note: 'Blue Bottle',
        amount: 6.50,
        category: TransactionCategory.food,
        type: TransactionType.expense,
      )..accountId = checking.id,
    );
    store.addTransaction(
      Transaction(
        note: 'Salary',
        amount: 4200,
        category: TransactionCategory.salary,
        type: TransactionType.income,
      )..accountId = checking.id,
    );

    store.setBudget(TransactionCategory.food, 400);
    store.addCustomCategory(
      CustomCategory(
        name: 'Coffee',
        emoji: '☕',
        typeRaw: 'Expense',
        colorHex: 'F97316',
      ),
    );
    store.addGoal(
      SavingsGoal(
        name: 'Japan Trip',
        targetAmount: 6000,
        allocatedAmount: 2350,
        accountId: savings.id,
      ),
    );
    store.addEmi(
      Emi(
        accountId: checking.id,
        name: 'MacBook',
        principal: 12000,
        annualRate: 13.5,
        tenureMonths: 12,
        startDate: DateTime(2026, 1, 14),
      ),
    );
    return (store: store, checking: checking, savings: savings);
  }

  group('backup', () {
    test('carries every collection, not just transactions', () async {
      final store = newStore();
      populate(store);
      final settings = await newSettings();
      settings.currencyCode = 'INR';
      settings.monthlyBudget = 3000;

      final data = buildBackup(store, settings);

      // The CSV export only ever held transactions — this is the gap it left.
      expect((data['transactions'] as List).length, 2);
      expect((data['accounts'] as List).length, 2);
      expect((data['categoryBudgets'] as List).length, 1);
      expect((data['customCategories'] as List).length, 1);
      expect((data['savingsGoals'] as List).length, 1);
      expect((data['emis'] as List).length, 1);
      expect((data['settings'] as Map)['currencyCode'], 'INR');
      expect((data['settings'] as Map)['monthlyBudget'], 3000);
      expect(data['format'], backupFormat);
    });

    test('round-trips a full dataset into an empty store', () async {
      final source = newStore();
      final fixture = populate(source);
      final sourceSettings = await newSettings();
      sourceSettings.currencyCode = 'INR';
      sourceSettings.userName = 'Failas';
      final json = jsonEncode(buildBackup(source, sourceSettings));

      final target = newStore();
      final targetSettings = await newSettings();
      final summary = await restoreBackup(json, target, targetSettings, tmp);

      expect(summary.transactions, 2);
      expect(summary.accounts, 2);
      expect(target.goals.single.name, 'Japan Trip');
      expect(target.goals.single.allocatedAmount, 2350);
      expect(target.emis.single.name, 'MacBook');
      expect(target.budgets.single.limit, 400);
      expect(target.customCategories.single.name, 'Coffee');
      expect(targetSettings.currencyCode, 'INR');
      expect(targetSettings.userName, 'Failas');

      // Balances must survive intact — they're the whole point.
      final restored = target.accounts.firstWhere((a) => a.name == 'Checking');
      expect(
        target.balanceFor(restored),
        fixture.store.balanceFor(fixture.checking),
      );
    });

    test('relinks transactions to their accounts', () async {
      final source = newStore();
      final fixture = populate(source);
      final settings = await newSettings();
      final json = jsonEncode(buildBackup(source, settings));

      final target = newStore();
      await restoreBackup(json, target, await newSettings(), tmp);

      final checking = target.accounts.firstWhere((a) => a.name == 'Checking');
      expect(checking.id, fixture.checking.id); // ids are preserved
      expect(target.transactionsForAccount(checking.id).length, 2);
    });

    test('embeds receipt photos and writes them back out', () async {
      final store = newStore();
      populate(store);
      final photo = File('${tmp.path}/receipt_1.jpg');
      await photo.writeAsBytes([1, 2, 3, 4, 5]);
      store.transactions.first.photoPath = photo.path;
      store.updateTransaction();

      final json = jsonEncode(buildBackup(store, await newSettings()));
      // Simulate a reinstall: the original container is gone.
      await photo.delete();

      final target = newStore();
      final restoreDir = await Directory.systemTemp.createTemp('expnd-photos');
      final summary = await restoreBackup(
        json,
        target,
        await newSettings(),
        restoreDir,
      );

      expect(summary.photos, 1);
      final restoredPath = target.transactions
          .firstWhere((t) => t.photoPath != null)
          .photoPath!;
      expect(File(restoredPath).readAsBytesSync(), [1, 2, 3, 4, 5]);
      await restoreDir.delete(recursive: true);
    });

    test('a photo missing at backup time does not abort the backup', () async {
      final store = newStore();
      populate(store);
      store.transactions.first.photoPath = '${tmp.path}/gone.jpg';
      store.updateTransaction();

      final data = buildBackup(store, await newSettings());
      expect((data['photos'] as Map), isEmpty);
      expect((data['transactions'] as List).length, 2);
    });
  });

  group('restore refuses bad input without touching existing data', () {
    Future<void> expectRejected(String content, Matcher message) async {
      final store = newStore();
      populate(store);
      final before = store.transactions.length;
      final settings = await newSettings();

      await expectLater(
        () => restoreBackup(content, store, settings, tmp),
        throwsA(
          isA<BackupException>().having((e) => e.message, 'message', message),
        ),
      );
      // The store must be exactly as it was — never half-restored.
      expect(store.transactions.length, before);
      expect(store.accounts.length, 2);
      expect(store.goals.length, 1);
    }

    test('rejects a non-JSON file', () async {
      await expectRejected('this is not json', contains('Not an EXPND backup'));
    });

    test('rejects JSON that is not an EXPND backup', () async {
      await expectRejected(
        jsonEncode({'some': 'other', 'app': 1}),
        contains('Not an EXPND backup'),
      );
    });

    test('rejects a backup from a newer app version', () async {
      await expectRejected(
        jsonEncode({'format': backupFormat, 'version': backupVersion + 1}),
        contains('newer version'),
      );
    });

    test('rejects a damaged backup mid-file', () async {
      await expectRejected(
        jsonEncode({
          'format': backupFormat,
          'version': backupVersion,
          'transactions': [
            {'id': 'x', 'note': 'ok'}, // missing required amount/category
          ],
        }),
        contains('damaged'),
      );
    });
  });

  test('restoring never bounces the user back into first-run setup', () async {
    final source = newStore();
    populate(source);
    final json = jsonEncode(buildBackup(source, await newSettings()));

    final settings = await newSettings();
    expect(settings.hasCompletedAccountSetup, isFalse);
    await restoreBackup(json, newStore(), settings, tmp);
    expect(settings.hasCompletedAccountSetup, isTrue);
  });

  test('biometric lock is not carried across devices', () async {
    final settings = await newSettings();
    settings.biometricLockEnabled = true;
    final snapshot = settings.backupSnapshot();
    // Restoring "locked" onto a device with no Face ID enrolled would lock
    // the user out of their own data.
    expect(snapshot.containsKey('biometricLockEnabled'), isFalse);
  });

  group('automatic snapshots', () {
    test('writes a snapshot and records when', () async {
      final store = newStore();
      populate(store);
      final settings = await newSettings();

      expect(settings.lastAutoBackupAt, isNull);
      final file = await writeAutoBackup(store, settings, tmp);

      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(settings.lastAutoBackupAt, isNotNull);
      expect(listAutoBackups(tmp).length, 1);
    });

    test('keeps only the most recent few', () async {
      final store = newStore();
      populate(store);
      final settings = await newSettings();

      for (var i = 0; i < autoBackupKeep + 3; i++) {
        await writeAutoBackup(store, settings, tmp);
        // Names carry a whole-second stamp, so space them out enough to differ.
        await Future.delayed(const Duration(milliseconds: 1100));
      }

      expect(listAutoBackups(tmp).length, autoBackupKeep);
    });

    test('a snapshot restores the ledger', () async {
      final store = newStore();
      populate(store);
      final settings = await newSettings();
      final file = await writeAutoBackup(store, settings, tmp);

      final target = newStore();
      final targetSettings = await newSettings();
      final summary = await restoreBackup(
        await file!.readAsString(),
        target,
        targetSettings,
        tmp,
      );

      expect(summary.transactions, store.transactions.length);
      expect(summary.accounts, store.accounts.length);
      expect(target.emis.length, store.emis.length);
    });

    test(
      'snapshots leave the photos on disk rather than copying them',
      () async {
        final store = newStore();
        populate(store);
        final settings = await newSettings();

        final embedded = buildBackup(store, settings);
        final onDevice = buildBackup(store, settings, embedPhotos: false);

        expect(embedded['photosEmbedded'], isTrue);
        expect(onDevice['photosEmbedded'], isFalse);
        expect((onDevice['photos'] as Map), isEmpty);
        // The exported one still carries them, which is the whole point of it.
        expect(
          (embedded['photos'] as Map).length,
          greaterThanOrEqualTo((onDevice['photos'] as Map).length),
        );
      },
    );

    test(
      'maybeAutoBackup skips an empty ledger, a fresh one, and when off',
      () async {
        final settings = await newSettings();

        // Nothing typed yet — a snapshot of an empty ledger protects nothing.
        expect(await maybeAutoBackup(newStore(), settings, tmp), isNull);

        final store = newStore();
        populate(store);
        expect(await maybeAutoBackup(store, settings, tmp), isNotNull);
        // Just taken, so the next launch must not take another.
        expect(await maybeAutoBackup(store, settings, tmp), isNull);

        settings.autoBackupEnabled = false;
        settings.lastAutoBackupMs = 0;
        expect(await maybeAutoBackup(store, settings, tmp), isNull);
      },
    );
  });
}
