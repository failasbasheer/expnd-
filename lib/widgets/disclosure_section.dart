import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// Keeps optional controls discoverable without making every visit a long form.
/// Expanded content stays mounted so collapsing never discards unfinished input.
class DisclosureSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool initiallyExpanded;

  const DisclosureSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
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
