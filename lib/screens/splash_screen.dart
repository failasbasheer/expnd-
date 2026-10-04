import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// Branded loading screen shown while the stores boot.
///
/// Its first frame is the native launch screen exactly: the heavy pop "E"
/// drawn in the same 200pt box, at the same screen-centre position, on the
/// same ink. Everything else then animates in on top: a warm glow, the
/// spaced "EXPND" wordmark letter by letter, and a looping NeoPOP "press" —
/// the E pushes down into its depth block, springs back, and sends out a
/// ripple — while the app loads. Reduced-motion users get the settled state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Must match the LaunchScreen storyboard image view and Android's
  // launch_image (both a 200pt/dp box) so the handoff is pixel-consistent.
  static const double _markBox = 200;

  static const _white = Color(0xFFF5F5F0);
  static const _letters = ['E', 'X', 'P', 'N', 'D'];

  // Glow, wordmark and credit fade/rise in once.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  // One press → release → ripple cycle, repeated while loading.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  Timer? _pressDelay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
      return;
    }
    _intro.forward();
    // Hold the static mark for a beat so the native → Flutter seam is
    // invisible, then start pressing.
    _pressDelay = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _press.repeat();
    });
  }

  @override
  void dispose() {
    _pressDelay?.cancel();
    _intro.dispose();
    _press.dispose();
    super.dispose();
  }

  double _interval(
    double t,
    double begin,
    double end, [
    Curve c = Curves.easeOut,
  ]) {
    if (t <= begin) return 0;
    if (t >= end) return 1;
    return c.transform((t - begin) / (end - begin));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExpndColors.ink,
      body: Semantics(
        label: 'EXPND is loading',
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _press]),
          builder: (context, _) {
            final i = _intro.value;
            final p = _press.value;
            final glow = _interval(i, 0, 0.6);
            return Stack(
              children: [
                // Soft spotlight + gold glow fade in over the flat launch ink.
                Positioned.fill(
                  child: Opacity(
                    opacity: glow,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -0.08),
                          radius: 0.9,
                          colors: [Color(0xFF26262A), Color(0xFF0A0A0A)],
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Opacity(
                    opacity: glow * (0.75 + 0.25 * _pressGlow(p)),
                    child: Container(
                      width: 340,
                      height: 340,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x38FFE81F), Color(0x00FFE81F)],
                        ),
                      ),
                    ),
                  ),
                ),

                // The mark: dead-centre, identical to the launch screen.
                Center(
                  child: SizedBox.square(
                    dimension: _markBox,
                    child: CustomPaint(
                      painter: _PopEPainter(
                        press: _pressDepth(p),
                        ripple: p,
                        shimmer: _interval(p, 0.42, 0.95, Curves.easeInOut),
                      ),
                    ),
                  ),
                ),

                // Wordmark below the mark, letters rising in one by one.
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(0, _markBox / 2 + 34),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var n = 0; n < _letters.length; n++)
                          _letter(
                            _letters[n],
                            _interval(
                              i,
                              0.28 + n * 0.08,
                              0.62 + n * 0.08,
                              Curves.easeOutBack,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 44,
                  child: Opacity(
                    opacity: _interval(i, 0.6, 1.0),
                    child: Text(
                      'by Trylas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'ExpndSans',
                        fontSize: 12,
                        color: _white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letter(String ch, double t) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.5),
          child: Text(
            ch,
            style: const TextStyle(
              fontFamily: 'ExpndSans',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  /// 0 = face up, 1 = face fully pressed onto its depth block.
  static double _pressDepth(double p) {
    if (p < 0.16) return Curves.easeIn.transform(p / 0.16);
    if (p < 0.26) return 1;
    if (p < 0.5) return 1 - Curves.easeOutBack.transform((p - 0.26) / 0.24);
    return 0;
  }

  static double _pressGlow(double p) => p < 0.5 ? _pressDepth(p) : 0;
}

/// Paints the heavy pop "E" in a 100×100 design space — the same geometry
/// the app icon and launch images are rendered from.
class _PopEPainter extends CustomPainter {
  final double press; // 0..1 (may overshoot slightly below 0 on release)
  final double ripple; // 0..1 cycle position
  final double shimmer; // 0..1 sweep progress

  const _PopEPainter({
    required this.press,
    required this.ripple,
    required this.shimmer,
  });

  static const _depth = 3.5;
  static const _depthColor = Color(0xFFB8A300);
  static const _gold = Color(0xFFFFE81F);

  static final Path _e = Path()
    ..moveTo(69, 27)
    ..lineTo(29, 27)
    ..lineTo(29, 73)
    ..lineTo(69, 73)
    ..moveTo(29, 50)
    ..lineTo(63, 50);

  Paint _stroke() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    // Optical framing shared with the icon renders.
    canvas.translate(50, 50);
    canvas.scale(0.86);
    canvas.translate(-51, -52);

    _paintRipple(canvas);

    canvas.save();
    canvas.translate(_depth, _depth);
    canvas.drawPath(_e, _stroke()..color = _depthColor);
    canvas.restore();

    final shift = _depth * press;
    canvas.save();
    canvas.translate(shift, shift);
    const bounds = Rect.fromLTWH(10, 10, 80, 80);
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(
      _e,
      _stroke()
        ..shader = ui.Gradient.linear(
          const Offset(22, 24),
          const Offset(74, 76),
          const [Color(0xFFFFF6A3), Color(0xFFFFE81F), Color(0xFFFFD400)],
          const [0, 0.45, 1],
        ),
    );
    if (shimmer > 0 && shimmer < 1) {
      // A light band sweeping diagonally across the face only.
      final x = -30 + 140 * shimmer;
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = ui.Gradient.linear(
            Offset(x - 14, 20),
            Offset(x + 14, 80),
            const [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)],
            const [0, 0.5, 1],
          ),
      );
    }
    canvas.restore();
    canvas.restore();

    canvas.restore();
  }

  void _paintRipple(Canvas canvas) {
    const start = 0.2;
    if (ripple <= start) return;
    final t = Curves.easeOut.transform((ripple - start) / (1 - start));
    final scale = 1 + 0.75 * t;
    final rect = Rect.fromCenter(
      center: const Offset(51, 52),
      width: 66 * scale,
      height: 72 * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(20 * scale)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _gold.withValues(alpha: 0.5 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_PopEPainter old) =>
      old.press != press || old.ripple != ripple || old.shimmer != shimmer;
}
