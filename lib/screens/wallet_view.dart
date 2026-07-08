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
import 'account_setup.dart';
import 'emi.dart';
import 'home_shell.dart';

class WalletView extends StatefulWidget {
  /// When set (e.g. after tapping an account card on the dashboard), the wallet
  /// opens with that account selected. [onFocusConsumed] lets the parent clear
  /// the request so tapping the same card again re-triggers the focus.
  final String? focusAccountId;
  final VoidCallback? onFocusConsumed;
  const WalletView({super.key, this.focusAccountId, this.onFocusConsumed});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  int _selected = 0;

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
      debugPrint('[wallet-focus] applyFocus id=$id -> idx=$idx '
          '(accounts=${accounts.map((a) => "${a.name}:${a.id}").toList()})');
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

    return Container(
      color: oc.bg,
      child: Column(
        children: [
          _titleBar(oc, accounts.isNotEmpty),
          Expanded(
            child: accounts.isEmpty
                ? _emptyState(oc)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
                    children: [
                      FadeSlideIn(
                        index: 0,
                        child: _netWorthHeader(oc, store, accounts, code),
                      ),
                      const SizedBox(height: 20),
                      FadeSlideIn(
                        index: 1,
                        child: _cardStack(store, accounts, code),
                      ),
                      const SizedBox(height: 20),
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
                  ),
          ),
        ],
      ),
    );
  }

  Widget _titleBar(ExpndColors oc, bool showAdd) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text(
            'MY WALLET',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: oc.text,
            ),
          ),
          const Spacer(),
          if (showAdd)
            NeoPopButton(
              onPressed: () {
                Haptics.light();
                showAddAccount(context);
              },
              depth: 3,
              cornerRadius: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(sfIcon('plus'), size: 10, color: ExpndColors.ink),
                    const SizedBox(width: 5),
                    Text(
                      'ADD',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
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
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
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
                      fontWeight: FontWeight.w900,
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
    final total = accounts.fold(0.0, (s, acc) => s + store.balanceFor(acc));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: NeoPopElevated(
        faceColor: ExpndColors.gold,
        depthColor: ExpndColors.goldDark,
        borderColor: ExpndColors.goldDark,
        depth: 5,
        cornerRadius: 6,
        child: Stack(
          children: [
            Positioned.fill(
              child: NeoPopShine(
                color: ExpndColors.ink.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL NET WORTH',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: ExpndColors.ink.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatCurrency(total, code),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: ExpndColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${accounts.length} account${accounts.length == 1 ? "" : "s"}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: ExpndColors.ink.withValues(alpha: 0.5),
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

  // Apple Wallet–style deck: non-selected cards collapse to a peeking header
  // strip stacked at the top, and the selected card expands fully at the front.
  // Tapping any peeking header brings that card forward.
  static const double _peek = 58;

  Widget _cardStack(AppStore store, List<Account> accounts, String code) {
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
      // Front cards differ in height (credit cards are taller), so totalH jumps
      // when you switch cards. Tween the height in step with the card spring so
      // the details section below glides instead of snapping.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: totalH),
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOut,
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
                  duration: const Duration(milliseconds: 480),
                  curve:
                      Curves.easeOutBack, // subtle spring/overshoot on settle
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 480),
                      curve: Curves.easeOut,
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
                              creditUsed:
                                  store.creditUsedFor(accounts[order[pos]]),
                            ),
                            if (!isFront)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: Colors.black
                                        .withValues(alpha: 1 - opacity),
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
          if (account.type == AccountType.credit) ...[
            const SizedBox(height: 16),
            CreditEmiSection(account: account),
          ],
          const SizedBox(height: 16),
          _accountTransactions(oc, store, account),
        ],
      ),
    );
  }

  Widget _balanceCard(
    ExpndColors oc,
    AppStore store,
    Account account,
    String code,
  ) {
    final netChange = store.transactionNet(account.id);
    final positive = netChange >= 0;
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 4,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        account.type == AccountType.credit
                            ? 'OUTSTANDING'
                            : 'SET BALANCE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: oc.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency(account.balance, code),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: oc.text,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    showAddAccount(context, editing: account);
                  },
                  child: Icon(
                    sfIcon('pencil.circle.fill'),
                    size: 26,
                    color: oc.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: oc.border),
            const SizedBox(height: 16),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NET FROM TRANSACTIONS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: oc.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          sfIcon(positive ? 'arrow.up' : 'arrow.down'),
                          size: 11,
                          color: positive ? ExpndColors.green : ExpndColors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCurrency(netChange.abs(), code),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: positive
                                ? ExpndColors.green
                                : ExpndColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: oc.border,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'LINKED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: oc.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${store.transactionsForAccount(account.id).length} txns',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: oc.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: oc.border),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _confirmDelete(context, store, account),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: ExpndColors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: ExpndColors.red.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(sfIcon('trash'), size: 11, color: ExpndColors.red),
                    const SizedBox(width: 6),
                    Text(
                      'REMOVE ACCOUNT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: ExpndColors.red,
                      ),
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
                  fontWeight: FontWeight.w900,
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
      depth: 4,
      cornerRadius: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  'RECENT TRANSACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: oc.muted,
                  ),
                ),
                const Spacer(),
                if (all.isNotEmpty)
                  Text(
                    '${all.length} total',
                    style: TextStyle(fontSize: 10, color: oc.dimmed),
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
                currencyCode: account.currencyCode,
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
