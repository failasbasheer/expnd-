import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

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
        padding: const EdgeInsets.only(left: 2, bottom: 10),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.1,
            color: oc.muted,
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: oc.surface,
          borderRadius: BorderRadius.circular(ExpndRadius.card),
          border: Border.all(color: oc.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ExpndRadius.card),
          child: child,
        ),
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
