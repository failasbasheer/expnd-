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

// ─────────────────────────────────────────────────────────────────────────────
// Credit summary + ongoing EMIs (shown under a credit-card account)
// ─────────────────────────────────────────────────────────────────────────────

/// The loans and installment plans running against an account, plus — for a
/// credit card — the limit / used / available breakdown above them.
///
/// Loans are not a credit-card-only idea: a car, personal or home loan sits
/// against a bank account and is repaid from it, and the amortization model
/// never cared which kind of account it hung off. Only this section used to,
/// so the whole feature was invisible unless you owned a credit card.
class AccountLoansSection extends StatelessWidget {
  final Account account;
  const AccountLoansSection({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final emis = store.emisForAccount(account.id);
    final isCredit = account.type == AccountType.credit;
    final limit = account.creditLimit ?? 0;
    final used = store.creditUsedFor(account);
    final available = store.creditAvailableFor(account);
    final util = store.creditUtilizationFor(account);

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
            if (isCredit) ...[
            Text('CREDIT SUMMARY',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: oc.muted)),
            const SizedBox(height: 12),
            if (limit <= 0)
              Text(
                  'Set a credit limit for this card to track available credit and utilization.',
                  style: TextStyle(fontSize: 12, color: oc.dimmed))
            else ...[
              Text('AVAILABLE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: oc.muted)),
              const SizedBox(height: 2),
              Text(formatCurrency(available, code),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: oc.text)),
              const SizedBox(height: 10),
              _UtilRow(fraction: util),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${(util * 100).toStringAsFixed(0)}% utilized',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: oc.muted)),
                  const Spacer(),
                  Text(
                      '${formatCurrency(used, code)} of ${formatCurrency(limit, code)}',
                      style: TextStyle(fontSize: 11, color: oc.dimmed)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(height: 1, color: oc.border),
            const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(isCredit ? 'ONGOING EMIs' : 'LOANS & EMIs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: oc.muted)),
                ),
                const SizedBox(width: 8),
                NeoPopButton(
                  onPressed: () {
                    Haptics.light();
                    showAddEmi(context, accountId: account.id);
                  },
                  depth: 3,
                  cornerRadius: 4,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sfIcon('plus'), size: 10, color: ExpndColors.ink),
                        const SizedBox(width: 5),
                        Text(isCredit ? 'ADD EMI' : 'ADD LOAN',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: ExpndColors.ink)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (emis.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    isCredit
                        ? 'No EMIs yet. Add a loan or purchase installment to track it here — it reduces your available credit as it runs.'
                        : 'No loans yet. Add a car, personal or home loan to track its balance, interest and monthly payment here.',
                    style: TextStyle(fontSize: 12, color: oc.dimmed)),
              )
            else
              for (int i = 0; i < emis.length; i++) ...[
                _EmiRow(emi: emis[i], account: account, code: code),
                if (i != emis.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(height: 1, color: oc.border),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _EmiRow extends StatelessWidget {
  final Emi emi;
  final Account account;
  final String code;
  const _EmiRow({required this.emi, required this.account, required this.code});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final done = !emi.isActive;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        showAddEmi(context, accountId: account.id, editing: emi);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(emi.name.isEmpty ? 'EMI' : emi.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: oc.text)),
              ),
              const SizedBox(width: 8),
              Text('${formatCurrency(emi.monthlyAmount, code)}/mo',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: oc.accent)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: emi.progress,
              minHeight: 5,
              backgroundColor: oc.border,
              valueColor: AlwaysStoppedAnimation(
                  done ? ExpndColors.green : oc.accent),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                    done
                        ? 'Completed · ${emi.tenureMonths} mo'
                        : 'Paid ${emi.monthsPaid}/${emi.tenureMonths} mo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: oc.muted)),
              ),
              const Spacer(),
              Text(
                  done
                      ? 'Closed'
                      : '${formatCurrency(emi.remainingAmount, code)} left',
                  style: TextStyle(fontSize: 11, color: oc.dimmed)),
            ],
          ),
          // What has actually been recorded as paid, which the schedule above
          // can't say — it only knows how many months have gone by.
          Builder(builder: (context) {
            final store = context.watch<AppStore>();
            final logged = store.installmentsOn(emi).length;
            final paidThisMonth = store.isInstallmentPaid(emi, DateTime.now());
            if (done && logged == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                        logged == 0
                            ? 'No payments recorded'
                            : '$logged recorded · '
                                '${formatCurrency(store.paidOn(emi), code)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: oc.dimmed)),
                  ),
                  const Spacer(),
                  if (!done)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: paidThisMonth
                          ? null
                          : () => showPayInstallment(context, emi),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: paidThisMonth
                                  ? oc.border
                                  : ExpndColors.gold.withValues(alpha: 0.6),
                              width: 1.5),
                        ),
                        child: Text(
                            paidThisMonth ? 'PAID THIS MONTH' : 'MARK PAID',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                                color: paidThisMonth ? oc.dimmed : oc.accent)),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _UtilRow extends StatelessWidget {
  final double fraction;
  const _UtilRow({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final f = fraction.clamp(0.0, 1.0);
    final color = f < 0.3
        ? ExpndColors.green
        : f < 0.75
            ? const Color(0xFFF59E0B)
            : ExpndColors.red;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: f,
        minHeight: 8,
        backgroundColor: oc.border,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / edit EMI — doubles as a live EMI calculator
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showAddEmi(BuildContext context,
    {required String accountId, Emi? editing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddEmiSheet(accountId: accountId, editing: editing),
  );
}

class _AddEmiSheet extends StatefulWidget {
  final String accountId;
  final Emi? editing;
  const _AddEmiSheet({required this.accountId, this.editing});

  @override
  State<_AddEmiSheet> createState() => _AddEmiSheetState();
}

class _AddEmiSheetState extends State<_AddEmiSheet> {
  final _nameCtrl = TextEditingController();
  final _principalCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _tenureCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();

  bool get _isEditing => widget.editing != null;

  double get _principal => double.tryParse(_principalCtrl.text) ?? 0;
  double get _rate => double.tryParse(_rateCtrl.text) ?? 0;
  int get _tenure => int.tryParse(_tenureCtrl.text) ?? 0;

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty && _principal > 0 && _tenure > 0;

  /// A throwaway model used purely to run the amortization math live.
  Emi get _preview => Emi(
        accountId: widget.accountId,
        name: _nameCtrl.text,
        principal: _principal,
        annualRate: _rate,
        tenureMonths: _tenure,
        startDate: _startDate,
      );

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _principalCtrl.text = e.principal > 0 ? _trim(e.principal) : '';
      _rateCtrl.text = e.annualRate > 0 ? _trim(e.annualRate) : '';
      _tenureCtrl.text = e.tenureMonths > 0 ? '${e.tenureMonths}' : '';
      _startDate = e.startDate;
    }
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _principalCtrl.dispose();
    _rateCtrl.dispose();
    _tenureCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final store = context.read<AppStore>();
    Haptics.success();
    final e = widget.editing;
    if (e != null) {
      e.name = _nameCtrl.text.trim();
      e.principal = _principal;
      e.annualRate = _rate;
      e.tenureMonths = _tenure;
      e.startDate = _startDate;
      store.updateEmi();
    } else {
      store.addEmi(Emi(
        accountId: widget.accountId,
        name: _nameCtrl.text.trim(),
        principal: _principal,
        annualRate: _rate,
        tenureMonths: _tenure,
        startDate: _startDate,
      ));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  void _delete() {
    final store = context.read<AppStore>();
    Haptics.warning();
    store.deleteEmi(widget.editing!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final code = context.watch<SettingsStore>().currencyCode;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final p = _preview;
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
                  color: oc.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Text(_isEditing ? 'EDIT EMI' : 'ADD EMI',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: oc.text)),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // Live calculation summary — this is the EMI calculator.
                _calcCard(oc, code, p),
                const SizedBox(height: 22),
                _label('EMI NAME', oc),
                const SizedBox(height: 8),
                _field(
                  oc,
                  child: TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 14, color: oc.text),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'e.g. iPhone, Car Loan'),
                  ),
                ),
                const SizedBox(height: 18),
                _label('LOAN AMOUNT (PRINCIPAL)', oc),
                const SizedBox(height: 8),
                _amountField(oc, code, _principalCtrl),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('INTEREST % / YR', oc),
                          const SizedBox(height: 8),
                          _field(
                            oc,
                            child: TextField(
                              controller: _rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(fontSize: 16, color: oc.text),
                              decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: '0.0'),
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
                          _label('TENURE (MONTHS)', oc),
                          const SizedBox(height: 8),
                          _field(
                            oc,
                            child: TextField(
                              controller: _tenureCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(fontSize: 16, color: oc.text),
                              decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: '12'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _label('START DATE', oc),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    FocusScope.of(context).unfocus();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: oc.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: oc.border, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(sfIcon('calendar'), size: 14, color: oc.muted),
                        const SizedBox(width: 10),
                        Text(_fmtDate(_startDate),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: oc.text)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                      child: Text(_isEditing ? 'SAVE CHANGES' : 'ADD EMI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: _isValid ? ExpndColors.ink : oc.dimmed)),
                    ),
                  ),
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _delete,
                    child: Text('Delete EMI',
                        style: TextStyle(
                            color: ExpndColors.red,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calcCard(ExpndColors oc, String code, Emi p) {
    final valid = _principal > 0 && _tenure > 0;
    return NeoPopElevated(
      faceColor: ExpndColors.gold,
      depthColor: ExpndColors.goldDark,
      borderColor: ExpndColors.goldDark,
      depth: 5,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MONTHLY EMI',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: ExpndColors.ink.withValues(alpha: 0.55))),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                  valid ? formatCurrency(p.monthlyAmount, code) : '—',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: ExpndColors.ink)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _calcStat('TOTAL PAYABLE',
                    valid ? formatCurrency(p.totalPayable, code) : '—'),
                const SizedBox(width: 16),
                _calcStat('TOTAL INTEREST',
                    valid ? formatCurrency(p.totalInterest, code) : '—'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _calcStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: ExpndColors.ink.withValues(alpha: 0.55))),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ExpndColors.ink)),
        ],
      ),
    );
  }

  Widget _amountField(
      ExpndColors oc, String code, TextEditingController ctrl) {
    return _field(
      oc,
      child: Row(
        children: [
          Text(currencySymbol(code),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: oc.accent)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: amountInputFormatters,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: oc.text),
              decoration: const InputDecoration(
                  border: InputBorder.none, isDense: true, hintText: '0.00'),
            ),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

Widget _label(String t, ExpndColors oc) => Text(t,
    style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        color: oc.muted));

Widget _field(ExpndColors oc, {required Widget child}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: oc.border, width: 1.5),
      ),
      child: child,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Mark an installment paid
// ─────────────────────────────────────────────────────────────────────────────

/// Records one installment of [emi] as really paid.
///
/// An EMI schedule is a plan; paying it is a fact, and until now the app held
/// only the plan — the money left your bank every month and nothing in EXPND
/// moved. This writes an ordinary expense against the account the cash
/// actually came from, tagged to the EMI.
///
/// The funding account is asked for rather than assumed: the installment
/// usually leaves a bank account, while the EMI itself hangs off the card it
/// was taken on, and a credit card's balance here is set by hand — so posting
/// against the card by default would quietly count the same money twice.
Future<bool> showPayInstallment(BuildContext context, Emi emi) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PayInstallmentSheet(emi: emi),
  );
  return paid ?? false;
}

class _PayInstallmentSheet extends StatefulWidget {
  final Emi emi;
  const _PayInstallmentSheet({required this.emi});

  @override
  State<_PayInstallmentSheet> createState() => _PayInstallmentSheetState();
}

class _PayInstallmentSheetState extends State<_PayInstallmentSheet> {
  String? _accountId;
  late final TextEditingController _amountCtrl = TextEditingController(
      text: widget.emi.monthlyAmount.toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    final accounts = context.read<AppStore>().accounts;
    // Default to somewhere the money could plausibly come from — a bank or
    // cash account before the card the EMI is attached to.
    final funding = accounts.where((a) =>
        a.type == AccountType.bank ||
        a.type == AccountType.cash ||
        a.type == AccountType.savings);
    _accountId = funding.isNotEmpty
        ? funding.first.id
        : (accounts.isNotEmpty ? accounts.first.id : null);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;
  bool get _isValid => _amount > 0;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final e = widget.emi;
    final accounts = store.accounts;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final n = (e.monthsPaid + 1).clamp(1, e.tenureMonths);

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85 - insets),
      margin: EdgeInsets.only(bottom: insets),
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: oc.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          Text('MARK INSTALLMENT PAID',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: oc.text)),
          const SizedBox(height: 2),
          Text(
              '${e.name.trim().isEmpty ? 'EMI' : e.name.trim()} · '
              'installment $n of ${e.tenureMonths}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: oc.muted)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                _label('AMOUNT', oc),
                const SizedBox(height: 8),
                _field(oc,
                    child: Row(
                      children: [
                        Text(currencySymbol(code),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: oc.accent)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: amountInputFormatters,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: oc.text),
                            decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: '0.00'),
                          ),
                        ),
                      ],
                    )),
                const SizedBox(height: 6),
                Text(
                    'Scheduled ${formatCurrency(e.monthlyAmount, code)} — '
                    "edit if your lender's rounding differs.",
                    style: TextStyle(fontSize: 10, color: oc.dimmed)),
                const SizedBox(height: 20),
                _label('PAY FROM', oc),
                const SizedBox(height: 8),
                if (accounts.isEmpty)
                  Text('No accounts yet — the payment will be recorded without one.',
                      style: TextStyle(fontSize: 12, color: oc.muted))
                else
                  for (final a in accounts) _accountOption(oc, store, a, code),
                const SizedBox(height: 20),
                _payButton(oc),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountOption(
      ExpndColors oc, AppStore store, Account a, String code) {
    final selected = _accountId == a.id;
    final tint = hexColor(a.colorHex);
    final isCard = a.type == AccountType.credit;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        setState(() => _accountId = a.id);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold.withValues(alpha: 0.12) : oc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? ExpndColors.gold : oc.border, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(sfIcon(selected ? 'checkmark.circle.fill' : 'circle'),
                size: 16, color: selected ? ExpndColors.gold : oc.dimmed),
            const SizedBox(width: 10),
            Icon(sfIcon(a.type.icon), size: 13, color: tint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: oc.text)),
            ),
            const SizedBox(width: 8),
            Text(
                isCard
                    ? 'the card itself'
                    : formatCurrency(store.balanceFor(a), code),
                style: TextStyle(
                    fontSize: 10,
                    fontStyle: isCard ? FontStyle.italic : FontStyle.normal,
                    color: oc.dimmed)),
          ],
        ),
      ),
    );
  }

  Widget _payButton(ExpndColors oc) {
    return NeoPopButton(
      onPressed: () {
        if (!_isValid) return;
        context
            .read<AppStore>()
            .payEmiInstallment(widget.emi,
                accountId: _accountId, amount: _amount);
        Haptics.success();
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(true);
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
              Icon(sfIcon('checkmark.circle.fill'),
                  size: 14, color: _isValid ? ExpndColors.ink : oc.dimmed),
              const SizedBox(width: 8),
              Text('POST PAYMENT',
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
