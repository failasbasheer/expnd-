import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// Full screen on iPad, landscape phones and tablets, without stretching:
/// past [maxWidth] the whole app (routes, sheets, dialogs) sits in a centred
/// column on the page colour. Cards, rows and the tab bar were designed at
/// phone width and read badly stretched across 13 inches.
class ReadableColumn extends StatelessWidget {
  final Widget child;
  const ReadableColumn({super.key, required this.child});

  static const double maxWidth = 720;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;
    final oc = context.oc;
    return ColoredBox(
      color: oc.bg,
      child: Center(
        child: Container(
          width: maxWidth,
          // A hairline at each side so the column reads as deliberate.
          decoration: BoxDecoration(
            border: Border.symmetric(
              vertical: BorderSide(color: oc.border.withValues(alpha: 0.6)),
            ),
          ),
          // Children size themselves from MediaQuery, so tell them the
          // column is the screen. Side insets belong to the outer edges.
          child: MediaQuery(
            data: media.copyWith(
              size: Size(maxWidth, media.size.height),
              padding: media.padding.copyWith(left: 0, right: 0),
              viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
              viewInsets: media.viewInsets.copyWith(left: 0, right: 0),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
