import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/reconciliation.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../widgets/app_header.dart';
import 'transaction_detail.dart';

class ReconciliationView extends StatefulWidget {
  final String? accountId;
  const ReconciliationView({super.key, this.accountId});

  @override
  State<ReconciliationView> createState() => _ReconciliationViewState();
}

class _ReconciliationViewState extends State<ReconciliationView> {
  final _amount = TextEditingController();
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _showResult = false;
  bool _negativeBalance = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accountId;
    _amount.addListener(() {
      setState(() => _showResult = false);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final accounts = store.accounts;
    final selected =
        accounts.where((a) => a.id == _accountId).firstOrNull ??
        (accounts.isEmpty ? null : accounts.first);
    final amount = parseAmount(_amount.text);
    final result = _showResult && selected != null && amount != null
        ? reconcileAccount(
            store: store,
            account: selected,
            statementBalance: _negativeBalance ? -amount : amount,
            statementDate: _date,
          )
        : null;
    // One app-wide currency: display never follows Account.currencyCode.
    final code = _appCurrency(context, selected?.currencyCode);
    final dates = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: closablePageBar(context, 'Check account balance'),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Compare the balance in EXPND with the balance shown by your bank. Use the same date for both.',
            ),
            const SizedBox(height: 20),
            if (selected == null)
              const Text(
                'No accounts yet. Add one in Wallet, then come back to check its balance.',
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: selected.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: accounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (id) => setState(() {
                  _accountId = id;
                  _showResult = false;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: amountFormattersFor(code),
                decoration: InputDecoration(
                  labelText: selected.type == AccountType.credit
                      ? 'Bank card balance owed'
                      : 'Balance shown by bank',
                  prefixText: '${currencySymbol(code)} ',
                  helperText: 'Enter the amount shown for the selected date.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Negative balance'),
                subtitle: Text(
                  selected.type == AccountType.credit
                      ? 'Your bank shows a credit in your favour'
                      : 'Your account is overdrawn',
                ),
                value: _negativeBalance,
                onChanged: (value) => setState(() {
                  _negativeBalance = value;
                  _showResult = false;
                }),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('As of date'),
                subtitle: Text(dates.formatMediumDate(_date)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _date = picked;
                      _showResult = false;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: amount == null || !amount.isFinite
                    ? null
                    : () {
                        FocusScope.of(context).unfocus();
                        setState(() => _showResult = true);
                      },
                child: const Text('Compare balances'),
              ),
              if (result != null) ...[
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.balanced(code)
                                ? 'Balances match'
                                : 'Difference to review',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(_differenceSummary(result, selected, code)),
                          const SizedBox(height: 12),
                          _balanceRow('In EXPND', result.ledgerBalance, code),
                          _balanceRow(
                            'At your bank',
                            result.statementBalance,
                            code,
                          ),
                          const Divider(),
                          _balanceRow(
                            'Difference (bank − EXPND)',
                            result.difference,
                            code,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!result.balanced(code)) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Nothing has been changed. To fix it, look for a missing entry, '
                    'a different posting date, or an entry recorded twice, then '
                    'add or edit it. If everything looks right, update the '
                    "account's opening balance in Wallet.",
                  ),
                ],
                if (result.possibleDuplicates.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Possible duplicates',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Same note and amount within two days. Open each entry to '
                    'compare before deleting either one.',
                  ),
                  for (final pair in result.possibleDuplicates)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          for (final t in [pair.$1, pair.$2])
                            _entryTile(context, t, selected, code),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Recent entries through this date',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  result.recentTransactions.isEmpty
                      ? 'No entries recorded for this account up to this date. '
                            'Add any missing ones from Home.'
                      : 'Latest ${result.recentTransactions.length} entries. Tap one to review or edit it.',
                ),
                for (final t in result.recentTransactions)
                  _entryTile(context, t, selected, code),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Plain-language reading of the difference so users don't have to work
  /// out the sign themselves.
  String _differenceSummary(
    ReconciliationResult result,
    Account account,
    String code,
  ) {
    if (result.balanced(code)) {
      return 'EXPND agrees with your bank on this date.';
    }
    final gap = formatCurrency(result.difference.abs(), code);
    final bankHigher = result.difference > 0;
    if (account.type == AccountType.credit) {
      return bankHigher
          ? 'Your bank says you owe $gap more than EXPND shows.'
          : 'Your bank says you owe $gap less than EXPND shows.';
    }
    return bankHigher
        ? 'Your bank shows $gap more than EXPND.'
        : 'Your bank shows $gap less than EXPND.';
  }

  Widget _entryTile(
    BuildContext context,
    Transaction t,
    Account account,
    String code,
  ) {
    final into = t.type == TransactionType.transfer
        ? t.toAccountId == account.id
        : t.type == TransactionType.income;
    final direction = t.type == TransactionType.transfer
        ? (into ? 'Transfer in' : 'Transfer out')
        : (into ? 'Money in' : 'Money out');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      minVerticalPadding: 8,
      onTap: () => showTransactionDetail(context, t),
      title: Text(
        t.note.isEmpty ? t.category.raw : t.note,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${MaterialLocalizations.of(context).formatMediumDate(t.date)} · $direction',
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.35,
        ),
        child: Text(
          '${into ? '+' : '−'}${formatCurrency(t.amount, code)}',
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _balanceRow(String label, double value, String code) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(formatCurrency(value, code), textAlign: TextAlign.end),
        ),
      ],
    ),
  );
}

/// The app-wide currency, falling back to the account's stored code only when
/// no [SettingsStore] is provided (isolated widget tests).
String _appCurrency(BuildContext context, String? fallback) {
  try {
    return Provider.of<SettingsStore>(context).currencyCode;
  } on ProviderNotFoundException {
    return fallback ?? 'USD';
  }
}
