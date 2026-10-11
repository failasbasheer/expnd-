import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';

/// The money behind whatever a list is currently filtered to: money in, money
/// out and the net, so a filter answers "how much?" and not only "which?".
/// Transfers move money between your own accounts, so they count as neither.
/// Amounts follow the hide-amounts eye through [formatCurrency].
class FilterTotals extends StatelessWidget {
  final Iterable<Transaction> transactions;
  final String currencyCode;

  /// Optional leading text, e.g. "69 transactions".
  final String? lead;

  const FilterTotals({
    super.key,
    required this.transactions,
    required this.currencyCode,
    this.lead,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    var income = 0.0;
    var spent = 0.0;
    for (final t in transactions) {
      if (t.type == TransactionType.income) income += t.amount;
      if (t.type == TransactionType.expense) spent += t.amount;
    }
    final hasIncome = income > 0;
    final hasSpend = spent > 0;
    final net = income - spent;

    Widget figure(String label, String value, Color color) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: oc.muted,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );

    final figures = <Widget>[
      if (hasIncome)
        figure(
          'IN',
          '+${formatCurrency(income, currencyCode)}',
          ExpndColors.green,
        ),
      if (hasSpend)
        figure(
          'OUT',
          '−${formatCurrency(spent, currencyCode)}',
          ExpndColors.red,
        ),
      // Net only adds something when both sides are present.
      if (hasIncome && hasSpend)
        figure(
          'NET',
          '${net < 0 ? '−' : '+'}${formatCurrency(net.abs(), currencyCode)}',
          oc.text,
        ),
    ];
    if (lead == null && figures.isEmpty) return const SizedBox.shrink();
    // Count on its own line, then the figures on ONE line that scales down
    // rather than wrapping — a wrapped "NET" on a line of its own read as
    // broken.
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lead != null)
            Text(lead!, style: TextStyle(fontSize: 12, color: oc.muted)),
          if (lead != null && figures.isNotEmpty) const SizedBox(height: 4),
          if (figures.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < figures.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    figures[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
