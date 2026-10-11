import 'package:expnd/screens/get_started_screen.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/theme/expnd_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBox implements Box {
  final Map<dynamic, dynamic> data = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('guide opens Plan and returns with the checklist intact', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.create();
    final store = AppStore(_FakeBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          theme: buildExpndTheme(Brightness.dark),
          home: const GetStartedScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('MAKE IT YOURS'), findsOneWidget);
    expect(find.text('0 / 4'), findsOneWidget);

    await tester.tap(find.text('Set a monthly budget'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close plan'));
    await tester.pumpAndSettle();
    expect(find.text('MAKE IT YOURS'), findsOneWidget);
  });
}
