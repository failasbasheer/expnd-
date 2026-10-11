import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// A short path through the first useful actions. Completion comes from the
/// ledger and settings, never from tapping a row.
class GetStartedCard extends StatelessWidget {
  final bool hasWallet;
  final bool hasExpense;
  final bool hasBudget;
  final bool hasReminder;
  final VoidCallback onWallet;
  final VoidCallback onExpense;
  final VoidCallback onBudget;
  final VoidCallback onReminder;
  final VoidCallback onDismiss;
  final bool showDismiss;

  const GetStartedCard({
    super.key,
    required this.hasWallet,
    required this.hasExpense,
    required this.hasBudget,
    required this.hasReminder,
    required this.onWallet,
    required this.onExpense,
    required this.onBudget,
    required this.onReminder,
    required this.onDismiss,
    this.showDismiss = true,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final completed = [
      hasWallet,
      hasExpense,
      hasBudget,
      hasReminder,
    ].where((done) => done).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(ExpndRadius.card),
        border: Border.all(color: oc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'GET STARTED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: oc.text,
                ),
              ),
              const Spacer(),
              Text(
                '$completed / 4',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: oc.muted,
                ),
              ),
              if (showDismiss)
                IconButton(
                  tooltip: 'Dismiss get started',
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, size: 18, color: oc.muted),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
            ],
          ),
          _step(oc, 'Set up your wallet', hasWallet, onWallet),
          _step(oc, 'Add your first expense', hasExpense, onExpense),
          _step(oc, 'Set a monthly budget', hasBudget, onBudget),
          _step(oc, 'Turn on a daily reminder', hasReminder, onReminder),
        ],
      ),
    );
  }

  Widget _step(ExpndColors oc, String title, bool done, VoidCallback onTap) {
    return InkWell(
      onTap: done ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: done ? ExpndColors.green : oc.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: done ? oc.muted : oc.text,
                ),
              ),
            ),
            if (!done)
              Icon(Icons.chevron_right_rounded, size: 18, color: oc.muted),
          ],
        ),
      ),
    );
  }
}
