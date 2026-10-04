import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';
import '../widgets/app_header.dart';
import 'add_transaction.dart';

/// The review desk for amounts logged outside the app.
///
/// A widget button or a Siri phrase knows an amount and nothing else — not the
/// account it left, not what it was for. Rather than guess (and quietly bend
/// every budget and balance that depends on the answer), those captures wait
/// here until the user says. Filing one opens the normal add-transaction
/// screen pre-filled, so there is exactly one place in the app where a
/// transaction gets written.
Future<void> showCaptureInbox(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const CaptureInboxScreen(),
    ),
  );
}

class CaptureInboxScreen extends StatelessWidget {
  const CaptureInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final code = context.watch<SettingsStore>().currencyCode;
    final captures = store.pendingCaptures;

    return Scaffold(
      backgroundColor: oc.bg,
      appBar: ExpndPageBar(
        title: 'To file',
        actions: [
          HeaderAction(
            icon: 'xmark',
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Close capture inbox',
          ),
        ],
      ),
      body: captures.isEmpty
          ? _EmptyState(oc: oc)
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                ExpndSpacing.scrollBottomUnderTabBar(context),
              ),
              itemCount: captures.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) return _Explainer(oc: oc, count: captures.length);
                return _CaptureRow(capture: captures[i - 1], code: code);
              },
            ),
    );
  }
}

class _Explainer extends StatelessWidget {
  final ExpndColors oc;
  final int count;
  const _Explainer({required this.oc, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$count ${count == 1 ? "amount" : "amounts"} logged from a widget or '
        'Siri. They are not in your balances yet — assign an account and '
        'category to file them.',
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: oc.muted,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ExpndColors oc;
  const _EmptyState({required this.oc});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sfIcon('tray'), size: 30, color: oc.muted),
            const SizedBox(height: 14),
            Text(
              'Nothing to file',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Amounts you log from the EXPND widget or by asking Siri land '
              'here, waiting to be categorised.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureRow extends StatelessWidget {
  final PendingCapture capture;
  final String code;
  const _CaptureRow({required this.capture, required this.code});

  /// The category the user picked while capturing, if any — a custom one by id,
  /// else a built-in by name. Null covers both "didn't pick" and a custom
  /// category deleted between capturing and filing.
  String? _categoryName(BuildContext context) {
    final id = capture.customCategoryId;
    if (id != null) {
      return context.read<AppStore>().customCategoryFor(id)?.name;
    }
    return capture.category?.raw;
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final category = _categoryName(context);

    return NeoPopElevated(
      faceColor: oc.surface,
      depthColor: oc.edge,
      borderColor: oc.border,
      depth: 0,
      cornerRadius: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatCurrency(capture.amount, code),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: oc.text,
                    ),
                  ),
                ),
                NeoPopTag(
                  text: _sourceLabel(capture.source),
                  bg: oc.card,
                  fg: oc.muted,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (capture.note.isNotEmpty) capture.note,
                // Only Quick Add captures carry a category — the widget and
                // Siri have nowhere to pick one.
                ?category,
                _when(capture.capturedAt),
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: NeoPopButton(
                    onPressed: () {
                      Haptics.light();
                      showAddTransaction(context, filing: capture);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'FILE',
                          style: ExpndType.label(
                            ExpndColors.ink,
                          ).copyWith(fontSize: 12, letterSpacing: 1.2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _DiscardButton(capture: capture),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _sourceLabel(String source) {
    switch (source) {
      case 'siri':
        return 'SIRI';
      case 'shortcut':
        return 'SHORTCUT';
      case 'backtap':
        return 'BACK TAP';
      case 'quick':
        return 'Quick add';
      default:
        return 'WIDGET';
    }
  }

  /// Captures are filed within a day or two of being taken, so a relative
  /// stamp reads better than a date here — "2h ago" is what the user needs to
  /// remember what the amount was.
  static String _when(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.day}/${at.month}';
  }
}

class _DiscardButton extends StatelessWidget {
  final PendingCapture capture;
  const _DiscardButton({required this.capture});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        Haptics.light();
        // A mis-tapped preset is the likely reason to be here, and the capture
        // was never in the ledger — but it is also the only record of it, so
        // confirm before it goes.
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: oc.surface,
            title: Text(
              'DISCARD CAPTURE?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: oc.text,
              ),
            ),
            content: Text(
              'This amount will be forgotten. It was never added to your '
              'balances.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('KEEP', style: TextStyle(color: oc.muted)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'DISCARD',
                  style: TextStyle(color: ExpndColors.red),
                ),
              ),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        context.read<AppStore>().deletePendingCapture(capture);
      },
      child: Container(
        height: 44,
        width: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: oc.border, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(sfIcon('trash'), size: 15, color: oc.muted),
      ),
    );
  }
}
