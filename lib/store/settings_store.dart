import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the app's `@AppStorage` keys. A [ChangeNotifier] so widgets rebuild
/// when a preference changes.
class SettingsStore extends ChangeNotifier {
  final SharedPreferences _p;
  SettingsStore(this._p);

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

  /// The user's selected currency. This is the single default used everywhere
  /// (net worth, account cards, transactions, analytics). Falls back to USD
  /// until the user picks one.
  String get currencyCode => _s('currencyCode', 'USD');

  set currencyCode(String v) {
    _p.setString('currencyCode', v);
    notifyListeners();
  }

  double get monthlyBudget => _d('monthlyBudget', 0.0);
  set monthlyBudget(double v) {
    _p.setDouble('monthlyBudget', v);
    notifyListeners();
  }

  String get defaultTransactionType => _s('defaultTransactionType', 'expense');
  set defaultTransactionType(String v) {
    _p.setString('defaultTransactionType', v);
    notifyListeners();
  }

  bool get hapticsEnabled => _b('hapticsEnabled', true);
  set hapticsEnabled(bool v) {
    _p.setBool('hapticsEnabled', v);
    notifyListeners();
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
