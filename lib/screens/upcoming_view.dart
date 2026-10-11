import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/upcoming.dart';
import '../services/insights.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/glass_header.dart';
import '../widgets/animations.dart';
import '../widgets/app_header.dart';
import '../widgets/context_ai_coach.dart';
import '../models/models.dart';
import '../widgets/neopop.dart';
import 'add_transaction.dart';
import 'emi.dart';

/// Pushes the full Upcoming timeline, matching how the dashboard opens History.
Future<void> showUpcoming(BuildContext context) {
  final oc = context.oc;
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: oc.bg,
        body: const SafeArea(
          top: !ExpndGlass.enabled,
          bottom: false,
          child: UpcomingView(),
        ),
      ),
    ),
  );
}

/// Everything due in the next 30 days — recurring transactions rolled forward
/// and EMI installments — grouped by day, above a summary of what it all means
/// for the current month.
class UpcomingView extends StatelessWidget {
  const UpcomingView({super.key});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;

    final items = projectUpcoming(store);
    final summary = summarizeUpcoming(store, items);
    final aiFacts = _upcomingAiFacts(items, summary, code);
    final groups = groupUpcomingByDay(items);

    // The rules behind the projections above. Managing them lives here rather
    // than in Plan: this is the screen where you actually see them fire.
    final series = store.transactions.where((t) => t.isRecurring).toList()
      ..sort((a, b) {
        final da = a.nextDueDate, db = b.nextDueDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    // Only a recurring series' *next* occurrence can be acted on — posting or
    // skipping advances its schedule one step, so it's meaningless on the later
    // projections of the same series, and EMIs never post a transaction at all.
    // Items are date-sorted, so the first time a sourceId appears is its next
    // occurrence.
    final actionable = <UpcomingItem>{};
    final seenSources = <String>{};
    for (final it in items) {
      // A debt repayment is settled from the debt itself in PLAN, where the
      // outstanding figure and the person's whole history are in view — there
      // is nothing sensible to post or skip from a projected row here.
      if (it.kind == UpcomingKind.debt) continue;
      if (seenSources.add(it.sourceId)) actionable.add(it);
    }

    return Container(
      color: oc.bg,
      child: GlassHeaderLayout(
        header: FadeSlideIn(child: _titleBar(context, oc)),
        body: (context, top) => (items.isEmpty && series.isEmpty)
            ? Padding(
                padding: EdgeInsets.only(top: top),
                child: _emptyState(oc),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4 + top,
                  16,
                  ExpndSpacing.scrollBottom,
                ),
                children: [
                  FadeSlideIn(
                    index: 1,
                    child: _summaryCard(context, oc, summary, code),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(index: 2, child: ContextAiCoach(facts: aiFacts)),
                  const SizedBox(height: 20),
                  for (var g = 0; g < groups.length; g++)
                    FadeSlideIn(
                      index: g + 3,
                      child: _dayGroup(
                        context,
                        oc,
                        store,
                        groups[g],
                        code,
                        actionable,
                      ),
                    ),
                  if (series.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FadeSlideIn(
                      index: groups.length + 3,
                      child: _seriesSection(context, oc, store, series, code),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  List<Insight> _upcomingAiFacts(
    List<UpcomingItem> items,
    UpcomingSummary summary,
    String code,
  ) {
    final safe = summary.safeToSpend;
    final facts = <Insight>[
      Insight(
        title: 'Safe to spend is ${formatCurrency(safe, code)}',
        detail: safe < 0
            ? 'Committed bills exceed the cash available now'
            : 'After bills committed through this month',
        tone: safe < 0 ? InsightTone.warn : InsightTone.good,
        icon: safe < 0
            ? 'exclamationmark.triangle.fill'
            : 'checkmark.circle.fill',
        weight: 100,
      ),
      Insight(
        title:
            '${formatCurrency(summary.committedOutflows, code)} is committed',
        detail:
            '${formatCurrency(summary.expectedInflows, code)} expected in the next $kUpcomingHorizonDays days',
        tone: InsightTone.neutral,
        icon: 'calendar.badge.clock',
        weight: 80,
      ),
    ];
    if (items.isNotEmpty) {
      final next = items.first;
      facts.add(
        Insight(
          title: 'Next: ${next.title}',
          detail:
              '${formatCurrency(next.amount, code)} on ${_dayLabel(next.date)}',
          tone: next.isInflow ? InsightTone.good : InsightTone.neutral,
          icon: next.category.icon,
          weight: 60,
        ),
      );
    }
    return facts;
  }

  Widget _titleBar(BuildContext context, ExpndColors oc) {
    return ExpndHeader(
      icon: 'calendar',
      title: 'Upcoming',
      actions: [
        if (Navigator.of(context).canPop())
          HeaderAction(
            icon: 'xmark',
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Close upcoming',
          ),
      ],
      below: Text(
        'Next $kUpcomingHorizonDays days',
        style: TextStyle(fontSize: 12, color: oc.muted),
      ),
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  Widget _summaryCard(
    BuildContext context,
    ExpndColors oc,
    UpcomingSummary s,
    String code,
  ) {
    final month = _monthName(DateTime.now().month);
    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 0,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _figure(
              oc,
              'COMMITTED OUTFLOWS',
              formatCurrency(s.committedOutflows, code),
              oc.negative,
            ),
            if (s.emiCommitted > 0) ...[
              const SizedBox(height: 4),
              Text(
                'includes ${formatCurrency(s.emiCommitted, code)} in EMI '
                'instalments, which are not deducted from the balances below',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: oc.muted,
                ),
              ),
            ],
            if (s.expectedInflows > 0) ...[
              const SizedBox(height: 14),
              _figure(
                oc,
                'EXPECTED INCOME',
                formatCurrency(s.expectedInflows, code),
                oc.positive,
              ),
            ],
            const SizedBox(height: 14),
            Container(height: 1, color: oc.border),
            const SizedBox(height: 14),
            _figure(
              oc,
              'PROJECTED ${month.toUpperCase()} END',
              formatCurrency(s.projectedMonthEnd, code),
              s.projectedMonthEnd < 0 ? oc.negative : oc.text,
            ),
            const SizedBox(height: 4),
            Text(
              // Explains why this can match Safe-to-Spend below: any payday that
              // lands next month isn't in this figure, so with no in-month income
              // left the two are equal rather than mistakenly duplicated.
              'Counts only income due before $month ends — later paydays land '
              'in next month’s projection.',
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
            const SizedBox(height: 14),
            _figure(
              oc,
              'SAFE TO SPEND',
              formatCurrency(s.safeToSpend, code),
              s.safeToSpend < 0 ? oc.negative : oc.accent,
            ),
            const SizedBox(height: 4),
            Text(
              s.safeToSpend < 0
                  ? 'Your committed bills through $month exceed what you '
                        'currently hold.'
                  : 'Cash on hand after every bill committed through $month. '
                        'Income you have not received yet is not counted.',
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _figure(ExpndColors oc, String label, String value, Color valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: oc.muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Capped rather than Flexible, so the figure sits flush right instead
        // of starting halfway across the card.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: valueColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Timeline ──────────────────────────────────────────────────────────────

  Widget _dayGroup(
    BuildContext context,
    ExpndColors oc,
    AppStore store,
    ({DateTime day, List<UpcomingItem> items}) group,
    String code,
    Set<UpcomingItem> actionable,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                Text(
                  _dayLabel(group.day).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: oc.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 1, color: oc.border)),
              ],
            ),
          ),
          NeoPopElevated(
            faceColor: oc.surface,
            depthColor: oc.edge,
            borderColor: oc.border,
            depth: 0,
            cornerRadius: 6,
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(height: 1, color: oc.border),
                    ),
                  UpcomingRow(
                    item: group.items[i],
                    code: code,
                    onTap: actionable.contains(group.items[i])
                        ? () => _showItemActions(
                            context,
                            store,
                            group.items[i],
                            code,
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Actions for the next occurrence of a rule: post-early / skip for a
  /// recurring series, or record the payment for an EMI installment.
  Future<void> _showItemActions(
    BuildContext context,
    AppStore store,
    UpcomingItem item,
    String code,
  ) async {
    if (item.kind == UpcomingKind.emi) {
      final emi = store.emis.where((e) => e.id == item.sourceId);
      if (emi.isNotEmpty) await showPayInstallment(context, emi.first);
      return;
    }
    Haptics.light();
    final oc = context.oc;
    // The series could have been edited/deleted between projection and tap.
    final matches = store.transactions.where((t) => t.id == item.sourceId);
    if (matches.isEmpty) return;
    final source = matches.first;
    await showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              item.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${item.isInflow ? '+' : '−'}${formatCurrency(item.amount, code)} · '
              'due ${_dayLabel(item.date)}',
              style: TextStyle(fontSize: 11, color: oc.muted),
            ),
            const SizedBox(height: 14),
            _actionRow(
              sheetCtx,
              'checkmark.circle.fill',
              'Post now',
              'Record it today and roll the schedule forward',
              oc.positive,
              () {
                store.postRecurringNow(source);
                Haptics.success();
              },
            ),
            _actionRow(
              sheetCtx,
              'xmark.circle',
              'Skip this one',
              'Move to the next date without recording it',
              oc.text,
              () {
                store.skipRecurringOccurrence(source);
                Haptics.warning();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext sheetCtx,
    String icon,
    String label,
    String sub,
    Color color,
    VoidCallback onTap,
  ) {
    final oc = sheetCtx.oc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onTap();
        Navigator.of(sheetCtx).pop();
      },
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        child: Row(
          children: [
            Icon(sfIcon(icon), size: 18, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: oc.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(sub, style: TextStyle(fontSize: 11, color: oc.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The recurring rules themselves, listed under the timeline they generate.
  /// Tapping one opens it for editing — this replaces the read-only list that
  /// used to sit in Profile, far from anywhere the schedule was visible.
  Widget _seriesSection(
    BuildContext context,
    ExpndColors oc,
    AppStore store,
    List<Transaction> series,
    String code,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Row(
            children: [
              Text(
                'RECURRING RULES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: oc.muted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: oc.border)),
            ],
          ),
        ),
        NeoPopElevated(
          faceColor: oc.surface,
          depthColor: oc.edge,
          borderColor: oc.border,
          depth: 0,
          cornerRadius: 6,
          child: Column(
            children: [
              for (var i = 0; i < series.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 62),
                    child: Container(height: 1, color: oc.border),
                  ),
                _seriesRow(context, oc, store, series[i], code),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _seriesRow(
    BuildContext context,
    ExpndColors oc,
    AppStore store,
    Transaction t,
    String code,
  ) {
    final custom = store.customCategoryFor(t.customCategoryId);
    final tint = custom != null ? hexColor(custom.colorHex) : t.category.color;
    final isIncome = t.type == TransactionType.income;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        showAddTransaction(context, editing: t);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: tint.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: custom != null
                  ? Text(custom.emoji, style: const TextStyle(fontSize: 15))
                  : Icon(sfIcon(t.category.icon), size: 13, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.note.trim().isNotEmpty
                        ? t.note.trim()
                        : (custom?.name ?? t.category.raw),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: oc.text,
                    ),
                  ),
                  Text(
                    t.nextDueDate == null
                        ? t.recurrenceRule.raw.toUpperCase()
                        : '${t.recurrenceRule.raw.toUpperCase()} · NEXT '
                              '${_shortDay(t.nextDueDate!).toUpperCase()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                      color: oc.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${isIncome ? "+" : "−"}${formatCurrency(t.amount, code)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isIncome ? oc.positive : oc.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 4),
            Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ExpndColors oc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon('calendar'), size: 40, color: oc.dimmed),
            const SizedBox(height: 14),
            Text(
              'NOTHING SCHEDULED',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: oc.muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mark a transaction as recurring, or add an EMI to an account, '
              'and it will show up here before it is due.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: oc.dimmed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One projected movement. Mirrors the shape of a transaction row so the
/// timeline reads as continuous with History, but stays visually provisional —
/// the icon is outlined rather than filled and the amount is muted.
class UpcomingRow extends StatelessWidget {
  final UpcomingItem item;
  final String code;
  final bool dense;

  /// When set, the row is tappable (post-early / skip actions) and shows a
  /// chevron. Only the next occurrence of a recurring series passes this.
  final VoidCallback? onTap;

  const UpcomingRow({
    super.key,
    required this.item,
    required this.code,
    this.dense = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.read<AppStore>();
    final custom = store.customCategoryFor(item.customCategoryId);
    final isEmi = item.kind == UpcomingKind.emi;
    final tint = isEmi
        ? oc.accent
        : custom != null
        ? hexColor(custom.colorHex)
        : item.category.color;
    final account = store.accountFor(item.accountId);

    final amountColor = item.isInflow ? oc.positive : oc.text;
    final sign = item.isInflow ? '+' : '−';

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 9 : 12),
      child: Row(
        children: [
          Container(
            width: dense ? 30 : 34,
            height: dense ? 30 : 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: tint.withValues(alpha: 0.45), width: 1),
            ),
            child: custom != null && !isEmi
                ? Text(
                    custom.emoji,
                    style: TextStyle(fontSize: dense ? 13 : 15),
                  )
                : Icon(
                    sfIcon(isEmi ? 'creditcard.fill' : item.category.icon),
                    size: dense ? 13 : 15,
                    color: tint,
                  ),
          ),
          SizedBox(width: dense ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: oc.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  account == null
                      ? item.subtitle
                      : '${item.subtitle} · ${account.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 9.5 : 10.5,
                    fontWeight: FontWeight.w600,
                    color: oc.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Capped, not Flexible: a Flexible here split the row in half with
          // the Expanded text, so short amounts floated mid-row and the
          // account name was cut off early.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.38,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$sign${formatCurrency(item.amount, code)}',
                    style: TextStyle(
                      fontSize: dense ? 12 : 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: amountColor,
                    ),
                  ),
                  if (dense) ...[
                    const SizedBox(height: 2),
                    Text(
                      _shortDay(item.date),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: oc.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (onTap != null && !dense) ...[
            const SizedBox(width: 4),
            Icon(sfIcon('chevron.right'), size: 13, color: oc.dimmed),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

// ── Date helpers ────────────────────────────────────────────────────────────

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthName(int m) => _months[m - 1];

String _shortDay(DateTime d) =>
    '${_months[d.month - 1].substring(0, 3)} '
    '${d.day.toString().padLeft(2, '0')}';

/// "Today" / "Tomorrow" for the near dates people actually care about, then a
/// plain date once the relative label stops being clearer than the absolute one.
String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return _shortDay(day);
}
