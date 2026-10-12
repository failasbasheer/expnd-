import 'package:flutter/material.dart';

import '../theme/expnd_theme.dart';

/// A brief coach mark over a real Home control. The target stays visible in
/// the cutout while the rest of the screen is blocked until Next or Skip.
class HomeTourOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final int step;
  final int stepCount;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const HomeTourOverlay({
    super.key,
    required this.targetKey,
    required this.step,
    required this.stepCount,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<HomeTourOverlay> createState() => _HomeTourOverlayState();
}

class _HomeTourOverlayState extends State<HomeTourOverlay> {
  final _overlayKey = GlobalKey();
  bool _measurementQueued = false;
  Rect? _rect;

  @override
  void didUpdateWidget(covariant HomeTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey) _rect = null;
  }

  Rect? _targetRect() {
    final target = widget.targetKey.currentContext?.findRenderObject();
    final overlay = _overlayKey.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        overlay is! RenderBox ||
        !target.hasSize ||
        !overlay.hasSize) {
      return null;
    }
    final origin =
        target.localToGlobal(Offset.zero) - overlay.localToGlobal(Offset.zero);
    return origin & target.size;
  }

  void _queueMeasurement() {
    if (_measurementQueued) return;
    _measurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementQueued = false;
      if (!mounted) return;
      final next = _targetRect();
      if (next != _rect) setState(() => _rect = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    _queueMeasurement();
    final rect = _rect;
    if (rect == null) return SizedBox.expand(key: _overlayKey);

    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final target = rect.inflate(7).intersect(Offset.zero & size);
    final below = size.height - safe.bottom - target.bottom;
    final above = target.top - safe.top;
    final placeBelow = below >= 235 || below >= above;
    final oc = context.oc;

    return SizedBox.expand(
      key: _overlayKey,
      child: Material(
        color: Colors.transparent,
        child: BlockSemantics(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(painter: _SpotlightPainter(target)),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: placeBelow ? target.bottom + 18 : safe.top + 12,
                bottom: placeBelow
                    ? safe.bottom + 12
                    : size.height - target.top + 18,
                child: Align(
                  alignment: placeBelow
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _TourCard(
                        step: widget.step,
                        stepCount: widget.stepCount,
                        title: widget.title,
                        description: widget.description,
                        onNext: widget.onNext,
                        onSkip: widget.onSkip,
                        oc: oc,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect target;

  const _SpotlightPainter(this.target);

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(target, const Radius.circular(20));
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rounded);
    canvas.drawPath(scrim, Paint()..color = const Color(0xD9080D12));
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = ExpndColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.target != target;
}

class _TourCard extends StatelessWidget {
  final int step;
  final int stepCount;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final ExpndColors oc;

  const _TourCard({
    required this.step,
    required this.stepCount,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    required this.oc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ExpndColors.gold, width: 1.5),
        boxShadow: [
          BoxShadow(color: ExpndColors.goldDark, offset: Offset(3, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < stepCount; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: i <= step ? ExpndColors.gold : oc.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${step + 1} / $stepCount',
                style: TextStyle(color: oc.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            title,
            style: TextStyle(
              color: oc.text,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            description,
            style: TextStyle(color: oc.muted, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(onPressed: onSkip, child: const Text('Skip tour')),
              const Spacer(),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: ExpndColors.gold,
                  foregroundColor: ExpndColors.ink,
                ),
                child: Text(step == stepCount - 1 ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
