import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expnd/theme/expnd_theme.dart';
import 'package:expnd/widgets/app_header.dart';
import 'package:expnd/widgets/glass_header.dart';

double _relativeLuminance(Color color) => color.computeLuminance();

double _contrast(Color first, Color second) {
  final a = _relativeLuminance(first);
  final b = _relativeLuminance(second);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _headerHarness({required bool highContrast}) => MaterialApp(
  theme: buildExpndTheme(Brightness.dark),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast),
      child: Scaffold(
        body: GlassHeaderLayout(
          header: const ExpndHeader(title: 'History'),
          body: (context, topInset) => ListView(
            children: [
              SizedBox(height: topInset),
              for (var i = 0; i < 30; i++) const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('frosted chrome keeps muted labels readable over extreme content', () {
    for (final brightness in Brightness.values) {
      final palette = ExpndColors(brightness);
      final worstUnderlay = brightness == Brightness.dark
          ? Colors.white
          : Colors.black;
      final plate = Color.alphaBlend(
        palette.bg.withValues(alpha: ExpndGlass.tint(brightness)),
        worstUnderlay,
      );
      expect(
        _contrast(palette.muted, plate),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness muted labels over passing content',
      );
    }
  });

  testWidgets('high contrast uses a solid header without backdrop blur', (
    tester,
  ) async {
    await tester.pumpWidget(_headerHarness(highContrast: true));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.enabled, isFalse);
  });

  testWidgets('normal contrast blurs only after content scrolls under header', (
    tester,
  ) async {
    await tester.pumpWidget(_headerHarness(highContrast: false));
    await tester.pump();
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isTrue,
    );
  });
}
