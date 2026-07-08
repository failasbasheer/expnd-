import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';

Future<void> showAddTransaction(BuildContext context,
    {Transaction? editing, String? initialText}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        AddTransactionScreen(editing: editing, initialText: initialText),
  ));
}

class AddTransactionScreen extends StatefulWidget {
  final Transaction? editing;
  final String? initialText;
  const AddTransactionScreen({super.key, this.editing, this.initialText});

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

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    final settings = context.read<SettingsStore>();
    final e = widget.editing;
    if (e != null) {
      _type = e.type;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _noteCtrl.text = e.note;
      _date = e.date;
      _isRecurring = e.isRecurring;
      _rule = e.recurrenceRule;
      _photoPath = e.photoPath;
      _account = store.accountFor(e.accountId);
      _toAccount = store.accountFor(e.toAccountId);
      _customCategory = store.customCategoryFor(e.customCategoryId);
      if (_customCategory == null) _category = e.category;
    } else {
      _type = settings.defaultTransactionType == 'income'
          ? TransactionType.income
          : TransactionType.expense;
      _account = store.accounts.isNotEmpty ? store.accounts.first : null;
      if (widget.initialText != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 300), () {
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
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;

  bool get _isValid {
    if (_amount <= 0) return false;
    if (_type == TransactionType.transfer) {
      return _account != null && _toAccount != null && _account!.id != _toAccount!.id;
    }
    return _category != null || _customCategory != null;
  }

  String get _symbol =>
      currencySymbol(context.read<SettingsStore>().currencyCode);

  // Over-budget check for the inline warning banner. Returns null unless this
  // is an expense in a built-in category that has a budget and the entered
  // amount would push this-month's spend past the limit. Mirrors the spend
  // rules in profile_view's category-budgets section: expenses only, built-in
  // categories only (CategoryBudget keys on the enum), scoped to the calendar
  // month of the transaction's own date. When editing, the transaction is
  // already in the store, so its original amount is excluded to avoid
  // double-counting.
  ({double spent, double limit, double over})? _budgetWarning(AppStore store) {
    if (_type != TransactionType.expense) return null;
    if (_customCategory != null) return null;
    final cat = _category;
    if (cat == null) return null;
    final budget =
        store.budgets.where((b) => b.categoryRaw == cat.raw).firstOrNull;
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
      'credit', 'credited', 'received', 'deposited', 'refund', 'salary', 'cashback'
    ];
    final detectedType = creditWords.any(lower.contains)
        ? TransactionType.income
        : TransactionType.expense;
    final patterns = [
      r'(?:rs\.?|inr|usd|\$|€|£|aud|cad|sgd|gbp|eur)\s*([\d,]+(?:\.\d{1,2})?)',
      r'([\d,]+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|usd|\$|€|£)'
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
    final result = await showModalBottomSheet<(TransactionType, TransactionCategory)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScanConfirmSheet(
          amount: amount, initialType: type, symbol: _symbol),
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
    if (xfile == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/receipt_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(xfile.path).copy(path);
    setState(() => _photoPath = path);
  }

  // ── Save ────────────────────────────────────────────────────────────────
  void _save() {
    if (!_isValid) return;
    final store = context.read<AppStore>();
    final amount = _amount;
    final builtin = _category ?? TransactionCategory.other;
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
      t.accountId = _account?.id;
      t.toAccountId = _type == TransactionType.transfer ? _toAccount?.id : null;
      store.addTransaction(t);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final accounts = store.accounts;

    return Scaffold(
      backgroundColor: oc.bg,
      appBar: AppBar(
        backgroundColor: oc.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(sfIcon('xmark'), size: 16, color: oc.muted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 40),
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
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        ?currentChild,
                      ],
                    ),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, 0.05), end: Offset.zero)
                            .animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_type == TransactionType.transfer
                          ? 'transfer'
                          : 'cat_${_type.raw}'),
                      child: _type == TransactionType.transfer
                          ? (accounts.isNotEmpty
                              ? _toAccountSection(store)
                              : const SizedBox.shrink())
                          : _categorySection(store),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _noteAndDate(oc),
                const SizedBox(height: 22),
                _recurringSection(oc),
                const SizedBox(height: 22),
                _photoSection(oc),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _accountSection(store),
                ],
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _submitButton(),
                ),
              ],
            ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isEditing ? 'EDIT TRANSACTION' : 'ADD TRANSACTION',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: oc.text)),
                  const SizedBox(height: 2),
                  Text(
                      _isEditing
                          ? 'update the details below'
                          : 'record your income, expense or transfer',
                      style: TextStyle(fontSize: 11, color: oc.muted)),
                ],
              ),
            ),
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
              Text('SCAN',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: oc.muted)),
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
              child: _typeButton(TransactionType.income, 'INCOME', 'arrow.up',
                  ExpndColors.green, ExpndColors.greenDk)),
          const SizedBox(width: 10),
          Expanded(
              child: _typeButton(TransactionType.expense, 'EXPENSE',
                  'arrow.down', ExpndColors.red, ExpndColors.redDark)),
          if (showTransfer) ...[
            const SizedBox(width: 10),
            Expanded(
                child: _typeButton(TransactionType.transfer, 'TRANSFER',
                    'arrow.left.arrow.right', ExpndColors.gold, ExpndColors.goldDark)),
          ],
        ],
      ),
    );
  }

  Widget _typeButton(TransactionType type, String label, String icon,
      Color active, Color activeDark) {
    final oc = context.oc;
    final selected = _type == type;
    return NeoPopElevated(
      faceColor: selected ? active : oc.surface,
      depthColor: selected ? activeDark : oc.edge,
      borderColor: selected ? activeDark : oc.border,
      depth: 4,
      cornerRadius: 6,
      child: InkWell(
        onTap: () {
          Haptics.light();
          setState(() {
            _type = type;
            final valid = TransactionCategory.categoriesFor(type);
            if (_category != null && !valid.contains(_category)) _category = null;
            if (_customCategory != null &&
                _customCategory!.applicableType != null &&
                _customCategory!.applicableType != type) {
              _customCategory = null;
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(sfIcon(icon),
                  size: 13, color: selected ? ExpndColors.ink : oc.muted),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: selected ? ExpndColors.ink : oc.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBlock(String title, Widget child) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: oc.muted)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _categorySection(AppStore store) {
    final counts = <TransactionCategory, int>{};
    for (final t in store.transactions) {
      if (t.customCategoryId == null) {
        counts[t.category] = (counts[t.category] ?? 0) + 1;
      }
    }
    final builtins = TransactionCategory.categoriesFor(_type)
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

    final customCounts = <String, int>{};
    for (final t in store.transactions) {
      if (t.customCategoryId != null) {
        customCounts[t.customCategoryId!] =
            (customCounts[t.customCategoryId!] ?? 0) + 1;
      }
    }
    final customs = store.customCategories
        .where((c) => c.applicableType == null || c.applicableType == _type)
        .toList()
      ..sort((a, b) =>
          (customCounts[b.id] ?? 0).compareTo(customCounts[a.id] ?? 0));

    return _sectionBlock(
      'CATEGORY',
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
        children: [
          for (final cat in builtins) _categoryButton(cat),
          for (final c in customs) _customCategoryButton(c),
          _createCategoryButton(),
        ],
      ),
    );
  }

  Widget _categoryButton(TransactionCategory cat) {
    final oc = context.oc;
    final selected = _category == cat;
    return AnimatedScale(
      scale: selected ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: NeoPopElevated(
      faceColor: selected ? ExpndColors.gold : oc.surface,
      depthColor: selected ? ExpndColors.goldDark : oc.edge,
      borderColor: selected ? ExpndColors.goldDark : oc.border,
      depth: 3,
      cornerRadius: 6,
      child: InkWell(
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
            Icon(sfIcon(cat.icon),
                size: 20, color: selected ? ExpndColors.ink : cat.color),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(cat.raw,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: selected ? ExpndColors.ink : oc.muted)),
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
      child: NeoPopElevated(
      faceColor: selected ? ExpndColors.gold : oc.surface,
      depthColor: selected ? ExpndColors.goldDark : oc.edge,
      borderColor: selected ? ExpndColors.goldDark : color.withValues(alpha: 0.5),
      depth: 3,
      cornerRadius: 6,
      child: InkWell(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(c.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: selected ? ExpndColors.ink : oc.muted)),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _createCategoryButton() {
    final oc = context.oc;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: ExpndColors.gold.withValues(alpha: 0.5),
      depth: 3,
      cornerRadius: 6,
      child: InkWell(
        onTap: () async {
          Haptics.light();
          final created = await showModalBottomSheet<CustomCategory>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CreateCategorySheet(defaultType: _type),
          );
          if (created != null) {
            setState(() {
              _customCategory = created;
              _category = null;
            });
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon('plus.circle'), size: 20, color: oc.accent),
            const SizedBox(height: 6),
            Text('NEW',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: oc.muted)),
          ],
        ),
      ),
    );
  }

  Widget _amountSection(ExpndColors oc) {
    return _sectionBlock(
      'AMOUNT',
      Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: oc.border, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Text(_symbol,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: oc.accent)),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: amountInputFormatters,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: oc.text),
                decoration: const InputDecoration(
                    border: InputBorder.none, hintText: '0.00'),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: ExpndColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: ExpndColors.red.withValues(alpha: 0.4),
                      width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(sfIcon('exclamationmark.triangle.fill'),
                        size: 15, color: ExpndColors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OVER BUDGET',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  color: ExpndColors.red)),
                          const SizedBox(height: 2),
                          Text(
                              '$_symbol${_fmtWhole(w.over)} over your '
                              '$_symbol${_fmtWhole(w.limit)} limit '
                              '($_symbol${_fmtWhole(w.spent)} spent this month)',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: oc.text)),
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
  // whole amounts (profile_view enters them with toStringAsFixed(0)).
  String _fmtWhole(double v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
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
                Text('NOTE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: oc.muted)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: oc.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _noteCtrl,
                    style: TextStyle(fontSize: 13, color: oc.text),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'optional note',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DATE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: oc.muted)),
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
                    child: Text(_shortDate(_date),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: oc.text)),
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
      'RECURRING',
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Repeat Transaction',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: oc.text)),
                    const SizedBox(height: 2),
                    Text('Auto-post on a schedule',
                        style: TextStyle(fontSize: 11, color: oc.muted)),
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
              color: selected ? ExpndColors.goldDark : oc.border, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(sfIcon(rule.icon),
                size: 13, color: selected ? ExpndColors.ink : oc.accent),
            const SizedBox(height: 5),
            Text(rule.raw.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: selected ? ExpndColors.ink : oc.muted)),
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
                    child: Image.file(File(_photoPath!),
                        width: 80, height: 80, fit: BoxFit.cover),
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
                            color: Color(0xFFEE4D37), shape: BoxShape.circle),
                        child: Icon(sfIcon('xmark'),
                            size: 10, color: Colors.white),
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
                      Text('ADD PHOTO',
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: oc.muted)),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 14),
            if (_photoPath != null)
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: oc.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Text('CHANGE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: oc.muted)),
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
            _accountChip('None', 'xmark.circle', '888888', _account == null,
                () => setState(() => _account = null)),
            for (final acc in store.accounts) ...[
              const SizedBox(width: 10),
              _accountChip(acc.name, acc.type.icon, acc.colorHex,
                  _account?.id == acc.id, () {
                Haptics.light();
                setState(() => _account = acc);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toAccountSection(AppStore store) {
    final options =
        store.accounts.where((a) => a.id != _account?.id).toList();
    return _sectionBlock(
      'TO ACCOUNT',
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (int i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _accountChip(options[i].name, options[i].type.icon,
                  options[i].colorHex, _toAccount?.id == options[i].id, () {
                Haptics.light();
                setState(() => _toAccount = options[i]);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _accountChip(String name, String icon, String colorHex,
      bool selected, VoidCallback onTap) {
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
              color: selected ? ExpndColors.goldDark : oc.border, width: 1.5),
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
                  shape: BoxShape.circle),
              child: Icon(sfIcon(icon),
                  size: 10, color: selected ? ExpndColors.ink : chipColor),
            ),
            const SizedBox(width: 6),
            Text(name,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? ExpndColors.ink : oc.text)),
          ],
        ),
      ),
    );
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
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(sfIcon(_isEditing ? 'pencil.circle.fill' : 'plus'),
                  size: 14, color: _isValid ? ExpndColors.ink : oc.dimmed),
              const SizedBox(width: 8),
              Text(_isEditing ? 'SAVE CHANGES' : 'ADD TRANSACTION',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: _isValid ? ExpndColors.ink : oc.dimmed)),
            ],
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
        child: Text(msg,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: ExpndColors.ink)),
      );

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Category sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CreateCategorySheet extends StatefulWidget {
  final TransactionType defaultType;
  const _CreateCategorySheet({required this.defaultType});

  @override
  State<_CreateCategorySheet> createState() => _CreateCategorySheetState();
}

class _CreateCategorySheetState extends State<_CreateCategorySheet> {
  final _nameCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController(text: '✨');
  late String _typeRaw = widget.defaultType.raw;
  String _colorHex = 'F97316';

  static const _colors = [
    '22C55E', '3B82F6', 'F97316', 'EC4899',
    'A855F7', '06B6D4', 'EAB308', 'EF4444',
    '10B981', '6366F1', 'F59E0B', '14B8A6'
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
                  color: oc.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Text('NEW CATEGORY',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: oc.text)),
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
                _field(_emojiCtrl, 'Tap to pick emoji', oc,
                    fontSize: 22, maxLength: 2),
                const SizedBox(height: 20),
                _label('APPLIES TO', oc),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final opt in [
                      TransactionType.expense.raw,
                      TransactionType.income.raw,
                      'Both'
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
                  children: [
                    for (final hex in _colors) _colorDot(hex),
                  ],
                ),
                const SizedBox(height: 20),
                _saveButton(oc),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t, ExpndColors oc) => Text(t,
      style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          color: oc.muted));

  Widget _preview(ExpndColors oc) {
    final color = hexColor(_colorHex);
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
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
                border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Text(_emojiCtrl.text.isEmpty ? '?' : _emojiCtrl.text,
                  style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_nameCtrl.text.isEmpty ? 'Category Name' : _nameCtrl.text,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _nameCtrl.text.isEmpty ? oc.dimmed : oc.text)),
                  const SizedBox(height: 4),
                  Text(_typeRaw.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, ExpndColors oc,
      {double fontSize = 14, int? maxLength}) {
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
            contentPadding: const EdgeInsets.symmetric(vertical: 14)),
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
              color: active ? ExpndColors.goldDark : oc.border, width: 1.5),
        ),
        child: Text(opt.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: active ? ExpndColors.ink : oc.muted)),
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
        final cat = CustomCategory(
          name: _nameCtrl.text.trim(),
          emoji: _emojiCtrl.text.isEmpty ? '✨' : _emojiCtrl.text,
          typeRaw: _typeRaw,
          colorHex: _colorHex,
        );
        context.read<AppStore>().addCustomCategory(cat);
        Haptics.success();
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(cat);
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
              Icon(sfIcon('plus.circle.fill'),
                  size: 14, color: _isValid ? ExpndColors.ink : oc.dimmed),
              const SizedBox(width: 8),
              Text('CREATE CATEGORY',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: _isValid ? ExpndColors.ink : oc.dimmed)),
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
  const _ScanConfirmSheet(
      {required this.amount, required this.initialType, required this.symbol});

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
                  color: oc.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Text('CONFIRM TRANSACTION',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: oc.text)),
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
                      Text('SCANNED AMOUNT',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: oc.muted)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.symbol,
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: oc.accent)),
                          Text(widget.amount.toStringAsFixed(2),
                              style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: oc.text)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text('TYPE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: oc.muted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _typeBtn(TransactionType.income, 'INCOME',
                            'arrow.up', ExpndColors.green, ExpndColors.greenDk, oc)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _typeBtn(TransactionType.expense, 'EXPENSE',
                            'arrow.down', ExpndColors.red, ExpndColors.redDark, oc)),
                  ],
                ),
                const SizedBox(height: 22),
                Text('SELECT CATEGORY',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: oc.muted)),
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

  Widget _typeBtn(TransactionType type, String label, String icon, Color active,
      Color activeDark, ExpndColors oc) {
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
              color: selected ? activeDark : oc.border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon(icon),
                size: 13, color: selected ? ExpndColors.ink : oc.muted),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: selected ? ExpndColors.ink : oc.muted)),
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
              color: selected ? ExpndColors.goldDark : oc.border, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon(cat.icon),
                size: 20, color: selected ? ExpndColors.ink : cat.color),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(cat.raw,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: selected ? ExpndColors.ink : oc.muted)),
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
              Icon(sfIcon('checkmark.circle.fill'),
                  size: 14, color: valid ? ExpndColors.ink : oc.dimmed),
              const SizedBox(width: 8),
              Text('USE THIS',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: valid ? ExpndColors.ink : oc.dimmed)),
            ],
          ),
        ),
      ),
    );
  }
}
