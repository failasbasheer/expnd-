import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/receipts.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/glass_header.dart';
import '../widgets/animations.dart';
import '../widgets/app_header.dart';
import '../widgets/neopop.dart';
import '../widgets/filter_totals.dart';
import '../widgets/segmented_picker.dart';
import '../widgets/tag_manager.dart';
import 'add_transaction.dart';
import 'transaction_detail.dart';

class HistoryView extends StatefulWidget {
  /// Opens with the date range already applied, so a summary elsewhere can hand
  /// off to the list showing exactly the transactions it was counting (the
  /// dashboard's TODAY row opens today). The range stays editable — it seeds
  /// the filter rather than locking it.
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  /// Opens already filtered to one account (Wallet's "See all").
  final Account? initialAccount;

  const HistoryView({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    this.initialAccount,
  });

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  /// Height of the glass header the lists scroll under (0 when solid).
  double _listTop = 0;

  final _searchCtrl = TextEditingController();
  String _search = '';
  TransactionType? _typeFilter;
  TransactionCategory? _categoryFilter;
  String? _customCategoryFilter;
  late Account? _accountFilter = widget.initialAccount;
  String? _tagFilter;
  late DateTime? _startDate = widget.initialStartDate;
  late DateTime? _endDate = widget.initialEndDate;

  /// Secondary filters stay behind one button until needed.
  bool _filtersExpanded = false;

  /// Show active filters on the toggle even when their controls are collapsed.
  int get _hiddenFilterCount =>
      (_categoryFilter != null ? 1 : 0) +
      (_customCategoryFilter != null ? 1 : 0) +
      (_accountFilter != null ? 1 : 0) +
      (_tagFilter != null ? 1 : 0);

  /// Multi-select mode: long-press a row to enter it, tap rows to (de)select,
  /// then delete or re-categorise the lot at once.
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasDateRange => _startDate != null || _endDate != null;

  bool get _hasFilters =>
      _search.isNotEmpty ||
      _typeFilter != null ||
      _categoryFilter != null ||
      _customCategoryFilter != null ||
      _accountFilter != null ||
      _tagFilter != null ||
      _hasDateRange;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _typeFilter = null;
      _categoryFilter = null;
      _customCategoryFilter = null;
      _accountFilter = null;
      _tagFilter = null;
      _startDate = null;
      _endDate = null;
    });
  }

  List<Transaction> _filtered(AppStore store) {
    var result = store.transactions;
    if (_typeFilter != null) {
      result = result.where((t) => t.type == _typeFilter).toList();
    }
    if (_categoryFilter != null) {
      result = result.where((t) => t.category == _categoryFilter).toList();
    }
    if (_customCategoryFilter != null) {
      result = result
          .where((t) => t.customCategoryId == _customCategoryFilter)
          .toList();
    }
    if (_startDate != null) {
      final start = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
      );
      result = result.where((t) => !t.date.isBefore(start)).toList();
    }
    if (_endDate != null) {
      final next = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
      ).add(const Duration(days: 1));
      result = result.where((t) => t.date.isBefore(next)).toList();
    }
    if (_accountFilter != null) {
      result = result.where((t) => t.accountId == _accountFilter!.id).toList();
    }
    if (_tagFilter != null) {
      final tag = _tagFilter!.toLowerCase();
      result = result
          .where((t) => t.tags.any((e) => e.toLowerCase() == tag))
          .toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      // Tags are searchable too — typing "japan" should find the trip whether
      // it was tagged or just noted.
      result = result
          .where(
            (t) =>
                t.note.toLowerCase().contains(q) ||
                t.category.raw.toLowerCase().contains(q) ||
                (store
                        .customCategoryFor(t.customCategoryId)
                        ?.name
                        .toLowerCase()
                        .contains(q) ??
                    false) ||
                t.tags.any((e) => e.toLowerCase().contains(q)),
          )
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
    final sortMode = context.watch<SettingsStore>().historySortMode;

    return Container(
      color: oc.bg,
      child: GlassHeaderLayout(
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeSlideIn(child: _titleBar(oc)),
            if (!allEmpty) ...[
              if (_selectMode)
                _selectionBar(oc, store)
              else
                FadeSlideIn(
                  index: 1,
                  child: _filterArea(oc, store, accounts, filtered),
                ),
              if (!ExpndGlass.enabled) Container(height: 1, color: oc.border),
            ],
          ],
        ),
        body: (context, top) {
          _listTop = top;
          return allEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: top),
                  child: _emptyState(oc),
                )
              : filtered.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: top),
                  child: _noResults(oc),
                )
              : (sortMode == 'amountDesc' || sortMode == 'amountAsc')
              ? _flatList(
                  oc,
                  store,
                  filtered,
                  code,
                  descending: sortMode == 'amountDesc',
                )
              : _groupedList(
                  oc,
                  store,
                  filtered,
                  code,
                  descending: sortMode != 'oldest',
                );
        },
      ),
    );
  }

  Widget _titleBar(ExpndColors oc) {
    return ExpndHeader(
      icon: 'clock.fill',
      title: 'History',
      actions: [
        if (context.watch<AppStore>().transactions.isNotEmpty) _sortButton(oc),
        if (Navigator.of(context).canPop())
          HeaderAction(
            icon: 'xmark',
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Close history',
          ),
      ],
    );
  }

  /// A pill on the same 36pt height as the header discs, so it reads as a
  /// control rather than loose text. The label stays: it says the current sort.
  Widget _sortButton(ExpndColors oc) {
    final mode = context.watch<SettingsStore>().historySortMode;
    final label = _sortLabel(mode);
    return Semantics(
      button: true,
      label: 'Sort, currently $label',
      excludeSemantics: true,
      onTap: _openSortSheet,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openSortSheet,
        child: SizedBox(
          height: ExpndHeaderMetrics.action,
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: oc.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: oc.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, size: 16, color: oc.muted),
                  const SizedBox(width: 4),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: oc.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sortLabel(String mode) {
    switch (mode) {
      case 'oldest':
        return 'Oldest';
      case 'amountDesc':
        return 'Amount ↓';
      case 'amountAsc':
        return 'Amount ↑';
      default:
        return 'Newest';
    }
  }

  Future<void> _openSortSheet() async {
    Haptics.light();
    final oc = context.oc;
    final settings = context.read<SettingsStore>();
    await showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'SORT HISTORY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 6),
            for (final opt in const [
              ('newest', 'Newest first', 'arrow.down'),
              ('oldest', 'Oldest first', 'arrow.up'),
              ('amountDesc', 'Amount: high to low', 'arrow.down'),
              ('amountAsc', 'Amount: low to high', 'arrow.up'),
            ])
              _sortOption(sheetCtx, settings, opt.$1, opt.$2, opt.$3),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(
    BuildContext sheetCtx,
    SettingsStore settings,
    String value,
    String label,
    String icon,
  ) {
    final oc = context.oc;
    final selected = settings.historySortMode == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        settings.historySortMode = value;
        Navigator.of(sheetCtx).pop();
      },
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(
              sfIcon(icon),
              size: 14,
              color: selected ? ExpndColors.gold : oc.muted,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                color: selected ? oc.text : oc.muted,
              ),
            ),
            const Spacer(),
            if (selected)
              Icon(sfIcon('checkmark'), size: 13, color: ExpndColors.gold),
          ],
        ),
      ),
    );
  }

  Widget _filterArea(
    ExpndColors oc,
    AppStore store,
    List<Account> accounts,
    List<Transaction> shown,
  ) {
    final count = shown.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (value) => setState(() => _search = value),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 15, color: oc.text),
                  decoration: InputDecoration(
                    hintText: 'Search transactions',
                    filled: true,
                    fillColor: oc.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: oc.muted,
                    ),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: oc.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _squareButton(
                oc,
                icon: 'calendar',
                active: _hasDateRange,
                onTap: _pickDateRange,
                semanticLabel: 'Filter by date range',
              ),
              _squareButton(
                oc,
                icon: _filtersExpanded
                    ? 'chevron.up'
                    : 'line.3.horizontal.decrease',
                active: _hiddenFilterCount > 0,
                badge: _filtersExpanded ? 0 : _hiddenFilterCount,
                onTap: () {
                  Haptics.light();
                  setState(() => _filtersExpanded = !_filtersExpanded);
                },
                semanticLabel: _filtersExpanded
                    ? 'Hide category, account and tag filters'
                    : 'Show category, account and tag filters',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedPicker<TransactionType?>(
            options: const [
              SegmentOption(
                value: null,
                label: 'All',
                semanticLabel: 'All transactions',
              ),
              SegmentOption(value: TransactionType.income, label: 'Income'),
              SegmentOption(value: TransactionType.expense, label: 'Expense'),
              SegmentOption(value: TransactionType.transfer, label: 'Transfer'),
            ],
            selected: _typeFilter,
            onSelected: (value) => setState(() => _typeFilter = value),
          ),
          // Compact selectors keep the transaction list in view.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_filtersExpanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(child: _categoryMenu(oc, store)),
                        const SizedBox(width: 8),
                        Expanded(child: _accountMenu(oc, accounts)),
                        if (store.allTags.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(child: _tagMenu(oc, store.allTags)),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Count plus what the current filters add up to.
              FilterTotals(
                transactions: shown,
                currencyCode: context.watch<SettingsStore>().currencyCode,
                lead: '$count ${count == 1 ? 'transaction' : 'transactions'}',
              ),
              if (_hasFilters)
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear filters'),
                ),
              if (_tagFilter != null)
                Text(
                  '${_tagFilter!} · '
                  '${formatCurrency(store.spentOnTag(_tagFilter!), context.watch<SettingsStore>().currencyCode)}',
                  style: TextStyle(fontSize: 12, color: oc.accent),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The two square controls pinned to the right of the type row. [badge] > 0
  /// paints a gold count in the corner, so filters hidden behind the collapsed
  /// section still announce themselves.
  Widget _squareButton(
    ExpndColors oc, {
    required String icon,
    required bool active,
    required VoidCallback onTap,
    required String semanticLabel,
    int badge = 0,
  }) {
    return Badge(
      isLabelVisible: badge > 0,
      label: Text('$badge'),
      child: IconButton(
        tooltip: semanticLabel,
        onPressed: onTap,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: active ? oc.accent : oc.muted,
          backgroundColor: active
              ? oc.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(sfIcon(icon), size: 21),
      ),
    );
  }

  Widget _filterMenu<T>(
    ExpndColors oc,
    String label,
    List<PopupMenuEntry<T>> items,
    ValueChanged<T> onSelected,
    bool active,
  ) => PopupMenuButton<T>(
    tooltip: 'Filter by $label',
    onSelected: onSelected,
    color: oc.surface,
    itemBuilder: (_) => items,
    child: Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active ? oc.accent.withValues(alpha: 0.12) : oc.surface,
        border: Border.all(color: active ? oc.accent : oc.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? oc.accent : oc.text,
              ),
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: oc.muted),
        ],
      ),
    ),
  );

  Widget _categoryMenu(ExpndColors oc, AppStore store) {
    final selected =
        store.customCategoryFor(_customCategoryFilter)?.name ??
        _categoryFilter?.raw ??
        'Category';
    return _filterMenu<String>(
      oc,
      selected,
      [
        const PopupMenuItem(value: '', child: Text('All categories')),
        for (final cat in TransactionCategory.values)
          PopupMenuItem(value: 'built:${cat.name}', child: Text(cat.raw)),
        for (final cat in store.customCategories)
          PopupMenuItem(value: 'custom:${cat.id}', child: Text(cat.name)),
      ],
      (value) => setState(() {
        _categoryFilter = value.startsWith('built:')
            ? TransactionCategory.values.byName(value.substring(6))
            : null;
        _customCategoryFilter = value.startsWith('custom:')
            ? value.substring(7)
            : null;
      }),
      _categoryFilter != null || _customCategoryFilter != null,
    );
  }

  Widget _accountMenu(ExpndColors oc, List<Account> accounts) =>
      _filterMenu<String>(
        oc,
        _accountFilter?.name ?? 'Account',
        [
          const PopupMenuItem(value: '', child: Text('All accounts')),
          for (final account in accounts)
            PopupMenuItem(value: account.id, child: Text(account.name)),
        ],
        (value) => setState(() {
          _accountFilter = value.isEmpty
              ? null
              : accounts.where((a) => a.id == value).firstOrNull;
        }),
        _accountFilter != null,
      );

  Widget _tagMenu(ExpndColors oc, List<String> tags) => _filterMenu<String>(
    oc,
    _tagFilter == null ? 'Tag' : '#$_tagFilter',
    [
      const PopupMenuItem(value: '', child: Text('All tags')),
      for (final tag in tags) PopupMenuItem(value: tag, child: Text('#$tag')),
      if (_tagFilter != null)
        PopupMenuItem(
          value: 'manage:$_tagFilter',
          child: Text('Manage #$_tagFilter'),
        ),
    ],
    (value) {
      if (value.startsWith('manage:')) {
        _manageTag(value.substring(7));
      } else {
        setState(() => _tagFilter = value.isEmpty ? null : value);
      }
    },
    _tagFilter != null,
  );

  void _manageTag(String tag) {
    showTagManager(
      context,
      tag,
      onRenamed: (newName) {
        if (mounted && _tagFilter?.toLowerCase() == tag.toLowerCase()) {
          setState(() => _tagFilter = newName);
        }
      },
      onDeleted: () {
        if (mounted && _tagFilter?.toLowerCase() == tag.toLowerCase()) {
          setState(() => _tagFilter = null);
        }
      },
    );
  }

  Future<void> _pickDateRange() async {
    Haptics.light();
    final oc = context.oc;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      helpText: 'SELECT RANGE',
      saveText: 'APPLY',
      // Left alone, this is the one screen in the app that looks like stock
      // Material: it inherits the seeded M3 scheme, which turns the gold seed
      // into an olive tonal primary, and pairs it with a plain text "Save".
      // Restate the real palette so the picker belongs to the same app.
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: DatePickerThemeData(
            backgroundColor: oc.bg,
            rangePickerBackgroundColor: oc.bg,
            rangePickerHeaderBackgroundColor: oc.bg,
            rangePickerHeaderForegroundColor: oc.text,
            rangePickerElevation: 0,
            rangePickerShape: const RoundedRectangleBorder(),
            headerBackgroundColor: oc.bg,
            headerForegroundColor: oc.text,
            dividerColor: oc.border,
            weekdayStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: oc.muted,
            ),
            dayForegroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? ExpndColors.ink
                  : s.contains(WidgetState.disabled)
                  ? oc.dimmed
                  : oc.text,
            ),
            dayBackgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? ExpndColors.gold : null,
            ),
            // Today is a reference point, not a selection — mark it with the
            // accent outline and only fill it once it's actually picked.
            todayForegroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? ExpndColors.ink
                  : oc.accent,
            ),
            todayBorder: BorderSide(color: oc.accent, width: 1.5),
            rangeSelectionBackgroundColor: ExpndColors.gold.withValues(
              alpha: 0.22,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: oc.accent,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        child: child!,
      ),
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
    ExpndColors oc,
    AppStore store,
    List<Transaction> filtered,
    String code, {
    bool descending = true,
  }) {
    // group by day
    final Map<DateTime, List<Transaction>> byDay = {};
    for (final t in filtered) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }
    final days = byDay.keys.toList()
      ..sort((a, b) => descending ? b.compareTo(a) : a.compareTo(b));

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: _listTop,
        bottom: ExpndSpacing.scrollBottom,
      ),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final txns = byDay[day]!
          ..sort(
            (a, b) => descending
                ? b.date.compareTo(a.date)
                : a.date.compareTo(b.date),
          );
        final net = txns
            .where((t) => t.type != TransactionType.transfer)
            .fold(
              0.0,
              (s, t) =>
                  s + (t.type == TransactionType.income ? t.amount : -t.amount),
            );
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
                    child: Container(
                      height: 1,
                      color: oc.border.withValues(alpha: 0.5),
                    ),
                  ),
              ],
              Container(height: 1, color: oc.border),
            ],
          ),
        );
      },
    );
  }

  // Amount-ranked view. Day grouping is dropped on purpose — the point of
  // sorting by amount is to see the biggest (or smallest) movements in a row,
  // which day headers would scatter.
  Widget _flatList(
    ExpndColors oc,
    AppStore store,
    List<Transaction> filtered,
    String code, {
    required bool descending,
  }) {
    final sorted = List<Transaction>.from(filtered)
      ..sort(
        (a, b) => descending
            ? b.amount.compareTo(a.amount)
            : a.amount.compareTo(b.amount),
      );
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: _listTop,
        bottom: ExpndSpacing.scrollBottom,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, i) => FadeSlideIn(
        index: i,
        child: Column(
          children: [
            _historyRow(oc, store, sorted[i], code),
            Container(height: 1, color: oc.border.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _dayHeader(
    ExpndColors oc,
    String label,
    String sub,
    double net,
    int count,
    String code,
  ) {
    return Container(
      color: oc.bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: oc.text,
                  ),
                ),
                if (label != sub)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: oc.dimmed),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${net >= 0 ? "+" : ""}${formatCurrency(net, code)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: net >= 0 ? ExpndColors.green : ExpndColors.red,
                ),
              ),
              Text(
                '$count item${count == 1 ? "" : "s"}',
                style: TextStyle(fontSize: 10, color: oc.dimmed),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyRow(
    ExpndColors oc,
    AppStore store,
    Transaction t,
    String code,
  ) {
    final custom = store.customCategoryFor(t.customCategoryId);
    final toAccount = store.accountFor(t.toAccountId);
    final isTransfer = t.type == TransactionType.transfer;
    final rowColor = isTransfer
        ? ExpndColors.gold
        : custom != null
        ? hexColor(custom.colorHex)
        : t.category.color;

    final stackDetails =
        MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(14) > 17;
    final amountDetails = Column(
      crossAxisAlignment: stackDetails
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          isTransfer
              ? '→ ${formatCurrency(t.amount, code)}'
              : '${t.type == TransactionType.income ? "+" : "-"}${formatCurrency(t.amount, code)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isTransfer
                ? ExpndColors.gold
                : t.type == TransactionType.income
                ? ExpndColors.green
                : ExpndColors.red,
          ),
        ),
        Text(
          t.type.raw.toUpperCase(),
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color:
                (t.type == TransactionType.income
                        ? ExpndColors.green
                        : ExpndColors.red)
                    .withValues(alpha: 0.7),
          ),
        ),
        if (Receipts.fileFor(t.photoPath) != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.file(
                Receipts.fileFor(t.photoPath)!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
          ),
      ],
    );
    final selected = _selectedIds.contains(t.id);
    return Dismissible(
      key: ValueKey('hist_${t.id}'),
      // Swipe-to-delete would fight the tap-to-select gesture, so it's off
      // while selecting.
      direction: _selectMode
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        color: ExpndColors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(sfIcon('trash'), color: Colors.white),
      ),
      onDismissed: (_) => store.deleteTransaction(t),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectMode
            ? _toggleSelect(t.id)
            : showTransactionDetail(context, t),
        onLongPress: () => _enterSelect(t.id),
        child: Container(
          color: selected
              ? ExpndColors.gold.withValues(alpha: 0.14)
              : oc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              if (_selectMode) ...[
                Icon(
                  sfIcon(selected ? 'checkmark.circle.fill' : 'circle'),
                  size: 20,
                  color: selected ? ExpndColors.gold : oc.dimmed,
                ),
                const SizedBox(width: 12),
              ],
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rowColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: rowColor.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: isTransfer
                    ? Icon(
                        sfIcon('arrow.left.arrow.right'),
                        size: 15,
                        color: oc.accent,
                      )
                    : custom != null
                    ? Text(custom.emoji, style: const TextStyle(fontSize: 19))
                    : Icon(
                        sfIcon(t.category.icon),
                        size: 15,
                        color: t.category.color,
                      ),
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
                        color: oc.text,
                      ),
                    ),
                    if (t.note.isNotEmpty)
                      Text(
                        t.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: oc.muted,
                        ),
                      ),
                    Text(
                      _timeLabel(t.date),
                      style: TextStyle(fontSize: 10, color: oc.dimmed),
                    ),
                    if (stackDetails) ...[
                      const SizedBox(height: 8),
                      amountDetails,
                    ],
                  ],
                ),
              ),
              if (!stackDetails) ...[const SizedBox(width: 12), amountDetails],
            ],
          ),
        ),
      ),
    );
  }

  // ── Multi-select ──────────────────────────────────────────────────────────
  void _enterSelect(String id) {
    Haptics.medium();
    setState(() {
      _selectMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelect(String id) {
    Haptics.light();
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Widget _selectionBar(ExpndColors oc, AppStore store) {
    final n = _selectedIds.length;
    return Container(
      color: oc.surface,
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _exitSelect,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(sfIcon('xmark'), size: 16, color: oc.text),
            ),
          ),
          Expanded(
            child: Text(
              '$n selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: oc.text,
              ),
            ),
          ),
          _selectAction(
            oc,
            'pencil',
            'Recategorize',
            n > 0 ? () => _recategorizeSelected(store) : null,
          ),
          const SizedBox(width: 6),
          _selectAction(
            oc,
            'trash',
            'Delete',
            n > 0 ? () => _deleteSelected(store) : null,
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _selectAction(
    ExpndColors oc,
    String icon,
    String label,
    VoidCallback? onTap, {
    bool danger = false,
  }) {
    final color = onTap == null
        ? oc.dimmed
        : (danger ? ExpndColors.red : oc.accent);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sfIcon(icon), size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelected(AppStore store) async {
    final ids = Set<String>.from(_selectedIds);
    if (ids.isEmpty) return;
    Haptics.light();
    final oc = context.oc;
    await showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Delete ${ids.length} transaction${ids.length == 1 ? '' : 's'}?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: oc.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: oc.muted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    store.deleteTransactions(ids);
                    Haptics.warning();
                    Navigator.of(sheetCtx).pop();
                    _exitSelect();
                  },
                  child: Text(
                    'Delete',
                    style: TextStyle(
                      color: ExpndColors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recategorizeSelected(AppStore store) async {
    if (_selectedIds.isEmpty) return;
    final picked = await _pickCategorySheet();
    if (picked == null || !mounted) return;
    var changed = 0;
    for (final t in store.transactions) {
      // Transfers don't carry a spending category, so leave them alone.
      if (_selectedIds.contains(t.id) && t.type != TransactionType.transfer) {
        t.category = picked;
        t.customCategoryId = null;
        changed++;
      }
    }
    if (changed > 0) {
      store.updateTransaction();
      Haptics.success();
    }
    _exitSelect();
  }

  Future<TransactionCategory?> _pickCategorySheet() {
    final oc = context.oc;
    return showModalBottomSheet<TransactionCategory>(
      context: context,
      backgroundColor: oc.surface,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MOVE TO CATEGORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: oc.text,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in TransactionCategory.values)
                    GestureDetector(
                      onTap: () => Navigator.of(sheetCtx).pop(c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: oc.bg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: oc.border, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(sfIcon(c.icon), size: 12, color: c.color),
                            const SizedBox(width: 6),
                            Text(
                              c.raw,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: oc.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
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
                  shape: BoxShape.circle,
                ),
              ),
              Icon(sfIcon('clock.fill'), size: 40, color: oc.accent),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No history yet',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: oc.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your transactions will\nappear here over time.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: oc.muted),
        ),
        const SizedBox(height: 24),
        NeoPopButton(
          onPressed: () {
            Haptics.light();
            showAddTransaction(context);
          },
          depth: 4,
          cornerRadius: 4,
          shine: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sfIcon('plus.circle.fill'),
                  size: 14,
                  color: ExpndColors.ink,
                ),
                const SizedBox(width: 8),
                Text(
                  'ADD TRANSACTION',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: ExpndColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _noResults(ExpndColors oc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.search, size: 36, color: oc.dimmed),
          const SizedBox(height: 12),
          Text(
            'No results',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different search or filter',
            style: TextStyle(fontSize: 13, color: oc.muted),
          ),
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
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _monthsFull = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String _fullDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
  String _weekday(DateTime d) => _weekdays[d.weekday - 1];
  String _monthDay(DateTime d) => '${_monthsFull[d.month - 1]} ${d.day}';
}
