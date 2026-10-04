import 'package:flutter_test/flutter_test.dart';

import 'package:expnd/services/insights.dart';
import 'package:expnd/services/apple_intelligence.dart';

void main() {
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
}
