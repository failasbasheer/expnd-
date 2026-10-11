import 'package:expnd/services/apple_intelligence.dart';
import 'package:expnd/services/cloud_coach.dart';
import 'package:expnd/services/insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _reply(String text, {String stop = 'end_turn'}) => {
  'stop_reason': stop,
  'content': [
    {'type': 'text', 'text': text},
  ],
};

void main() {
  late List<Map<String, dynamic>> sent;
  late Map<String, dynamic>? Function() next;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    next = () => _reply('All good.');
    CloudCoach.send = (body) async {
      sent.add(body);
      return next();
    };
    AppleIntelligence.resetAvailabilityForTest();
  });

  tearDown(() {
    CloudCoach.enabledOverride = null;
    AppleIntelligence.resetAvailabilityForTest();
  });

  test('normal builds have no key, so it is off and sends nothing', () async {
    expect(CloudCoach.enabled, isFalse);
    expect(
      await CloudCoach.summarize([(title: 'A', detail: 'B')], 'summary'),
      isNull,
    );
    expect(sent, isEmpty);
  });

  group('personal build', () {
    setUp(() => CloudCoach.enabledOverride = true);

    test('asks Haiku briefly, thinking at low effort, with only the facts', () async {
      await CloudCoach.summarize([
        (title: 'Food is up 20%', detail: '\$120 vs \$100 last month'),
      ], 'summary');
      final body = sent.single;
      expect(body['model'], 'claude-haiku-5-5');
      expect(body['thinking'], {'type': 'adaptive'});
      expect(body['output_config'], {'effort': 'low'});
      expect(body['max_tokens'], lessThanOrEqualTo(600));
      final prompt = (body['messages'] as List).single['content'] as String;
      expect(prompt, contains('Food is up 20%'));
    });

    test('refusals and cut-off replies are not shown', () async {
      next = () => _reply('nope', stop: 'refusal');
      expect(
        await CloudCoach.summarize([(title: 'A', detail: 'B')], 'summary'),
        isNull,
      );
      next = () => _reply('half a sen', stop: 'max_tokens');
      expect(
        await CloudCoach.summarize([(title: 'A', detail: 'B')], 'summary'),
        isNull,
      );
    });

    test('category answers must be one of the allowed list', () async {
      next = () => _reply('transport');
      expect(
        await CloudCoach.category('Uber to work', ['Food', 'Transport']),
        'Transport',
      );
      next = () => _reply('Travel');
      expect(
        await CloudCoach.category('Uber to work', ['Food', 'Transport']),
        isNull,
      );
    });

    test('stops at the daily cap', () async {
      for (var i = 0; i < CloudCoach.dailyLimit; i++) {
        await CloudCoach.category('Uber', ['Transport']);
      }
      expect(sent, hasLength(CloudCoach.dailyLimit));
      expect(await CloudCoach.category('Uber', ['Transport']), isNull);
      expect(sent, hasLength(CloudCoach.dailyLimit));
    });

    test('coach answers are labelled as cloud AI', () async {
      next = () => _reply('Food spending is up 20% this month.');
      final answer = await AppleIntelligence.summarizeInsights([
        const Insight(
          title: 'Food is up 20%',
          detail: '\$120 vs \$100 last month',
          tone: InsightTone.warn,
          icon: 'fork.knife',
          weight: 1,
        ),
      ]);
      expect(answer?.source, CoachSource.cloud);
      expect(answer?.text, 'Food spending is up 20% this month.');
    });

    test('an invented figure is rejected for the app\'s own wording', () async {
      next = () => _reply('Food is up 45% — cut back by \$300.');
      final answer = await AppleIntelligence.summarizeInsights([
        const Insight(
          title: 'Food is up 20%',
          detail: '\$120 vs \$100 last month',
          tone: InsightTone.warn,
          icon: 'fork.knife',
          weight: 1,
        ),
      ]);
      expect(answer?.source, CoachSource.rules);
    });
  });
}
