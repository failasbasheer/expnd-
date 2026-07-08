import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';
import '../widgets/neopop_cards.dart';
import 'account_setup.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _budgetCtrl = TextEditingController();
  bool _editingName = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _budgetCtrl.text = s.monthlyBudget > 0 ? s.monthlyBudget.toStringAsFixed(0) : '';
    _nameCtrl.text = s.userName;
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final code = settings.currencyCode;
    final symbol = currencySymbol(code);

    final txns = store.transactions;
    final totalIncome = txns
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (s, t) => s + t.amount);
    final totalExpenses = txns
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (s, t) => s + t.amount);
    final balance = totalIncome - totalExpenses;
    final goals = store.goals;
    final recurring = txns.where((t) => t.isRecurring).toList();

    return Container(
      color: oc.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text('PROFILE',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: oc.text)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                _avatarCard(oc, settings),
                const SizedBox(height: 20),
                _statsGrid(oc, txns.length, balance, totalIncome, totalExpenses,
                    symbol),
                const SizedBox(height: 20),
                _budgetSection(oc, store, settings, symbol),
                const SizedBox(height: 20),
                _categoryBudgetsSection(oc, store, symbol),
                if (goals.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _goalsSection(oc, store, goals, symbol),
                ],
                if (recurring.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _recurringSection(oc, store, recurring, code),
                ],
                const SizedBox(height: 20),
                _generalSection(oc, store, settings),
                const SizedBox(height: 20),
                _appearanceSection(oc, settings),
                const SizedBox(height: 20),
                _dataSection(oc, store, symbol),
                const SizedBox(height: 20),
                _aboutSection(oc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar ────────────────────────────────────────────────────────────────
  Widget _avatarCard(ExpndColors oc, SettingsStore settings) {
    final initial =
        settings.userName.isNotEmpty ? settings.userName[0].toUpperCase() : '?';
    return NeoPopElevated(
      faceColor: ExpndColors.gold,
      depthColor: ExpndColors.goldDark,
      borderColor: ExpndColors.ink,
      depth: 7,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flat outlined monogram tile — hard ink border, no heavy block.
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExpndColors.ink.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ExpndColors.ink, width: 2),
              ),
              child: Text(initial,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: ExpndColors.ink)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('WELCOME BACK',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: ExpndColors.ink.withValues(alpha: 0.5))),
                  const SizedBox(height: 6),
                  if (_editingName)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          autofocus: true,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: ExpndColors.ink),
                          decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'Your name'),
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (_nameCtrl.text.trim().isNotEmpty) {
                                  settings.userName = _nameCtrl.text.trim();
                                }
                                // Release focus before removing the field,
                                // or iOS leaves the keyboard stuck open.
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() => _editingName = false);
                              },
                              child: Text('Save',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: ExpndColors.ink)),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                _nameCtrl.text = settings.userName;
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() => _editingName = false);
                              },
                              child: Text('Cancel',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: ExpndColors.ink.withValues(alpha: 0.6))),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(settings.userName,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: ExpndColors.ink)),
                        GestureDetector(
                          onTap: () {
                            _nameCtrl.text = settings.userName;
                            setState(() => _editingName = true);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(sfIcon('pencil'),
                                  size: 10, color: ExpndColors.ink.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text('Edit name',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: ExpndColors.ink.withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Widget _statsGrid(ExpndColors oc, int count, double balance,
      double income, double expenses, String symbol) {
    Widget tile(String label, String value, Color color) => Expanded(
          child: NeoPopElevated(
            faceColor: oc.surface,
            depthColor: oc.edge,
            borderColor: color.withValues(alpha: 0.3),
            depth: 4,
            cornerRadius: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: oc.muted)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: color)),
                  ),
                ],
              ),
            ),
          ),
        );

    String money(double v) => '$symbol${_fmt(v.abs())}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // These totals span every month; the dashboard shows the selected
        // month. Label the scope so the two never read as contradictory.
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text('ALL-TIME TOTALS',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: oc.dimmed)),
        ),
        Row(
          children: [
            tile('TRANSACTIONS', '$count', ExpndColors.gold),
            const SizedBox(width: 12),
            tile('BALANCE',
                balance >= 0 ? '+${money(balance)}' : '-${money(balance)}',
                balance >= 0 ? ExpndColors.green : ExpndColors.red),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            tile('TOTAL INCOME', money(income), ExpndColors.green),
            const SizedBox(width: 12),
            tile('TOTAL EXPENSES', money(expenses), ExpndColors.red),
          ],
        ),
      ],
    );
  }

  // ── Section card wrapper ────────────────────────────────────────────────
  Widget _sectionCard(ExpndColors oc, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: oc.muted)),
        ),
        NeoPopElevated(
          faceColor: oc.surface,
          depthColor: oc.edge,
          borderColor: oc.border,
          depth: 4,
          cornerRadius: 6,
          child: child,
        ),
      ],
    );
  }

  Widget _divider(ExpndColors oc) => Padding(
        padding: const EdgeInsets.only(left: 52),
        child: Container(height: 1, color: oc.border),
      );

  // ── Budget ───────────────────────────────────────────────────────────────
  Widget _budgetSection(
      ExpndColors oc, AppStore store, SettingsStore settings, String symbol) {
    final budget = settings.monthlyBudget;
    final now = DateTime.now();
    final monthExpenses = store.transactions
        .where((t) =>
            t.type == TransactionType.expense &&
            t.date.year == now.year &&
            t.date.month == now.month)
        .fold(0.0, (s, t) => s + t.amount);
    final progress = budget > 0 ? (monthExpenses / budget).clamp(0.0, 1.0) : 0.0;
    final color = progress >= 0.9
        ? ExpndColors.red
        : progress >= 0.7
            ? oc.accent
            : ExpndColors.green;

    return _sectionCard(
      oc,
      'BUDGET',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(sfIcon('target'), size: 20, color: oc.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Monthly Budget',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: oc.text)),
                      Text(budget > 0 ? 'Set to $symbol${_fmt(budget)}' : 'Not set',
                          style: TextStyle(fontSize: 11, color: oc.muted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: oc.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(symbol,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: oc.accent)),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _budgetCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          // Cap at 7 digits (max 9,999,999). Larger values
                          // overflow the budget gauge's max label. Digits only
                          // since monthlyBudget is stored whole (toStringAsFixed(0)).
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(7),
                          ],
                          onChanged: (v) =>
                              settings.monthlyBudget = double.tryParse(v) ?? 0,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: oc.text),
                          decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: '0'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (budget > 0) ...[
            _divider(oc),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: NeoPopStatCard(
                progress: progress,
                gaugeText: '${(progress * 100).toInt()}%',
                statusLabel: progress >= 0.9
                    ? 'over budget'
                    : progress >= 0.7
                        ? 'watch spending'
                        : 'on track',
                statusColor: color,
                title:
                    '$symbol${_fmt(monthExpenses)} spent of $symbol${_fmt(budget)}',
                subtitle: 'this month · ${_monthName(now.month)} ${now.year}',
                minLabel: symbol,
                maxLabel: '$symbol${_fmt(budget)}',
                footerText: progress >= 1.0
                    ? 'monthly budget exceeded'
                    : '$symbol${_fmt((budget - monthExpenses).clamp(0, budget))} left this month',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Category budgets ──────────────────────────────────────────────────────
  Widget _categoryBudgetsSection(
      ExpndColors oc, AppStore store, String symbol) {
    final now = DateTime.now();
    // This-month spend per built-in category (custom categories excluded — the
    // CategoryBudget model keys on the built-in enum).
    final Map<TransactionCategory, double> spent = {};
    for (final t in store.transactions) {
      if (t.type == TransactionType.expense &&
          t.customCategoryId == null &&
          t.date.year == now.year &&
          t.date.month == now.month) {
        spent[t.category] = (spent[t.category] ?? 0) + t.amount;
      }
    }
    final budgets = store.budgets
        .where((b) => b.category != null)
        .toList()
      ..sort((a, b) => a.category!.raw.compareTo(b.category!.raw));

    return _sectionCard(
      oc,
      'CATEGORY BUDGETS',
      Column(
        children: [
          if (budgets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(sfIcon('chart.pie.fill'), size: 20, color: oc.dimmed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Set per-category limits to track spending.',
                        style: TextStyle(fontSize: 12, color: oc.muted)),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < budgets.length; i++) ...[
              _categoryBudgetRow(oc, store, budgets[i].category!,
                  budgets[i].limit, spent[budgets[i].category!] ?? 0, symbol),
              if (i < budgets.length - 1) _divider(oc),
            ],
          _divider(oc),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openCategoryBudgetSheet(store),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(sfIcon('plus.circle.fill'),
                      size: 20, color: oc.accent),
                  const SizedBox(width: 12),
                  Text('Add category budget',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: oc.accent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryBudgetRow(ExpndColors oc, AppStore store,
      TransactionCategory cat, double limit, double spent, String symbol) {
    final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final color = progress >= 0.9
        ? ExpndColors.red
        : progress >= 0.7
            ? oc.accent
            : ExpndColors.green;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCategoryBudgetSheet(store, editing: cat, limit: limit),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: cat.color.withValues(alpha: 0.25), width: 1),
              ),
              child: Icon(sfIcon(cat.icon), size: 15, color: cat.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(cat.raw,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: oc.text)),
                      ),
                      Text('$symbol${_fmt(spent)} / $symbol${_fmt(limit)}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: color)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LayoutBuilder(builder: (context, c) {
                      return Stack(
                        children: [
                          Container(height: 4, color: oc.border),
                          Container(
                              height: 4,
                              width: (c.maxWidth * progress).clamp(0.0, c.maxWidth),
                              color: color),
                        ],
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
          ],
        ),
      ),
    );
  }

  Future<void> _openCategoryBudgetSheet(AppStore store,
      {TransactionCategory? editing, double limit = 0}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryBudgetSheet(
        store: store,
        editing: editing,
        initialLimit: limit,
        symbol: currencySymbol(context.read<SettingsStore>().currencyCode),
      ),
    );
  }

  // ── Goals ────────────────────────────────────────────────────────────────
  Widget _goalsSection(
      ExpndColors oc, AppStore store, List<SavingsGoal> goals, String symbol) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('SAVINGS GOALS',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: oc.muted)),
        ),
        for (int i = 0; i < goals.length; i++) ...[
          _goalCard(store, goals[i], symbol),
          if (i < goals.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _goalCard(AppStore store, SavingsGoal goal, String symbol) {
    final color = hexColor(goal.colorHex);
    final pct = (goal.progress * 100).toInt();
    return NeoPopBillCard(
      color: color,
      name: goal.name,
      subtitle: 'target $symbol${_fmt(goal.targetAmount)}',
      icon: sfIcon(goal.iconName),
      tagText: '$pct% saved',
      tagColor: Color.alphaBlend(Colors.black.withValues(alpha: 0.30), color),
      amountText:
          '$symbol${_fmt(goal.currentAmount)} of $symbol${_fmt(goal.targetAmount)}',
      ctaLabel: goal.progress >= 1.0 ? 'Completed' : 'Add funds',
      onCta: () {
        Haptics.light();
        _contribute(store, goal, symbol);
      },
      onOptions: () {
        store.deleteGoal(goal);
        Haptics.warning();
      },
    );
  }


  Future<void> _contribute(
      AppStore store, SavingsGoal goal, String symbol) async {
    final ctrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final oc = context.oc;
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: oc.bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ADD CONTRIBUTION',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: oc.text)),
                const SizedBox(height: 16),
                Text('${goal.name} · ${(goal.progress * 100).toInt()}% complete',
                    style: TextStyle(fontSize: 12, color: oc.muted)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: oc.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Text(symbol,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: oc.accent)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: amountInputFormatters,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: oc.text),
                          decoration: const InputDecoration(
                              border: InputBorder.none, hintText: '0.00'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                NeoPopButton(
                  onPressed: () {
                    final amt = double.tryParse(ctrl.text) ?? 0;
                    if (amt <= 0) return;
                    goal.currentAmount =
                        (goal.currentAmount + amt).clamp(0.0, goal.targetAmount);
                    store.touchGoals();
                    Haptics.success();
                    // Detach the keyboard before the sheet pops so it slides
                    // away cleanly on iOS instead of lingering.
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).pop();
                  },
                  depth: 4,
                  cornerRadius: 6,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('ADD CONTRIBUTION',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: ExpndColors.ink)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Recurring ────────────────────────────────────────────────────────────
  Widget _recurringSection(
      ExpndColors oc, AppStore store, List<Transaction> recurring, String code) {
    return _sectionCard(
      oc,
      'RECURRING TRANSACTIONS',
      Column(
        children: [
          for (int i = 0; i < recurring.length; i++) ...[
            Builder(builder: (context) {
              final t = recurring[i];
              final custom = store.customCategoryFor(t.customCategoryId);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.category.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: t.category.color.withValues(alpha: 0.25), width: 1),
                      ),
                      child: custom != null
                          ? Text(custom.emoji, style: const TextStyle(fontSize: 15))
                          : Icon(sfIcon(t.category.icon),
                              size: 13, color: t.category.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(custom?.name ?? t.category.raw,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: oc.text)),
                          Text(t.recurrenceRule.raw.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                  color: oc.accent)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${t.type == TransactionType.income ? "+" : "-"}${formatCurrency(t.amount, code)}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: t.type == TransactionType.income
                                    ? ExpndColors.green
                                    : ExpndColors.red)),
                        if (t.nextDueDate != null)
                          Text('Next: ${_shortDate(t.nextDueDate!)}',
                              style: TextStyle(fontSize: 9, color: oc.dimmed)),
                      ],
                    ),
                  ],
                ),
              );
            }),
            if (i < recurring.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 62),
                child: Container(height: 1, color: oc.border),
              ),
          ],
        ],
      ),
    );
  }

  // ── General ──────────────────────────────────────────────────────────────
  Widget _generalSection(
      ExpndColors oc, AppStore store, SettingsStore settings) {
    // Amounts are stored without FX conversion, so the app-wide currency is
    // fixed once any transaction references it — changing it would relabel
    // existing amounts rather than convert them. Lock it after the first tx.
    final currencyLocked = store.transactions.isNotEmpty;
    return _sectionCard(
      oc,
      'GENERAL',
      Column(
        children: [
          // Currency
          GestureDetector(
            onTap: () async {
              if (currencyLocked) {
                _snack(
                    'Currency is locked — amounts aren\'t converted, so it can\'t change once you have transactions.');
                return;
              }
              final picked =
                  await showCurrencyPicker(context, settings.currencyCode);
              if (picked != null) settings.currencyCode = picked;
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(sfIcon('dollarsign.circle.fill'),
                      size: 20,
                      color: currencyLocked ? oc.dimmed : oc.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Currency',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: oc.text)),
                        Text(
                            currencyLocked
                                ? 'Locked — you have transactions'
                                : supportedCurrencies
                                        .where(
                                            (c) => c.code == settings.currencyCode)
                                        .map((c) => c.name)
                                        .firstOrNull ??
                                    'US Dollar',
                            style: TextStyle(fontSize: 11, color: oc.muted)),
                      ],
                    ),
                  ),
                  Text(settings.currencyCode,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: currencyLocked ? oc.muted : oc.accent)),
                  const SizedBox(width: 6),
                  Icon(sfIcon(currencyLocked ? 'lock.fill' : 'chevron.right'),
                      size: 12, color: oc.dimmed),
                ],
              ),
            ),
          ),
          _divider(oc),
          // Default type
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(sfIcon('arrow.left.arrow.right'),
                    size: 20, color: oc.accent),
                const SizedBox(width: 12),
                Text('Default Type',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: oc.text)),
                const Spacer(),
                _segmented(oc, [
                  ('expense', 'EXPENSE'),
                  ('income', 'INCOME'),
                ], settings.defaultTransactionType, (v) {
                  Haptics.light();
                  settings.defaultTransactionType = v;
                }),
              ],
            ),
          ),
          _divider(oc),
          // Haptics
          _toggleRow(oc, 'hand.raised.fill', 'Haptics',
              'Tactile feedback on actions', settings.hapticsEnabled, (v) {
            settings.hapticsEnabled = v;
            if (v) Haptics.medium();
          }),
          _divider(oc),
          // Biometric app lock — Face ID on iPhone, fingerprint on Android.
          _toggleRow(oc, 'faceid', 'Biometric Lock',
              'Require Face ID / fingerprint to open', settings.biometricLockEnabled,
              (v) {
            Haptics.light();
            settings.biometricLockEnabled = v;
          }),
        ],
      ),
    );
  }

  Widget _toggleRow(ExpndColors oc, String icon, String title, String subtitle,
      bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(sfIcon(icon), size: 20, color: oc.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: oc.text)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: oc.muted)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: oc.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _segmented(ExpndColors oc, List<(String, String)> options,
      String selected, ValueChanged<String> onSelect) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: oc.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (val, label) in options)
            GestureDetector(
              onTap: () => onSelect(val),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected == val ? ExpndColors.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: selected == val ? ExpndColors.ink : oc.muted)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Appearance ───────────────────────────────────────────────────────────
  Widget _appearanceSection(ExpndColors oc, SettingsStore settings) {
    final modes = [
      ('system', 'circle.lefthalf.filled'),
      ('dark', 'moon.fill'),
      ('light', 'sun.max.fill'),
    ];
    return _sectionCard(
      oc,
      'APPEARANCE',
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(sfIcon('paintbrush.fill'), size: 20, color: oc.accent),
            const SizedBox(width: 12),
            Text('Theme',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: oc.text)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: oc.border.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: oc.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (mode, icon) in modes)
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        settings.appearanceMode = mode;
                      },
                      child: Container(
                        width: 30,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: settings.appearanceMode == mode
                              ? ExpndColors.gold
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(sfIcon(icon),
                            size: 11,
                            color: settings.appearanceMode == mode
                                ? ExpndColors.ink
                                : oc.muted),
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

  // ── Data ─────────────────────────────────────────────────────────────────
  Widget _dataSection(ExpndColors oc, AppStore store, String symbol) {
    Widget row(String icon, Color iconColor, String title, String subtitle,
        VoidCallback onTap,
        {bool enabled = true}) {
      return GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(sfIcon(icon), size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: title == 'Clear All Data'
                                  ? ExpndColors.red
                                  : oc.text)),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: oc.muted)),
                    ],
                  ),
                ),
                Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
              ],
            ),
          ),
        ),
      );
    }

    final count = store.transactions.length;
    return _sectionCard(
      oc,
      'DATA',
      Column(
        children: [
          row('square.and.arrow.up', ExpndColors.gold, 'Import Transactions',
              'Load from CSV file', () => _importCSV(store)),
          _divider(oc),
          row('square.and.arrow.up', ExpndColors.green, 'Export Transactions',
              'Download as CSV file', () => _exportCSV(store),
              enabled: count > 0),
          _divider(oc),
          row('trash.fill', ExpndColors.red, 'Clear All Data',
              '$count transaction${count == 1 ? "" : "s"} will be removed',
              () => _confirmClear(store),
              enabled: count > 0),
        ],
      ),
    );
  }

  Future<void> _exportCSV(AppStore store) async {
    final buf = StringBuffer('Date,Category,Type,Amount,Note\n');
    for (final t in store.transactions) {
      final note = t.note.replaceAll(',', ';');
      buf.write(
          '${_shortDate(t.date)},${t.category.raw},${t.type.raw},${t.amount.toStringAsFixed(2)},$note\n');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/expnd-transactions.csv');
    await file.writeAsString(buf.toString());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'EXPND transactions export'),
    );
  }

  Future<void> _importCSV(AppStore store) async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    if (result == null || result.files.single.path == null) return;
    final content = await File(result.files.single.path!).readAsString();
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) {
      _snack('No valid rows found.');
      return;
    }
    var added = 0;
    for (final line in lines.skip(1)) {
      final cols = line.split(',');
      if (cols.length < 4) continue;
      final date = _parseDate(cols[0].trim());
      final amount = double.tryParse(cols[3].trim());
      if (date == null || amount == null || amount <= 0) continue;
      final type = cols[2].trim().toLowerCase() == 'income'
          ? TransactionType.income
          : TransactionType.expense;
      final cat = TransactionCategory.values.firstWhere(
          (c) => c.raw.toLowerCase() == cols[1].trim().toLowerCase(),
          orElse: () => TransactionCategory.other);
      store.addTransaction(Transaction(
        note: cols.length >= 5 ? cols[4].trim() : '',
        amount: amount,
        category: cat,
        type: type,
        date: date,
      ));
      added++;
    }
    Haptics.success();
    _snack(added > 0 ? 'Imported $added transactions' : 'No valid rows found.');
  }

  DateTime? _parseDate(String s) {
    // try ISO / common formats
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // MMM d, yyyy  e.g. "Jan 5, 2026"
    final m = RegExp(r'^(\w{3}) (\d{1,2}), (\d{4})$').firstMatch(s);
    if (m != null) {
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
      };
      final mm = months[m.group(1)];
      if (mm != null) {
        return DateTime(int.parse(m.group(3)!), mm, int.parse(m.group(2)!));
      }
    }
    // MM/dd/yyyy
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    if (slash != null) {
      return DateTime(int.parse(slash.group(3)!), int.parse(slash.group(1)!),
          int.parse(slash.group(2)!));
    }
    return null;
  }

  void _confirmClear(AppStore store) {
    final oc = context.oc;
    final count = store.transactions.length;
    showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Clear all transactions?',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: oc.text)),
              const SizedBox(height: 8),
              Text(
                  'This will permanently delete $count transaction${count == 1 ? "" : "s"}. This cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: oc.muted)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    for (final t in store.transactions) {
                      store.deleteTransaction(t);
                    }
                    Haptics.warning();
                    Navigator.of(context).pop();
                  },
                  child: Text('Clear All Data',
                      style: TextStyle(
                          color: ExpndColors.red, fontWeight: FontWeight.bold)),
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── About ────────────────────────────────────────────────────────────────
  Widget _aboutSection(ExpndColors oc) {
    Widget row(String icon, Color color, String label, String value,
        {bool divider = true}) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(sfIcon(icon), size: 20, color: color),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: oc.text)),
                const Spacer(),
                Text(value, style: TextStyle(fontSize: 13, color: oc.muted)),
              ],
            ),
          ),
          if (divider) _divider(oc),
        ],
      );
    }

    return _sectionCard(
      oc,
      'ABOUT',
      Column(
        children: [
          row('info.circle.fill', ExpndColors.gold, 'App', 'XPND Finance'),
          row('info.circle.fill', oc.muted, 'Version', '1.0.0'),
          row('checkmark.seal.fill', hexColor('F05138'), 'Built with',
              'Flutter + Hive',
              divider: false),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];

  // Shared grouped-number formatter (see currencies.dart). Kept as a thin
  // alias so the many local call sites read the same.
  String _fmt(double v) => formatAmount(v);

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

// ─────────────────────────────────────────────────────────────────────────────
// Category budget sheet — pick an expense category (when adding) and set a
// monthly limit. Editing an existing budget also offers Remove.
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryBudgetSheet extends StatefulWidget {
  final AppStore store;
  final TransactionCategory? editing;
  final double initialLimit;
  final String symbol;
  const _CategoryBudgetSheet({
    required this.store,
    required this.editing,
    required this.initialLimit,
    required this.symbol,
  });

  @override
  State<_CategoryBudgetSheet> createState() => _CategoryBudgetSheetState();
}

class _CategoryBudgetSheetState extends State<_CategoryBudgetSheet> {
  late TransactionCategory? _category = widget.editing;
  late final TextEditingController _limitCtrl = TextEditingController(
      text: widget.initialLimit > 0
          ? widget.initialLimit.toStringAsFixed(0)
          : '');

  bool get _isEditing => widget.editing != null;

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final cat = _category;
    final limit = double.tryParse(_limitCtrl.text) ?? 0;
    if (cat == null || limit <= 0) return;
    widget.store.setBudget(cat, limit);
    Haptics.success();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  void _remove() {
    final cat = _category;
    if (cat == null) return;
    widget.store.setBudget(cat, 0); // non-positive clears it
    Haptics.warning();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    // Expense categories that don't already have a budget (plus the one being
    // edited, so it stays selectable).
    final taken = widget.store.budgets
        .map((b) => b.category)
        .whereType<TransactionCategory>()
        .toSet();
    final available = TransactionCategory.categoriesFor(TransactionType.expense)
        .where((c) => !taken.contains(c) || c == widget.editing)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                  _isEditing ? 'EDIT CATEGORY BUDGET' : 'ADD CATEGORY BUDGET',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: oc.text)),
            ),
            const SizedBox(height: 20),
            if (!_isEditing) ...[
              Text('CATEGORY',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: oc.muted)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in available)
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        setState(() => _category = c);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _category == c
                              ? ExpndColors.gold
                              : oc.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _category == c
                                  ? ExpndColors.goldDark
                                  : oc.border,
                              width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(sfIcon(c.icon),
                                size: 12,
                                color: _category == c
                                    ? ExpndColors.ink
                                    : c.color),
                            const SizedBox(width: 6),
                            Text(c.raw,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _category == c
                                        ? ExpndColors.ink
                                        : oc.muted)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            Text('MONTHLY LIMIT',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: oc.muted)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: oc.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: oc.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Text(widget.symbol,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: oc.accent)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _limitCtrl,
                      autofocus: _isEditing,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: amountInputFormatters,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: oc.text),
                      decoration: const InputDecoration(
                          border: InputBorder.none, hintText: '0'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            NeoPopButton(
              onPressed: _save,
              enabled: _category != null &&
                  (double.tryParse(_limitCtrl.text) ?? 0) > 0,
              faceColor: _category != null &&
                      (double.tryParse(_limitCtrl.text) ?? 0) > 0
                  ? ExpndColors.gold
                  : oc.surface,
              depthColor: _category != null &&
                      (double.tryParse(_limitCtrl.text) ?? 0) > 0
                  ? ExpndColors.goldDark
                  : oc.edge,
              depth: 4,
              cornerRadius: 6,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                    child: Text(_isEditing ? 'SAVE' : 'ADD BUDGET',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: ExpndColors.ink)),
                  ),
                ),
              ),
            ),
            if (_isEditing)
              Center(
                child: TextButton(
                  onPressed: _remove,
                  child: Text('Remove budget',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ExpndColors.red)),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
