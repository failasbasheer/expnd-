// End-to-end check of the quick-capture handoff on a real device/simulator.
//
// The unit tests cover the store's half (dedupe, filing, isolation from
// balances) with a fake box. What they can't reach is the part that only
// exists on-device: HomeWidget actually writing to and reading from the iOS
// App Group. This drives that real channel — seed the queue the way the widget
// extension does, drain it, and check the UI that results.
//
// Run with:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/capture_flow_test.dart \
//     -d <device-id>
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/screens/capture_inbox_view.dart';
import 'package:expnd/screens/home_shell.dart';
import 'package:expnd/services/capture_inbox.dart';
import 'package:expnd/services/widget_bridge.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';

late final IntegrationTestWidgetsFlutterBinding binding;

late SettingsStore _settings;
late AppStore _store;

/// Writes the queue exactly as ios/ExpndWidget/CaptureQueue.swift does, so the
/// drain is reading the real shape rather than one this test invented.
Future<void> _seedQueue(List<Map<String, Object>> entries) async {
  await HomeWidget.saveWidgetData<String>(
    CaptureInbox.queueKey,
    jsonEncode(entries),
  );
}

Future<String> _readQueue() async =>
    await HomeWidget.getWidgetData<String>(CaptureInbox.queueKey) ?? '';

Map<String, Object> _entry(
  String id,
  double amount, {
  String note = '',
  String source = 'widget',
}) => {
  'id': id,
  'amount': amount,
  'note': note,
  'at': DateTime.now().millisecondsSinceEpoch,
  'source': source,
};

Widget _wrap(Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: _settings),
    ChangeNotifierProvider.value(value: _store),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    darkTheme: ThemeData(brightness: Brightness.dark),
    themeMode: ThemeMode.dark,
    home: home,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 120));
  } catch (_) {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.initFlutter();
    await Hive.deleteBoxFromDisk('capture_flow');
    final box = await Hive.openBox('capture_flow');
    _settings = await SettingsStore.create();
    _store = AppStore(box);
    _store.addAccount(
      Account(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'USD',
        balance: 500,
      ),
    );
    await HomeWidget.setAppGroupId(WidgetBridge.appGroupId);
    // Leave no queue behind from a previous run.
    await HomeWidget.saveWidgetData<String>(CaptureInbox.queueKey, '');
  });

  testWidgets('the App Group round-trips a capture into the inbox', (
    tester,
  ) async {
    await _seedQueue([
      _entry('cap-int-1', 500),
      _entry('cap-int-2', 120.5, note: 'Coffee', source: 'siri'),
    ]);

    // Proves the write actually reached the shared container, not just a
    // Dart-side cache — otherwise a no-op drain would look like a pass.
    expect(await _readQueue(), contains('cap-int-1'));

    final taken = await CaptureInbox.drain(_store);

    expect(taken, 2);
    expect(_store.pendingCaptures.length, 2);
    expect(_store.pendingCaptures.first.amount, 500);
    expect(_store.pendingCaptures.last.note, 'Coffee');
    // Captured, but deliberately not money yet.
    expect(_store.transactions, isEmpty);
    expect(_store.balanceFor(_store.accounts.first), 500);
    // Acknowledged, so the next launch doesn't see them again.
    expect(await _readQueue(), isEmpty);
  }, skip: !Platform.isIOS);

  testWidgets('a capture appended mid-drain is not swallowed', (tester) async {
    await _seedQueue([_entry('cap-int-1', 500)]);
    await CaptureInbox.drain(_store);

    // The widget tapped again after that drain read the queue. The entry it
    // appended must survive the acknowledgement that follows.
    await _seedQueue([_entry('cap-int-1', 500), _entry('cap-int-2', 75)]);
    final taken = await CaptureInbox.drain(_store);

    // Only the new one is new — the replayed id is skipped, not duplicated.
    expect(taken, 2);
    expect(_store.pendingCaptures.length, 2);
    expect(
      _store.pendingCaptures.map((c) => c.id),
      containsAll(['cap-int-1', 'cap-int-2']),
    );
  }, skip: !Platform.isIOS);

  testWidgets('the dashboard surfaces them and the inbox lists them', (
    tester,
  ) async {
    await _seedQueue([
      _entry('cap-int-1', 500),
      _entry('cap-int-2', 120.5, note: 'Coffee', source: 'siri'),
    ]);
    await CaptureInbox.drain(_store);

    await tester.pumpWidget(_wrap(const HomeShell()));
    await _settle(tester);

    // The banner sits at the bottom of the dashboard, so scroll to it.
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -1200));
      await _settle(tester);
    }
    expect(find.textContaining('to file'), findsOneWidget);
    await binding.takeScreenshot('40_capture_banner_dark');

    await tester.tap(find.textContaining('to file'));
    await _settle(tester);

    expect(find.byType(CaptureInboxScreen), findsOneWidget);
    expect(find.text('WIDGET'), findsOneWidget);
    expect(find.text('SIRI'), findsOneWidget);
    expect(find.text('Coffee · just now'), findsOneWidget);
    await binding.takeScreenshot('41_capture_inbox_dark');
  }, skip: !Platform.isIOS);

  testWidgets(
    'filing one moves it into the ledger and clears the inbox',
    (tester) async {
      await _seedQueue([_entry('cap-int-1', 500)]);
      await CaptureInbox.drain(_store);

      await tester.pumpWidget(_wrap(const CaptureInboxScreen()));
      await _settle(tester);

      await tester.tap(find.text('FILE'));
      await _settle(tester);

      // Pre-filled with what the capture knew, waiting on what it didn't.
      expect(find.text('500.00'), findsOneWidget);
      await binding.takeScreenshot('42_capture_filing_dark');
    },
    skip: !Platform.isIOS,
  );
}
