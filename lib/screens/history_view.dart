import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/animations.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  TransactionType? _typeFilter;
  TransactionCategory? _categoryFilter;
  Account? _accountFilter;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasDateRange => _startDate != null || _endDate != null;

  List<Transaction> _filtered(AppStore store) {
    var result = store.transactions;
    if (_typeFilter != null) {
      result = result.where((t) => t.type == _typeFilter).toList();
    }
    if (_categoryFilter != null) {
      result = result.where((t) => t.category == _categoryFilter).toList();
    }
    if (_startDate != null) {
      final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      result = result.where((t) => !t.date.isBefore(start)).toList();
    }
    if (_endDate != null) {
      final next = DateTime(_endDate!.year, _endDate!.month, _endDate!.day)
          .add(const Duration(days: 1));
      result = result.where((t) => t.date.isBefore(next)).toList();
    }
    if (_accountFilter != null) {
      result = result.where((t) => t.accountId == _accountFilter!.id).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      result = result
          .where((t) =>
              t.note.toLowerCase().contains(q) ||
              t.category.raw.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final accounts = store.accounts;
    final allEmpty = store.transactions.isEmpty;
    final filtered = _filtered(store);

    return Container(
      color: oc.bg,
      child: Column(
        children: [
          FadeSlideIn(child: _titleBar(oc)),
          if (allEmpty)
            Expanded(child: _emptyState(oc))
          else ...[
            FadeSlideIn(
                index: 1, child: _filterArea(oc, store, accounts, filtered.length)),
            Container(height: 1, color: oc.border),
            Expanded(
              child: filtered.isEmpty
                  ? _noResults(oc)
                  : _groupedList(oc, store, filtered, code),
            ),
          ],
        ],
      ),
    );
  }

  Widget _titleBar(ExpndColors oc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(sfIcon('chevron.left'), size: 18, color: oc.text),
              ),
            ),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: ExpndColors.gold, borderRadius: BorderRadius.circular(6)),
            child: Icon(sfIcon('clock.fill'), size: 12, color: ExpndColors.ink),
          ),
          const SizedBox(width: 8),
          Text('HISTORY',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: oc.text)),
        ],
      ),
    );
  }

  Widget _filterArea(ExpndColors oc, AppStore store, List<Account> accounts,
      int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        children: [
          // Search
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: oc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: oc.border, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 16, color: oc.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: TextStyle(fontSize: 13, color: oc.text),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'Search transactions…'),
                  ),
                ),
                if (_search.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                    child: Icon(sfIcon('xmark.circle'), size: 16, color: oc.dimmed),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Type filters + calendar
          Row(
            children: [
              _typeChip(oc, 'ALL', null),
              const SizedBox(width: 8),
              _typeChip(oc, 'INCOME', TransactionType.income),
              const SizedBox(width: 8),
              _typeChip(oc, 'EXPENSE', TransactionType.expense),
              const SizedBox(width: 8),
              _typeChip(oc, 'TRANSFER', TransactionType.transfer),
              const Spacer(),
              GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  width: 34,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _hasDateRange ? ExpndColors.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _hasDateRange ? ExpndColors.goldDark : oc.border,
                        width: 1.5),
                  ),
                  child: Icon(sfIcon('calendar'),
                      size: 12,
                      color: _hasDateRange ? ExpndColors.ink : oc.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Category chips
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _categoryChip(oc, null),
                for (final cat in TransactionCategory.values) ...[
                  const SizedBox(width: 8),
                  _categoryChip(oc, cat),
                ],
              ],
            ),
          ),
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _accountChip(oc, null),
                  for (final acc in accounts) ...[
                    const SizedBox(width: 8),
                    _accountChip(oc, acc),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text('$count ${count == 1 ? 'transaction' : 'transactions'}',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: oc.dimmed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(ExpndColors oc, String label, bool active, VoidCallback onTap,
      {Widget? leading}) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? ExpndColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: active ? ExpndColors.goldDark : oc.border, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 5)],
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: active ? ExpndColors.ink : oc.muted)),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(ExpndColors oc, String label, TransactionType? value) =>
      _chip(oc, label, _typeFilter == value,
          () => setState(() => _typeFilter = value));

  Widget _categoryChip(ExpndColors oc, TransactionCategory? cat) {
    final active = _categoryFilter == cat;
    return _chip(oc, cat?.raw.toUpperCase() ?? 'ALL', active, () {
      Haptics.light();
      setState(() => _categoryFilter = cat);
    },
        leading: cat != null
            ? Icon(sfIcon(cat.icon),
                size: 10, color: active ? ExpndColors.ink : oc.muted)
            : null);
  }

  Widget _accountChip(ExpndColors oc, Account? acc) {
    final active = _accountFilter?.id == acc?.id;
    return _chip(oc, acc?.name ?? 'ALL ACCOUNTS', active, () {
      Haptics.light();
      setState(() => _accountFilter = acc);
    },
        leading: acc != null
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: hexColor(acc.colorHex), shape: BoxShape.circle))
            : null);
  }

  Future<void> _pickDateRange() async {
    Haptics.light();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    } else if (_hasDateRange) {
      // offer a clear via long? Simplest: tapping again with no selection clears
    }
  }

  Widget _groupedList(
      ExpndColors oc, AppStore store, List<Transaction> filtered, String code) {
    // group by day
    final Map<DateTime, List<Transaction>> byDay = {};
    for (final t in filtered) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final txns = byDay[day]!..sort((a, b) => b.date.compareTo(a.date));
        final net = txns
            .where((t) => t.type != TransactionType.transfer)
            .fold(0.0,
                (s, t) => s + (t.type == TransactionType.income ? t.amount : -t.amount));
        final (label, sub) = _dayLabel(day);
        return FadeSlideIn(
          index: i,
          child: Column(
          children: [
            _dayHeader(oc, label, sub, net, txns.length, code),
            for (int j = 0; j < txns.length; j++) ...[
              _historyRow(oc, store, txns[j], code),
              if (j < txns.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 66),
                  child: Container(height: 1, color: oc.border.withValues(alpha: 0.5)),
                ),
            ],
            Container(height: 1, color: oc.border),
          ],
          ),
        );
      },
    );
  }

  Widget _dayHeader(ExpndColors oc, String label, String sub, double net,
      int count, String code) {
    return Container(
      color: oc.bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900, color: oc.text)),
              if (label != sub)
                Text(sub, style: TextStyle(fontSize: 10, color: oc.dimmed)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${net >= 0 ? "+" : ""}${formatCurrency(net, code)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: net >= 0 ? ExpndColors.green : ExpndColors.red)),
              Text('$count item${count == 1 ? "" : "s"}',
                  style: TextStyle(fontSize: 10, color: oc.dimmed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyRow(
      ExpndColors oc, AppStore store, Transaction t, String code) {
    final custom = store.customCategoryFor(t.customCategoryId);
    final toAccount = store.accountFor(t.toAccountId);
    final isTransfer = t.type == TransactionType.transfer;
    final rowColor = isTransfer
        ? ExpndColors.gold
        : custom != null
            ? hexColor(custom.colorHex)
            : t.category.color;

    return Dismissible(
      key: ValueKey('hist_${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: ExpndColors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(sfIcon('trash'), color: Colors.white),
      ),
      onDismissed: (_) => store.deleteTransaction(t),
      child: Container(
        color: oc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rowColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: rowColor.withValues(alpha: 0.25), width: 1),
              ),
              child: isTransfer
                  ? Icon(sfIcon('arrow.left.arrow.right'),
                      size: 15, color: oc.accent)
                  : custom != null
                      ? Text(custom.emoji, style: const TextStyle(fontSize: 19))
                      : Icon(sfIcon(t.category.icon),
                          size: 15, color: t.category.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      isTransfer
                          ? 'Transfer → ${toAccount?.name ?? "account"}'
                          : (custom?.name ?? t.category.raw),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: oc.text)),
                  if (t.note.isNotEmpty)
                    Text(t.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: oc.dimmed)),
                  Text(_timeLabel(t.date),
                      style: TextStyle(fontSize: 10, color: oc.dimmed)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    isTransfer
                        ? '→ ${formatCurrency(t.amount, code)}'
                        : '${t.type == TransactionType.income ? "+" : "-"}${formatCurrency(t.amount, code)}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isTransfer
                            ? ExpndColors.gold
                            : t.type == TransactionType.income
                                ? ExpndColors.green
                                : ExpndColors.red)),
                Text(t.type.raw.toUpperCase(),
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: (t.type == TransactionType.income
                                ? ExpndColors.green
                                : ExpndColors.red)
                            .withValues(alpha: 0.7))),
                if (t.photoPath != null && File(t.photoPath!).existsSync())
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(File(t.photoPath!),
                          width: 36, height: 36, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ExpndColors oc) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                  decoration: BoxDecoration(
                      color: ExpndColors.gold.withValues(alpha: 0.1),
                      shape: BoxShape.circle)),
              Icon(sfIcon('clock.fill'), size: 40, color: oc.accent),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('No history yet',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: oc.text)),
        const SizedBox(height: 8),
        Text('Your transactions will\nappear here over time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: oc.muted)),
      ],
    );
  }

  Widget _noResults(ExpndColors oc) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.search, size: 36, color: oc.dimmed),
          const SizedBox(height: 12),
          Text('No results',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: oc.text)),
          const SizedBox(height: 4),
          Text('Try a different search or filter',
              style: TextStyle(fontSize: 13, color: oc.muted)),
        ],
      ),
    );
  }

  (String, String) _dayLabel(DateTime date) {
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final days = t0.difference(date).inDays;
    final sub = _fullDate(date);
    if (days == 0) return ('Today', sub);
    if (days == 1) return ('Yesterday', sub);
    if (days >= 2 && days <= 6) return (_weekday(date), sub);
    return (_monthDay(date), sub);
  }

  String _timeLabel(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const _monthsFull = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  String _fullDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
  String _weekday(DateTime d) => _weekdays[d.weekday - 1];
  String _monthDay(DateTime d) => '${_monthsFull[d.month - 1]} ${d.day}';
}
