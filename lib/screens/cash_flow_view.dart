import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/cash_flow.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/section_card.dart';

Future<void> showCashFlow(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const CashFlowView()));

class CashFlowView extends StatelessWidget {
  const CashFlowView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final oc = context.oc;
    final code = settings.currencyCode;
    final estimate = estimateUntilPayday(store, settings);
    final period = budgetPeriodFor(settings, DateTime.now());
    final spent = budgetSpentInPeriod(store, period);
    final budget = settings.budgetCycle == 'calendar'
        ? store.effectiveMonthlyBudget(
            settings.monthlyBudget,
            rollover: settings.budgetRollover,
          )
        : settings.monthlyBudget;
    final date = DateFormat.MMMd();
    String money(double amount) => formatCurrency(amount, code);

    Widget amountRow(String label, double value, {bool emphasized = false}) =>
        MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: emphasized ? oc.text : oc.muted,
                      fontWeight: emphasized ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    money(value),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: emphasized
                          ? (value < 0 ? oc.negative : oc.positive)
                          : oc.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    final weekly =
        settings.budgetCycle == 'weekly' ||
        settings.budgetCycle == 'fortnightly';

    return Scaffold(
      backgroundColor: oc.bg,
      appBar: ExpndPageBar(
        title: 'Until payday',
        actions: [
          if (Navigator.of(context).canPop())
            HeaderAction(
              icon: 'xmark',
              onPressed: () => Navigator.of(context).maybePop(),
              semanticLabel: 'Close until payday',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (!settings.paydayConfigured)
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
                    Text(
                      'Set your payday',
                      style: TextStyle(
                        color: oc.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      weekly
                          ? 'Choose a date you were paid below to see what is '
                                'available until the next payday.'
                          : 'Pick the day of the month you are usually paid '
                                'below, then confirm it, to see what is '
                                'available until the next payday.',
                      style: TextStyle(color: oc.muted),
                    ),
                  ],
                ),
              )
            else
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
                    Text(
                      'SPENDABLE UNTIL ${date.format(estimate.nextPayday).toUpperCase()}',
                      style: TextStyle(
                        color: oc.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money(estimate.spendable),
                        style: TextStyle(
                          color: estimate.spendable < 0
                              ? oc.negative
                              : oc.positive,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      estimate.spendable < 0
                          ? 'Upcoming commitments exceed the cash available before payday.'
                          : 'After money set aside for goals and bills due before payday.',
                      style: TextStyle(color: oc.muted),
                    ),
                    Divider(height: 28, color: oc.border),
                    amountRow(
                      'Cash and savings balances',
                      estimate.liquidBalance,
                    ),
                    amountRow(
                      'Set aside for savings goals',
                      -estimate.reservedForGoals,
                    ),
                    amountRow('Bills before payday', -estimate.upcomingBills),
                    Divider(height: 20, color: oc.border),
                    amountRow(
                      'Available to spend',
                      estimate.spendable,
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (settings.paydayConfigured)
              Text(
                'Uses ${settings.currencyCode} cash, bank and savings accounts. Future income is not included. Keep balances and recurring bills current.',
                style: TextStyle(color: oc.muted, fontSize: 13),
              ),
            if (settings.paydayConfigured &&
                estimate.excludedBills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${estimate.excludedBills.length} upcoming ${estimate.excludedBills.length == 1 ? 'bill is' : 'bills are'} excluded because the linked account uses another currency or no eligible account is linked. Link these bills to a ${settings.currencyCode} cash, bank or savings account to include them.',
                style: TextStyle(color: oc.negative, fontSize: 13),
              ),
            ],
            const SizedBox(height: 22),
            sectionCard(
              oc,
              'BUDGET PERIOD',
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose how often your budget resets.',
                      style: TextStyle(color: oc.muted),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(settings.budgetCycle),
                      isExpanded: true,
                      isDense: true,
                      initialValue: settings.budgetCycle,
                      decoration: const InputDecoration(
                        labelText: 'Budget repeats',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'calendar',
                          child: Text('Calendar month'),
                        ),
                        DropdownMenuItem(
                          value: 'payday',
                          child: Text('Monthly payday'),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Weekly payday'),
                        ),
                        DropdownMenuItem(
                          value: 'fortnightly',
                          child: Text('Every two weeks'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) settings.budgetCycle = value;
                      },
                    ),
                    const SizedBox(height: 10),
                    if (settings.budgetCycle == 'calendar' ||
                        settings.budgetCycle == 'payday')
                      DropdownButtonFormField<int>(
                        key: ValueKey(settings.paydayDay),
                        isExpanded: true,
                        isDense: true,
                        initialValue: settings.paydayDay,
                        decoration: const InputDecoration(
                          labelText: 'Payday each month',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                        ),
                        items: [
                          for (var day = 1; day <= 31; day++)
                            DropdownMenuItem(
                              value: day,
                              child: Text('Day $day'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) settings.paydayDay = value;
                        },
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: settings.paydayConfigured
                                ? settings.paydayAnchor
                                : DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            helpText: 'Choose a known payday',
                          );
                          if (selected != null && context.mounted) {
                            settings.paydayAnchor = selected;
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: Text(
                          settings.paydayConfigured
                              ? 'Known payday: ${date.format(settings.paydayAnchor)}'
                              : 'Choose a known payday',
                        ),
                      ),
                    if (!settings.paydayConfigured &&
                        (settings.budgetCycle == 'calendar' ||
                            settings.budgetCycle == 'payday')) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () =>
                              settings.paydayDay = settings.paydayDay,
                          child: Text(
                            'Confirm day ${settings.paydayDay} as my payday',
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: oc.border),
                    ),
                    Text(
                      'CURRENT PERIOD',
                      style: TextStyle(
                        color: oc.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${date.format(period.start)} – '
                      '${date.format(period.end.subtract(const Duration(days: 1)))}',
                      style: TextStyle(
                        color: oc.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      budget > 0
                          ? '${money(spent)} spent of ${money(budget)}'
                          : '${money(spent)} spent · No budget limit set',
                      style: TextStyle(color: oc.muted),
                    ),
                  ],
                ),
              ),
            ),
            if (settings.paydayConfigured && estimate.bills.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'Coming up before payday',
                style: TextStyle(
                  color: oc.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final bill in estimate.bills)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bill.title,
                                style: TextStyle(color: oc.text),
                              ),
                              Text(
                                date.format(bill.date),
                                style: TextStyle(color: oc.muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            money(bill.amount),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: oc.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
