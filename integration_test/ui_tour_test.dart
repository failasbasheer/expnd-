// UI/UX screenshot tour. Seeds the rich dev dataset and captures every screen
// on a booted device/simulator so the layouts can be reviewed as a designer
// would see them. Run with:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/ui_tour_test.dart \
//     -d <device-id>
//
// PNGs land in screenshots/ (see test_driver/integration_test.dart onScreenshot).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/models/models.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/theme/expnd_theme.dart';

import 'package:expnd/screens/home_shell.dart';
import 'package:expnd/screens/history_view.dart';
import 'package:expnd/screens/analytics_view.dart';
import 'package:expnd/screens/wallet_view.dart';
import 'package:expnd/screens/plan_view.dart';
import 'package:expnd/screens/settings_view.dart';
import 'package:expnd/screens/upcoming_view.dart';
import 'package:expnd/screens/add_transaction.dart';
import 'package:expnd/screens/transaction_detail.dart';
import 'package:expnd/screens/emi.dart';
import 'package:expnd/screens/account_setup.dart';
import 'package:expnd/screens/whats_new.dart';
import 'package:expnd/screens/quick_capture.dart';
import 'package:expnd/screens/capture_inbox_view.dart';

late final IntegrationTestWidgetsFlutterBinding binding;

SettingsStore? _settings;
AppStore? _store;
bool _hiveReady = false;

Future<void> ensureBooted() async {
  if (_store != null) return;
  SharedPreferences.setMockInitialValues({});
  if (!_hiveReady) {
    await Hive.initFlutter();
    _hiveReady = true;
  }
  await Hive.deleteBoxFromDisk('ui_tour');
  final box = await Hive.openBox('ui_tour');
  final settings = await SettingsStore.create();
  final store = AppStore(box);
  _seed(store, settings);
  store.generateRecurring();
  store.takeRecurringNotice(); // clear so the toast doesn't cover the dashboard
  _settings = settings;
  _store = store;
}

/// Self-contained review dataset (the shipping app's temporary dev seeder was
/// removed). Rich enough to exercise every screen: four account types, two
/// months of history, recurring bills, EMIs, category budgets in each state,
/// savings goals across the progress range, debts, tags and a split.
void _seed(AppStore store, SettingsStore settings) {
  store.wipeAll();
  settings.currencyCode = 'USD';
  settings.userName = 'Failas';
  settings.monthlyBudget = 3000;
  settings.hasCompletedAccountSetup = true;

  final now = DateTime.now();
  DateTime days(int d) => now.add(Duration(days: d));

  final checking = Account(
    name: 'HDFC Checking',
    type: AccountType.bank,
    currencyCode: 'USD',
    balance: 6400,
  );
  final savings = Account(
    name: 'Emergency Fund',
    type: AccountType.savings,
    currencyCode: 'USD',
    balance: 11200,
  );
  final cash = Account(
    name: 'Cash',
    type: AccountType.cash,
    currencyCode: 'USD',
    balance: 320,
  );
  final card = Account(
    name: 'ICICI Amazon Pay',
    type: AccountType.credit,
    currencyCode: 'USD',
    balance: 1840,
    creditLimit: 15000,
    cardDigits: '4519280734',
  );
  for (final a in [checking, savings, cash, card]) {
    store.addAccount(a);
  }

  void recurring(
    String note,
    double amount,
    TransactionCategory cat,
    TransactionType type,
    RecurrenceRule rule,
    int last,
    int next,
    String accId,
  ) {
    final t = Transaction(
      note: note,
      amount: amount,
      category: cat,
      type: type,
      date: days(last),
      isRecurring: true,
      recurrenceRule: rule,
      accountId: accId,
    );
    t.nextDueDate = days(next);
    store.addTransaction(t);
  }

  recurring(
    'Rent',
    1200,
    TransactionCategory.rent,
    TransactionType.expense,
    RecurrenceRule.monthly,
    -26,
    4,
    checking.id,
  );
  recurring(
    'Salary',
    4200,
    TransactionCategory.salary,
    TransactionType.income,
    RecurrenceRule.monthly,
    -20,
    11,
    checking.id,
  );
  recurring(
    'Netflix',
    15.99,
    TransactionCategory.subscription,
    TransactionType.expense,
    RecurrenceRule.monthly,
    -19,
    11,
    card.id,
  );
  recurring(
    'Spotify',
    9.99,
    TransactionCategory.subscription,
    TransactionType.expense,
    RecurrenceRule.monthly,
    -24,
    6,
    card.id,
  );
  recurring(
    'Gym',
    22,
    TransactionCategory.medical,
    TransactionType.expense,
    RecurrenceRule.weekly,
    -6,
    1,
    checking.id,
  );
  recurring(
    'Car Insurance',
    148,
    TransactionCategory.insurance,
    TransactionType.expense,
    RecurrenceRule.monthly,
    -8,
    22,
    checking.id,
  );
  recurring(
    'Internet',
    59,
    TransactionCategory.utilities,
    TransactionType.expense,
    RecurrenceRule.monthly,
    -32,
    -2,
    checking.id,
  );

  store.addEmi(
    Emi(
      accountId: card.id,
      name: 'MacBook Pro',
      principal: 12000,
      annualRate: 13.5,
      tenureMonths: 12,
      startDate: DateTime(now.year, now.month - 6, 14),
    ),
  );
  store.addEmi(
    Emi(
      accountId: card.id,
      name: 'iPhone 17 Pro',
      principal: 4800,
      annualRate: 0,
      tenureMonths: 6,
      startDate: DateTime(now.year, now.month - 2, 27),
    ),
  );

  store.setBudget(TransactionCategory.groceries, 600);
  store.setBudget(TransactionCategory.food, 400);
  store.setBudget(TransactionCategory.transport, 250);
  store.setBudget(TransactionCategory.entertainment, 200);
  store.setBudget(TransactionCategory.shopping, 500);

  void goal(
    String name,
    double target,
    double alloc,
    String icon,
    String hex, {
    String? accId,
  }) {
    store.addGoal(
      SavingsGoal(
        name: name,
        targetAmount: target,
        allocatedAmount: alloc,
        iconName: icon,
        colorHex: hex,
        accountId: accId,
        createdDate: days(-120),
      ),
    );
  }

  goal('Japan Trip', 6000, 2350, 'star.fill', '1A56DB', accId: savings.id);
  goal('New Camera', 2200, 1980, 'camera.fill', '057A55', accId: savings.id);
  goal('Rainy Day', 10000, 3000, 'shield.fill', '7C3AED', accId: savings.id);
  goal(
    'MacBook Pro',
    2800,
    2800,
    'laptopcomputer',
    'C27803',
    accId: savings.id,
  );
  goal('Car Down Payment', 8000, 0, 'car.fill', 'EF4444');

  final lentPriya = Debt(
    person: 'Priya',
    amount: 1200,
    theyOweMe: true,
    date: days(-70),
    dueDate: days(-5),
    accountId: checking.id,
    note: 'Deposit top-up',
  );
  store.addDebt(
    Debt(
      person: 'Rahul',
      amount: 500,
      theyOweMe: true,
      date: days(-24),
      dueDate: days(6),
      accountId: checking.id,
      note: 'Concert tickets',
    ),
  );
  store.addDebt(lentPriya);
  store.addDebt(
    Debt(
      person: 'Dad',
      amount: 2000,
      theyOweMe: false,
      date: days(-45),
      accountId: checking.id,
    ),
  );
  store.repayDebt(lentPriya, 400, checking.id);

  final rnd = math.Random(7);
  const spends = <(String, TransactionCategory, double, double)>[
    ('Whole Foods', TransactionCategory.groceries, 42, 130),
    ('Blue Bottle', TransactionCategory.food, 5, 14),
    ('Uber', TransactionCategory.transport, 9, 34),
    ('Amazon', TransactionCategory.shopping, 15, 160),
    ('Cinema', TransactionCategory.entertainment, 14, 38),
    ('Pharmacy', TransactionCategory.medical, 8, 45),
    ('Electricity', TransactionCategory.utilities, 60, 110),
  ];
  for (var back = 0; back < 60; back++) {
    final day = now.subtract(Duration(days: back));
    for (var i = 0; i < rnd.nextInt(3); i++) {
      final s = spends[rnd.nextInt(spends.length)];
      store.addTransaction(
        Transaction(
          note: s.$1,
          amount: double.parse(
            (s.$3 + rnd.nextDouble() * (s.$4 - s.$3)).toStringAsFixed(2),
          ),
          category: s.$2,
          type: TransactionType.expense,
          date: DateTime(day.year, day.month, day.day, 8 + rnd.nextInt(12)),
          accountId: rnd.nextBool() ? checking.id : card.id,
        ),
      );
    }
  }

  store.addTransaction(
    Transaction(
      note: 'Freelance — landing page',
      amount: 850,
      category: TransactionCategory.freelance,
      type: TransactionType.income,
      date: days(-9),
      accountId: checking.id,
    ),
  );

  store.addTransaction(
    Transaction(
      note: 'ANA flights',
      amount: 940,
      category: TransactionCategory.transport,
      type: TransactionType.expense,
      date: days(-21),
      accountId: card.id,
      tags: ['Osaka', 'travel'],
    ),
  );
  store.addTransaction(
    Transaction(
      note: 'Dotonbori dinner',
      amount: 74.5,
      category: TransactionCategory.food,
      type: TransactionType.expense,
      date: days(-18),
      accountId: cash.id,
      tags: ['Osaka'],
    ),
  );

  store.addSplit(
    lines: const [
      (
        amount: 86.40,
        category: TransactionCategory.groceries,
        note: 'Costco run',
      ),
      (
        amount: 31.20,
        category: TransactionCategory.shopping,
        note: 'Costco run — household',
      ),
    ],
    type: TransactionType.expense,
    date: days(-5),
    accountId: checking.id,
  );
}

Widget _wrap({
  required Widget home,
  required Brightness brightness,
  GlobalKey<NavigatorState>? navKey,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: _settings!),
      ChangeNotifierProvider.value(value: _store!),
    ],
    child: MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      theme: buildExpndTheme(Brightness.light),
      darkTheme: buildExpndTheme(Brightness.dark),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      // Match production's readability boost so text sizes/overflow look real.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.15)),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// pumpAndSettle that tolerates never-ending animations (charts, shimmers).
Future<void> _safeSettle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 120));
  } catch (_) {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _safeSettle(tester);
  if (Platform.isAndroid) {
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
  }
  await binding.takeScreenshot(name);
}

/// Drag the first scrollable up so we can also see a screen's lower content.
Future<void> _scrollDown(WidgetTester tester, [double dy = -650]) async {
  final s = find.byType(Scrollable);
  if (s.evaluate().isEmpty) return;
  await tester.drag(s.first, Offset(0, dy));
  await _safeSettle(tester);
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── The four main tabs + settings + add, driven through the real shell so
  //    the bottom bar and header chrome are captured exactly as shipped. ──────
  testWidgets('shell tour (dark)', (tester) async {
    await ensureBooted();
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _wrap(
        home: const HomeShell(),
        brightness: Brightness.dark,
        navKey: navKey,
      ),
    );
    await _safeSettle(tester);

    await _shot(tester, '01_home_dark');
    await _scrollDown(tester);
    await _shot(tester, '01b_home_scrolled_dark');

    // Return to the header before opening settings.
    await _scrollDown(tester, 3000);
    // Settings via the header avatar.
    try {
      await tester.tap(find.byType(SettingsAvatarAction).first);
      await _safeSettle(tester);
      await _shot(tester, '05_settings_dark');
      await _scrollDown(tester);
      await _shot(tester, '05b_settings_scrolled_dark');
      // A little further so the alert toggles start flush under the header
      // instead of on a half-cut row — this is the one used for the listing.
      await _scrollDown(tester, -152);
      await _shot(tester, '34_settings_alerts_dark');
      navKey.currentState?.pop();
      await _safeSettle(tester);
    } catch (e) {
      rethrow;
    }

    // Add Transaction via the FAB.
    try {
      await tester.tap(find.byTooltip('Add transaction').first);
      await _safeSettle(tester);
      await _shot(tester, '06_add_transaction_dark');
      await _scrollDown(tester);
      await _shot(tester, '06b_add_transaction_scrolled_dark');
      navKey.currentState?.pop();
      await _safeSettle(tester);
    } catch (e) {
      rethrow;
    }
  });

  // ── Every tab reached by tapping the real bottom bar, so each shot carries
  //    the shipping nav chrome (HOME/ANALYTICS/+/WALLET/PLAN). These are the
  //    ones fit for the App Store listing; the direct-pump shots below are for
  //    design review and deliberately omit the bar. Semantics taps need a live
  //    handle, hence ensureSemantics(). ────────────────────────────────────────
  testWidgets('shell tabs with nav bar (dark)', (tester) async {
    await ensureBooted();
    await tester.pumpWidget(
      _wrap(home: const HomeShell(), brightness: Brightness.dark),
    );
    await _safeSettle(tester);

    await _shot(tester, '30_shell_home_dark');

    for (final (label, name, screenType) in [
      ('Analytics', '31_shell_analytics_dark', AnalyticsView),
      ('Wallet', '32_shell_wallet_dark', WalletView),
      ('Plan', '33_shell_plan_dark', PlanView),
    ]) {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '$label tab',
        ),
      );
      await _safeSettle(tester);
      expect(find.byType(screenType), findsOneWidget);
      await _shot(tester, name);
      await _scrollDown(tester);
      await _shot(tester, '${name}_scrolled');
    }
  });

  // ── The three content tabs, pumped directly (semantics-label taps proved
  //    flaky without an active semantics handle). Each renders its own header. ─
  Future<void> tabScreen(
    WidgetTester tester,
    String name,
    Brightness b,
    Widget screen,
  ) async {
    await ensureBooted();
    await tester.pumpWidget(
      _wrap(
        brightness: b,
        home: Material(type: MaterialType.transparency, child: screen),
      ),
    );
    await _safeSettle(tester);
    await _shot(tester, name);
    await _scrollDown(tester);
    await _shot(tester, '${name}_scrolled');
    await _scrollDown(tester);
    await _shot(tester, '${name}_scrolled2');
  }

  Widget walletScreen() =>
      WalletView(focusAccountId: null, onFocusConsumed: () {});

  testWidgets('analytics tab (dark)', (tester) async {
    await tabScreen(
      tester,
      '02_analytics_dark',
      Brightness.dark,
      const AnalyticsView(),
    );
  });
  testWidgets('wallet tab (dark)', (tester) async {
    await tabScreen(tester, '03_wallet_dark', Brightness.dark, walletScreen());
  });
  testWidgets('plan tab (dark)', (tester) async {
    await tabScreen(tester, '04_plan_dark', Brightness.dark, const PlanView());
  });
  testWidgets('analytics tab (light)', (tester) async {
    await tabScreen(
      tester,
      '23_analytics_light',
      Brightness.light,
      const AnalyticsView(),
    );
  });
  testWidgets('wallet tab (light)', (tester) async {
    await tabScreen(
      tester,
      '21_wallet_light',
      Brightness.light,
      walletScreen(),
    );
  });
  testWidgets('plan tab (light)', (tester) async {
    await tabScreen(
      tester,
      '22_plan_light',
      Brightness.light,
      const PlanView(),
    );
  });

  // ── Modals / pushed routes, each launched from a bare context ──────────────
  Future<void> launchAndShoot(
    WidgetTester tester,
    String name,
    Brightness b,
    void Function(BuildContext) open, {
    bool scroll = false,
  }) async {
    await ensureBooted();
    await tester.pumpWidget(
      _wrap(
        brightness: b,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => open(ctx),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await _safeSettle(tester);
    await tester.tap(find.text('OPEN'));
    await _safeSettle(tester);
    await _shot(tester, name);
    if (scroll) {
      await _scrollDown(tester);
      await _shot(tester, '${name}_scrolled');
    }
  }

  testWidgets('upcoming (dark)', (tester) async {
    await launchAndShoot(
      tester,
      '07_upcoming_dark',
      Brightness.dark,
      (ctx) => showUpcoming(ctx),
      scroll: true,
    );
  });

  testWidgets('transaction detail (dark)', (tester) async {
    await ensureBooted();
    final t = _store!.transactions.firstWhere(
      (e) => e.tags.isNotEmpty,
      orElse: () => _store!.transactions.first,
    );
    await launchAndShoot(
      tester,
      '08_transaction_detail_dark',
      Brightness.dark,
      (ctx) => showTransactionDetail(ctx, t),
    );
  });

  testWidgets('add EMI (dark)', (tester) async {
    await ensureBooted();
    final card = _store!.accounts.firstWhere(
      (a) => a.type == AccountType.credit,
      orElse: () => _store!.accounts.first,
    );
    await launchAndShoot(
      tester,
      '09_add_emi_dark',
      Brightness.dark,
      (ctx) => showAddEmi(ctx, accountId: card.id),
      scroll: true,
    );
  });

  testWidgets('account onboarding (dark)', (tester) async {
    await launchAndShoot(
      tester,
      '10_account_onboarding_dark',
      Brightness.dark,
      (ctx) => showAccountOnboarding(ctx),
      scroll: true,
    );
  });

  testWidgets('add account (dark)', (tester) async {
    await launchAndShoot(
      tester,
      '11_add_account_dark',
      Brightness.dark,
      (ctx) => showAddAccount(ctx),
      scroll: true,
    );
  });

  testWidgets("what's new (dark)", (tester) async {
    await launchAndShoot(
      tester,
      '12_whats_new_dark',
      Brightness.dark,
      (ctx) => showWhatsNew(ctx),
      scroll: true,
    );
  });

  // ── Light-mode spot checks on the primary surfaces ─────────────────────────
  testWidgets('home (light)', (tester) async {
    await ensureBooted();
    await tester.pumpWidget(
      _wrap(home: const HomeShell(), brightness: Brightness.light),
    );
    await _safeSettle(tester);
    await _shot(tester, '20_home_light');
    await _scrollDown(tester);
    await _shot(tester, '20b_home_scrolled_light');
  });

  testWidgets('add transaction (light)', (tester) async {
    await launchAndShoot(
      tester,
      '24_add_transaction_light',
      Brightness.light,
      (ctx) => showAddTransaction(ctx),
      scroll: true,
    );
  });
  for (final brightness in Brightness.values) {
    testWidgets('history search ${brightness.name}', (tester) async {
      await ensureBooted();
      await tester.pumpWidget(
        _wrap(
          home: const Scaffold(body: SafeArea(child: HistoryView())),
          brightness: brightness,
        ),
      );
      await _shot(tester, '50_history_${brightness.name}');
      await tester.enterText(find.byType(TextField).first, 'Coffee');
      await _shot(tester, '51_search_${brightness.name}');
    });
  }
  testWidgets('settings light', (tester) async {
    await ensureBooted();
    await tester.pumpWidget(
      _wrap(home: const SettingsView(), brightness: Brightness.light),
    );
    await _shot(tester, '52_settings_light');
  });

  for (final brightness in Brightness.values) {
    testWidgets('capture headers ${brightness.name}', (tester) async {
      await ensureBooted();
      await tester.pumpWidget(
        _wrap(home: const QuickCaptureScreen(), brightness: brightness),
      );
      await _shot(tester, '53_quick_capture_${brightness.name}');
      await tester.pumpWidget(
        _wrap(home: const CaptureInboxScreen(), brightness: brightness),
      );
      await _shot(tester, '54_capture_inbox_${brightness.name}');
    });
  }
}
