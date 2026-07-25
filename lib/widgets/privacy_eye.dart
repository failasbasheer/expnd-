import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/settings_store.dart';
import '../theme/sf_icons.dart';

/// The eye button: one tap masks every amount in the app, another reveals them.
///
/// It owns no state of its own — it flips `SettingsStore.amountsHidden`, which
/// the currency formatters read, so every screen watching the store repaints
/// masked in the same frame. Placed wherever a headline figure sits (dashboard
/// hero, wallet header); all instances drive the same switch.
class PrivacyEyeButton extends StatelessWidget {
  /// Ink colour for the glyph. Callers pass the colour of the surface it sits
  /// on — the gold hero card uses dark ink, the wallet bar uses muted grey.
  final Color color;
  final double size;

  /// Slack around the glyph, which is also the tap target. The default suits a
  /// bare eye sitting next to a label; the header passes a larger value so the
  /// button fills its action square edge to edge.
  final EdgeInsets padding;

  const PrivacyEyeButton({
    super.key,
    required this.color,
    this.size = 16,
    this.padding = const EdgeInsets.all(6),
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final hidden = settings.amountsHidden;

    return Semantics(
      button: true,
      label: hidden ? 'Show amounts' : 'Hide amounts',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.light();
          settings.amountsHidden = !hidden;
        },
        // Padding rather than a bare icon: the glyph is small, the tap target
        // shouldn't be.
        child: Padding(
          padding: padding,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              sfIcon(hidden ? 'eye.slash' : 'eye'),
              // Keyed so AnimatedSwitcher sees the swap as a new child.
              key: ValueKey(hidden),
              size: size,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
