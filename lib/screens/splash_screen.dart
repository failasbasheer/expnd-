import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// Branded loading screen shown while the stores boot. It renders the SAME gold
/// "E" asset the native launch storyboard uses, at the SAME size and the SAME
/// screen-centre position, and starts it fully static — so the storyboard →
/// splash handoff is seamless (no pop, resize, or jump). Only the elements that
/// were NOT on the launch screen (wordmark, loading bar, credit) animate in,
/// below the mark, and the mark itself breathes gently once settled.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Height the "E" renders at — must match the launch storyboard imageView
  // (173x172, aspectFit) so the handoff is pixel-consistent.
  static const double _markH = 172;

  // The supporting elements fade/rise in.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  // Loading-bar shimmer sweep.
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  // Slow breathing on the mark. Starts at value 0 → scale 1.0, so the very
  // first frame matches the static launch screen exactly, then eases up.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _in.dispose();
    _bar.dispose();
    _breathe.dispose();
    super.dispose();
  }

  static const _white = Color(0xFFF5F5F0);

  @override
  Widget build(BuildContext context) {
    final support = CurvedAnimation(
      parent: _in,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: ExpndColors.ink,
      body: Stack(
        children: [
          // Soft gold glow, static — reads as lit ink, no motion at the seam.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.05),
                  radius: 0.95,
                  colors: [Color(0x22FFEB34), Color(0x00FFEB34)],
                ),
              ),
            ),
          ),

          // The mark: dead-centre (matching the launch storyboard), static on
          // frame one, then breathing. No fade, no pop.
          Center(
            child: AnimatedBuilder(
              animation: _breathe,
              builder: (_, child) {
                final t = Curves.easeInOut.transform(_breathe.value);
                return Transform.scale(scale: 1.0 + 0.02 * t, child: child);
              },
              child: Image.asset(
                'assets/brand/expnd_E.png',
                height: _markH,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),

          // Wordmark + loading bar, positioned BELOW the centred mark so the
          // mark never has to move to make room. These fade/rise in.
          Align(
            alignment: Alignment.center,
            child: Transform.translate(
              offset: const Offset(0, _markH / 2 + 66),
              child: FadeTransition(
                opacity: support,
                child: AnimatedBuilder(
                  animation: support,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, (1 - support.value) * 10),
                    child: child,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'EXPND',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: ExpndColors.gold,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _loadingBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Brand credit at the foot.
          Positioned(
            left: 0,
            right: 0,
            bottom: 42,
            child: FadeTransition(
              opacity: support,
              child: Center(
                child: Text(
                  'BY TRYLAS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: _white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingBar() {
    const w = 190.0;
    const seg = 74.0;
    return Container(
      width: w,
      height: 6,
      decoration: BoxDecoration(
        color: _white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(3),
        border:
            Border.all(color: ExpndColors.gold.withValues(alpha: 0.35), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: AnimatedBuilder(
          animation: _bar,
          builder: (_, _) {
            final t = Curves.easeInOut.transform(_bar.value);
            final x = -seg + (w + seg) * t;
            return Stack(
              children: [
                Positioned(
                  left: x,
                  top: 0,
                  bottom: 0,
                  width: seg,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ExpndColors.gold.withValues(alpha: 0.0),
                          ExpndColors.gold,
                          ExpndColors.gold.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
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
}
