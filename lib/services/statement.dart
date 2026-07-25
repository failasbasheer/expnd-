import '../models/models.dart';
import '../store/app_store.dart';
import '../theme/currencies.dart';

/// One month's statement, resolved down to plain numbers and strings so both
/// the text renderer below and the PDF renderer ([buildMonthlyStatementPdf] in
/// `statement_pdf.dart`) can share it without reaching back into the store.
class StatementData {
  final DateTime month;
  final DateTime generatedAt;
  final String? userName;
  final String code;
  final double income;
  final double expenses;
  final int txnCount;

  /// Expense categories, biggest first, each with its share of the month's
  /// spending as a whole percent.
  final List<StatementCategory> categories;

  /// Every account and the balance it holds at generation time.
  final List<StatementAccount> accounts;

  /// Every transaction in the month, in date order, label already resolved.
  final List<StatementLine> lines;

  const StatementData({
    required this.month,
    required this.generatedAt,
    required this.userName,
    required this.code,
    required this.income,
    required this.expenses,
    required this.txnCount,
    required this.categories,
    required this.accounts,
    required this.lines,
  });

  bool get isEmpty => txnCount == 0;
  double get net => income - expenses;
}

class StatementCategory {
  final String name;
  final double amount;
  final int sharePct;
  const StatementCategory(this.name, this.amount, this.sharePct);
}

class StatementAccount {
  final String name;
  final double balance;
  const StatementAccount(this.name, this.balance);
}

class StatementLine {
  final String label;
  final double amount;
  final TransactionType type;
  final DateTime date;
  const StatementLine(this.label, this.amount, this.type, this.date);
}

/// Gathers everything a statement for [month] needs, resolving custom-category
/// names and account balances up front. Pure aside from reading the store.
StatementData buildStatementData(
  AppStore store,
  String code,
  DateTime month, {
  String? userName,
  DateTime? generatedAt,
}) {
  final now = generatedAt ?? DateTime.now();

  final txns = store.transactions
      .where((t) => t.date.year == month.year && t.date.month == month.month)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final income = txns
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (s, t) => s + t.amount);
  final expenses = txns
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (s, t) => s + t.amount);

  final byCategory = <String, double>{};
  for (final t in txns.where((t) => t.type == TransactionType.expense)) {
    final custom = store.customCategoryFor(t.customCategoryId);
    final name = custom?.name ?? t.category.raw;
    byCategory[name] = (byCategory[name] ?? 0) + t.amount;
  }
  final categories = (byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => StatementCategory(
            e.key,
            e.value,
            expenses > 0 ? (e.value / expenses * 100).round() : 0,
          ))
      .toList();

  final accounts = store.accounts
      .map((a) => StatementAccount(a.name, store.balanceFor(a)))
      .toList();

  final lines = txns.map((t) {
    final custom = store.customCategoryFor(t.customCategoryId);
    final label = t.note.trim().isEmpty
        ? (custom?.name ?? t.category.raw)
        : t.note.trim();
    return StatementLine(label, t.amount, t.type, t.date);
  }).toList();

  return StatementData(
    month: month,
    generatedAt: now,
    userName: userName,
    code: code,
    income: income,
    expenses: expenses,
    txnCount: txns.length,
    categories: categories,
    accounts: accounts,
    lines: lines,
  );
}

/// A readable month-end statement, as plain text.
///
/// The CSV export is for feeding a spreadsheet — columns, no totals, no shape.
/// This is for reading: what came in, what went out, where it went, and every
/// line behind those figures. It stays available for anywhere plain text is
/// wanted; the share sheet ships the [buildMonthlyStatementPdf] rendering.
///
/// Amounts are never privacy-masked here — a saved statement must show the real
/// figures regardless of whether the on-screen eye happens to be closed.
String buildMonthlyStatement(
  AppStore store,
  String code,
  DateTime month, {
  String? userName,
  DateTime? generatedAt,
}) {
  final d = buildStatementData(store, code, month,
      userName: userName, generatedAt: generatedAt);
  final b = StringBuffer();

  String money(double v) => formatCurrency(v, code, maskable: false);

  void rule() => b.writeln('-' * 46);

  // ── Header ────────────────────────────────────────────────────────────────
  b.writeln('EXPND STATEMENT');
  b.writeln('${_monthName(month.month)} ${month.year}');
  if (userName != null && userName.trim().isNotEmpty) {
    b.writeln(userName.trim());
  }
  b.writeln('Generated ${_shortDate(d.generatedAt)}');
  b.writeln();

  // ── Summary ───────────────────────────────────────────────────────────────
  rule();
  b.writeln('SUMMARY');
  rule();
  b.writeln(_row('Income', money(d.income)));
  b.writeln(_row('Expenses', money(d.expenses)));
  b.writeln(_row('Net', money(d.net)));
  b.writeln(_row('Transactions', '${d.txnCount}'));
  b.writeln();

  if (d.isEmpty) {
    b.writeln('No transactions recorded this month.');
    return b.toString();
  }

  // ── Where it went ─────────────────────────────────────────────────────────
  if (d.categories.isNotEmpty) {
    rule();
    b.writeln('SPENDING BY CATEGORY');
    rule();
    for (final c in d.categories) {
      b.writeln(_row(
          c.name, '${money(c.amount)}  ${c.sharePct.toString().padLeft(3)}%'));
    }
    b.writeln();
  }

  // ── Accounts ──────────────────────────────────────────────────────────────
  if (d.accounts.isNotEmpty) {
    rule();
    b.writeln('ACCOUNTS AT ${_shortDate(d.generatedAt).toUpperCase()}');
    rule();
    for (final a in d.accounts) {
      b.writeln(_row(a.name, money(a.balance)));
    }
    b.writeln();
  }

  // ── Every line ────────────────────────────────────────────────────────────
  rule();
  b.writeln('TRANSACTIONS');
  rule();
  DateTime? day;
  for (final line in d.lines) {
    final dd = DateTime(line.date.year, line.date.month, line.date.day);
    if (day != dd) {
      if (day != null) b.writeln();
      b.writeln(_shortDate(dd));
      day = dd;
    }
    final sign = switch (line.type) {
      TransactionType.income => '+',
      TransactionType.expense => '-',
      TransactionType.transfer => '>',
    };
    b.writeln(_row('  ${line.label}', '$sign${money(line.amount)}'));
  }

  return b.toString();
}

/// Label left, figure right, padded to a fixed width so the numbers line up
/// in a monospaced viewer.
String _row(String label, String value) {
  const width = 46;
  final l = label.length > width - value.length - 1
      ? '${label.substring(0, width - value.length - 2)}…'
      : label;
  return l + value.padLeft(width - l.length);
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _monthName(int m) => _months[m - 1];

String _shortDate(DateTime d) =>
    '${_months[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';
