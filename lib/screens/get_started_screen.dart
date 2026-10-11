import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/expnd_theme.dart';
import '../widgets/get_started_card.dart';
import 'add_transaction.dart';
import 'plan_view.dart';
import 'settings_view.dart';

/// First-use actions stay on one screen and complete from saved app state.
class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});

  Future<void> _openPlan(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        body: SafeArea(
          top: !ExpndGlass.enabled,
          bottom: false,
          child: const PlanView(showClose: true),
        ),
      ),
    ),
  );

  void _close(BuildContext context, {bool dismiss = false}) {
    if (dismiss) context.read<SettingsStore>().getStartedDismissed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final hasWallet = store.accounts.isNotEmpty;
    final hasExpense = store.transactions.any(
      (t) => t.type == TransactionType.expense,
    );
    final hasBudget = settings.monthlyBudget > 0;
    final hasReminder = settings.dailyReminder;
    final complete = hasWallet && hasExpense && hasBudget && hasReminder;

    return Scaffold(
      backgroundColor: oc.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _close(context, dismiss: true),
                child: Text(complete ? 'DONE' : 'SKIP FOR NOW'),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'MAKE IT YOURS',
              style: TextStyle(
                color: oc.text,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A few small steps make EXPND useful from day one.',
              style: TextStyle(color: oc.muted, fontSize: 15),
            ),
            const SizedBox(height: 24),
            GetStartedCard(
              hasWallet: hasWallet,
              hasExpense: hasExpense,
              hasBudget: hasBudget,
              hasReminder: hasReminder,
              showDismiss: false,
              onWallet: () {},
              onExpense: () => showAddTransaction(context),
              onBudget: () => _openPlan(context),
              onReminder: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsView(openReminders: true),
                ),
              ),
              onDismiss: () => _close(context, dismiss: true),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _close(context, dismiss: complete),
                child: Text(complete ? 'GO TO HOME' : 'CONTINUE LATER'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
