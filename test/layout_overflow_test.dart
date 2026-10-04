// Every screen, laid out at the narrowest phone we support and again with the
// system text size turned up, must not overflow. A "RIGHT OVERFLOWED BY 2.0
// PIXELS" stripe is a shipping bug — it only ever shows up on someone else's
// device — so the guard lives here rather than in a manual pass.
//
// The test font draws every glyph as a full-em box, so labels measure roughly
// 40% wider here than they do on a device. That is deliberate headroom: a
// layout that survives this font survives a long account name, a five-digit
// balance, and a user who bumped their text size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/theme/expnd_theme.dart';
import 'package:expnd/screens/capture_inbox_view.dart';
import 'package:expnd/screens/whats_new.dart';
import 'package:expnd/screens/transaction_detail.dart';
import 'package:expnd/screens/emi.dart';
import 'package:expnd/screens/account_setup.dart';
import 'package:expnd/screens/add_transaction.dart';
import 'package:expnd/screens/analytics_view.dart';
import 'package:expnd/screens/history_view.dart';
import 'package:expnd/screens/home_shell.dart';
import 'package:expnd/screens/plan_view.dart';
import 'package:expnd/screens/quick_capture.dart';
import 'package:expnd/screens/settings_view.dart';
import 'package:expnd/screens/upcoming_view.dart';
import 'package:expnd/screens/wallet_view.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';

class _FakeBox implements Box {
  final Map<dynamic, dynamic> _m = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _m[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _m[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A dataset with the shapes that actually break layouts: a long account name,
/// a six-figure balance, a credit card with a limit, every transaction type.
Future<AppStore> _seeded() async {
  final store = AppStore(_FakeBox());
  final checking = Account(
    name: 'HDFC Checking Account',
    type: AccountType.bank,
    currencyCode: 'USD',
    balance: 64000,
  );
  final savings = Account(
    name: 'Emergency Fund',
    type: AccountType.savings,
    currencyCode: 'USD',
    balance: 112000,
  );
  final card = Account(
    name: 'ICICI Amazon Pay',
    type: AccountType.credit,
    currencyCode: 'USD',
    balance: 18400,
    creditLimit: 150000,
  );
  for (final a in [checking, savings, card]) {
    store.addAccount(a);
  }

  const cats = [
    TransactionCategory.groceries,
    TransactionCategory.food,
    TransactionCategory.transport,
    TransactionCategory.entertainment,
    TransactionCategory.rent,
    TransactionCategory.utilities,
  ];
  for (var i = 0; i < 24; i++) {
    store.addTransaction(
      Transaction(
        note: 'Weekly grocery run at the big store $i',
        amount: 120.0 * (i + 1),
        category: cats[i % cats.length],
        type: TransactionType.expense,
        date: DateTime(2026, 7, 22).subtract(Duration(days: i)),
        accountId: checking.id,
      ),
    );
  }
  store.addTransaction(
    Transaction(
      note: 'Salary',
      amount: 285000,
      category: TransactionCategory.salary,
      type: TransactionType.income,
      date: DateTime(2026, 7, 1),
      accountId: checking.id,
    ),
  );
  final rent = Transaction(
    note: 'Apartment rent',
    amount: 24000,
    category: TransactionCategory.rent,
    type: TransactionType.expense,
    date: DateTime(2026, 8, 1),
    accountId: checking.id,
    isRecurring: true,
    recurrenceRule: RecurrenceRule.monthly,
  );
  rent.nextDueDate = DateTime(2026, 8, 1);
  store.addTransaction(rent);
  store.addGoal(
    SavingsGoal(
      name: 'Emergency savings fund',
      targetAmount: 10000,
      allocatedAmount: 2500,
      iconName: 'shield.fill',
      colorHex: '057A55',
    ),
  );
  store.addDebt(
    Debt(
      person: 'A long contact name',
      amount: 1200,
      theyOweMe: true,
      date: DateTime.now(),
      accountId: checking.id,
    ),
  );
  store.addPendingCaptures([
    PendingCapture(
      id: 'layout-capture',
      amount: 120.50,
      note: 'Weekly grocery shopping',
      source: 'quick',
    ),
  ]);
  return store;
}

/// One overflow, keyed by where it comes from so repeats across viewports
/// collapse into a single line.
class _Overflow {
  final String widget;
  final String location;
  final double pixels;
  final String edge;
  _Overflow(this.widget, this.location, this.pixels, this.edge);

  String get key => '$location|$edge';
  @override
  String toString() =>
      '$location  ($widget overflowed $edge by ${pixels.toStringAsFixed(1)}px)';
}

final _overflowRe = RegExp(
  r'A (\w+) overflowed by ([\d.]+) pixels on the (\w+)',
);
final _locationRe = RegExp(
  r'The relevant error-causing widget was:\s*\n\s*(\S+)',
);
final _fileRe = RegExp(r'(lib/[\w/]+\.dart:\d+:\d+)');

_Overflow? _parse(FlutterErrorDetails d) {
  final text = d.toString();
  final m = _overflowRe.firstMatch(text);
  if (m == null) return null;
  final file = _fileRe.firstMatch(
    text.replaceAll('file:///', '').replaceAll(RegExp(r'.*?(?=lib/)'), ''),
  );
  return _Overflow(
    _locationRe.firstMatch(text)?.group(1) ?? m.group(1)!,
    file?.group(1) ?? '<unknown location>',
    double.parse(m.group(2)!),
    m.group(3)!,
  );
}

/// Viewports we promise to look right on: the narrowest phone still on iOS 17
/// (iPhone SE, 320pt), the common 375/390 sizes, and each of those with the
/// system text size raised one notch.
const _widths = <double>[320, 375, 430];
const _textScales = <double>[1.0, 1.5];

Future<void> _audit(
  WidgetTester tester,
  String screen,
  Widget Function() build, {
  Future<void> Function(WidgetTester)? after,
}) async {
  final found = <String, _Overflow>{};
  final store = await _seeded();
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.create();
  settings.monthlyBudget = 3000;
  settings.userName = 'Failas';
  settings.hasCompletedAccountSetup = true;

  final prior = FlutterError.onError;
  FlutterError.onError = (details) {
    final o = _parse(details);
    if (o == null) {
      prior?.call(details);
      return;
    }
    found.putIfAbsent(o.key, () => o);
  };
  addTearDown(() => FlutterError.onError = prior);
  addTearDown(tester.view.reset);

  for (final brightness in Brightness.values) {
    for (final width in _widths) {
      for (final scale in _textScales) {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: settings),
                ChangeNotifierProvider.value(value: store),
              ],
              child: MaterialApp(
                theme: buildExpndTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                debugShowCheckedModeBanner: false,
                // Screens that normally live inside the shell's Scaffold are
                // pumped bare here, so supply the Material ancestor their text
                // fields need. Transparent: it must not alter layout.
                home: Material(type: MaterialType.transparency, child: build()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (after != null) await after(tester);
        await tester.pumpAndSettle();
      }
    }
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  expect(
    found.values,
    isEmpty,
    reason: '$screen overflowed:\n  ${found.values.join('\n  ')}',
  );
}

void main() {
  for (final sheet in ['transaction detail', 'add loan']) {
    testWidgets(
      sheet,
      (t) => _audit(
        t,
        sheet,
        () => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                final store = context.read<AppStore>();
                if (sheet == 'transaction detail') {
                  showTransactionDetail(context, store.transactions.first);
                } else {
                  showAddEmi(context, accountId: store.accounts.last.id);
                }
              },
              child: const Text('Open sheet'),
            ),
          ),
        ),
        after: (tester) async {
          await tester.tap(find.text('Open sheet'));
          await tester.pumpAndSettle();
        },
      ),
    );
  }
  testWidgets(
    'capture inbox',
    (t) => _audit(t, 'capture inbox', () => const CaptureInboxScreen()),
  );
  testWidgets(
    'what is new',
    (t) => _audit(t, 'what is new', () => const WhatsNewScreen()),
  );
  testWidgets(
    'home shell',
    (t) => _audit(t, 'home shell', () => const HomeShell()),
  );

  testWidgets(
    'add transaction',
    (t) => _audit(t, 'add transaction', () => const AddTransactionScreen()),
  );

  testWidgets(
    'expanded entry options',
    (t) => _audit(
      t,
      'expanded entry options',
      () => const AddTransactionScreen(),
      after: (tester) async {
        if (find.text('Repeat Transaction').evaluate().isNotEmpty) return;
        await tester.scrollUntilVisible(
          find.text('More options'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('More options')),
          alignment: 0.3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('More options'));
        await tester.pumpAndSettle();
        expect(find.text('Split across categories'), findsOneWidget);
      },
    ),
  );

  for (final task in ['Savings goals', 'Debts & loans']) {
    testWidgets(
      'plan: $task',
      (t) => _audit(
        t,
        task,
        () => const PlanView(),
        after: (tester) async {
          await tester.tap(find.widgetWithText(ChoiceChip, task));
        },
      ),
    );
  }

  for (final group in [
    'General',
    'Reminders & alerts',
    'Categories & tags',
    'Appearance',
    'Data',
  ]) {
    testWidgets(
      'settings: $group',
      (t) => _audit(
        t,
        group,
        () => const SettingsView(),
        after: (tester) async {
          await tester.scrollUntilVisible(
            find.text(group),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          final tile = find
              .ancestor(
                of: find.text(group),
                matching: find.byType(ExpansionTile),
              )
              .first;
          await Scrollable.ensureVisible(tester.element(tile), alignment: 0.3);
          await tester.pumpAndSettle();
          await tester.tap(find.text(group));
        },
      ),
    );
  }

  testWidgets(
    'analytics',
    (t) => _audit(t, 'analytics', () => const AnalyticsView()),
  );

  testWidgets(
    'history',
    (t) => _audit(t, 'history', () => const HistoryView()),
  );

  // The category/account/tag rows are collapsed by default, so the plain
  // history audit above never lays them out. Expand them and audit again, or
  // the widest chips in the app go unguarded.
  testWidgets(
    'history with filters expanded',
    (t) => _audit(
      t,
      'history with filters expanded',
      () => const HistoryView(),
      after: (tester) async {
        final toggle = find.bySemanticsLabel(
          'Show category, account and tag filters',
        );
        if (toggle.evaluate().isEmpty) return;
        await tester.tap(toggle.first);
        await tester.pumpAndSettle();
      },
    ),
  );

  testWidgets('wallet', (t) => _audit(t, 'wallet', () => const WalletView()));

  testWidgets('plan', (t) => _audit(t, 'plan', () => const PlanView()));

  testWidgets(
    'settings',
    (t) => _audit(t, 'settings', () => const SettingsView()),
  );

  testWidgets(
    'upcoming',
    (t) => _audit(t, 'upcoming', () => const UpcomingView()),
  );

  testWidgets(
    'account onboarding',
    (t) => _audit(t, 'account onboarding', () => const AccountOnboarding()),
  );

  testWidgets(
    'add account',
    (t) => _audit(t, 'add account', () => const AddAccountSheet()),
  );

  // Four category chips across is the tightest grid in the app, and the labels
  // are real category names, so this is the screen most likely to break at a
  // large text scale on a small phone.
  testWidgets(
    'quick capture',
    (t) => _audit(t, 'quick capture', () => const QuickCaptureScreen()),
  );
}
