import 'package:flutter/material.dart';

/// Parse a hex string like "F7C948" or "#F7C948" into a [Color].
Color hexColor(String hex) {
  final h = hex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  final n = int.parse(h.length >= 6 ? h.substring(0, 6) : h, radix: 16);
  return Color(0xFF000000 | n);
}

/// The EXPND / NeoPOP palette. Adaptive colours resolve from the current
/// [Brightness]; brand colours (gold/red/green/ink) are fixed.
class ExpndColors {
  final Brightness brightness;
  const ExpndColors(this.brightness);

  bool get _dark => brightness == Brightness.dark;

  // Adaptive surfaces. Dark values map to the neoPOP "pop black" scale:
  // 500 #0D0D0D · 400 #121212 · 300 #161616 · 200 #3D3D3D · 100 #8A8A8A.
  Color get bg => _dark ? hexColor('0D0D0D') : hexColor('F4F4EF');
  Color get surface => _dark ? hexColor('121212') : hexColor('FFFFFF');
  Color get card => _dark ? hexColor('161616') : hexColor('F0F0EA');
  Color get border => _dark ? hexColor('3D3D3D') : hexColor('D4D4CC');
  Color get edge => _dark ? hexColor('000000') : hexColor('AEAEA0');
  Color get muted => _dark ? hexColor('8A8A8A') : hexColor('666660');
  Color get dimmed => _dark ? hexColor('5A5A5A') : hexColor('AAAAAA');

  /// SwiftUI `.primary` label colour.
  Color get text => _dark ? Colors.white : hexColor('0D0D0D');

  /// Gold used as a FOREGROUND — text, icons, progress indicators, selected
  /// states, thin accents that sit directly on an adaptive surface. Bright
  /// [gold] pops on ink but is nearly invisible on white (its luminance is
  /// close to white's), so light mode resolves to a darker amber-gold that
  /// clears WCAG-AA (~4.5:1 on white). Use the fixed [gold] only for FILLS
  /// (a gold block with ink content on top); use this everywhere gold is the
  /// mark itself.
  Color get accent => _dark ? gold : hexColor('9A6F00');
  Color get accentDepth => _dark ? goldDark : hexColor('6E4F00');

  // Fixed brand colours — aligned to the CRED neoPOP UI kit tokens.
  // "win yellow" 500/600 replace the softer gold for an authentic pop.
  static final gold = hexColor('FFEB34'); // win yellow / 500
  static final goldDark = hexColor('CDB900'); // win yellow / 600 (depth block)
  static final green = hexColor('06C270');
  static final greenDk = hexColor('039554');
  static final red = hexColor('EE4D37');
  static final redDark = hexColor('B03A28');
  static final ink = hexColor('0D0D0D'); // pop black / 500
}

/// Shared layout metrics.
class ExpndSpacing {
  /// Bottom padding for a scroll view that has nothing overhanging it — a
  /// pushed route, a sheet. Just enough to clear the home indicator and stop
  /// the last row from sitting flush against the screen edge. Padding beyond
  /// this is dead space that reads as the list having ended early.
  static const double scrollBottom = 40;

  /// Bottom padding for a tab screen's scroll view.
  ///
  /// The tab bar is a translucent glass plate over an `extendBody: true`
  /// [Scaffold], so the body is laid out *behind* it and content genuinely
  /// scrolls underneath. Flutter reports the bar's full height (bar + home
  /// indicator) as `MediaQuery.padding.bottom` for that body, so reserving it
  /// here lands the last row just above the glass at rest while still letting
  /// mid-scroll content pass under and tint it.
  static double scrollBottomUnderTabBar(BuildContext context) =>
      MediaQuery.of(context).padding.bottom + scrollBottom;
}

/// neoPOP corner-radius tokens. The design language is deliberately hard-edged:
/// buttons are near-sharp, cards keep only a hint of a radius, tags are square.
class ExpndRadius {
  static const double button = 2;
  static const double card = 3;
  static const double tag = 0;
  static const double sheet = 4;
}

/// Central type scale (system/default font). neoPOP leans on heavy weights,
/// tight-to-wide tracking, and UPPERCASE labels.
class ExpndType {
  /// Screen / section titles — heavy and slightly condensed tracking.
  static TextStyle title(Color c) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: c,
      );

  /// Large numeric readouts (balances, amounts).
  static TextStyle amount(Color c) => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: c,
      );

  /// Body / row text.
  static TextStyle body(Color c) =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c);

  /// The signature neoPOP label: UPPERCASE, black weight, wide tracking.
  static TextStyle label(Color c) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: c,
      );
}

extension ExpndContext on BuildContext {
  ExpndColors get oc => ExpndColors(Theme.of(this).brightness);
}
