import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/money_checkup.dart';
import '../services/cash_flow.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/money_field.dart';

Future<void> showPurchasePreview(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const PurchasePreviewView()));

Future<void> showMonthlyReview(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const MonthlyReviewView()));

class PurchasePreviewView extends StatefulWidget {
  const PurchasePreviewView({super.key});

  @override
  State<PurchasePreviewView> createState() => _PurchasePreviewViewState();
}

class _PurchasePreviewViewState extends State<PurchasePreviewView> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final code = settings.currencyCode;
    final value = parseAmount(_amount.text);
    String money(double amount) => formatCurrency(amount, code);
    final preview = value == null || value <= 0
        ? null
        : previewPurchase(
            store,
            amount: value,
            monthlyBudget: settings.monthlyBudget,
            budgetRollover: settings.budgetRollover,
            budgetPeriod: settings.budgetCycle == 'calendar'
                ? null
                : budgetPeriodFor(settings, DateTime.now()),
          );
    return Scaffold(
      backgroundColor: oc.bg,
      appBar: closablePageBar(context, 'Plan a purchase'),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          ExpndSpacing.scrollBottom,
        ),
        children: [
          Text(
            'See how a purchase could affect this month before you buy.',
            style: ExpndType.body(oc.muted),
          ),
          const SizedBox(height: 16),
          MoneyField(
            controller: _amount,
            currencyCode: code,
            label: 'Purchase amount',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (preview == null)
            _Panel(
              child: Text(
                'Enter an amount to see what would be left after your bills, '
                'savings goals and budget.',
                style: ExpndType.body(oc.muted),
              ),
            )
          else ...[
            _FigureCard(
              title: 'Left after this purchase',
              value: money(preview.afterPurchase),
              detail: preview.afterPurchase < 0
                  ? 'This purchase is more than the cash left after bills due '
                        'this month and savings set aside.'
                  : 'Cash left after bills due this month and savings set aside.',
              attention: preview.afterPurchase < 0,
              rows: [
                _AmountRow('Cash and savings balances', money(preview.cash)),
                _AmountRow(
                  'Bills due before month end',
                  money(-preview.upcomingBills),
                ),
                _AmountRow(
                  'Set aside for savings goals',
                  money(-preview.reservedForGoals),
                ),
                _AmountRow(
                  'Available before purchase',
                  money(preview.availableAfterBills),
                  emphasized: true,
                ),
                _AmountRow('This purchase', money(-value!)),
              ],
            ),
            if (settings.monthlyBudget > 0) ...[
              const SizedBox(height: 12),
              _FigureCard(
                title: 'Budget left after purchase',
                value: money(preview.budgetAfterPurchase),
                detail: 'Based on spending in your current budget period.',
                attention: preview.budgetAfterPurchase < 0,
              ),
            ],
          ],
          if (preview != null && preview.excludedBills > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '${preview.excludedBills} '
                '${preview.excludedBills == 1 ? 'bill is' : 'bills are'} '
                'not included because '
                '${preview.excludedBills == 1 ? 'it uses' : 'they use'} '
                'another currency, a credit or investment account, or no '
                'account. Check Upcoming before deciding.',
                style: ExpndType.body(oc.negative),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'This is an estimate based on accounts and bills you recorded. It does not add a transaction.',
            style: ExpndType.label(oc.muted),
          ),
        ],
      ),
    );
  }
}

class MonthlyReviewView extends StatelessWidget {
  const MonthlyReviewView({super.key});

  /// Writes the review to a temporary CSV and opens the share sheet; the file
  /// only leaves the device if the user picks a destination.
  Future<void> _shareCsv(
    BuildContext context,
    MonthlyReview review,
    AppStore store,
    String code,
  ) async {
    final now = DateTime.now();
    final csv = monthlyReviewCsv(
      review,
      month: now,
      currencyCode: code,
      goals: store.goals,
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/expnd-review-${now.year}-'
        '${now.month.toString().padLeft(2, '0')}.csv',
      );
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          text: 'EXPND monthly review',
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't export the review. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final code = settings.currencyCode;
    final review = monthlyReview(store);
    final difference = review.spent - review.previousSpent;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text.toUpperCase(), style: ExpndType.label(oc.muted)),
    );
    Widget row(String title, String subtitle) => _Panel(
      margin: const EdgeInsets.only(bottom: 8),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ExpndType.body(oc.text)),
            const SizedBox(height: 2),
            Text(subtitle, style: ExpndType.label(oc.muted)),
          ],
        ),
      ),
    );
    Widget hint(String text) => Text(text, style: ExpndType.body(oc.muted));
    return Scaffold(
      backgroundColor: oc.bg,
      appBar: closablePageBar(
        context,
        'Monthly review',
        actions: [
          HeaderAction(
            icon: 'square.and.arrow.up',
            onPressed: () => _shareCsv(context, review, store, code),
            semanticLabel: 'Export monthly review as CSV',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          ExpndSpacing.scrollBottom,
        ),
        children: [
          _FigureCard(
            title: 'Spent this month',
            value: formatCurrency(review.spent, code),
            detail: difference == 0 && review.transactionCount > 0
                ? 'The same spending as last month'
                : review.previousSpent == 0
                ? '${review.transactionCount} recorded '
                      '${review.transactionCount == 1 ? 'expense' : 'expenses'}'
                : '${formatCurrency(difference.abs(), code)} ${difference > 0 ? 'more' : 'less'} than last month '
                      '(${formatCurrency(review.previousSpent, code)})',
          ),
          if (review.transactionCount == 0) ...[
            const SizedBox(height: 12),
            hint(
              'No expenses recorded this month yet. Expenses you add will '
              'appear here, grouped by category.',
            ),
          ] else ...[
            if (review.uncategorizedCount > 0) ...[
              const SizedBox(height: 12),
              row(
                '${review.uncategorizedCount} '
                    '${review.uncategorizedCount == 1 ? 'expense' : 'expenses'} in Other',
                'Give them a category in History for a clearer review',
              ),
            ],
            heading('Top categories'),
            for (final entry in review.categories.take(5))
              row(entry.key.raw, formatCurrency(entry.value, code)),
          ],
          heading('Savings goals'),
          if (store.goals.isEmpty)
            hint('Create a savings goal in Plan to track your progress.'),
          for (final goal in store.goals)
            row(
              goal.name,
              '${formatCurrency(goal.allocatedAmount, code)} of ${formatCurrency(goal.targetAmount, code)} set aside',
            ),
          heading('Annual bills'),
          if (review.annualBills.isEmpty)
            hint(
              'No yearly recurring bills recorded. Add one as a yearly '
              'recurring expense so it shows here before it is due.',
            ),
          for (final bill in review.annualBills.take(4))
            row(
              bill.note.isEmpty ? bill.category.raw : bill.note,
              '${formatCurrency(bill.amount, code)} · Next due ${MaterialLocalizations.of(context).formatMediumDate(bill.nextDueDate ?? bill.date)}',
            ),
        ],
      ),
    );
  }
}

/// The app's flat panel surface (matches Subscriptions and Until payday).
class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const _Panel({required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: oc.surface,
        border: Border.all(color: oc.border),
        borderRadius: BorderRadius.circular(ExpndRadius.card),
      ),
      child: child,
    );
  }
}

class _AmountRow {
  final String label;
  final String value;
  final bool emphasized;

  const _AmountRow(this.label, this.value, {this.emphasized = false});
}

class _FigureCard extends StatelessWidget {
  final String title;
  final String value;
  final String detail;
  final bool attention;

  /// Optional breakdown shown under the figure, so the calculation is visible.
  final List<_AmountRow> rows;

  const _FigureCard({
    required this.title,
    required this.value,
    required this.detail,
    this.attention = false,
    this.rows = const [],
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: ExpndType.label(oc.muted)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: ExpndType.amount(
                      attention ? oc.negative : oc.text,
                    ).copyWith(fontSize: 30),
                  ),
                ),
                const SizedBox(height: 6),
                Text(detail, style: ExpndType.body(oc.muted)),
              ],
            ),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 20, color: oc.border),
            for (final row in rows)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          style: ExpndType.body(
                            row.emphasized ? oc.text : oc.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          row.value,
                          textAlign: TextAlign.end,
                          style: ExpndType.body(
                            oc.text,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
