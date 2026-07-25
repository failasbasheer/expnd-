import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';

/// Whole-app backup to a single JSON file, and the restore that reads it back.
///
/// EXPND keeps everything on-device by design (no network permission, no
/// account), which makes this file the *only* way data survives a lost phone,
/// a delete-and-reinstall, or a move to another device. So unlike the CSV
/// export it must be complete: every collection, the settings that shape the
/// data (currency, budget), and the receipt photos themselves — photo paths
/// are absolute and the iOS app container moves on reinstall, so paths alone
/// would come back dead.
///
/// The user decides where the file goes (share sheet → Files/iCloud/AirDrop);
/// the app itself still never touches a network.

const backupFormat = 'expnd-backup';
const backupVersion = 1;

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

/// Everything the app knows, as one JSON-encodable map.
///
/// [embedPhotos] rides the receipt images along as base64. Always true for a
/// backup the user exports off the device — the photos must travel with it.
/// Automatic on-device snapshots pass false: the image files are already
/// sitting in the same app container the snapshot is written to, so copying
/// them into every snapshot would multiply the app's storage for nothing.
Map<String, dynamic> buildBackup(AppStore store, SettingsStore settings,
    {bool embedPhotos = true}) {
  // Photos ride along as base64 keyed by filename. Missing files are skipped
  // rather than failing the whole backup — a dead path shouldn't hold the
  // rest of the data hostage.
  final photos = <String, String>{};
  if (embedPhotos) {
    for (final t in store.transactions) {
      final p = t.photoPath;
      if (p == null) continue;
      final f = File(p);
      if (f.existsSync()) {
        photos[p.split('/').last] = base64Encode(f.readAsBytesSync());
      }
    }
  }

  return {
    'format': backupFormat,
    'version': backupVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'photosEmbedded': embedPhotos,
    'settings': settings.backupSnapshot(),
    'transactions': store.transactions.map((e) => e.toJson()).toList(),
    'accounts': store.accounts.map((e) => e.toJson()).toList(),
    'customCategories':
        store.customCategories.map((e) => e.toJson()).toList(),
    'categoryBudgets': store.budgets.map((e) => e.toJson()).toList(),
    'savingsGoals': store.goals.map((e) => e.toJson()).toList(),
    'emis': store.emis.map((e) => e.toJson()).toList(),
    'debts': store.debts.map((e) => e.toJson()).toList(),
    'photos': photos,
  };
}

/// What a restore found in the file, reported back to the UI.
typedef RestoreSummary = ({int transactions, int accounts, int photos});

/// Replaces the entire store with the backup's contents.
///
/// Parses and validates everything *before* touching the store, so a corrupt
/// file leaves existing data exactly as it was — never half-restored.
/// [photoDir] is where embedded photos are written (the app documents
/// directory in production, a temp dir in tests); each transaction's
/// photoPath is rewritten to its new location.
Future<RestoreSummary> restoreBackup(
  String jsonString,
  AppStore store,
  SettingsStore settings,
  Directory photoDir,
) async {
  final Map<String, dynamic> root;
  try {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw BackupException('Not an EXPND backup file.');
    }
    root = decoded;
  } on FormatException {
    throw BackupException('Not an EXPND backup file.');
  }

  if (root['format'] != backupFormat) {
    throw BackupException('Not an EXPND backup file.');
  }
  final version = root['version'];
  if (version is! int || version < 1 || version > backupVersion) {
    throw BackupException(
        'This backup was made by a newer version of EXPND — update the app '
        'and try again.');
  }

  // Parse it all up front: any malformed entity aborts before the wipe.
  final List<Transaction> transactions;
  final List<Account> accounts;
  final List<CustomCategory> customCategories;
  final List<CategoryBudget> budgets;
  final List<SavingsGoal> goals;
  final List<Emi> emis;
  final List<Debt> debts;
  try {
    List<T> parse<T>(String key, T Function(Map) fromJson) =>
        ((root[key] as List?) ?? const [])
            .map((e) => fromJson(e as Map))
            .toList();
    transactions = parse('transactions', Transaction.fromJson);
    accounts = parse('accounts', Account.fromJson);
    customCategories = parse('customCategories', CustomCategory.fromJson);
    budgets = parse('categoryBudgets', CategoryBudget.fromJson);
    goals = parse('savingsGoals', SavingsGoal.fromJson);
    emis = parse('emis', Emi.fromJson);
    debts = parse('debts', Debt.fromJson);
  } catch (_) {
    throw BackupException('This backup file is damaged and can\'t be read.');
  }

  // Write photos out and repoint each transaction at its restored copy.
  // A missing photo degrades to "no photo", same as backup-time.
  final photos = (root['photos'] as Map?) ?? const {};
  var photosRestored = 0;
  for (final t in transactions) {
    final p = t.photoPath;
    if (p == null) continue;
    final name = p.split('/').last;
    final data = photos[name];
    if (data is String) {
      final file = File('${photoDir.path}/$name');
      await file.writeAsBytes(base64Decode(data));
      t.photoPath = file.path;
      photosRestored++;
      continue;
    }
    // An on-device snapshot didn't carry the image because it never left the
    // device — so look for the file where it already lives, both at the
    // recorded path and beside the other restored photos.
    final beside = File('${photoDir.path}/$name');
    if (File(p).existsSync()) {
      photosRestored++;
    } else if (beside.existsSync()) {
      t.photoPath = beside.path;
      photosRestored++;
    } else {
      t.photoPath = null;
    }
  }

  store.replaceAll(
    transactions: transactions,
    accounts: accounts,
    customCategories: customCategories,
    budgets: budgets,
    goals: goals,
    emis: emis,
    debts: debts,
  );
  settings.applyBackup((root['settings'] as Map?) ?? const {});

  return (
    transactions: transactions.length,
    accounts: accounts.length,
    photos: photosRestored,
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// Automatic on-device snapshots
// ─────────────────────────────────────────────────────────────────────────────

/// Folder under the app documents directory holding the rolling snapshots.
const autoBackupDirName = 'backups';

/// How many snapshots to keep. Enough to step back past a bad import or an
/// accidental "clear all data" noticed a few days late, without hoarding.
const autoBackupKeep = 5;

/// How stale a snapshot may get before another is written.
const autoBackupInterval = Duration(days: 1);

Directory autoBackupDir(Directory documents) =>
    Directory('${documents.path}/$autoBackupDirName');

/// The snapshots on disk, newest first.
List<File> listAutoBackups(Directory documents) {
  final dir = autoBackupDir(documents);
  if (!dir.existsSync()) return const [];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path)); // timestamped names sort by age
  return files;
}

/// Writes a snapshot and prunes the oldest beyond [autoBackupKeep].
///
/// Returns the file written. Never throws for lack of space or a missing
/// directory — a failed snapshot must not take the app down with it, and the
/// next launch will simply try again.
Future<File?> writeAutoBackup(
  AppStore store,
  SettingsStore settings,
  Directory documents,
) async {
  try {
    final dir = autoBackupDir(documents);
    if (!dir.existsSync()) await dir.create(recursive: true);

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file = File('${dir.path}/expnd-$stamp.json');

    await file.writeAsString(
        jsonEncode(buildBackup(store, settings, embedPhotos: false)));

    for (final old in listAutoBackups(documents).skip(autoBackupKeep)) {
      try {
        old.deleteSync();
      } catch (_) {
        // A snapshot we can't delete is not worth failing the backup over.
      }
    }

    settings.lastAutoBackupMs = now.millisecondsSinceEpoch;
    return file;
  } catch (_) {
    return null;
  }
}

/// Writes a snapshot if auto-backup is on, there is data worth keeping, and
/// the last one has gone stale. Safe to call on every launch.
Future<File?> maybeAutoBackup(
  AppStore store,
  SettingsStore settings,
  Directory documents,
) async {
  if (!settings.autoBackupEnabled) return null;
  // Nothing typed yet — a snapshot of an empty ledger protects nothing.
  if (store.transactions.isEmpty && store.accounts.isEmpty) return null;
  final last = settings.lastAutoBackupAt;
  if (last != null && DateTime.now().difference(last) < autoBackupInterval) {
    return null;
  }
  return writeAutoBackup(store, settings, documents);
}
