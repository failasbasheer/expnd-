// The reminder copy is the "personal" half of the notifications: a tone the
// user picked, a line they may have written themselves. These tests pin the
// rules that keep it honest — a custom line only shows when it exists, a tone
// only ever touches the framing, and the factual insight bodies are never
// reworded — because a personality setting that mangles a figure is worse than
// no personality at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:expnd/services/insights.dart';
import 'package:expnd/store/app_store.dart';

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

void main() {
  final now = DateTime(2026, 6, 15);
  AppStore store() => AppStore(_FakeBox());

  group('buildReminderBodies — message modes', () {
    test('custom mode repeats the user\'s line every night', () {
      final bodies = buildReminderBodies(
        store(),
        'USD',
        from: now,
        mode: 'custom',
        customMessage: 'Did you log lunch?',
      );
      expect(bodies, hasLength(7));
      expect(bodies.every((b) => b == 'Did you log lunch?'), isTrue);
    });

    test('custom mode with a blank line falls back to auto', () {
      final bodies = buildReminderBodies(
        store(),
        'USD',
        from: now,
        mode: 'custom',
        customMessage: '   ',
      );
      // A fresh store has no trends, so auto is all filler — the point is only
      // that it is NOT seven copies of an empty string.
      expect(bodies.every((b) => b.trim().isEmpty), isFalse);
    });

    test('mixed mode drops the custom line into every other slot', () {
      final bodies = buildReminderBodies(
        store(),
        'USD',
        from: now,
        mode: 'mixed',
        customMessage: 'My own nudge',
      );
      expect(bodies[1], 'My own nudge');
      expect(bodies[3], 'My own nudge');
      expect(bodies[0], isNot('My own nudge'));
    });

    test('auto mode is unaffected by an unused custom line', () {
      final withLine = buildReminderBodies(
        store(),
        'USD',
        from: now,
        mode: 'auto',
        customMessage: 'ignored',
      );
      final without = buildReminderBodies(store(), 'USD', from: now);
      expect(withLine, without);
    });
  });

  group('reminderVoice — tone & name', () {
    test('parses the stored string, unknown falls back to neutral', () {
      expect(reminderToneFromString('blunt'), ReminderTone.blunt);
      expect(reminderToneFromString('playful'), ReminderTone.playful);
      expect(reminderToneFromString('nonsense'), ReminderTone.neutral);
    });

    test('title changes with tone', () {
      expect(
        reminderVoice(ReminderTone.neutral).title,
        'Log today\'s spending',
      );
      expect(reminderVoice(ReminderTone.blunt).title, 'Log it.');
    });

    test('a real name is greeted, the placeholder is not', () {
      expect(
        reminderVoice(ReminderTone.blunt, name: 'Travis Smith').title,
        'Travis — log it.',
      );
      // First name only, and the setup placeholder is treated as "no name".
      expect(
        reminderVoice(ReminderTone.neutral, name: 'Your Name').title,
        'Log today\'s spending',
      );
    });

    test('filler pool differs by tone', () {
      final playful = reminderVoice(ReminderTone.playful).filler;
      final neutral = reminderVoice(ReminderTone.neutral).filler;
      expect(playful, isNot(neutral));
      // Playful carries an emoji; neutral never does.
      expect(playful.any((f) => f.contains('💸') || f.contains('🕵️')), isTrue);
    });

    test('a chosen tone shapes the filler the bodies fall back to', () {
      final bodies = buildReminderBodies(
        store(),
        'USD',
        from: now,
        tone: ReminderTone.playful,
      );
      // A fresh store has nothing to report, so at least one line is playful
      // filler rather than the neutral default.
      expect(
        bodies.any(
          (b) => reminderVoice(ReminderTone.playful).filler.contains(b),
        ),
        isTrue,
      );
    });
  });

  group('buildWeeklySummaryBody', () {
    test('a quiet week gets the gentle fallback, not an empty string', () {
      final body = buildWeeklySummaryBody(store(), 'USD', from: now);
      expect(body.trim(), isNotEmpty);
      expect(body, contains('quiet week'));
    });
  });
}
