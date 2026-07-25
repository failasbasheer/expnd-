import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';
import 'neopop.dart';

/// A titled block of rows — the shape every settings/plan section wears.
///
/// Lived as a private helper on the old 4k-line Profile screen; lifted out
/// when that screen split into Plan and Settings so both keep the same shape
/// rather than drifting apart.
Widget sectionCard(ExpndColors oc, String title, Widget child) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: oc.muted)),
      ),
      NeoPopElevated(
        faceColor: oc.surface,
        depthColor: oc.edge,
        borderColor: oc.border,
        depth: 4,
        cornerRadius: 6,
        child: child,
      ),
    ],
  );
}

/// The hairline between two rows of a [sectionCard]. Inset to clear the row
/// icons, so the rule starts where the text does.
Widget sectionDivider(ExpndColors oc) => Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Container(height: 1, color: oc.border),
    );
