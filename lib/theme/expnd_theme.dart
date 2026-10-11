import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

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

  // Neutral surfaces keep charts and account colours visually distinct.
  Color get bg => _dark ? hexColor('14191F') : hexColor('F5F6F8');
  Color get surface => _dark ? hexColor('1C222A') : hexColor('FFFFFF');
  Color get card => _dark ? hexColor('232B35') : hexColor('F0F2F5');
  Color get border => _dark ? hexColor('35404C') : hexColor('DCE1E7');
  Color get edge => _dark ? hexColor('000000') : hexColor('AEAEA0');
  Color get muted => _dark ? hexColor('ACB7C4') : hexColor('576474');
  Color get dimmed => _dark ? hexColor('97A4B3') : hexColor('647080');

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
  Color get positive => _dark ? green : hexColor('087A4D');
  Color get negative => _dark ? hexColor('FF806C') : hexColor('BB3526');

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

/// Frosted "glass" chrome (iOS 26 style) for surfaces that content scrolls
/// under — shared headers and the tab bar. Set [enabled] to false to restore
/// the solid surfaces.
class ExpndGlass {
  static const bool enabled = true;

  /// Keep geometry unchanged while offering a solid, predictable backdrop for
  /// people who request increased contrast in their system settings.
  static bool translucent(BuildContext context) =>
      enabled && !MediaQuery.highContrastOf(context);

  /// Backdrop blur radius.
  static const double blur = 24;

  /// Keep muted labels readable even when a bright (dark theme) or dark
  /// (light theme) card passes directly beneath the frosted chrome.
  static double tint(Brightness b) => b == Brightness.dark ? 0.82 : 0.93;
}

/// EXPND keeps a crisp silhouette, while content surfaces have enough radius
/// to feel finished and touch-friendly. Hard neoPOP geometry is reserved for
/// the yellow hero and primary actions rather than repeated on every panel.
class ExpndRadius {
  static const double button = 8;
  static const double card = 12;
  static const double tag = 4;
  static const double sheet = 20;
}

/// Central type scale. Large figures carry the character; supporting text stays
/// calm and readable instead of competing through tracking and all-caps.
class ExpndType {
  /// Screen / section titles — heavy and slightly condensed tracking.
  static TextStyle title(Color c) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: c,
  );

  /// Large numeric readouts (balances, amounts).
  static TextStyle amount(Color c) => TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: c,
  );

  /// Body / row text.
  static TextStyle body(Color c) => TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: c,
  );

  /// Compact supporting label. Callers choose casing based on meaning.
  static TextStyle label(Color c) => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.15,
    color: c,
  );
}

extension ExpndContext on BuildContext {
  ExpndColors get oc => ExpndColors(Theme.of(this).brightness);
}

/// Used by the app and device review tour, so screenshots reflect shipped UI.
ThemeData buildExpndTheme(Brightness brightness) {
  final oc = ExpndColors(brightness);
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(ExpndRadius.button),
    borderSide: BorderSide(color: oc.border),
  );
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: oc.bg,
    useMaterial3: true,
    fontFamily: 'ExpndSans',
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: ExpndColors.gold,
          brightness: brightness,
        ).copyWith(
          primary: oc.accent,
          onPrimary: brightness == Brightness.dark
              ? ExpndColors.ink
              : Colors.white,
          surface: oc.surface,
          onSurface: oc.text,
          onSurfaceVariant: oc.muted,
          outline: oc.border,
        ),
    dividerColor: oc.border,
    appBarTheme: AppBarTheme(
      backgroundColor: oc.bg,
      foregroundColor: oc.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'ExpndSans',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: oc.text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      fillColor: oc.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      hintStyle: TextStyle(color: oc.dimmed),
      border: outline,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: oc.surface,
      selectedColor: ExpndColors.gold,
      checkmarkColor: ExpndColors.ink,
      side: BorderSide(color: oc.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(
        color: oc.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: ExpndColors.ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: oc.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ExpndRadius.sheet),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: oc.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ExpndRadius.sheet),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
