import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/insights.dart';
import '../services/reminders.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/app_header.dart';
import '../widgets/disclosure_section.dart';
import '../widgets/context_ai_coach.dart';
import '../widgets/neopop.dart';
import '../widgets/money_field.dart';
import '../widgets/neopop_cards.dart';
import '../widgets/section_card.dart';
import 'settings_view.dart';

/// Everything you actively manage about your money: what you meant to spend
/// (budgets), what you are saving toward (goals), what you owe or are owed
/// (debts), and what repeats.
///
/// Split out of the old Profile screen, which had grown to carry planning,
/// taxonomy and app settings in one 4k-line scroll. Profile kept the settings;
/// this tab took the money.
class PlanView extends StatefulWidget {
  const PlanView({super.key});

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  String _focus = 'Budgets';
  final _budgetCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _budgetCtrl.text = s.monthlyBudget > 0
        ? s.monthlyBudget.toStringAsFixed(0)
        : '';
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
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
    final aiFacts = _planAiFacts(store, settings, code);

    return Container(
      color: oc.bg,
      child: Column(
        children: [
          const ExpndHeader(
            icon: 'target',
            title: 'PLAN',
            actions: [SettingsAvatarAction()],
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                ExpndSpacing.scrollBottomUnderTabBar(context),
              ),
              children: [
                Text(
                  'What would you like to plan?',
                  style: TextStyle(fontSize: 14, color: oc.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final focus in [
                      'Budgets',
                      'Savings goals',
                      'Debts & loans',
                    ])
                      ChoiceChip(
                        label: Text(focus),
                        selected: _focus == focus,
                        onSelected: (_) => setState(() => _focus = focus),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_focus == 'Budgets') ...[
                  _budgetSection(oc, store, settings, symbol),
                  const SizedBox(height: 20),
                  _categoryBudgetsSection(oc, store, symbol),
                ],
                if (_focus == 'Savings goals')
                  _goalsSection(oc, store, goals, symbol),
                if (_focus == 'Debts & loans') ...[
                  _debtsSection(oc, store, symbol),
                  if (store.emis.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _loansSection(oc, store, code),
                  ],
                ],
                const SizedBox(height: 20),
                DisclosureSection(
                  title: 'Overall progress',
                  subtitle: 'Lifetime totals and planning insights',
                  child: Column(
                    children: [
                      _statsGrid(
                        oc,
                        txns.length,
                        balance,
                        totalIncome,
                        totalExpenses,
                        symbol,
                      ),
                      if (aiFacts.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        ContextAiCoach(facts: aiFacts),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Insight> _planAiFacts(
    AppStore store,
    SettingsStore settings,
    String code,
  ) {
    final facts = <Insight>[];
    final budget = settings.monthlyBudget;
    if (budget > 0) {
      final spent = store.spentInMonth(DateTime.now());
      final remaining = budget - spent;
      facts.add(
        Insight(
          title: remaining >= 0
              ? '${formatCurrency(remaining, code)} left this month'
              : '${formatCurrency(remaining.abs(), code)} over this month',
          detail:
              '${formatCurrency(spent, code)} spent from ${formatCurrency(budget, code)}',
          tone: remaining >= 0 ? InsightTone.good : InsightTone.warn,
          icon: remaining >= 0
              ? 'checkmark.circle.fill'
              : 'exclamationmark.triangle.fill',
          weight: 100,
        ),
      );
    }

    if (store.goals.isNotEmpty) {
      final saved = store.goals.fold(
        0.0,
        (sum, goal) => sum + goal.allocatedAmount,
      );
      final target = store.goals.fold(
        0.0,
        (sum, goal) => sum + goal.targetAmount,
      );
      facts.add(
        Insight(
          title:
              '${store.goals.length} savings goal${store.goals.length == 1 ? '' : 's'} active',
          detail:
              '${formatCurrency(saved, code)} saved of ${formatCurrency(target, code)}',
          tone: InsightTone.good,
          icon: 'target',
          weight: 70,
        ),
      );
    }

    final openDebts = store.debts.where((debt) => !debt.isSettled).toList();
    if (openDebts.isNotEmpty) {
      final outstanding = openDebts.fold(
        0.0,
        (sum, debt) => sum + store.outstandingOn(debt),
      );
      facts.add(
        Insight(
          title:
              '${formatCurrency(outstanding, code)} across ${openDebts.length} open debt${openDebts.length == 1 ? '' : 's'}',
          detail: 'Repayment plans stay visible in Upcoming',
          tone: InsightTone.neutral,
          icon: 'arrow.left.arrow.right',
          weight: 60,
        ),
      );
    }
    return facts;
  }

  Widget _statsGrid(
    ExpndColors oc,
    int count,
    double balance,
    double income,
    double expenses,
    String symbol,
  ) {
    Widget tile(String label, String value, Color color) => Expanded(
      child: NeoPopElevated(
        faceColor: oc.surface,
        depthColor: oc.edge,
        borderColor: color.withValues(alpha: 0.3),
        depth: 0,
        cornerRadius: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: oc.muted,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
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
          child: Text(
            'All-time totals',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: oc.dimmed,
            ),
          ),
        ),
        Row(
          children: [
            tile('Transactions', '$count', ExpndColors.gold),
            const SizedBox(width: 12),
            // "LIFETIME NET" (income − expense over all time), not a spendable
            // balance — the wallet's "NET WORTH" is the money-on-hand figure.
            tile(
              'Lifetime net',
              balance >= 0 ? '+${money(balance)}' : '-${money(balance)}',
              balance >= 0 ? ExpndColors.green : ExpndColors.red,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            tile('Total income', money(income), ExpndColors.green),
            const SizedBox(width: 12),
            tile('Total expenses', money(expenses), ExpndColors.red),
          ],
        ),
      ],
    );
  }

  // ── Section card wrapper ────────────────────────────────────────────────

  Widget _budgetSection(
    ExpndColors oc,
    AppStore store,
    SettingsStore settings,
    String symbol,
  ) {
    final now = DateTime.now();
    // The gauge measures against the effective limit (base + last month's
    // leftover when rollover is on); the input row always edits the base.
    final base = settings.monthlyBudget;
    final budget = settings.budgetRollover && base > 0
        ? store.rolledOverLimit(base, now)
        : base;
    final monthExpenses = store.spentInMonth(now);
    final progress = budget > 0
        ? (monthExpenses / budget).clamp(0.0, 1.0)
        : 1.0;
    final color = progress >= 0.9
        ? ExpndColors.red
        : progress >= 0.7
        ? oc.accent
        : oc.positive;

    return sectionCard(
      oc,
      'Monthly budget',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly spending limit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: oc.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your limit for the whole month. Use 0 for no limit.',
                  style: TextStyle(fontSize: 12, color: oc.muted),
                ),
                const SizedBox(height: 12),
                MoneyField(
                  controller: _budgetCtrl,
                  currencyCode: settings.currencyCode,
                  label: 'Monthly spending limit',
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: (v) =>
                      settings.monthlyBudget = double.tryParse(v) ?? 0,
                ),
              ],
            ),
          ),
          sectionDivider(oc),
          // Rollover: leftover budget carries into next month instead of
          // evaporating; an overspent month starts the next one smaller.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(sfIcon('repeat'), size: 20, color: oc.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Roll Over Leftover',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: oc.text,
                        ),
                      ),
                      Text(
                        'Unused budget carries into next month',
                        style: TextStyle(fontSize: 11, color: oc.muted),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: settings.budgetRollover,
                  activeTrackColor: ExpndColors.gold,
                  onChanged: (v) {
                    Haptics.light();
                    settings.budgetRollover = v;
                  },
                ),
              ],
            ),
          ),
          if (base > 0) ...[
            sectionDivider(oc),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: NeoPopStatCard(
                progress: progress,
                gaugeText: '${(progress * 100).toInt()}%',
                statusLabel: progress >= 1.0
                    ? 'over budget'
                    : progress >= 0.7
                    ? 'watch spending'
                    : 'on track',
                statusColor: color,
                title:
                    '$symbol${_fmt(monthExpenses)} spent of $symbol${_fmt(budget)}',
                subtitle: settings.budgetRollover && budget != base
                    ? 'this month · $symbol${_fmt(base)} '
                          '${budget > base ? '+' : '−'} $symbol${_fmt((budget - base).abs())} rolled over'
                    : 'this month · ${_monthName(now.month)} ${now.year}',
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
    ExpndColors oc,
    AppStore store,
    String symbol,
  ) {
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
    final rollover = context.watch<SettingsStore>().budgetRollover;
    // Rank by how close each budget is to (or over) its limit, so the categories
    // that need attention sit at the top instead of being buried alphabetically.
    double ratioOf(CategoryBudget b) {
      final eff = rollover
          ? store.rolledOverLimit(b.limit, now, category: b.category)
          : b.limit;
      final s = spent[b.category!] ?? 0;
      if (eff > 0) return s / eff;
      return s > 0
          ? double.infinity
          : 0; // spent with no limit left = most urgent
    }

    final budgets = store.budgets.where((b) => b.category != null).toList()
      ..sort((a, b) {
        final byRatio = ratioOf(b).compareTo(ratioOf(a));
        return byRatio != 0
            ? byRatio
            : a.category!.raw.compareTo(b.category!.raw);
      });

    return sectionCard(
      oc,
      'Category budgets',
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
                    child: Text(
                      'Set per-category limits to track spending.',
                      style: TextStyle(fontSize: 12, color: oc.muted),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < budgets.length; i++) ...[
              _categoryBudgetRow(
                oc,
                store,
                budgets[i].category!,
                // Same rollover rule as the overall budget: the row measures
                // against the effective limit, the sheet still edits the base.
                rollover
                    ? store.rolledOverLimit(
                        budgets[i].limit,
                        now,
                        category: budgets[i].category,
                      )
                    : budgets[i].limit,
                spent[budgets[i].category!] ?? 0,
                symbol,
                baseLimit: budgets[i].limit,
              ),
              if (i < budgets.length - 1) sectionDivider(oc),
            ],
          sectionDivider(oc),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openCategoryBudgetSheet(store),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(sfIcon('plus.circle.fill'), size: 20, color: oc.accent),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Add category budget',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: oc.accent,
                      ),
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

  // ── Manage custom categories ──────────────────────────────────────────────
  // Editing/deleting a custom category is reachable from Add Transaction
  // (long-press), but that's easy to miss — this gives it a home in Profile.

  Widget _categoryBudgetRow(
    ExpndColors oc,
    AppStore store,
    TransactionCategory cat,
    double limit,
    double spent,
    String symbol, {
    double? baseLimit,
  }) {
    final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final color = progress >= 0.9
        ? ExpndColors.red
        : progress >= 0.7
        ? oc.accent
        : oc.positive;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCategoryBudgetSheet(
        store,
        editing: cat,
        limit: baseLimit ?? limit,
      ),
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
                border: Border.all(
                  color: cat.color.withValues(alpha: 0.25),
                  width: 1,
                ),
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
                        child: Text(
                          cat.raw,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                      ),
                      Text(
                        '$symbol${_fmt(spent)} / $symbol${_fmt(limit)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        return Stack(
                          children: [
                            Container(height: 4, color: oc.border),
                            Container(
                              height: 4,
                              width: (c.maxWidth * progress).clamp(
                                0.0,
                                c.maxWidth,
                              ),
                              color: color,
                            ),
                          ],
                        );
                      },
                    ),
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

  Future<void> _openCategoryBudgetSheet(
    AppStore store, {
    TransactionCategory? editing,
    double limit = 0,
  }) async {
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
    ExpndColors oc,
    AppStore store,
    List<SavingsGoal> goals,
    String symbol,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Savings goals',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
              ),
              if (goals.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Haptics.light();
                    _openGoalSheet(store);
                  },
                  child: Row(
                    children: [
                      Icon(sfIcon('plus'), size: 11, color: oc.accent),
                      const SizedBox(width: 4),
                      Text(
                        'NEW GOAL',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                          color: oc.accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (goals.isEmpty)
          NeoPopElevated(
            faceColor: oc.surface,
            depthColor: oc.edge,
            borderColor: oc.border,
            depth: 0,
            cornerRadius: 6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.light();
                _openGoalSheet(store);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(sfIcon('flag.fill'), size: 20, color: oc.dimmed),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add savings goal',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: oc.accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Set a target and track what you put aside.',
                            style: TextStyle(fontSize: 12, color: oc.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      sfIcon('plus.circle.fill'),
                      size: 20,
                      color: oc.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (int i = 0; i < goals.length; i++) ...[
          _goalCard(store, goals[i], symbol),
          if (i < goals.length - 1) const SizedBox(height: 14),
        ],
        // Where the goal money actually is. Goals never move money, so this
        // has to reconcile: every account's claims plus its unclaimed
        // remainder equal the balance the bank shows.
        for (final acc in store.accounts)
          if (store.goalsIn(acc).isNotEmpty) ...[
            const SizedBox(height: 14),
            _accountAllocationCard(oc, store, acc, symbol),
          ],
      ],
    );
  }

  Widget _accountAllocationCard(
    ExpndColors oc,
    AppStore store,
    Account acc,
    String symbol,
  ) {
    final balance = store.balanceFor(acc);
    final free = store.unallocatedIn(acc);
    final over = free < 0;
    final goals = store.goalsIn(acc);

    Widget line(String label, double value, Color color, {bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(width: 8, height: 8, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
                    color: bold ? oc.text : oc.muted,
                  ),
                ),
              ),
              Text(
                '$symbol${_fmt(value)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                  color: bold ? oc.text : oc.muted,
                ),
              ),
            ],
          ),
        );

    return sectionCard(
      oc,
      'WHERE IT SITS',
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(sfIcon(acc.type.icon), size: 16, color: oc.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    acc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: oc.text,
                    ),
                  ),
                ),
                Text(
                  '$symbol${_fmt(balance)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: oc.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Balance as your bank shows it',
              style: TextStyle(fontSize: 10, color: oc.dimmed),
            ),
            const SizedBox(height: 10),
            Container(height: 1, color: oc.border),
            const SizedBox(height: 6),
            for (final g in goals)
              line(g.name, g.allocatedAmount, hexColor(g.colorHex)),
            line(
              over ? 'Overcommitted' : 'Unclaimed',
              free,
              over ? ExpndColors.red : oc.dimmed,
            ),
            const SizedBox(height: 6),
            Container(height: 1, color: oc.border),
            line('Total', balance, Colors.transparent, bold: true),
            if (over) ...[
              const SizedBox(height: 6),
              Text(
                'Your goals set aside more than ${acc.name} holds — some of '
                'it has been spent. Release a goal to square it up.',
                style: TextStyle(fontSize: 11, color: ExpndColors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Debts ────────────────────────────────────────────────────────────────
  //
  // Lending is a real movement, so the cash leaving an account is an ordinary
  // transaction. This section only answers "who owes what", which no account
  // balance can.

  /// Loans and installment plans, gathered from every account.
  ///
  /// They used to be reachable only through Wallet → pick the credit card →
  /// scroll, which hid the largest recurring commitment most people have.
  /// This is a read-out; the rows tap through to the account that holds them.
  Widget _loansSection(ExpndColors oc, AppStore store, String code) {
    final loans = store.emis.toList()
      ..sort((a, b) {
        // Running loans first, then by how much is left to pay.
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.remainingAmount.compareTo(a.remainingAmount);
      });
    final monthly = loans
        .where((e) => e.isActive)
        .fold(0.0, (s, e) => s + e.monthlyAmount);
    final owed = loans
        .where((e) => e.isActive)
        .fold(0.0, (s, e) => s + e.outstandingPrincipal);

    return sectionCard(
      oc,
      'LOANS & EMIs',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PER MONTH',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: oc.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatCurrency(monthly, code),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: oc.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'STILL OWED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: oc.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatCurrency(owed, code),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: ExpndColors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (int i = 0; i < loans.length; i++) ...[
            sectionDivider(oc),
            _loanRow(oc, store, loans[i], code),
          ],
        ],
      ),
    );
  }

  Widget _loanRow(ExpndColors oc, AppStore store, Emi e, String code) {
    final acc = store.accountFor(e.accountId);
    final done = !e.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sfIcon(done ? 'checkmark.circle.fill' : 'creditcard.fill'),
                size: 16,
                color: done ? ExpndColors.green : oc.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.name.trim().isEmpty ? 'Loan' : e.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${formatCurrency(e.monthlyAmount, code)}/mo',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? oc.dimmed : oc.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            done
                ? 'Closed · ${acc?.name ?? 'no account'}'
                : '${e.annualRate.toStringAsFixed(e.annualRate % 1 == 0 ? 0 : 2)}% · '
                      '${e.monthsRemaining} of ${e.tenureMonths} mo left · '
                      '${acc?.name ?? 'no account'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: oc.dimmed),
          ),
          if (!done) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: e.progress,
                minHeight: 4,
                backgroundColor: oc.border,
                valueColor: AlwaysStoppedAnimation(oc.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _debtsSection(ExpndColors oc, AppStore store, String symbol) {
    final debts = store.debts;
    final open = debts.where((d) => !d.isSettled).toList();

    return sectionCard(
      oc,
      'LENT & BORROWED',
      Column(
        children: [
          if (open.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OWED TO YOU',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: oc.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$symbol${_fmt(store.owedToMe)}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: ExpndColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 34, color: oc.border),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'YOU OWE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: oc.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$symbol${_fmt(store.owedByMe)}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: ExpndColors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            sectionDivider(oc),
          ],
          if (debts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(
                    sfIcon('arrow.left.arrow.right'),
                    size: 20,
                    color: oc.dimmed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Track money you\'ve lent out or borrowed.',
                      style: TextStyle(fontSize: 12, color: oc.muted),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < debts.length; i++) ...[
              _debtRow(oc, store, debts[i], symbol),
              if (i < debts.length - 1) sectionDivider(oc),
            ],
          sectionDivider(oc),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openDebtSheet(store, symbol),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(sfIcon('plus.circle.fill'), size: 20, color: oc.accent),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Record a loan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: oc.accent,
                      ),
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

  Widget _debtRow(ExpndColors oc, AppStore store, Debt d, String symbol) {
    final outstanding = store.outstandingOn(d);
    final repaid = store.repaidOn(d);
    final color = d.theyOweMe ? ExpndColors.green : ExpndColors.red;
    final progress = d.amount > 0 ? (repaid / d.amount).clamp(0.0, 1.0) : 0.0;
    final overdue =
        !d.isSettled &&
        d.dueDate != null &&
        d.dueDate!.isBefore(DateTime.now());

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _debtOptions(store, d, symbol),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: color.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    sfIcon(d.theyOweMe ? 'arrow.down' : 'arrow.up'),
                    size: 14,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.person,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: oc.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d.isSettled
                            ? 'Settled'
                            : overdue
                            ? 'Due ${_goalDate(d.dueDate!)} · overdue'
                            : d.theyOweMe
                            ? 'Lent ${_goalDate(d.date)}'
                            : 'Borrowed ${_goalDate(d.date)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: overdue ? ExpndColors.red : oc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$symbol${_fmt(d.isSettled ? d.amount : outstanding)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: d.isSettled ? oc.dimmed : color,
                      ),
                    ),
                    if (!d.isSettled && repaid > 0)
                      Text(
                        'of $symbol${_fmt(d.amount)}',
                        style: TextStyle(fontSize: 10, color: oc.dimmed),
                      ),
                  ],
                ),
              ],
            ),
            if (!d.isSettled && repaid > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LayoutBuilder(
                  builder: (_, c) {
                    return Stack(
                      children: [
                        Container(height: 4, color: oc.border),
                        Container(
                          height: 4,
                          width: (c.maxWidth * progress).clamp(0.0, c.maxWidth),
                          color: color,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _debtOptions(AppStore store, Debt d, String symbol) async {
    Haptics.light();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  d.person.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              Container(height: 1, color: oc.border),
              if (!d.isSettled)
                _goalOptionRow(
                  oc,
                  'banknote.fill',
                  d.theyOweMe ? 'Record repayment' : 'Record a payment',
                  () => Navigator.of(sheet).pop('repay'),
                ),
              if (!d.isSettled)
                _goalOptionRow(
                  oc,
                  'checkmark.circle.fill',
                  'Mark settled',
                  () => Navigator.of(sheet).pop('settle'),
                ),
              if (d.isSettled)
                _goalOptionRow(
                  oc,
                  'arrow.up',
                  'Reopen',
                  () => Navigator.of(sheet).pop('reopen'),
                ),
              _goalOptionRow(
                oc,
                'trash',
                'Delete',
                () => Navigator.of(sheet).pop('delete'),
                danger: true,
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheet).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'repay':
        await _openRepaySheet(store, d, symbol);
      case 'settle':
        d.settledDate = DateTime.now();
        store.updateDebt();
        Haptics.success();
      case 'reopen':
        d.settledDate = null;
        store.updateDebt();
        Haptics.light();
      case 'delete':
        store.deleteDebt(d);
        Haptics.warning();
    }
  }

  Future<void> _openDebtSheet(AppStore store, String symbol) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DebtSheet(store: store, symbol: symbol),
    );
  }

  Future<void> _openRepaySheet(AppStore store, Debt d, String symbol) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RepaySheet(store: store, debt: d, symbol: symbol),
    );
  }

  Future<void> _openGoalSheet(AppStore store, {SavingsGoal? editing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoalSheet(
        store: store,
        editing: editing,
        symbol: currencySymbol(context.read<SettingsStore>().currencyCode),
      ),
    );
  }

  Widget _goalCard(AppStore store, SavingsGoal goal, String symbol) {
    final color = hexColor(goal.colorHex);
    final progress = store.progressForGoal(goal);
    final saved = goal.allocatedAmount;
    final pct = (progress * 100).toInt();
    final holder = store.accountFor(goal.accountId);
    return NeoPopBillCard(
      color: color,
      name: goal.name,
      subtitle: holder != null
          ? 'set aside in ${holder.name}'
          : 'no account linked',
      icon: sfIcon(goal.iconName),
      tagText: '$pct% saved',
      tagColor: Color.alphaBlend(Colors.black.withValues(alpha: 0.30), color),
      amountText: '$symbol${_fmt(saved)} of $symbol${_fmt(goal.targetAmount)}',
      progress: progress,
      ctaLabel: progress >= 1.0 ? 'Completed' : 'Set aside',
      onCta: () {
        Haptics.light();
        // A finished goal clamps every contribution to zero, so send that CTA
        // to the breakdown instead of an input that can't do anything.
        if (progress >= 1.0) {
          _goalDetails(store, goal, symbol);
        } else {
          _contribute(store, goal, symbol);
        }
      },
      onOptions: () {
        Haptics.light();
        _goalOptions(store, goal, symbol);
      },
    );
  }

  /// The ⋮ on a goal card. Used to delete the goal outright on a single tap —
  /// now it opens a menu, and deleting goes through a confirmation.

  Future<void> _goalOptions(
    AppStore store,
    SavingsGoal goal,
    String symbol,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  goal.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              Container(height: 1, color: oc.border),
              _goalOptionRow(
                oc,
                'eye',
                'View details',
                () => Navigator.of(sheet).pop('view'),
              ),
              if (store.progressForGoal(goal) < 1.0)
                _goalOptionRow(
                  oc,
                  'plus.circle',
                  'Set aside more',
                  () => Navigator.of(sheet).pop('funds'),
                ),
              if (goal.allocatedAmount > 0)
                _goalOptionRow(
                  oc,
                  'arrow.down.circle.fill',
                  'Release money',
                  () => Navigator.of(sheet).pop('release'),
                ),
              _goalOptionRow(
                oc,
                'pencil',
                'Edit goal',
                () => Navigator.of(sheet).pop('edit'),
              ),
              _goalOptionRow(
                oc,
                'trash',
                'Delete goal',
                () => Navigator.of(sheet).pop('delete'),
                danger: true,
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheet).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        await _goalDetails(store, goal, symbol);
      case 'funds':
        await _contribute(store, goal, symbol);
      case 'release':
        await _confirmRelease(store, goal, symbol);
      case 'edit':
        await _openGoalSheet(store, editing: goal);
      case 'delete':
        await _confirmDeleteGoal(store, goal);
    }
  }

  /// Hands a goal's claim back to the account. Used when the money gets spent
  /// on the thing, or the goal is abandoned — no money moves either way, the
  /// balance just stops being spoken for.

  Future<void> _confirmRelease(
    AppStore store,
    SavingsGoal goal,
    String symbol,
  ) async {
    Haptics.light();
    final holder = store.accountFor(goal.accountId);
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Release $symbol${_fmt(goal.allocatedAmount)}?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: oc.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  holder == null
                      ? 'The goal stops claiming this money.'
                      : 'It stays in ${holder.name} — it just stops being '
                            'set aside for ${goal.name}. If you spent it, '
                            'record that separately.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: oc.muted),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      store.releaseFromGoal(goal);
                      Haptics.success();
                      Navigator.of(sheet).pop();
                    },
                    child: Text(
                      'Release',
                      style: TextStyle(
                        color: oc.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheet).pop(),
                    child: Text('Cancel', style: TextStyle(color: oc.muted)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _goalOptionRow(
    ExpndColors oc,
    String icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? ExpndColors.red : oc.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(sfIcon(icon), size: 16, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Read-only breakdown of a goal: progress, what's saved, what's left.

  Future<void> _goalDetails(
    AppStore store,
    SavingsGoal goal,
    String symbol,
  ) async {
    final color = hexColor(goal.colorHex);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        final saved = goal.allocatedAmount;
        final progress = store.progressForGoal(goal);
        final remaining = (goal.targetAmount - saved).clamp(
          0.0,
          double.infinity,
        );
        final holder = store.accountFor(goal.accountId);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        sfIcon(goal.iconName),
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: oc.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            progress >= 1.0
                                ? 'Goal reached'
                                : '${(progress * 100).toInt()}% saved',
                            style: TextStyle(fontSize: 12, color: oc.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (_, c) {
                    return Stack(
                      children: [
                        Container(
                          height: 6,
                          width: c.maxWidth,
                          color: oc.border,
                        ),
                        Container(
                          height: 6,
                          width: (c.maxWidth * progress).clamp(0.0, c.maxWidth),
                          color: color,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                _goalDetailRow(oc, 'Set aside', '$symbol${_fmt(saved)}'),
                _goalDetailRow(
                  oc,
                  'Target',
                  '$symbol${_fmt(goal.targetAmount)}',
                ),
                _goalDetailRow(oc, 'Still to go', '$symbol${_fmt(remaining)}'),
                _goalDetailRow(oc, 'Held in', holder?.name ?? 'Not linked'),
                if (holder != null)
                  _goalDetailRow(
                    oc,
                    '${holder.name} balance',
                    '$symbol${_fmt(store.balanceFor(holder))}',
                  ),
                _goalDetailRow(oc, 'Started', _goalDate(goal.createdDate)),
                if (holder != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'This money is part of the ${holder.name} balance above '
                    '— it hasn\'t been moved anywhere.',
                    style: TextStyle(fontSize: 11, color: oc.dimmed),
                  ),
                ],
                const SizedBox(height: 12),
                if (progress < 1.0)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheet).pop('funds'),
                      child: Text(
                        'Set Aside More',
                        style: TextStyle(
                          color: oc.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (saved > 0)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheet).pop('release'),
                      child: Text(
                        'Release Money',
                        style: TextStyle(
                          color: oc.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheet).pop('edit'),
                    child: Text(
                      'Edit Goal',
                      style: TextStyle(
                        color: oc.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheet).pop('delete'),
                    child: Text(
                      'Delete Goal',
                      style: TextStyle(
                        color: ExpndColors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'funds') {
      await _contribute(store, goal, symbol);
    } else if (action == 'release') {
      await _confirmRelease(store, goal, symbol);
    } else if (action == 'edit') {
      await _openGoalSheet(store, editing: goal);
    } else if (action == 'delete') {
      await _confirmDeleteGoal(store, goal);
    }
  }

  Widget _goalDetailRow(ExpndColors oc, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: oc.muted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: oc.text,
            ),
          ),
        ],
      ),
    );
  }

  String _goalDate(DateTime d) =>
      '${_goalMonths[d.month - 1]} ${d.day}, ${d.year}';

  static const _goalMonths = [
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

  Future<void> _confirmDeleteGoal(AppStore store, SavingsGoal goal) async {
    Haptics.light();
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete "${goal.name}"?',
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
                      store.deleteGoal(goal);
                      Haptics.warning();
                      Navigator.of(sheet).pop();
                    },
                    child: Text(
                      'Delete Goal',
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
                    onPressed: () => Navigator.of(sheet).pop(),
                    child: Text('Cancel', style: TextStyle(color: oc.muted)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A contribution is a real transfer: money leaves the account the user
  /// picks and lands in the account the goal is held in.

  Future<void> _contribute(
    AppStore store,
    SavingsGoal goal,
    String symbol,
  ) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ContributeSheet(store: store, goal: goal, symbol: symbol),
    );
    // The goal has nowhere to hold the money yet — send them to pick one.
    if (mounted && result == 'link') {
      await _openGoalSheet(store, editing: goal);
    }
  }

  // ── Recurring ────────────────────────────────────────────────────────────

  // ── General ──────────────────────────────────────────────────────────────

  String _monthName(int m) => const [
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
  ][m - 1];

  // Shared grouped-number formatter (see currencies.dart). Kept as a thin
  // alias so the many local call sites read the same.

  String _fmt(double v) => formatAmount(v);
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
    text: widget.initialLimit > 0 ? widget.initialLimit.toStringAsFixed(0) : '',
  );

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
    final available = TransactionCategory.categoriesFor(
      TransactionType.expense,
    ).where((c) => !taken.contains(c) || c == widget.editing).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: oc.text,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isEditing) ...[
              Text(
                'CATEGORY',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: oc.muted,
                ),
              ),
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
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _category == c ? ExpndColors.gold : oc.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _category == c
                                ? ExpndColors.goldDark
                                : oc.border,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              sfIcon(c.icon),
                              size: 12,
                              color: _category == c ? ExpndColors.ink : c.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              c.raw,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _category == c
                                    ? ExpndColors.ink
                                    : oc.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'MONTHLY LIMIT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                color: oc.muted,
              ),
            ),
            const SizedBox(height: 10),
            MoneyField(
              controller: _limitCtrl,
              currencyCode: context.read<SettingsStore>().currencyCode,
              label: 'Monthly category limit',
              autofocus: _isEditing,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            NeoPopButton(
              onPressed: _save,
              enabled:
                  _category != null &&
                  (double.tryParse(_limitCtrl.text) ?? 0) > 0,
              faceColor:
                  _category != null &&
                      (double.tryParse(_limitCtrl.text) ?? 0) > 0
                  ? ExpndColors.gold
                  : oc.surface,
              depthColor:
                  _category != null &&
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
                    child: Text(
                      _isEditing ? 'SAVE' : 'ADD BUDGET',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: ExpndColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isEditing)
              Center(
                child: TextButton(
                  onPressed: _remove,
                  child: Text(
                    'Remove budget',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ExpndColors.red,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Creates a savings goal, or edits one in place. Goals used to exist only in
/// seeded data, so a fresh install had no way to make one.
class _GoalSheet extends StatefulWidget {
  final AppStore store;
  final SavingsGoal? editing;
  final String symbol;
  const _GoalSheet({
    required this.store,
    required this.editing,
    required this.symbol,
  });

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _savedCtrl = TextEditingController();
  String _icon = 'star.fill';
  String _colorHex = _colors.first;
  String? _accountId;

  // Deep enough for the white text the goal card paints over them.
  static const _colors = [
    '1A56DB',
    '057A55',
    '7C3AED',
    'C27803',
    '0E7490',
    'EF4444',
    'F97316',
    'EC4899',
    '10B981',
    '6366F1',
  ];

  static const _icons = [
    'star.fill',
    'flag.fill',
    'target',
    'gift.fill',
    'car.fill',
    'house.fill',
    'laptopcomputer',
    'camera.fill',
    'book.closed.fill',
    'bag.fill',
    'gamecontroller.fill',
    'shield.fill',
  ];

  bool get _isEditing => widget.editing != null;
  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty &&
      (double.tryParse(_targetCtrl.text) ?? 0) > 0;

  /// Savings accounts first — that's where a goal's money normally sits — but
  /// any account can hold one.
  List<Account> get _holders {
    final all = widget.store.accounts;
    final savings = all.where((a) => a.type == AccountType.savings).toList();
    final rest = all.where((a) => a.type != AccountType.savings).toList();
    return [...savings, ...rest];
  }

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _targetCtrl.text = e.targetAmount.toStringAsFixed(0);
      if (e.allocatedAmount > 0) {
        _savedCtrl.text = e.allocatedAmount.toStringAsFixed(0);
      }
      _icon = e.iconName;
      _colorHex = e.colorHex;
      _accountId = e.accountId;
    } else {
      // Default to the first savings account so the common case is one tap.
      final holders = _holders;
      if (holders.isNotEmpty && holders.first.type == AccountType.savings) {
        _accountId = holders.first.id;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _savedCtrl.dispose();
    super.dispose();
  }

  /// The most this goal may set aside: what the chosen account has spare, plus
  /// whatever this goal already claims (editing shouldn't fight its own claim).
  double get _maxSetAside {
    final acc = widget.store.accountFor(_accountId);
    if (acc == null) return 0;
    final free = widget.store.unallocatedIn(acc);
    final mine =
        widget.editing != null && widget.editing!.accountId == _accountId
        ? widget.editing!.allocatedAmount
        : 0;
    final max = free + mine;
    return max < 0 ? 0 : max;
  }

  void _save() {
    if (!_isValid) return;
    final name = _nameCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text) ?? 0;
    // Two ceilings: the target (progress divides by it) and what the account
    // actually holds — a goal must never claim money that isn't there.
    final saved = (double.tryParse(_savedCtrl.text) ?? 0)
        .clamp(0.0, target)
        .clamp(0.0, _maxSetAside);
    final e = widget.editing;
    if (e != null) {
      e.name = name;
      e.targetAmount = target;
      e.allocatedAmount = saved;
      e.iconName = _icon;
      e.colorHex = _colorHex;
      e.accountId = _accountId;
      widget.store.touchGoals();
    } else {
      widget.store.addGoal(
        SavingsGoal(
          name: name,
          targetAmount: target,
          allocatedAmount: saved,
          iconName: _icon,
          colorHex: _colorHex,
          accountId: _accountId,
        ),
      );
    }
    // Funding a goal to its target is a "goal reached" moment — refresh the
    // alerts so the celebration fires now, not just on the next launch.
    unawaited(
      Reminders.refreshAll(widget.store, context.read<SettingsStore>()),
    );
    Haptics.success();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final accent = hexColor(_colorHex);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  _isEditing ? 'EDIT SAVINGS GOAL' : 'NEW SAVINGS GOAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _label(oc, 'GOAL NAME'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: oc.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: oc.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(sfIcon(_icon), size: 18, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        autofocus: !_isEditing,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: oc.text,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'e.g. Japan Trip',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _label(oc, 'TARGET AMOUNT'),
              const SizedBox(height: 10),
              _amountField(oc, _targetCtrl, '0'),
              const SizedBox(height: 20),
              _label(oc, 'HELD IN'),
              const SizedBox(height: 4),
              Text(
                'The account this goal\'s money actually sits in. '
                'Contributions transfer into it.',
                style: TextStyle(fontSize: 11, color: oc.dimmed),
              ),
              const SizedBox(height: 10),
              if (_holders.isEmpty)
                Text(
                  'No accounts yet — add one in Wallet to fund this goal.',
                  style: TextStyle(fontSize: 12, color: oc.muted),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in _holders)
                      GestureDetector(
                        onTap: () {
                          Haptics.light();
                          // Tapping the selected one clears it — an unlinked
                          // goal is allowed, it just can't take contributions.
                          setState(
                            () => _accountId = _accountId == a.id ? null : a.id,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _accountId == a.id ? accent : oc.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _accountId == a.id ? accent : oc.border,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                sfIcon(a.type.icon),
                                size: 12,
                                color: _accountId == a.id
                                    ? Colors.white
                                    : oc.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                a.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _accountId == a.id
                                      ? Colors.white
                                      : oc.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              _label(oc, 'SET ASIDE NOW (OPTIONAL)'),
              const SizedBox(height: 4),
              Text(
                _accountId == null
                    ? 'Link an account first — money can only be set aside '
                          'from a balance you already have.'
                    : 'How much of that balance is already spoken for by '
                          'this goal. Nothing moves; it stays in the account.',
                style: TextStyle(fontSize: 11, color: oc.dimmed),
              ),
              const SizedBox(height: 10),
              _amountField(oc, _savedCtrl, '0'),
              if (_accountId != null) ...[
                const SizedBox(height: 6),
                Builder(
                  builder: (_) {
                    final entered = double.tryParse(_savedCtrl.text) ?? 0;
                    final over = entered > _maxSetAside;
                    final acc = widget.store.accountFor(_accountId);
                    return Text(
                      over
                          ? '${acc?.name ?? 'That account'} only has '
                                '${widget.symbol}${formatAmount(_maxSetAside)} unclaimed.'
                          : 'Up to ${widget.symbol}${formatAmount(_maxSetAside)} unclaimed '
                                'in ${acc?.name ?? 'that account'}.',
                      style: TextStyle(
                        fontSize: 11,
                        color: over ? ExpndColors.red : oc.dimmed,
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 20),
              _label(oc, 'ICON'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final name in _icons)
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        setState(() => _icon = name);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _icon == name ? accent : oc.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _icon == name ? accent : oc.border,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          sfIcon(name),
                          size: 18,
                          color: _icon == name ? Colors.white : oc.muted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _label(oc, 'COLOR'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final hex in _colors)
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        setState(() => _colorHex = hex);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hexColor(hex),
                          shape: BoxShape.circle,
                          border: _colorHex == hex
                              ? Border.all(color: oc.text, width: 2.5)
                              : null,
                        ),
                        child: AnimatedScale(
                          scale: _colorHex == hex ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          child: const Icon(
                            Icons.check,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              NeoPopButton(
                onPressed: _save,
                enabled: _isValid,
                faceColor: _isValid ? ExpndColors.gold : oc.surface,
                depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
                depth: 4,
                cornerRadius: 6,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Center(
                      child: Text(
                        _isEditing ? 'SAVE CHANGES' : 'ADD GOAL',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: _isValid ? ExpndColors.ink : oc.dimmed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ExpndColors oc, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.3,
      color: oc.muted,
    ),
  );

  Widget _amountField(
    ExpndColors oc,
    TextEditingController ctrl,
    String hint,
  ) => MoneyField(
    controller: ctrl,
    currencyCode: context.read<SettingsStore>().currencyCode,
    label: ctrl == _targetCtrl ? 'Goal target' : 'Amount set aside',
    onChanged: (_) => setState(() {}),
  );
}

/// Sets aside part of an account's existing balance for a goal.
///
/// Deliberately writes no transaction: the money is already in the account and
/// nothing about it changes in the real world, so inventing a movement here
/// would put EXPND's balances permanently out of step with the user's bank.
/// All that changes is how much of the balance has a name on it.
class _ContributeSheet extends StatefulWidget {
  final AppStore store;
  final SavingsGoal goal;
  final String symbol;
  const _ContributeSheet({
    required this.store,
    required this.goal,
    required this.symbol,
  });

  @override
  State<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends State<_ContributeSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _entered => double.tryParse(_ctrl.text) ?? 0;
  double get _available => widget.store.availableToAllocate(widget.goal);
  bool get _isValid => _entered > 0 && _entered <= _available;

  void _save() {
    if (!_isValid) return;
    widget.store.allocateToGoal(widget.goal, _entered);
    Haptics.success();
    // Detach the keyboard before the sheet pops so it slides away cleanly on
    // iOS instead of lingering.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = widget.store;
    final goal = widget.goal;
    final symbol = widget.symbol;
    final holder = store.accountFor(goal.accountId);
    final over = _entered > _available;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'SET ASIDE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${goal.name} · ${(store.progressForGoal(goal) * 100).toInt()}% of target',
                  style: TextStyle(fontSize: 12, color: oc.muted),
                ),
              ),
              const SizedBox(height: 20),
              if (holder == null) ...[
                // Nothing to claim against: the goal has no account yet.
                Text(
                  'This goal isn\'t linked to an account yet.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: oc.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Setting money aside earmarks part of an account you '
                  'already have, so the goal needs to know which one.',
                  style: TextStyle(fontSize: 12, color: oc.muted),
                ),
                const SizedBox(height: 20),
                NeoPopButton(
                  onPressed: () => Navigator.of(context).pop('link'),
                  depth: 4,
                  cornerRadius: 6,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Center(
                        child: Text(
                          'CHOOSE ACCOUNT',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: ExpndColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // The whole point of the screen: what's genuinely spare.
                _allocationBar(oc, store, holder, symbol),
                const SizedBox(height: 20),
                Text(
                  'AMOUNT TO SET ASIDE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(height: 10),
                MoneyField(
                  controller: _ctrl,
                  currencyCode: context.read<SettingsStore>().currencyCode,
                  label: 'Amount to set aside',
                  autofocus: true,
                  error: over,
                  onChanged: (_) => setState(() {}),
                  trailing: TextButton(
                    onPressed: () => setState(
                      () => _ctrl.text = _available.toStringAsFixed(
                        currencyDecimalDigits(
                          context.read<SettingsStore>().currencyCode,
                        ),
                      ),
                    ),
                    child: const Text('Max'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  over
                      ? '${holder.name} only has $symbol${formatAmount(_available)} unclaimed.'
                      : 'Nothing moves — this money stays in ${holder.name}.',
                  style: TextStyle(
                    fontSize: 11,
                    color: over ? ExpndColors.red : oc.dimmed,
                  ),
                ),
                const SizedBox(height: 20),
                NeoPopButton(
                  onPressed: _save,
                  enabled: _isValid,
                  faceColor: _isValid ? ExpndColors.gold : oc.surface,
                  depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
                  depth: 4,
                  cornerRadius: 6,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Center(
                        child: Text(
                          'SET ASIDE',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: _isValid ? ExpndColors.ink : oc.dimmed,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// The account's real balance with the claims against it drawn underneath,
  /// so the parts visibly add back up to the figure the bank shows.
  Widget _allocationBar(
    ExpndColors oc,
    AppStore store,
    Account acc,
    String symbol,
  ) {
    final balance = store.balanceFor(acc);
    final claimed = store.claimedIn(acc);
    final free = balance - claimed;
    final claimedFraction = balance > 0
        ? (claimed / balance).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  acc.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
              ),
              Text(
                '$symbol${_fmt(balance)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: oc.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LayoutBuilder(
              builder: (_, c) {
                return Stack(
                  children: [
                    Container(height: 6, width: c.maxWidth, color: oc.border),
                    Container(
                      height: 6,
                      width: (c.maxWidth * claimedFraction).clamp(
                        0.0,
                        c.maxWidth,
                      ),
                      color: oc.accent,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Set aside  $symbol${_fmt(claimed)}',
                  style: TextStyle(fontSize: 11, color: oc.muted),
                ),
              ),
              Text(
                'Unclaimed  $symbol${_fmt(free < 0 ? 0 : free)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: oc.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) => formatAmount(v);
}

/// Records money lent out or borrowed.
///
/// Lending is a real movement — the cash left an account — so this optionally
/// posts that transaction alongside the debt record. The debt itself only
/// tracks who owes what, which no account balance can express.
class _DebtSheet extends StatefulWidget {
  final AppStore store;
  final String symbol;
  const _DebtSheet({required this.store, required this.symbol});

  @override
  State<_DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<_DebtSheet> {
  final _personCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _planCtrl = TextEditingController();
  bool _theyOweMe = true;
  DateTime? _dueDate;
  String? _accountId;
  bool _recordMovement = true;

  @override
  void initState() {
    super.initState();
    final accounts = widget.store.accounts;
    if (accounts.isNotEmpty) _accountId = accounts.first.id;
  }

  @override
  void dispose() {
    _personCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _planCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;
  bool get _isValid => _personCtrl.text.trim().isNotEmpty && _amount > 0;

  void _save() {
    if (!_isValid) return;
    final store = widget.store;
    final debt = Debt(
      person: _personCtrl.text.trim(),
      amount: _amount,
      theyOweMe: _theyOweMe,
      dueDate: _dueDate,
      note: _noteCtrl.text.trim(),
      accountId: _accountId,
      monthlyRepayment: double.tryParse(_planCtrl.text),
    );
    store.addDebt(debt);

    // The money genuinely moved, so record it like any other movement —
    // otherwise the account balance silently stops matching the bank.
    if (_recordMovement && _accountId != null) {
      final t = Transaction(
        note: _theyOweMe
            ? 'Lent to ${debt.person}'
            : 'Borrowed from ${debt.person}',
        amount: _amount,
        category: TransactionCategory.other,
        // Lending: money leaves. Borrowing: money arrives.
        type: _theyOweMe ? TransactionType.expense : TransactionType.income,
        accountId: _accountId,
      );
      store.addTransaction(t);
    }
    Haptics.success();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final accounts = widget.store.accounts;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'RECORD A LOAN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _directionButton(
                      oc,
                      true,
                      'I LENT IT',
                      'They owe me',
                      ExpndColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _directionButton(
                      oc,
                      false,
                      'I BORROWED',
                      'I owe them',
                      ExpndColors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _label(oc, 'PERSON'),
              const SizedBox(height: 10),
              _textField(oc, _personCtrl, 'e.g. Rahul'),
              const SizedBox(height: 20),
              _label(oc, 'REPAID MONTHLY (OPTIONAL)'),
              const SizedBox(height: 10),
              _textField(
                oc,
                _planCtrl,
                'e.g. 200 — leave blank for no plan',
                numeric: true,
              ),
              const SizedBox(height: 6),
              Text(
                'With a monthly figure the repayments show up in Upcoming '
                'like any other commitment.',
                style: TextStyle(fontSize: 10, color: oc.dimmed),
              ),
              const SizedBox(height: 20),
              _label(oc, 'AMOUNT'),
              const SizedBox(height: 10),
              MoneyField(
                controller: _amountCtrl,
                currencyCode: context.read<SettingsStore>().currencyCode,
                label: 'Debt amount',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              _label(oc, 'DUE DATE (OPTIONAL)'),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        _dueDate ??
                        DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: oc.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: oc.border, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(sfIcon('calendar'), size: 14, color: oc.accent),
                      const SizedBox(width: 10),
                      Text(
                        _dueDate == null
                            ? 'No due date'
                            : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _dueDate == null ? oc.muted : oc.text,
                        ),
                      ),
                      const Spacer(),
                      if (_dueDate != null)
                        GestureDetector(
                          onTap: () => setState(() => _dueDate = null),
                          child: Icon(
                            sfIcon('xmark.circle'),
                            size: 14,
                            color: oc.dimmed,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _label(oc, 'NOTE (OPTIONAL)'),
              const SizedBox(height: 10),
              _textField(oc, _noteCtrl, 'what it was for'),
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: 20),
                _label(oc, 'ACCOUNT'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in accounts)
                      GestureDetector(
                        onTap: () {
                          Haptics.light();
                          setState(() => _accountId = a.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _accountId == a.id
                                ? ExpndColors.gold
                                : oc.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _accountId == a.id
                                  ? ExpndColors.goldDark
                                  : oc.border,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _accountId == a.id
                                  ? ExpndColors.ink
                                  : oc.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Haptics.light();
                    setState(() => _recordMovement = !_recordMovement);
                  },
                  child: Row(
                    children: [
                      Icon(
                        sfIcon(
                          _recordMovement
                              ? 'checkmark.circle.fill'
                              : 'circle.lefthalf.filled',
                        ),
                        size: 16,
                        color: _recordMovement ? ExpndColors.gold : oc.dimmed,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _theyOweMe
                              ? 'The money left this account'
                              : 'The money arrived in this account',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _recordMovement
                      ? 'Records it as a real transaction so the balance stays right.'
                      : 'No transaction — use this if the cash never touched a tracked account.',
                  style: TextStyle(fontSize: 11, color: oc.dimmed),
                ),
              ],
              const SizedBox(height: 22),
              NeoPopButton(
                onPressed: _save,
                enabled: _isValid,
                faceColor: _isValid ? ExpndColors.gold : oc.surface,
                depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
                depth: 4,
                cornerRadius: 6,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Center(
                      child: Text(
                        'SAVE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: _isValid ? ExpndColors.ink : oc.dimmed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _directionButton(
    ExpndColors oc,
    bool value,
    String title,
    String subtitle,
    Color color,
  ) {
    final active = _theyOweMe == value;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _theyOweMe = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : oc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color : oc.border, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: active ? color : oc.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 11, color: oc.dimmed)),
          ],
        ),
      ),
    );
  }

  Widget _label(ExpndColors oc, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.3,
      color: oc.muted,
    ),
  );

  Widget _textField(
    ExpndColors oc,
    TextEditingController ctrl,
    String hint, {
    bool numeric = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1.5),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        inputFormatters: numeric ? amountInputFormatters : null,
        textCapitalization: numeric
            ? TextCapitalization.none
            : TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: oc.text,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// Records a repayment against a debt. The money really moves, so this posts
/// a real transaction — the outstanding figure is derived from those, never
/// stored, so deleting the repayment in History reconciles the debt too.
class _RepaySheet extends StatefulWidget {
  final AppStore store;
  final Debt debt;
  final String symbol;
  const _RepaySheet({
    required this.store,
    required this.debt,
    required this.symbol,
  });

  @override
  State<_RepaySheet> createState() => _RepaySheetState();
}

class _RepaySheetState extends State<_RepaySheet> {
  final _ctrl = TextEditingController();
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _accountId =
        widget.debt.accountId ??
        (widget.store.accounts.isNotEmpty
            ? widget.store.accounts.first.id
            : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_ctrl.text) ?? 0;
  double get _outstanding => widget.store.outstandingOn(widget.debt);
  bool get _isValid => _amount > 0 && _amount <= _outstanding + 0.005;

  void _save() {
    if (!_isValid) return;
    widget.store.repayDebt(widget.debt, _amount, _accountId);
    Haptics.success();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final d = widget.debt;
    final accounts = widget.store.accounts;
    final over = _amount > _outstanding + 0.005;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  d.theyOweMe ? 'RECORD REPAYMENT' : 'RECORD A PAYMENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${d.person} · ${widget.symbol}${formatAmount(_outstanding)} outstanding',
                  style: TextStyle(fontSize: 12, color: oc.muted),
                ),
              ),
              const SizedBox(height: 20),
              MoneyField(
                controller: _ctrl,
                currencyCode: context.read<SettingsStore>().currencyCode,
                label: 'Repayment amount',
                autofocus: true,
                error: over,
                onChanged: (_) => setState(() {}),
                trailing: TextButton(
                  onPressed: () => setState(
                    () => _ctrl.text = _outstanding.toStringAsFixed(
                      currencyDecimalDigits(
                        context.read<SettingsStore>().currencyCode,
                      ),
                    ),
                  ),
                  child: const Text('Full amount'),
                ),
              ),
              if (over) ...[
                const SizedBox(height: 8),
                Text(
                  'Only ${widget.symbol}${formatAmount(_outstanding)} is outstanding.',
                  style: TextStyle(fontSize: 11, color: ExpndColors.red),
                ),
              ],
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  d.theyOweMe ? 'INTO' : 'FROM',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in accounts)
                      GestureDetector(
                        onTap: () {
                          Haptics.light();
                          setState(() => _accountId = a.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _accountId == a.id
                                ? ExpndColors.gold
                                : oc.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _accountId == a.id
                                  ? ExpndColors.goldDark
                                  : oc.border,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _accountId == a.id
                                  ? ExpndColors.ink
                                  : oc.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              NeoPopButton(
                onPressed: _save,
                enabled: _isValid,
                faceColor: _isValid ? ExpndColors.gold : oc.surface,
                depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
                depth: 4,
                cornerRadius: 6,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Center(
                      child: Text(
                        'RECORD',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: _isValid ? ExpndColors.ink : oc.dimmed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
