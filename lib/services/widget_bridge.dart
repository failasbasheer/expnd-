import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/models.dart';
import 'cash_flow.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';

/// Pushes a lightweight snapshot of the user's finances into the shared
/// container the native home-screen widgets read from — a WidgetKit App Group
/// on iOS, `HomeWidgetProvider` SharedPreferences on Android.
///
/// The widgets are read-only glances, so the contract is deliberately flat:
/// pre-formatted strings the native side renders verbatim, never raw models.
/// Everything funnels through [sync], which we hang off the stores' change
/// notifications so a refresh happens on every mutation with no call sites to
/// remember. Balances stay transactions-authoritative — we only ever read
/// [AppStore.balanceFor], never recompute or mutate.
class WidgetBridge {
  WidgetBridge._();

  /// Must match the App Group added to both the Runner and widget targets in
  /// Xcode, and the `home_widget` group id. Ignored on Android.
  static const appGroupId = 'group.com.expnd.app';

  /// WidgetKit widget kind (the `kind:` string in the Swift widget).
  static const _iOSWidgetName = 'ExpndWidget';

  /// The Quick Log widget's kind (QuickLogWidget.swift).
  static const _iOSQuickLogWidgetName = 'ExpndQuickLogWidget';

  /// Fully-qualified Android provider so `updateWidget` can target it.
  static const _androidProvider = 'com.failas.expnd.ExpndWidgetProvider';

  /// URI the quick-add button launches the app with.
  static const quickAddUri = 'expnd://add';

  static AppStore? _store;
  static SettingsStore? _settings;
  static bool _attached = false;

  /// Wires the bridge to the live stores. Safe to call once at boot; after
  /// this, any transaction/account/settings change re-syncs automatically.
  static Future<void> attach(AppStore store, SettingsStore settings) async {
    _store = store;
    _settings = settings;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (e) {
      debugPrint('WidgetBridge.setAppGroupId failed: $e');
    }
    if (!_attached) {
      store.addListener(_scheduleSync);
      settings.addListener(_scheduleSync);
      _attached = true;
    }
    await sync();
  }

  // Coalesce bursts of notifications (e.g. importing many rows) into one push.
  static Timer? _debounce;
  static void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), sync);
  }

  /// Computes the snapshot and hands it to the native widgets.
  static Future<void> sync() async {
    final store = _store;
    final settings = _settings;
    if (store == null || settings == null) return;

    final code = settings.currencyCode;
    final now = DateTime.now();

    final isCalendar = settings.budgetCycle == 'calendar';
    final monthSpent = budgetSpentInPeriod(
      store,
      budgetPeriodFor(settings, now),
    );

    // Same effective limit as the Plan gauge: base budget plus last month's
    // leftover when rollover is on. The widget leads with what's left rather
    // than net worth, which is too revealing on a glanceable Home Screen.
    final base = settings.monthlyBudget;
    final budget = isCalendar && settings.budgetRollover && base > 0
        ? store.rolledOverLimit(base, now)
        : base;
    final ratio = budget > 0 ? (monthSpent / budget).clamp(0.0, 1.0) : -1.0;
    final left = budget - monthSpent;

    final recent = store.transactions.take(3).toList();

    // What the Quick Log widget needs to draw its buttons. Presets go over as
    // a plain comma list because the native side only ever parses them back
    // into doubles, and repeat-last carries the raw amount rather than a
    // formatted string — the widget re-reads it at tap time so a stale
    // timeline can never log a number the user has moved past.
    final presets = settings.quickCapturePresets;
    final expenses = store.transactions.where(
      (t) => t.type == TransactionType.expense,
    );
    final lastExpense = expenses.isEmpty ? null : expenses.first;

    try {
      await Future.wait([
        HomeWidget.saveWidgetData('has_data', store.accounts.isNotEmpty),
        HomeWidget.saveWidgetData('currency', code),
        HomeWidget.saveWidgetData('amounts_hidden', settings.amountsHidden),
        HomeWidget.saveWidgetData('symbol', currencySymbol(code)),
        HomeWidget.saveWidgetData(
          'left_to_spend',
          budget > 0 ? formatCurrency(left.abs(), code, maskable: true) : '',
        ),
        HomeWidget.saveWidgetData('over_budget', budget > 0 && left < 0),
        HomeWidget.saveWidgetData(
          'month_label',
          isCalendar ? _monthName(now.month).toUpperCase() : 'THIS PERIOD',
        ),
        HomeWidget.saveWidgetData(
          'month_spent',
          formatCurrency(monthSpent, code, maskable: true),
        ),
        HomeWidget.saveWidgetData(
          'budget_ratio',
          ratio < 0 ? -1 : (ratio * 100).round(),
        ),
        HomeWidget.saveWidgetData(
          'budget_text',
          budget > 0
              ? 'of ${formatCurrency(budget, code, maskable: true)}'
              : '',
        ),
        HomeWidget.saveWidgetData('tx_count', recent.length),
        for (var i = 0; i < recent.length; i++) ...[
          HomeWidget.saveWidgetData('tx${i}_note', _label(recent[i], store)),
          HomeWidget.saveWidgetData(
            'tx${i}_amount',
            signedAmountFor(recent[i], code),
          ),
          HomeWidget.saveWidgetData(
            'tx${i}_positive',
            recent[i].type == TransactionType.income,
          ),
        ],
        HomeWidget.saveWidgetData(
          'presets',
          presets.map((p) => p.toString()).join(','),
        ),
        HomeWidget.saveWidgetData(
          'last_expense_amount',
          lastExpense?.amount ?? 0.0,
        ),
        HomeWidget.saveWidgetData(
          'last_expense_note',
          lastExpense == null ? '' : _label(lastExpense, store),
        ),
        HomeWidget.saveWidgetData('updated', now.millisecondsSinceEpoch),
      ]);

      await HomeWidget.updateWidget(
        iOSName: _iOSWidgetName,
        qualifiedAndroidName: _androidProvider,
      );
      // `updateWidget` reloads one WidgetKit kind; the Quick Log widget has
      // its own and a `.never` policy, so it went stale without this.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.updateWidget(iOSName: _iOSQuickLogWidgetName);
      }
    } catch (e) {
      debugPrint('WidgetBridge.sync failed: $e');
    }
  }

  /// A human label for a transaction row: its note, else the category name.
  static String _label(Transaction t, AppStore store) {
    if (t.note.trim().isNotEmpty) return t.note.trim();
    if (t.customCategoryId != null) {
      final c = store.customCategoryFor(t.customCategoryId);
      if (c != null) return c.name;
    }
    return t.category.raw;
  }

  /// Signed, symbol-prefixed amount: `+₹1,200.00` / `-$4.50`. Transfers are
  /// balance-neutral overall, so they read without a sign.
  @visibleForTesting
  static String signedAmountFor(Transaction t, String code) {
    final formatted = formatCurrency(t.amount, code);
    switch (t.type) {
      case TransactionType.income:
        return '+$formatted';
      case TransactionType.expense:
        return '-$formatted';
      case TransactionType.transfer:
        return formatted;
    }
  }

  static String _monthName(int m) => const [
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
  ][m - 1];
}
