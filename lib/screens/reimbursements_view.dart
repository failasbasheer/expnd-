import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../widgets/app_header.dart';

class ReimbursementsView extends StatefulWidget {
  final String? purchaseId;
  const ReimbursementsView({super.key, this.purchaseId});

  @override
  State<ReimbursementsView> createState() => _ReimbursementsViewState();
}

class _ReimbursementsViewState extends State<ReimbursementsView> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    // One app-wide currency: display never follows Account.currencyCode.
    final code = _appCurrency(context);
    final purchases = store.transactions
        .where((t) => t.type == TransactionType.expense && !t.isRecurring)
        .toList();
    final purchaseIds = {
      for (final t in store.transactions)
        if (t.type == TransactionType.expense) t.id,
    };
    // Money back whose purchase was later deleted: still real income, but it
    // has nothing to attach to, so it gets its own section.
    final orphans = store.transactions
        .where(
          (t) =>
              t.type == TransactionType.income &&
              t.relatedPurchaseId != null &&
              !purchaseIds.contains(t.relatedPurchaseId),
        )
        .toList();
    final missingPurchase =
        widget.purchaseId != null &&
        !store.transactions.any((t) => t.id == widget.purchaseId);
    final awaiting = purchases
        .where(
          (t) =>
              t.reimbursementExpected != null &&
              store.reimbursementOutstanding(t) > 0,
        )
        .toList();
    final awaitingTotal = awaiting.fold(
      0.0,
      (sum, t) => sum + store.reimbursementOutstanding(t),
    );
    final visible = _showAll
        ? purchases
        : purchases
              .where(
                (t) =>
                    t.reimbursementExpected != null ||
                    t.id == widget.purchaseId ||
                    store.returnsFor(t).isNotEmpty,
              )
              .toList();

    return Scaffold(
      appBar: closablePageBar(context, 'Money coming back'),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Track money someone owes you for a purchase, and link refunds to '
              'the original purchase. Nothing is added to your balance until '
              'you record that the money arrived.',
            ),
            const SizedBox(height: 16),
            if (missingPurchase)
              const Card(
                margin: EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Original purchase deleted'),
                  subtitle: Text(
                    'The purchase you opened no longer exists. Any money '
                    'already received for it is listed below.',
                  ),
                ),
              ),
            if (awaiting.isNotEmpty)
              Semantics(
                container: true,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatCurrency(awaitingTotal, code)} still expected',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          awaiting.length == 1
                              ? 'From 1 purchase'
                              : 'From ${awaiting.length} purchases',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show all purchases'),
              subtitle: const Text('Choose a purchase to track or refund'),
              value: _showAll,
              onChanged: purchases.isEmpty
                  ? null
                  : (value) => setState(() => _showAll = value),
            ),
            if (visible.isEmpty && orphans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  purchases.isEmpty
                      ? 'No purchases yet. Add an expense first, then track '
                            'its reimbursement or refund here.'
                      : 'Nothing tracked yet. Turn on "Show all purchases" '
                            'and pick the one you expect money back for.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final purchase in visible)
              _purchaseCard(context, store, purchase, code),
            if (orphans.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Original purchase deleted',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'This money is already counted in your balance. Keep it as '
                'regular income, or delete it if it was recorded by mistake.',
              ),
              for (final t in orphans) _orphanCard(context, store, t, code),
            ],
          ],
        ),
      ),
    );
  }

  Widget _purchaseCard(
    BuildContext context,
    AppStore store,
    Transaction purchase,
    String code,
  ) {
    final expected = purchase.reimbursementExpected;
    final remaining = store.reimbursementOutstanding(purchase);
    final refunded = store.returnedFor(purchase, kind: 'refund');
    final received = store.returnedFor(purchase, kind: 'reimbursement');
    final availableToRefund = purchase.amount - store.returnedFor(purchase);
    final canTrack = purchase.amount - refunded > 0.000001;
    final title = purchase.note.isEmpty ? purchase.category.raw : purchase.note;
    final highlighted = purchase.id == widget.purchaseId;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${formatCurrency(purchase.amount, code)} · ${MaterialLocalizations.of(context).formatMediumDate(purchase.date)}',
            ),
            if (expected != null) ...[
              const SizedBox(height: 8),
              Text(
                remaining > 0
                    ? '${purchase.reimbursementFrom ?? 'Reimbursement'} owes '
                          '${formatCurrency(remaining, code)} of '
                          '${formatCurrency(expected, code)}'
                    : '${purchase.reimbursementFrom ?? 'Reimbursement'} paid '
                          'back in full',
              ),
              if (received > 0 && remaining > 0)
                Text('Received so far: ${formatCurrency(received, code)}'),
            ],
            if (refunded > 0)
              Text('Refunded: ${formatCurrency(refunded, code)}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (remaining > 0)
                  FilledButton.tonal(
                    onPressed: () => _record(
                      context,
                      store,
                      purchase,
                      code,
                      'reimbursement',
                    ),
                    child: const Text('Record reimbursement'),
                  ),
                if (availableToRefund > 0.000001)
                  FilledButton.tonal(
                    onPressed: () =>
                        _record(context, store, purchase, code, 'refund'),
                    child: const Text('Record refund'),
                  ),
                if (canTrack || expected != null)
                  OutlinedButton(
                    onPressed: () => _track(context, store, purchase, code),
                    child: Text(
                      expected == null
                          ? 'Track reimbursement'
                          : 'Edit tracking',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _orphanCard(
    BuildContext context,
    AppStore store,
    Transaction t,
    String code,
  ) {
    final refund = t.relatedPurchaseKind == 'refund';
    final kindLabel = refund ? 'Refund' : 'Reimbursement';
    // Returns are noted "Refund: <purchase note>"; with an empty purchase note
    // that leaves just the prefix, so fall back to the kind.
    final note = t.note.trim();
    final title = note.isEmpty || note == 'Refund:' || note == 'Reimbursement:'
        ? kindLabel
        : note;
    final account = store.accountFor(t.accountId);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$kindLabel received · ${formatCurrency(t.amount, code)} · '
              '${MaterialLocalizations.of(context).formatMediumDate(t.date)}'
              '${account == null ? '' : ' · ${account.name}'}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    t.relatedPurchaseId = null;
                    t.relatedPurchaseKind = null;
                    store.updateTransaction();
                    _toast('Kept as income.');
                  },
                  child: const Text('Keep as income'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _confirmDeleteOrphan(context, store, t),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteOrphan(
    BuildContext context,
    AppStore store,
    Transaction t,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'The money will be removed from your balance. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    store.deleteTransaction(t);
    _toast('Entry deleted.');
  }

  Future<void> _track(
    BuildContext context,
    AppStore store,
    Transaction purchase,
    String code,
  ) async {
    final result = await showDialog<_TrackResult>(
      context: context,
      builder: (_) =>
          _TrackDialog(store: store, purchase: purchase, code: code),
    );
    if (result == null || !mounted) return;
    if (result.stop) {
      store.stopTrackingReimbursement(purchase);
      _toast('Stopped tracking. Money already received stays recorded.');
      return;
    }
    try {
      store.trackReimbursement(
        purchase,
        expected: result.expected!,
        from: result.from!,
      );
    } on ArgumentError catch (e) {
      _toast('${e.message}');
    }
  }

  Future<void> _record(
    BuildContext context,
    AppStore store,
    Transaction purchase,
    String code,
    String kind,
  ) async {
    // The store rejects accounts whose stored code differs from the purchase
    // account's, so only offer accounts it will accept.
    final purchaseAccount = store.accountFor(purchase.accountId);
    final accounts = store.accounts
        .where(
          (a) =>
              purchaseAccount == null ||
              a.currencyCode == purchaseAccount.currencyCode,
        )
        .toList();
    if (accounts.isEmpty) {
      _toast('Add an account in Wallet first to record money received.');
      return;
    }
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (_) => _RecordDialog(
        store: store,
        purchase: purchase,
        code: code,
        kind: kind,
        accounts: accounts,
      ),
    );
    if (result == null || !mounted) return;
    try {
      store.recordPurchaseReturn(
        purchase,
        amount: result.$1,
        accountId: result.$2,
        kind: kind,
      );
      _toast(kind == 'refund' ? 'Refund recorded.' : 'Reimbursement recorded.');
    } on ArgumentError catch (e) {
      _toast('${e.message}');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The app-wide currency, falling back to USD only when no [SettingsStore] is
/// provided (isolated widget tests).
String _appCurrency(BuildContext context) {
  try {
    return Provider.of<SettingsStore>(context).currencyCode;
  } on ProviderNotFoundException {
    return 'USD';
  }
}

class _TrackResult {
  final bool stop;
  final double? expected;
  final String? from;
  const _TrackResult.save(this.expected, this.from) : stop = false;
  const _TrackResult.stop() : stop = true, expected = null, from = null;
}

/// Owns its controllers so they outlive the dialog's exit animation.
class _TrackDialog extends StatefulWidget {
  final AppStore store;
  final Transaction purchase;
  final String code;
  const _TrackDialog({
    required this.store,
    required this.purchase,
    required this.code,
  });

  @override
  State<_TrackDialog> createState() => _TrackDialogState();
}

class _TrackDialogState extends State<_TrackDialog> {
  final _key = GlobalKey<FormState>();
  late final _from = TextEditingController(
    text: widget.purchase.reimbursementFrom ?? '',
  );
  late final _amount = TextEditingController(
    text: amountInputText(
      widget.purchase.reimbursementExpected ?? widget.purchase.amount,
      widget.code,
    ),
  );

  @override
  void dispose() {
    _from.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _close([_TrackResult? result]) {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, result);
  }

  Future<void> _confirmStop() async {
    FocusScope.of(context).unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop tracking?'),
        content: const Text(
          'This purchase will no longer show money owed to you. Any '
          'reimbursement already recorded stays in your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep tracking'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Stop tracking'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _close(const _TrackResult.stop());
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final purchase = widget.purchase;
    final code = widget.code;
    final maxExpected =
        purchase.amount - store.returnedFor(purchase, kind: 'refund');
    final received = store.returnedFor(purchase, kind: 'reimbursement');
    final tracking = purchase.reimbursementExpected != null;
    return AlertDialog(
      title: Text(tracking ? 'Edit tracking' : 'Track reimbursement'),
      scrollable: true,
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _from,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Who will pay you back?',
                hintText: 'e.g. Employer, Alex',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter a person or source'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: amountFormattersFor(code),
              decoration: InputDecoration(
                labelText: 'Expected amount',
                prefixText: '${currencySymbol(code)} ',
                helperText: 'Up to ${formatCurrency(maxExpected, code)}',
              ),
              validator: (v) {
                final n = parseAmount(v ?? '');
                if (n == null || n <= 0 || n > maxExpected + 0.000001) {
                  return 'Enter an amount up to ${formatCurrency(maxExpected, code)}';
                }
                if (n < received - 0.000001) {
                  return 'Can\'t be less than the ${formatCurrency(received, code)} already received';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (tracking)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _confirmStop,
            child: const Text('Stop tracking'),
          ),
        TextButton(onPressed: _close, child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_key.currentState!.validate()) {
              _close(
                _TrackResult.save(
                  parseAmount(_amount.text)!,
                  _from.text.trim(),
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Owns its controller so it outlives the dialog's exit animation.
class _RecordDialog extends StatefulWidget {
  final AppStore store;
  final Transaction purchase;
  final String code;
  final String kind;
  final List<Account> accounts;
  const _RecordDialog({
    required this.store,
    required this.purchase,
    required this.code,
    required this.kind,
    required this.accounts,
  });

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _key = GlobalKey<FormState>();
  late final double _cap = widget.kind == 'refund'
      ? widget.purchase.amount - widget.store.returnedFor(widget.purchase)
      : widget.store.reimbursementOutstanding(widget.purchase);
  late final _amount = TextEditingController(
    text: amountInputText(_cap, widget.code),
  );
  late String _accountId =
      widget.accounts.any((a) => a.id == widget.purchase.accountId)
      ? widget.purchase.accountId!
      : widget.accounts.first.id;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _close([(double, String)? result]) {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    final refund = widget.kind == 'refund';
    return AlertDialog(
      scrollable: true,
      title: Text(refund ? 'Record refund' : 'Record reimbursement'),
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              refund
                  ? 'Adds the refund as income, linked to this purchase.'
                  : 'Adds the money you got back as income, linked to this '
                        'purchase.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: amountFormattersFor(code),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '${currencySymbol(code)} ',
                helperText: 'Up to ${formatCurrency(_cap, code)}',
              ),
              validator: (v) {
                final n = parseAmount(v ?? '');
                return n == null || n <= 0 || n > _cap + 0.000001
                    ? 'Enter an amount up to ${formatCurrency(_cap, code)}'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Received in account',
              ),
              items: widget.accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() => _accountId = id ?? _accountId),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_key.currentState!.validate()) {
              _close((parseAmount(_amount.text)!, _accountId));
            }
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
