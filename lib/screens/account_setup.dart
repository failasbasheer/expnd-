import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';
import '../widgets/money_field.dart';
import '../widgets/neopop_cards.dart';
import 'whats_new.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding (first launch)
// ─────────────────────────────────────────────────────────────────────────────

void showAccountOnboarding(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const AccountOnboarding(),
    ),
  );
}

class _AccountDraft {
  String name = '';
  AccountType type = AccountType.bank;
  String currencyCode;
  String balance = '';
  _AccountDraft(this.currencyCode);
}

class AccountOnboarding extends StatefulWidget {
  const AccountOnboarding({super.key});

  @override
  State<AccountOnboarding> createState() => _AccountOnboardingState();
}

class _AccountOnboardingState extends State<AccountOnboarding> {
  int _step = 0; // 0 welcome, 1..count steps, count+1 done
  int _count = 1;
  List<_AccountDraft> _drafts = [];

  void _complete() {
    final settings = context.read<SettingsStore>();
    settings.hasCompletedAccountSetup = true;
    settings.getStartedEligible = true;
    // A fresh install is meeting these features for the first time, so it has
    // no "what's new" to catch up on — stamp the current version as seen.
    settings.whatsNewSeenVersion = kWhatsNewVersion;
    Navigator.of(context).pop();
  }

  void _saveAccounts() {
    final store = context.read<AppStore>();
    for (final d in _drafts) {
      final name = d.name.trim().isEmpty ? 'My Account' : d.name.trim();
      store.addAccount(
        Account(
          name: name,
          type: d.type,
          currencyCode: d.currencyCode,
          balance: parseAmount(d.balance) ?? 0,
        ),
      );
    }
    Haptics.success();
    setState(() => _step = _count + 1);
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    Widget body;
    if (_step == 0) {
      body = _welcome(oc);
    } else if (_step <= _count) {
      body = _AccountStepForm(
        key: ValueKey(_step),
        draft: _drafts[_step - 1],
        accountNumber: _step,
        total: _count,
        onNext: () {
          Haptics.light();
          // The step form (and its focused field) is swapped out below —
          // release focus first or the keyboard stays stuck on iOS.
          FocusManager.instance.primaryFocus?.unfocus();
          if (_step < _count) {
            setState(() => _step++);
          } else {
            _saveAccounts();
          }
        },
        onBack: () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _step--);
        },
      );
    } else {
      body = _done(oc);
    }

    return Scaffold(
      backgroundColor: oc.bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: body,
        ),
      ),
    );
  }

  Widget _welcome(ExpndColors oc) {
    final settings = context.watch<SettingsStore>();
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: ExpndColors.gold.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: ExpndColors.gold.withValues(alpha: 0.07),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(
                          sfIcon('creditcard.fill'),
                          size: 50,
                          color: oc.accent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'SET UP YOUR WALLET',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: oc.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'How many accounts do you have?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: oc.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bank accounts, cash, credit cards, etc.',
                    style: TextStyle(fontSize: 12, color: oc.dimmed),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 38,
                        icon: Icon(
                          sfIcon('minus.circle.fill') == sfIcon('circle')
                              ? Icons.remove_circle
                              : Icons.remove_circle,
                          color: _count > 1 ? ExpndColors.gold : oc.dimmed,
                        ),
                        onPressed: () {
                          if (_count > 1) {
                            Haptics.light();
                            setState(() => _count--);
                          }
                        },
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '$_count',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            color: oc.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        iconSize: 38,
                        icon: Icon(
                          Icons.add_circle,
                          color: _count < 10 ? ExpndColors.gold : oc.dimmed,
                        ),
                        onPressed: () {
                          if (_count < 10) {
                            Haptics.light();
                            setState(() => _count++);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // The whole app uses one currency, chosen here at setup.
                  Text(
                    'CURRENCY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: oc.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final picked = await showCurrencyPicker(
                        context,
                        settings.currencyCode,
                      );
                      if (picked != null) settings.currencyCode = picked;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: oc.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: oc.border, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Text(
                            currencySymbol(settings.currencyCode),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: oc.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              supportedCurrencies
                                      .where(
                                        (c) => c.code == settings.currencyCode,
                                      )
                                      .map((c) => '${c.code} · ${c.name}')
                                      .firstOrNull ??
                                  settings.currencyCode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: oc.text,
                              ),
                            ),
                          ),
                          Icon(
                            sfIcon('chevron.right'),
                            size: 12,
                            color: oc.dimmed,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  NeoPopButton(
                    onPressed: () {
                      Haptics.medium();
                      final code = context.read<SettingsStore>().currencyCode;
                      _drafts = List.generate(
                        _count,
                        (_) => _AccountDraft(code),
                      );
                      setState(() => _step = 1);
                    },
                    depth: 4,
                    cornerRadius: 8,
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'CONTINUE',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: ExpndColors.ink,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              sfIcon('arrow.up') == sfIcon('circle')
                                  ? Icons.arrow_forward
                                  : Icons.arrow_forward,
                              size: 12,
                              color: ExpndColors.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _complete,
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: oc.dimmed,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _done(ExpndColors oc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Spacer(),
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: ExpndColors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(
                  sfIcon('checkmark.circle.fill'),
                  size: 60,
                  color: ExpndColors.green,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "YOU'RE ALL SET!",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your accounts have been added.\nManage them anytime from the Wallet tab.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: oc.muted),
          ),
          const Spacer(),
          NeoPopButton(
            onPressed: () {
              Haptics.success();
              _complete();
            },
            depth: 4,
            cornerRadius: 8,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'GET STARTED',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: ExpndColors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward,
                      size: 12,
                      color: Color(0xFF0D0D0D),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _AccountStepForm extends StatefulWidget {
  final _AccountDraft draft;
  final int accountNumber;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _AccountStepForm({
    super.key,
    required this.draft,
    required this.accountNumber,
    required this.total,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<_AccountStepForm> createState() => _AccountStepFormState();
}

class _AccountStepFormState extends State<_AccountStepForm> {
  late final _nameCtrl = TextEditingController(text: widget.draft.name);
  late final _balanceCtrl = TextEditingController(text: widget.draft.balance);

  bool get _isValid => _nameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final d = widget.draft;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // progress
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: widget.accountNumber / widget.total,
              minHeight: 4,
              backgroundColor: oc.border,
              valueColor: AlwaysStoppedAnimation(oc.accent),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Account ${widget.accountNumber} of ${widget.total}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: oc.muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          d.type == AccountType.cash
              ? 'Cash in Hand'
              : 'Account ${widget.accountNumber} Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: oc.text,
          ),
        ),
        const SizedBox(height: 20),
        _label('Account name', oc),
        const SizedBox(height: 8),
        _box(
          oc,
          child: TextField(
            controller: _nameCtrl,
            onChanged: (v) => setState(() => d.name = v),
            style: TextStyle(fontSize: 14, color: oc.text),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'e.g. Chase Checking, Wallet, HDFC Savings',
            ),
          ),
        ),
        const SizedBox(height: 20),
        _label('Account type', oc),
        const SizedBox(height: 8),
        _typeGrid(oc, d.type, (t) => setState(() => d.type = t)),
        const SizedBox(height: 20),
        _label(
          d.type == AccountType.cash ? 'CASH IN HAND' : 'CURRENT BALANCE',
          oc,
        ),
        const SizedBox(height: 8),
        MoneyField(
          controller: _balanceCtrl,
          currencyCode: d.currencyCode,
          label: 'Current balance',
          onChanged: (v) => d.balance = v,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: NeoPopButton(
                onPressed: widget.onBack,
                faceColor: oc.surface,
                depthColor: oc.edge,
                depth: 4,
                cornerRadius: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_back, size: 11),
                      const SizedBox(width: 6),
                      Text(
                        'BACK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: oc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NeoPopButton(
                onPressed: widget.onNext,
                enabled: _isValid,
                faceColor: _isValid ? ExpndColors.gold : oc.surface,
                depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
                depth: 4,
                cornerRadius: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.accountNumber == widget.total
                            ? 'FINISH'
                            : 'NEXT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: _isValid ? ExpndColors.ink : oc.dimmed,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        widget.accountNumber == widget.total
                            ? Icons.check
                            : Icons.arrow_forward,
                        size: 11,
                        color: _isValid ? ExpndColors.ink : oc.dimmed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / edit account
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showAddAccount(BuildContext context, {Account? editing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddAccountSheet(editing: editing),
  );
}

class AddAccountSheet extends StatefulWidget {
  final Account? editing;
  const AddAccountSheet({super.key, this.editing});

  @override
  State<AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<AddAccountSheet> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  AccountType _type = AccountType.bank;
  late String _currencyCode;
  String _colorHex = AccountType.bank.defaultColorHex;

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

  bool get _isEditing => widget.editing != null;

  /// What the balance field was pre-filled with. A negative balance can't be
  /// typed, so it pre-fills empty; leaving the field untouched keeps it.
  String? _balancePrefill;

  bool get _isValid => _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _currencyCode = context.read<SettingsStore>().currencyCode;
    final e = widget.editing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _type = e.type;
      _currencyCode = e.currencyCode;
      // Currency precision, so editing never rounds the stored balance
      // (100.125 KWD) or blocks typing (a JPY "50000.00" fails validation).
      _balanceCtrl.text = e.balance > 0
          ? amountInputText(e.balance, e.currencyCode)
          : '';
      _balancePrefill = _balanceCtrl.text;
      _colorHex = e.colorHex;
      _cardCtrl.text = e.cardDigits ?? '';
      _limitCtrl.text = amountInputText(e.creditLimit ?? 0, e.currencyCode);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _cardCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final store = context.read<AppStore>();
    final name = _nameCtrl.text.trim();
    final e = widget.editing;
    final bal = e != null && _balanceCtrl.text == _balancePrefill
        ? e.balance
        : parseAmount(_balanceCtrl.text) ?? 0;
    Haptics.success();
    final digits = _cardCtrl.text.replaceAll(RegExp(r'\D'), '');
    final cardDigits = digits.isEmpty ? null : digits;
    final limit = _type == AccountType.credit
        ? parseAmount(_limitCtrl.text)
        : null;
    if (e != null) {
      e.name = name;
      e.type = _type;
      e.currencyCode = _currencyCode;
      e.balance = bal;
      e.colorHex = _colorHex;
      e.cardDigits = cardDigits;
      e.creditLimit = (limit ?? 0) > 0 ? limit : null;
      store.updateTransaction();
    } else {
      store.addAccount(
        Account(
          name: name,
          type: _type,
          currencyCode: _currencyCode,
          balance: bal,
          colorHex: _colorHex,
          cardDigits: cardDigits,
          creditLimit: (limit ?? 0) > 0 ? limit : null,
        ),
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    // Shrink above the keyboard so fields never hide behind it — the
    // sheet's fixed height otherwise ignores the keyboard entirely.
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.92 - insets,
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
            _isEditing ? 'Edit account' : 'Add account',
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // Credit cards render taller (232 vs 200); switching type snaps
                // this preview's height and shoves the fields below — animate it.
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: Builder(
                    builder: (context) {
                      final bal = parseAmount(_balanceCtrl.text) ?? 0;
                      final lim = parseAmount(_limitCtrl.text) ?? 0;
                      // Reflect any active EMIs already on the account being edited
                      // so the preview's utilization matches the live wallet card.
                      final emiUsed = _isEditing
                          ? context
                                .read<AppStore>()
                                .emisForAccount(widget.editing!.id)
                                .where((e) => e.isActive)
                                .fold(0.0, (s, e) => s + e.outstandingPrincipal)
                          : 0.0;
                      return AccountCardContent(
                        name: _nameCtrl.text,
                        type: _type,
                        currencyCode: _currencyCode,
                        balance: bal,
                        colorHex: _colorHex,
                        cardDigits: _cardCtrl.text,
                        creditLimit: _type == AccountType.credit ? lim : null,
                        creditUsed: (bal < 0 ? 0 : bal) + emiUsed,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                _label('Account name', oc),
                const SizedBox(height: 8),
                _box(
                  oc,
                  child: TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 14, color: oc.text),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'e.g. Chase Checking, Wallet, HDFC Savings',
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _label('Account type', oc),
                const SizedBox(height: 8),
                _typeGrid(oc, _type, (t) {
                  setState(() {
                    _type = t;
                    if (!_isEditing) _colorHex = t.defaultColorHex;
                  });
                }),
                const SizedBox(height: 22),
                _label(
                  _type == AccountType.cash
                      ? 'CASH IN HAND'
                      : _type == AccountType.credit
                      ? 'AMOUNT USED / OUTSTANDING'
                      : 'CURRENT BALANCE',
                  oc,
                ),
                const SizedBox(height: 8),
                MoneyField(
                  controller: _balanceCtrl,
                  currencyCode: _currencyCode,
                  label: 'Current balance',
                  onChanged: (_) => setState(() {}),
                ),
                if (_type == AccountType.credit) ...[
                  const SizedBox(height: 22),
                  _label('Credit limit', oc),
                  const SizedBox(height: 8),
                  MoneyField(
                    controller: _limitCtrl,
                    currencyCode: _currencyCode,
                    label: 'Credit limit',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 22),
                _label('Card number', oc),
                const SizedBox(height: 8),
                _box(
                  oc,
                  child: TextField(
                    controller: _cardCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(kCardTypedDigits),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: oc.text,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'First $kCardTypedDigits digits (optional)',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The last 6 digits stay masked and can’t be entered.',
                  style: TextStyle(fontSize: 11, color: oc.dimmed),
                ),
                const SizedBox(height: 22),
                _label('Card color', oc),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
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
                          decoration: BoxDecoration(
                            color: hexColor(hex),
                            shape: BoxShape.circle,
                            border: _colorHex == hex
                                ? Border.all(color: Colors.white, width: 2.5)
                                : null,
                          ),
                          child: AnimatedScale(
                            scale: _colorHex == hex ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutBack,
                            child: const Icon(
                              Icons.check,
                              size: 14,
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            sfIcon(
                              _isEditing
                                  ? 'pencil.circle.fill'
                                  : 'plus.circle.fill',
                            ),
                            size: 14,
                            color: _isValid ? ExpndColors.ink : oc.dimmed,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isEditing ? 'Save changes' : 'Add account',
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account card (shared with Wallet)
// ─────────────────────────────────────────────────────────────────────────────

class AccountCardContent extends StatelessWidget {
  final String name;
  final AccountType type;
  final String currencyCode;
  final double balance;
  final String colorHex;
  final String? cardDigits;

  /// Credit-card figures. When [creditLimit] is > 0 and [type] is credit, the
  /// hero switches from balance to available credit with a utilization bar.
  final double? creditLimit;
  final double creditUsed;

  const AccountCardContent({
    super.key,
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.balance,
    required this.colorHex,
    this.cardDigits,
    this.creditLimit,
    this.creditUsed = 0,
  });

  bool get _showCredit => type == AccountType.credit && (creditLimit ?? 0) > 0;

  /// Credit cards carry an extra utilization row, so they need a taller face.
  double get cardHeight => _showCredit ? 232 : 200;

  /// The face height a card of this [type]/[creditLimit] will render at —
  /// lets the Wallet stack reserve the right amount of room for the front card.
  static double heightFor(AccountType type, double? creditLimit) =>
      type == AccountType.credit && (creditLimit ?? 0) > 0 ? 232 : 200;

  @override
  Widget build(BuildContext context) {
    // Card face reproduces the neoPOP credit-card layout: name/network top,
    // EMV chip, then the balance as hero with a masked-holder row beneath.
    final cardColor = hexColor(colorHex);
    const faceText = Color(0xFFD2D2D2); // pop white / 100
    // The card is a fixed-dimension visual (like a physical bank card), so its
    // text renders at design size regardless of the app-wide text boost / user
    // Dynamic Type — otherwise enlarged text overflows the fixed card height.
    return MediaQuery.withNoTextScaling(
      child: NeoPopElevated(
        faceColor: cardColor,
        depthColor: Colors.black,
        borderColor: Colors.white.withValues(alpha: 0.14),
        depth: 0,
        cornerRadius: 5,
        child: SizedBox(
          height: cardHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              children: [
                const Positioned.fill(child: CardGuilloche()),
                Positioned.fill(
                  child: NeoPopShine(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
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
                                  name.isEmpty ? 'Account Name' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  type.raw.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                    color: faceText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            sfIcon(type.icon),
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const CardChip(),
                      const Spacer(),
                      Text(
                        _showCredit ? 'AVAILABLE CREDIT' : 'TOTAL BALANCE',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: faceText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatCurrency(
                            _showCredit
                                ? ((creditLimit ?? 0) - creditUsed).clamp(
                                    0.0,
                                    creditLimit ?? 0,
                                  )
                                : balance,
                            currencyCode,
                          ),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (_showCredit) ...[
                        const SizedBox(height: 8),
                        _UtilizationBar(
                          fraction:
                              ((creditLimit ?? 0) <= 0
                                      ? 0.0
                                      : creditUsed / (creditLimit ?? 1))
                                  .clamp(0.0, 1.0),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${formatCurrency(creditUsed, currencyCode)} used',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: faceText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Limit ${formatCurrency(creditLimit ?? 0, currencyCode)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: faceText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              maskedCardNumber(cardDigits),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: faceText,
                              ),
                            ),
                          ),
                          // No currency tag: the app runs on one currency,
                          // so naming it on every card only added noise.
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A slim utilization meter drawn on the card face — green under 30%, amber
/// under 75%, red past that, mirroring how card apps flag heavy usage.
class _UtilizationBar extends StatelessWidget {
  final double fraction;
  const _UtilizationBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final color = f < 0.3
        ? const Color(0xFF34D399)
        : f < 0.75
        ? const Color(0xFFFBBF24)
        : const Color(0xFFF87171);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: f,
        minHeight: 6,
        backgroundColor: Colors.white.withValues(alpha: 0.22),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _label(String t, ExpndColors oc) => Text(
  t,
  style: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.3,
    color: oc.muted,
  ),
);

Widget _box(ExpndColors oc, {required Widget child}) => Container(
  constraints: const BoxConstraints(minHeight: 44),
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  decoration: BoxDecoration(
    color: oc.bg,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: oc.border, width: 1.5),
  ),
  child: child,
);

Widget _typeGrid(
  ExpndColors oc,
  AccountType selected,
  ValueChanged<AccountType> onSelect,
) {
  return GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    // Slightly taller cells so a two-line type name ("Credit Card") plus icon
    // clears the tile even at a bumped-up system text size.
    childAspectRatio: 1.0,
    children: [
      for (final t in AccountType.values)
        Builder(
          builder: (context) {
            final sel = selected == t;
            return GestureDetector(
              onTap: () {
                Haptics.light();
                onSelect(t);
              },
              child: AnimatedScale(
                scale: sel ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? ExpndColors.gold : oc.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? ExpndColors.goldDark : oc.border,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sfIcon(t.icon),
                        size: 16,
                        color: sel
                            ? ExpndColors.ink
                            : hexColor(t.defaultColorHex),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          t.raw,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: sel ? ExpndColors.ink : oc.muted,
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
    ],
  );
}

Future<String?> showCurrencyPicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
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
              'SELECT CURRENCY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: supportedCurrencies.length,
                itemBuilder: (context, i) {
                  final c = supportedCurrencies[i];
                  return ListTile(
                    onTap: () {
                      Haptics.light();
                      Navigator.of(context).pop(c.code);
                    },
                    leading: SizedBox(
                      width: 40,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          c.symbol,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: oc.accent,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      c.code,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: oc.text,
                      ),
                    ),
                    subtitle: Text(
                      c.name,
                      style: TextStyle(fontSize: 11, color: oc.muted),
                    ),
                    trailing: current == c.code
                        ? Icon(sfIcon('checkmark'), size: 14, color: oc.accent)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
