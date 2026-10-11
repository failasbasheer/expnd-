// The nav restructure moved Profile off the tab bar and behind the header
// avatar, and gave the freed 4th slot to PLAN. Both are one-line changes to
// break by accident, and neither shows up in a store test — so they are
// pinned here.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expnd/screens/home_shell.dart';
import 'package:expnd/screens/plan_view.dart';
import 'package:expnd/screens/settings_view.dart';
import 'package:expnd/store/app_store.dart';
import 'package:expnd/store/settings_store.dart';
import 'package:expnd/widgets/app_header.dart';

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

/// A tall, narrow surface so a ListView builds enough of its children for the
/// section headers near the bottom to exist. The default 800x600 test window
/// leaves them unbuilt and the finders come up empty.
void _sizeView(WidgetTester t) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 2200);
  addTearDown(t.view.reset);
}

Future<Widget> _app(Widget home) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.create();
  settings.userName = 'Failas';
  settings.hasCompletedAccountSetup = true;
  final store = AppStore(_FakeBox());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: store),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      // Screens that normally live inside the shell's Scaffold are pumped bare
      // here, so supply the Material ancestor their fields and switches need.
      home: Material(type: MaterialType.transparency, child: home),
    ),
  );
}

void main() {
  testWidgets('the tab bar offers Plan, and no longer Profile', (t) async {
    _sizeView(t);
    await t.pumpWidget(await _app(const HomeShell()));
    await t.pumpAndSettle();

    final add = find.byTooltip('Add transaction');
    expect(t.getTopLeft(add).dy, greaterThan(500));
    final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
    expect(
      t.getSize(find.byWidget(scaffold.bottomNavigationBar!)).height,
      lessThan(130),
    );
    // NeoPOP caps tab labels, as shipped in 1.0.
    expect(find.text('PLAN'), findsWidgets);
    expect(find.text('PROFILE'), findsNothing);
  });

  testWidgets('navigation controls expose accessible tap actions', (t) async {
    _sizeView(t);
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(await _app(const HomeShell()));
      await t.pumpAndSettle();
      for (final label in [
        'Home tab',
        'Analytics tab',
        'Wallet tab',
        'Plan tab',
        'Add transaction',
      ]) {
        final control = find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        );
        expect(
          t
              .getSemantics(control)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
          reason: label,
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the header avatar opens settings', (t) async {
    _sizeView(t);
    await t.pumpWidget(await _app(const PlanView()));
    await t.pumpAndSettle();

    // Identity is the user's initial, not a generic icon.
    expect(find.widgetWithText(SettingsAvatarAction, 'F'), findsOneWidget);
    expect(find.byType(SettingsView), findsNothing);

    await t.tap(find.byType(SettingsAvatarAction));
    await t.pumpAndSettle();

    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('settings carries the sections Plan gave up', (t) async {
    _sizeView(t);
    await t.pumpWidget(await _app(const SettingsView()));
    await t.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('CUSTOM CATEGORIES'), findsNothing);
    await t.tap(find.text('Categories & tags'));
    await t.pumpAndSettle();
    expect(find.text('CUSTOM CATEGORIES'), findsOneWidget);
    // Money-management sections belong to PLAN now.
    expect(find.text('CATEGORY BUDGETS'), findsNothing);
  });

  testWidgets('the avatar lines up with the other header controls', (t) async {
    _sizeView(t);
    await t.pumpWidget(await _app(const PlanView()));
    await t.pumpAndSettle();

    final avatar = t.getRect(find.byType(SettingsAvatarAction));
    // Square, the same footprint every header action occupies — a nested box
    // used to make it both doubled-up and a different size.
    expect(avatar.width, closeTo(ExpndHeaderMetrics.action, 2.5));
    expect(avatar.height, closeTo(ExpndHeaderMetrics.action, 2.5));

    // Flush to the header's right gutter rather than floating mid-row.
    final header = t.getRect(find.byType(ExpndHeader));
    expect(header.right - avatar.right, closeTo(ExpndHeaderMetrics.gutter, 4));
  });

  testWidgets('switching tabs keeps each tab\'s state', (t) async {
    _sizeView(t);
    await t.pumpWidget(await _app(const HomeShell()));
    await t.pumpAndSettle();
    final before = t.state(find.byType(Scrollable).first);
    await t.tap(find.text('ANALYTICS').last);
    await t.pumpAndSettle();
    await t.tap(find.text('HOME').last);
    await t.pumpAndSettle();
    expect(t.state(find.byType(Scrollable).first), same(before));
  });
}
