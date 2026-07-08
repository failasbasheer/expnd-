// Drives the real app on a device/simulator to the point where adding an
// expense pushes a category over its monthly budget, then screenshots the
// resulting over-budget toast. Run with:
//   flutter test integration_test/over_budget_toast_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/screens/home_shell.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/theme/sf_icons.dart';
import 'package:expnd/widgets/neopop.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('over-budget toast after adding an expense', (tester) async {
    // ── Seed a clean, already-set-up app with a Food budget near its limit ──
    SharedPreferences.setMockInitialValues({
      'hasCompletedAccountSetup': true,
      'currencyCode': 'INR',
      'defaultTransactionType': 'expense',
    });
    final settings = await SettingsStore.create();

    await Hive.initFlutter();
    await Hive.deleteBoxFromDisk('onyx'); // start empty every run
    final box = await Hive.openBox('onyx');
    final store = AppStore(box);

    // ₹8,000 Food budget with ₹7,500 already spent this month.
    store.setBudget(TransactionCategory.food, 8000);
    store.addTransaction(Transaction(
      note: 'Groceries run',
      amount: 7500,
      category: TransactionCategory.food,
      type: TransactionType.expense,
      date: DateTime.now(),
    ));

    // ── Launch the real HomeShell (skips AppRoot's native widget bridge, which
    // needs an App Group that isn't configured under `flutter test`) ─────────
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    debugPrint('[toast-test] plus icons found: '
        '${find.byIcon(sfIcon('plus')).evaluate().length}');
    // Open the add-transaction screen from the tab bar's plus button.
    await tester.tap(find.byIcon(sfIcon('plus')).first);
    await tester.pumpAndSettle();
    debugPrint('[toast-test] on add screen: '
        '${find.text('ADD TRANSACTION').evaluate().isNotEmpty}, '
        'Food chips: ${find.text('Food').evaluate().length}, '
        'TextFields: ${find.byType(TextField).evaluate().length}');

    // Pick the Food category and enter an amount that tips it over budget.
    await tester.tap(find.text('Food').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '1200');
    await tester.pump(const Duration(milliseconds: 300));

    // The submit button lives at the bottom of a lazy ListView, so scroll it
    // into view before tapping (target the button widget, not the identically
    // labelled header).
    final submit = find.widgetWithText(NeoPopButton, 'ADD TRANSACTION');
    await tester.scrollUntilVisible(submit, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    debugPrint('[toast-test] submit buttons found: ${submit.evaluate().length}');

    // Save. Do NOT pumpAndSettle here — the toast auto-dismisses after 3.5s,
    // and settling would advance past that timer and hide it. Pump fixed
    // frames to close the add screen and let the toast slide in instead.
    await tester.tap(submit);
    await tester.pump(); // start the pop
    await tester.pump(const Duration(milliseconds: 400)); // route pops out
    await tester.pump(const Duration(milliseconds: 500)); // toast slides in
    debugPrint('[toast-test] transactions now: ${store.transactions.length}; '
        'toast text present: '
        '${find.textContaining('Over Food Budget').evaluate().isNotEmpty}');

    // Capture whatever is on screen for inspection.
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('over_budget_toast');

    // The over-budget toast should now be on screen.
    expect(find.textContaining('Over Food Budget'), findsOneWidget);
  });
}
