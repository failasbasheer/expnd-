import 'package:flutter/material.dart';
import '../theme/expnd_theme.dart';
import '../store/settings_store.dart';

/// A flat face sitting on a hard, un-blurred bottom-right "plinth" — the
/// signature CRED neoPOP elevation. The depth block is reserved in layout via
/// trailing/bottom padding so siblings don't overlap it.
class NeoPopElevated extends StatelessWidget {
  final Widget child;
  final Color? faceColor;
  final Color? depthColor;
  final Color? borderColor;
  final double depth;
  final double cornerRadius;
  final double borderWidth;

  const NeoPopElevated({
    super.key,
    required this.child,
    this.faceColor,
    this.depthColor,
    this.borderColor,
    this.depth = 0,
    this.cornerRadius = ExpndRadius.card,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final face = faceColor ?? oc.surface;
    final depthC = depthColor ?? oc.edge;
    final borderC = borderColor ?? oc.border;
    final radius = BorderRadius.circular(cornerRadius);

    return Padding(
      padding: EdgeInsets.only(right: depth, bottom: depth),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hard depth block, offset toward bottom-right.
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(depth, depth),
              child: DecoratedBox(
                decoration: BoxDecoration(color: depthC, borderRadius: radius),
              ),
            ),
          ),
          // Face fills the whole box so it never half-covers a fixed-size cell
          // (e.g. grid tiles). The content below still sizes the stack when the
          // parent gives loose constraints, and is centered when it doesn't.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: face,
                borderRadius: radius,
                border: Border.all(color: borderC, width: borderWidth),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A pressable neoPOP "plunk" button: the face presses down-right into its
/// depth block on touch, then springs back.
class NeoPopButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final Color faceColor;
  final Color depthColor;
  final double depth;
  final double cornerRadius;
  final bool shine;
  final Color? shineColor;
  final bool enabled;

  /// Optional hairline around the face. Used to keep a light-coloured face
  /// (e.g. the gold FAB) from dissolving into a light background.
  final Color? borderColor;

  NeoPopButton({
    super.key,
    required this.child,
    required this.onPressed,
    Color? faceColor,
    Color? depthColor,
    this.depth = 2,
    this.cornerRadius = ExpndRadius.button,
    this.shine = false,
    this.shineColor,
    this.enabled = true,
    this.borderColor,
  }) : faceColor = faceColor ?? ExpndColors.gold,
       depthColor = depthColor ?? ExpndColors.goldDark;

  @override
  State<NeoPopButton> createState() => _NeoPopButtonState();
}

class _NeoPopButtonState extends State<NeoPopButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    if (v) Haptics.medium();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.cornerRadius);
    final d = widget.depth;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => _set(true) : null,
      onTapUp: widget.enabled
          ? (_) {
              _set(false);
              widget.onPressed();
            }
          : null,
      onTapCancel: () => _set(false),
      child: Padding(
        padding: EdgeInsets.only(right: d, bottom: d),
        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(d, d),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.depthColor,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              offset: _pressed ? const Offset(0, 0) : Offset.zero,
              child: Transform.translate(
                offset: _pressed ? Offset(d, d) : Offset.zero,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: widget.faceColor,
                    borderRadius: radius,
                    border: widget.borderColor != null
                        ? Border.all(color: widget.borderColor!, width: 1.5)
                        : null,
                  ),
                  child: Stack(
                    children: [
                      widget.child,
                      if (widget.shine)
                        Positioned.fill(
                          child: NeoPopShine(
                            color:
                                widget.shineColor ??
                                Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two forward-leaning translucent stripes, mirroring the highlight sweep on
/// CRED neoPOP primary buttons.
class NeoPopShine extends StatelessWidget {
  final Color color;
  const NeoPopShine({super.key, required this.color});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _ShinePainter(color)));
}

class _ShinePainter extends CustomPainter {
  final Color color;
  _ShinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final skew = h * 0.42;
    final paint = Paint()..color = color;
    void stripe(double x, double width) {
      final p = Path()
        ..moveTo(x, 0)
        ..lineTo(x + width, 0)
        ..lineTo(x + width - skew, h)
        ..lineTo(x - skew, h)
        ..close();
      canvas.drawPath(p, paint);
    }

    stripe(w * 0.80, w * 0.055);
    stripe(w * 0.90, w * 0.028);
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.color != color;
}

/// Flat, rectangular status tag.
class NeoPopTag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final double cornerRadius;

  const NeoPopTag({
    super.key,
    required this.text,
    required this.bg,
    required this.fg,
    this.cornerRadius = ExpndRadius.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Text(
        text,
        style: ExpndType.label(fg).copyWith(fontSize: 11, letterSpacing: 0.2),
      ),
    );
  }
}
