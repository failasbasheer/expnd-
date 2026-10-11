import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expnd/services/insights.dart';
import 'package:expnd/services/apple_intelligence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('native availability and generation', () {
    const channel = MethodChannel('com.expnd.app/apple_intelligence');
    const fact = Insight(
      title: 'Food is up 34%',
      detail: r'$670 vs a $500 average',
      tone: InsightTone.warn,
      icon: 'fork.knife',
    );
    var available = true;
    var checks = 0;
    var generations = 0;
    var response = 'Food is up 34%.';
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      AppleIntelligence.resetAvailabilityForTest();
      available = true;
      checks = 0;
      generations = 0;
      response = 'Food is up 34%.';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              checks++;
              return available;
            }
            if (call.method == 'summarizeInsights') {
              generations++;
              return response;
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      AppleIntelligence.resetAvailabilityForTest();
    });
    test('unavailable devices cache the check and never generate', () async {
      available = false;
      for (var i = 0; i < 3; i++) {
        final answer = await AppleIntelligence.summarizeInsights([fact]);
        expect(answer?.source, CoachSource.rules);
      }
      expect(checks, 1);
      expect(generations, 0);
    });
    test(
      'concurrent identical requests share a single model response',
      () async {
        final answers = await Future.wait(
          List.generate(4, (_) => AppleIntelligence.summarizeInsights([fact])),
        );
        expect(
          answers.every((a) => a?.source == CoachSource.appleIntelligence),
          isTrue,
        );
        await AppleIntelligence.summarizeInsights([fact]);
        expect(checks, 1);
        expect(generations, 1);
      },
    );
    test(
      'availability changes replace cached rules with model answers',
      () async {
        available = false;
        expect(
          (await AppleIntelligence.summarizeInsights([fact]))?.source,
          CoachSource.rules,
        );
        available = true;
        await AppleIntelligence.refreshAvailability();
        expect(
          (await AppleIntelligence.summarizeInsights([fact]))?.source,
          CoachSource.appleIntelligence,
        );
        expect(generations, 1);
      },
    );
    test(
      'invented figures fall back and do not poison a later retry',
      () async {
        response = 'Spend 999 less.';
        expect(
          (await AppleIntelligence.summarizeInsights([fact]))?.source,
          CoachSource.rules,
        );
        response = 'Food is up 34%.';
        expect(
          (await AppleIntelligence.summarizeInsights([fact]))?.source,
          CoachSource.appleIntelligence,
        );
      },
    );
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coach prompts use stable native wire names', () {
    expect(AiCoachPrompt.values.map((prompt) => prompt.wireName), [
      'summary',
      'focus',
      'win',
      'next_step',
    ]);
  });

  test('demo-seeded builds provide every simulator preview response', () async {
    if (!AppleIntelligence.isPreview) return;
    const fact = Insight(
      title: 'Food is up 34%',
      detail: r'$670 vs a $500 average',
      tone: InsightTone.warn,
      icon: 'fork.knife',
    );

    for (final prompt in AiCoachPrompt.values) {
      final response = await AppleIntelligence.generateInsight(const [
        fact,
      ], prompt: prompt);
      expect(response?.text, isNotEmpty, reason: prompt.wireName);
      expect(response?.source, CoachSource.preview);
    }
  });

  test('demo AI suggests only an allowed transaction category', () async {
    if (!AppleIntelligence.isPreview) return;
    final suggestion = await AppleIntelligence.suggestCategory('Careem ride', [
      'Food',
      'Transport',
      'Other',
    ]);
    expect(suggestion?.category, 'Transport');

    final excluded = await AppleIntelligence.suggestCategory('Careem ride', [
      'Food',
      'Other',
    ]);
    expect(excluded, isNull);
  });

  group('without Apple Intelligence (e.g. iPhone 15, Android)', () {
    setUp(AppleIntelligence.resetAvailabilityForTest);

    const fact = Insight(
      title: 'Food is up 34%',
      detail: r'$670 vs a $500 average',
      tone: InsightTone.warn,
      icon: 'fork.knife',
    );

    test('reports the model as unavailable', () async {
      if (AppleIntelligence.isPreview) return;
      expect(await AppleIntelligence.isAvailable(), isFalse);
      expect(AppleIntelligence.available.value, isFalse);
    });

    test('every coach prompt falls back to rule-based insights', () async {
      if (AppleIntelligence.isPreview) return;
      for (final prompt in AiCoachPrompt.values) {
        final answer = await AppleIntelligence.generateInsight(const [
          fact,
        ], prompt: prompt);
        expect(answer?.source, CoachSource.rules, reason: prompt.wireName);
        expect(answer?.text, isNotEmpty, reason: prompt.wireName);
        expect(
          AppleIntelligence.isGroundedSummary(
            answer!.text,
            '${fact.title} ${fact.detail}',
          ),
          isTrue,
          reason: prompt.wireName,
        );
      }
      expect(CoachSource.rules.title, 'Insights');
      expect(CoachSource.rules.isAi, isFalse);
    });

    test('no facts still yields no card', () async {
      expect(
        await AppleIntelligence.generateInsight(
          const [],
          prompt: AiCoachPrompt.summary,
        ),
        isNull,
      );
    });

    test('category suggestions fall back to keyword rules', () async {
      if (AppleIntelligence.isPreview) return;
      final suggestion = await AppleIntelligence.suggestCategory(
        'Netflix monthly',
        ['Food', 'Subscription', 'Other'],
      );
      expect(suggestion?.category, 'Subscription');
      expect(suggestion?.source, CoachSource.rules);
    });
  });

  group('rule category matcher', () {
    const expense = [
      'Groceries',
      'Food',
      'Transport',
      'Utilities',
      'Rent',
      'Education',
      'Other',
    ];

    test('matches whole words and plurals', () {
      expect(AppleIntelligence.ruleCategory('Monthly rent', expense), 'Rent');
      expect(AppleIntelligence.ruleCategory('Two books', expense), 'Education');
      expect(
        AppleIntelligence.ruleCategory('DEWA electricity', expense),
        'Utilities',
      );
    });

    test('ignores keywords inside other words', () {
      expect(AppleIntelligence.ruleCategory('Gift for parents', expense), null);
      expect(AppleIntelligence.ruleCategory('Current account', expense), null);
      expect(AppleIntelligence.ruleCategory('Facebook ads', expense), null);
    });

    test('only returns allowed categories', () {
      expect(AppleIntelligence.ruleCategory('Uber home', ['Food']), isNull);
    });
  });

  group('Apple Intelligence grounding guard', () {
    const source =
        'Food is up 34% ₹6,700 vs a ₹5,000 average 2 payments due this week';

    test('accepts prose using only verified figures', () {
      expect(
        AppleIntelligence.isGroundedSummary(
          'Food is up 34%, with 2 payments also approaching.',
          source,
        ),
        isTrue,
      );
    });

    test('rejects a figure invented by the model', () {
      expect(
        AppleIntelligence.isGroundedSummary(
          'Cut food spending by 10% this week.',
          source,
        ),
        isFalse,
      );
    });
  });

  group('native availability and fallback', () {
    const channel = MethodChannel('com.expnd.app/apple_intelligence');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var available = false;
    var availabilityCalls = 0;
    var generationCalls = 0;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      AppleIntelligence.resetAvailabilityForTest();
      available = false;
      availabilityCalls = 0;
      generationCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'isAvailable':
            availabilityCalls++;
            return available;
          case 'summarizeInsights':
            generationCalls++;
            return 'Food is up 34%.';
          case 'suggestCategory':
            generationCalls++;
            return 'Transport';
        }
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      AppleIntelligence.resetAvailabilityForTest();
    });

    const fact = Insight(
      title: 'Food is up 34%',
      detail: r'$670 vs a $500 average',
      tone: InsightTone.warn,
      icon: 'fork.knife',
    );

    test(
      'unavailable devices skip model generation and show Insights',
      () async {
        if (AppleIntelligence.isPreview) return;
        final answer = await AppleIntelligence.summarizeInsights(const [fact]);
        expect(answer?.source, CoachSource.rules);
        expect(answer?.text, isNotEmpty);
        expect(availabilityCalls, 1);
        expect(generationCalls, 0);
      },
    );

    test('a newly available model replaces the rule result', () async {
      if (AppleIntelligence.isPreview) return;
      final first = await AppleIntelligence.summarizeInsights(const [fact]);
      expect(first?.source, CoachSource.rules);

      available = true;
      expect(await AppleIntelligence.refreshAvailability(), isTrue);
      final second = await AppleIntelligence.summarizeInsights(const [fact]);
      expect(second?.source, CoachSource.appleIntelligence);
      expect(second?.text, 'Food is up 34%.');
      expect(generationCalls, 1);
      expect(availabilityCalls, 2);
    });

    test('category output remains constrained to the allowed list', () async {
      if (AppleIntelligence.isPreview) return;
      available = true;
      final suggested = await AppleIntelligence.suggestCategory('Uber home', [
        'Food',
        'Transport',
      ]);
      expect(suggested?.category, 'Transport');
      expect(suggested?.source, CoachSource.appleIntelligence);
      expect(generationCalls, 1);
    });
  });
}
