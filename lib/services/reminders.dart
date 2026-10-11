import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../store/app_store.dart';
import '../store/settings_store.dart';
import 'alerts.dart';
import 'cash_flow.dart';
import 'insights.dart';

/// Every notification EXPND sends — the nightly nudge, bill warnings, the
/// weekly roundup, and the state alerts (over budget, goal reached).
///
/// All of it is local: scheduled on-device by the OS, no server, no push token,
/// nothing leaves the phone. The app still makes no network requests. This
/// class is the *only* part of the notification feature that touches the OS —
/// the copy and the timing are decided by pure functions in `insights.dart`
/// and `alerts.dart`, so everything worth testing is tested without a plugin.
///
/// [refreshAll] is the single entry point: hand it the store and settings and
/// it rebuilds every scheduled surface and fires anything newly true. It is
/// cheap and idempotent — each queue is cancelled and re-laid — so the app
/// calls it on launch and after any change that could move a figure.
class Reminders {
  Reminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // ── Notification id ranges ──────────────────────────────────────────────────
  // Each surface owns a disjoint block so rebuilding one never disturbs another.
  // The queues are deliberately short: iOS caps an app at 64 pending
  // notifications, and the totals below (7 + 15 + 4) sit comfortably under it.

  /// Nightly nudge — one id per queued day.
  static const _dailyBaseId = 1001;
  static const dailyQueueDays = 7;

  /// Bill / due-soon warnings.
  static const _billBaseId = 1100;
  static const billMaxCount = 15;

  /// Weekly roundup — a short run of dated one-shots, rebuilt each launch so
  /// the summary never goes stale, the same reasoning as the nightly queue.
  static const _weeklyBaseId = 1200;
  static const weeklyQueueWeeks = 4;

  /// State alerts, shown immediately rather than scheduled.
  static const _overBudgetId = 1300;
  static const _goalBaseId = 1310;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _deviceTimeZone()));
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Permission is requested later, when the user actually turns a
        // reminder on — a prompt on first launch, before they know what it's
        // for, is how you get denied forever.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// The IANA zone the device is in, so 9pm stays 9pm after the user flies
  /// somewhere. Falls back to UTC if the platform won't say.
  static Future<String> _deviceTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (info.identifier.isNotEmpty) return info.identifier;
    } catch (_) {
      // fall through
    }
    return 'UTC';
  }

  /// Asks the OS for permission. Returns whether it was granted — the caller
  /// keeps the setting off when it wasn't, so a toggle never claims an alert is
  /// on when the OS will silently drop it.
  static Future<bool> requestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  // ── The orchestrator ────────────────────────────────────────────────────────

  /// Rebuilds every scheduled surface from the ledger + settings as they stand
  /// right now, and fires any state alert that's newly true. Each surface is
  /// gated by its own setting, so turning one off cancels just that queue and
  /// leaves the rest in place.
  ///
  /// State alerts ([SettingsStore.alertOverBudget] / [alertGoalReached]) are
  /// deduped through markers persisted back onto [settings], so the same
  /// crossing is only ever announced once.
  static Future<void> refreshAll(AppStore store, SettingsStore settings) async {
    await init();
    final t = settings.reminderTime;
    final tone = reminderToneFromString(settings.reminderTone);
    final code = settings.currencyCode;
    final period = settings.budgetCycle == 'calendar'
        ? null
        : budgetPeriodFor(settings, DateTime.now());
    final budget = period == null
        ? store.effectiveMonthlyBudget(
            settings.monthlyBudget,
            rollover: settings.budgetRollover,
          )
        : settings.monthlyBudget;

    // ── Nightly nudge ─────────────────────────────────────────────────────────
    if (settings.dailyReminder) {
      await scheduleDaily(
        t.hour,
        t.minute,
        title: reminderVoice(tone, name: settings.userName).title,
        activeDays: settings.reminderDays,
        bodies: buildReminderBodies(
          store,
          code,
          monthlyBudget: period == null ? budget : 0,
          count: dailyQueueDays,
          customMessage: settings.reminderCustomMessage,
          mode: settings.reminderMessageMode,
          tone: tone,
        ),
      );
    } else {
      await _cancelRange(_dailyBaseId, dailyQueueDays);
    }

    // ── Bills due soon ────────────────────────────────────────────────────────
    if (settings.alertBillsDue) {
      final dueAlerts = [
        ...dueSoonAlerts(
          store,
          code,
          hour: t.hour,
          minute: t.minute,
          cap: billMaxCount,
        ),
        ...trialEndAlerts(store.transactions, hour: t.hour, minute: t.minute),
      ]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
      await scheduleBillAlerts(dueAlerts.take(billMaxCount).toList());
    } else {
      await _cancelRange(_billBaseId, billMaxCount);
    }

    // ── Weekly roundup ────────────────────────────────────────────────────────
    if (settings.weeklySummary) {
      await scheduleWeekly(
        settings.weeklySummaryDay,
        t.hour,
        t.minute,
        title: 'Your week in money',
        body: buildWeeklySummaryBody(
          store,
          code,
          monthlyBudget: period == null ? budget : 0,
        ),
      );
    } else {
      await _cancelRange(_weeklyBaseId, weeklyQueueWeeks);
    }

    // ── State alerts (fired on the spot) ──────────────────────────────────────
    if (settings.alertOverBudget) {
      final alert = overBudgetAlert(
        store,
        code,
        monthlyBudget: budget,
        period: period,
        lastAlertedMonth: settings.lastOverBudgetAlertMonth,
      );
      if (alert != null) {
        await showNow(_overBudgetId, alert.title, alert.body);
        settings.lastOverBudgetAlertMonth = budgetAlertKey(
          DateTime.now(),
          period: period,
        );
      }
    }

    if (settings.alertGoalReached) {
      final reached = newlyReachedGoals(store, settings.goalsCelebrated);
      if (reached.isNotEmpty) {
        var id = _goalBaseId;
        final celebrated = [...settings.goalsCelebrated];
        for (final g in reached) {
          final alert = goalReachedAlert(g, code);
          await showNow(id++, alert.title, alert.body);
          celebrated.add(g.id);
        }
        settings.goalsCelebrated = celebrated;
      }
    }
  }

  // ── Scheduling helpers ──────────────────────────────────────────────────────

  /// Schedules the nightly nudge at [hour]:[minute].
  ///
  /// [bodies] are the lines to use, one per firing night — pass what
  /// [buildReminderBodies] produced. One repeating notification can only ever
  /// carry one body, so a queue of dated one-shots is what buys different text
  /// each night. [activeDays] mutes the days the user switched off (as
  /// `DateTime.weekday` numbers); a body index that only advances on the nights
  /// that fire keeps the surviving nights varied.
  static Future<void> scheduleDaily(
    int hour,
    int minute, {
    List<String> bodies = const [],
    String title = 'Log today\'s spending',
    Set<int>? activeDays,
  }) async {
    await init();
    await _cancelRange(_dailyBaseId, dailyQueueDays);

    final days = activeDays ?? const {1, 2, 3, 4, 5, 6, 7};
    var bodyIndex = 0;
    for (var offset = 0; offset < dailyQueueDays; offset++) {
      final when = _nextInstanceOf(hour, minute, addDays: offset);
      if (!days.contains(when.weekday)) continue; // a night the user muted
      final body = bodies.isEmpty
          ? _genericBody
          : bodies[bodyIndex % bodies.length];
      bodyIndex++;
      await _plugin.zonedSchedule(
        id: _dailyBaseId + offset,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _scheduledDetails(
          'daily_reminder',
          'Daily reminder',
          'Nightly nudge to log the day\'s spending.',
        ),
        // Inexact on purpose: a nudge doesn't justify SCHEDULE_EXACT_ALARM,
        // which Play treats as a restricted permission needing justification.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Schedules one warning per [alerts] entry, at the moment it carries. The
  /// list is expected from [dueSoonAlerts], already capped and future-only.
  static Future<void> scheduleBillAlerts(List<DueAlert> alerts) async {
    await init();
    await _cancelRange(_billBaseId, billMaxCount);
    for (var i = 0; i < alerts.length && i < billMaxCount; i++) {
      final a = alerts[i];
      await _plugin.zonedSchedule(
        id: _billBaseId + i,
        title: a.title,
        body: a.body,
        scheduledDate: tz.TZDateTime.from(a.fireAt, tz.local),
        notificationDetails: _scheduledDetails(
          'bill_alert',
          'Bill reminders',
          'A heads-up the day before a bill or installment is due.',
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Schedules the weekly roundup at [hour]:[minute] on [weekday], for the next
  /// [weeklyQueueWeeks] weeks. The body is the same each week; refreshing on
  /// every launch keeps it current.
  static Future<void> scheduleWeekly(
    int weekday,
    int hour,
    int minute, {
    required String title,
    required String body,
  }) async {
    await init();
    await _cancelRange(_weeklyBaseId, weeklyQueueWeeks);
    for (var w = 0; w < weeklyQueueWeeks; w++) {
      await _plugin.zonedSchedule(
        id: _weeklyBaseId + w,
        title: title,
        body: body,
        scheduledDate: _nextInstanceOfWeekday(
          weekday,
          hour,
          minute,
          addWeeks: w,
        ),
        notificationDetails: _scheduledDetails(
          'weekly_summary',
          'Weekly summary',
          'A once-a-week look at where your money went.',
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Shows a notification right now. Used for the state alerts, whose condition
  /// is already true — there's nothing in the future to schedule against. The
  /// iOS presentation flags are set so it surfaces even if the app happens to
  /// be foregrounded when the crossing is noticed.
  static Future<void> showNow(int id, String title, String body) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        android: AndroidNotificationDetails(
          'event_alert',
          'Alerts',
          channelDescription: 'Budget and savings-goal alerts.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// Cancels every notification this app schedules. Used when wiping data.
  static Future<void> cancelAll() async {
    await init();
    await _cancelRange(_dailyBaseId, dailyQueueDays);
    await _cancelRange(_billBaseId, billMaxCount);
    await _cancelRange(_weeklyBaseId, weeklyQueueWeeks);
  }

  static const _genericBody =
      'A minute now beats reconstructing the week on Sunday.';

  static NotificationDetails _scheduledDetails(
    String channelId,
    String channelName,
    String channelDescription,
  ) => NotificationDetails(
    iOS: const DarwinNotificationDetails(),
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static Future<void> _cancelRange(int baseId, int count) async {
    for (var i = 0; i < count; i++) {
      await _plugin.cancel(id: baseId + i);
    }
  }

  /// Today at [hour]:[minute] if that's still ahead, otherwise tomorrow —
  /// then [addDays] further out, for queueing a run of nights.
  static tz.TZDateTime _nextInstanceOf(
    int hour,
    int minute, {
    int addDays = 0,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next.add(Duration(days: addDays));
  }

  /// The next [weekday] (1 = Mon … 7 = Sun) at [hour]:[minute], then [addWeeks]
  /// further out. Fires today when today is that weekday and the time's ahead.
  static tz.TZDateTime _nextInstanceOfWeekday(
    int weekday,
    int hour,
    int minute, {
    int addWeeks = 0,
  }) {
    var next = _nextInstanceOf(hour, minute);
    while (next.weekday != weekday) {
      next = next.add(const Duration(days: 1));
    }
    return next.add(Duration(days: 7 * addWeeks));
  }
}
