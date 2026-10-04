import 'package:flutter/material.dart';

import '../services/apple_intelligence.dart';
import '../services/insights.dart';
import '../store/settings_store.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';

/// A compact, contextual entry point to the on-device coach.
///
/// The supplied facts are calculated by the calling screen. The model only
/// explains those facts, so the card can sit beside charts and plans without
/// becoming a second, less reliable calculator. Without Apple Intelligence the
/// same card shows rule-based copy labelled "Insights".
class ContextAiCoach extends StatefulWidget {
  final List<Insight> facts;

  const ContextAiCoach({super.key, required this.facts});

  @override
  State<ContextAiCoach> createState() => _ContextAiCoachState();
}

class _ContextAiCoachState extends State<ContextAiCoach>
    with WidgetsBindingObserver {
  CoachAnswer? _summary;
  late String _fingerprint;
  int _requestId = 0;

  String _fingerprintFor(List<Insight> facts) =>
      facts.map((i) => '${i.title}\u001f${i.detail}').join('\u001e');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppleIntelligence.available.addListener(_load);
    _fingerprint = _fingerprintFor(widget.facts);
    _load();
  }

  @override
  void didUpdateWidget(covariant ContextAiCoach oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _fingerprintFor(widget.facts);
    if (next == _fingerprint) return;
    _fingerprint = next;
    _summary = null;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Apple Intelligence may be switched on or finish downloading while the
    // app is in the background; a change notifies [available] and reloads.
    if (state == AppLifecycleState.resumed) {
      AppleIntelligence.refreshAvailability();
    }
  }

  void _load() {
    final requestId = ++_requestId;
    AppleIntelligence.summarizeInsights(widget.facts).then((value) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _summary = value);
    });
  }

  @override
  void dispose() {
    _requestId++;
    AppleIntelligence.available.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null || widget.facts.isEmpty) {
      return const SizedBox.shrink();
    }
    final oc = context.oc;
    final source = summary.source;
    return Semantics(
      button: true,
      label: '${source.title}. ${summary.text}',
      hint: 'Opens short coaching choices',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.light();
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _ContextCoachSheet(
              facts: List<Insight>.of(widget.facts),
              initialAnswer: summary,
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: ExpndColors.gold.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(ExpndRadius.card),
            border: Border.all(color: ExpndColors.gold.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sfIcon(source.icon), size: 13, color: oc.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: oc.accent,
                      ),
                    ),
                  ),
                  Text(
                    'Ask',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: oc.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(sfIcon('chevron.right'), size: 10, color: oc.accent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: oc.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextCoachSheet extends StatefulWidget {
  final List<Insight> facts;
  final CoachAnswer initialAnswer;

  const _ContextCoachSheet({required this.facts, required this.initialAnswer});

  @override
  State<_ContextCoachSheet> createState() => _ContextCoachSheetState();
}

class _ContextCoachSheetState extends State<_ContextCoachSheet> {
  late CoachAnswer _answer;
  AiCoachPrompt _selected = AiCoachPrompt.summary;
  final Map<AiCoachPrompt, CoachAnswer> _cache = {};
  bool _loading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _answer = widget.initialAnswer;
    _cache[AiCoachPrompt.summary] = _answer;
  }

  Future<void> _ask(AiCoachPrompt prompt) async {
    Haptics.light();
    final cached = _cache[prompt];
    if (cached != null) {
      _requestId++;
      setState(() {
        _selected = prompt;
        _answer = cached;
        _loading = false;
      });
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _selected = prompt;
      _loading = true;
    });
    final result = await AppleIntelligence.generateInsight(
      widget.facts,
      prompt: prompt,
    );
    if (!mounted || requestId != _requestId) return;
    setState(() {
      if (result != null) {
        _answer = result;
        _cache[prompt] = result;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final source = _answer.source;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: oc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: oc.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: oc.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(sfIcon(source.icon), size: 18, color: oc.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: oc.text,
                      ),
                    ),
                    Text(
                      source.subtitle,
                      style: TextStyle(fontSize: 11, color: oc.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(sfIcon('xmark'), size: 17, color: oc.muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 86),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: oc.surface,
              borderRadius: BorderRadius.circular(ExpndRadius.card),
              border: Border.all(color: oc.border),
            ),
            child: _loading
                ? Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: oc.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        source.isAi ? 'Thinking on your phone…' : 'Loading…',
                        style: TextStyle(fontSize: 12, color: oc.muted),
                      ),
                    ],
                  )
                : Text(
                    _answer.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: oc.text,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _choice(AiCoachPrompt.focus, 'Focus'),
              _choice(AiCoachPrompt.win, 'Good news'),
              _choice(AiCoachPrompt.nextStep, 'Next step'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice(AiCoachPrompt prompt, String label) {
    final oc = context.oc;
    final selected = _selected == prompt;
    return GestureDetector(
      onTap: () => _ask(prompt),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? ExpndColors.gold : oc.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? ExpndColors.goldDark : oc.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? ExpndColors.ink : oc.text,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }
}
