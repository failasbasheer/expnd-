import '../models/models.dart';
import '../store/app_store.dart';
import '../theme/currencies.dart';

class ReconciliationResult {
  final double ledgerBalance;
  final double statementBalance;
  final double difference;
  final List<(Transaction, Transaction)> possibleDuplicates;
  final List<Transaction> recentTransactions;

  const ReconciliationResult({
    required this.ledgerBalance,
    required this.statementBalance,
    required this.difference,
    required this.possibleDuplicates,
    required this.recentTransactions,
  });

  bool balanced(String currencyCode) =>
      toMinorUnits(difference, currencyCode) == 0;
}

/// Compares a bank's displayed balance with transactions posted through a
/// selected date. A mismatch is a prompt to review; it never alters money.
ReconciliationResult reconcileAccount({
  required AppStore store,
  required Account account,
  required double statementBalance,
  required DateTime statementDate,
}) {
  final cutoff = DateTime(
    statementDate.year,
    statementDate.month,
    statementDate.day,
    23,
    59,
    59,
    999,
  );
  final rows = store.transactions
      .where(
        (t) =>
            !t.date.isAfter(cutoff) &&
            (t.accountId == account.id || t.toAccountId == account.id),
      )
      .toList();
  var net = 0.0;
  for (final t in rows) {
    final credit = account.type == AccountType.credit;
    if (t.type == TransactionType.transfer) {
      if (t.accountId == account.id) net += credit ? t.amount : -t.amount;
      if (t.toAccountId == account.id) net += credit ? -t.amount : t.amount;
    } else if (t.accountId == account.id) {
      net += (t.type == TransactionType.income) == !credit
          ? t.amount
          : -t.amount;
    }
  }
  final ledger = account.balance + net;
  final candidates = <(Transaction, Transaction)>[];
  for (var i = 0; i < rows.length; i++) {
    for (var j = i + 1; j < rows.length; j++) {
      final a = rows[i], b = rows[j];
      if (a.type == TransactionType.transfer ||
          b.type == TransactionType.transfer ||
          a.type != b.type ||
          a.accountId != b.accountId ||
          toMinorUnits(a.amount - b.amount, account.currencyCode) != 0 ||
          a.note.trim().toLowerCase() != b.note.trim().toLowerCase() ||
          a.note.trim().isEmpty ||
          a.date.difference(b.date).inDays.abs() > 2) {
        continue;
      }
      candidates.add((a, b));
    }
  }
  return ReconciliationResult(
    ledgerBalance: ledger,
    statementBalance: statementBalance,
    difference: statementBalance - ledger,
    possibleDuplicates: candidates,
    recentTransactions: rows.take(12).toList(),
  );
}
