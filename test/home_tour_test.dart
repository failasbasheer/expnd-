import 'package:expnd/models/models.dart';
import 'package:expnd/screens/home_shell.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/theme/expnd_theme.dart';
import 'package:expnd/widgets/home_tour_overlay.dart';
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
  testWidgets('first-run tour spotlights key screens and saves completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'getStartedEligible': true,
      'hasCompletedAccountSetup': true,
    });
    final settings = await SettingsStore.create();
    final store = AppStore(_FakeBox());
    store.addAccount(
      Account(
        name: 'My Wallet',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 0,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
        ],
        child: MaterialApp(
          theme: buildExpndTheme(Brightness.dark),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeTourOverlay), findsOneWidget);
    for (final title in [
      'Your month at a glance',
      'Add money in or out',
      'Give the month a plan',
      'Keep amounts private',
      'Understand your patterns',
      'Manage your accounts',
      'Make EXPND yours',
    ]) {
      expect(find.text(title), findsOneWidget);
      await tester.tap(
        find.text(title == 'Make EXPND yours' ? 'Done' : 'Next'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    expect(find.byType(HomeTourOverlay), findsNothing);
    expect(settings.getStartedDismissed, isTrue);
  });
}
