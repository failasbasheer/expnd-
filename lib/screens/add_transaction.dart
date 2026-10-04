import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/apple_intelligence.dart';
import '../services/reminders.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/app_header.dart';
import '../widgets/disclosure_section.dart';
import '../widgets/neopop.dart';
import '../widgets/money_field.dart';

/// One cell of the category grid — exactly one of [builtin]/[custom] is set.
/// A single list of these lets built-in and custom categories be sorted
/// together (by usage, name, recency or a hand-set order) instead of always
/// rendering built-ins first.
typedef _CatEntry = ({TransactionCategory? builtin, CustomCategory? custom});

Future<void> showAddTransaction(
  BuildContext context, {
  Transaction? editing,
  Transaction? duplicating,
  String? initialText,
  PendingCapture? filing,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AddTransactionScreen(
        editing: editing,
        duplicating: duplicating,
        initialText: initialText,
        filing: filing,
      ),
    ),
  );
}

class AddTransactionScreen extends StatefulWidget {
  final Transaction? editing;

  /// Opens pre-filled from an existing transaction but saves a *new* one,
  /// dated today. The same lunch, the same fare, the same weekly shop —
  /// re-typing it every time is the friction that stops people logging.
  final Transaction? duplicating;
  final String? initialText;

  /// Set when this screen is filing an amount captured outside the app (a
  /// widget button, the Lock Screen, Siri). The amount and note are known; the
  /// point of opening the screen is to attach the account and category the
  /// capture couldn't know. Saving commits both sides at once, so a capture is
  /// never both filed and still waiting.
  final PendingCapture? filing;

  const AddTransactionScreen({
    super.key,
    this.editing,
    this.duplicating,
    this.initialText,
    this.filing,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  TransactionType _type = TransactionType.expense;
  TransactionCategory? _category;
  CustomCategory? _customCategory;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isRecurring = false;
  RecurrenceRule _rule = RecurrenceRule.monthly;
  String? _photoPath;
  Account? _account;
  Account? _toAccount;
  String? _banner;
  bool _showAllCategories = false;
  final List<String> _tags = [];
  final _tagCtrl = TextEditingController();
  Timer? _categorySuggestionTimer;
  TransactionCategory? _aiCategorySuggestion;
  CoachSource _aiCategorySource = CoachSource.rules;
  int _categorySuggestionRequest = 0;

  /// Non-empty when this entry is one receipt spread over several categories.
  final List<({double amount, TransactionCategory category, String note})>
  _splitLines = [];

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    final settings = context.read<SettingsStore>();
    final e = widget.editing;
    if (e != null) {
      _type = e.type;
      _amountCtrl.text = e.amount.toStringAsFixed(
        currencyDecimalDigits(settings.currencyCode),
      );
      _noteCtrl.text = e.note;
      _date = e.date;
      _isRecurring = e.isRecurring;
      _rule = e.recurrenceRule;
      _photoPath = e.photoPath;
      _tags.addAll(e.tags);
      _account = store.accountFor(e.accountId);
      _toAccount = store.accountFor(e.toAccountId);
      _customCategory = store.customCategoryFor(e.customCategoryId);
      if (_customCategory == null) _category = e.category;
    } else if (widget.duplicating != null) {
      // Everything except the date, which is the one thing that must be today
      // rather than whenever the original happened.
      final d = widget.duplicating!;
      _type = d.type;
      _amountCtrl.text = d.amount.toStringAsFixed(
        currencyDecimalDigits(settings.currencyCode),
      );
      _noteCtrl.text = d.note;
      _tags.addAll(d.tags);
      _account = store.accountFor(d.accountId);
      _toAccount = store.accountFor(d.toAccountId);
      _customCategory = store.customCategoryFor(d.customCategoryId);
      if (_customCategory == null) _category = d.category;
    } else if (widget.filing != null) {
      // A capture is always an expense: nothing outside the app can log income
      // or a transfer, and both would need a counterparty account anyway.
      final c = widget.filing!;
      _type = TransactionType.expense;
      _amountCtrl.text = c.amount.toStringAsFixed(
        currencyDecimalDigits(settings.currencyCode),
      );
      _noteCtrl.text = c.note;
      // Dated when it was captured, not when it's filed — the tap was the
      // moment the money moved, and filing can happen days later.
      _date = c.capturedAt;
      _account = store.accounts.isNotEmpty ? store.accounts.first : null;
      // Quick Add lets the user pick a category at capture time; carry it
      // through so filing doesn't ask again. Captures from the widget or Siri
      // have no category and leave the grid unselected, as before.
      _customCategory = store.customCategoryFor(c.customCategoryId);
      if (_customCategory == null) _category = c.category;
    } else {
      _type = settings.defaultTransactionType == 'income'
          ? TransactionType.income
          : TransactionType.expense;
      _account = store.accounts.isNotEmpty ? store.accounts.first : null;
      if (widget.initialText != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            if (!_parseText(widget.initialText!)) {
              _showBanner("COULDN'T PARSE AMOUNT");
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _categorySuggestionTimer?.cancel();
    _categorySuggestionRequest++;
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _onNoteChanged(String value) {
    setState(() {});
    _categorySuggestionTimer?.cancel();
    final note = value.trim();
    if (_type == TransactionType.transfer || note.length < 3) {
      if (_aiCategorySuggestion != null) {
        setState(() => _aiCategorySuggestion = null);
      }
      return;
    }
    final requestId = ++_categorySuggestionRequest;
    _categorySuggestionTimer = Timer(
      const Duration(milliseconds: 420),
      () async {
        final allowed = TransactionCategory.categoriesFor(_type);
        final answer = await AppleIntelligence.suggestCategory(
          note,
          allowed.map((c) => c.raw).toList(growable: false),
        );
        if (!mounted || requestId != _categorySuggestionRequest) return;
        final suggestion = answer == null
            ? null
            : allowed.where((c) => c.raw == answer.category).firstOrNull;
        setState(() {
          _aiCategorySuggestion = suggestion;
          if (answer != null) _aiCategorySource = answer.source;
        });
      },
    );
  }

  Widget _aiCategoryChip(ExpndColors oc) {
    final suggestion = _aiCategorySuggestion;
    if (suggestion == null || suggestion == _category) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: true,
        label: _aiCategorySource.isAi
            ? 'AI suggests ${suggestion.raw}'
            : 'Suggested category ${suggestion.raw}',
        hint: 'Applies this category',
        child: GestureDetector(
          onTap: () {
            Haptics.light();
            setState(() {
              _category = suggestion;
              _customCategory = null;
              _aiCategorySuggestion = null;
            });
            _showBanner(
              _aiCategorySource.isAi
                  ? 'AI CATEGORY APPLIED'
                  : 'CATEGORY APPLIED',
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: ExpndColors.gold.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(ExpndRadius.button),
              border: Border.all(
                color: ExpndColors.gold.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sfIcon(_aiCategorySource.icon),
                  size: 12,
                  color: oc.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _aiCategorySource.isAi
                        ? 'AI suggests ${suggestion.raw}'
                        : 'Suggested: ${suggestion.raw}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: oc.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(sfIcon('checkmark'), size: 11, color: oc.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;

  bool get _isValid {
    if (_amount <= 0) return false;
    if (_type == TransactionType.transfer) {
      return _account != null &&
          _toAccount != null &&
          _account!.id != _toAccount!.id;
    }
    // A split carries its own categories, so the single-category rule doesn't
    // apply — but the lines must add up to the receipt total, or the ledger
    // silently gains or loses money.
    if (_splitLines.isNotEmpty) return _splitRemaining.abs() < 0.005;
    return _category != null || _customCategory != null;
  }

  double get _splitAllocated => _splitLines.fold(0.0, (s, l) => s + l.amount);
  double get _splitRemaining => _amount - _splitAllocated;

  String get _symbol =>
      currencySymbol(context.read<SettingsStore>().currencyCode);

  // Over-budget check for the inline warning banner. Returns null unless this
  // is an expense in a built-in category that has a budget and the entered
  // amount would push this-month's spend past the limit. Mirrors the spend
  // rules in plan_view's category-budgets section: expenses only, built-in
  // categories only (CategoryBudget keys on the enum), scoped to the calendar
  // month of the transaction's own date. When editing, the transaction is
  // already in the store, so its original amount is excluded to avoid
  // double-counting.
  ({double spent, double limit, double over})? _budgetWarning(AppStore store) {
    if (_type != TransactionType.expense) return null;
    if (_customCategory != null) return null;
    final cat = _category;
    if (cat == null) return null;
    final budget = store.budgets
        .where((b) => b.categoryRaw == cat.raw)
        .firstOrNull;
    if (budget == null || budget.limit <= 0) return null;

    final amount = _amount;
    if (amount <= 0) return null;

    double spent = 0;
    for (final t in store.transactions) {
      if (t.type == TransactionType.expense &&
          t.customCategoryId == null &&
          t.category == cat &&
          t.date.year == _date.year &&
          t.date.month == _date.month &&
          t.id != widget.editing?.id) {
        spent += t.amount;
      }
    }

    final projected = spent + amount;
    if (projected <= budget.limit) return null;
    return (spent: spent, limit: budget.limit, over: projected - budget.limit);
  }

  void _showBanner(String msg) {
    setState(() => _banner = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  // ── Clipboard scan ──────────────────────────────────────────────────────
  Future<void> _scanClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text ?? '';
    if (text.isEmpty) {
      _showBanner('NOTHING ON CLIPBOARD');
      return;
    }
    if (!_parseText(text)) _showBanner("COULDN'T PARSE AMOUNT");
  }

  bool _parseText(String text) {
    final lower = text.toLowerCase();
    const creditWords = [
      'credit',
      'credited',
      'received',
      'deposited',
      'refund',
      'salary',
      'cashback',
    ];
    final detectedType = creditWords.any(lower.contains)
        ? TransactionType.income
        : TransactionType.expense;
    final patterns = [
      r'(?:rs\.?|inr|usd|\$|€|£|aud|cad|sgd|gbp|eur)\s*([\d,]+(?:\.\d{1,2})?)',
      r'([\d,]+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|usd|\$|€|£)',
    ];
    double? amount;
    for (final p in patterns) {
      if (amount != null) break;
      final m = RegExp(p, caseSensitive: false).firstMatch(text);
      if (m != null && m.groupCount >= 1) {
        amount = double.tryParse(m.group(1)!.replaceAll(',', ''));
      }
    }
    if (amount == null || amount <= 0) return false;
    Haptics.light();
    _openScanConfirm(amount, detectedType);
    return true;
  }

  Future<void> _openScanConfirm(double amount, TransactionType type) async {
    final result =
        await showModalBottomSheet<(TransactionType, TransactionCategory)>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ScanConfirmSheet(
            amount: amount,
            initialType: type,
            symbol: _symbol,
          ),
        );
    if (result != null) {
      setState(() {
        _type = result.$1;
        _category = result.$2;
        _customCategory = null;
        _amountCtrl.text = amount.toStringAsFixed(2);
      });
      _showBanner('FILLED FROM CLIPBOARD');
    }
  }

  // ── Receipt photo ─────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/receipt_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(xfile.path).copy(path);
    if (!mounted) return;
    setState(() => _photoPath = path);
  }

  // ── Save ────────────────────────────────────────────────────────────────
  void _save() {
    if (!_isValid) return;
    final store = context.read<AppStore>();
    final amount = _amount;
    final builtin = _category ?? TransactionCategory.other;
    final e2 = widget.editing;
    FocusScope.of(context).unfocus();

    switch (_type) {
      case TransactionType.income:
        Haptics.success();
        break;
      case TransactionType.expense:
        Haptics.warning();
        break;
      case TransactionType.transfer:
        Haptics.success();
        break;
    }

    // A split is several ordinary transactions sharing a group id, so every
    // balance/budget/chart counts them without knowing splits exist.
    if (e2 == null && _splitLines.isNotEmpty) {
      store.addSplit(
        lines: _splitLines,
        type: _type,
        date: _date,
        accountId: _account?.id,
        tags: List<String>.from(_tags),
      );
      // Splitting a capture across categories is a legitimate way to file it —
      // one tap at the till, several lines on the receipt — so clear it here
      // too, or it would sit in the inbox after already being recorded.
      final splitFiling = widget.filing;
      if (splitFiling != null) store.deletePendingCapture(splitFiling);
      Navigator.of(context).pop();
      return;
    }

    final e = widget.editing;
    if (e != null) {
      e.amount = amount;
      e.category = builtin;
      e.customCategoryId = _customCategory?.id;
      e.type = _type;
      e.date = _date;
      e.note = _noteCtrl.text.trim();
      e.isRecurring = _isRecurring;
      e.recurrenceRule = _rule;
      e.photoPath = _photoPath;
      e.tags = List<String>.from(_tags);
      e.accountId = _account?.id;
      e.toAccountId = _type == TransactionType.transfer ? _toAccount?.id : null;
      if (_isRecurring && e.nextDueDate == null) {
        e.nextDueDate = _rule.nextDate(_date);
      }
      store.updateTransaction();
    } else {
      final t = Transaction(
        note: _noteCtrl.text.trim(),
        amount: amount,
        category: builtin,
        type: _type,
        date: _date,
        isRecurring: _isRecurring,
        recurrenceRule: _rule,
      );
      t.customCategoryId = _customCategory?.id;
      t.photoPath = _photoPath;
      t.tags = List<String>.from(_tags);
      t.accountId = _account?.id;
      t.toAccountId = _type == TransactionType.transfer ? _toAccount?.id : null;
      final filing = widget.filing;
      if (filing != null) {
        store.filePendingCapture(filing, t);
      } else {
        store.addTransaction(t);
      }
    }
    // A new expense can tip the month over budget; refresh the alerts so that
    // crossing is noticed now rather than only on the next launch. Fire and
    // forget — the pop shouldn't wait on the OS scheduler.
    unawaited(Reminders.refreshAll(store, context.read<SettingsStore>()));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final accounts = store.accounts;

    return Scaffold(
      backgroundColor: oc.bg,
      appBar: ExpndPageBar(
        title: _isEditing ? 'Edit transaction' : 'Add transaction',
        actions: [
          HeaderAction(
            icon: 'xmark',
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(context).pop();
            },
            semanticLabel: 'Close transaction',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      _header(oc),
                      const SizedBox(height: 22),
                      _typeSelector(accounts.length >= 2),
                      const SizedBox(height: 22),
                      // Amount is the whole point of this screen — keep it directly
                      // under the type selector so it's the first field in view,
                      // instead of buried below the category grid.
                      _amountSection(oc),
                      _budgetWarningBanner(oc, store),
                      const SizedBox(height: 22),
                      // Smoothly cross-fade + resize between the category grid and the
                      // transfer target section as the type switches. Keying by type
                      // also re-animates the grid when toggling income ↔ expense,
                      // since their category lists differ.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.topCenter,
                                children: [...previousChildren, ?currentChild],
                              ),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, 0.05),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(
                              _type == TransactionType.transfer
                                  ? 'transfer'
                                  : 'cat_${_type.raw}',
                            ),
                            child: _type == TransactionType.transfer
                                ? (accounts.isNotEmpty
                                      ? _toAccountSection(store)
                                      : const SizedBox.shrink())
                                : _splitLines.isNotEmpty
                                ? _splitSection(oc)
                                : _categorySection(store),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _noteAndDate(oc),
                      if (accounts.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _accountSection(store),
                      ],
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: DisclosureSection(
                          title: 'More options',
                          subtitle:
                              'Tags, repeating payments, receipts and splits',
                          initiallyExpanded:
                              _tags.isNotEmpty ||
                              _isRecurring ||
                              _photoPath != null,
                          child: Column(
                            children: [
                              if (_type != TransactionType.transfer &&
                                  !_isEditing) ...[
                                _splitToggle(oc),
                                const SizedBox(height: 22),
                              ],
                              _tagsSection(oc, store),
                              const SizedBox(height: 22),
                              _recurringSection(oc),
                              const SizedBox(height: 22),
                              _photoSection(oc),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Primary action pinned to the bottom so it's reachable without
              // scrolling past every optional field. The Scaffold lifts this
              // footer above the keyboard while the amount field is focused.
              _stickySubmitBar(oc),
            ],
          ),
          if (_banner != null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(child: _bannerPill(_banner!)),
            ),
        ],
      ),
    );
  }

  Widget _header(ExpndColors oc) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _isEditing
                ? 'Update the details below'
                : 'Record income, spending, or a transfer',
            style: TextStyle(fontSize: 12, color: oc.muted),
          ),
        ),
        const SizedBox(width: 12),
        if (!_isEditing) _scanButton(oc),
      ],
    ),
  );

  Widget _scanButton(ExpndColors oc) => GestureDetector(
    onTap: _scanClipboard,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sfIcon('doc.on.clipboard'), size: 11, color: oc.muted),
          const SizedBox(width: 5),
          Text(
            'Paste',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: oc.muted,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _typeSelector(bool showTransfer) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _typeButton(
              TransactionType.income,
              'Income',
              'arrow.up',
              ExpndColors.green,
              ExpndColors.greenDk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _typeButton(
              TransactionType.expense,
              'Expense',
              'arrow.down',
              ExpndColors.red,
              ExpndColors.redDark,
            ),
          ),
          if (showTransfer) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _typeButton(
                TransactionType.transfer,
                'Transfer',
                'arrow.left.arrow.right',
                ExpndColors.gold,
                ExpndColors.goldDark,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeButton(
    TransactionType type,
    String label,
    String icon,
    Color active,
    Color activeDark,
  ) {
    final oc = context.oc;
    final selected = _type == type;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? active.withValues(alpha: 0.14) : oc.surface,
        borderRadius: BorderRadius.circular(ExpndRadius.button),
        border: Border.all(
          color: selected ? active : oc.border,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ExpndRadius.button),
        onTap: () {
          Haptics.light();
          setState(() {
            _type = type;
            _aiCategorySuggestion = null;
            // Split allocations are type-specific. Never carry stale split
            // rows across an income/expense/transfer switch.
            _splitLines.clear();
            final valid = TransactionCategory.categoriesFor(type);
            if (_category != null && !valid.contains(_category)) {
              _category = null;
            }
            if (_customCategory != null &&
                _customCategory!.applicableType != null &&
                _customCategory!.applicableType != type) {
              _customCategory = null;
            }
          });
          _onNoteChanged(_noteCtrl.text);
        },
        child: Padding(
          // The three segments share the width equally, so the longest label
          // ("TRANSFER") plus its icon has to fit a third of the row. The type
          // below is sized so it does — at 12pt TRANSFER overran its segment,
          // and letting the FittedBox absorb that rendered it noticeably
          // smaller than INCOME/EXPENSE, which reads as a mistake across three
          // sibling buttons. The inset guarantees the same breathing room in
          // every segment.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  sfIcon(icon),
                  size: 13,
                  color: selected ? oc.text : oc.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    // Keeps the neoPOP wide tracking; 11pt is the size at
                    // which TRANSFER still clears a third of the row, so
                    // all three labels render unscaled and identical.
                    letterSpacing: 1.4,
                    color: selected ? oc.text : oc.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionBlock(String title, Widget child, {Widget? trailing}) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: oc.muted,
                ),
              ),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  // Keys a category the same way built-ins and customs are keyed in the saved
  // manual order and the usage/recency maps: a built-in by its raw name, a
  // custom by 'custom:<id>'.
  static String _catKey(_CatEntry e) =>
      e.builtin != null ? e.builtin!.raw : 'custom:${e.custom!.id}';

  static String _catName(_CatEntry e) => e.builtin?.raw ?? e.custom!.name;

  Widget _categorySection(AppStore store) {
    final settings = context.watch<SettingsStore>();

    // Usage count and last-used date per category, keyed uniformly so built-in
    // and custom categories rank against each other in one list.
    final counts = <String, int>{};
    final lastUsed = <String, DateTime>{};
    for (final t in store.transactions) {
      final key = t.customCategoryId != null
          ? 'custom:${t.customCategoryId}'
          : t.category.raw;
      counts[key] = (counts[key] ?? 0) + 1;
      final prev = lastUsed[key];
      if (prev == null || t.date.isAfter(prev)) lastUsed[key] = t.date;
    }

    final entries = <_CatEntry>[
      for (final c in TransactionCategory.categoriesFor(_type))
        (builtin: c, custom: null),
      for (final c in store.customCategories.where(
        (c) => c.applicableType == null || c.applicableType == _type,
      ))
        (builtin: null, custom: c),
    ];

    _sortEntries(entries, settings, counts, lastUsed);

    final oc = context.oc;
    final hasCustoms = entries.any((e) => e.custom != null);
    final visibleEntries = _showAllCategories || entries.length <= 6
        ? entries
        : entries.take(6).toList();

    // Editing or filing should always show the current category, even when it
    // isn't among the six most-used choices.
    final selected = entries
        .where(
          (e) => e.builtin != null
              ? e.builtin == _category
              : e.custom?.id == _customCategory?.id,
        )
        .firstOrNull;
    if (selected != null && !visibleEntries.contains(selected)) {
      visibleEntries[visibleEntries.length - 1] = selected;
    }

    return _sectionBlock(
      'CATEGORY',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              for (final e in visibleEntries)
                e.builtin != null
                    ? _categoryButton(e.builtin!)
                    : _customCategoryButton(e.custom!),
              _createCategoryButton(),
            ],
          ),
          if (entries.length > 6)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => _showAllCategories = !_showAllCategories),
              child: Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _showAllCategories
                            ? 'Show fewer categories'
                            : 'Show all categories',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: oc.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showAllCategories
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: oc.accent,
                    ),
                  ],
                ),
              ),
            ),
          // Long-press isn't self-evident, so name the gesture — but only once
          // there's a custom category it actually applies to.
          if (hasCustoms) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(sfIcon('pencil'), size: 10, color: oc.dimmed),
                const SizedBox(width: 6),
                Text(
                  'Long-press a custom category to edit or delete it',
                  style: TextStyle(fontSize: 10, color: oc.dimmed),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: _sortButton(settings),
    );
  }

  void _sortEntries(
    List<_CatEntry> entries,
    SettingsStore settings,
    Map<String, int> counts,
    Map<String, DateTime> lastUsed,
  ) {
    int byUsage(_CatEntry a, _CatEntry b) =>
        (counts[_catKey(b)] ?? 0).compareTo(counts[_catKey(a)] ?? 0);

    switch (settings.categorySortMode) {
      case 'alpha':
        entries.sort(
          (a, b) =>
              _catName(a).toLowerCase().compareTo(_catName(b).toLowerCase()),
        );
        break;
      case 'recent':
        entries.sort((a, b) {
          final da = lastUsed[_catKey(a)];
          final db = lastUsed[_catKey(b)];
          if (da == null && db == null) return byUsage(a, b);
          if (da == null) return 1; // never-used sinks below used
          if (db == null) return -1;
          return db.compareTo(da);
        });
        break;
      case 'manual':
        final order = settings.categoryOrder;
        int rank(_CatEntry e) {
          final i = order.indexOf(_catKey(e));
          return i == -1 ? 1 << 30 : i;
        }
        entries.sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          // Categories created after the order was saved aren't listed — keep
          // them together at the end, most-used first.
          return byRank != 0 ? byRank : byUsage(a, b);
        });
        break;
      case 'usage':
      default:
        entries.sort(byUsage);
    }
  }

  Widget _sortButton(SettingsStore settings) {
    final oc = context.oc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSortSheet(settings),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sfIcon('arrow.up.arrow.down'), size: 10, color: oc.accent),
            const SizedBox(width: 5),
            Text(
              _sortLabel(settings.categorySortMode),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: oc.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(String mode) {
    switch (mode) {
      case 'alpha':
        return 'A–Z';
      case 'recent':
        return 'RECENT';
      case 'manual':
        return 'MANUAL';
      default:
        return 'USAGE';
    }
  }

  Future<void> _openSortSheet(SettingsStore settings) async {
    Haptics.light();
    FocusScope.of(context).unfocus();
    final oc = context.oc;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'SORT CATEGORIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 6),
            for (final opt in const [
              ('usage', 'Most used', 'chart.bar.fill'),
              ('alpha', 'Alphabetical (A–Z)', 'textformat'),
              ('recent', 'Recently used', 'clock'),
              ('manual', 'Manual order', 'line.horizontal.3'),
            ])
              _sortOption(sheetCtx, settings, opt.$1, opt.$2, opt.$3),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    // Picking manual drops straight into the arranger, so it's never a dead end
    // that silently keeps the old order.
    if (choice == 'manual') await _openReorderSheet(settings);
  }

  Widget _sortOption(
    BuildContext sheetCtx,
    SettingsStore settings,
    String value,
    String label,
    String icon,
  ) {
    final oc = context.oc;
    final selected = settings.categorySortMode == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        settings.categorySortMode = value;
        Navigator.of(sheetCtx).pop(value);
      },
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(
              sfIcon(icon),
              size: 15,
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

  Future<void> _openReorderSheet(SettingsStore settings) async {
    final store = context.read<AppStore>();

    final counts = <String, int>{};
    for (final t in store.transactions) {
      final key = t.customCategoryId != null
          ? 'custom:${t.customCategoryId}'
          : t.category.raw;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final items = <_ReorderItem>[
      for (final c in TransactionCategory.categoriesFor(_type))
        _ReorderItem(key: c.raw, name: c.raw, icon: c.icon, color: c.color),
      for (final c in store.customCategories.where(
        (c) => c.applicableType == null || c.applicableType == _type,
      ))
        _ReorderItem(
          key: 'custom:${c.id}',
          name: c.name,
          emoji: c.emoji,
          color: hexColor(c.colorHex),
        ),
    ];

    // Seed the editor with the order that's currently on screen: any saved
    // manual order first, usage as the tiebreaker.
    final order = settings.categoryOrder;
    items.sort((a, b) {
      final ra = order.indexOf(a.key);
      final rb = order.indexOf(b.key);
      final ia = ra == -1 ? 1 << 30 : ra;
      final ib = rb == -1 ? 1 << 30 : rb;
      if (ia != ib) return ia.compareTo(ib);
      return (counts[b.key] ?? 0).compareTo(counts[a.key] ?? 0);
    });

    final newOrder = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReorderCategoriesSheet(items: items),
    );
    if (newOrder == null) return;

    // Only this transaction type's categories are shown here; preserve the
    // saved positions of the other type's keys so arranging expenses never
    // scrambles the income order.
    final shown = items.map((e) => e.key).toSet();
    final preserved = settings.categoryOrder.where((k) => !shown.contains(k));
    settings.categoryOrder = [...newOrder, ...preserved];
    settings.categorySortMode = 'manual';
    Haptics.success();
  }

  Widget _categoryButton(TransactionCategory cat) {
    final oc = context.oc;
    final selected = _category == cat;
    return AnimatedScale(
      scale: selected ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(ExpndRadius.button),
          border: Border.all(
            color: selected ? ExpndColors.goldDark : oc.border,
            width: 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(ExpndRadius.button),
          onTap: () {
            Haptics.light();
            setState(() {
              _category = selected ? null : cat;
              if (!selected) _customCategory = null;
            });
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                sfIcon(cat.icon),
                size: 20,
                color: selected ? ExpndColors.ink : cat.color,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  cat.raw,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: selected ? ExpndColors.ink : oc.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customCategoryButton(CustomCategory c) {
    final oc = context.oc;
    final selected = _customCategory?.id == c.id;
    final color = hexColor(c.colorHex);
    return AnimatedScale(
      scale: selected ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(ExpndRadius.button),
          border: Border.all(
            color: selected
                ? ExpndColors.goldDark
                : color.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(ExpndRadius.button),
          onTap: () {
            Haptics.light();
            setState(() {
              if (selected) {
                _customCategory = null;
              } else {
                _customCategory = c;
                _category = null;
              }
            });
          },
          // Custom categories are the only ones a user can change, so long-press
          // opens their edit/delete sheet. Built-ins are enum-defined and fixed.
          onLongPress: () => _editCustomCategory(c),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(c.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: selected ? ExpndColors.ink : oc.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createCategoryButton() {
    final oc = context.oc;
    return Container(
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(ExpndRadius.button),
        border: Border.all(
          color: ExpndColors.gold.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ExpndRadius.button),
        onTap: () async {
          Haptics.light();
          final result = await showModalBottomSheet<_CategorySheetResult>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CreateCategorySheet(defaultType: _type),
          );
          if (result != null && !result.deleted) {
            setState(() {
              _customCategory = result.category;
              _category = null;
            });
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon('plus.circle'), size: 20, color: oc.accent),
            const SizedBox(height: 6),
            Text(
              'NEW',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: oc.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the edit/delete sheet for a custom category (built-ins can't change).
  Future<void> _editCustomCategory(CustomCategory c) async {
    Haptics.light();
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<_CategorySheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateCategorySheet(defaultType: _type, editing: c),
    );
    if (result == null) return;
    if (!mounted) return;
    // Edits land in place (same object, refreshed via the store), so we only
    // need to react when the category is deleted out from under a selection.
    if (result.deleted && _customCategory?.id == c.id) {
      setState(() => _customCategory = null);
    } else {
      final updated = context.read<AppStore>().customCategoryFor(c.id);
      setState(() {
        if (updated == null ||
            (updated.applicableType != null &&
                updated.applicableType != _type)) {
          _customCategory = null;
        }
      });
    }
  }

  Widget _amountSection(ExpndColors oc) => _sectionBlock(
    'Amount',
    MoneyField(
      controller: _amountCtrl,
      currencyCode: context.read<SettingsStore>().currencyCode,
      label: 'Amount',
      prominent: true,
      onChanged: (_) => setState(() {}),
    ),
  );

  // Live inline warning shown under the amount field when the entered expense
  // would push a budgeted category over its monthly limit. Non-blocking — the
  // user can still save (the money was already spent); it only informs.
  Widget _budgetWarningBanner(ExpndColors oc, AppStore store) {
    final w = _budgetWarning(store);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: w == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: ExpndColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: ExpndColors.red.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      sfIcon('exclamationmark.triangle.fill'),
                      size: 15,
                      color: ExpndColors.red,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OVER BUDGET',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: ExpndColors.red,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$_symbol${_fmtWhole(w.over)} over your '
                            '$_symbol${_fmtWhole(w.limit)} limit '
                            '($_symbol${_fmtWhole(w.spent)} spent this month)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: oc.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // Whole-number money for the budget banner — category budgets are stored as
  // whole amounts (plan_view enters them with toStringAsFixed(0)).
  String _fmtWhole(double v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// One receipt, several categories — a $64 supermarket run that's really
  /// $48 groceries and $16 household. Kept behind a toggle so the common case
  /// (one purchase, one category) doesn't pay for it.
  Widget _splitToggle(ExpndColors oc) {
    final on = _splitLines.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.light();
          setState(() {
            if (on) {
              _splitLines.clear();
            } else {
              // Seed the first line with whatever's already selected, so
              // turning it on never throws away the user's work.
              _splitLines.add((
                amount: _amount,
                category: _category ?? TransactionCategory.other,
                note: _noteCtrl.text.trim(),
              ));
            }
          });
        },
        child: Row(
          children: [
            Icon(
              sfIcon(on ? 'checkmark.circle.fill' : 'plusminus'),
              size: 14,
              color: on ? ExpndColors.gold : oc.muted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                on ? 'Splitting across categories' : 'Split across categories',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? ExpndColors.gold : oc.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _splitSection(ExpndColors oc) {
    final remaining = _splitRemaining;
    final settled = remaining.abs() < 0.005;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPLIT LINES',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
              color: oc.muted,
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < _splitLines.length; i++) ...[
            _splitLineRow(oc, i),
            const SizedBox(height: 8),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.light();
              setState(
                () => _splitLines.add((
                  // Default the new line to whatever is still unallocated,
                  // which is almost always what the user is about to type.
                  amount: remaining > 0 ? remaining : 0,
                  category: TransactionCategory.other,
                  note: '',
                )),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(sfIcon('plus.circle.fill'), size: 16, color: oc.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Add line',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: oc.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: oc.border),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'ALLOCATED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: oc.muted,
                ),
              ),
              const Spacer(),
              Text(
                '$_symbol${_splitAllocated.toStringAsFixed(2)} of '
                '$_symbol${_amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: settled ? ExpndColors.green : oc.text,
                ),
              ),
            ],
          ),
          if (!settled) ...[
            const SizedBox(height: 4),
            Text(
              remaining > 0
                  ? '$_symbol${remaining.toStringAsFixed(2)} still to allocate'
                  : '$_symbol${(-remaining).toStringAsFixed(2)} over the total',
              style: TextStyle(fontSize: 11, color: ExpndColors.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _splitLineRow(ExpndColors oc, int index) {
    final line = _splitLines[index];
    return Row(
      children: [
        // Category
        Expanded(
          child: GestureDetector(
            onTap: () async {
              FocusScope.of(context).unfocus();
              final picked = await _pickSplitCategory(line.category);
              if (picked != null) {
                setState(
                  () => _splitLines[index] = (
                    amount: line.amount,
                    category: picked,
                    note: line.note,
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: oc.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: oc.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(
                    sfIcon(line.category.icon),
                    size: 13,
                    color: line.category.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line.category.raw,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: oc.text),
                    ),
                  ),
                  Icon(sfIcon('chevron.down'), size: 10, color: oc.dimmed),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Amount
        SizedBox(
          width: 96,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: oc.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: oc.border, width: 1.5),
            ),
            child: TextFormField(
              initialValue: line.amount > 0
                  ? line.amount.toStringAsFixed(2)
                  : '',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: amountInputFormatters,
              textAlign: TextAlign.right,
              onChanged: (v) => setState(
                () => _splitLines[index] = (
                  amount: double.tryParse(v) ?? 0,
                  category: line.category,
                  note: line.note,
                ),
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: oc.text,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                prefixText: _symbol,
                prefixStyle: TextStyle(fontSize: 13, color: oc.accent),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ),
        // Removing the last line leaves the split with nothing in it, which is
        // just an ordinary transaction — so it exits split mode.
        GestureDetector(
          onTap: () {
            Haptics.light();
            setState(() => _splitLines.removeAt(index));
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(sfIcon('xmark.circle'), size: 16, color: oc.dimmed),
          ),
        ),
      ],
    );
  }

  Future<TransactionCategory?> _pickSplitCategory(TransactionCategory current) {
    final oc = context.oc;
    return showModalBottomSheet<TransactionCategory>(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in TransactionCategory.categoriesFor(_type))
                GestureDetector(
                  onTap: () => Navigator.of(sheet).pop(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c == current ? ExpndColors.gold : oc.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: c == current ? ExpndColors.goldDark : oc.border,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          sfIcon(c.icon),
                          size: 12,
                          color: c == current ? ExpndColors.ink : c.color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.raw,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: c == current ? ExpndColors.ink : oc.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tags cut across categories — one purchase is Food *and* "Japan trip".
  /// Existing tags are offered first because retyping them by hand is how you
  /// end up with "japan", "Japan" and "Japan Trip" as three different things.
  Widget _tagsSection(ExpndColors oc, AppStore store) {
    void add(String raw) {
      final tag = raw.trim();
      if (tag.isEmpty) return;
      if (_tags.any((e) => e.toLowerCase() == tag.toLowerCase())) return;
      setState(() {
        _tags.add(tag);
        _tagCtrl.clear();
      });
      Haptics.light();
    }

    final suggestions = store.allTags
        .where((t) => !_tags.any((e) => e.toLowerCase() == t.toLowerCase()))
        .take(6)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tags',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
              color: oc.muted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tagCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: add,
            style: TextStyle(fontSize: 13, color: oc.text),
            decoration: InputDecoration(
              hintText: 'add a tag',
              isDense: true,
              filled: true,
              fillColor: oc.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ExpndRadius.button),
                borderSide: BorderSide(color: oc.border, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ExpndRadius.button),
                borderSide: BorderSide(color: oc.accent, width: 1.8),
              ),
              suffixIcon: GestureDetector(
                onTap: () => add(_tagCtrl.text),
                child: Icon(sfIcon('plus'), size: 14, color: oc.accent),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _tags)
                  GestureDetector(
                    onTap: () {
                      Haptics.light();
                      setState(() => _tags.remove(tag));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: ExpndColors.gold,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: ExpndColors.goldDark,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: ExpndColors.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            sfIcon('xmark'),
                            size: 9,
                            color: ExpndColors.ink,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            // A "RECENT" caption + a leading "+" on each chip so these read as
            // tap-to-add suggestions, not tags already on this transaction
            // (those are the gold "×" chips above). Without the cue an outlined
            // chip is ambiguous — applied or offered?
            Text(
              'RECENT',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: oc.dimmed,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in suggestions)
                  GestureDetector(
                    onTap: () => add(tag),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: oc.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: oc.border, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sfIcon('plus'), size: 9, color: oc.accent),
                          const SizedBox(width: 5),
                          Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: oc.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Everything here is typed by hand, so the second time someone logs "Blue
  /// Bottle" the app should already know it's Food on the checking account.
  /// Tapping a suggestion fills the note, category and account from the last
  /// time that payee was logged — the amount is deliberately left alone.
  Widget _payeeSuggestions(ExpndColors oc) {
    // Editing an existing row shouldn't second-guess what's already there.
    if (widget.editing != null) return const SizedBox.shrink();
    final store = context.read<AppStore>();
    final matches = store.payeeSuggestions(_noteCtrl.text);
    if (matches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in matches)
            GestureDetector(
              onTap: () {
                Haptics.light();
                final custom = store.customCategoryFor(t.customCategoryId);
                setState(() {
                  _noteCtrl.text = t.note;
                  _noteCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: t.note.length),
                  );
                  _type = t.type;
                  _category = t.category;
                  _customCategory = custom;
                  final acc = store.accountFor(t.accountId);
                  if (acc != null) _account = acc;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: oc.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: oc.border, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      sfIcon(t.category.icon),
                      size: 11,
                      color: t.category.color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.note,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: oc.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noteAndDate(ExpndColors oc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Note',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  onChanged: _onNoteChanged,
                  style: TextStyle(fontSize: 13, color: oc.text),
                  decoration: InputDecoration(
                    hintText: 'optional note',
                    isDense: true,
                    filled: true,
                    fillColor: oc.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(ExpndRadius.button),
                      ),
                      borderSide: BorderSide(color: oc.border, width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(ExpndRadius.button),
                      ),
                      borderSide: BorderSide(color: oc.accent, width: 1.8),
                    ),
                  ),
                ),
                _payeeSuggestions(oc),
                _aiCategoryChip(oc),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    FocusScope.of(context).unfocus();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: Container(
                    height: 46,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: oc.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: oc.border, width: 1.5),
                    ),
                    child: Text(
                      _shortDate(_date),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: oc.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recurringSection(ExpndColors oc) {
    return _sectionBlock(
      'Recurring',
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Repeat Transaction',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: oc.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Auto-post on a schedule',
                      style: TextStyle(fontSize: 11, color: oc.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isRecurring,
                activeThumbColor: context.oc.accent,
                onChanged: (v) {
                  Haptics.light();
                  setState(() => _isRecurring = v);
                },
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: _isRecurring
                  ? Padding(
                      key: const ValueKey('rules'),
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        children: [
                          for (final rule in RecurrenceRule.values) ...[
                            Expanded(child: _ruleButton(rule)),
                            if (rule != RecurrenceRule.values.last)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleButton(RecurrenceRule rule) {
    final oc = context.oc;
    final selected = _rule == rule;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _rule = rule);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? ExpndColors.goldDark : oc.border,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              sfIcon(rule.icon),
              size: 13,
              color: selected ? ExpndColors.ink : oc.accent,
            ),
            const SizedBox(height: 5),
            Text(
              rule.raw.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: selected ? ExpndColors.ink : oc.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoSection(ExpndColors oc) {
    return _sectionBlock(
      'RECEIPT PHOTO',
      Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: oc.border, width: 1.5),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (_photoPath != null && File(_photoPath!).existsSync())
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_photoPath!),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: GestureDetector(
                      onTap: () {
                        Haptics.light();
                        setState(() => _photoPath = null);
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEE4D37),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          sfIcon('xmark'),
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: oc.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(sfIcon('camera.fill'), size: 20, color: oc.muted),
                      const SizedBox(height: 6),
                      Text(
                        'ADD PHOTO',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: oc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 14),
            if (_photoPath != null)
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: oc.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Text(
                    'CHANGE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: oc.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _accountSection(AppStore store) {
    return _sectionBlock(
      'ACCOUNT',
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _accountChip(
              'None',
              'xmark.circle',
              '888888',
              _account == null,
              () => setState(() => _account = null),
            ),
            for (final acc in store.accounts) ...[
              const SizedBox(width: 10),
              _accountChip(
                acc.name,
                acc.type.icon,
                acc.colorHex,
                _account?.id == acc.id,
                () {
                  Haptics.light();
                  setState(() => _account = acc);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toAccountSection(AppStore store) {
    final options = store.accounts.where((a) => a.id != _account?.id).toList();
    return _sectionBlock(
      'TO ACCOUNT',
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (int i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _accountChip(
                options[i].name,
                options[i].type.icon,
                options[i].colorHex,
                _toAccount?.id == options[i].id,
                () {
                  Haptics.light();
                  setState(() => _toAccount = options[i]);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _accountChip(
    String name,
    String icon,
    String colorHex,
    bool selected,
    VoidCallback onTap,
  ) {
    final oc = context.oc;
    final chipColor = hexColor(colorHex);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? ExpndColors.goldDark : oc.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? ExpndColors.ink.withValues(alpha: 0.15)
                    : chipColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                sfIcon(icon),
                size: 10,
                color: selected ? ExpndColors.ink : chipColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: selected ? ExpndColors.ink : oc.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The submit button pinned to the bottom of the screen. A hairline + page-bg
  /// fill separates it from content scrolling underneath, and [SafeArea] keeps
  /// it clear of the home indicator when the keyboard is down.
  Widget _stickySubmitBar(ExpndColors oc) => DecoratedBox(
    decoration: BoxDecoration(
      color: oc.bg,
      border: Border(top: BorderSide(color: oc.border, width: 1)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isValid) ...[
              Text(
                _validationHint,
                style: TextStyle(fontSize: 12, color: oc.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            _submitButton(),
          ],
        ),
      ),
    ),
  );

  String get _validationHint {
    if (_amount <= 0) return 'Enter an amount greater than zero';
    if (_type == TransactionType.transfer) {
      return 'Choose two different accounts for the transfer';
    }
    if (_splitLines.isNotEmpty) {
      return 'Split amounts must add up to the total';
    }
    return 'Choose a category to save this transaction';
  }

  Widget _submitButton() {
    final oc = context.oc;
    return NeoPopButton(
      onPressed: _save,
      enabled: _isValid,
      faceColor: _isValid ? ExpndColors.gold : oc.surface,
      depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
      depth: 4,
      cornerRadius: 6,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          // Scale the label down rather than overflow it at very large text
          // sizes on a narrow screen — the button is a fixed full-width bar.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  sfIcon(_isEditing ? 'pencil.circle.fill' : 'plus'),
                  size: 14,
                  color: _isValid ? ExpndColors.ink : oc.dimmed,
                ),
                const SizedBox(width: 8),
                Text(
                  _isEditing ? 'Save changes' : 'Add transaction',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: _isValid ? ExpndColors.ink : oc.dimmed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bannerPill(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: ExpndColors.gold,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: ExpndColors.goldDark, width: 1.5),
    ),
    child: Text(
      msg,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
        color: ExpndColors.ink,
      ),
    ),
  );

  String _shortDate(DateTime d) {
    const months = [
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Category sheet
// ─────────────────────────────────────────────────────────────────────────────

/// What the create/edit category sheet returns: the affected category and
/// whether it was deleted (vs created or edited in place).
class _CategorySheetResult {
  final CustomCategory category;
  final bool deleted;
  const _CategorySheetResult(this.category, {this.deleted = false});
}

/// Opens the create/edit custom-category sheet from anywhere (Add Transaction
/// uses it inline; Profile's category manager reuses it). Pass [editing] to
/// edit an existing category — the sheet then offers a delete action. Returns
/// the created/edited category, or null if it was dismissed or deleted.
Future<CustomCategory?> showCustomCategorySheet(
  BuildContext context, {
  CustomCategory? editing,
  TransactionType defaultType = TransactionType.expense,
}) async {
  final result = await showModalBottomSheet<_CategorySheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _CreateCategorySheet(defaultType: defaultType, editing: editing),
  );
  if (result == null || result.deleted) return null;
  return result.category;
}

class _CreateCategorySheet extends StatefulWidget {
  final TransactionType defaultType;

  /// When set, the sheet edits this category in place instead of creating a
  /// new one, and offers a delete action.
  final CustomCategory? editing;
  const _CreateCategorySheet({required this.defaultType, this.editing});

  @override
  State<_CreateCategorySheet> createState() => _CreateCategorySheetState();
}

class _CreateCategorySheetState extends State<_CreateCategorySheet> {
  late final _nameCtrl = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late final _emojiCtrl = TextEditingController(
    text: widget.editing?.emoji ?? '✨',
  );
  late String _typeRaw = widget.editing?.typeRaw ?? widget.defaultType.raw;
  late String _colorHex = widget.editing?.colorHex ?? 'F97316';

  bool get _isEditing => widget.editing != null;

  static const _colors = [
    '22C55E',
    '3B82F6',
    'F97316',
    'EC4899',
    'A855F7',
    '06B6D4',
    'EAB308',
    'EF4444',
    '10B981',
    '6366F1',
    'F59E0B',
    '14B8A6',
  ];

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty && _emojiCtrl.text.isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    // Shrink above the keyboard so fields never hide behind it — the
    // sheet's fixed height otherwise ignores the keyboard entirely.
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9 - insets,
      margin: EdgeInsets.only(bottom: insets),
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: oc.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isEditing ? 'EDIT CATEGORY' : 'NEW CATEGORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: oc.text,
            ),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              children: [
                _preview(oc),
                const SizedBox(height: 20),
                _label('NAME', oc),
                const SizedBox(height: 8),
                _field(_nameCtrl, 'e.g. Coffee, Gym, Side Income', oc),
                const SizedBox(height: 20),
                _label('EMOJI', oc),
                const SizedBox(height: 8),
                _field(
                  _emojiCtrl,
                  'Tap to pick emoji',
                  oc,
                  fontSize: 22,
                  maxLength: 2,
                ),
                const SizedBox(height: 20),
                _label('APPLIES TO', oc),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final opt in [
                      TransactionType.expense.raw,
                      TransactionType.income.raw,
                      'Both',
                    ]) ...[
                      Expanded(child: _typeOption(opt, oc)),
                      if (opt != 'Both') const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                _label('COLOR', oc),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [for (final hex in _colors) _colorDot(hex)],
                ),
                const SizedBox(height: 20),
                _saveButton(oc),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  _deleteButton(oc),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t, ExpndColors oc) => Text(
    t,
    style: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.3,
      color: oc.muted,
    ),
  );

  Widget _preview(ExpndColors oc) {
    final color = hexColor(_colorHex);
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 0,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Text(
                _emojiCtrl.text.isEmpty ? '?' : _emojiCtrl.text,
                style: const TextStyle(fontSize: 26),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nameCtrl.text.isEmpty ? 'Category Name' : _nameCtrl.text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _nameCtrl.text.isEmpty ? oc.dimmed : oc.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _typeRaw.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    ExpndColors oc, {
    double fontSize = 14,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: c,
        maxLength: maxLength,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: fontSize, color: oc.text),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _typeOption(String opt, ExpndColors oc) {
    final active = _typeRaw == opt;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _typeRaw = opt);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? ExpndColors.goldDark : oc.border,
            width: 1.5,
          ),
        ),
        child: Text(
          opt.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: active ? ExpndColors.ink : oc.muted,
          ),
        ),
      ),
    );
  }

  Widget _colorDot(String hex) {
    final selected = _colorHex == hex;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _colorHex = hex);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: hexColor(hex),
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
        ),
        child: AnimatedScale(
          scale: selected ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: Icon(sfIcon('checkmark'), size: 10, color: Colors.white),
        ),
      ),
    );
  }

  Widget _saveButton(ExpndColors oc) {
    return NeoPopButton(
      onPressed: () {
        if (!_isValid) return;
        final store = context.read<AppStore>();
        final emoji = _emojiCtrl.text.isEmpty ? '✨' : _emojiCtrl.text;
        final CustomCategory cat;
        if (_isEditing) {
          // Mutate in place so every transaction already pointing at this
          // category picks up the new name/emoji/colour with no re-linking.
          cat = widget.editing!;
          cat.name = _nameCtrl.text.trim();
          cat.emoji = emoji;
          cat.typeRaw = _typeRaw;
          cat.colorHex = _colorHex;
          store.updateCustomCategory();
        } else {
          cat = CustomCategory(
            name: _nameCtrl.text.trim(),
            emoji: emoji,
            typeRaw: _typeRaw,
            colorHex: _colorHex,
          );
          store.addCustomCategory(cat);
        }
        Haptics.success();
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(_CategorySheetResult(cat));
      },
      enabled: _isValid,
      faceColor: _isValid ? ExpndColors.gold : oc.surface,
      depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
      depth: 4,
      cornerRadius: 6,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                sfIcon(
                  _isEditing ? 'checkmark.circle.fill' : 'plus.circle.fill',
                ),
                size: 14,
                color: _isValid ? ExpndColors.ink : oc.dimmed,
              ),
              const SizedBox(width: 8),
              Text(
                _isEditing ? 'Save changes' : 'CREATE CATEGORY',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: _isValid ? ExpndColors.ink : oc.dimmed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deleteButton(ExpndColors oc) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _confirmDelete,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ExpndColors.red.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: ExpndColors.red.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon('trash'), size: 14, color: ExpndColors.red),
            const SizedBox(width: 8),
            Text(
              'DELETE CATEGORY',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: ExpndColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    final c = widget.editing;
    if (c == null) return;
    Haptics.light();
    final oc = context.oc;
    final store = context.read<AppStore>();
    // Spell out the impact: deleting a category doesn't delete its history —
    // those transactions fall back to "Other" (see deleteCustomCategory).
    final used = store.transactions
        .where((t) => t.customCategoryId == c.id)
        .length;
    showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Delete "${c.name}"?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: oc.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                used == 0
                    ? 'No transactions use it. This cannot be undone.'
                    : '$used transaction${used == 1 ? '' : 's'} will move to '
                          '"Other". This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: oc.muted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    store.deleteCustomCategory(c);
                    Haptics.warning();
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(sheetCtx).pop(); // confirm sheet
                    Navigator.of(
                      context,
                    ).pop(_CategorySheetResult(c, deleted: true)); // edit sheet
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan Confirm sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ScanConfirmSheet extends StatefulWidget {
  final double amount;
  final TransactionType initialType;
  final String symbol;
  const _ScanConfirmSheet({
    required this.amount,
    required this.initialType,
    required this.symbol,
  });

  @override
  State<_ScanConfirmSheet> createState() => _ScanConfirmSheetState();
}

class _ScanConfirmSheetState extends State<_ScanConfirmSheet> {
  late TransactionType _type = widget.initialType;
  TransactionCategory? _category;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final cats = TransactionCategory.categoriesFor(_type);
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: oc.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'CONFIRM TRANSACTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: oc.text,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: oc.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'SCANNED AMOUNT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                          color: oc.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.symbol,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: oc.accent,
                            ),
                          ),
                          Text(
                            widget.amount.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: oc.text,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'TYPE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _typeBtn(
                        TransactionType.income,
                        'INCOME',
                        'arrow.up',
                        ExpndColors.green,
                        ExpndColors.greenDk,
                        oc,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _typeBtn(
                        TransactionType.expense,
                        'EXPENSE',
                        'arrow.down',
                        ExpndColors.red,
                        ExpndColors.redDark,
                        oc,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'SELECT CATEGORY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [for (final c in cats) _catBtn(c, oc)],
                ),
                const SizedBox(height: 20),
                _confirmButton(oc),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeBtn(
    TransactionType type,
    String label,
    String icon,
    Color active,
    Color activeDark,
    ExpndColors oc,
  ) {
    final selected = _type == type;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() {
          _type = type;
          if (_category != null &&
              !TransactionCategory.categoriesFor(type).contains(_category)) {
            _category = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? active : oc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? activeDark : oc.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sfIcon(icon),
              size: 13,
              color: selected ? ExpndColors.ink : oc.muted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: selected ? ExpndColors.ink : oc.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catBtn(TransactionCategory cat, ExpndColors oc) {
    final selected = _category == cat;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _category = selected ? null : cat);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? ExpndColors.goldDark : oc.border,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sfIcon(cat.icon),
              size: 20,
              color: selected ? ExpndColors.ink : cat.color,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                cat.raw,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: selected ? ExpndColors.ink : oc.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmButton(ExpndColors oc) {
    final valid = _category != null;
    return NeoPopButton(
      onPressed: () {
        if (_category == null) return;
        Navigator.of(context).pop((_type, _category!));
      },
      enabled: valid,
      faceColor: valid ? ExpndColors.gold : oc.surface,
      depthColor: valid ? ExpndColors.goldDark : oc.edge,
      depth: 4,
      cornerRadius: 6,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                sfIcon('checkmark.circle.fill'),
                size: 14,
                color: valid ? ExpndColors.ink : oc.dimmed,
              ),
              const SizedBox(width: 8),
              Text(
                'USE THIS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: valid ? ExpndColors.ink : oc.dimmed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reorder categories sheet (manual sort)
// ─────────────────────────────────────────────────────────────────────────────

/// One draggable row in the manual-order editor. [icon] is set for built-ins,
/// [emoji] for custom categories — exactly one of the two.
class _ReorderItem {
  final String key;
  final String name;
  final String? icon;
  final String? emoji;
  final Color color;
  const _ReorderItem({
    required this.key,
    required this.name,
    this.icon,
    this.emoji,
    required this.color,
  });
}

class _ReorderCategoriesSheet extends StatefulWidget {
  final List<_ReorderItem> items;
  const _ReorderCategoriesSheet({required this.items});

  @override
  State<_ReorderCategoriesSheet> createState() =>
      _ReorderCategoriesSheetState();
}

class _ReorderCategoriesSheetState extends State<_ReorderCategoriesSheet> {
  late final List<_ReorderItem> _items = List.of(widget.items);

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: oc.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ARRANGE CATEGORIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Drag to set your own order',
            style: TextStyle(fontSize: 11, color: oc.muted),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _items.length,
              onReorderItem: (oldIndex, newIndex) {
                Haptics.light();
                setState(() {
                  final it = _items.removeAt(oldIndex);
                  _items.insert(newIndex, it);
                });
              },
              itemBuilder: (context, i) => _row(oc, _items[i], i),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: NeoPopButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(_items.map((e) => e.key).toList()),
                enabled: true,
                faceColor: ExpndColors.gold,
                depthColor: ExpndColors.goldDark,
                depth: 4,
                cornerRadius: 6,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sfIcon('checkmark.circle.fill'),
                          size: 14,
                          color: ExpndColors.ink,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SAVE ORDER',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: ExpndColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ExpndColors oc, _ReorderItem it, int index) {
    return Container(
      key: ValueKey(it.key),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Center(
              child: it.emoji != null
                  ? Text(it.emoji!, style: const TextStyle(fontSize: 18))
                  : Icon(sfIcon(it.icon!), size: 18, color: it.color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              it.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: oc.text,
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                sfIcon('line.horizontal.3'),
                size: 16,
                color: oc.dimmed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
