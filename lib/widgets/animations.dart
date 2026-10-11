import 'dart:async';

import 'package:flutter/material.dart';

/// Fades a child in while it gently rises into place. Used for section /
/// list-item entrances so screens assemble themselves instead of snapping in.
///
/// [index] staggers the start: each successive item waits [stagger] longer,
/// giving a cascading reveal down a list.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final Duration stagger;
  final double offset;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 260),
    this.stagger = const Duration(milliseconds: 35),
    this.offset = 8,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _delay?.cancel();
      _c.value = 1;
      return;
    }
    if (_started) return;
    _started = true;
    // Bound the cascade so a long ledger remains readable immediately.
    final delay = widget.stagger * widget.index.clamp(0, 8);
    _delay = Timer(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didUpdateWidget(covariant FadeSlideIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) _c.duration = widget.duration;
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}

/// Wraps a tappable child so it dips slightly on press and springs back on
/// release, giving flat chips/tiles the same tactile feedback the NeoPop
/// buttons already have. Keeps the child's own hit region via [onTap].
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;
  final HitTestBehavior behavior;
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.duration = const Duration(milliseconds: 90),
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap != null || widget.onLongPress != null
          ? (_) => _set(true)
          : null,
      onTapUp: widget.onTap != null || widget.onLongPress != null
          ? (_) => _set(false)
          : null,
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? widget.scale : 1.0,
        duration: reducedMotion ? Duration.zero : widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
