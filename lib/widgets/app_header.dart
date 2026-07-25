import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import 'neopop.dart';

/// One header, worn by every tab.
///
/// Each tab used to invent its own top: the dashboard had no title at all (it
/// opened straight into an elevated month card), analytics had a gold icon
/// chip, wallet and profile had bare text, and only wallet carried an action —
/// a labelled "+ ADD" button that sat at a different height to everything else.
/// Switching tabs moved the top line around. The grammar is fixed here so it
/// can't drift again:
///
///     [chip] TITLE .................. [action] [action]
///     ( optional second row — e.g. the month strip )
///     ─────────────────────────────────────────────────  hairline
///
/// The chip carries the same glyph as that tab's tab-bar icon, so the top of
/// the screen and the bottom of the screen agree on where you are.
class ExpndHeader extends StatelessWidget {
  /// SF Symbol name for the identity chip. Ignored when [leading] is supplied.
  final String? icon;
  final String? title;

  /// Replaces the chip + title block. The dashboard passes its once-a-day
  /// greeting here, which crossfades against the wordmark.
  final Widget? leading;

  /// Right-hand controls, in reading order. Use [HeaderAction].
  final List<Widget> actions;

  /// Optional second row, drawn under the title inside the same hairline.
  final Widget? below;

  const ExpndHeader({
    super.key,
    this.icon,
    this.title,
    this.leading,
    this.actions = const [],
    this.below,
  }) : assert(leading != null || (icon != null && title != null),
            'a header needs either a leading block or an icon + title');

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: oc.border, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ExpndHeaderMetrics.gutter, 6, ExpndHeaderMetrics.gutter, 6),
            child: Row(
              children: [
                // Expanded + Align, not Flexible + Spacer: those are both
                // flex:1, so they split the free space evenly and the half the
                // title didn't use became dead space — leaving the actions
                // stranded mid-row instead of on the right gutter. Expanded is
                // still bounded by what the actions leave, so a long title
                // ellipsises rather than pushing them off a 320pt screen.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leading ?? HeaderTitle(icon: icon!, title: title!),
                  ),
                ),
                for (final a in actions) ...[const SizedBox(width: 8), a],
              ],
            ),
          ),
          if (below != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ExpndHeaderMetrics.gutter, 0, ExpndHeaderMetrics.gutter, 6),
              child: below!,
            ),
        ],
      ),
    );
  }
}

/// Geometry shared by every header, so the top of the screen keeps one shape
/// across tabs.
class ExpndHeaderMetrics {
  /// Side padding — matches the 16pt gutter the screens' lists already use.
  static const double gutter = 16;

  /// The identity chip. A label, not a target, so it stays small.
  static const double chip = 28;

  /// Action face. Larger than the chip because this one is actually tapped.
  static const double action = 36;

  /// neoPOP depth reserved under a primary action, so primary and secondary
  /// actions line their faces up.
  static const double actionDepth = 2;

  /// Corner radius for header furniture — chips and actions alike.
  static const double radius = 6;
}

/// The gold identity chip: the tab's tab-bar glyph on a gold square.
class HeaderChip extends StatelessWidget {
  final String icon;
  const HeaderChip(this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: ExpndHeaderMetrics.chip,
        height: ExpndHeaderMetrics.chip,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ExpndColors.gold,
          borderRadius: BorderRadius.circular(ExpndHeaderMetrics.radius),
        ),
        child: Icon(sfIcon(icon), size: 13, color: ExpndColors.ink),
      );
}

/// Chip + title, the default leading block.
class HeaderTitle extends StatelessWidget {
  final String icon;
  final String title;
  const HeaderTitle({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HeaderChip(icon),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: oc.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// A square header control.
///
/// [primary] is the tab's own main action and gets the gold neoPOP face with a
/// real press; everything else is a quiet outlined square. Icon-only on
/// purpose: a labelled button in the header competes with the title beside it,
/// and at these sizes the label is what forces the button out of alignment
/// with its neighbours.
class HeaderAction extends StatelessWidget {
  final String? icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool primary;

  /// Small gold dot on the corner — "there's something waiting in here".
  final bool badge;

  /// Supplied instead of [icon] when the control owns its own glyph and tap
  /// handling (the privacy eye animates between two glyphs and writes straight
  /// to settings, so it stays one implementation rather than two).
  final Widget? child;

  const HeaderAction({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.primary = false,
    this.badge = false,
  }) : child = null;

  const HeaderAction.custom({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.badge = false,
  })  : icon = null,
        onPressed = null,
        primary = false;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    const size = ExpndHeaderMetrics.action;
    const depth = ExpndHeaderMetrics.actionDepth;

    Widget face;
    if (primary) {
      face = NeoPopButton(
        onPressed: onPressed ?? () {},
        depth: depth,
        cornerRadius: ExpndHeaderMetrics.radius,
        // The gold face dissolves into the near-white light background without
        // a hairline, exactly as the FAB does.
        borderColor: Theme.of(context).brightness == Brightness.light
            ? ExpndColors.ink.withValues(alpha: 0.85)
            : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(sfIcon(icon!), size: 15, color: ExpndColors.ink),
        ),
      );
    } else {
      // Padded to the same footprint a primary action occupies, so the faces
      // line up whichever kind of action a tab uses.
      face = Padding(
        padding: const EdgeInsets.only(right: depth, bottom: depth),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: oc.surface,
            borderRadius: BorderRadius.circular(ExpndHeaderMetrics.radius),
            border: Border.all(color: oc.border, width: 1),
          ),
          child: child ?? Icon(sfIcon(icon!), size: 15, color: oc.muted),
        ),
      );
      // A custom child brings its own gesture; a plain icon needs one.
      if (child == null) {
        face = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: face,
        );
      }
    }

    if (badge) {
      face = Stack(
        clipBehavior: Clip.none,
        children: [
          face,
          Positioned(
            right: 0,
            top: -1,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: ExpndColors.gold,
                shape: BoxShape.circle,
                border: Border.all(color: oc.bg, width: 1),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(button: true, label: semanticLabel, child: face);
  }
}
