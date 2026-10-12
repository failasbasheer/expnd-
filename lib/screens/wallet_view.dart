import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/insights.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/glass_header.dart';
import '../widgets/animations.dart';
import '../widgets/app_header.dart';
import '../widgets/context_ai_coach.dart';
import '../widgets/neopop.dart';
import 'account_setup.dart';
import 'settings_view.dart';
import 'emi.dart';
import 'home_shell.dart';
import 'transaction_detail.dart';
import 'history_view.dart';
import 'reconciliation_view.dart';

/// Identifies the sticky selected-account bar so tests can assert on it without
/// guessing at an icon or a label that might legitimately change.
const Key walletStickyBarKey = ValueKey('wallet-sticky-account-bar');

class WalletView extends StatefulWidget {
  /// When set (e.g. after tapping an account card on the dashboard), the wallet
  /// opens with that account selected. [onFocusConsumed] lets the parent clear
  /// the request so tapping the same card again re-triggers the focus.
  final String? focusAccountId;
  final VoidCallback? onFocusConsumed;
  final GlobalKey? tourKey;
  final GlobalKey? profileTourKey;
  const WalletView({
    super.key,
    this.focusAccountId,
    this.onFocusConsumed,
    this.tourKey,
    this.profileTourKey,
  });

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  int _selected = 0;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _deckKey = GlobalKey();

  /// Height of the glass header the list scrolls under (0 when solid).
  double _headerInset = 0;

  /// True once the card deck has scrolled out of view. The details below belong
  /// to whichever card is at the front, so with the deck gone there's nothing
  /// left on screen saying which account you're reading — hence the sticky bar.
  ///
  /// A [ValueNotifier] rather than setState so a scroll only rebuilds the bar,
  /// not the whole wallet (the card deck is expensive to lay out).
  final ValueNotifier<bool> _deckOffscreen = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncDeckVisibility);
    // A focus request can arrive with the first build (e.g. Wallet created
    // straight from a Home account card), not only via didUpdateWidget.
    _applyFocus();
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncDeckVisibility);
    _scroll.dispose();
    _deckOffscreen.dispose();
    super.dispose();
  }

  void _syncDeckVisibility() {
    final deck = _deckKey.currentContext?.findRenderObject() as RenderBox?;
    if (deck == null || !deck.attached || !deck.hasSize) return;
    if (!_scroll.hasClients) return;

    // getOffsetToReveal(_, 0) is the scroll offset at which the deck's top sits
    // at the viewport's top; add its height and the deck has just cleared.
    // Asking the viewport directly beats measuring against a key on the
    // ListView — that resolves to a render object *inside* the scrolled
    // content, so the offset it reports never changes as you scroll.
    final viewport = RenderAbstractViewport.maybeOf(deck);
    if (viewport == null) return;
    final clearedAt =
        viewport.getOffsetToReveal(deck, 0).offset + deck.size.height;

    // Flip just before it fully clears, so the bar arrives while a sliver of
    // card is still visible instead of after a blank beat.
    // Under a glass header the list starts beneath the header, so the deck is
    // hidden once it passes the header's bottom edge, not the screen top.
    final show = _scroll.offset > clearedAt - 24 - _headerInset;
    if (_deckOffscreen.value != show) _deckOffscreen.value = show;
  }

  @override
  void didUpdateWidget(covariant WalletView old) {
    super.didUpdateWidget(old);
    if (widget.focusAccountId != old.focusAccountId) _applyFocus();
  }

  /// Select the requested account (if it still exists), then tell the parent
  /// the request has been handled. Deferred to after the frame so it's safe to
  /// call setState from didUpdateWidget.
  void _applyFocus() {
    final id = widget.focusAccountId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accounts = context.read<AppStore>().accounts;
      final idx = accounts.indexWhere((a) => a.id == id);
      if (idx >= 0) setState(() => _selected = idx);
      widget.onFocusConsumed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final accounts = store.accounts;
    if (_selected >= accounts.length) {
      _selected = accounts.isEmpty ? 0 : accounts.length - 1;
    }
    final aiFacts = _walletAiFacts(store, accounts, code);

    return Container(
      color: oc.bg,
      child: GlassHeaderLayout(
        header: _titleBar(accounts),
        // Not counted in the inset: it appears mid-scroll and covers the
        // content rather than pushing it down.
        overlay: accounts.isNotEmpty
            ? _selectedAccountBar(oc, store, accounts, code)
            : null,
        body: (context, top) {
          _headerInset = top;
          return accounts.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: top),
                  child: _emptyState(oc),
                )
              : ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                    0,
                    top,
                    0,
                    ExpndSpacing.scrollBottomUnderTabBar(context),
                  ),
                  children: [
                    FadeSlideIn(
                      index: 0,
                      child: _netWorthHeader(oc, store, accounts, code),
                    ),
                    const SizedBox(height: 20),
                    if (aiFacts.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: FadeSlideIn(
                          index: 1,
                          child: ContextAiCoach(facts: aiFacts),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    FadeSlideIn(
                      index: 2,
                      child: KeyedSubtree(
                        key: _deckKey,
                        child: _cardStack(store, accounts, code),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (accounts.length >= 2) ...[
                      _reorderHint(oc),
                      const SizedBox(height: 8),
                    ],
                    if (_selected < accounts.length)
                      // Switching cards swaps these details (credit cards add
                      // an EMI section) — animate the height so the section
                      // grows/shrinks smoothly instead of snapping.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: FadeSlideIn(
                          index: 2,
                          child: _accountDetails(
                            oc,
                            store,
                            accounts[_selected],
                            code,
                          ),
                        ),
                      ),
                  ],
                );
        },
      ),
    );
  }

  List<Insight> _walletAiFacts(
    AppStore store,
    List<Account> accounts,
    String code,
  ) {
    if (accounts.isEmpty) return const [];
    final creditAccounts = accounts
        .where((account) => account.type == AccountType.credit)
        .toList();
    final creditUsed = creditAccounts.fold(
      0.0,
      (sum, account) => sum + store.creditUsedFor(account),
    );

    // Net worth and spendable cash are already the gold card's headline and
    // sub-line; repeating them here only echoed the number directly above.
    return [
      if (creditAccounts.isNotEmpty)
        Insight(
          title: '${formatCurrency(creditUsed, code)} in credit is used',
          detail:
              'Across ${creditAccounts.length} credit card${creditAccounts.length == 1 ? '' : 's'}',
          tone: creditUsed > 0 ? InsightTone.neutral : InsightTone.good,
          icon: 'creditcard.fill',
          weight: 60,
        ),
    ];
  }

  /// Sticky identity bar for the card at the front of the deck. Slides in only
  /// once the deck has scrolled away, so it never duplicates what's already on
  /// screen. Tapping it scrolls back up to the deck.
  Widget _selectedAccountBar(
    ExpndColors oc,
    AppStore store,
    List<Account> accounts,
    String code,
  ) {
    if (_selected >= accounts.length) return const SizedBox.shrink();
    final account = accounts[_selected];
    final tint = hexColor(account.colorHex);
    final isCredit = account.type == AccountType.credit;
    // Mirrors the card face: a credit card leads with what's owed, everything
    // else with what it holds.
    final amount = isCredit
        ? store.creditUsedFor(account)
        : store.balanceFor(account);

    return ValueListenableBuilder<bool>(
      valueListenable: _deckOffscreen,
      builder: (context, show, _) => AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: !show
            ? const SizedBox(width: double.infinity)
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.light();
                  _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: Container(
                  key: walletStickyBarKey,
                  decoration: BoxDecoration(
                    // Part of the glass header plate when glass is on.
                    color: ExpndGlass.enabled ? null : oc.surface,
                    border: Border(
                      top: ExpndGlass.enabled
                          ? BorderSide(color: oc.border.withValues(alpha: 0.5))
                          : BorderSide.none,
                      bottom: ExpndGlass.enabled
                          ? BorderSide.none
                          : BorderSide(color: oc.border, width: 1),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.16),
                          border: Border.all(
                            color: tint.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          sfIcon(account.type.icon),
                          size: 12,
                          color: tint,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: oc.text,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              isCredit
                                  ? 'Credit Card · used'
                                  : account.type.raw,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: oc.muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(amount, code),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: amount < 0 ? ExpndColors.red : oc.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const SizedBox(width: 6),
                      Icon(sfIcon('chevron.up'), size: 12, color: oc.dimmed),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _titleBar(List<Account> accounts) {
    return ExpndHeader(
      key: widget.tourKey,
      icon: 'creditcard.fill',
      title: 'Wallet',
      actions: [
        // Was a labelled "+ ADD" pill — squat, a different height to every
        // other control on screen, and carrying a word the plus already says.
        // As a square primary action it lines up with the header furniture on
        // the other tabs. The empty wallet keeps its own full-width CTA, so
        // there's nothing to add *to* until an account exists.
        if (accounts.isNotEmpty)
          HeaderAction(
            icon: 'plus',
            semanticLabel: 'Add account',
            primary: true,
            onPressed: () {
              Haptics.light();
              showAddAccount(context);
            },
          ),
        SettingsAvatarAction(key: widget.profileTourKey),
      ],
    );
  }

  Widget _reorderHint(ExpndColors oc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(sfIcon('arrow.up.arrow.down'), size: 10, color: oc.dimmed),
          const SizedBox(width: 6),
          // Flexible so the hint ellipsises rather than overflowing on the
          // narrowest phones at a bumped-up text size.
          Flexible(
            child: Text(
              'Long-press a card to rearrange',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: oc.dimmed),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReorderAccounts(List<Account> accounts) async {
    Haptics.light();
    final store = context.read<AppStore>();
    final selectedId = _selected < accounts.length
        ? accounts[_selected].id
        : null;
    final newOrder = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReorderAccountsSheet(accounts: accounts),
    );
    if (newOrder == null) return;
    store.reorderAccounts(newOrder);
    // Keep the same card at the front after the shuffle.
    if (selectedId != null) {
      final idx = newOrder.indexOf(selectedId);
      if (idx >= 0) setState(() => _selected = idx);
    }
    Haptics.success();
  }

  Widget _emptyState(ExpndColors oc) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: ExpndColors.gold.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(sfIcon('creditcard.fill'), size: 44, color: oc.accent),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'NO ACCOUNTS YET',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Add your bank accounts, cash,\nor credit cards to track them here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: oc.muted),
          ),
          const SizedBox(height: 24),
          NeoPopButton(
            onPressed: () {
              Haptics.light();
              showAddAccount(context);
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
                    'ADD FIRST ACCOUNT',
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
      ),
    );
  }

  Widget _netWorthHeader(
    ExpndColors oc,
    AppStore store,
    List<Account> accounts,
    String code,
  ) {
    final total = accounts.fold(0.0, (s, acc) => s + store.netWorthFor(acc));
    final spendable = accounts
        .where(
          (acc) =>
              acc.type == AccountType.bank ||
              acc.type == AccountType.cash ||
              acc.type == AccountType.savings,
        )
        .fold(0.0, (s, acc) => s + store.netWorthFor(acc));
    final ink = ExpndColors.ink;
    // Debt (card balances owed, loans) is subtracted from net worth but not
    // from spendable cash, so spendable can read higher. Say why when it does.
    final owesMore = spendable > total;
    Widget eyebrow(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        color: ink.withValues(alpha: 0.6),
      ),
    );
    Widget stat(String label, String value) => Expanded(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow(label),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ExpndColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Same raised gold slab as Home's balance card.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: NeoPopElevated(
        faceColor: ExpndColors.gold,
        depthColor: ExpndColors.goldDark,
        borderColor: ExpndColors.goldDark,
        borderWidth: 1.5,
        depth: 6,
        cornerRadius: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow('NET WORTH'),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatCurrency(total, code),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: ExpndColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: ink.withValues(alpha: 0.16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  stat('SPENDABLE CASH', formatCurrency(spendable, code)),
                  const SizedBox(width: 12),
                  stat(
                    accounts.length == 1 ? 'ACCOUNT' : 'ACCOUNTS',
                    '${accounts.length}',
                  ),
                ],
              ),
              if (owesMore) ...[
                const SizedBox(height: 10),
                Text(
                  'Spendable is bank, cash and savings. Card and loan '
                  'balances you owe come off net worth.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: ink.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Apple Wallet–style deck: non-selected cards collapse to a peeking header
  // strip stacked at the top, and the selected card expands fully at the front.
  // Tapping any peeking header brings that card forward.
  static const double _peek = 58;

  Widget _cardStack(AppStore store, List<Account> accounts, String code) {
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final n = accounts.length;
    // Paint order (bottom → top): every non-selected card in natural order,
    // then the selected card last so it draws over the rest, fully visible.
    final order = <int>[
      for (int i = 0; i < n; i++)
        if (i != _selected) i,
      _selected,
    ];
    // The selected card sits at the front, fully visible — reserve its true
    // height (credit cards render taller) so a tall front card never overflows.
    final frontH = AccountCardContent.heightFor(
      accounts[_selected].type,
      accounts[_selected].creditLimit,
    );
    final totalH = (n - 1) * _peek + frontH + 10; // +buffer for neoPOP depth

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // Keep the deck and the details beneath it moving at the same pace.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: totalH),
        duration: motionDuration,
        curve: Curves.easeOutCubic,
        builder: (context, height, child) =>
            SizedBox(height: height, child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int pos = 0; pos < order.length; pos++)
              () {
                // 0 = front (selected) card; larger = further back in the stack.
                final depth = (order.length - 1) - pos;
                final isFront = depth == 0;
                // Cards further back tuck in narrower and dim, giving the deck
                // a sense of perspective behind the lifted front card.
                final inset = (depth.clamp(0, 3)) * 7.0;
                final opacity = isFront
                    ? 1.0
                    : (1 - depth * 0.06).clamp(0.82, 1.0);
                return AnimatedPositioned(
                  key: ValueKey(accounts[order[pos]].id),
                  duration: motionDuration,
                  curve: Curves.easeOutCubic,
                  left: inset,
                  right: inset,
                  top: pos * _peek,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final idx = order[pos];
                      if (idx == _selected) return;
                      Haptics.light();
                      setState(() => _selected = idx);
                    },
                    // Long-press any card to rearrange the deck — matches the
                    // long-press-to-manage gesture used for categories and tags.
                    onLongPress: accounts.length >= 2
                        ? () => _openReorderAccounts(accounts)
                        : null,
                    child: AnimatedContainer(
                      duration: motionDuration,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: isFront
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 22,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 12),
                                ),
                              ]
                            : const [],
                      ),
                      // Back cards are dimmed with a scrim painted ON TOP of an
                      // opaque card — never by lowering the card's own opacity,
                      // which would make its peek strip translucent and let the
                      // card stacked beneath bleed through (ghost text).
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Stack(
                          children: [
                            AccountCardContent(
                              name: accounts[order[pos]].name,
                              type: accounts[order[pos]].type,
                              currencyCode: code,
                              balance: store.balanceFor(accounts[order[pos]]),
                              colorHex: accounts[order[pos]].colorHex,
                              cardDigits: accounts[order[pos]].cardDigits,
                              creditLimit: accounts[order[pos]].creditLimit,
                              creditUsed: store.creditUsedFor(
                                accounts[order[pos]],
                              ),
                            ),
                            if (!isFront)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: Colors.black.withValues(
                                      alpha: 1 - opacity,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }

  Widget _accountDetails(
    ExpndColors oc,
    AppStore store,
    Account account,
    String code,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _balanceCard(oc, store, account, code),
          const SizedBox(height: 16),
          AccountLoansSection(account: account),
          const SizedBox(height: 16),
          _accountTransactions(oc, store, account),
        ],
      ),
    );
  }

  /// The account's balance with its working shown — opening balance plus
  /// what the linked transactions added — and one row of actions underneath.
  /// It used to headline the *opening* balance as "SET BALANCE" beside a card
  /// face showing the current one, which read as two conflicting numbers.
  Widget _balanceCard(
    ExpndColors oc,
    AppStore store,
    Account account,
    String code,
  ) {
    final isCredit = account.type == AccountType.credit;
    final netChange = store.transactionNet(account.id);
    final linked = store.transactionsForAccount(account.id).length;
    final txns = '$linked transaction${linked == 1 ? '' : 's'}';
    // A card's outstanding is what's owed now (posted spending + EMIs),
    // matching the card face.
    final headline = isCredit
        ? store.creditUsedFor(account)
        : store.balanceFor(account);
    final working = isCredit
        ? 'Owed across $txns'
        : 'Opening ${formatCurrency(account.balance, code)} '
              '${netChange >= 0 ? '+' : '−'} '
              '${formatCurrency(netChange.abs(), code)} from $txns';

    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) {
      final c = color ?? oc.text;
      return Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.light();
              onTap();
            },
            child: SizedBox(
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19, color: c),
                  const SizedBox(height: 4),
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: c,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(ExpndRadius.card),
        border: Border.all(color: oc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCredit ? 'OUTSTANDING' : 'CURRENT BALANCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: oc.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatCurrency(headline, code),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: oc.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    working,
                    style: TextStyle(fontSize: 12, color: oc.muted),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: oc.border),
          // Everyday actions first; the irreversible one last, muted, and
          // still behind its confirm sheet.
          Row(
            children: [
              action(
                Icons.fact_check_outlined,
                'Check bank',
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReconciliationView(accountId: account.id),
                  ),
                ),
              ),
              action(
                sfIcon('pencil'),
                'Edit',
                () => showAddAccount(context, editing: account),
              ),
              action(
                sfIcon('trash'),
                'Remove',
                () => _confirmDelete(context, store, account),
                color: ExpndColors.red.withValues(alpha: 0.8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppStore store, Account account) {
    Haptics.light();
    final oc = context.oc;
    showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Remove "${account.name}"?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: oc.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Linked transactions will remain but won't be tied to any account.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: oc.muted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    store.deleteAccount(account);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Remove Account',
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

  Widget _accountTransactions(ExpndColors oc, AppStore store, Account account) {
    final all = store.transactionsForAccount(account.id)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = all.take(5).toList();
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 0,
      cornerRadius: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                // Expanded, not Flexible + Spacer — the latter caps the title at
                // half the row and clips it even with a short trailing value.
                Expanded(
                  child: Text(
                    'RECENT TRANSACTIONS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: oc.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (all.isNotEmpty)
                  Semantics(
                    button: true,
                    label: 'See all ${all.length} transactions',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Haptics.light();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              backgroundColor: oc.bg,
                              body: SafeArea(
                                top: !ExpndGlass.enabled,
                                bottom: false,
                                child: HistoryView(initialAccount: account),
                              ),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        // Pads the link out to a fair tap target.
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'SEE ALL ${all.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                color: oc.accent,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              sfIcon('chevron.right'),
                              size: 11,
                              color: oc.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: oc.border),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(sfIcon('tray'), size: 30, color: oc.dimmed),
                  const SizedBox(height: 10),
                  Text(
                    'No transactions linked yet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: oc.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose this account when adding transactions',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: oc.dimmed),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < recent.length; i++) ...[
              TransactionRow(
                transaction: recent[i],
                currencyCode: context.read<SettingsStore>().currencyCode,
                onTap: () => showTransactionDetail(context, recent[i]),
              ),
              if (i != recent.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 66),
                  child: Container(height: 1, color: oc.border),
                ),
            ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reorder accounts sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Drag-to-arrange the wallet's account cards. Returns the account ids in their
/// new order (or null on dismiss). The order is stored on [AppStore] so it
/// holds everywhere accounts are listed, not just the card deck.
class _ReorderAccountsSheet extends StatefulWidget {
  final List<Account> accounts;
  const _ReorderAccountsSheet({required this.accounts});

  @override
  State<_ReorderAccountsSheet> createState() => _ReorderAccountsSheetState();
}

class _ReorderAccountsSheetState extends State<_ReorderAccountsSheet> {
  late final List<Account> _items = List.of(widget.accounts);

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
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
            'ARRANGE ACCOUNTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Drag to set your card order',
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
                onPressed: () =>
                    Navigator.of(context).pop(_items.map((e) => e.id).toList()),
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

  Widget _row(ExpndColors oc, Account acc, int index) {
    final tint = hexColor(acc.colorHex);
    return Container(
      key: ValueKey(acc.id),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tint.withValues(alpha: 0.5), width: 1),
            ),
            child: Icon(sfIcon(acc.type.icon), size: 14, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  acc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: oc.text,
                  ),
                ),
                Text(
                  acc.type.raw,
                  style: TextStyle(fontSize: 10, color: oc.muted),
                ),
              ],
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
