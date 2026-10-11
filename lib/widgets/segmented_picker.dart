import 'package:flutter/material.dart';

import '../store/settings_store.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';

/// One option in a [SegmentedPicker].
class SegmentOption<T> {
  final T value;

  /// Short label, shown upper-cased.
  final String label;

  /// Fuller name read by assistive tech; defaults to [label].
  final String? semanticLabel;

  /// Optional SF symbol name shown before the label.
  final String? icon;

  /// Fill when selected (defaults to brand gold) and the text/icon colour on
  /// it (defaults to ink). Lets a picker keep meaning in colour — income
  /// green, expense red — while sharing the one shape.
  final Color? color;
  final Color? onColor;

  const SegmentOption({
    required this.value,
    required this.label,
    this.semanticLabel,
    this.icon,
    this.color,
    this.onColor,
  });
}

/// The app's one even, rounded segment control — Home's and History's type
/// filters, Add's entry type, Plan's sections and Analytics' periods — so the
/// pickers can't drift into different styles again.
class SegmentedPicker<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final double height;

  const SegmentedPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(ExpndRadius.card),
        border: Border.all(color: oc.border),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Builder(
                builder: (context) {
                  final on = option.value == selected;
                  final fg = on
                      ? (option.onColor ?? ExpndColors.ink)
                      : oc.muted;
                  return Semantics(
                    button: true,
                    selected: on,
                    label: option.semanticLabel ?? option.label,
                    excludeSemantics: true,
                    onTap: () => onSelected(option.value),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Haptics.light();
                        onSelected(option.value);
                      },
                      child: AnimatedContainer(
                        duration: motion,
                        curve: Curves.easeOut,
                        height: height,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on
                              ? (option.color ?? ExpndColors.gold)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            ExpndRadius.card - 4,
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (option.icon != null) ...[
                                  Icon(sfIcon(option.icon!), size: 13, color: fg),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  option.label.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                    color: fg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
