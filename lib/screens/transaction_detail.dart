import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';
import 'add_transaction.dart';

// Read-only transaction detail. Tapping a transaction anywhere opens this;
// the pencil enters edit mode (reusing the add/edit screen) and the trash
// deletes after a confirm. Presented as a bottom sheet to match the app's
// other detail interactions.
Future<void> showTransactionDetail(BuildContext context, Transaction t) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TransactionDetailSheet(transaction: t),
  );
}

class _TransactionDetailSheet extends StatelessWidget {
  final Transaction transaction;
  const _TransactionDetailSheet({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    // Watch so the sheet reflects an edit made through the pencil without
    // needing to be reopened.
    final store = context.watch<AppStore>();

    // The transaction may have been deleted while this sheet is open (via the
    // trash action, which pops afterwards). Guard against a stale render.
    final t = store.transactions.where((x) => x.id == transaction.id).firstOrNull;
    if (t == null) return const SizedBox.shrink();

    final custom = store.customCategoryFor(t.customCategoryId);
    final account = store.accountFor(t.accountId);
    final toAccount = store.accountFor(t.toAccountId);
    final isTransfer = t.type == TransactionType.transfer;
    final isIncome = t.type == TransactionType.income;

    final accent = isTransfer
        ? ExpndColors.gold
        : custom != null
            ? hexColor(custom.colorHex)
            : t.category.color;
    final amountColor = isTransfer
        ? ExpndColors.gold
        : isIncome
            ? ExpndColors.green
            : ExpndColors.red;
    final sign = isTransfer ? '→ ' : (isIncome ? '+' : '-');
    final title =
        isTransfer ? 'Transfer' : (custom?.name ?? t.category.raw);

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: oc.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          _header(context, oc, store, t),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              children: [
                _amountCard(oc, accent, amountColor, sign, title, custom, t),
                const SizedBox(height: 20),
                _detailRow(oc, 'TYPE', t.type.raw),
                _detailRow(oc, 'DATE', _longDate(t.date)),
                if (isTransfer) ...[
                  _detailRow(oc, 'FROM', account?.name ?? '—'),
                  _detailRow(oc, 'TO', toAccount?.name ?? '—'),
                ] else
                  _detailRow(oc, 'ACCOUNT', account?.name ?? 'None'),
                if (t.note.isNotEmpty) _detailRow(oc, 'NOTE', t.note),
                if (t.isRecurring)
                  _detailRow(oc, 'REPEATS', t.recurrenceRule.raw),
                if (t.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('TAGS',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: oc.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in t.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: oc.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: oc.border, width: 1),
                          ),
                          child: Text('#$tag',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: oc.text)),
                        ),
                    ],
                  ),
                ],
                // A split row is one line of a bigger purchase; showing the
                // whole receipt keeps the small number from looking wrong.
                if (t.splitGroupId != null) ...[
                  const SizedBox(height: 8),
                  _splitCard(context, oc, store, t),
                ],
                if (t.photoPath != null && File(t.photoPath!).existsSync()) ...[
                  const SizedBox(height: 8),
                  Text('RECEIPT',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: oc.muted)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(t.photoPath!),
                        width: double.infinity, fit: BoxFit.cover),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(
      BuildContext context, ExpndColors oc, AppStore store, Transaction t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Text('TRANSACTION',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: oc.text)),
          const Spacer(),
          _iconButton(oc, 'pencil', oc.accent, () async {
            Haptics.light();
            Navigator.of(context).pop();
            await showAddTransaction(context, editing: t);
          }),
          const SizedBox(width: 8),
          _iconButton(oc, 'doc.on.doc', oc.accent, () async {
            Haptics.light();
            Navigator.of(context).pop();
            await showAddTransaction(context, duplicating: t);
          }),
          const SizedBox(width: 8),
          _iconButton(oc, 'trash', ExpndColors.red,
              () => _confirmDelete(context, store, t)),
        ],
      ),
    );
  }

  Widget _iconButton(
      ExpndColors oc, String icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Icon(sfIcon(icon), size: 15, color: color),
      ),
    );
  }

  Widget _amountCard(ExpndColors oc, Color accent, Color amountColor,
      String sign, String title, CustomCategory? custom, Transaction t) {
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: accent.withValues(alpha: 0.3), width: 1.5),
              ),
              child: t.type == TransactionType.transfer
                  ? Icon(sfIcon('arrow.left.arrow.right'),
                      size: 20, color: ExpndColors.gold)
                  : custom != null
                      ? Text(custom.emoji, style: const TextStyle(fontSize: 24))
                      : Icon(sfIcon(t.category.icon),
                          size: 20, color: t.category.color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: oc.text)),
                  const SizedBox(height: 4),
                  Builder(builder: (context) {
                    final code = context.read<SettingsStore>().currencyCode;
                    return Text('$sign${formatCurrency(t.amount, code)}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: amountColor));
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The other lines of a split purchase, with the receipt total — so a
  /// $12 "Household" row is visibly part of a $64 grocery run.
  Widget _splitCard(
      BuildContext context, ExpndColors oc, AppStore store, Transaction t) {
    final rows = store.splitRows(t.splitGroupId!);
    if (rows.length < 2) return const SizedBox.shrink();
    final code = context.read<SettingsStore>().currencyCode;
    final total = rows.fold(0.0, (s, e) => s + e.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PART OF A SPLIT',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: oc.muted)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: oc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: oc.border, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(sfIcon(row.category.icon),
                          size: 12, color: row.category.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            row.note.isEmpty ? row.category.raw : row.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: row.id == t.id
                                    ? FontWeight.w900
                                    : FontWeight.w500,
                                color: row.id == t.id ? oc.text : oc.muted)),
                      ),
                      Text(formatCurrency(row.amount, code),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: row.id == t.id
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: row.id == t.id ? oc.text : oc.muted)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Container(height: 1, color: oc.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('RECEIPT TOTAL',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: oc.muted)),
                  const Spacer(),
                  Text(formatCurrency(total, code),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: oc.text)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(ExpndColors oc, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: oc.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: oc.text)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppStore store, Transaction t) {
    Haptics.light();
    final oc = context.oc;
    // Half a receipt is never what someone means, so a split goes as a unit —
    // and the prompt says so rather than surprising them after the fact.
    final splitRows =
        t.splitGroupId == null ? 0 : store.splitRows(t.splitGroupId!).length;
    final isSplit = splitRows > 1;
    showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isSplit
                      ? 'Delete this whole split?'
                      : 'Delete this transaction?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: oc.text)),
              const SizedBox(height: 8),
              Text(
                  isSplit
                      ? 'All $splitRows lines of this purchase are removed. '
                          'This cannot be undone.'
                      : 'This cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: oc.muted)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    if (isSplit) {
                      store.deleteSplit(t.splitGroupId!);
                    } else {
                      store.deleteTransaction(t);
                    }
                    Haptics.warning();
                    Navigator.of(context).pop(); // confirm sheet
                    Navigator.of(context).pop(); // detail sheet
                  },
                  child: Text('Delete',
                      style: TextStyle(
                          color: ExpndColors.red,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _longDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
