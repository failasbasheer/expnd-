import 'package:expnd/models/models.dart';
import 'package:expnd/screens/subscriptions_view.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Box implements Box {
  final Map<dynamic, dynamic> _values = {};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'subscriptions fit narrow screen and large text in $brightness',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final settings = await SettingsStore.create();
        final store = AppStore(_Box());
        store.addTransaction(
          Transaction(
            note: 'A streaming subscription with a long service name',
            amount: 12345.67,
            category: TransactionCategory.other,
            type: TransactionType.expense,
            date: DateTime.now(),
            isRecurring: true,
            tags: ['subscription'],
            nextDueDate: DateTime.now().add(const Duration(days: 30)),
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider.value(value: store),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const SubscriptionManagerView(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byTooltip('Manage subscription'),
          150,
        );
        await tester.tap(find.byTooltip('Manage subscription'));
        await tester.pumpAndSettle();
        expect(find.text('Set trial end'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
