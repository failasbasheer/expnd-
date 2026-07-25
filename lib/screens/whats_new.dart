import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/settings_store.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';

/// Bumped every release that ships user-facing features. When a user's stored
/// [SettingsStore.whatsNewSeenVersion] is behind this number, the carousel runs
/// once at launch and then records this number, so the same build never shows
/// it twice.
///
/// The app dropped `package_info_plus`, so there's no runtime build number to
/// key off — this hand-maintained int is the source of truth. Increment it (and
/// refresh [_features]) with every update that's worth telling people about.
const int kWhatsNewVersion = 2;

/// Pushes the What's New carousel and records that this version was seen once
/// it's dismissed — whether the user stepped through every page or skipped.
Future<void> showWhatsNew(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const WhatsNewScreen(),
    ),
  );
}

/// One page of the tour.
class _Feature {
  final String icon;
  final String title;
  final String body;
  const _Feature(this.icon, this.title, this.body);
}

/// The features to show, most-loved first. Keep the copy short — a page the eye
/// can take in at a glance is a page people actually read.
const List<_Feature> _features = [
  _Feature(
    'bell.fill',
    'Reminders, your way',
    'Write your own nudge, pick a tone and choose the days — plus alerts '
        'for a bill due tomorrow, going over budget, or a goal reached. '
        'All on-device.',
  ),
  _Feature(
    'calendar.badge.clock',
    'See what’s coming',
    'Your bills, subscriptions and EMIs for the next 30 days — with a '
        'safe-to-spend figure.',
  ),
  _Feature(
    'arrow.left.arrow.right',
    'Loans & lending',
    'Track EMIs and money you’ve lent or borrowed, and log repayments '
        'as they happen.',
  ),
  _Feature(
    'bolt.fill',
    'Smart insights',
    'Your dashboard now flags budgets running hot and unusual spending '
        'before they surprise you.',
  ),
  _Feature(
    'lock.shield.fill',
    'Back up everything',
    'Save your whole ledger to one file and restore it on a new phone. '
        'It never leaves your device.',
  ),
  _Feature(
    'chart.pie.fill',
    'Tags & split receipts',
    'Tag spending across categories, and split one receipt into the '
        'things it was really for.',
  ),
  _Feature(
    'eye.slash',
    'Hide your balances',
    'Tap the eye to mask every amount on screen.',
  ),
];

class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _features.length - 1;

  /// Marks this version seen so it never reappears, then closes the tour.
  void _finish() {
    context.read<SettingsStore>().whatsNewSeenVersion = kWhatsNewVersion;
    Navigator.of(context).pop();
  }

  void _next() {
    if (_isLast) {
      Haptics.success();
      _finish();
      return;
    }
    Haptics.light();
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Scaffold(
      backgroundColor: oc.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: page counter on the left, Skip on the right ──────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Text(
                    '${_page + 1} / ${_features.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: oc.muted,
                    ),
                  ),
                  const Spacer(),
                  // Hidden on the last page, where the primary button finishes.
                  AnimatedOpacity(
                    opacity: _isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _isLast
                          ? null
                          : () {
                              Haptics.light();
                              _finish();
                            },
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: oc.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Fixed header ──────────────────────────────────────────────────
            const SizedBox(height: 8),
            Text(
              'WHAT’S NEW',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: oc.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your first update — shaped by your feedback',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
            // ── Swipeable feature pages ───────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _features.length,
                onPageChanged: (i) {
                  Haptics.light();
                  setState(() => _page = i);
                },
                itemBuilder: (_, i) => _page_(oc, _features[i]),
              ),
            ),
            // ── Dots ──────────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _features.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? ExpndColors.gold : oc.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // ── Primary action ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: NeoPopButton(
                onPressed: _next,
                depth: 4,
                cornerRadius: 8,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLast ? 'GET STARTED' : 'NEXT',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: ExpndColors.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _isLast
                              ? sfIcon('checkmark')
                              : sfIcon('chevron.right'),
                          size: 13,
                          color: ExpndColors.ink,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page_(ExpndColors oc, _Feature f) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Concentric gold rings behind the glyph, echoing the onboarding hero.
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: ExpndColors.gold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: ExpndColors.gold.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(sfIcon(f.icon), size: 50, color: oc.accent),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            f.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            f.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: oc.muted,
            ),
          ),
        ],
      ),
    );
  }
}
