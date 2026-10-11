import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/expnd_theme.dart';
import 'neopop.dart';

/// neoPOP card primitives reproduced from the CRED neoPOP UI kit
/// (credit card, transaction cell, score gauge). Painted in pure Flutter so
/// they carry no dependency on the kit's sample bank/merchant assets.

/// The subtle guilloche (concentric offset rings) printed across the credit
/// card face in the kit. Drawn faint so it reads as texture, not decoration.
class CardGuilloche extends StatelessWidget {
  final Color color;
  const CardGuilloche({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GuillochePainter(color)));
}

class _GuillochePainter extends CustomPainter {
  final Color color;
  _GuillochePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = color.withValues(alpha: 0.06);

    // Rings radiate from a focal point past the bottom-right corner, matching
    // the kit's sweeping pattern under the chip/holder area.
    final focus = Offset(size.width * 0.78, size.height * 1.15);
    for (double r = 40; r < size.width * 1.4; r += 16) {
      canvas.drawCircle(focus, r, paint);
    }
    // A few long diagonals for the woven look.
    final diag = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = color.withValues(alpha: 0.04);
    for (double x = -size.height; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), diag);
    }
  }

  @override
  bool shouldRepaint(_GuillochePainter old) => old.color != color;
}

/// The EMV chip glyph on the credit card.
class CardChip extends StatelessWidget {
  final Color color;
  const CardChip({super.key, this.color = const Color(0xFFD9C27A)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(painter: _ChipPainter()),
    );
  }
}

class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.black.withValues(alpha: 0.35);
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(0, h * 0.33), Offset(w, h * 0.33), p);
    canvas.drawLine(Offset(0, h * 0.66), Offset(w, h * 0.66), p);
    canvas.drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h), p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.28, h * 0.28, w * 0.44, h * 0.44),
        const Radius.circular(2),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(_ChipPainter old) => false;
}

/// The colored neoPOP "bill card": a saturated panel with a name/network line,
/// a white icon medallion, a status tag, an amount, and a white CTA. Adapted
/// here for savings goals.
class NeoPopBillCard extends StatelessWidget {
  final Color color;
  final String name;
  final String subtitle;
  final IconData icon;
  final String tagText;
  final Color tagColor;
  final String amountText;
  final String ctaLabel;
  final VoidCallback onCta;
  final VoidCallback? onOptions;

  /// 0..1 fill for an optional progress bar under the amount. Null hides it.
  /// Gives goal cards an at-a-glance sense of "how close" beyond the % label.
  final double? progress;

  const NeoPopBillCard({
    super.key,
    required this.color,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.tagText,
    required this.tagColor,
    required this.amountText,
    required this.ctaLabel,
    required this.onCta,
    this.onOptions,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    // Darken the picked color for the depth block, like the kit's V/H shadow.
    final depth = Color.alphaBlend(Colors.black.withValues(alpha: 0.45), color);
    return NeoPopElevated(
      faceColor: color,
      depthColor: depth,
      borderColor: Colors.white.withValues(alpha: 0.12),
      depth: 0,
      cornerRadius: 0,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: CardGuilloche(color: Colors.white)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 22, color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    color: tagColor,
                    child: Text(
                      tagText.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    amountText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress!.clamp(0.0, 1.0),
                            child: Container(height: 6, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onCta,
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.center,
                            color: Colors.white,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    ctaLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: Color(0xFF121212),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward,
                                  size: 15,
                                  color: Color(0xFF121212),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (onOptions != null)
                        GestureDetector(
                          onTap: onOptions,
                          child: Container(
                            height: 44,
                            width: 44,
                            alignment: Alignment.center,
                            decoration: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                              width: 0.5,
                            ).toBoxDecoration(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                3,
                                (_) => Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _BorderBox on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

/// The 300–900 arc score gauge from the neoPOP credit-score card.
/// Reused generically as a progress ring (e.g. budget used / goal progress).
class NeoPopScoreGauge extends StatelessWidget {
  final double progress; // 0..1
  final String centerText;
  final Color arcColor;
  final Color trackColor;
  final Color? centerTextColor;
  final double size;

  const NeoPopScoreGauge({
    super.key,
    required this.progress,
    required this.centerText,
    this.arcColor = const Color(0xFFEDFE79), // neo pacha lime
    this.trackColor = const Color(0xFF161616),
    this.centerTextColor,
    this.size = 90,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(progress.clamp(0, 1), arcColor, trackColor),
        child: Center(
          child: Text(
            centerText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: centerTextColor ?? Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// The neoPOP credit-score card: dark panel with a gauge on the left, a status
/// label + description + outline CTA on the right, and an optional footer bar.
/// Generalised here as a stat card (e.g. monthly budget usage).
class NeoPopStatCard extends StatelessWidget {
  final double progress; // 0..1
  final String gaugeText; // centre of the gauge, e.g. "72%"
  final String statusLabel; // e.g. "ON TRACK"
  final Color statusColor;
  final String title; // e.g. "spent ₹12,300 of ₹20,000"
  final String subtitle; // e.g. "updated just now"
  final String? footerText; // optional bottom bar caption
  final String? minLabel;
  final String? maxLabel;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const NeoPopStatCard({
    super.key,
    required this.progress,
    required this.gaugeText,
    required this.statusLabel,
    required this.statusColor,
    required this.title,
    required this.subtitle,
    this.footerText,
    this.minLabel,
    this.maxLabel,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    // Adaptive surfaces. The dark values below are identical to the original
    // hard-coded panel (#121212), footer (#161616) and line (#3D3D3D), so dark
    // mode is unchanged; light mode now resolves to a proper light card instead
    // of a black block floating on a white screen.
    final oc = context.oc;
    final panel = oc.surface;
    final footer = oc.card;
    final line = oc.border;
    final popWhite = oc.text;
    // Rounded like the app's other cards: one outer border drawn over a
    // clipped body, with a hairline between body and footer.
    final radius = BorderRadius.circular(ExpndRadius.card);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: line),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: panel,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      NeoPopScoreGauge(
                        progress: progress,
                        centerText: gaugeText,
                        arcColor: statusColor,
                        trackColor: line,
                        centerTextColor: popWhite,
                      ),
                      if (minLabel != null || maxLabel != null) ...[
                        const SizedBox(height: 12),
                        // Wider than the 90pt gauge so the max label (e.g. "$3,000")
                        // renders in full at boosted text sizes instead of "$3,00…".
                        SizedBox(
                          width: 100,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  minLabel ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                    color: oc.dimmed,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  maxLabel ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                    color: oc.dimmed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: popWhite,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.4,
                            color: oc.muted,
                          ),
                        ),
                        if (ctaLabel != null) ...[
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: onCta,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: ExpndColors.ink,
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                              child: Text(
                                ctaLabel!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (footerText != null)
              Container(
                decoration: BoxDecoration(
                  color: footer,
                  border: Border(top: BorderSide(color: line)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.autorenew_rounded,
                        size: 11,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        footerText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: popWhite,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color arcColor;
  final Color trackColor;
  _GaugePainter(this.progress, this.arcColor, this.trackColor);

  // Gap at the bottom, like a speedometer sweep.
  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, _start, _sweep, false, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    canvas.drawArc(rect, _start, _sweep * progress, false, arc);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}
