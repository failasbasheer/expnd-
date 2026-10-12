import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';

/// Shared page title and actions. Optional context controls sit below the title.
class ExpndHeader extends StatelessWidget {
  /// Optional identity metadata; titles do not repeat the navigation icon.
  final String? icon;
  final String? title;

  /// Replaces the standard title block.
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
  }) : assert(
         leading != null || title != null,
         'a header needs either a leading block or a title',
       );

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return ColoredBox(
      // In glass mode the header sits on GlassHeaderLayout's frosted plate.
      color: ExpndGlass.enabled ? Colors.transparent : oc.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ExpndHeaderMetrics.gutter,
              12,
              ExpndHeaderMetrics.gutter,
              12,
            ),
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
                    child: leading ?? HeaderTitle(title: title!),
                  ),
                ),
                for (final a in actions) ...[const SizedBox(width: 4), a],
              ],
            ),
          ),
          if (below != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ExpndHeaderMetrics.gutter,
                0,
                ExpndHeaderMetrics.gutter,
                8,
              ),
              child: Align(alignment: Alignment.centerLeft, child: below!),
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

  /// Minimum touch target for every header action.
  static const double action = 44;

  /// Corner radius for header furniture — chips and actions alike.
  static const double radius = 12;
}

/// The shared page-title style: NeoPOP heavy, letter-spaced caps, as in 1.0.
///
/// Callers pass the plain title ('Wallet'); it is upper-cased for display and
/// read to assistive tech in its natural case, so VoiceOver says the word
/// instead of spelling out capitals.
class HeaderTitle extends StatelessWidget {
  final String title;
  const HeaderTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final spoken = title == 'EXPND' || title.isEmpty
        ? title
        : '${title[0]}${title.substring(1).toLowerCase()}';
    return Semantics(
      header: true,
      label: spoken,
      excludeSemantics: true,
      child: Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          color: oc.text,
        ),
      ),
    );
  }
}

/// A 44-point header action with a quiet optional primary tint.
///
class HeaderAction extends StatelessWidget {
  final String? icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool primary;
  final bool selected;

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
    this.selected = false,
    this.badge = false,
  }) : child = null;

  const HeaderAction.custom({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.badge = false,
    this.selected = false,
  }) : icon = null,
       onPressed = null,
       primary = false;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    const size = ExpndHeaderMetrics.action;
    // Header actions use the app's rounded-square button shape, scaled down
    // from the larger NeoPOP actions used in the body.
    final disc = Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: primary || selected
              ? oc.accent.withValues(alpha: 0.14)
              : oc.card,
          border: Border.all(
            color: primary || selected
                ? oc.accent.withValues(alpha: 0.55)
                : oc.border,
          ),
        ),
      ),
    );
    Widget face = SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          disc,
          child ??
              IconButton(
                onPressed: onPressed,
                style: IconButton.styleFrom(
                  foregroundColor: primary || selected ? oc.accent : oc.muted,
                  backgroundColor: Colors.transparent,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                icon: Icon(switch (icon) {
                  'plus' => Icons.add_rounded,
                  'xmark' => Icons.close_rounded,
                  _ => sfIcon(icon!),
                }, size: 20),
              ),
        ],
      ),
    );

    if (badge) {
      face = Stack(
        clipBehavior: Clip.none,
        children: [
          face,
          Positioned(
            right: 5,
            top: 4,
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

    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: Semantics(button: true, label: semanticLabel, child: face),
    );
  }
}

/// Uses the same title/action geometry on a Scaffold's app bar as on main tabs.
class ExpndPageBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  const ExpndPageBar({super.key, required this.title, this.actions = const []});

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: preferredSize.height,
    titleSpacing: ExpndHeaderMetrics.gutter,
    title: HeaderTitle(title: title),
    actions: [
      for (final action in actions)
        Padding(padding: const EdgeInsets.only(left: 4), child: action),
      const SizedBox(width: ExpndHeaderMetrics.gutter),
    ],
  );
}

/// [ExpndPageBar] for a pushed screen, ending in a close action. Focus is
/// dropped first so the keyboard does not flash over the previous route.
PreferredSizeWidget closablePageBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
}) => ExpndPageBar(
  title: title,
  actions: [
    ...actions,
    if (Navigator.of(context).canPop())
      HeaderAction(
        icon: 'xmark',
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).maybePop();
        },
        semanticLabel: 'Close ${title.toLowerCase()}',
      ),
  ],
);
