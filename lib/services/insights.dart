import '../models/models.dart';
import '../store/app_store.dart';
import '../theme/currencies.dart';
import 'upcoming.dart';

/// Sentences the app can say about your money.
///
/// Everything here is arithmetic over data already in the store — no model, no
/// network, no guesses. That is deliberate: this app has no internet permission
/// at all, and beside someone's budget a confidently wrong number is worse than
/// silence. Every line below traces to a figure the user can go and verify.
///
/// Insights are *derived on read* and never stored, the same rule the Upcoming
/// projections follow.

enum InsightTone {
  /// Something is going well — under budget, a streak, a goal in reach.
  good,

  /// Neutral fact worth knowing.
  neutral,

  /// Something to look at — overspending, a big bill landing, a stale ledger.
  warn,
}

class Insight {
  /// Short headline, e.g. "Food is up 34%".
  final String title;

  /// The supporting detail, e.g. "vs your 3-month average of $210".
  final String detail;

  final InsightTone tone;
  final String icon;

  /// Higher sorts first. Used to pick the few worth showing.
  final int weight;

  const Insight({
    required this.title,
    required this.detail,
    required this.tone,
    required this.icon,
    this.weight = 0,
  });

  /// One line, for places with no room for two — the daily notification.
  String get sentence => '$title — $detail';
}

/// Everything worth saying right now, most important first.
///
/// [from] exists for tests; production callers let it default to now.
List<Insight> buildInsights(
  AppStore store,
  String code, {
  DateTime? from,
  double monthlyBudget = 0,
}) {
  final now = from ?? DateTime.now();
  final out = <Insight>[];

  String money(double v) => formatCurrency(v, code);

  // ── Budget pace ───────────────────────────────────────────────────────────
  // "On track" needs the month's shape, not just its total: being 60% through
  // the budget on the 5th is very different from the 25th.
  if (monthlyBudget > 0) {
    final spent = store.spentInMonth(now);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final elapsed = now.day / daysInMonth;
    final projected = elapsed > 0 ? spent / elapsed : spent;
    final diff = monthlyBudget - projected;

    if (spent > monthlyBudget) {
      out.add(
        Insight(
          title: 'Over budget by ${money(spent - monthlyBudget)}',
          detail: 'with ${daysInMonth - now.day} days still to go',
          tone: InsightTone.warn,
          icon: 'exclamationmark.triangle.fill',
          weight: 100,
        ),
      );
    } else if (diff < 0) {
      out.add(
        Insight(
          title: 'On pace to overspend',
          detail:
              'heading for ${money(projected)} against ${money(monthlyBudget)}',
          tone: InsightTone.warn,
          icon: 'chart.line.uptrend.xyaxis',
          weight: 90,
        ),
      );
    } else if (now.day >= 10) {
      // Early in the month the projection is too noisy to be worth saying.
      out.add(
        Insight(
          title: 'On track to finish ${money(diff)} under',
          detail: '${money(spent)} of ${money(monthlyBudget)} so far',
          tone: InsightTone.good,
          icon: 'checkmark.circle.fill',
          weight: 60,
        ),
      );
    }
  }

  // ── Category vs its own recent average ────────────────────────────────────
  // Compared against the same category's last three months rather than against
  // other categories, because "you spend more on rent than coffee" is not news.
  final categoryShifts = <Insight>[];
  for (final cat in TransactionCategory.values) {
    final thisMonth = store.spentInMonth(now, category: cat);
    if (thisMonth <= 0) continue;

    var total = 0.0;
    var months = 0;
    for (var i = 1; i <= 3; i++) {
      final m = DateTime(now.year, now.month - i);
      total += store.spentInMonth(m, category: cat);
      months++;
    }
    if (months == 0) continue;
    final average = total / months;
    // A category with no history yet has nothing to be up or down against.
    if (average < 1) continue;

    final change = (thisMonth - average) / average;
    // Ignore noise; a tenth either way is not a finding.
    if (change.abs() < 0.25) continue;

    final pct = (change.abs() * 100).round();
    categoryShifts.add(
      Insight(
        title: '${cat.raw} is ${change > 0 ? 'up' : 'down'} $pct%',
        detail: '${money(thisMonth)} vs a ${money(average)} average',
        tone: change > 0 ? InsightTone.warn : InsightTone.good,
        icon: cat.icon,
        // Bigger swings, and rises over falls, are the ones worth the space.
        weight: 40 + (change.abs() * 20).round() + (change > 0 ? 5 : 0),
      ),
    );
  }
  categoryShifts.sort((a, b) => b.weight.compareTo(a.weight));
  out.addAll(categoryShifts.take(2));

  // ── Renewals landing this week ────────────────────────────────────────────
  final week = projectUpcoming(
    store,
    from: now,
    horizonDays: 7,
  ).where((i) => !i.isInflow).toList();
  if (week.isNotEmpty) {
    final total = week.fold(0.0, (s, i) => s + i.amount);
    out.add(
      Insight(
        title:
            '${week.length} payment${week.length == 1 ? '' : 's'} due this week',
        detail:
            '${money(total)} committed by ${_weekday(now.add(const Duration(days: 7)))}',
        tone: InsightTone.neutral,
        icon: 'calendar.badge.clock',
        weight: 70,
      ),
    );
  }

  // ── A category held under its budget, month after month ───────────────────
  for (final b in store.budgets) {
    final cat = b.category;
    if (cat == null || b.limit <= 0) continue;
    var streak = 0;
    for (var i = 1; i <= 6; i++) {
      final m = DateTime(now.year, now.month - i);
      final spent = store.spentInMonth(m, category: cat);
      // A month with no spending at all isn't a win, it's an empty month.
      if (spent <= 0 || spent > b.limit) break;
      streak++;
    }
    if (streak >= 3) {
      out.add(
        Insight(
          title: '${cat.raw} under budget $streak months running',
          detail: 'holding at ${money(b.limit)} a month',
          tone: InsightTone.good,
          icon: 'checkmark.circle.fill',
          weight: 50,
        ),
      );
    }
  }

  // ── A stale ledger ────────────────────────────────────────────────────────
  // The whole app depends on the user typing things in, so a gap is the most
  // useful thing it can point out.
  final txns = store.transactions;
  if (txns.isNotEmpty) {
    final gap = now.difference(txns.first.date).inDays;
    if (gap >= 3) {
      out.add(
        Insight(
          title: 'Nothing logged in $gap days',
          detail: 'the longer the gap, the harder it is to remember',
          tone: InsightTone.warn,
          icon: 'clock.fill',
          weight: 80,
        ),
      );
    }
  }

  // ── Biggest single expense this month ─────────────────────────────────────
  final monthExpenses =
      txns
          .where(
            (t) =>
                t.type == TransactionType.expense &&
                t.date.year == now.year &&
                t.date.month == now.month,
          )
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
  if (monthExpenses.length >= 3) {
    final top = monthExpenses.first;
    final total = monthExpenses.fold(0.0, (s, t) => s + t.amount);
    final share = total > 0 ? top.amount / total : 0.0;
    if (share >= 0.25) {
      out.add(
        Insight(
          title: '${(share * 100).round()}% of this month was one purchase',
          detail:
              '${money(top.amount)}'
              '${top.note.trim().isEmpty ? ' on ${top.category.raw}' : ' — ${top.note.trim()}'}',
          tone: InsightTone.neutral,
          icon: 'chart.pie.fill',
          weight: 45,
        ),
      );
    }
  }

  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out;
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekday(DateTime d) => _weekdays[d.weekday - 1];

/// The voice a reminder speaks in. Chosen by the user; parsed from the stored
/// string so an unknown value falls back to [neutral] rather than throwing.
enum ReminderTone { neutral, gentle, blunt, playful }

ReminderTone reminderToneFromString(String s) {
  switch (s) {
    case 'gentle':
      return ReminderTone.gentle;
    case 'blunt':
      return ReminderTone.blunt;
    case 'playful':
      return ReminderTone.playful;
    default:
      return ReminderTone.neutral;
  }
}

/// The framing a tone puts around a reminder: the bold **title** on the lock
/// screen and the pool of **filler** lines used when the ledger has nothing to
/// report. Deliberately the *only* place tone lives — an insight's body ("Food
/// is up 34% — …") is never routed through here, so a personality setting can
/// never reword a figure into being wrong.
class ReminderVoice {
  final String title;
  final List<String> filler;
  const ReminderVoice(this.title, this.filler);
}

/// A first name to address the user by, or null when they haven't set one.
/// [SettingsStore.userName] defaults to the placeholder 'Your Name', which is
/// treated as "no name" rather than greeting someone by it.
String? _firstName(String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty || n == 'Your Name') return null;
  return n.split(RegExp(r'\s+')).first;
}

/// The [ReminderVoice] for [tone], greeting [name] when one is set.
ReminderVoice reminderVoice(ReminderTone tone, {String? name}) {
  final n = _firstName(name);
  switch (tone) {
    case ReminderTone.gentle:
      return ReminderVoice(
        n == null ? 'A quick check-in' : 'A quick check-in, $n',
        const [
          'No rush — a few taps whenever you have a moment.',
          "Anything from today worth jotting down before it slips?",
          'Small and often keeps it painless.',
          'Whenever you’re ready, the ledger’s here.',
        ],
      );
    case ReminderTone.blunt:
      return ReminderVoice(n == null ? 'Log it.' : '$n — log it.', const [
        'Type it in now, not on Sunday.',
        'Nothing logged yet today.',
        'Small ones count. Add them.',
        'Thirty seconds. Do it.',
      ]);
    case ReminderTone.playful:
      return ReminderVoice(
        n == null ? 'Where’d it go? 💸' : '$n, where’d it go? 💸',
        const [
          'Your wallet won’t snitch on itself. 🕵️',
          'Feed the ledger before it forgets. 🍽️',
          'Tiny spends are sneaky. Catch ’em. 🐭',
          'Thirty seconds to keep the month honest. ⏱️',
        ],
      );
    case ReminderTone.neutral:
      return ReminderVoice(
        n == null ? 'Log today\'s spending' : 'Log today\'s spending, $n',
        const [
          'A minute now beats reconstructing the week on Sunday.',
          "Anything you paid for today that isn't in yet?",
          'Small ones are the ones that get forgotten.',
          'Thirty seconds keeps the month honest.',
        ],
      );
  }
}

/// Lines for the nightly reminder, one per queued day, newest concern first.
///
/// The generic "log today's spending" said the same thing every night, which
/// is how a daily notification becomes wallpaper and then gets switched off.
/// These are the same insights the dashboard shows, phrased for a lock screen
/// and padded with [tone]'s filler when there is little to say — a new user
/// with three transactions has no trends yet, and inventing some would be
/// worse than a plain prompt.
///
/// [mode] chooses where the text comes from:
/// - `auto`   — the ledger-derived insights (padded with filler).
/// - `custom` — the user's own [customMessage] every night; falls back to
///   `auto` when they've left it blank, so a half-set option never sends an
///   empty push.
/// - `mixed`  — the custom line rotated in among the auto ones.
///
/// [tone] only shapes the filler; the insight bodies are verbatim.
List<String> buildReminderBodies(
  AppStore store,
  String code, {
  DateTime? from,
  double monthlyBudget = 0,
  int count = 7,
  String customMessage = '',
  String mode = 'auto',
  ReminderTone tone = ReminderTone.neutral,
}) {
  final custom = customMessage.trim();

  // Every-night custom text short-circuits the whole insight engine — but only
  // when there's actually a line to say.
  if (mode == 'custom' && custom.isNotEmpty) {
    return List.filled(count, custom);
  }

  final insights = buildInsights(
    store,
    code,
    from: from,
    monthlyBudget: monthlyBudget,
  );
  final filler = reminderVoice(tone).filler;

  final auto = <String>[for (final i in insights.take(count)) i.sentence];
  var f = 0;
  while (auto.length < count) {
    auto.add(filler[f++ % filler.length]);
  }

  // Mixed: drop the custom line into every other slot, so it recurs without
  // crowding out what the ledger has to say.
  if (mode == 'mixed' && custom.isNotEmpty) {
    for (var i = 1; i < auto.length; i += 2) {
      auto[i] = custom;
    }
  }
  return auto;
}

/// One line summing up the week, for the optional weekly roundup. Reuses the
/// same insights as everywhere else, joined so the most important couple of
/// facts fit a single notification.
String buildWeeklySummaryBody(
  AppStore store,
  String code, {
  DateTime? from,
  double monthlyBudget = 0,
}) {
  final insights = buildInsights(
    store,
    code,
    from: from,
    monthlyBudget: monthlyBudget,
  );
  if (insights.isEmpty) {
    return 'A quiet week on the books. Log as you go and it stays effortless.';
  }
  return insights.take(2).map((i) => i.sentence).join('  •  ');
}
