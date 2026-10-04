// Amounts captured from a widget button or Siri are logged in a process that
// can't reach the store, so they cross into the app through a queue that both
// sides mutate. These tests cover the two ways that handoff can go wrong: a
// capture logged twice, or a capture that is filed into the ledger while still
// sitting in the inbox.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/services/capture_trigger.dart';
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

PendingCapture _capture(String id, double amount) =>
    PendingCapture(id: id, amount: amount, capturedAt: DateTime(2026, 7, 20));

void main() {
  // The capture-trigger group talks over a mocked platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pending captures', () {
    test('are held out of the ledger and every balance', () {
      final store = AppStore(_FakeBox());
      final account = Account(
        name: 'Cash',
        type: AccountType.cash,
        balance: 500,
        currencyCode: 'USD',
      );
      store.addAccount(account);

      store.addPendingCaptures([_capture('cap-1', 120)]);

      expect(store.pendingCaptures.length, 1);
      // The whole point of the inbox: a capture is recorded but inert.
      expect(store.transactions, isEmpty);
      expect(store.balanceFor(account), 500);
    });

    test('a replayed drain does not duplicate them', () {
      final store = AppStore(_FakeBox());

      store.addPendingCaptures([_capture('cap-1', 120), _capture('cap-2', 40)]);
      // The native queue keeps entries until acknowledged, so a drain that
      // dies before acknowledging hands back the same ids next launch.
      store.addPendingCaptures([_capture('cap-1', 120), _capture('cap-2', 40)]);

      expect(store.pendingCaptures.length, 2);
    });

    test('a replayed drain still admits genuinely new captures', () {
      final store = AppStore(_FakeBox());

      store.addPendingCaptures([_capture('cap-1', 120)]);
      store.addPendingCaptures([_capture('cap-1', 120), _capture('cap-2', 40)]);

      expect(store.pendingCaptures.map((c) => c.id), ['cap-1', 'cap-2']);
    });

    test('sort oldest first, the order they were logged in', () {
      final store = AppStore(_FakeBox());

      store.addPendingCaptures([
        PendingCapture(id: 'b', amount: 10, capturedAt: DateTime(2026, 7, 21)),
        PendingCapture(id: 'a', amount: 20, capturedAt: DateTime(2026, 7, 19)),
      ]);

      expect(store.pendingCaptures.map((c) => c.id), ['a', 'b']);
    });

    test('filing one moves it into the ledger in a single step', () {
      final store = AppStore(_FakeBox());
      final account = Account(
        name: 'Cash',
        type: AccountType.cash,
        balance: 500,
        currencyCode: 'USD',
      );
      store.addAccount(account);
      final capture = _capture('cap-1', 120);
      store.addPendingCaptures([capture]);

      final t = Transaction(
        note: 'Groceries',
        amount: 120,
        category: TransactionCategory.food,
        type: TransactionType.expense,
        date: DateTime(2026, 7, 20),
      );
      t.accountId = account.id;
      store.filePendingCapture(capture, t);

      // Never both: in the ledger and still waiting would double-count it the
      // moment the user filed it a second time.
      expect(store.pendingCaptures, isEmpty);
      expect(store.transactions.length, 1);
      expect(store.balanceFor(account), 380);
    });

    test('discarding one leaves the ledger untouched', () {
      final store = AppStore(_FakeBox());
      final account = Account(
        name: 'Cash',
        type: AccountType.cash,
        balance: 500,
        currencyCode: 'USD',
      );
      store.addAccount(account);
      final capture = _capture('cap-1', 120);
      store.addPendingCaptures([capture]);

      store.deletePendingCapture(capture);

      expect(store.pendingCaptures, isEmpty);
      expect(store.transactions, isEmpty);
      expect(store.balanceFor(account), 500);
    });

    test('survive a relaunch', () {
      final box = _FakeBox();
      AppStore(box).addPendingCaptures([_capture('cap-1', 120)]);

      // A capture the user hasn't filed yet is the only record that the money
      // moved, so it has to outlive the session that received it.
      final reopened = AppStore(box);
      expect(reopened.pendingCaptures.length, 1);
      expect(reopened.pendingCaptures.first.amount, 120);
    });
  });

  // Quick Add is the one capture surface with room to ask for a category, so
  // the category has to survive the trip to the inbox — otherwise filing asks
  // the user the same question twice.
  group('captured categories', () {
    test('are absent for captures taken where none could be picked', () {
      final capture = _capture('cap-1', 120);

      // Not TransactionCategory.other: "didn't pick" has to stay
      // distinguishable from "picked Other", or filing can't know whether to
      // leave the grid empty.
      expect(capture.category, isNull);
      expect(capture.customCategoryId, isNull);
    });

    test('resolve a built-in category by name', () {
      final capture = PendingCapture(
        id: 'cap-1',
        amount: 120,
        categoryRaw: TransactionCategory.food.raw,
      );

      expect(capture.category, TransactionCategory.food);
    });

    test('resolve to nothing when the name is not one we know', () {
      // A capture written by an older or newer build shouldn't silently file
      // itself under the wrong category.
      final capture = PendingCapture(
        id: 'cap-1',
        amount: 120,
        categoryRaw: 'Hovercraft',
      );

      expect(capture.category, isNull);
    });

    test('survive a relaunch', () {
      final box = _FakeBox();
      AppStore(box).addPendingCaptures([
        PendingCapture(
          id: 'cap-1',
          amount: 120,
          categoryRaw: TransactionCategory.transport.raw,
        ),
        PendingCapture(id: 'cap-2', amount: 40, customCategoryId: 'cc-9'),
      ]);

      final reopened = AppStore(box).pendingCaptures;
      expect(reopened.first.category, TransactionCategory.transport);
      expect(reopened.last.customCategoryId, 'cc-9');
    });
  });

  // Back Tap can't call into the app; it runs an intent that leaves a flag
  // behind. These cover the flag's two failure modes: a request that fires
  // twice, and a request that ambushes the user long after the gesture.
  group('capture trigger', () {
    const channel = MethodChannel('home_widget');
    // Stands in for the App Group the intent writes into.
    late Map<String, Object?> shared;

    setUp(() {
      shared = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = (call.arguments as Map).cast<String, Object?>();
            switch (call.method) {
              case 'getWidgetData':
                return shared[args['id']];
              case 'saveWidgetData':
                shared[args['id'] as String] = args['data'];
                return true;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void request(DateTime at) => shared[CaptureTrigger.requestKey] = at
        .millisecondsSinceEpoch
        .toString();

    test('reports nothing when no gesture has fired', () async {
      expect(await CaptureTrigger.consume(), isFalse);
    });

    test('reports a fresh request', () async {
      request(DateTime.now());

      expect(await CaptureTrigger.consume(), isTrue);
    });

    test('only fires once per gesture', () async {
      request(DateTime.now());

      await CaptureTrigger.consume();
      // Several places look for a request — launch, a late re-check, and every
      // resume — so a request that survived being read would open Quick Add
      // two or three times for one tap.
      expect(await CaptureTrigger.consume(), isFalse);
    });

    test('ignores a request too old to have meant "now"', () async {
      request(DateTime.now().subtract(const Duration(hours: 3)));

      // A request the app never managed to consume must not ambush the user
      // with a Quick Add screen days later.
      expect(await CaptureTrigger.consume(), isFalse);
    });

    test('clears a stale request rather than leaving it armed', () async {
      request(DateTime.now().subtract(const Duration(hours: 3)));

      await CaptureTrigger.consume();

      expect(shared[CaptureTrigger.requestKey], '');
    });

    test('honours a request whose timestamp is unreadable', () async {
      shared[CaptureTrigger.requestKey] = 'not-a-timestamp';

      // The user did tap; one unnecessary screen beats swallowing the gesture.
      expect(await CaptureTrigger.consume(), isTrue);
    });
  });

  group('quick-capture presets', () {
    test('scale to the currency the user actually spends in', () {
      // A one-tap button with no confirmation has to be plausible: $500 and
      // ₹500 are not the same suggestion.
      expect(SettingsStore.defaultQuickPresets('INR'), [100, 500, 1000]);
      expect(SettingsStore.defaultQuickPresets('JPY'), [100, 500, 1000]);
      expect(SettingsStore.defaultQuickPresets('USD'), [5, 10, 20]);
      expect(SettingsStore.defaultQuickPresets('EUR'), [5, 10, 20]);
    });
  });
}
