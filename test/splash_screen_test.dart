import 'package:expnd/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('splash is the still launch mark, with no animation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ExpndMarkPainter,
      ),
      findsOneWidget,
    );
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.bySemanticsLabel('EXPND is loading'), findsOneWidget);
    expect(find.text('by Trylas'), findsOneWidget);
  });

  testWidgets('mark sits in the 200pt box the native launch screen uses', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    final box = tester.getSize(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ExpndMarkPainter,
      ),
    );
    expect(box, const Size(200, 200));
  });
}
