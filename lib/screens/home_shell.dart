import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/receipts.dart';
import '../services/cash_flow.dart';
import '../services/apple_intelligence.dart';
import '../services/insights.dart';
import '../services/upcoming.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/glass_header.dart';
import '../widgets/app_header.dart';
import '../widgets/neopop.dart';
import '../widgets/neopop_cards.dart';
import '../widgets/privacy_eye.dart';
import '../widgets/segmented_picker.dart';
import 'add_transaction.dart';
import 'capture_inbox_view.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showRecurringNotice());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // AppRoot posts due recurring rows on resume; explain them here too.
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showRecurringNotice(),
      );
    }
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
    // Android back on a secondary tab returns to Home instead of leaving the
    // app; only Home lets the system back gesture close the activity.
    return PopScope(
      canPop: _tab == ExpndTab.dashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) setState(() => _tab = ExpndTab.dashboard);
      },
      child: Scaffold(
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
              // Glass headers extend under the status bar themselves.
              top: !ExpndGlass.enabled,
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
                    : _ToastBanner(
                        transaction: _toast!,
                        overage: _toastOverage,
                      ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _TabBar(
          selected: _tab,
          onSelect: (t) => setState(() => _tab = t),
          onAdd: () => _openAdd(),
        ),
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

  // Created once: building a new CurvedAnimation every frame leaked a
  // listener on [_controller] per build.
  late final CurvedAnimation _anim = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

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
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final anim = _anim;
    final animating =
        !reduceMotion && _controller.status != AnimationStatus.completed;

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
          // Every tab gets the same wrapper shape whether or not it's the
          // current one. Swapping AnimatedBuilder in only for the current tab
          // changed the subtree type on each switch, which threw away the
          // tab's state (scroll, filters, Wallet focus) and replayed its
          // entrance animations.
          child: AnimatedBuilder(
            animation: anim,
            child: widget.children[i],
            builder: (context, child) {
              final t = isCurrent && !reduceMotion ? anim.value : 1.0;
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 8),
                  child: child,
                ),
              );
            },
          ),
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
    final glass = ExpndGlass.translucent(context);
    // The NeoPOP bar from 1.0: square plate, hard 2px top edge, caps labels
    // and the raised gold FAB. Only the fill is glass. The blur sits in its
    // own clipped layer underneath so the FAB, which stands proud of the bar,
    // is never clipped; the FAB itself stays solid — a see-through primary
    // action reads as broken.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: glass
              ? ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: ExpndGlass.blur,
                      sigmaY: ExpndGlass.blur,
                    ),
                    child: ColoredBox(
                      color: oc.surface.withValues(
                        alpha: ExpndGlass.tint(oc.brightness),
                      ),
                    ),
                  ),
                )
              : ColoredBox(color: oc.surface),
        ),
        SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
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
                    // Gap slot that holds the FAB, so it always sits centered
                    // between the two tab groups instead of overlapping WALLET.
                    Expanded(
                      child: Center(
                        child: Transform.translate(
                          offset: const Offset(0, -14),
                          child: Tooltip(
                            message: 'Add transaction',
                            child: Semantics(
                              button: true,
                              label: 'Add transaction',
                              onTap: onAdd,
                              excludeSemantics: true,
                              child: NeoPopButton(
                                onPressed: () {
                                  Haptics.medium();
                                  onAdd();
                                },
                                faceColor: ExpndColors.gold,
                                depthColor: ExpndColors.goldDark,
                                // Same language as the balance card: a rounded
                                // gold face with a gold-dark rim and a short
                                // offset edge, rather than a hard-inked circle.
                                borderColor: ExpndColors.goldDark,
                                depth: 4,
                                cornerRadius: 18,
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
    // Inactive uses `muted`, not `dimmed` — the label is small, so it needs
    // the extra contrast to stay legible.
    final color = active ? context.oc.accent : context.oc.muted;
    final name = label[0] + label.substring(1).toLowerCase();
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        // Read as "Home tab", not letter-spaced caps.
        label: '$name tab',
        onTap: () => onSelect(tab),
        excludeSemantics: true,
        child: _TabPress(
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
                // Labels are chrome inside a fixed 64pt bar, so they don't
                // scale with Dynamic Type — a large text size would overflow
                // the bar. 10pt bold caps reads clearly on its own.
                MediaQuery.withNoTextScaling(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// iOS-style tab press: the item dips slightly while held instead of the
/// Material ink highlight, which painted a grey slab over the whole cell.
class _TabPress extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TabPress({required this.onTap, required this.child});

  @override
  State<_TabPress> createState() => _TabPressState();
}

class _TabPressState extends State<_TabPress> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.7 : 1,
          duration: const Duration(milliseconds: 110),
          child: widget.child,
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
      depth: 0,
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
                    fontWeight: FontWeight.w700,
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
      depth: 0,
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
                      fontWeight: FontWeight.w700,
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
/// Dashboard prompt for amounts captured from a widget or Siri that haven't
/// been categorised yet. Deliberately understated: these are already logged
/// and safe, they just aren't in the balances until the user says what they
/// were.
class _CaptureInboxBanner extends StatelessWidget {
  final int count;
  const _CaptureInboxBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        showCaptureInbox(context);
      },
      child: NeoPopElevated(
        faceColor: oc.surface,
        depthColor: oc.edge,
        borderColor: oc.border,
        depth: 0,
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
                child: Icon(sfIcon('tray'), size: 16, color: oc.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count quick ${count == 1 ? "capture" : "captures"} '
                      'to file',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: oc.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Not in your balances yet — tap to categorise',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: oc.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(sfIcon('chevron.right'), size: 13, color: oc.muted),
            ],
          ),
        ),
      ),
    );
  }
}

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
        depth: 0,
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
                        fontWeight: FontWeight.w700,
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
          child: const HeaderTitle(title: 'EXPND'),
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

  BoxDecoration _panelDecoration(ExpndColors oc, {Color? borderColor}) {
    return BoxDecoration(
      color: oc.surface,
      borderRadius: BorderRadius.circular(ExpndRadius.card),
      border: Border.all(color: borderColor ?? oc.border),
    );
  }

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
      child: GlassHeaderLayout(
        header: _header(context, upcoming.length),
        collapsedHeader: _compactHeader(context),
        body: (context, top) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16 + top,
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
              settings.monthlyBudget > 0 &&
                      (settings.budgetCycle == 'calendar' || _isCurrentMonth)
                  ? _budgetBar(
                      context,
                      settings.budgetCycle == 'calendar'
                          ? expenses
                          : budgetSpentInPeriod(
                              store,
                              budgetPeriodFor(settings, DateTime.now()),
                            ),
                      settings.budgetCycle == 'calendar' &&
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
            // Last, not first: captures are a small housekeeping chore,
            // and putting them above the balance would make every widget
            // tap feel like an error to be cleared.
            _slot(
              8,
              _isCurrentMonth && store.pendingCaptures.isNotEmpty
                  ? _CaptureInboxBanner(count: store.pendingCaptures.length)
                  : null,
            ),
          ],
        ),
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
          : Padding(padding: const EdgeInsets.only(bottom: 20), child: child),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  // Page title and month navigation share the header system used by every tab.
  Widget _header(BuildContext context, int upcomingCount) {
    final oc = context.oc;
    return ExpndHeader(
      leading: const _GreetingIdentity(),
      actions: [
        HeaderAction.custom(
          semanticLabel: 'Hide or show amounts',
          child: PrivacyEyeButton(
            color: oc.muted,
            size: 19,
            padding: const EdgeInsets.all(12.5),
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

  /// The bar once you scroll: the month becomes the title next to the same
  /// actions, and the separate greeting and month strip fold away.
  Widget _compactHeader(BuildContext context) {
    final oc = context.oc;
    return ExpndHeader(
      title: _monthLabel(_displayMonth),
      actions: [
        HeaderAction.custom(
          semanticLabel: 'Hide or show amounts',
          child: PrivacyEyeButton(
            color: oc.muted,
            size: 19,
            padding: const EdgeInsets.all(12.5),
          ),
        ),
        const SettingsAvatarAction(),
      ],
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

  /// The 1.0 month strip: spaced caps between gold chevrons, a dot when on
  /// the current month and a NOW tag to jump back when you're not.
  Widget _monthStrip(BuildContext context) {
    final oc = context.oc;
    return SizedBox(
      height: 44,
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
                      Semantics(
                        button: true,
                        label: 'Back to this month',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Haptics.light();
                            final now = DateTime.now();
                            setState(
                              () =>
                                  _displayMonth = DateTime(now.year, now.month),
                            );
                          },
                          child: Padding(
                            // Pads the small tag out to a fair tap target.
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 44,
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
    final oc = context.oc;
    final positive = balance >= 0;
    final ink = positive ? ExpndColors.ink : oc.text;

    // The NeoPOP slab from 1.0: a solid edge block offset down-right under
    // the face, so the hero reads as a raised card rather than a flat panel.
    final edge = positive ? ExpndColors.goldDark : oc.edge;
    return SizedBox(
      height: 196,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: edge,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 6),
            child: _balanceFace(context, positive, ink, balance, income,
                expenses, lastMonthNet, code),
          ),
        ],
      ),
    );
  }

  Widget _balanceFace(
    BuildContext context,
    bool positive,
    Color ink,
    double balance,
    double income,
    double expenses,
    double lastMonthNet,
    String code,
  ) {
    final oc = context.oc;
    return Container(
      height: 190,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: positive ? ExpndColors.gold : oc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: positive ? ExpndColors.goldDark : oc.border,
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          if (positive) Positioned.fill(child: CardGuilloche(color: ink)),
          if (!positive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(height: 3, color: oc.negative),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Label and trend split the row two ways and each shrinks
                    // only on a very narrow screen. (Flexible + Spacer +
                    // Flexible split it three ways and clipped the label to
                    // "NET THIS M…".)
                    Flexible(
                      child: Text(
                        'NET THIS MONTH',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: ink.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // The trend is relative, but it still gives away how the
                    // hidden figures moved, so it hides with them.
                    if (lastMonthNet != 0 && !AmountPrivacy.hidden)
                      Builder(
                        builder: (_) {
                          final diff = balance - lastMonthNet;
                          final base = lastMonthNet.abs();
                          final meaningful =
                              base >= 1 && base >= balance.abs() * 0.1;
                          final arrow = diff >= 0 ? '↑' : '↓';
                          final label = meaningful
                              ? '$arrow ${((diff / lastMonthNet).abs() * 100).clamp(0, 999).round()}% from last month'
                              : '$arrow from last month';
                          return Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                label,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ink.withValues(alpha: 0.62),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: balance),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, _) => Text(
                          formatCurrency(value, code),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.2,
                            color: positive ? ink : oc.negative,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.only(bottom: 14),
                  color: ink.withValues(alpha: 0.16),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _balanceStat(
                        'INCOME',
                        income,
                        'arrow.up',
                        ink,
                        code,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: ink.withValues(alpha: 0.16),
                    ),
                    Expanded(
                      child: _balanceStat(
                        'EXPENSES',
                        expenses,
                        'arrow.down',
                        ink,
                        code,
                      ),
                    ),
                  ],
                ),
              ],
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
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: ink.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatCurrency(amount, code),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
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
                  top: !ExpndGlass.enabled,
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
        child: Container(
          decoration: _panelDecoration(oc),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(sfIcon('sun.max.fill'), size: 13, color: oc.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: oc.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '-${formatCurrency(todaySpent, code)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: oc.negative,
                      ),
                    ),
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
    final cycle = context.read<SettingsStore>().budgetCycle;
    final label = switch (cycle) {
      'weekly' => 'WEEKLY BUDGET',
      'fortnightly' => 'FORTNIGHTLY BUDGET',
      'payday' => 'PAYDAY BUDGET',
      _ => 'MONTHLY BUDGET',
    };
    final barColor = progress >= 0.9
        ? ExpndColors.red
        : progress >= 0.7
        ? hexColor('EAB308')
        : ExpndColors.green;
    return Semantics(
      button: true,
      label: '${label[0]}${label.substring(1).toLowerCase()}, $pct percent used. Opens budgets in Plan',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Reporting the budget invites changing it, and every budget control
        // lives on PLAN. Switch tabs rather than growing a second set here.
        onTap: () {
          Haptics.light();
          widget.onOpenPlan();
        },
        child: Container(
          decoration: _panelDecoration(oc),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The label keeps its full width up to 60% of the row; the
                // values take the rest, right-aligned, and are what ellipsize
                // when space is tight. (Two Flexibles split the row 50/50 and
                // clipped the label to "MONTHLY BUDG…".)
                LayoutBuilder(
                  builder: (context, c) => Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth * 0.6),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: oc.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${formatPercent(pct)} used ',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: barColor,
                                ),
                              ),
                              TextSpan(
                                text: 'of ${formatCurrency(budget, code)}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: oc.dimmed,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
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

  // A compact preview of what's coming: the committed total plus the nearest
  // movement, with the full timeline a tap away.
  Widget _upcomingCard(
    BuildContext context,
    AppStore store,
    List<UpcomingItem> upcoming,
    String code,
  ) {
    final oc = context.oc;
    final summary = summarizeUpcoming(store, upcoming);
    final preview = upcoming.take(1).toList();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _panelDecoration(oc),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Text(
                  'UPCOMING',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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
                      fontWeight: FontWeight.w700,
                      color: oc.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$kUpcomingHorizonDays DAYS',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: oc.dimmed,
                    ),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: oc.muted,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatCurrency(summary.committedOutflows, code),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: oc.text,
                      ),
                    ),
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
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
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
            Expanded(
              child: Text(
                'Accounts',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: oc.muted,
                ),
              ),
            ),
            // Keep the dashboard preview to two complete cards. Partial cards
            // looked like broken layout in dark mode; the count remains the
            // affordance for opening the full Wallet list.
            if (store.accounts.length > 2) ...[
              Flexible(
                child: Text(
                  '${store.accounts.length} accounts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: oc.dimmed),
                ),
              ),
              const SizedBox(width: 2),
              Icon(sfIcon('chevron.right'), size: 9, color: oc.dimmed),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92 + (MediaQuery.textScalerOf(context).scale(40) - 40),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: store.accounts.length > 2 ? 2 : store.accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final acc = store.accounts[i];
              // Cards show what's owed, the same figure as Wallet's card face.
              final total = acc.type == AccountType.credit
                  ? store.creditUsedFor(acc)
                  : store.balanceFor(acc);
              final accColor = hexColor(acc.colorHex);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.light();
                  widget.onOpenAccount(acc.id);
                },
                child: Container(
                  decoration: _panelDecoration(
                    oc,
                    borderColor: accColor.withValues(alpha: 0.38),
                  ),
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatCurrency(total, code),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: oc.text,
                            ),
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
      monthlyBudget: settings.budgetCycle == 'calendar'
          ? store.effectiveMonthlyBudget(
              settings.monthlyBudget,
              rollover: settings.budgetRollover,
            )
          : 0,
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
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: oc.muted,
            ),
          ),
        ),
        _AiInsightNarrative(insights: shown),
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
    return Container(
      decoration: _panelDecoration(
        oc,
        borderColor: tint.withValues(alpha: 0.28),
      ),
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _panelDecoration(oc),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                // Title + count take everything SEE ALL leaves. (Flexible plus
                // a Spacer split the row in half and clipped the title.)
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'TRANSACTIONS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
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
                            fontWeight: FontWeight.w700,
                            color: oc.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Haptics.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: oc.bg,
                          body: SafeArea(
                            top: !ExpndGlass.enabled,
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
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
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
            child: SegmentedPicker<TransactionType?>(
              options: const [
                SegmentOption(
                  value: null,
                  label: 'All',
                  semanticLabel: 'All transactions',
                ),
                SegmentOption(value: TransactionType.income, label: 'Income'),
                SegmentOption(
                  value: TransactionType.expense,
                  label: 'Expense',
                ),
              ],
              selected: _filter,
              onSelected: (value) => setState(() => _filter = value),
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

/// A short narrative generated by Apple's system model when the device can run
/// it, or built from rules otherwise. The verified cards remain directly
/// below, so the explanation can always be checked against the figures that
/// produced it.
class _AiInsightNarrative extends StatefulWidget {
  final List<Insight> insights;
  const _AiInsightNarrative({required this.insights});

  @override
  State<_AiInsightNarrative> createState() => _AiInsightNarrativeState();
}

class _AiInsightNarrativeState extends State<_AiInsightNarrative>
    with WidgetsBindingObserver {
  CoachAnswer? _summary;
  late String _fingerprint;
  int _requestId = 0;

  String _factsFingerprint(List<Insight> insights) =>
      insights.map((i) => '${i.title}\u001f${i.detail}').join('\u001e');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppleIntelligence.available.addListener(_requestSummary);
    _fingerprint = _factsFingerprint(widget.insights);
    _requestSummary();
  }

  @override
  void didUpdateWidget(covariant _AiInsightNarrative oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _factsFingerprint(widget.insights);
    if (next == _fingerprint) return;
    _fingerprint = next;
    // Clear immediately: if the privacy eye hid amounts, an older summary must
    // not keep a previously visible figure on screen during regeneration.
    _summary = null;
    _requestSummary();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Apple Intelligence may become available after its model download or
    // setting changes. A change notifies [available], which regenerates.
    if (state == AppLifecycleState.resumed) {
      AppleIntelligence.refreshAvailability();
    }
  }

  void _requestSummary() {
    final requestId = ++_requestId;
    final facts = List<Insight>.of(widget.insights);
    AppleIntelligence.summarizeInsights(facts).then((summary) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _summary = summary);
    });
  }

  @override
  void dispose() {
    _requestId++;
    AppleIntelligence.available.removeListener(_requestSummary);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();
    final source = summary.source;

    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: source.isAi
            ? 'On-device AI summary. ${summary.text}'
            : 'Insights summary. ${summary.text}',
        hint: 'Opens quick coaching choices',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.light();
            _showAiCoach(context, widget.insights, summary);
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: ExpndColors.gold.withValues(
                alpha: Theme.of(context).brightness == Brightness.light
                    ? 0.10
                    : 0.08,
              ),
              borderRadius: BorderRadius.circular(ExpndRadius.card),
              border: Border.all(
                color: ExpndColors.gold.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(sfIcon(source.icon), size: 13, color: oc.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: oc.accent,
                          ),
                        ),
                      ),
                      Text(
                        'Explore',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: oc.accent,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(sfIcon('chevron.right'), size: 10, color: oc.accent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: oc.text,
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
}

Future<void> _showAiCoach(
  BuildContext context,
  List<Insight> insights,
  CoachAnswer summary,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiCoachSheet(
      insights: List<Insight>.of(insights),
      initialSummary: summary,
    ),
  );
}

class _AiCoachSheet extends StatefulWidget {
  final List<Insight> insights;
  final CoachAnswer initialSummary;
  const _AiCoachSheet({required this.insights, required this.initialSummary});

  @override
  State<_AiCoachSheet> createState() => _AiCoachSheetState();
}

class _AiCoachSheetState extends State<_AiCoachSheet> {
  AiCoachPrompt _selected = AiCoachPrompt.summary;
  late CoachAnswer _answer;
  final Map<AiCoachPrompt, CoachAnswer> _answers = {};
  bool _loading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _answer = widget.initialSummary;
    _answers[AiCoachPrompt.summary] = widget.initialSummary;
  }

  Future<void> _ask(AiCoachPrompt prompt) async {
    Haptics.light();
    final cached = _answers[prompt];
    if (cached != null) {
      _requestId++;
      setState(() {
        _selected = prompt;
        _answer = cached;
        _loading = false;
      });
      return;
    }

    final requestId = ++_requestId;
    setState(() {
      _selected = prompt;
      _loading = true;
    });
    final answer = await AppleIntelligence.generateInsight(
      widget.insights,
      prompt: prompt,
    );
    if (!mounted || requestId != _requestId) return;
    setState(() {
      if (answer != null) {
        _answers[prompt] = answer;
        _answer = answer;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final source = _answer.source;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
          decoration: BoxDecoration(
            color: oc.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(top: BorderSide(color: oc.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: oc.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ExpndColors.gold.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      sfIcon(source.icon),
                      size: 17,
                      color: oc.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: oc.text,
                          ),
                        ),
                        Text(
                          source.subtitle,
                          style: TextStyle(fontSize: 11, color: oc.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(sfIcon('xmark'), size: 17, color: oc.muted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Container(
                  key: ValueKey('$_selected-$_loading-${_answer.text}'),
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 92),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: oc.surface,
                    borderRadius: BorderRadius.circular(ExpndRadius.card),
                    border: Border.all(color: oc.border),
                  ),
                  child: _loading
                      ? Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: oc.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                source.isAi
                                    ? 'Thinking on your phone…'
                                    : 'Loading…',
                                style: TextStyle(fontSize: 12, color: oc.muted),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _answer.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _coachChoice(
                    AiCoachPrompt.focus,
                    'Focus',
                    Icons.center_focus_strong,
                  ),
                  _coachChoice(
                    AiCoachPrompt.win,
                    'Good news',
                    Icons.celebration_outlined,
                  ),
                  _coachChoice(
                    AiCoachPrompt.nextStep,
                    'Next step',
                    Icons.arrow_forward,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coachChoice(AiCoachPrompt prompt, String label, IconData icon) {
    final oc = context.oc;
    final selected = _selected == prompt;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () => _ask(prompt),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? ExpndColors.gold : oc.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? ExpndColors.goldDark : oc.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? ExpndColors.ink : oc.text),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? ExpndColors.ink : oc.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
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

    final amountColor = isTransfer
        ? ExpndColors.gold
        : isIncome
        ? ExpndColors.green
        : ExpndColors.red;
    final receipt = Receipts.fileFor(transaction.photoPath);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: oc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The amount rides on the title line only, so the note and the
            // date/account line below get the full width of the row instead
            // of being squeezed beside it.
            final amount = ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
              // Scale a very large amount down rather than overflow on a
              // narrow phone at a bumped-up text size.
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
                        color: amountColor,
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
                      color: amountColor,
                    ),
                  ],
                ),
              ),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rowColor.withValues(alpha: 0.12),
                    // Rounded to sit with the app's rounded cards.
                    borderRadius: BorderRadius.circular(10),
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
                      ? Text(
                          custom.emoji,
                          style: const TextStyle(fontSize: 20),
                        )
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
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
                          ),
                          const SizedBox(width: 8),
                          amount,
                        ],
                      ),
                      if (transaction.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          transaction.note,
                          // Two lines so a descriptive note ("Reimbursement:
                          // Client trip flights") reads in full.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: oc.dimmed),
                        ),
                      ],
                      const SizedBox(height: 3),
                      // One line of text rather than flex-split widgets: the
                      // date and account share the space and only ellipsize
                      // when the line genuinely runs out of room.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: _dateLabel(transaction.date)),
                            if (transaction.isRecurring)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    sfIcon('repeat'),
                                    size: 9,
                                    color: oc.accent,
                                  ),
                                ),
                              ),
                            if (account != null) ...[
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(
                                    left: 6,
                                    right: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hexColor(account.colorHex),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: account.name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: oc.dimmed),
                      ),
                    ],
                  ),
                ),
                if (receipt != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(
                        receipt,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            );
          },
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
