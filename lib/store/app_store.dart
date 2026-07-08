import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';

/// The reactive data layer. Replaces SwiftData's `@Model` + `@Query`.
/// Holds every entity in memory and persists each collection as JSON strings
/// in a Hive box. Notifies listeners on any mutation (like `@Query` refreshing).
class AppStore extends ChangeNotifier {
  final Box _box;
  AppStore(this._box) {
    _load();
  }

  static const _kTransactions = 'transactions';
  static const _kAccounts = 'accounts';
  static const _kCustomCategories = 'customCategories';
  static const _kBudgets = 'categoryBudgets';
  static const _kGoals = 'savingsGoals';
  static const _kEmis = 'emis';

  static Future<AppStore> create() async {
    await Hive.initFlutter();
    final box = await Hive.openBox('onyx');
    return AppStore(box);
  }

  final List<Transaction> _transactions = [];
  final List<Account> _accounts = [];
  final List<CustomCategory> _customCategories = [];
  final List<CategoryBudget> _budgets = [];
  final List<SavingsGoal> _goals = [];
  final List<Emi> _emis = [];

  // ── Public reads (mirror @Query sort orders) ──────────────────────────────

  /// All transactions, most recent first (matches ContentView's reverse query).
  List<Transaction> get transactions {
    final list = List<Transaction>.from(_transactions);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Ascending by date (matches AppRootView's `sort: \.date`).
  List<Transaction> get transactionsAscending {
    final list = List<Transaction>.from(_transactions);
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  List<Account> get accounts {
    final list = List<Account>.from(_accounts);
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  List<CustomCategory> get customCategories =>
      List<CustomCategory>.from(_customCategories);

  List<CategoryBudget> get budgets => List<CategoryBudget>.from(_budgets);

  List<SavingsGoal> get goals => List<SavingsGoal>.from(_goals);

  List<Emi> get emis => List<Emi>.from(_emis);

  // ── Relationship resolution ───────────────────────────────────────────────

  Account? accountFor(String? id) =>
      id == null ? null : _accounts.where((a) => a.id == id).firstOrNull;

  CustomCategory? customCategoryFor(String? id) =>
      id == null ? null : _customCategories.where((c) => c.id == id).firstOrNull;

  List<Transaction> transactionsForAccount(String accountId) =>
      _transactions.where((t) => t.accountId == accountId).toList();

  /// EMIs attached to an account, most recent first.
  List<Emi> emisForAccount(String accountId) {
    final list = _emis.where((e) => e.accountId == accountId).toList();
    list.sort((a, b) => b.startDate.compareTo(a.startDate));
    return list;
  }

  // ── Credit-card computations ──────────────────────────────────────────────
  //
  // For a credit card, the entered balance is treated as the current manually
  // set outstanding, and every active EMI's remaining principal adds on top —
  // so ongoing EMIs eat into available credit, exactly like a real card.

  double creditUsedFor(Account a) {
    final base = a.balance < 0 ? 0.0 : a.balance;
    final emi = emisForAccount(a.id)
        .where((e) => e.isActive)
        .fold(0.0, (s, e) => s + e.outstandingPrincipal);
    return base + emi;
  }

  double creditAvailableFor(Account a) {
    final limit = a.creditLimit ?? 0;
    if (limit <= 0) return 0;
    return (limit - creditUsedFor(a)).clamp(0.0, limit);
  }

  double creditUtilizationFor(Account a) {
    final limit = a.creditLimit ?? 0;
    if (limit <= 0) return 0;
    return (creditUsedFor(a) / limit).clamp(0.0, 1.0);
  }

  /// Net effect of every transaction on an account's balance.
  /// Income adds, expense subtracts; a transfer moves its amount OUT of the
  /// source account and INTO the destination account (so across all accounts
  /// transfers cancel out and never change total net worth).
  double transactionNet(String accountId) {
    var net = 0.0;
    for (final t in _transactions) {
      if (t.type == TransactionType.transfer) {
        if (t.accountId == accountId) net -= t.amount;
        if (t.toAccountId == accountId) net += t.amount;
      } else if (t.accountId == accountId) {
        net += t.type == TransactionType.income ? t.amount : -t.amount;
      }
    }
    return net;
  }

  /// The account's live balance: its opening balance plus the net of every
  /// transaction attached to it. Transactions are the single source of truth,
  /// so adding/editing/deleting a transaction always reconciles automatically.
  double balanceFor(Account acc) => acc.balance + transactionNet(acc.id);

  // ── Mutations ─────────────────────────────────────────────────────────────

  void addTransaction(Transaction t) {
    _transactions.add(t);
    _persist();
  }

  void updateTransaction() => _persist(); // caller mutated in place

  void deleteTransaction(Transaction t) {
    _transactions.removeWhere((e) => e.id == t.id);
    _persist();
  }

  void addAccount(Account a) {
    _accounts.add(a);
    _persist();
  }

  void deleteAccount(Account a) {
    // nullify references (SwiftData deleteRule: .nullify)
    for (final t in _transactions) {
      if (t.accountId == a.id) t.accountId = null;
      if (t.toAccountId == a.id) t.toAccountId = null;
    }
    _accounts.removeWhere((e) => e.id == a.id);
    // Cascade: an EMI has no meaning without its account.
    _emis.removeWhere((e) => e.accountId == a.id);
    _persist();
  }

  void addEmi(Emi e) {
    _emis.add(e);
    _persist();
  }

  void updateEmi() => _persist(); // caller mutated in place

  void deleteEmi(Emi e) {
    _emis.removeWhere((x) => x.id == e.id);
    _persist();
  }

  void addCustomCategory(CustomCategory c) {
    _customCategories.add(c);
    _persist();
  }

  void deleteCustomCategory(CustomCategory c) {
    for (final t in _transactions) {
      if (t.customCategoryId == c.id) t.customCategoryId = null;
    }
    _customCategories.removeWhere((e) => e.id == c.id);
    _persist();
  }

  void setBudget(TransactionCategory category, double limit) {
    final existing = _budgets.where((b) => b.categoryRaw == category.raw).firstOrNull;
    if (limit <= 0) {
      if (existing != null) _budgets.remove(existing);
    } else if (existing != null) {
      existing.limit = limit;
    } else {
      _budgets.add(CategoryBudget(category: category, limit: limit));
    }
    _persist();
  }

  /// If [t] is an expense in a built-in category whose monthly budget is now
  /// exceeded, returns the limit, the total spent that month (including [t]),
  /// and the amount over. Returns null otherwise. Mirrors the scoping used by
  /// the profile category-budgets section and the add-transaction warning:
  /// expenses only, built-in categories only, same calendar month.
  ({double limit, double spent, double over})? categoryBudgetOverage(
      Transaction t) {
    if (t.type != TransactionType.expense) return null;
    if (t.customCategoryId != null) return null;
    final budget =
        _budgets.where((b) => b.categoryRaw == t.category.raw).firstOrNull;
    if (budget == null || budget.limit <= 0) return null;

    double spent = 0;
    for (final e in _transactions) {
      if (e.type == TransactionType.expense &&
          e.customCategoryId == null &&
          e.category == t.category &&
          e.date.year == t.date.year &&
          e.date.month == t.date.month) {
        spent += e.amount;
      }
    }
    if (spent <= budget.limit) return null;
    return (limit: budget.limit, spent: spent, over: spent - budget.limit);
  }

  void addGoal(SavingsGoal g) {
    _goals.add(g);
    _persist();
  }

  void deleteGoal(SavingsGoal g) {
    _goals.removeWhere((e) => e.id == g.id);
    _persist();
  }

  void touchGoals() => _persist();

  /// Deletes every entity (Profile "reset all data").
  void wipeAll() {
    _transactions.clear();
    _accounts.clear();
    _customCategories.clear();
    _budgets.clear();
    _goals.clear();
    _emis.clear();
    _persist();
  }

  /// Generates due recurring transactions (mirrors AppRootView.generateRecurring).
  void generateRecurring() {
    final now = DateTime.now();
    var changed = false;
    for (final t in List<Transaction>.from(_transactions)) {
      if (!t.isRecurring) continue;
      var due = t.nextDueDate;
      if (due == null || due.isAfter(now)) continue;
      while (!due!.isAfter(now)) {
        final posted = Transaction(
          note: t.note,
          amount: t.amount,
          category: t.category,
          type: t.type,
          date: due,
          isRecurring: false,
        );
        // Carry the relationships forward so the generated entry stays attached
        // to its account/category and counts toward the computed balance.
        posted.accountId = t.accountId;
        posted.toAccountId = t.toAccountId;
        posted.customCategoryId = t.customCategoryId;
        _transactions.add(posted);
        due = t.recurrenceRule.nextDate(due);
      }
      t.nextDueDate = due;
      changed = true;
    }
    if (changed) _persist();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  void _load() {
    _transactions
      ..clear()
      ..addAll(_decode(_kTransactions).map(Transaction.fromJson));
    _accounts
      ..clear()
      ..addAll(_decode(_kAccounts).map(Account.fromJson));
    _customCategories
      ..clear()
      ..addAll(_decode(_kCustomCategories).map(CustomCategory.fromJson));
    _budgets
      ..clear()
      ..addAll(_decode(_kBudgets).map(CategoryBudget.fromJson));
    _goals
      ..clear()
      ..addAll(_decode(_kGoals).map(SavingsGoal.fromJson));
    _emis
      ..clear()
      ..addAll(_decode(_kEmis).map(Emi.fromJson));
  }

  List<Map> _decode(String key) {
    final raw = _box.get(key) as String?;
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map>();
  }

  void _persist() {
    _box.put(_kTransactions,
        jsonEncode(_transactions.map((e) => e.toJson()).toList()));
    _box.put(_kAccounts, jsonEncode(_accounts.map((e) => e.toJson()).toList()));
    _box.put(_kCustomCategories,
        jsonEncode(_customCategories.map((e) => e.toJson()).toList()));
    _box.put(_kBudgets, jsonEncode(_budgets.map((e) => e.toJson()).toList()));
    _box.put(_kGoals, jsonEncode(_goals.map((e) => e.toJson()).toList()));
    _box.put(_kEmis, jsonEncode(_emis.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
