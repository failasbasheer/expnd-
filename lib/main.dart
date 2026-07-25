import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/backup.dart';
import 'services/reminders.dart';
import 'services/widget_bridge.dart';
import 'store/app_store.dart';
import 'store/settings_store.dart';
import 'theme/expnd_theme.dart';
import 'screens/add_transaction.dart';
import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
import 'screens/account_setup.dart';
import 'screens/splash_screen.dart';
import 'screens/whats_new.dart';

/// Lets the home-widget deep-link handler push routes from outside the tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpndBootstrap());
}

/// Boots the stores while showing the branded splash. Data loading and a
/// minimum splash duration run concurrently, so the loading screen is always
/// seen but never lingers longer than the work takes.
class ExpndBootstrap extends StatefulWidget {
  const ExpndBootstrap({super.key});

  @override
  State<ExpndBootstrap> createState() => _ExpndBootstrapState();
}

class _ExpndBootstrapState extends State<ExpndBootstrap> {
  late final Future<_Boot> _boot = _load();

  Future<_Boot> _load() async {
    final init = _init();
    // Keep the splash up long enough for its animation to land.
    await Future.delayed(const Duration(milliseconds: 1600));
    return init;
  }

  Future<_Boot> _init() async {
    Haptics.prefs = await SharedPreferences.getInstance();
    final settings = await SettingsStore.create();
    final store = await AppStore.create();
    store.generateRecurring();
    // Seed the home-screen widgets and keep them in sync with every change.
    await WidgetBridge.attach(store, settings);
    // Re-arm every notification from the ledger + settings as they stand now.
    // iOS drops pending notifications when an app is reinstalled and Android
    // forgets them on some OEM restarts, so the whole schedule is rebuilt on
    // each launch rather than assumed to still be in place — and rebuilding it
    // is also what keeps the personalised text current. Never prompts:
    // permission was already granted when the user turned an alert on. Any
    // state alert newly true (over budget, goal reached) fires here too.
    await Reminders.refreshAll(store, settings);
    // Take a rolling snapshot if the last one has gone stale. Everything here
    // was typed by hand and there is no server to re-fetch it from, so this
    // runs unprompted rather than waiting to be remembered. Failures are
    // swallowed inside — a backup must never stop the app from opening.
    unawaited(maybeAutoBackup(
        store, settings, await getApplicationDocumentsDirectory()));
    return _Boot(settings, store);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _boot,
      builder: (context, snap) {
        // Cross-fade from the splash into the app instead of a hard cut.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: snap.hasData
              ? ExpndApp(
                  key: const ValueKey('app'),
                  settings: snap.data!.settings,
                  store: snap.data!.store,
                )
              : const MaterialApp(
                  key: ValueKey('splash'),
                  debugShowCheckedModeBanner: false,
                  home: SplashScreen(),
                ),
        );
      },
    );
  }
}

class _Boot {
  final SettingsStore settings;
  final AppStore store;
  _Boot(this.settings, this.store);
}

class ExpndApp extends StatelessWidget {
  final SettingsStore settings;
  final AppStore store;
  const ExpndApp({super.key, required this.settings, required this.store});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: store),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, s, _) => MaterialApp(
          navigatorKey: navigatorKey,
          title: 'EXPND',
          debugShowCheckedModeBanner: false,
          themeMode: s.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          // App-wide momentum scrolling with an interactive edge-swipe back,
          // so every list and route feels fluid on both iOS and Android.
          scrollBehavior: const _FluidScrollBehavior(),
          // Tapping anywhere that isn't itself tappable dismisses the
          // keyboard. Essential on iOS, where the decimal pad has no Done
          // key, and it matches platform convention on Android too.
          builder: (context, child) {
            // Bump all text ~15% for readability, composed on top of the
            // user's system text-size setting (so Dynamic Type still works),
            // then clamped so extreme accessibility sizes can't break layouts.
            final system = MediaQuery.textScalerOf(context)
                .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.15);
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: _BoostedTextScaler(system, 1.15)),
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: child,
              ),
            );
          },
          home: const AppRoot(),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness b) {
    final oc = ExpndColors(b);
    return ThemeData(
      brightness: b,
      scaffoldBackgroundColor: oc.bg,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ExpndColors.gold,
        brightness: b,
      ),
      // Smooth, consistent route transitions: a fluid horizontal slide with
      // interactive back-swipe on iOS, and the modern zoom on Android.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
      }),
    );
  }
}

/// Gives the whole app iOS-style momentum + overscroll bounce (instead of the
/// hard clamp Android uses by default) and drops the glow, so scrolling reads
/// as fluid everywhere. Also enables trackpad/mouse dragging for desktop.
class _FluidScrollBehavior extends MaterialScrollBehavior {
  const _FluidScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// Wraps another [TextScaler] and multiplies its result by [boost], so the
/// app's readability bump composes with (rather than replaces) the user's
/// system text-size preference.
class _BoostedTextScaler extends TextScaler {
  const _BoostedTextScaler(this.base, this.boost);
  final TextScaler base;
  final double boost;

  @override
  double scale(double fontSize) => base.scale(fontSize) * boost;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * boost;

  @override
  bool operator ==(Object other) =>
      other is _BoostedTextScaler &&
      other.base == base &&
      other.boost == boost;

  @override
  int get hashCode => Object.hash(base, boost);
}

/// Lock gate + first-run account onboarding (mirrors AppRootView).
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _shownSetup = false;
  bool _shownWhatsNew = false;
  // A quick-add tap that arrived while the app was locked, replayed on unlock.
  bool _pendingQuickAdd = false;
  StreamSubscription<Uri?>? _widgetClicks;
  // When the app last dropped to the background, so resume can decide whether
  // the auto-lock grace window has elapsed. Null means "not backgrounded".
  DateTime? _leftAt;
  // An opaque cover shown while the app is away, so the OS app-switcher
  // snapshot never leaks balances even when re-auth is inside its grace window.
  bool _covering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowSetup();
      _maybeShowWhatsNew();
    });
    // Home-screen widget quick-add: both the cold-start launch and taps while
    // the app is already running.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetUri);
    _widgetClicks = HomeWidget.widgetClicked.listen(_onWidgetUri);
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onWidgetUri(Uri? uri) {
    if (uri == null || !mounted) return;
    if (uri.host != 'add' && uri.path != '/add') return;
    final settings = context.read<SettingsStore>();
    final locked = settings.biometricLockEnabled && !_unlocked;
    if (locked) {
      _pendingQuickAdd = true; // wait until the user gets past the lock screen
    } else {
      _openQuickAdd();
    }
  }

  void _openQuickAdd() {
    _pendingQuickAdd = false;
    final ctx = navigatorKey.currentContext;
    if (ctx != null) showAddTransaction(ctx);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final settings = context.read<SettingsStore>();
    if (!settings.biometricLockEnabled) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Only cover/track once the user is actually past the lock. If the
        // LockScreen is already up it covers itself, and its Face ID prompt
        // (which itself fires `inactive`) must not arm the grace timer.
        if (_unlocked) {
          if (!_covering) setState(() => _covering = true);
          // `paused` is the only truly-backgrounded signal — Control Center
          // and the notification shade stop at `inactive`, so they never start
          // the re-lock countdown.
          if (state == AppLifecycleState.paused) _leftAt = DateTime.now();
        }
      case AppLifecycleState.resumed:
        final leftAt = _leftAt;
        _leftAt = null;
        // Immediately (grace 0) always expires; any window compares elapsed
        // time. Never having reached `paused` (leftAt null) leaves us unlocked.
        final expired = leftAt != null &&
            DateTime.now().difference(leftAt).inSeconds >=
                settings.autoLockGraceSeconds;
        setState(() {
          _covering = false;
          if (_unlocked && expired) _unlocked = false;
        });
      case AppLifecycleState.detached:
        break;
    }
  }

  void _maybeShowSetup() {
    final settings = context.read<SettingsStore>();
    final locked = settings.biometricLockEnabled && !_unlocked;
    if (!settings.hasCompletedAccountSetup && !locked && !_shownSetup) {
      _shownSetup = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        showAccountOnboarding(context);
      });
    }
  }

  /// Shows the What's New tour once per version, but only to users who already
  /// finished setup — that's exactly the people upgrading from a previous
  /// version. Fresh installs get [kWhatsNewVersion] stamped as they complete
  /// onboarding, so they never see an "update" tour for features they're
  /// meeting for the first time.
  void _maybeShowWhatsNew() {
    final settings = context.read<SettingsStore>();
    final locked = settings.biometricLockEnabled && !_unlocked;
    if (locked || _shownWhatsNew) return;
    if (!settings.hasCompletedAccountSetup) return;
    if (settings.whatsNewSeenVersion >= kWhatsNewVersion) return;
    _shownWhatsNew = true;
    // Just behind the setup delay, so the home screen has settled first.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      showWhatsNew(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final locked = settings.biometricLockEnabled && !_unlocked;

    return Stack(
      children: [
        const HomeShell(),
        if (locked)
          LockScreen(onUnlock: () {
            setState(() => _unlocked = true);
            _maybeShowSetup();
            _maybeShowWhatsNew();
            if (_pendingQuickAdd) _openQuickAdd();
          })
        // Away but still within the grace window: no re-auth needed, just an
        // opaque cover so nothing shows through the app-switcher snapshot.
        else if (_covering)
          const _PrivacyCover(),
      ],
    );
  }
}

/// Opaque, static screen laid over the app while it sits in the background but
/// is still inside its auto-lock grace window (so no Face ID is owed yet). It
/// keeps balances out of the OS app-switcher snapshot, reusing the launch mark
/// so a quick hop away and back reads as the app, not a foreign screen.
class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ExpndColors.ink,
      child: const Center(
        child: Image(
          image: AssetImage('assets/brand/expnd_E.png'),
          height: 172,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
