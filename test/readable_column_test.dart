import 'package:expnd/theme/expnd_theme.dart';
import 'package:expnd/widgets/readable_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    theme: buildExpndTheme(Brightness.dark),
    builder: (context, child) => ReadableColumn(child: child!),
    home: Builder(
      builder: (context) =>
          Text('${MediaQuery.sizeOf(context).width.round()}'),
    ),
  ),
);

void main() {
  testWidgets('phone width passes straight through', (tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const Size(402, 874)));
    expect(find.text('402'), findsOneWidget);
  });

  testWidgets('wide screens get a centred phone-width column', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1032, 1376));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const Size(1032, 1376)));
    // Screens see the column as the whole screen.
    expect(find.text('${ReadableColumn.maxWidth.round()}'), findsOneWidget);
    // And sit centred, not pinned to the left edge.
    final left = (1032 - ReadableColumn.maxWidth) / 2;
    expect(tester.getTopLeft(find.byType(Text)).dx, greaterThanOrEqualTo(left));
  });
}
