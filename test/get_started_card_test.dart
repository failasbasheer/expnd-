import 'package:expnd/theme/expnd_theme.dart';
import 'package:expnd/widgets/get_started_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'only unfinished steps navigate and progress follows real state',
    (tester) async {
      var walletTaps = 0;
      var expenseTaps = 0;
      var budgetTaps = 0;
      var reminderTaps = 0;
      var dismissals = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildExpndTheme(Brightness.dark),
          home: Scaffold(
            body: GetStartedCard(
              hasWallet: true,
              hasExpense: false,
              hasBudget: false,
              hasReminder: false,
              onWallet: () => walletTaps++,
              onExpense: () => expenseTaps++,
              onBudget: () => budgetTaps++,
              onReminder: () => reminderTaps++,
              onDismiss: () => dismissals++,
            ),
          ),
        ),
      );

      expect(find.text('1 / 4'), findsOneWidget);
      await tester.tap(find.text('Set up your wallet'));
      await tester.tap(find.text('Add your first expense'));
      await tester.tap(find.text('Set a monthly budget'));
      await tester.tap(find.text('Turn on a daily reminder'));
      await tester.tap(find.byTooltip('Dismiss get started'));
      expect(walletTaps, 0);
      expect(expenseTaps, 1);
      expect(budgetTaps, 1);
      expect(reminderTaps, 1);
      expect(dismissals, 1);
    },
  );
}
