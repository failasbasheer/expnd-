import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional cloud AI for a personal Android build, via Claude Haiku 5.5.
///
/// Off in every normal build: it only switches on when the APK is built with
/// `--dart-define=EXPND_CLAUDE_KEY=...` (see tool/build_personal_apk.sh),
/// and only on Android — iPhones use Apple's on-device model instead. Store
/// builds carry no key and no INTERNET permission, so they stay offline.
///
/// What leaves the phone is deliberately small: the two or three insight
/// lines the app already calculated (category totals and comparisons), or a
/// single merchant/note when suggesting a category. Never accounts, balances
/// by name, or transaction history. Spend is capped twice: a hard monthly
/// limit on the Anthropic workspace the key belongs to, and a daily request
/// cap here.
class CloudCoach {
  CloudCoach._();

  static const _key = String.fromEnvironment('EXPND_CLAUDE_KEY');
  static const _model = 'claude-haiku-5-5';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  /// Requests allowed per calendar day on this phone.
  static const dailyLimit = 40;

  /// Lets tests switch the feature on without a real key.
  @visibleForTesting
  static bool? enabledOverride;

  static bool get enabled =>
      enabledOverride ??
      (_key.isNotEmpty &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android);

  /// Swappable in tests so no request leaves the machine.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(Map<String, dynamic> body)
  send = _post;

  // One short sentence that says what matters and, where it helps, what to
  // do — not a restatement of every figure. Worked examples matter more than
  // rules for a small model: without them it played safe and read the facts
  // back in two crowded sentences.
  static const _summaryInstructions = '''
You are the money coach inside a private budgeting app. The app gives you a
few facts it has already calculated and checked.

Write ONE sentence of at most 20 words that tells the person the single most
important thing, and when it helps, one small practical next step.

Rules:
- Use at most one number, copied exactly from the facts. Never calculate,
  estimate or invent a number, date, merchant or prediction.
- Plain, warm, everyday words. No greetings, lists, emoji or markdown.
- Never shame. No investment, tax, credit or legal advice.

Examples:
Facts: On pace to overspend. Heading for \$6,489.12 against \$3,000.00.
Coach: You're heading well past your \$3,000.00 budget, so hold off on extras for the rest of the month.

Facts: Groceries is up 40%. \$210.00 vs a \$150.00 average.
Coach: Groceries are running high this month, so a planned list for your next shop could help.

Facts: You finished ahead by \$324.83. Based on 69 transactions.
Coach: Nice work, you came out \$324.83 ahead, so consider moving some of it to savings.
''';

  static const _categoryInstructions =
      'Classify a transaction using only its short merchant or note. Reply '
      'with exactly one category from the supplied list. Do not add '
      'punctuation, explanation, or a category that is not listed.';

  /// Mode-specific ask, matching the on-device iOS prompts.
  static String _request(String mode) => switch (mode) {
    'focus' => 'Write the coach line about the one fact that needs attention first.',
    'win' => 'Write the coach line about the most encouraging fact, or kindly say there is none yet.',
    'next_step' => 'Write the coach line, focused on one small step for this week.',
    _ => 'Write the coach line for these facts.',
  };

  /// A short coach line from verified insight facts, or null (caller falls
  /// back to the app's own wording).
  static Future<String?> summarize(
    List<({String title, String detail})> facts,
    String mode,
  ) async {
    if (!enabled || facts.isEmpty || !await _takeQuota()) return null;
    final lines = [for (final f in facts) '- ${f.title}. ${f.detail}.'];
    return _ask(
      system: _summaryInstructions,
      prompt: '${_request(mode)}\n\nFacts:\n${lines.join('\n')}',
      // Room for the brief think plus one sentence; billed only as used.
      maxTokens: 600,
    );
  }

  /// One of [categories], or null.
  static Future<String?> category(String note, List<String> categories) async {
    if (!enabled || categories.isEmpty || !await _takeQuota()) return null;
    final answer = await _ask(
      system: _categoryInstructions,
      prompt: 'Note: $note\nAllowed categories: ${categories.join(', ')}',
      maxTokens: 300,
    );
    if (answer == null) return null;
    for (final c in categories) {
      if (c.toLowerCase() == answer.toLowerCase()) return c;
    }
    return null;
  }

  static Future<String?> _ask({
    required String system,
    required String prompt,
    required int maxTokens,
  }) async {
    final response = await send({
      'model': _model,
      'max_tokens': maxTokens,
      // A brief, low-effort think lets the model plan the one sentence
      // privately: with thinking off it sometimes broke a rule and then
      // corrected itself in the visible reply. Same speed, ~same cost.
      'thinking': {'type': 'adaptive'},
      'output_config': {'effort': 'low'},
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });
    if (response == null) return null;
    // A safety refusal or a cut-off reply is not something to show.
    if (response['stop_reason'] != 'end_turn') return null;
    final content = response['content'];
    if (content is! List) return null;
    final text = content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .whereType<String>()
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }

  static Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers
        ..contentType = ContentType.json
        ..set('x-api-key', _key)
        ..set('anthropic-version', '2023-06-01');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final text = await response.transform(utf8.decoder).join();
      // Over the workspace spend limit, rate limited, offline, etc.: quietly
      // fall back to the app's own wording.
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Counts one request against today's cap; false once it's used up.
  static Future<bool> _takeQuota() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = now.year * 10000 + now.month * 100 + now.day;
    final day = prefs.getInt('cloudCoachDay');
    final used = day == today ? prefs.getInt('cloudCoachCount') ?? 0 : 0;
    if (used >= dailyLimit) return false;
    await prefs.setInt('cloudCoachDay', today);
    await prefs.setInt('cloudCoachCount', used + 1);
    return true;
  }
}
