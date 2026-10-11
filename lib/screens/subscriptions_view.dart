import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/subscriptions.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../widgets/app_header.dart';
import 'add_transaction.dart';

Future<void> showSubscriptions(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const SubscriptionManagerView()));

class SubscriptionManagerView extends StatelessWidget {
  const SubscriptionManagerView({super.key});

  Future<void> _setTrialEnd(
    BuildContext context,
    Transaction transaction,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: transaction.subscriptionTrialEndDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      helpText: 'When does the free trial end?',
    );
    if (picked == null || !context.mounted) return;
    transaction.subscriptionTrialEndDate = picked;
    context.read<AppStore>().updateTransaction();
  }

  Future<void> _stop(BuildContext context, Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop tracking this subscription?'),
        content: const Text(
          'Future charges will no longer be added automatically. This does not cancel the service with the provider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep tracking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop tracking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    transaction.isRecurring = false;
    transaction.nextDueDate = null;
    transaction.subscriptionTrialEndDate = null;
    transaction.tags.removeWhere((tag) => tag.toLowerCase() == subscriptionTag);
    context.read<AppStore>().updateTransaction();
  }

  void _track(BuildContext context, Transaction transaction) {
    final store = context.read<AppStore>();
    final added = !transaction.tags.any(
      (tag) => tag.toLowerCase() == subscriptionTag,
    );
    if (added) transaction.tags.add(subscriptionTag);
    store.updateTransaction();
    if (!added) return;
    final name = transaction.note.isEmpty
        ? transaction.category.raw
        : transaction.note;
    // One tap moves the row; Undo keeps that tap safe to make by mistake.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Tracking $name as a subscription.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              transaction.tags.remove(subscriptionTag);
              store.updateTransaction();
            },
          ),
        ),
      );
  }

  Future<void> _acceptSuggestion(
    BuildContext context,
    SubscriptionSuggestion suggestion,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Track ${suggestion.merchant}?'),
        scrollable: true,
        content: Text(
          'This will add a ${suggestion.recurrenceRule.raw.toLowerCase()} recurring payment. '
          'Future charges will be recorded automatically. You can edit the payment or stop tracking at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Track subscription'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final transaction = suggestion.lastTransaction;
    final now = DateTime.now();
    transaction.isRecurring = true;
    transaction.recurrenceRule = suggestion.recurrenceRule;
    var nextDue = suggestion.recurrenceRule.nextDate(transaction.date);
    while (!nextDue.isAfter(now)) {
      nextDue = suggestion.recurrenceRule.nextDate(nextDue);
    }
    transaction.nextDueDate = nextDue;
    if (!transaction.tags.any((tag) => tag.toLowerCase() == subscriptionTag)) {
      transaction.tags.add(subscriptionTag);
    }
    context.read<AppStore>().updateTransaction();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tracking ${suggestion.merchant}. Check the next renewal date.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final subscriptions = store.transactions.where(isSubscription).toList()
      ..sort(
        (a, b) => (a.nextDueDate ?? a.date).compareTo(b.nextDueDate ?? b.date),
      );
    final available = store.transactions
        .where(
          (transaction) =>
              transaction.type == TransactionType.expense &&
              transaction.isRecurring &&
              !isSubscription(transaction),
        )
        .toList();
    final suggestions = suggestSubscriptions(store.transactions)
        .where(
          (suggestion) => !subscriptions.any(
            (subscription) =>
                subscription.note.trim().toLowerCase() ==
                suggestion.merchant.toLowerCase(),
          ),
        )
        .toList();
    final annual = subscriptions.fold<double>(
      0,
      (sum, transaction) => sum + annualSubscriptionCost(transaction),
    );

    return Scaffold(
      backgroundColor: oc.bg,
      appBar: ExpndPageBar(
        title: 'Subscriptions',
        actions: [
          if (Navigator.of(context).canPop())
            HeaderAction(
              icon: 'xmark',
              onPressed: () => Navigator.of(context).maybePop(),
              semanticLabel: 'Close subscriptions',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          ExpndSpacing.scrollBottom,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: oc.surface,
              border: Border.all(color: oc.border),
              borderRadius: BorderRadius.circular(ExpndRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ESTIMATED YEARLY COST', style: ExpndType.label(oc.muted)),
                const SizedBox(height: 8),
                Text(
                  formatCurrency(annual, code),
                  style: ExpndType.amount(oc.text),
                ),
                const SizedBox(height: 6),
                Text(
                  subscriptions.isEmpty
                      ? 'No tracked subscriptions yet'
                      : '${subscriptions.length} tracked · about '
                            '${formatCurrency(annual / 12, code)} a month',
                  style: ExpndType.body(oc.muted),
                ),

              ],
            ),
          ),
          const SizedBox(height: 24),
          if (subscriptions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                available.isEmpty && suggestions.isEmpty
                    ? 'Track recurring services here to see renewal dates, '
                          'trial endings and the full yearly cost. Start by '
                          'adding a recurring payment below.'
                    : 'Track recurring services here to see renewal dates, '
                          'trial endings and the full yearly cost. Tap Track '
                          'on a payment below to start.',
                style: ExpndType.body(oc.muted),
              ),
            )
          else ...[
            Text('YOUR SUBSCRIPTIONS', style: ExpndType.label(oc.muted)),
            const SizedBox(height: 10),
            for (final transaction in subscriptions) ...[
              _subscriptionTile(context, transaction, code),
              const SizedBox(height: 10),
            ],
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('ADD FROM RECURRING', style: ExpndType.label(oc.muted)),
            const SizedBox(height: 8),
            for (final transaction in available)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  transaction.note.isEmpty
                      ? transaction.category.raw
                      : transaction.note,
                ),
                subtitle: Text(
                  '${transaction.recurrenceRule.raw} · ${formatCurrency(transaction.amount, code)}',
                ),
                trailing: _trackLabel(oc),
                onTap: () => _track(context, transaction),
              ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('POSSIBLE SUBSCRIPTIONS', style: ExpndType.label(oc.muted)),
            const SizedBox(height: 6),
            Text(
              'Found from repeated charges on this device. Review before tracking.',
              style: ExpndType.body(oc.muted),
            ),
            for (final suggestion in suggestions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(suggestion.merchant),
                subtitle: Text(
                  '${suggestion.count} similar payments · ${suggestion.recurrenceRule.raw} · ${formatCurrency(suggestion.amount, code)}',
                ),
                trailing: _trackLabel(oc),
                onTap: () => _acceptSuggestion(context, suggestion),
              ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => showAddTransaction(context),
            icon: const Icon(Icons.add),
            label: const Text('Add a recurring payment'),
          ),
        ],
      ),
    );
  }

  /// Reads as an action (accent, bold) like the app's other inline actions;
  /// the whole row is the 48dp+ tap target.
  Widget _trackLabel(ExpndColors oc) => Text(
    'Track',
    style: ExpndType.body(oc.accent).copyWith(fontWeight: FontWeight.w700),
  );

  bool _trialEnded(DateTime trial) {
    final now = DateTime.now();
    return DateTime(
      trial.year,
      trial.month,
      trial.day,
    ).isBefore(DateTime(now.year, now.month, now.day));
  }

  Widget _subscriptionTile(
    BuildContext context,
    Transaction transaction,
    String code,
  ) {
    final oc = context.oc;
    final due = transaction.nextDueDate;
    final trial = transaction.subscriptionTrialEndDate;
    final dateLabel = due == null
        ? 'Renewal date unavailable'
        : 'Next renewal ${MaterialLocalizations.of(context).formatMediumDate(due)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: oc.surface,
        border: Border.all(color: oc.border),
        borderRadius: BorderRadius.circular(ExpndRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.note.isEmpty
                      ? transaction.category.raw
                      : transaction.note,
                  style: ExpndType.body(oc.text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatCurrency(transaction.amount, code)} · ${transaction.recurrenceRule.raw}',
                  style: ExpndType.label(oc.muted),
                ),
                const SizedBox(height: 3),
                Text(dateLabel, style: ExpndType.label(oc.muted)),
                if (trial != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${_trialEnded(trial) ? 'Trial ended' : 'Trial ends'} '
                    '${MaterialLocalizations.of(context).formatMediumDate(trial)}',
                    style: ExpndType.label(oc.negative),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Manage subscription',
            onSelected: (action) {
              if (action == 'edit') {
                showAddTransaction(context, editing: transaction);
              }
              if (action == 'trial') _setTrialEnd(context, transaction);
              if (action == 'clear_trial') {
                transaction.subscriptionTrialEndDate = null;
                context.read<AppStore>().updateTransaction();
              }
              if (action == 'stop') _stop(context, transaction);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit payment')),
              PopupMenuItem(
                value: 'trial',
                child: Text(
                  trial == null ? 'Set trial end' : 'Change trial end',
                ),
              ),
              if (trial != null)
                const PopupMenuItem(
                  value: 'clear_trial',
                  child: Text('Clear trial end'),
                ),
              const PopupMenuItem(value: 'stop', child: Text('Stop tracking')),
            ],
          ),
        ],
      ),
    );
  }
}
