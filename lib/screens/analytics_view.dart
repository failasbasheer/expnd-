import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/animations.dart';
import '../widgets/app_header.dart';
import 'settings_view.dart';
import '../widgets/neopop.dart';

enum _Period { m1, m3, m6, y1, all }

extension on _Period {
  String get label => switch (this) {
    _Period.m1 => '1M',
    _Period.m3 => '3M',
    _Period.m6 => '6M',
    _Period.y1 => '1Y',
    _Period.all => 'ALL',
  };
  int? get days => switch (this) {
    _Period.m1 => 30,
    _Period.m3 => 90,
    _Period.m6 => 180,
    _Period.y1 => 365,
    _Period.all => null,
  };
}

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  _Period _period = _Period.m3;
  Account? _accountFilter;

  List<Transaction> _filtered(AppStore store) {
    var result = store.transactionsAscending
        .where((t) => t.type != TransactionType.transfer)
        .toList();
    final days = _period.days;
    if (days != null) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      result = result.where((t) => !t.date.isBefore(cutoff)).toList();
    }
    if (_accountFilter != null) {
      result = result.where((t) => t.accountId == _accountFilter!.id).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final accounts = store.accounts;
    final filtered = _filtered(store);

    final income = filtered
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (s, t) => s + t.amount);
    final expenses = filtered
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (s, t) => s + t.amount);
    final net = income - expenses;

    final categoryCards = _categoryCards(oc, store, filtered, code);

    // Fixed slots that stay in the same list positions across period/filter
    // changes. Sections that switch on/off (trend, bar, categories) collapse or
    // expand via _slot's AnimatedSize instead of the list snapping to a new
    // height. FadeSlideIn only plays its intro when a slot first gains content.
    return Container(
      color: oc.bg,
      child: Column(
        children: [
          const ExpndHeader(
            icon: 'chart.bar.xaxis',
            title: 'ANALYTICS',
            actions: [SettingsAvatarAction()],
          ),
          Expanded(
            child: store.transactions.isEmpty
                ? _emptyState(oc)
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      ExpndSpacing.scrollBottomUnderTabBar(context),
                    ),
                    children: [
                      _slot(0, _periodSelector(oc)),
                      _slot(
                        1,
                        accounts.isNotEmpty
                            ? _accountFilterRow(oc, accounts)
                            : null,
                      ),
                      _slot(2, _summaryRow(oc, income, expenses, net, code)),
                      _slot(
                        3,
                        filtered.length >= 2
                            ? _balanceTrendCard(oc, filtered, code)
                            : null,
                      ),
                      _slot(
                        4,
                        filtered.isNotEmpty
                            ? _monthlyBarCard(oc, filtered, code)
                            : null,
                      ),
                      _slot(
                        5,
                        categoryCards.isEmpty
                            ? null
                            : Column(
                                children: [
                                  for (int i = 0; i < categoryCards.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == categoryCards.length - 1
                                            ? 0
                                            : 20,
                                      ),
                                      child: categoryCards[i],
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // One list slot whose height animates as its section appears, disappears, or
  // resizes with the data — keeps the analytics list from snapping on switches.
  Widget _slot(int index, Widget? child) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: FadeSlideIn(index: index, child: child),
            ),
    );
  }

  Widget _periodSelector(ExpndColors oc) {
    return Row(
      children: [
        for (final p in _Period.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () {
                Haptics.light();
                setState(() => _period = p);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _period == p ? ExpndColors.gold : oc.surface,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _period == p ? ExpndColors.goldDark : oc.border,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: _period == p ? ExpndColors.ink : oc.muted,
                  ),
                ),
              ),
            ),
          ),
          if (p != _Period.all) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _accountFilterRow(ExpndColors oc, List<Account> accounts) {
    Widget chip(Account? acc) {
      final active = _accountFilter?.id == acc?.id;
      return GestureDetector(
        onTap: () {
          Haptics.light();
          setState(() => _accountFilter = acc);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? ExpndColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? ExpndColors.goldDark : oc.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (acc != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: hexColor(acc.colorHex),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                acc?.name ?? 'ALL ACCOUNTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: active ? ExpndColors.ink : oc.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Fade the trailing edge so a row that overflows reads as "there's more
    // to swipe" instead of a hard-clipped chip. dstIn keeps the row opaque
    // until the last few points, then ramps to transparent.
    return SizedBox(
      height: 30,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.92, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 24),
          children: [
            chip(null),
            for (final acc in accounts) ...[
              const SizedBox(width: 8),
              chip(acc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    ExpndColors oc,
    double income,
    double expenses,
    double net,
    String code,
  ) {
    Widget tile(String label, double value, Color color) => Expanded(
      child: NeoPopElevated(
        faceColor: oc.surface,
        depthColor: oc.edge,
        borderColor: color.withValues(alpha: 0.4),
        depth: 3,
        cornerRadius: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: oc.muted,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                // Count up to the value (and smoothly re-count when the
                // period/account filter changes), matching the home balance.
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    formatCurrency(v, code),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        tile('INCOME', income, ExpndColors.green),
        const SizedBox(width: 10),
        tile('EXPENSES', expenses, ExpndColors.red),
        const SizedBox(width: 10),
        tile('NET', net, net >= 0 ? ExpndColors.green : ExpndColors.red),
      ],
    );
  }

  Widget _chartCard(ExpndColors oc, String title, String icon, Widget child) {
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
            Row(
              children: [
                Icon(sfIcon(icon), size: 12, color: oc.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: oc.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  /// Compact money for chart axes — "$2.7k", "-$840", "$1.2M".
  String _compact(double v, String code) {
    final sym = currencySymbol(code);
    final sign = v < 0 ? '-' : '';
    final a = v.abs();
    String n;
    if (a >= 1000000) {
      n = '${(a / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)}M';
    } else if (a >= 1000) {
      n = '${(a / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
    } else {
      n = a.toStringAsFixed(0);
    }
    return '$sign$sym$n';
  }

  Widget _balanceTrendCard(
    ExpndColors oc,
    List<Transaction> filtered,
    String code,
  ) {
    double running = 0;
    final spots = <FlSpot>[];
    for (int i = 0; i < filtered.length; i++) {
      running += filtered[i].type == TransactionType.income
          ? filtered[i].amount
          : -filtered[i].amount;
      spots.add(FlSpot(i.toDouble(), running));
    }
    final lineColor = running >= 0 ? ExpndColors.gold : ExpndColors.red;

    // Axis bounds with a little headroom so the line never kisses the edges,
    // and always includes the zero line for an honest reference.
    var lo = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    var hi = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    lo = lo > 0 ? 0 : lo;
    hi = hi < 0 ? 0 : hi;
    final pad = (hi - lo) * 0.12;
    final minY = lo - pad;
    final maxY = hi + pad;
    final interval = ((maxY - minY) / 3).abs();

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
            // Header carries the current running balance as an explicit value,
            // so the curve reads as a quantity, not just a shape.
            Row(
              children: [
                Icon(
                  sfIcon('chart.line.uptrend.xyaxis'),
                  size: 12,
                  color: oc.accent,
                ),
                const SizedBox(width: 8),
                // Expanded (not Flexible + Spacer): two flex:1 children split
                // the free space evenly, capping the title at half the row and
                // ellipsizing it even when the value is short. Expanded lets the
                // title take all the room the value leaves.
                Expanded(
                  child: Text(
                    'NET CASH FLOW',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: oc.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCurrency(running, code),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: lineColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval <= 0 ? null : interval,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: oc.border, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        interval: interval <= 0 ? null : interval,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.min || value == meta.max) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              _compact(value, code),
                              style: TextStyle(fontSize: 9, color: oc.dimmed),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  // Without this fl_chart falls back to its own tooltip, which
                  // prints the raw double — a balance came out as
                  // "-770.8900000000001". Money is never a bare toString().
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => oc.surface,
                      tooltipBorderRadius: BorderRadius.circular(6),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
                            formatCurrency(s.y, code),
                            TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: s.y < 0 ? ExpndColors.red : oc.text,
                            ),
                          ),
                      ],
                    ),
                    getTouchedSpotIndicator: (bar, indexes) => [
                      for (final _ in indexes)
                        TouchedSpotIndicatorData(
                          FlLine(color: oc.border, strokeWidth: 1),
                          FlDotData(
                            getDotPainter: (spot, _, _, _) =>
                                FlDotCirclePainter(
                                  radius: 4,
                                  color: lineColor,
                                  strokeWidth: 2,
                                  strokeColor: oc.surface,
                                ),
                          ),
                        ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      // Clamp the spline so it never bulges above/below a real
                      // data point — the old curve overshot and invented peaks.
                      preventCurveOverShooting: true,
                      curveSmoothness: 0.28,
                      color: lineColor,
                      barWidth: 2.5,
                      // Mark only the latest point so the current balance is
                      // pinned on the curve.
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, _) => spot.x == spots.last.x,
                        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                          radius: 4,
                          color: lineColor,
                          strokeWidth: 2,
                          strokeColor: oc.surface,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            lineColor.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthlyBarCard(
    ExpndColors oc,
    List<Transaction> filtered,
    String code,
  ) {
    // group by month
    final Map<DateTime, (double, double)> byMonth = {};
    for (final t in filtered) {
      final key = DateTime(t.date.year, t.date.month);
      final pair = byMonth[key] ?? (0.0, 0.0);
      byMonth[key] = t.type == TransactionType.income
          ? (pair.$1 + t.amount, pair.$2)
          : (pair.$1, pair.$2 + t.amount);
    }
    final months = byMonth.keys.toList()..sort();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    // Headroom above the tallest bar so a single-month chart doesn't slam a bar
    // into the ceiling, and a faint track behind each rod grounds it to zero.
    double maxV = 0;
    for (final m in months) {
      final (inc, exp) = byMonth[m]!;
      if (inc > maxV) maxV = inc;
      if (exp > maxV) maxV = exp;
    }
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.2;
    final barInterval = maxY / 3;

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < months.length; i++) {
      final (inc, exp) = byMonth[months[i]]!;
      BarChartRodData rod(double v, Color c) => BarChartRodData(
        toY: v,
        color: c,
        width: 12,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        backDrawRodData: BackgroundBarChartRodData(
          show: true,
          toY: maxY,
          color: oc.border.withValues(alpha: 0.35),
        ),
      );
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 6,
          barRods: [rod(inc, ExpndColors.green), rod(exp, ExpndColors.red)],
        ),
      );
    }

    return _chartCard(
      oc,
      'INCOME VS EXPENSES',
      'chart.bar.fill',
      Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _legendDot(ExpndColors.green, 'Income', oc),
              const SizedBox(width: 12),
              _legendDot(ExpndColors.red, 'Expenses', oc),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barGroups: groups,
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => oc.surface,
                    tooltipBorderRadius: BorderRadius.circular(6),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      formatCurrency(rod.toY, code),
                      TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: rod.color ?? oc.text,
                      ),
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: barInterval <= 0 ? null : barInterval,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: oc.border, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      interval: barInterval <= 0 ? null : barInterval,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value <= 0) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _compact(value, code),
                            style: TextStyle(fontSize: 9, color: oc.dimmed),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= months.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthNames[months[i].month - 1],
                            style: TextStyle(fontSize: 9, color: oc.dimmed),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, ExpndColors oc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: oc.muted,
          ),
        ),
      ],
    );
  }

  List<Widget> _categoryCards(
    ExpndColors oc,
    AppStore store,
    List<Transaction> filtered,
    String code,
  ) {
    final expenses = filtered.where((t) => t.type == TransactionType.expense);
    final total = expenses.fold(0.0, (s, t) => s + t.amount);
    if (total <= 0) return [];
    final Map<TransactionCategory, double> grouped = {};
    for (final t in expenses) {
      grouped[t.category] = (grouped[t.category] ?? 0) + t.amount;
    }
    final slices = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return [
      _chartCard(
        oc,
        'SPENDING BREAKDOWN',
        'chart.pie.fill',
        Row(
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2.5,
                      centerSpaceRadius: 40,
                      sections: [
                        for (final s in slices.take(7))
                          PieChartSectionData(
                            value: s.value,
                            color: s.key.color,
                            radius: 28,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${slices.length}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: oc.text,
                        ),
                      ),
                      Text(
                        slices.length == 1 ? 'category' : 'categories',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: oc.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in slices.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.key.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.key.raw,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: oc.text,
                              ),
                            ),
                          ),
                          Text(
                            '${((s.value / total) * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: s.key.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (slices.length > 5)
                    Text(
                      '+ ${slices.length - 5} more',
                      style: TextStyle(fontSize: 10, color: oc.dimmed),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _chartCard(
        oc,
        'TOP CATEGORIES',
        'chart.bar.xaxis',
        Column(
          children: [
            for (final s in slices.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.key.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: s.key.color.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        sfIcon(s.key.icon),
                        size: 13,
                        color: s.key.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.key.raw,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: oc.text,
                                  ),
                                ),
                              ),
                              Text(
                                formatCurrency(s.value, code),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: s.key.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRect(
                            child: LayoutBuilder(
                              builder: (context, c) {
                                return Stack(
                                  children: [
                                    Container(height: 4, color: oc.border),
                                    Container(
                                      height: 4,
                                      width: (c.maxWidth * (s.value / total))
                                          .clamp(4.0, c.maxWidth),
                                      color: s.key.color,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _emptyState(ExpndColors oc) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: ExpndColors.gold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(sfIcon('chart.bar.xaxis'), size: 40, color: oc.accent),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No data yet',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: oc.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add transactions to see your\nspending analytics here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: oc.muted),
        ),
      ],
    );
  }
}
