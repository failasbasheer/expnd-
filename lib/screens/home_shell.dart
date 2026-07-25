import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/insights.dart';
import '../services/upcoming.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/animations.dart';
import '../widgets/app_header.dart';
import '../widgets/neopop.dart';
import '../widgets/neopop_cards.dart';
import '../widgets/privacy_eye.dart';
import 'add_transaction.dart';
import 'transaction_detail.dart';
import 'analytics_view.dart';
import 'wallet_view.dart';
import 'history_view.dart';
import 'plan_view.dart';
import 'settings_view.dart';
import 'upcoming_view.dart';

enum ExpndTab { dashboard, analytics, wallet, plan }

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
  // Recurring transactions auto-posted during boot. Takes over the toast slot
  // on first frame so the balance never moves without an explanation.
  List<Transaction>? _recurringPosted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showRecurringNotice());
  }

  void _showRecurringNotice() {
    if (!mounted) return;
    final posted = context.read<AppStore>().takeRecurringNotice();
    if (posted.isEmpty) return;
    setState(() {
      _recurringPosted = posted;
      _showToast = true;
    });
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  void _openAccountInWallet(String accountId) {
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
        _toastOverage = store.categoryBudgetOverage(
          added,
          rollover: context.read<SettingsStore>().budgetRollover,
        );
        _recurringPosted = null; // the new transaction owns the toast now
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
      // The tab bar is translucent, so the body has to run underneath it —
      // otherwise there is nothing behind the glass to blur and it just reads
      // as a flat tint. Tab screens reserve the bar's height via
      // [ExpndSpacing.scrollBottomUnderTabBar], which Scaffold reports to the
      // body as MediaQuery.padding.bottom.
      extendBody: true,
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
                  onOpenPlan: () => setState(() => _tab = ExpndTab.plan),
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
                const PlanView(),
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
              child: _recurringPosted != null
                  ? _RecurringToast(
                      posted: _recurringPosted!,
                      onTap: () {
                        setState(() => _showToast = false);
                        showUpcoming(context);
                      },
                    )
                  : _toast == null
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
    final light = Theme.of(context).brightness == Brightness.light;
    // A translucent plate rather than a full glassmorphic restyle: the bar
    // keeps its square corners and hard 2px top edge, and only the fill
    // becomes a material that scrolled content blurs through. The FAB stays
    // solid — a see-through primary action reads as broken.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // Positioned.fill matches the bar's laid-out size exactly, and
        // ClipRect keeps the blur from bleeding past it. The FAB lives in the
        // content layer above this one, so it is never clipped and can still
        // sit proud of the bar.
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(
                // Light mode blurs near-white content under a near-white
                // surface, so the plate has to stay thin enough for the warmer
                // page bg and any colour underneath to tint through — opaque
                // white would read as flat paint, not glass.
                color: oc.surface.withValues(alpha: light ? 0.62 : 0.60),
              ),
            ),
          ),
        ),
        SafeArea(
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
                    _tabButton(
                      context,
                      'house.fill',
                      'HOME',
                      ExpndTab.dashboard,
                    ),
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
                                  Theme.of(context).brightness ==
                                      Brightness.light
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
                    _tabButton(context, 'target', 'PLAN', ExpndTab.plan),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabButton(
    BuildContext context,
    String icon,
    String label,
    ExpndTab tab,
  ) {
    final active = selected == tab;
    // Inactive uses `muted` (#8A8A8A, ~AA on the bar), not `dimmed` (#5A5A5A,
    // ~3:1) — the label is small, so it needs the extra contrast to stay legible.
    final color = active ? context.oc.accent : context.oc.muted;
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
                // Tab labels are chrome inside a fixed-height (64pt) bar, so
                // they don't scale with Dynamic Type — otherwise a large system
                // text size overflows the bar. 10pt reads clearly on its own.
                MediaQuery.withNoTextScaling(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: color,
                    ),
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
    BuildContext context,
    ExpndColors oc,
    SettingsStore settings,
  ) {
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
              child: Icon(
                sfIcon('exclamationmark.triangle.fill'),
                size: 16,
                color: ExpndColors.red,
              ),
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

/// Tells the user that recurring transactions posted themselves on launch.
/// Without this the balance simply changes between sessions with no account of
/// why. Tapping opens Upcoming, so the next ones are no longer a surprise.
class _RecurringToast extends StatelessWidget {
  final List<Transaction> posted;
  final VoidCallback onTap;
  const _RecurringToast({required this.posted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final code = context.read<SettingsStore>().currencyCode;
    final net = posted.fold<double>(
      0,
      (s, t) =>
          s +
          (t.type == TransactionType.income
              ? t.amount
              : t.type == TransactionType.expense
              ? -t.amount
              : 0),
    );
    final names = posted
        .map((t) => t.note.trim().isNotEmpty ? t.note.trim() : t.category.raw)
        .toSet()
        .toList();
    final shown = names.take(3).join(', ');
    final extra = names.length > 3 ? ' +${names.length - 3} more' : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: NeoPopElevated(
        faceColor: oc.surface,
        depthColor: oc.edge,
        borderColor: oc.border,
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
                  color: ExpndColors.gold.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(sfIcon('repeat'), size: 16, color: oc.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${posted.length} recurring '
                      '${posted.length == 1 ? "transaction" : "transactions"} '
                      'posted',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: oc.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$shown$extra · '
                      '${net < 0 ? "−" : "+"}${formatCurrency(net.abs(), code)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: net < 0 ? ExpndColors.red : ExpndColors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(sfIcon('chevron.right'), size: 14, color: oc.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard identity — the greeting, and the wordmark it hands back to
// ─────────────────────────────────────────────────────────────────────────────

/// Greets you once a day, then gets out of the way.
///
/// The first time the dashboard is built on a new calendar day it shows "GOOD
/// MORNING / `name`"; a few seconds later that retires into the EXPND wordmark,
/// and every later open the same day starts there. Deliberately not a
/// permanent fixture: a greeting you see twenty times a day stops reading as
/// one, and it would be the first thing in the way every time you tabbed home.
///
/// Both states stay mounted in a [Stack] so the row keeps a single height —
/// the balance card below must not jump when the greeting hands over.
class _GreetingIdentity extends StatefulWidget {
  const _GreetingIdentity();

  @override
  State<_GreetingIdentity> createState() => _GreetingIdentityState();
}

class _GreetingIdentityState extends State<_GreetingIdentity> {
  /// Long enough to read a name, short enough that it's gone before you've
  /// finished taking in the balance.
  static const _hold = Duration(milliseconds: 4000);
  static const _handover = Duration(milliseconds: 450);

  bool _greeting = false;
  Timer? _timer;

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsStore>();
    final today = _dayKey(DateTime.now());
    if (settings.lastGreetedDay == today) return;

    _greeting = true;
    // Stamped after the frame, not here: the setter notifies listeners, and
    // initState runs mid-build. Stamping on *show* rather than on hand-over
    // means a relaunch two seconds later doesn't earn a second greeting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsStore>().lastGreetedDay = today;
    });
    _timer = Timer(_hold, () {
      if (mounted) setState(() => _greeting = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _salutation {
    final h = DateTime.now().hour;
    if (h < 12) return 'GOOD MORNING';
    if (h < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final name = context.watch<SettingsStore>().userName.trim();
    // 'Your Name' is the placeholder the setup screen ships with — greeting
    // someone by it would be worse than not naming them at all.
    final named = name.isNotEmpty && name != 'Your Name';

    return Stack(
      children: [
        // Laid out whether or not it's visible, so the taller of the two fixes
        // the row height for good.
        _phase(
          visible: _greeting,
          rise: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _salutation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: named ? 10 : 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: named ? oc.accent : oc.text,
                ),
              ),
              if (named) ...[
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: oc.text,
                  ),
                ),
              ],
            ],
          ),
        ),
        _phase(
          visible: !_greeting,
          rise: false,
          child: const HeaderTitle(icon: 'house.fill', title: 'EXPND'),
        ),
      ],
    );
  }

  /// One of the two states, fading and sliding a little as it takes or gives
  /// up the row. [rise] sends it upward on the way out (the greeting leaving);
  /// the wordmark comes up from below to replace it.
  Widget _phase({
    required bool visible,
    required bool rise,
    required Widget child,
  }) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: _handover,
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : Offset(0, rise ? -0.35 : 0.35),
          duration: _handover,
          curve: Curves.easeOut,
          child: ExcludeSemantics(excluding: !visible, child: child),
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

  /// Budgets are owned by the PLAN tab, so the dashboard's budget bar hands off
  /// there rather than duplicating the controls.
  final VoidCallback onOpenPlan;
  const _DashboardView({
    required this.onAdd,
    required this.onOpenAccount,
    required this.onOpenPlan,
  });

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

    // Projected forward from today regardless of which month is on screen; the
    // card that renders it is hidden unless the current month is showing.
    final upcoming = projectUpcoming(store);

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
      // The header stays pinned at the top; everything below scrolls beneath
      // it, so the current month is always in view.
      child: Column(
        children: [
          _header(context, upcoming.length),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                ExpndSpacing.scrollBottomUnderTabBar(context),
              ),
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
                      ? _budgetBar(
                          context,
                          expenses,
                          settings.budgetRollover
                              ? store.rolledOverLimit(
                                  settings.monthlyBudget,
                                  _displayMonth,
                                )
                              : settings.monthlyBudget,
                          code,
                        )
                      : null,
                ),
                // Forward-looking, so it only belongs on the current month —
                // it would be nonsense sitting under a past month's figures.
                _slot(
                  4,
                  _isCurrentMonth && upcoming.isNotEmpty
                      ? _upcomingCard(context, store, upcoming, code)
                      : null,
                ),
                // Only for the month you're actually in: an insight is a
                // read on where things stand now, not a history lesson.
                _slot(
                  5,
                  _isCurrentMonth ? _insightsStrip(context, store, code) : null,
                ),
                _slot(
                  6,
                  store.accounts.isNotEmpty
                      ? _accountsRow(context, store, code)
                      : null,
                ),
                _slot(7, _transactionsCard(context, store, filtered, code)),
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

  // Dashboard header: identity row (greeting or wordmark) over the month strip.
  Widget _header(BuildContext context, int upcomingCount) {
    final oc = context.oc;
    return ExpndHeader(
      leading: const _GreetingIdentity(),
      actions: [
        HeaderAction.custom(
          semanticLabel: 'Hide or show amounts',
          // Lifted out of the gold balance card, where a piece of chrome had
          // been wedged in beside the NET BALANCE label.
          child: PrivacyEyeButton(
            color: oc.muted,
            size: 15,
            padding: const EdgeInsets.all(10),
          ),
        ),
        // No calendar button here: the Upcoming card in the body opens the
        // same screen from its "VIEW ALL" row, and does it with the count and
        // committed total already in view. Two doors to one room is what made
        // this bar feel busy.
        const SettingsAvatarAction(),
      ],
      below: _monthStrip(context),
    );
  }

  void _shiftMonth(int by) {
    Haptics.light();
    setState(
      () => _displayMonth = DateTime(
        _displayMonth.year,
        _displayMonth.month + by,
      ),
    );
  }

  /// The month switcher, flattened.
  ///
  /// It used to be an elevated neoPOP block — the same visual weight as the
  /// balance hero directly under it — with two 48pt [IconButton]s and a pair of
  /// [Spacer]s around a 14pt label, so most of that bar was empty. Navigation
  /// is chrome; it shouldn't compete with the figures for hierarchy. The old
  /// "CURRENT MONTH" caption is gone too: it only ever appeared when the right
  /// chevron was already disabled, which said the same thing twice. In its
  /// place, a NOW tag that appears only when you're *off* the current month and
  /// jumps you back in one tap instead of a run of chevron presses.
  Widget _monthStrip(BuildContext context) {
    final oc = context.oc;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          _monthArrow(oc, 'chevron.left', () => _shiftMonth(-1)),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // Uppercased here rather than in _monthLabel: as a bare
                      // row sitting under the EXPND wordmark it now reads as a
                      // header label, and every other label at this level of
                      // the design is caps.
                      _monthLabel(_displayMonth).toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: oc.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isCurrentMonth)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: oc.accent,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Haptics.light();
                          final now = DateTime.now();
                          setState(
                            () => _displayMonth = DateTime(now.year, now.month),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: ExpndColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: ExpndColors.goldDark.withValues(
                                alpha: 0.4,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'NOW',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: oc.accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _monthArrow(
            oc,
            'chevron.right',
            _isCurrentMonth ? null : () => _shiftMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _monthArrow(ExpndColors oc, String icon, VoidCallback? onTap) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: icon == 'chevron.left' ? 'Previous month' : 'Next month',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 34,
          child: Icon(
            sfIcon(icon),
            size: 15,
            color: onTap == null ? oc.dimmed : oc.accent,
          ),
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
      // Back to 200 now the privacy eye has moved up into the header: the label
      // row is a bare line of text again, so the 14px this card was carrying
      // for the eye's tap padding is dead space.
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
                                    // Month-scoped flow (income − expense for the
                                    // selected month), not money on hand — the
                                    // wallet owns "NET WORTH". Naming it "…THIS
                                    // MONTH" keeps the two from reading as rivals.
                                    'NET THIS MONTH',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                                          base >= 1 &&
                                          base >= balance.abs() * 0.1;
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
                            // Each stat scales down within its half rather than
                            // pushing the row past its edge when the figures are
                            // large or the text size is raised.
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _balanceStat(
                                  'INCOME',
                                  income,
                                  'arrow.up',
                                  ink,
                                  code,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              color: ink.withValues(alpha: 0.15),
                            ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _balanceStat(
                                  'EXPENSES',
                                  expenses,
                                  'arrow.down',
                                  ink,
                                  code,
                                ),
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
    final today = DateTime.now();
    return Semantics(
      button: true,
      label: "Today's spending, opens history for today",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The row states a figure without showing what makes it up. Open
        // history already narrowed to today so the tap answers "spent on what?"
        // instead of dropping you in the full list to filter it yourself.
        onTap: () {
          Haptics.light();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: oc.bg,
                body: SafeArea(
                  bottom: false,
                  child: HistoryView(
                    initialStartDate: today,
                    initialEndDate: today,
                  ),
                ),
              ),
            ),
          );
        },
        child: NeoPopElevated(
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
                const SizedBox(width: 8),
                Icon(sfIcon('chevron.right'), size: 11, color: oc.dimmed),
              ],
            ),
          ),
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
    return Semantics(
      button: true,
      label: 'Monthly budget, $pct percent used. Opens budgets in Plan',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Reporting the budget invites changing it, and every budget control
        // lives on PLAN. Switch tabs rather than growing a second set here.
        onTap: () {
          Haptics.light();
          widget.onOpenPlan();
        },
        child: NeoPopElevated(
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
                    // Flexible (no Spacer): the label takes the room the values
                    // leave, so it shows in full instead of clipping to
                    // "MONTHLY BU…". Both flexible ends shrink under extreme
                    // widths/text sizes so the row never overflows.
                    Flexible(
                      child: Text(
                        'MONTHLY BUDGET',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: oc.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$pct% used',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: barColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // No chevron here, unlike the TODAY row: the whole card is
                    // the target. The limit gives (ellipsizes) before the label
                    // does when space is tight.
                    Flexible(
                      child: Text(
                        'of ${formatCurrency(budget, code)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: oc.dimmed),
                      ),
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
        ),
      ),
    );
  }

  // A preview of what's coming: the committed total plus the three nearest
  // movements, with the full timeline a tap away.
  Widget _upcomingCard(
    BuildContext context,
    AppStore store,
    List<UpcomingItem> upcoming,
    String code,
  ) {
    final oc = context.oc;
    final summary = summarizeUpcoming(store, upcoming);
    final preview = upcoming.take(3).toList();

    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Text(
                  'UPCOMING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
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
                    '${upcoming.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: oc.accent,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${kUpcomingHorizonDays}D',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: oc.dimmed,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'COMMITTED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: oc.muted,
                    ),
                  ),
                ),
                Text(
                  formatCurrency(summary.committedOutflows, code),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: oc.text,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: oc.border),
          for (var i = 0; i < preview.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(height: 1, color: oc.border),
              ),
            UpcomingRow(item: preview[i], code: code, dense: true),
          ],
          Container(height: 1, color: oc.border),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.light();
              showUpcoming(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    upcoming.length > preview.length
                        ? 'VIEW ALL ${upcoming.length}'
                        : 'VIEW ALL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: oc.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(sfIcon('chevron.right'), size: 11, color: oc.accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountsRow(BuildContext context, AppStore store, String code) {
    final oc = context.oc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
            const Spacer(),
            // The row scrolls horizontally; with two cards filling the width
            // there's no hint more exist. A count + chevron says "swipe for the
            // rest" so off-screen accounts aren't missed.
            if (store.accounts.length > 2) ...[
              Text(
                '${store.accounts.length} accounts',
                style: TextStyle(fontSize: 9, color: oc.dimmed),
              ),
              const SizedBox(width: 2),
              Icon(sfIcon('chevron.right'), size: 9, color: oc.dimmed),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
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
                    // Narrow enough that a third card peeks past the screen edge
                    // when there are more than two — reinforcing the swipe hint.
                    width: 158,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// A few sentences about where the money is going.
  ///
  /// The app was collecting budgets, categories, recurring rules and 30-day
  /// projections and never saying a word about any of it — charts show data,
  /// they don't tell you what happened. Every line here is arithmetic over
  /// what's already stored, so each one traces to a figure the user can go
  /// and check.
  Widget? _insightsStrip(BuildContext context, AppStore store, String code) {
    final oc = context.oc;
    final settings = context.watch<SettingsStore>();
    final insights = buildInsights(
      store,
      code,
      monthlyBudget: settings.monthlyBudget,
    );
    if (insights.isEmpty) return null;
    final shown = insights.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'WHAT CHANGED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: oc.muted,
            ),
          ),
        ),
        for (int i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _insightCard(oc, shown[i]),
        ],
      ],
    );
  }

  Widget _insightCard(ExpndColors oc, Insight insight) {
    final tint = switch (insight.tone) {
      InsightTone.good => ExpndColors.green,
      InsightTone.warn => ExpndColors.red,
      InsightTone.neutral => oc.accent,
    };
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: tint.withValues(alpha: 0.35),
      depth: 3,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(sfIcon(insight.icon), size: 14, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    insight.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: oc.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    insight.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: oc.muted,
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
                Flexible(
                  child: Text(
                    'TRANSACTIONS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: oc.muted,
                    ),
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
                Expanded(child: _filterTab(context, 'ALL', null)),
                const SizedBox(width: 8),
                Expanded(
                  child: _filterTab(context, 'INCOME', TransactionType.income),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _filterTab(
                    context,
                    'EXPENSE',
                    TransactionType.expense,
                  ),
                ),
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
                        onTap: () =>
                            showTransactionDetail(context, filtered[i]),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                      // Both flexible so the row can never overflow, but the
                      // date is biased to win (flex 3 vs 2): a long account name
                      // ellipsizes first, and the short date stays whole. The
                      // old 50/50 (both plain Flexible) clipped the date too.
                      Flexible(
                        flex: 3,
                        child: Text(
                          _dateLabel(transaction.date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: oc.dimmed),
                        ),
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
                        Flexible(
                          flex: 2,
                          child: Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: oc.dimmed),
                          ),
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
            // Scale a very large amount down to fit rather than overflow the row
            // on a narrow phone at a bumped-up text size.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
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
              ),
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
    // Drop the year for the current year — in a "recent" list it's redundant,
    // and it clears space so the date never clips to "Jul 25, 20…" in a row
    // that also carries an amount and an account name.
    final label = '${months[d.month - 1]} ${d.day}';
    return d.year == DateTime.now().year ? label : '$label, ${d.year}';
  }
}
