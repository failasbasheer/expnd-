import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// The "open Quick Add" request an iOS App Intent leaves behind.
///
/// Back Tap can't call into the app — it can only run a Shortcut, which runs an
/// App Intent. That intent foregrounds the app and drops a timestamp in the
/// shared App Group (see ios/Runner/ExpndAppIntents.swift); this is the Dart
/// half that picks it up and clears it.
///
/// A durable flag rather than an event, because the ordering between the
/// intent's `perform()` and Flutter finishing its boot isn't guaranteed: on a
/// cold launch the request can land either side of the first frame. A flag
/// tolerates both — whoever looks next finds it. Consuming clears it, so the
/// several places that look can't open the screen twice.
class CaptureTrigger {
  CaptureTrigger._();

  /// Keep in sync with QuickCaptureIntent.requestKey.
  static const requestKey = 'capture_request';

  /// How long a request stays honourable. Without this, a request the app never
  /// managed to consume (killed mid-launch, say) would ambush the user with a
  /// Quick Add screen the next time they opened the app themselves — possibly
  /// days later. The gesture means "now"; two minutes is generous for a cold
  /// launch and still unmistakably now.
  static const _maxAge = Duration(minutes: 2);

  /// Reads and clears any pending request, reporting whether a *fresh* one was
  /// waiting. Stale requests are cleared too — they've been answered by being
  /// forgotten, and leaving one behind would re-arm it forever.
  ///
  /// Never throws: failing to open Quick Add must not take the app's launch or
  /// resume path down with it.
  static Future<bool> consume() async {
    final String? raw;
    try {
      raw = await HomeWidget.getWidgetData<String>(requestKey);
    } catch (e) {
      debugPrint('CaptureTrigger.consume read failed: $e');
      return false;
    }
    if (raw == null || raw.isEmpty) return false;

    try {
      await HomeWidget.saveWidgetData<String>(requestKey, '');
    } catch (e) {
      // Worth continuing anyway: opening the screen the user asked for matters
      // more than the flag, and the staleness window caps how long an
      // un-cleared request can keep firing.
      debugPrint('CaptureTrigger.consume clear failed: $e');
    }

    final at = int.tryParse(raw);
    // An unparseable timestamp is treated as a real request rather than
    // dropped: the user did tap, and the worst case is one extra screen.
    if (at == null) return true;

    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(at))
        .abs();
    return age <= _maxAge;
  }
}
