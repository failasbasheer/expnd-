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
import '../widgets/neopop.dart';
import '../widgets/neopop_cards.dart';
import 'add_transaction.dart';
import 'transaction_detail.dart';
import 'analytics_view.dart';
import 'wallet_view.dart';
import 'history_view.dart';
import 'profile_view.dart';

enum ExpndTab { dashboard, analytics, wallet, profile }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  ExpndTab _tab = ExpndTab.dashboard;

  // Account whose detail the wallet should open, set when a dashboard account
  // card is tapped. Cleared once the wallet has consumed it.
  String? _walletFocus;

  Transaction? _toast;
  bool _showToast = false;
  // When the just-added expense pushed its category over budget, the toast
  // shows an over-budget warning instead of the usual "Transaction Added".
  ({double limit, double spent, double over})? _toastOverage;

  void _openAccountInWallet(String accountId) {
    debugPrint('[wallet-focus] tapped account id=$accountId');
    setState(() {
      _walletFocus = accountId;
      _tab = ExpndTab.wallet;
    });
  }

  Future<void> _openAdd({Transaction? editing, String? initialText}) async {
    final store = context.read<AppStore>();
    final before = store.transactions.length;
    await showAddTransaction(
      context,
      editing: editing,
      initialText: initialText,
    );
    if (!mounted) return;
    final after = store.transactions.length;
    if (after > before) {
      final added = store.transactions.first;
      setState(() {
        _toast = added;
        _toastOverage = store.categoryBudgetOverage(added);
        _showToast = true;
      });
      // Over-budget toast lingers a touch longer so the warning registers.
      final linger = _toastOverage != null ? 3500 : 2500;
      Future.delayed(Duration(milliseconds: linger), () {
        if (mounted) setState(() => _showToast = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Scaffold(
      backgroundColor: oc.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: _AnimatedTabStack(
              index: _tab.index,
              children: [
                _DashboardView(
                  onAdd: () => _openAdd(),
                  onOpenAccount: _openAccountInWallet,
                ),
                const AnalyticsView(),
                WalletView(
                  focusAccountId: _walletFocus,
                  onFocusConsumed: () {
                    if (_walletFocus != null) {
                      setState(() => _walletFocus = null);
                    }
                  },
                ),
                const ProfileView(),
              ],
            ),
          ),
          // Toast
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            top: _showToast ? MediaQuery.of(context).padding.top + 10 : -120,
            left: 16,
            right: 16,
            child: AnimatedOpacity(
              opacity: _showToast ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: _toast == null
                  ? const SizedBox.shrink()
                  : _ToastBanner(transaction: _toast!, overage: _toastOverage),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _TabBar(
        selected: _tab,
        onSelect: (t) => setState(() => _tab = t),
        onAdd: () => _openAdd(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated tab stack — keeps every tab alive (like IndexedStack) while
// cross-fading + gently rising the newly-selected tab into view.
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedTabStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _AnimatedTabStack({required this.index, required this.children});

  @override
  State<_AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<_AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..value = 1;

  // The tab we're transitioning away from. Kept painted underneath the
  // incoming tab during the animation so the new page rises over the old one
  // instead of over an empty background (which flashed as a dark gap before).
  late int _previousIndex = widget.index;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      // Once the incoming tab is fully opaque, drop the outgoing tab so it
      // isn't needlessly kept alive/painted underneath.
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _previousIndex = old.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    final animating = _controller.status != AnimationStatus.completed;

    Widget layerFor(int i) {
      final isCurrent = i == widget.index;
      final visible = isCurrent || (animating && i == _previousIndex);
      return Offstage(
        // Stable key so the reordering below (current painted last) preserves
        // each tab's element/state instead of swapping it between tabs.
        key: ValueKey(i),
        offstage: !visible,
        // Pause tickers/animations in the inactive tabs so they don't run
        // offstage, while keeping their state (scroll position, etc).
        child: TickerMode(
          enabled: isCurrent,
          child: isCurrent
              ? AnimatedBuilder(
                  animation: anim,
                  child: widget.children[i],
                  builder: (context, child) => Opacity(
                    opacity: anim.value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - anim.value) * 8),
                      child: child,
                    ),
                  ),
                )
              : widget.children[i],
        ),
      );
    }

    // Paint every tab in stable index order, then the current tab last so it
    // sits on top of the outgoing one during the crossfade.
    return Stack(
      children: [
        for (int i = 0; i < widget.children.length; i++)
          if (i != widget.index) layerFor(i),
        layerFor(widget.index),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final ExpndTab selected;
  final ValueChanged<ExpndTab> onSelect;
  final VoidCallback onAdd;
  const _TabBar({
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      color: oc.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(height: 2, color: oc.edge),
              ),
              Row(
                children: [
                  _tabButton(context, 'house.fill', 'HOME', ExpndTab.dashboard),
                  _tabButton(
                    context,
                    'chart.bar.xaxis',
                    'ANALYTICS',
                    ExpndTab.analytics,
                  ),
                  // Gap slot that holds the FAB, so it always sits centered in
                  // the space between the two tab groups instead of overlapping
                  // the WALLET tab.
                  Expanded(
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -14),
                        child: Semantics(
                          button: true,
                          label: 'Add transaction',
                          child: NeoPopButton(
                            onPressed: onAdd,
                            faceColor: ExpndColors.gold,
                            depthColor: ExpndColors.goldDark,
                            // On the near-white light tab bar the gold face
                            // loses its edge; add an ink hairline in light mode
                            // only so the FAB stays the clear primary action.
                            borderColor:
                                Theme.of(context).brightness == Brightness.light
                                    ? ExpndColors.ink.withValues(alpha: 0.85)
                                    : null,
                            depth: 4,
                            cornerRadius: 30,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: Icon(
                                sfIcon('plus'),
                                size: 24,
                                color: ExpndColors.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _tabButton(
                    context,
                    'creditcard.fill',
                    'WALLET',
                    ExpndTab.wallet,
                  ),
                  _tabButton(
                    context,
                    'person.fill',
                    'PROFILE',
                    ExpndTab.profile,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(
    BuildContext context,
    String icon,
    String label,
    ExpndTab tab,
  ) {
    final active = selected == tab;
    final color = active ? context.oc.accent : context.oc.dimmed;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: '$label tab',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.light();
            onSelect(tab);
          },
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: active ? 1.12 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: Icon(sfIcon(icon), size: 19, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  width: active ? 16 : 0,
                  height: 2,
                  color: active ? context.oc.accent : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toast banner
// ─────────────────────────────────────────────────────────────────────────────

class _ToastBanner extends StatelessWidget {
  final Transaction transaction;
  // Non-null when the added expense pushed its category over budget; renders
  // the warning variant instead of the standard confirmation.
  final ({double limit, double spent, double over})? overage;
  const _ToastBanner({required this.transaction, this.overage});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.read<AppStore>();
    final settings = context.read<SettingsStore>();
    if (overage != null) return _overBudget(context, oc, settings);
    final isIncome = transaction.type == TransactionType.income;
    final custom = store.customCategoryFor(transaction.customCategoryId);
    final catColor = custom != null
        ? hexColor(custom.colorHex)
        : transaction.category.color;

    return NeoPopElevated(
      faceColor: isIncome ? ExpndColors.gold : oc.surface,
      depthColor: isIncome ? ExpndColors.goldDark : oc.edge,
      borderColor: isIncome ? ExpndColors.goldDark : oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: custom != null
                  ? Text(custom.emoji, style: const TextStyle(fontSize: 18))
                  : Icon(
                      sfIcon(transaction.category.icon),
                      size: 16,
                      color: isIncome ? ExpndColors.ink : catColor,
                    ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Transaction Added',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isIncome ? ExpndColors.ink : oc.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isIncome ? "+" : "-"}${formatCurrency(transaction.amount, settings.currencyCode)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isIncome
                        ? ExpndColors.ink.withValues(alpha: 0.65)
                        : ExpndColors.red,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              sfIcon(
                isIncome ? 'arrow.up.circle.fill' : 'arrow.down.circle.fill',
              ),
              size: 20,
              color: isIncome
                  ? ExpndColors.ink.withValues(alpha: 0.5)
                  : ExpndColors.red,
            ),
          ],
        ),
      ),
    );
  }

  // Over-budget variant: red-tinted banner naming the category and how far
  // over its monthly limit the spend now is. Purely informational — the
  // transaction was already saved (soft limits).
  Widget _overBudget(
      BuildContext context, ExpndColors oc, SettingsStore settings) {
    final o = overage!;
    final code = settings.currencyCode;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: ExpndColors.red,
      borderColor: ExpndColors.red,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExpndColors.red.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(sfIcon('exclamationmark.triangle.fill'),
                  size: 16, color: ExpndColors.red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Over ${transaction.category.raw} Budget',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: oc.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatCurrency(o.over, code)} over your '
                    '${formatCurrency(o.limit, code)} limit this month',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ExpndColors.red,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardView extends StatefulWidget {
  final VoidCallback onAdd;
  final ValueChanged<String> onOpenAccount;
  const _DashboardView(
      {required this.onAdd, required this.onOpenAccount});

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  TransactionType? _filter;

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  bool get _isCurrentMonth => _sameMonth(_displayMonth, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final code = settings.currencyCode;

    final monthTx = store.transactions
        .where((t) => _sameMonth(t.date, _displayMonth))
        .toList();

    double balance = monthTx
        .where((t) => t.type != TransactionType.transfer)
        .fold(
          0.0,
          (s, t) =>
              s + (t.type == TransactionType.income ? t.amount : -t.amount),
        );
    double income = monthTx
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (s, t) => s + t.amount);
    double expenses = monthTx
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (s, t) => s + t.amount);

    final filtered = _filter == null
        ? monthTx
        : monthTx.where((t) => t.type == _filter).toList();

    final todaySpent = store.transactions
        .where((t) => t.type == TransactionType.expense && _isToday(t.date))
        .fold(0.0, (s, t) => s + t.amount);

    final lastMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    final lastMonthNet = store.transactions
        .where(
          (t) =>
              _sameMonth(t.date, lastMonth) &&
              t.type != TransactionType.transfer,
        )
        .fold(
          0.0,
          (s, t) =>
              s + (t.type == TransactionType.income ? t.amount : -t.amount),
        );

    // Fixed slots keep list positions stable so sections that toggle with the
    // month (today, budget, accounts) collapse/expand smoothly instead of the
    // list snapping to a new height.
    return Container(
      color: oc.bg,
      // The month navigator stays pinned at the top; everything below scrolls
      // beneath it, so the current month is always in view.
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _monthNavigator(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              children: [
                _slot(
                  1,
                  _balanceHero(
                    context,
                    balance,
                    income,
                    expenses,
                    lastMonthNet,
                    code,
                  ),
                ),
                _slot(
                  2,
                  _isCurrentMonth && todaySpent > 0
                      ? _todayRow(context, todaySpent, code)
                      : null,
                ),
                _slot(
                  3,
                  settings.monthlyBudget > 0
                      ? _budgetBar(context, expenses, settings.monthlyBudget, code)
                      : null,
                ),
                _slot(
                  4,
                  store.accounts.isNotEmpty
                      ? _accountsRow(context, store, code)
                      : null,
                ),
                _slot(5, _transactionsCard(context, store, filtered, code)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // One list slot whose height animates as its section appears, disappears, or
  // resizes — keeps the dashboard from snapping on month/filter changes.
  Widget _slot(int index, Widget? child) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: FadeSlideIn(index: index, child: child),
            ),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  // Month navigator
  Widget _monthNavigator(BuildContext context) {
    final oc = context.oc;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(sfIcon('chevron.left'), size: 14, color: oc.accent),
              onPressed: () {
                Haptics.light();
                setState(
                  () => _displayMonth = DateTime(
                    _displayMonth.year,
                    _displayMonth.month - 1,
                  ),
                );
              },
            ),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _monthLabel(_displayMonth),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: oc.text,
                  ),
                ),
                if (_isCurrentMonth)
                  Text(
                    'CURRENT MONTH',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: oc.accent,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                sfIcon('chevron.right'),
                size: 14,
                color: _isCurrentMonth ? oc.dimmed : oc.accent,
              ),
              onPressed: _isCurrentMonth
                  ? null
                  : () {
                      Haptics.light();
                      setState(
                        () => _displayMonth = DateTime(
                          _displayMonth.year,
                          _displayMonth.month + 1,
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  // Balance hero card
  Widget _balanceHero(
    BuildContext context,
    double balance,
    double income,
    double expenses,
    double lastMonthNet,
    String code,
  ) {
    final positive = balance >= 0;
    final bg = positive ? ExpndColors.gold : ExpndColors.red;
    final edge = positive ? ExpndColors.goldDark : ExpndColors.redDark;
    final ink = ExpndColors.ink;

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: edge,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 6),
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: edge, width: 1.5),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: CardGuilloche(color: ink)),
                  Positioned.fill(
                    child: NeoPopShine(color: ink.withValues(alpha: 0.10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'NET BALANCE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                      color: ink.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: balance),
                                      duration: const Duration(
                                        milliseconds: 650,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      builder: (_, value, _) => Text(
                                        formatCurrency(value, code),
                                        style: TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.w900,
                                          color: ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                NeoPopTag(
                                  text: positive ? 'POSITIVE' : 'NEGATIVE',
                                  bg: ink,
                                  fg: bg,
                                ),
                                // Only show a percentage when last month is a
                                // meaningful base — comparing against a near-zero
                                // prior month yields absurd figures (e.g. 5000%).
                                // Below that floor, show a plain direction chip;
                                // and cap the percentage so it never runs away.
                                if (lastMonthNet != 0) ...[
                                  const SizedBox(height: 6),
                                  Builder(
                                    builder: (_) {
                                      final diff = balance - lastMonthNet;
                                      final base = lastMonthNet.abs();
                                      final meaningful =
                                          base >= 1 && base >= balance.abs() * 0.1;
                                      final arrow = diff >= 0 ? '▲' : '▼';
                                      final label = meaningful
                                          ? '$arrow ${((diff / lastMonthNet).abs() * 100).clamp(0, 999).round()}% vs last mo'
                                          : '$arrow vs last mo';
                                      return Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: ink.withValues(alpha: 0.5),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          height: 1,
                          margin: const EdgeInsets.only(bottom: 14),
                          color: ink.withValues(alpha: 0.15),
                        ),
                        Row(
                          children: [
                            _balanceStat(
                              'INCOME',
                              income,
                              'arrow.up',
                              ink,
                              code,
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              color: ink.withValues(alpha: 0.15),
                            ),
                            _balanceStat(
                              'EXPENSES',
                              expenses,
                              'arrow.down',
                              ink,
                              code,
                            ),
                          ],
                        ),
                      ],
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

  Widget _balanceStat(
    String label,
    double amount,
    String icon,
    Color ink,
    String code,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(sfIcon(icon), size: 12, color: ink.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: ink.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatCurrency(amount, code),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _todayRow(BuildContext context, double todaySpent, String code) {
    final oc = context.oc;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(sfIcon('sun.max.fill'), size: 13, color: oc.accent),
            const SizedBox(width: 10),
            Text(
              'TODAY',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: oc.muted,
              ),
            ),
            const Spacer(),
            Text(
              '-${formatCurrency(todaySpent, code)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: ExpndColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _budgetBar(
    BuildContext context,
    double expenses,
    double budget,
    String code,
  ) {
    final oc = context.oc;
    final progress = (expenses / budget).clamp(0.0, 1.0);
    final pct = (progress * 100).toInt();
    final barColor = progress >= 0.9
        ? ExpndColors.red
        : progress >= 0.7
        ? hexColor('EAB308')
        : ExpndColors.green;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'MONTHLY BUDGET',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: oc.muted,
                  ),
                ),
                const Spacer(),
                Text(
                  '$pct% used',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: barColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'of ${formatCurrency(budget, code)}',
                  style: TextStyle(fontSize: 9, color: oc.dimmed),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRect(
              child: LayoutBuilder(
                builder: (context, c) {
                  return Stack(
                    children: [
                      Container(height: 6, color: oc.border),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, _) => Container(
                          height: 6,
                          width: c.maxWidth * value,
                          color: barColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountsRow(BuildContext context, AppStore store, String code) {
    final oc = context.oc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACCOUNTS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: oc.muted,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: store.accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final acc = store.accounts[i];
              final total = store.balanceFor(acc);
              final accColor = hexColor(acc.colorHex);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.light();
                  widget.onOpenAccount(acc.id);
                },
                child: NeoPopElevated(
                faceColor: oc.surface,
                depthColor: accColor.withValues(alpha: 0.5),
                borderColor: accColor.withValues(alpha: 0.4),
                depth: 3,
                cornerRadius: 6,
                child: Container(
                  width: 172,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            sfIcon(acc.type.icon),
                            size: 11,
                            color: accColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            // Common account names ("Chase Checking") were
                            // clipping mid-word — shrink to fit one line before
                            // ellipsizing so the full name shows when it can.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                acc.name,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                  color: oc.text,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency(total, code),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: oc.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ));
            },
          ),
        ),
      ],
    );
  }

  Widget _transactionsCard(
    BuildContext context,
    AppStore store,
    List<Transaction> filtered,
    String code,
  ) {
    final oc = context.oc;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  'TRANSACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ExpndColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: ExpndColors.goldDark.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${filtered.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: oc.accent,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Haptics.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: oc.bg,
                          body: SafeArea(
                            bottom: false,
                            child: const HistoryView(),
                          ),
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        'SEE ALL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: oc.accent,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(sfIcon('chevron.right'), size: 11, color: oc.accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                _filterTab(context, 'ALL', null),
                const SizedBox(width: 8),
                _filterTab(context, 'INCOME', TransactionType.income),
                const SizedBox(width: 8),
                _filterTab(context, 'EXPENSE', TransactionType.expense),
              ],
            ),
          ),
          Container(height: 1, color: oc.border),
          // Filtering (ALL/INCOME/EXPENSE) swaps the row set — animate the
          // height so the card grows/shrinks smoothly instead of snapping.
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              key: ValueKey(_filter),
              children: [
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 50),
                    child: Column(
                      children: [
                        Icon(sfIcon('tray'), size: 36, color: oc.dimmed),
                        const SizedBox(height: 10),
                        Text(
                          'No transactions this month',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: oc.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap + to add your first one',
                          style: TextStyle(fontSize: 12, color: oc.dimmed),
                        ),
                      ],
                    ),
                  )
                else
                  for (int i = 0; i < filtered.length; i++) ...[
                    Dismissible(
                      key: ValueKey(filtered[i].id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: ExpndColors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(sfIcon('trash'), color: Colors.white),
                      ),
                      onDismissed: (_) => store.deleteTransaction(filtered[i]),
                      child: TransactionRow(
                        transaction: filtered[i],
                        currencyCode: code,
                        onTap: () => showTransactionDetail(context, filtered[i]),
                      ),
                    ),
                    if (i != filtered.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 66),
                        child: Container(height: 1, color: oc.border),
                      ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterTab(
    BuildContext context,
    String label,
    TransactionType? value,
  ) {
    final oc = context.oc;
    final active = _filter == value;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _filter = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ExpndColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? ExpndColors.goldDark : oc.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: active ? ExpndColors.ink : oc.muted,
          ),
        ),
      ),
    );
  }

  String _monthLabel(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction row (shared)
// ─────────────────────────────────────────────────────────────────────────────

class TransactionRow extends StatelessWidget {
  final Transaction transaction;
  final String currencyCode;
  final VoidCallback? onTap;
  const TransactionRow({
    super.key,
    required this.transaction,
    required this.currencyCode,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.read<AppStore>();
    final custom = store.customCategoryFor(transaction.customCategoryId);
    final account = store.accountFor(transaction.accountId);
    final toAccount = store.accountFor(transaction.toAccountId);
    final isTransfer = transaction.type == TransactionType.transfer;
    final isIncome = transaction.type == TransactionType.income;

    final rowColor = isTransfer
        ? ExpndColors.gold
        : custom != null
        ? hexColor(custom.colorHex)
        : transaction.category.color;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: oc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rowColor.withValues(alpha: 0.12),
                // neoPOP transaction cell uses a square logo tile.
                border: Border.all(
                  color: rowColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: isTransfer
                  ? Icon(
                      sfIcon('arrow.left.arrow.right'),
                      size: 16,
                      color: oc.accent,
                    )
                  : custom != null
                  ? Text(custom.emoji, style: const TextStyle(fontSize: 20))
                  : Icon(
                      sfIcon(transaction.category.icon),
                      size: 16,
                      color: transaction.category.color,
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
                        : (custom?.name ?? transaction.category.raw),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: oc.text,
                    ),
                  ),
                  if (transaction.note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      transaction.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: oc.dimmed),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _dateLabel(transaction.date),
                        style: TextStyle(fontSize: 11, color: oc.dimmed),
                      ),
                      if (transaction.isRecurring) ...[
                        const SizedBox(width: 6),
                        Icon(sfIcon('repeat'), size: 9, color: oc.accent),
                      ],
                      if (account != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: hexColor(account.colorHex),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          account.name,
                          style: TextStyle(fontSize: 10, color: oc.dimmed),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (transaction.photoPath != null &&
                File(transaction.photoPath!).existsSync())
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.file(
                    File(transaction.photoPath!),
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isTransfer
                      ? formatCurrency(transaction.amount, currencyCode)
                      : '${isIncome ? "+" : "-"}${formatCurrency(transaction.amount, currencyCode)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isTransfer
                        ? ExpndColors.gold
                        : isIncome
                        ? ExpndColors.green
                        : ExpndColors.red,
                  ),
                ),
                const SizedBox(width: 3),
                // Direction arrow, mirroring the neoPOP transaction cell.
                Icon(
                  isTransfer
                      ? sfIcon('arrow.left.arrow.right')
                      : isIncome
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 15,
                  color: isTransfer
                      ? ExpndColors.gold
                      : isIncome
                      ? ExpndColors.green
                      : ExpndColors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
