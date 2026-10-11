import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// Loading screen shown while the stores boot.
///
/// It is the native launch screen exactly — the flat NeoPOP "E" in the same
/// 200pt box, at the same screen-centre position, on the same ink — and it
/// holds still. Apple's guidance is that a launch screen should look like the
/// app opening rather than an intro, and the app now opens as soon as it has
/// loaded, so there is nothing for an animation to fill. (It used to loop a
/// press-and-ripple with a glow and a letter-by-letter wordmark.)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // Must match the LaunchScreen storyboard image view and Android's
  // launch_image (both a 200pt/dp box) so the handoff is pixel-consistent.
  static const double _markBox = 200;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExpndColors.ink,
      body: Semantics(
        label: 'EXPND is loading',
        child: Stack(
          children: [
            const Center(
              child: SizedBox.square(
                dimension: _markBox,
                child: CustomPaint(painter: ExpndMarkPainter()),
              ),
            ),
            // Quiet maker's credit, still like the mark.
            Positioned(
              left: 0,
              right: 0,
              bottom: 44,
              child: ExcludeSemantics(
                child: Text(
                  'by Trylas',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'ExpndSans',
                    fontSize: 12,
                    letterSpacing: 0.4,
                    color: const Color(0xFFF5F5F0).withValues(alpha: 0.45),
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

/// The flat NeoPOP "E": a solid gold face over a solid gold-dark offset edge.
///
/// Same geometry as tool/generate_brand_assets.py, which renders the app icon
/// and launch images — change both together.
class ExpndMarkPainter extends CustomPainter {
  const ExpndMarkPainter();

  // In units of the E's own height.
  static const _stroke = 0.22;
  static const _width = 0.80;
  static const _midArm = 0.82;
  static const _radius = 0.03;
  static const _depth = 0.07;
  // Share of the box the whole mark (face + edge) takes vertically.
  static const _markHeight = 0.55;

  static const _gold = Color(0xFFFFE81F);
  static const _goldDark = Color(0xFFB8A300);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height * _markHeight / (1 + _depth);
    final w = h * _width;
    final d = h * _depth;
    final origin = Offset(
      (size.width - (w + d)) / 2,
      (size.height - (h + d)) / 2,
    );
    _paintE(canvas, origin + Offset(d, d), h, w, _goldDark);
    _paintE(canvas, origin, h, w, _gold);
  }

  void _paintE(Canvas canvas, Offset o, double h, double w, Color color) {
    final t = h * _stroke;
    final r = Radius.circular(h * _radius);
    final paint = Paint()..color = color;
    for (final rect in [
      Rect.fromLTWH(o.dx, o.dy, t, h), // spine
      Rect.fromLTWH(o.dx, o.dy, w, t), // top arm
      Rect.fromLTWH(o.dx, o.dy + (h - t) / 2, w * _midArm, t), // middle
      Rect.fromLTWH(o.dx, o.dy + h - t, w, t), // bottom arm
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, r), paint);
    }
  }

  @override
  bool shouldRepaint(ExpndMarkPainter oldDelegate) => false;
}
