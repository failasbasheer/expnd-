import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';

/// Keeps optional controls discoverable without making every visit a long form.
/// Expanded content stays mounted so collapsing never discards unfinished input.
class DisclosureSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool initiallyExpanded;

  /// Optional SF symbol name for a tinted leading tile, so a list of
  /// sections can be scanned by shape and colour instead of read row by row.
  final String? icon;
  final Color? tint;

  const DisclosureSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
    this.icon,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
        backgroundColor: oc.surface,
        collapsedBackgroundColor: oc.surface,
        iconColor: oc.accent,
        collapsedIconColor: oc.muted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ExpndRadius.card),
          side: BorderSide(color: oc.border),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ExpndRadius.card),
          side: BorderSide(color: oc.border),
        ),
        leading: icon == null
            ? null
            : ExcludeSemantics(
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  // Same tinted, rounded tile as the transaction rows.
                  decoration: BoxDecoration(
                    color: (tint ?? oc.accent).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (tint ?? oc.accent).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    sfIcon(icon!),
                    size: 17,
                    color: tint ?? oc.accent,
                  ),
                ),
              ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: oc.text,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: oc.muted),
        ),
        children: [child],
      ),
    );
  }
}
