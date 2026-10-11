// Tests for the eye button's privacy mask. The mask is the whole feature —
// if a formatter leaks a figure while it's on, the button is a lie — so each
// formatter and the widget-bridge carve-out get direct coverage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/theme/currencies.dart';
import 'package:expnd/widgets/privacy_eye.dart';

void main() {
  tearDown(() => AmountPrivacy.hidden = false);

  group('privacy mask off', () {
    test('formats the real figure', () {
      expect(formatCurrency(1250.5, 'USD'), '\$1,250.50');
      expect(formatAmount(1250.5), '1,250.50');
    });
  });

  group('privacy mask on', () {
    setUp(() => AmountPrivacy.hidden = true);

    test('masks the figure but keeps the currency symbol', () {
      expect(formatCurrency(1250.5, 'USD'), '\$${AmountPrivacy.mask}');
      expect(formatCurrency(1250.5, 'INR'), '₹${AmountPrivacy.mask}');
    });

    test('masks bare amounts (savings goals, category budgets)', () {
      expect(formatAmount(1250.5), AmountPrivacy.mask);
    });

    test('masks percentages too (budget used, month-on-month change)', () {
      expect(formatPercent(63), '●●%');
      expect(formatPercent(63), formatPercent(187));
      AmountPrivacy.hidden = false;
      expect(formatPercent(63), '63%');
    });

    test('leaks nothing about magnitude', () {
      expect(formatCurrency(9999999.99, 'USD'), formatCurrency(0.01, 'USD'));
      expect(formatAmount(9999999.99), formatAmount(0.01));
    });

    test('honours per-currency decimals only when revealed', () {
      // JPY has no minor units, KWD has three. Masked, both collapse to the
      // same fixed-width mask (the symbol is kept on purpose); revealed, each
      // gets its own ISO 4217 precision back.
      expect(formatCurrency(1000, 'JPY'), '¥${AmountPrivacy.mask}');
      expect(formatCurrency(1000, 'KWD'), 'KWD${AmountPrivacy.mask}');
      AmountPrivacy.hidden = false;
      expect(formatCurrency(1000, 'JPY'), '¥1,000');
      expect(formatCurrency(1000, 'KWD'), 'KWD1,000.000');
    });

    test('the home-screen widget bridge opts out and stays readable', () {
      expect(formatCurrency(1250.5, 'USD', maskable: false), '\$1,250.50');
    });
  });

  group('PrivacyEyeButton', () {
    testWidgets('tapping it masks and reveals amounts on screen', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.create();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            home: Consumer<SettingsStore>(
              builder: (_, s, _) => Scaffold(
                body: Column(
                  children: [
                    Text(formatCurrency(1250.5, s.currencyCode)),
                    const PrivacyEyeButton(color: Colors.black),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('\$1,250.50'), findsOneWidget);

      await tester.tap(find.byType(PrivacyEyeButton));
      await tester.pumpAndSettle();
      expect(find.text('\$${AmountPrivacy.mask}'), findsOneWidget);
      expect(find.text('\$1,250.50'), findsNothing);
      expect(settings.amountsHidden, isTrue);

      await tester.tap(find.byType(PrivacyEyeButton));
      await tester.pumpAndSettle();
      expect(find.text('\$1,250.50'), findsOneWidget);
      expect(settings.amountsHidden, isFalse);
    });

    testWidgets('a hidden session survives a relaunch', (tester) async {
      SharedPreferences.setMockInitialValues({'amountsHidden': true});
      // Constructing the store is what a cold boot does; the formatters must
      // already be masking before the first frame paints.
      await SettingsStore.create();
      expect(AmountPrivacy.hidden, isTrue);
      expect(formatCurrency(1250.5, 'USD'), '\$${AmountPrivacy.mask}');
    });
  });
}
