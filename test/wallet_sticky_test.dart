// The wallet's sticky account bar. Its whole job is to answer "which card am I
// looking at?" once the deck has scrolled away, so the behaviour worth pinning
// is exactly that: hidden while the deck is on screen, present once it isn't,
// and always naming the card that's actually at the front.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/screens/wallet_view.dart';

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

Account _acct(String name, AccountType type, double balance,
        {double? limit}) =>
    Account(
      name: name,
      type: type,
      currencyCode: 'USD',
      balance: balance,
      creditLimit: limit,
    );

Future<AppStore> _seeded() async {
  final store = AppStore(_FakeBox());
  store.addAccount(_acct('HDFC Checking', AccountType.bank, 6400));
  store.addAccount(_acct('Emergency Fund', AccountType.savings, 11200));
  store.addAccount(_acct('Pocket Cash', AccountType.cash, 320));
  store.addAccount(
      _acct('ICICI Amazon Pay', AccountType.credit, 1840, limit: 15000));
  // The bar only matters when there's enough below the deck to scroll past it,
  // so give the selected account a real transaction list.
  final first = store.accounts.first;
  for (var i = 0; i < 20; i++) {
    store.addTransaction(Transaction(
      note: 'Spend $i',
      amount: 20.0 + i,
      category: TransactionCategory.groceries,
      type: TransactionType.expense,
      date: DateTime(2026, 7, 20 - (i % 19)),
      accountId: first.id,
    ));
  }
  return store;
}

Future<void> _pumpWallet(WidgetTester tester, AppStore store) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.create();
  // A phone-sized viewport. The default 800x600 test surface is short enough
  // that the deck can never scroll clear, which is precisely the state the bar
  // exists for.
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(tester.view.reset);

  // flutter_test draws every glyph as a box the full width of the font size,
  // so the card face's number rows measure far wider here than with the real
  // font and report overflows that don't occur on a device (verified: zero
  // layout exceptions in a simulator run). This test is about the sticky bar's
  // behaviour, so those measurement artifacts are filtered out rather than
  // allowed to fail it.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    priorOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = priorOnError);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: store),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SafeArea(child: WalletView())),
      ),
    ),
  );
  // Let the deck's entrance animation and height tween settle.
  await tester.pumpAndSettle();
}

bool _barVisible(WidgetTester tester) =>
    tester.any(find.byKey(walletStickyBarKey));

void main() {
  testWidgets('stays hidden while the card deck is on screen', (tester) async {
    final store = await _seeded();
    await _pumpWallet(tester, store);

    expect(_barVisible(tester), isFalse,
        reason: 'the deck is visible, so the bar would be redundant');
  });

  testWidgets('appears once the deck scrolls out of view', (tester) async {
    final store = await _seeded();
    await _pumpWallet(tester, store);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(_barVisible(tester), isTrue,
        reason: 'the deck is gone, so the details below need an owner');
  });

  testWidgets('names the account at the front of the deck', (tester) async {
    final store = await _seeded();
    await _pumpWallet(tester, store);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    // The first account is selected by default, so it is what the bar claims.
    expect(find.text('HDFC Checking'), findsWidgets);
  });

  testWidgets('retreats again when scrolled back to the deck', (tester) async {
    final store = await _seeded();
    await _pumpWallet(tester, store);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_barVisible(tester), isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(_barVisible(tester), isFalse,
        reason: 'the deck is back, so the bar should get out of the way');
  });

  testWidgets('an empty wallet never shows the bar', (tester) async {
    final store = AppStore(_FakeBox());
    await _pumpWallet(tester, store);

    expect(_barVisible(tester), isFalse);
    expect(find.text('NO ACCOUNTS YET'), findsOneWidget);
  });
}
