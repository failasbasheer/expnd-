import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/currencies.dart';

/// Mirrors the app's `@AppStorage` keys. A [ChangeNotifier] so widgets rebuild
/// when a preference changes.
class SettingsStore extends ChangeNotifier {
  final SharedPreferences _p;
  SettingsStore(this._p) {
    // Seed the formatters' privacy gate so a hidden session survives a relaunch.
    AmountPrivacy.hidden = amountsHidden;
  }

  static Future<SettingsStore> create() async =>
      SettingsStore(await SharedPreferences.getInstance());

  String _s(String k, String d) => _p.getString(k) ?? d;
  double _d(String k, double d) => _p.getDouble(k) ?? d;
  bool _b(String k, bool d) => _p.getBool(k) ?? d;

  // appearanceMode: "system" | "light" | "dark"
  // neoPOP is a dark-first design language, so default to dark.
  String get appearanceMode => _s('appearanceMode', 'dark');
  set appearanceMode(String v) {
    _p.setString('appearanceMode', v);
    notifyListeners();
  }

  ThemeMode get themeMode {
    switch (appearanceMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  bool get biometricLockEnabled => _b('biometricLockEnabled', false);
  set biometricLockEnabled(bool v) {
    _p.setBool('biometricLockEnabled', v);
    notifyListeners();
  }

  /// How long the app may sit in the background before biometric unlock is
  /// asked for again. 0 = immediately (re-lock the moment it leaves the
  /// foreground). Anything higher is a grace window so a quick hop to another
  /// app — or the Face ID / notification shade / Control Center flicker —
  /// doesn't demand a fresh scan. Only consulted while [biometricLockEnabled].
  int get autoLockGraceSeconds => _p.getInt('autoLockGraceSeconds') ?? 0;
  set autoLockGraceSeconds(int v) {
    _p.setInt('autoLockGraceSeconds', v);
    notifyListeners();
  }

  /// The user's selected currency. This is the single default used everywhere
  /// (net worth, account cards, transactions, analytics). Falls back to USD
  /// until the user picks one.
  String get currencyCode => _s('currencyCode', 'USD');

  set currencyCode(String v) {
    _p.setString('currencyCode', v);
    notifyListeners();
  }

  /// The eye button. When on, every amount the app renders is masked — net
  /// balance, account cards, transactions, analytics, savings goals. Persisted
  /// so the app reopens in whichever state the user left it, and mirrored into
  /// [AmountPrivacy] where the formatters read it.
  bool get amountsHidden => _b('amountsHidden', false);
  set amountsHidden(bool v) {
    _p.setBool('amountsHidden', v);
    AmountPrivacy.hidden = v;
    notifyListeners();
  }

  double get monthlyBudget => _d('monthlyBudget', 0.0);
  set monthlyBudget(double v) {
    _p.setDouble('monthlyBudget', v);
    notifyListeners();
  }

  /// Calendar month by default for existing users. Other cycles use the
  /// configured payday as the first day of each budget period.
  String get budgetCycle {
    final value = _s('budgetCycle', 'calendar');
    return const {'calendar', 'payday', 'weekly', 'fortnightly'}.contains(value)
        ? value
        : 'calendar';
  }

  set budgetCycle(String value) {
    if (!const {
      'calendar',
      'payday',
      'weekly',
      'fortnightly',
    }.contains(value)) {
      return;
    }
    _p.setString('budgetCycle', value);
    notifyListeners();
  }

  /// Day of month for monthly payday. Days beyond a month's end are clamped.
  int get paydayDay => (_p.getInt('paydayDay') ?? 1).clamp(1, 31);
  set paydayDay(int value) {
    _p.setInt('paydayDay', value.clamp(1, 31));
    notifyListeners();
  }

  /// Date of a known payday, used as the anchor for weekly and fortnightly
  /// cycles. A local calendar date avoids timezone and DST shifts.
  DateTime get paydayAnchor {
    final raw = _s('paydayAnchor', '2020-01-06');
    final parsed = DateTime.tryParse(raw) ?? DateTime(2020, 1, 6);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  set paydayAnchor(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    _p.setString(
      'paydayAnchor',
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    );
    notifyListeners();
  }

  /// A cash flow estimate needs a real payday, not the fallback UI values.
  bool get paydayConfigured =>
      budgetCycle == 'weekly' || budgetCycle == 'fortnightly'
      ? _p.containsKey('paydayAnchor')
      : _p.containsKey('paydayDay');

  /// Highest [kWhatsNewVersion] whose carousel the user has already seen. 0 for
  /// a fresh key, so upgraders from 1.0.0 (who have no stored value) get the
  /// tour once; new installs have it stamped to current at the end of setup.
  int get whatsNewSeenVersion => _p.getInt('whatsNewSeenVersion') ?? 0;
  set whatsNewSeenVersion(int v) {
    _p.setInt('whatsNewSeenVersion', v);
    notifyListeners();
  }

  /// The day whose greeting has already been spent, as `yyyymmdd`. The
  /// dashboard greets you on the first open of a new day and shows its wordmark
  /// every time after, so this is stamped the moment the greeting is shown
  /// rather than when it retires — reopening the app two seconds later must not
  /// earn a second one. 0 means "never greeted", which is what a fresh install
  /// and every existing user reads as, so everyone gets one on next launch.
  int get lastGreetedDay => _p.getInt('lastGreetedDay') ?? 0;
  set lastGreetedDay(int v) {
    _p.setInt('lastGreetedDay', v);
    notifyListeners();
  }

  String get defaultTransactionType => _s('defaultTransactionType', 'expense');
  set defaultTransactionType(String v) {
    _p.setString('defaultTransactionType', v);
    notifyListeners();
  }

  /// Rolling on-device snapshots. On by default: every row in this app was
  /// typed by hand and there is no server to re-fetch it from, so the cost of
  /// a few small files is nothing against losing the lot.
  bool get autoBackupEnabled => _b('autoBackupEnabled', true);
  set autoBackupEnabled(bool v) {
    _p.setBool('autoBackupEnabled', v);
    notifyListeners();
  }

  /// When the last automatic snapshot was written (ms since epoch, 0 = never).
  int get lastAutoBackupMs => _p.getInt('lastAutoBackupMs') ?? 0;
  set lastAutoBackupMs(int v) {
    _p.setInt('lastAutoBackupMs', v);
    notifyListeners();
  }

  DateTime? get lastAutoBackupAt => lastAutoBackupMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastAutoBackupMs);

  bool get hapticsEnabled => _b('hapticsEnabled', true);
  set hapticsEnabled(bool v) {
    _p.setBool('hapticsEnabled', v);
    notifyListeners();
  }

  /// How the add-transaction category grid is ordered: 'usage' (most-used
  /// first, the default), 'alpha' (A→Z), 'recent' (most-recently used first),
  /// or 'manual' (the hand-arranged order kept in [categoryOrder]).
  String get categorySortMode => _s('categorySortMode', 'usage');
  set categorySortMode(String v) {
    _p.setString('categorySortMode', v);
    notifyListeners();
  }

  /// How the History list is ordered: 'newest' (default) / 'oldest' keep the
  /// day-grouped layout; 'amountDesc' / 'amountAsc' switch to a flat list
  /// ranked by amount.
  String get historySortMode => _s('historySortMode', 'newest');
  set historySortMode(String v) {
    _p.setString('historySortMode', v);
    notifyListeners();
  }

  /// The user's hand-arranged category order, consulted when [categorySortMode]
  /// is 'manual'. Each entry keys a category: a built-in's raw name, or
  /// `custom:<id>` for a custom one. Keys the list doesn't mention fall to the
  /// end (by usage), so creating a category never invalidates a saved order.
  List<String> get categoryOrder =>
      _p.getStringList('categoryOrder') ?? const [];
  set categoryOrder(List<String> v) {
    _p.setStringList('categoryOrder', v);
    notifyListeners();
  }

  /// The amounts the Quick Log widget offers as one-tap buttons. Stored as
  /// strings because SharedPreferences has no double-list; empty means "never
  /// customised", which falls back to [defaultQuickPresets] for the currency.
  ///
  /// A tap logs one of these without any UI, so they have to be plausible in
  /// the user's own currency — ₹100 and $100 are not the same suggestion.
  List<double> get quickCapturePresets {
    final raw = _p.getStringList('quickCapturePresets');
    if (raw == null || raw.isEmpty) return defaultQuickPresets(currencyCode);
    final parsed = raw.map(double.tryParse).whereType<double>().toList();
    return parsed.isEmpty ? defaultQuickPresets(currencyCode) : parsed;
  }

  set quickCapturePresets(List<double> v) {
    _p.setStringList(
      'quickCapturePresets',
      v.map((e) => e.toString()).toList(),
    );
    notifyListeners();
  }

  /// Sensible starting amounts for a currency. Currencies whose everyday note
  /// denominations run large (a ₹100 coffee, a ¥1000 lunch) need a different
  /// ladder from ones where a coffee is 5 — otherwise every preset is either
  /// absurdly small or absurdly large on first launch.
  static List<double> defaultQuickPresets(String code) {
    const largeUnit = {
      'INR',
      'PKR',
      'BDT',
      'LKR',
      'JPY',
      'KRW',
      'IDR',
      'VND',
      'NGN',
      'KES',
      'UGX',
      'TZS',
      'PHP',
      'THB',
      'HUF',
      'CLP',
    };
    return largeUnit.contains(code)
        ? const [100, 500, 1000]
        : const [5, 10, 20];
  }

  bool get hasCompletedAccountSetup => _b('hasCompletedAccountSetup', false);
  set hasCompletedAccountSetup(bool v) {
    _p.setBool('hasCompletedAccountSetup', v);
    notifyListeners();
  }

  String get userName => _s('userName', 'Your Name');
  set userName(String v) {
    _p.setString('userName', v);
    notifyListeners();
  }

  /// When on, whatever a monthly budget didn't use (or overshot) carries into
  /// the next month, YNAB-style, instead of every month starting flat.
  bool get budgetRollover => _b('budgetRollover', false);
  set budgetRollover(bool v) {
    _p.setBool('budgetRollover', v);
    notifyListeners();
  }

  /// The nightly "log today's spending" nudge. Off until the user asks for it
  /// — and only ever true once the OS has actually granted permission, so the
  /// toggle can't claim a reminder that will never fire.
  bool get dailyReminder => _b('dailyReminder', false);
  set dailyReminder(bool v) {
    _p.setBool('dailyReminder', v);
    notifyListeners();
  }

  /// Minutes from midnight, so one int carries the whole time. 21:00.
  int get reminderMinuteOfDay => _p.getInt('reminderMinuteOfDay') ?? 21 * 60;
  set reminderMinuteOfDay(int v) {
    _p.setInt('reminderMinuteOfDay', v);
    notifyListeners();
  }

  TimeOfDay get reminderTime => TimeOfDay(
    hour: reminderMinuteOfDay ~/ 60,
    minute: reminderMinuteOfDay % 60,
  );

  /// A line the user wrote for their own nightly nudge. Empty until they set
  /// one; only ever shown when [reminderMessageMode] asks for it.
  String get reminderCustomMessage => _s('reminderCustomMessage', '');
  set reminderCustomMessage(String v) {
    _p.setString('reminderCustomMessage', v);
    notifyListeners();
  }

  /// Where the nightly text comes from:
  /// - `auto`   — written from the ledger (the default, and what shipped first).
  /// - `custom` — the user's own line, every night.
  /// - `mixed`  — their line rotated in among the auto ones.
  ///
  /// `custom` silently falls back to `auto` when [reminderCustomMessage] is
  /// blank, so a mode set but never filled in never produces an empty push.
  String get reminderMessageMode => _s('reminderMessageMode', 'auto');
  set reminderMessageMode(String v) {
    _p.setString('reminderMessageMode', v);
    notifyListeners();
  }

  /// The voice the notifications speak in: `neutral` (default), `gentle`,
  /// `blunt` or `playful`. Only ever reshapes the greeting/title and the
  /// filler lines — never the figures in an insight, which stay verbatim.
  String get reminderTone => _s('reminderTone', 'neutral');
  set reminderTone(String v) {
    _p.setString('reminderTone', v);
    notifyListeners();
  }

  /// Which weekdays the nightly nudge is allowed to fire, as `DateTime.weekday`
  /// numbers (Mon = 1 … Sun = 7). Default is all seven. Stored as strings
  /// because that's the only list type `shared_preferences` carries.
  Set<int> get reminderDays {
    final raw = _p.getStringList('reminderDays');
    if (raw == null || raw.isEmpty) return {1, 2, 3, 4, 5, 6, 7};
    return raw.map(int.parse).where((d) => d >= 1 && d <= 7).toSet();
  }

  set reminderDays(Set<int> v) {
    // An empty set would silence the reminder while the toggle still reads on,
    // which is exactly the "claims on, fires never" trap the rest of this file
    // avoids — treat "none" as "every day" instead.
    final days = v.isEmpty ? {1, 2, 3, 4, 5, 6, 7} : v;
    _p.setStringList(
      'reminderDays',
      (days.toList()..sort()).map((d) => '$d').toList(),
    );
    notifyListeners();
  }

  /// Event alerts — each a separate, on-device notification the user opts into.
  /// All off by default; turning any on shares the reminder's OS permission.
  bool get alertBillsDue => _b('alertBillsDue', false);
  set alertBillsDue(bool v) {
    _p.setBool('alertBillsDue', v);
    notifyListeners();
  }

  bool get alertOverBudget => _b('alertOverBudget', false);
  set alertOverBudget(bool v) {
    _p.setBool('alertOverBudget', v);
    notifyListeners();
  }

  bool get alertGoalReached => _b('alertGoalReached', false);
  set alertGoalReached(bool v) {
    _p.setBool('alertGoalReached', v);
    notifyListeners();
  }

  /// A once-a-week roundup, sent at [reminderTime] on [weeklySummaryDay].
  bool get weeklySummary => _b('weeklySummary', false);
  set weeklySummary(bool v) {
    _p.setBool('weeklySummary', v);
    notifyListeners();
  }

  /// The weekday the roundup lands on (`DateTime.weekday`; default Sun = 7).
  int get weeklySummaryDay {
    final d = _p.getInt('weeklySummaryDay') ?? 7;
    return d >= 1 && d <= 7 ? d : 7;
  }

  set weeklySummaryDay(int v) {
    _p.setInt('weeklySummaryDay', v);
    notifyListeners();
  }

  // ── Alert dedup markers ─────────────────────────────────────────────────────
  // The "state" alerts (over budget, goal reached) describe a condition that is
  // already true rather than a moment in the future, so they're fired the
  // instant it's noticed and then remembered here, so the same crossing isn't
  // announced twice. Device-local: they track what this phone has said, not
  // data, so they're deliberately left out of the backup.

  /// The month (`yyyymm`) an over-budget alert has already fired for. Resets
  /// naturally each month because the number no longer matches.
  int get lastOverBudgetAlertMonth =>
      _p.getInt('lastOverBudgetAlertMonth') ?? 0;
  set lastOverBudgetAlertMonth(int v) {
    _p.setInt('lastOverBudgetAlertMonth', v);
    // No notifyListeners: a dedup marker changes nothing on screen.
  }

  /// Ids of goals already congratulated, so a reached goal celebrates once.
  List<String> get goalsCelebrated =>
      _p.getStringList('goalsCelebrated') ?? const [];
  set goalsCelebrated(List<String> v) {
    _p.setStringList('goalsCelebrated', v);
  }

  // ── Backup ─────────────────────────────────────────────────────────────────
  // The settings that shape the data itself. Deliberately not included:
  // biometricLockEnabled (tied to this device's enrolled Face ID/fingerprint —
  // restoring it onto a device without one would lock the user out) and
  // amountsHidden (a momentary privacy toggle, not data).

  Map<String, dynamic> backupSnapshot() => {
    'currencyCode': currencyCode,
    'monthlyBudget': monthlyBudget,
    'budgetCycle': budgetCycle,
    if (_p.containsKey('paydayDay')) 'paydayDay': paydayDay,
    if (_p.containsKey('paydayAnchor'))
      'paydayAnchor': _s('paydayAnchor', '2020-01-06'),
    'userName': userName,
    'appearanceMode': appearanceMode,
    'defaultTransactionType': defaultTransactionType,
    'hapticsEnabled': hapticsEnabled,
    'hasCompletedAccountSetup': hasCompletedAccountSetup,
    'budgetRollover': budgetRollover,
    'reminderMinuteOfDay': reminderMinuteOfDay,
    // How the reminders should read — but not which are switched on. Like
    // reminderMinuteOfDay above, the shape travels; the on/off state does
    // not, because notification permission belongs to the device, not the
    // backup (so alertBillsDue, weeklySummary, etc. are deliberately absent).
    'reminderCustomMessage': reminderCustomMessage,
    'reminderMessageMode': reminderMessageMode,
    'reminderTone': reminderTone,
    'reminderDays': (reminderDays.toList()..sort()).map((d) => '$d').toList(),
    'weeklySummaryDay': weeklySummaryDay,
  };

  void applyBackup(Map snapshot) {
    T pick<T>(String k, T fallback) =>
        snapshot[k] is T ? snapshot[k] as T : fallback;
    _p.setString('currencyCode', pick('currencyCode', currencyCode));
    _p.setDouble(
      'monthlyBudget',
      (snapshot['monthlyBudget'] as num?)?.toDouble() ?? monthlyBudget,
    );
    final restoredCycle = snapshot['budgetCycle'];
    if (restoredCycle is String &&
        const {
          'calendar',
          'payday',
          'weekly',
          'fortnightly',
        }.contains(restoredCycle)) {
      _p.setString('budgetCycle', restoredCycle);
    }
    final restoredDay = snapshot['paydayDay'];
    if (restoredDay is num) {
      _p.setInt('paydayDay', restoredDay.toInt().clamp(1, 31));
    }
    final restoredAnchor = snapshot['paydayAnchor'];
    final parsedAnchor = restoredAnchor is String
        ? DateTime.tryParse(restoredAnchor)
        : null;
    if (parsedAnchor != null) {
      // Stored date-only, exactly as the setter writes it.
      final d = parsedAnchor;
      _p.setString(
        'paydayAnchor',
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
    _p.setString('userName', pick('userName', userName));
    _p.setString('appearanceMode', pick('appearanceMode', appearanceMode));
    _p.setString(
      'defaultTransactionType',
      pick('defaultTransactionType', defaultTransactionType),
    );
    _p.setBool('hapticsEnabled', pick('hapticsEnabled', hapticsEnabled));
    // A restored backup always has data behind it — never bounce the user
    // back into first-run setup.
    _p.setBool('hasCompletedAccountSetup', true);
    _p.setBool('budgetRollover', pick('budgetRollover', budgetRollover));
    // The preferred time carries over, but not the on/off state — notification
    // permission belongs to the device, not the backup.
    _p.setInt(
      'reminderMinuteOfDay',
      (snapshot['reminderMinuteOfDay'] as num?)?.toInt() ?? reminderMinuteOfDay,
    );
    // The rest of the reminder shape — how it reads, which days, the weekly
    // day — carries over the same way, again without touching what's on.
    _p.setString(
      'reminderCustomMessage',
      pick('reminderCustomMessage', reminderCustomMessage),
    );
    _p.setString(
      'reminderMessageMode',
      pick('reminderMessageMode', reminderMessageMode),
    );
    _p.setString('reminderTone', pick('reminderTone', reminderTone));
    final days = snapshot['reminderDays'];
    if (days is List) {
      _p.setStringList('reminderDays', days.map((d) => '$d').toList());
    }
    _p.setInt(
      'weeklySummaryDay',
      (snapshot['weeklySummaryDay'] as num?)?.toInt() ?? weeklySummaryDay,
    );
    notifyListeners();
  }
}

/// Global haptics gate (reads the raw pref so non-widget code can call it).
class Haptics {
  static SharedPreferences? prefs;

  static bool get _enabled => prefs?.getBool('hapticsEnabled') ?? true;

  static void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  static void success() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  static void warning() {
    if (_enabled) HapticFeedback.heavyImpact();
  }
}
