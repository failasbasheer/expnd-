import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/models.dart';
import '../store/app_store.dart';

/// Moves amounts captured outside the app — widget buttons, the Lock Screen,
/// Siri — out of the shared App Group queue and into the store's inbox.
///
/// The native side can't reach Hive, so it only ever appends to a JSON array in
/// the App Group (see ios/ExpndWidget/CaptureQueue.swift). This is the other
/// half of that handoff: read the array, hand it to [AppStore], then rewrite
/// the array without the entries we took.
///
/// Two things make that safe against a widget tap landing mid-drain:
///  * acknowledgement re-reads the queue rather than clearing it, so an entry
///    appended while we were working survives;
///  * ids come from the native side and [AppStore.addPendingCaptures] skips
///    ones it already holds, so a drain that dies before acknowledging replays
///    without duplicating.
class CaptureInbox {
  CaptureInbox._();

  /// Keep in sync with CaptureQueue.queueKey and AppCaptureQueue.queueKey.
  static const queueKey = 'pending_captures';
  static const consumedKey = 'consumed_capture_ids';

  /// Reads and files everything waiting. Returns how many captures were taken,
  /// so a caller can decide whether to surface the inbox. Never throws: a
  /// failure here must not block app start.
  static Future<int> drain(AppStore store) async {
    final List<Map> entries;
    try {
      entries = await _read();
    } catch (e) {
      debugPrint('CaptureInbox.drain read failed: $e');
      return 0;
    }
    if (entries.isEmpty) return 0;

    final captures = <PendingCapture>[];
    final consumed = <String>{};
    for (final e in entries) {
      final capture = _parse(e);
      // A malformed entry would otherwise jam the queue forever, so drop it:
      // it's acknowledged below along with the good ones.
      final id = e['id'];
      if (id is String) consumed.add(id);
      if (capture != null) captures.add(capture);
    }

    store.addPendingCaptures(captures);

    try {
      await _acknowledge(consumed);
    } catch (e) {
      // The captures are already saved and deduped by id, so the worst case is
      // that the next drain re-reads them and adds nothing.
      debugPrint('CaptureInbox.drain acknowledge failed: $e');
    }
    return captures.length;
  }

  static Future<List<Map>> _read() async {
    final raw = await HomeWidget.getWidgetData<String>(queueKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final consumedRaw = await HomeWidget.getWidgetData<String>(consumedKey);
    final consumed = consumedRaw == null || consumedRaw.isEmpty
        ? <String>{}
        : (jsonDecode(consumedRaw) as List? ?? const [])
              .whereType<String>()
              .toSet();
    return decoded
        .whereType<Map>()
        .where((e) => e['id'] is! String || !consumed.contains(e['id']))
        .toList();
  }

  /// Rewrites the queue with only the entries we didn't take, so anything the
  /// widget appended while this drain ran is left for the next one.
  static Future<void> _acknowledge(Set<String> consumed) async {
    final raw = await HomeWidget.getWidgetData<String>(consumedKey);
    final prior = raw == null || raw.isEmpty
        ? <String>{}
        : (jsonDecode(raw) as List? ?? const []).whereType<String>().toSet();
    prior.addAll(consumed);
    await HomeWidget.saveWidgetData<String>(
      consumedKey,
      jsonEncode(prior.toList()),
    );
  }

  static PendingCapture? _parse(Map e) {
    final id = e['id'];
    final amount = e['amount'];
    if (id is! String || amount is! num || amount <= 0) return null;
    final at = e['at'];
    return PendingCapture(
      id: id,
      amount: amount.toDouble(),
      note: e['note'] is String ? (e['note'] as String).trim() : '',
      capturedAt: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : DateTime.now(),
      source: e['source'] is String ? e['source'] as String : 'widget',
    );
  }
}
