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
  static const _kDebts = 'debts';
  static const _kAccountOrder = 'accountOrder';
  static const _kPendingCaptures = 'pendingCaptures';

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
  final List<Debt> _debts = [];
  final List<PendingCapture> _pendingCaptures = [];

  /// User-defined account order (account ids). Empty means "no preference" —
  /// fall back to creation order. Ids not listed here sort after listed ones,
  /// so adding an account never disturbs the arrangement.
  List<String> _accountOrder = [];

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
    if (_accountOrder.isEmpty) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    }
    int rank(Account a) {
      final i = _accountOrder.indexOf(a.id);
      return i == -1 ? 1 << 30 : i;
    }

    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  List<String> get accountOrder => List<String>.from(_accountOrder);

  /// Sets the user's account arrangement (see [_accountOrder]). Callers pass
  /// the full list of ids in the new order.
  void reorderAccounts(List<String> orderedIds) {
    _accountOrder = List<String>.from(orderedIds);
    _persist();
  }

  List<CustomCategory> get customCategories =>
      List<CustomCategory>.from(_customCategories);

  List<CategoryBudget> get budgets => List<CategoryBudget>.from(_budgets);

  List<SavingsGoal> get goals => List<SavingsGoal>.from(_goals);

  List<Emi> get emis => List<Emi>.from(_emis);

  /// Newest first, unsettled before settled — the order the screen wants.
  List<Debt> get debts {
    final list = List<Debt>.from(_debts);
    list.sort((a, b) {
      if (a.isSettled != b.isSettled) return a.isSettled ? 1 : -1;
      return b.date.compareTo(a.date);
    });
    return list;
  }

  // ── Relationship resolution ───────────────────────────────────────────────

  Account? accountFor(String? id) =>
      id == null ? null : _accounts.where((a) => a.id == id).firstOrNull;

  CustomCategory? customCategoryFor(String? id) => id == null
      ? null
      : _customCategories.where((c) => c.id == id).firstOrNull;

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
    final base = balanceFor(a).clamp(0.0, double.infinity);
    final emi = emisForAccount(
      a.id,
    ).where((e) => e.isActive).fold(0.0, (s, e) => s + e.outstandingPrincipal);
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
    final isCredit = accountFor(accountId)?.type == AccountType.credit;
    var net = 0.0;
    for (final t in _transactions) {
      if (t.type == TransactionType.transfer) {
        if (t.accountId == accountId) net += isCredit ? t.amount : -t.amount;
        if (t.toAccountId == accountId) net += isCredit ? -t.amount : t.amount;
      } else if (t.accountId == accountId) {
        if (isCredit) {
          net += t.type == TransactionType.income ? -t.amount : t.amount;
        } else {
          net += t.type == TransactionType.income ? t.amount : -t.amount;
        }
      }
    }
    return net;
  }

  /// The account's live balance: its opening balance plus the net of every
  /// transaction attached to it. Transactions are the single source of truth,
  /// so adding/editing/deleting a transaction always reconciles automatically.
  double balanceFor(Account acc) => acc.balance + transactionNet(acc.id);

  /// Net-worth contribution: assets are positive, credit-card liabilities are
  /// negative and include both posted spending and active EMI principal.
  ///
  /// Unlike [creditUsedFor], a card's balance isn't floored at 0 here: an
  /// overpaid card holds a credit that belongs to the user, so moving money
  /// onto it from their own bank must leave net worth unchanged.
  double netWorthFor(Account acc) {
    if (acc.type != AccountType.credit) return balanceFor(acc);
    final emi = emisForAccount(
      acc.id,
    ).where((e) => e.isActive).fold(0.0, (s, e) => s + e.outstandingPrincipal);
    return -(balanceFor(acc) + emi);
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  void addTransaction(Transaction t) {
    _transactions.add(t);
    _persist();
  }

  /// Purchases awaiting money back. This metadata never changes the ledger.
  List<Transaction> get reimbursablePurchases => transactions
      .where(
        (t) =>
            t.type == TransactionType.expense &&
            t.reimbursementExpected != null &&
            t.reimbursementExpected! > 0,
      )
      .toList();

  void trackReimbursement(
    Transaction purchase, {
    required double expected,
    required String from,
  }) {
    if (!_transactions.contains(purchase) ||
        purchase.type != TransactionType.expense ||
        !expected.isFinite ||
        expected <= 0 ||
        expected > purchase.amount - returnedFor(purchase, kind: 'refund') ||
        expected < returnedFor(purchase, kind: 'reimbursement') ||
        from.trim().isEmpty) {
      throw ArgumentError(
        'Enter a valid purchase, amount, and person or source.',
      );
    }
    purchase.reimbursementExpected = expected;
    purchase.reimbursementFrom = from.trim();
    _persist();
  }

  void stopTrackingReimbursement(Transaction purchase) {
    purchase.reimbursementExpected = null;
    purchase.reimbursementFrom = null;
    _persist();
  }

  List<Transaction> returnsFor(Transaction purchase, {String? kind}) =>
      transactions
          .where(
            (t) =>
                t.type == TransactionType.income &&
                t.relatedPurchaseId == purchase.id &&
                (kind == null || t.relatedPurchaseKind == kind),
          )
          .toList();

  double returnedFor(Transaction purchase, {String? kind}) =>
      returnsFor(purchase, kind: kind).fold(0, (sum, t) => sum + t.amount);

  double reimbursementOutstanding(Transaction purchase) {
    final expected =
        (purchase.reimbursementExpected ?? 0) -
        returnedFor(purchase, kind: 'reimbursement');
    final purchaseRemaining = purchase.amount - returnedFor(purchase);
    return expected.clamp(0, purchaseRemaining.clamp(0, double.infinity));
  }

  /// Record money that actually arrived. Income stays attached to an account
  /// and is linked to its original expense for history and remaining amounts.
  Transaction recordPurchaseReturn(
    Transaction purchase, {
    required double amount,
    required String accountId,
    required String kind,
  }) {
    if (!_transactions.contains(purchase) ||
        purchase.type != TransactionType.expense ||
        accountFor(accountId) == null ||
        !amount.isFinite ||
        amount <= 0 ||
        (kind != 'refund' && kind != 'reimbursement')) {
      throw ArgumentError(
        'Choose a valid purchase, amount, account, and return type.',
      );
    }
    final purchaseAccount = accountFor(purchase.accountId);
    if (purchaseAccount != null &&
        accountFor(accountId)!.currencyCode != purchaseAccount.currencyCode) {
      throw ArgumentError('Use an account in the purchase currency.');
    }
    final cap = kind == 'refund'
        ? purchase.amount - returnedFor(purchase)
        : reimbursementOutstanding(purchase);
    if (amount > cap + 0.000001) {
      throw ArgumentError('Amount exceeds what is still expected.');
    }
    final returned = Transaction(
      note: kind == 'refund'
          ? 'Refund: ${purchase.note}'
          : 'Reimbursement: ${purchase.note}',
      amount: amount,
      category: purchase.category,
      type: TransactionType.income,
      accountId: accountId,
      relatedPurchaseId: purchase.id,
      relatedPurchaseKind: kind,
    );
    _transactions.add(returned);
    _persist();
    return returned;
  }

  void updateTransaction() {
    _reconcileAutoSettledDebts();
    _persist();
  } // caller mutated in place

  /// Posts a recurring series' next occurrence early, then advances the
  /// schedule one step so it stops being projected on the Upcoming screen.
  /// Dated now — the user is recording it as done today, ahead of when
  /// [generateRecurring] would have auto-posted it. The posted row is an
  /// ordinary (non-recurring) transaction, exactly like an auto-posted one.
  Transaction postRecurringNow(Transaction source) {
    final posted = Transaction(
      note: source.note,
      amount: source.amount,
      category: source.category,
      type: source.type,
      date: DateTime.now(),
      isRecurring: false,
    );
    posted.accountId = source.accountId;
    posted.toAccountId = source.toAccountId;
    posted.customCategoryId = source.customCategoryId;
    // Same as an auto-posted occurrence, so a subscription charge stays tagged.
    posted.tags = List<String>.from(source.tags);
    _transactions.add(posted);
    final due = source.nextDueDate;
    if (due != null) {
      source.nextDueDate = source.recurrenceRule.nextDate(due);
    }
    _persist();
    return posted;
  }

  /// Skips a recurring series' next occurrence: advances the schedule one step
  /// without posting anything, so a bill you won't pay this cycle drops off
  /// Upcoming without leaving a phantom transaction behind.
  void skipRecurringOccurrence(Transaction source) {
    final due = source.nextDueDate;
    if (due == null) return;
    source.nextDueDate = source.recurrenceRule.nextDate(due);
    _persist();
  }

  void deleteTransaction(Transaction t) {
    _transactions.removeWhere((e) => e.id == t.id);
    _reconcileAutoSettledDebts();
    _persist();
  }

  /// Removes many transactions in one shot (History's multi-select delete), so
  /// the ledger persists and notifies once instead of once per row.
  void deleteTransactions(Set<String> ids) {
    if (ids.isEmpty) return;
    _transactions.removeWhere((e) => ids.contains(e.id));
    _reconcileAutoSettledDebts();
    _persist();
  }

  void addAccount(Account a) {
    _accounts.add(a);
    _persist();
  }

  void deleteAccount(Account a) {
    // A transfer with a deleted endpoint is no longer a meaningful movement;
    // remove it rather than leaving a one-sided phantom transfer.
    _transactions.removeWhere(
      (t) =>
          t.type == TransactionType.transfer &&
          (t.accountId == a.id || t.toAccountId == a.id),
    );
    for (final t in _transactions) {
      if (t.accountId == a.id) t.accountId = null;
      if (t.toAccountId == a.id) t.toAccountId = null;
    }
    for (final g in _goals) {
      if (g.accountId == a.id) {
        g.accountId = null;
        g.allocatedAmount = 0;
      }
    }
    for (final d in _debts) {
      if (d.accountId == a.id) d.accountId = null;
    }
    _accounts.removeWhere((e) => e.id == a.id);
    _accountOrder.remove(a.id);
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
    // Untag the installments but keep them: the money really did move.
    for (final t in _transactions) {
      if (t.emiId == e.id) t.emiId = null;
    }
    _emis.removeWhere((x) => x.id == e.id);
    _persist();
  }

  // ── EMI installments ──────────────────────────────────────────────────────
  //
  // An EMI's schedule is a *plan* derived from its start date and tenure; a
  // payment is a *fact*. Recording one writes an ordinary expense against the
  // account the money actually left, tagged with the EMI id — the same shape
  // debt repayments use. The schedule getters stay time-based, so projections
  // and outstanding principal are unchanged by whether you logged the payment.

  /// Installments recorded against [e], newest first.
  List<Transaction> installmentsOn(Emi e) {
    final list = _transactions.where((t) => t.emiId == e.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Total actually paid toward [e] so far, from recorded installments.
  double paidOn(Emi e) => installmentsOn(e).fold(0.0, (s, t) => s + t.amount);

  /// True once an installment has been recorded in [month] — used to stop the
  /// same one being logged twice from the Upcoming list.
  bool isInstallmentPaid(Emi e, DateTime month) => installmentsOn(
    e,
  ).any((t) => t.date.year == month.year && t.date.month == month.month);

  /// Records one installment of [e] as really paid out of [accountId].
  ///
  /// [amount] defaults to the scheduled installment, but is settable because
  /// a lender's rounding rarely matches ours to the paisa.
  Transaction payEmiInstallment(
    Emi e, {
    String? accountId,
    double? amount,
    DateTime? date,
  }) {
    final t = Transaction(
      note: e.name.trim().isEmpty ? 'EMI installment' : e.name.trim(),
      amount: amount ?? e.monthlyAmount,
      category: TransactionCategory.other,
      type: TransactionType.expense,
      date: date ?? DateTime.now(),
      accountId: accountId,
      emiId: e.id,
    );
    _transactions.add(t);
    _persist();
    return t;
  }

  void addCustomCategory(CustomCategory c) {
    _customCategories.add(c);
    _persist();
  }

  void updateCustomCategory() => _persist(); // caller mutated in place

  void deleteCustomCategory(CustomCategory c) {
    for (final t in _transactions) {
      if (t.customCategoryId == c.id) t.customCategoryId = null;
    }
    _customCategories.removeWhere((e) => e.id == c.id);
    _persist();
  }

  void setBudget(TransactionCategory category, double limit) {
    final existing = _budgets
        .where((b) => b.categoryRaw == category.raw)
        .firstOrNull;
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
    Transaction t, {
    bool rollover = false,
  }) {
    if (t.type != TransactionType.expense) return null;
    if (t.customCategoryId != null) return null;
    final budget = _budgets
        .where((b) => b.categoryRaw == t.category.raw)
        .firstOrNull;
    if (budget == null || budget.limit <= 0) return null;

    final limit = rollover
        ? rolledOverLimit(budget.limit, t.date, category: t.category)
        : budget.limit;
    final spent = spentInMonth(t.date, category: t.category);
    if (spent <= limit) return null;
    return (limit: limit, spent: spent, over: spent - limit);
  }

  // ── Debts (lent / borrowed) ───────────────────────────────────────────────
  //
  // Lending money is a real movement — the cash left an account — so that side
  // is an ordinary transaction and balances stay honest. A Debt only records
  // who owes what, which no account balance can express. How much has been
  // paid back is derived from the repayment transactions, never stored.

  void addDebt(Debt d) {
    _debts.add(d);
    _persist();
  }

  void updateDebt() {
    _reconcileAutoSettledDebts();
    _persist();
  } // caller mutated in place

  void deleteDebt(Debt d) {
    // Untag the repayments but keep them: the money really did move.
    for (final t in _transactions) {
      if (t.debtId == d.id) t.debtId = null;
    }
    _debts.removeWhere((e) => e.id == d.id);
    _persist();
  }

  Debt? debtFor(String? id) =>
      id == null ? null : _debts.where((d) => d.id == id).firstOrNull;

  /// Repayments recorded against this debt, newest first.
  List<Transaction> repaymentsOn(Debt d) {
    final list = _transactions.where((t) => t.debtId == d.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double repaidOn(Debt d) => repaymentsOn(d).fold(0.0, (s, t) => s + t.amount);

  /// What's still owed. Settling by hand closes it out regardless of what the
  /// repayments add up to — people forgive the last ten rupees.
  double outstandingOn(Debt d) {
    if (d.isSettled) return 0;
    final left = d.amount - repaidOn(d);
    return left < 0 ? 0 : left;
  }

  /// Records money coming back (they repay me) or going out (I repay them) as
  /// a real transaction against [account], tagged to the debt.
  Transaction repayDebt(Debt d, double amount, String? accountId) {
    final t = Transaction(
      note: d.theyOweMe ? '${d.person} repaid' : 'Repaid ${d.person}',
      amount: amount,
      category: TransactionCategory.other,
      // They pay me back: money comes in. I pay them back: money goes out.
      type: d.theyOweMe ? TransactionType.income : TransactionType.expense,
      accountId: accountId,
      debtId: d.id,
    );
    _transactions.add(t);
    // Fully repaid closes it without the user having to also tap "settled".
    if (d.amount - repaidOn(d) <= 0.005) d.autoSettled = true;
    _persist();
    return t;
  }

  void _reconcileAutoSettledDebts() {
    for (final d in _debts) {
      if (d.autoSettled && d.amount - repaidOn(d) > 0.005) {
        d.autoSettled = false;
      }
    }
  }

  /// Total still owed to the user across every open debt.
  double get owedToMe => _debts
      .where((d) => d.theyOweMe && !d.isSettled)
      .fold(0.0, (s, d) => s + outstandingOn(d));

  /// Total the user still owes others.
  double get owedByMe => _debts
      .where((d) => !d.theyOweMe && !d.isSettled)
      .fold(0.0, (s, d) => s + outstandingOn(d));

  // ── Tags ──────────────────────────────────────────────────────────────────

  /// Every tag in use, most-used first — the order a picker should offer them.
  List<String> get allTags {
    final counts = <String, int>{};
    for (final t in _transactions) {
      for (final tag in t.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return list;
  }

  List<Transaction> transactionsWithTag(String tag) {
    final needle = tag.toLowerCase();
    return transactions
        .where((t) => t.tags.any((e) => e.toLowerCase() == needle))
        .toList();
  }

  /// Net spend under a tag — what "how much did Japan actually cost me?"
  /// resolves to. Expenses count up, refunds against the tag count back down.
  double spentOnTag(String tag) {
    var total = 0.0;
    for (final t in transactionsWithTag(tag)) {
      if (t.type == TransactionType.expense) {
        total += t.amount;
      } else if (t.type == TransactionType.income) {
        total -= t.amount;
      }
    }
    return total;
  }

  /// Renames a tag everywhere it appears, collapsing duplicates if the new
  /// name already exists on a transaction.
  void renameTag(String from, String to) {
    final target = to.trim();
    if (target.isEmpty) return;
    final needle = from.toLowerCase();
    for (final t in _transactions) {
      if (!t.tags.any((e) => e.toLowerCase() == needle)) continue;
      t.tags.removeWhere((e) => e.toLowerCase() == needle);
      if (!t.tags.any((e) => e.toLowerCase() == target.toLowerCase())) {
        t.tags.add(target);
      }
    }
    _persist();
  }

  void deleteTag(String tag) {
    final needle = tag.toLowerCase();
    for (final t in _transactions) {
      t.tags.removeWhere((e) => e.toLowerCase() == needle);
    }
    _persist();
  }

  // ── Splits ────────────────────────────────────────────────────────────────

  /// The rows of a split purchase, oldest first so they read in entry order.
  List<Transaction> splitRows(String groupId) {
    final list = _transactions.where((t) => t.splitGroupId == groupId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  /// Records one purchase spread over several categories as several ordinary
  /// transactions sharing a group id. They are deliberately *not* a special
  /// kind of row: balances, budgets and analytics count them like any other
  /// expense, which is exactly what a split should do.
  List<Transaction> addSplit({
    required List<({double amount, TransactionCategory category, String note})>
    lines,
    required TransactionType type,
    required DateTime date,
    String? accountId,
    List<String> tags = const [],
  }) {
    final groupId = newId();
    final made = <Transaction>[];
    for (final line in lines) {
      if (line.amount <= 0) continue;
      final t = Transaction(
        note: line.note,
        amount: line.amount,
        category: line.category,
        type: type,
        date: date,
        accountId: accountId,
        tags: List<String>.from(tags),
        splitGroupId: groupId,
      );
      _transactions.add(t);
      made.add(t);
    }
    _persist();
    return made;
  }

  /// Deleting any row of a split removes the whole purchase — a half-deleted
  /// receipt is never what someone means.
  void deleteSplit(String groupId) {
    _transactions.removeWhere((t) => t.splitGroupId == groupId);
    _persist();
  }

  /// Manual entry lives or dies on friction, so typing a payee the user has
  /// logged before should finish the rest of the form. Returns the most
  /// recent transaction for each distinct note matching [query] (newest
  /// first) — the caller copies category/account off them. Transfers are
  /// skipped: their notes ("To Emergency Fund") aren't payees.
  List<Transaction> payeeSuggestions(String query, {int limit = 4}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final out = <Transaction>[];
    for (final t in transactions) {
      // getter is newest-first
      if (t.type == TransactionType.transfer) continue;
      final note = t.note.trim();
      if (note.isEmpty) continue;
      final key = note.toLowerCase();
      if (!key.contains(q) || key == q) continue;
      if (seen.add(key)) {
        out.add(t);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Total spent in [month] — across everything, or one built-in category.
  /// Mirrors the scoping the budget screens already use: expenses only, and
  /// custom-category spends only count toward the overall total.
  double spentInMonth(DateTime month, {TransactionCategory? category}) {
    double spent = 0;
    for (final t in _transactions) {
      if (t.type != TransactionType.expense) continue;
      if (t.date.year != month.year || t.date.month != month.month) continue;
      if (category != null &&
          (t.customCategoryId != null || t.category != category)) {
        continue;
      }
      spent += t.amount;
    }
    return spent;
  }

  /// What last month's budget leaves for [month] when rollover is on:
  /// underspend adds to this month, overspend eats into it. Floored so a
  /// blown month can't produce a negative budget (progress math divides by
  /// the limit).
  double rolledOverLimit(
    double baseLimit,
    DateTime month, {
    TransactionCategory? category,
  }) {
    if (baseLimit <= 0) return baseLimit;
    // Nothing logged before this month (a new install, or a fresh ledger)
    // means there's no real last month to carry from — not an empty one
    // worth a doubled budget.
    final start = DateTime(month.year, month.month);
    if (!_transactions.any((t) => t.date.isBefore(start))) return baseLimit;
    final prev = DateTime(month.year, month.month - 1);
    final carried = baseLimit - spentInMonth(prev, category: category);
    final effective = baseLimit + carried;
    return effective < 0 ? 0 : effective;
  }

  /// The monthly limit actually in force for [month]: [baseLimit], adjusted by
  /// last month when [rollover] is on. Every screen, insight, alert and the
  /// widget must use this, or they contradict each other.
  double effectiveMonthlyBudget(
    double baseLimit, {
    required bool rollover,
    DateTime? month,
  }) => rollover
      ? rolledOverLimit(baseLimit, month ?? DateTime.now())
      : baseLimit;

  void addGoal(SavingsGoal g) {
    _goals.add(g);
    _persist();
  }

  void deleteGoal(SavingsGoal g) {
    // Nothing to clean up: the goal only ever claimed part of an account's
    // balance. Dropping it releases the claim and touches no money.
    _goals.removeWhere((e) => e.id == g.id);
    _persist();
  }

  void touchGoals() => _persist();

  double progressForGoal(SavingsGoal g) => g.targetAmount > 0
      ? (g.allocatedAmount / g.targetAmount).clamp(0.0, 1.0)
      : 0.0;

  /// Goals holding their money in [acc], in the order they were created.
  List<SavingsGoal> goalsIn(Account acc) =>
      _goals.where((g) => g.accountId == acc.id).toList();

  double claimedIn(Account acc) {
    var claimed = 0.0;
    for (final g in _goals) {
      if (g.accountId == acc.id) claimed += g.allocatedAmount;
    }
    return claimed;
  }

  /// Money in [acc] that no goal has spoken for. Goes negative only when the
  /// balance has since dropped below what the goals claim — i.e. the user
  /// spent money that was set aside.
  double unallocatedIn(Account acc) => balanceFor(acc) - claimedIn(acc);

  /// The most a goal could add to its claim right now: what its account has
  /// spare, but never more than the goal still needs. A credit card holds
  /// debt, not savings, so it never has anything to set aside.
  double availableToAllocate(SavingsGoal g) {
    final acc = accountFor(g.accountId);
    if (acc == null || acc.type == AccountType.credit) return 0;
    final free = unallocatedIn(acc);
    final needed = g.targetAmount > 0
        ? g.targetAmount - g.allocatedAmount
        : double.infinity;
    final cap = free < needed ? free : needed;
    return cap < 0 ? 0 : cap;
  }

  /// Sets aside [amount] more of the holding account's balance for this goal,
  /// capped at what the account actually has spare — a goal can never claim
  /// money that isn't there. Returns the amount actually applied.
  ///
  /// This moves no money and writes no transaction: the balance was already
  /// in the account, it just now has a name on it.
  double allocateToGoal(SavingsGoal g, double amount) {
    if (amount <= 0 || g.accountId == null) return 0;
    final applied = amount.clamp(0.0, availableToAllocate(g));
    if (applied <= 0) return 0;
    g.allocatedAmount += applied;
    _persist();
    return applied;
  }

  /// Hands [amount] back to the account's unallocated pool (all of it when
  /// [amount] is omitted) — used when a goal is spent or abandoned.
  void releaseFromGoal(SavingsGoal g, [double? amount]) {
    final give = amount ?? g.allocatedAmount;
    g.allocatedAmount = (g.allocatedAmount - give).clamp(0.0, double.infinity);
    _persist();
  }

  /// Accounts whose goals claim more than the account still holds. Happens
  /// when set-aside money gets spent; the fix is to release a goal's claim.
  List<Account> get overAllocatedAccounts =>
      _accounts.where((a) => unallocatedIn(a) < -0.001).toList();

  /// Swaps in a full dataset in one shot — the restore path of backup.dart.
  /// Callers must pass fully-parsed collections; nothing here validates,
  /// so a restore that can fail must fail before calling this.
  void replaceAll({
    required List<Transaction> transactions,
    required List<Account> accounts,
    required List<CustomCategory> customCategories,
    required List<CategoryBudget> budgets,
    required List<SavingsGoal> goals,
    required List<Emi> emis,
    List<Debt> debts = const [],
    List<PendingCapture> pendingCaptures = const [],
    List<String> accountOrder = const [],
  }) {
    _transactions
      ..clear()
      ..addAll(transactions);
    _accounts
      ..clear()
      ..addAll(accounts);
    _customCategories
      ..clear()
      ..addAll(customCategories);
    _budgets
      ..clear()
      ..addAll(budgets);
    _goals
      ..clear()
      ..addAll(goals);
    _emis
      ..clear()
      ..addAll(emis);
    _debts
      ..clear()
      ..addAll(debts);
    _pendingCaptures
      ..clear()
      ..addAll(pendingCaptures);
    _accountOrder = List<String>.from(accountOrder);
    _persist();
  }

  /// Deletes every entity (Profile "reset all data").
  void wipeAll() {
    _transactions.clear();
    _accounts.clear();
    _customCategories.clear();
    _budgets.clear();
    _goals.clear();
    _emis.clear();
    _debts.clear();
    _pendingCaptures.clear();
    _accountOrder = [];
    _persist();
  }

  /// Transactions the most recent [generateRecurring] posted, awaiting a UI
  /// that tells the user about them. Held here because generation runs during
  /// boot, before any screen exists to receive the result.
  List<Transaction> _recurringNotice = [];

  /// Hands over (and clears) the transactions auto-posted on this launch, so
  /// the shell can surface them once. Returns empty if there were none or if
  /// they've already been shown.
  List<Transaction> takeRecurringNotice() {
    final n = _recurringNotice;
    _recurringNotice = [];
    return n;
  }

  /// Generates due recurring transactions (mirrors AppRootView.generateRecurring).
  /// Returns everything it posted, newest last.
  List<Transaction> generateRecurring() {
    final now = DateTime.now();
    final generated = <Transaction>[];
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
        posted.tags = List<String>.from(t.tags);
        _transactions.add(posted);
        generated.add(posted);
        due = t.recurrenceRule.nextDate(due);
      }
      t.nextDueDate = due;
    }
    if (generated.isNotEmpty) {
      _recurringNotice = generated;
      _persist();
    }
    return generated;
  }

  // ── Pending captures (widget / Siri quick logging) ────────────────────────

  // These are not transactions and never touch a balance. They are a holding
  // pen for amounts captured outside the app, waiting for the user to say what
  // they were. Filing one is an ordinary addTransaction plus a delete here, so
  // the ledger keeps its single authority over balances.

  /// Unreviewed captures, oldest first — the order the user logged them, which
  /// is the order they'll remember them in.
  List<PendingCapture> get pendingCaptures {
    final list = List<PendingCapture>.from(_pendingCaptures);
    list.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return list;
  }

  /// Adds captures drained from the native queue, skipping any id already
  /// held. The native side keeps its entries until we acknowledge them, so a
  /// drain interrupted mid-way replays safely.
  void addPendingCaptures(Iterable<PendingCapture> captures) {
    final known = _pendingCaptures.map((c) => c.id).toSet();
    final fresh = captures.where((c) => !known.contains(c.id)).toList();
    if (fresh.isEmpty) return;
    _pendingCaptures.addAll(fresh);
    _persist();
  }

  void deletePendingCapture(PendingCapture c) {
    _pendingCaptures.removeWhere((e) => e.id == c.id);
    _persist();
  }

  /// Files a capture as a real transaction. The caller supplies the finished
  /// [Transaction] from the review flow; this just commits both sides together
  /// so a capture can never be both filed and still pending.
  void filePendingCapture(PendingCapture c, Transaction t) {
    _transactions.add(t);
    _pendingCaptures.removeWhere((e) => e.id == c.id);
    _persist();
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
    _debts
      ..clear()
      ..addAll(_decode(_kDebts).map(Debt.fromJson));
    _pendingCaptures
      ..clear()
      ..addAll(_decode(_kPendingCaptures).map(PendingCapture.fromJson));
    final rawOrder = _box.get(_kAccountOrder) as String?;
    _accountOrder = rawOrder == null || rawOrder.isEmpty
        ? []
        : (jsonDecode(rawOrder) as List).cast<String>();
  }

  List<Map> _decode(String key) {
    final raw = _box.get(key) as String?;
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map>();
  }

  void _persist() {
    _box.put(
      _kTransactions,
      jsonEncode(_transactions.map((e) => e.toJson()).toList()),
    );
    _box.put(_kAccounts, jsonEncode(_accounts.map((e) => e.toJson()).toList()));
    _box.put(
      _kCustomCategories,
      jsonEncode(_customCategories.map((e) => e.toJson()).toList()),
    );
    _box.put(_kBudgets, jsonEncode(_budgets.map((e) => e.toJson()).toList()));
    _box.put(_kGoals, jsonEncode(_goals.map((e) => e.toJson()).toList()));
    _box.put(_kEmis, jsonEncode(_emis.map((e) => e.toJson()).toList()));
    _box.put(_kDebts, jsonEncode(_debts.map((e) => e.toJson()).toList()));
    _box.put(
      _kPendingCaptures,
      jsonEncode(_pendingCaptures.map((e) => e.toJson()).toList()),
    );
    _box.put(_kAccountOrder, jsonEncode(_accountOrder));
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
