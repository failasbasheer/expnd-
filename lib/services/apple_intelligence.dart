import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'insights.dart';

enum AiCoachPrompt {
  summary('summary'),
  focus('focus'),
  win('win'),
  nextStep('next_step');

  final String wireName;
  const AiCoachPrompt(this.wireName);
}

/// Where a coach answer or category suggestion came from. Screens label the
/// result from this so rule-based copy is never presented as AI.
enum CoachSource {
  appleIntelligence('AI Coach', 'Private • On-device • Short answers'),
  preview('AI Coach Preview', 'Simulator preview • Short answers'),
  rules('Insights', 'Private • Calculated from your data');

  final String title;
  final String subtitle;
  const CoachSource(this.title, this.subtitle);

  bool get isAi => this != CoachSource.rules;
  String get icon => isAi ? 'sparkles' : 'lightbulb';
}

class CoachAnswer {
  final String text;
  final CoachSource source;
  const CoachAnswer(this.text, this.source);
}

typedef CategorySuggestion = ({String category, CoachSource source});

/// Optional access to Apple's on-device Foundation Models framework.
///
/// Money is still calculated by [buildInsights]. The model only turns a few
/// already-verified facts into a short explanation. Devices without Apple
/// Intelligence (for example iPhone 15, older iOS, or Android) get the same
/// coach built from deterministic rules instead.
class AppleIntelligence {
  static const _channel = MethodChannel('com.expnd.app/apple_intelligence');
  static const _demoSeed = bool.fromEnvironment('EXPND_SEED_DEMO');

  /// The Apple model is unavailable in Simulator. Demo-seeded debug builds use
  /// grounded local copy so the complete interaction can still be reviewed.
  static bool get isPreview => kDebugMode && _demoSeed;

  /// Last known model availability. Widgets listen to this to regenerate
  /// their copy when Apple Intelligence is switched on or finishes
  /// downloading.
  static final ValueNotifier<bool> available = ValueNotifier(false);
  static bool _checked = false;
  static Future<bool>? _pendingCheck;
  // Bounded, memory-only cache. Identical requests share generation work,
  // including requests started by availability listeners on several screens.
  static final _answers = <String, Future<CoachAnswer?>>{};

  /// Cached availability; only the first call reaches the platform.
  static Future<bool> isAvailable() async {
    if (_checked) return available.value;
    return refreshAvailability();
  }

  /// Re-queries the platform, sharing one in-flight request between callers.
  /// Call on app resume, since the user may have changed the system setting.
  static Future<bool> refreshAvailability() {
    return _pendingCheck ??= _queryAvailability().then((value) {
      _checked = true;
      if (available.value != value) _answers.clear();
      available.value = value;
      _pendingCheck = null;
      return value;
    });
  }

  static Future<bool> _queryAvailability() async {
    if (isPreview) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @visibleForTesting
  static void resetAvailabilityForTest() {
    _checked = false;
    _pendingCheck = null;
    _answers.clear();
    available.value = false;
  }

  static Future<CoachAnswer?> summarizeInsights(List<Insight> insights) async {
    return generateInsight(insights, prompt: AiCoachPrompt.summary);
  }

  /// Suggests one of the app's existing categories from a merchant or note.
  /// The returned category is always a member of [allowedCategories];
  /// free-form model output is never allowed to become saved financial data.
  static Future<CategorySuggestion?> suggestCategory(
    String description,
    List<String> allowedCategories,
  ) async {
    final note = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (note.length < 3 || allowedCategories.isEmpty) return null;

    if (isPreview) {
      final category = ruleCategory(note, allowedCategories);
      return category == null
          ? null
          : (category: category, source: CoachSource.preview);
    }

    final modelCategory = await _modelCategory(note, allowedCategories);
    if (modelCategory != null) {
      return (category: modelCategory, source: CoachSource.appleIntelligence);
    }
    final category = ruleCategory(note, allowedCategories);
    return category == null
        ? null
        : (category: category, source: CoachSource.rules);
  }

  static Future<String?> _modelCategory(
    String note,
    List<String> allowedCategories,
  ) async {
    if (!await isAvailable()) return null;
    try {
      final raw = await _channel.invokeMethod<String>('suggestCategory', {
        'description': note.substring(0, note.length > 240 ? 240 : note.length),
        'categories': allowedCategories,
      });
      final answer = raw?.trim();
      if (answer == null) return null;
      for (final category in allowedCategories) {
        if (category.toLowerCase() == answer.toLowerCase()) return category;
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Returns a coach answer for [prompt]. Uses Apple's model when available
  /// and its reply passes the grounding check; otherwise falls back to copy
  /// built directly from the verified facts.
  static Future<CoachAnswer?> generateInsight(
    List<Insight> insights, {
    required AiCoachPrompt prompt,
  }) async {
    if (insights.isEmpty) return null;
    await isAvailable();
    final facts = List<Insight>.unmodifiable(insights);
    final key = jsonEncode([
      prompt.wireName,
      for (final fact in facts) [fact.title, fact.detail, fact.tone.name],
    ]);
    final cached = _answers[key];
    if (cached != null) return cached;
    if (_answers.length >= 32) _answers.remove(_answers.keys.first);
    final pending = _generateInsight(facts, prompt: prompt);
    _answers[key] = pending;
    final answer = await pending;
    // An available model can fail transiently. Keep the fallback visible,
    // but let a later explicit request retry instead of caching the failure.
    if (answer?.source == CoachSource.rules &&
        available.value &&
        identical(_answers[key], pending)) {
      _answers.remove(key);
    }
    return answer;
  }

  static Future<CoachAnswer?> _generateInsight(
    List<Insight> insights, {
    required AiCoachPrompt prompt,
  }) async {
    if (isPreview) {
      return CoachAnswer(ruleResponse(insights, prompt), CoachSource.preview);
    }

    final modelText = await _modelInsight(insights, prompt);
    if (modelText != null) {
      return CoachAnswer(modelText, CoachSource.appleIntelligence);
    }
    return CoachAnswer(ruleResponse(insights, prompt), CoachSource.rules);
  }

  static Future<String?> _modelInsight(
    List<Insight> insights,
    AiCoachPrompt prompt,
  ) async {
    if (!await isAvailable()) return null;

    final facts = insights
        .take(3)
        .map((i) => {'title': i.title, 'detail': i.detail})
        .toList(growable: false);

    try {
      final raw = await _channel.invokeMethod<String>('summarizeInsights', {
        'facts': facts,
        'mode': prompt.wireName,
      });
      final summary = raw?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (summary == null || summary.isEmpty || summary.length > 320) {
        return null;
      }

      // A model may rephrase prose, but it may not invent a figure beside
      // someone's money. Reject any response containing a numeric token that
      // wasn't present in the verified input.
      final source = facts.expand((f) => [f['title']!, f['detail']!]).join(' ');
      return isGroundedSummary(summary, source) ? summary : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Deterministic coach copy assembled only from the verified facts.
  @visibleForTesting
  static String ruleResponse(List<Insight> insights, AiCoachPrompt prompt) {
    final primary = insights.first;
    switch (prompt) {
      case AiCoachPrompt.summary:
        return '${primary.title}. ${primary.detail}.';
      case AiCoachPrompt.focus:
        return 'Focus here: ${primary.title}. ${primary.detail}.';
      case AiCoachPrompt.win:
        final wins = insights.where((i) => i.tone == InsightTone.good);
        if (wins.isEmpty) return 'No clear win yet — keep logging.';
        final win = wins.first;
        return '${win.title}. ${win.detail}.';
      case AiCoachPrompt.nextStep:
        return 'Review “${primary.title}” and choose one small adjustment today.';
    }
  }

  /// Keyword category matcher used when the model is unavailable. Keywords
  /// match whole words (with an optional plural), so "rent" does not match
  /// "parent" or "current".
  @visibleForTesting
  static String? ruleCategory(String description, List<String> allowed) {
    final text = description.toLowerCase();
    const signals = <String, List<String>>{
      'Salary': ['salary', 'payroll', 'wage'],
      'Freelance': ['client', 'freelance', 'invoice'],
      'Investment': ['dividend', 'broker', 'investment'],
      'Rental Income': ['tenant', 'rental income'],
      'Gift': ['gift'],
      'Groceries': ['grocery', 'groceries', 'supermarket', 'carrefour', 'lulu'],
      'Food': ['coffee', 'cafe', 'restaurant', 'lunch', 'dinner', 'talabat'],
      'Shopping': ['amazon', 'mall', 'shopping', 'store'],
      'Entertainment': ['cinema', 'movie', 'game', 'concert'],
      'Transport': ['uber', 'careem', 'taxi', 'fuel', 'metro', 'petrol'],
      'Utilities': [
        'electric',
        'electricity',
        'water',
        'internet',
        'phone bill',
      ],
      'Rent': ['rent', 'landlord'],
      'Subscription': ['netflix', 'spotify', 'subscription'],
      'Insurance': ['insurance'],
      'Medical': ['pharmacy', 'doctor', 'clinic', 'hospital'],
      'Education': ['school', 'course', 'tuition', 'book'],
    };
    for (final entry in signals.entries) {
      if (allowed.contains(entry.key) &&
          entry.value.any((keyword) => _hasWord(text, keyword))) {
        return entry.key;
      }
    }
    return null;
  }

  static bool _hasWord(String text, String keyword) => RegExp(
    '(?<![a-z])${RegExp.escape(keyword)}(?:s|es)?(?![a-z])',
  ).hasMatch(text);

  static bool isGroundedSummary(String summary, String source) {
    final tokenPattern = RegExp(r'(?<!\d)\d+(?:[.,]\d+)*%?(?!\d)');
    final numericTokens = tokenPattern
        .allMatches(summary)
        .map((m) => m.group(0)!)
        .toSet();
    final sourceTokens = tokenPattern
        .allMatches(source)
        .map((m) => m.group(0)!)
        .toSet();
    return numericTokens.every(sourceTokens.contains);
  }
}
