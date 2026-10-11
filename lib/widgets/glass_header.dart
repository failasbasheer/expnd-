import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/expnd_theme.dart';

/// A screen whose header floats over its scrolling body as frosted glass, so
/// content passes underneath the title instead of being cut off at its edge.
///
/// The header is measured after layout and its height handed to [body] as
/// `topInset`; the body adds it to its scroll view's top padding so the first
/// row still starts just below the header at rest. [overlay] is an optional
/// strip drawn under the header inside the same glass that is *not* counted
/// in the inset — for bars that appear mid-scroll (wallet's sticky account
/// bar) and should cover content rather than push it down.
///
/// [collapsedHeader], when given, replaces [header] once the body has scrolled
/// past [collapseAfter] — a compact bar for screens whose resting header is
/// tall. The body keeps the resting inset, so nothing jumps when it swaps.
///
/// With [ExpndGlass.enabled] off this degrades to the old solid layout.
/// In glass mode callers must not apply a top SafeArea: the plate extends
/// under the status bar and pads the header by the status-bar height.
class GlassHeaderLayout extends StatefulWidget {
  final Widget header;
  final Widget? collapsedHeader;
  final double collapseAfter;
  final Widget? overlay;
  final Widget Function(BuildContext context, double topInset) body;

  const GlassHeaderLayout({
    super.key,
    required this.header,
    required this.body,
    this.collapsedHeader,
    this.collapseAfter = 48,
    this.overlay,
  });

  @override
  State<GlassHeaderLayout> createState() => _GlassHeaderLayoutState();
}

class _GlassHeaderLayoutState extends State<GlassHeaderLayout> {
  double _height = 0;
  bool _scrolled = false;
  bool _collapsed = false;

  void _onHeaderSize(Size size) {
    // Only the resting header sets the body's inset; the compact one is
    // shorter and would otherwise pull the content up under the finger.
    // Mid-animation sizes on the way back out are ignored too: the inset only
    // ever grows to the tallest resting height.
    if (!mounted || _collapsed) return;
    if (widget.collapsedHeader != null && size.height <= _height) return;
    if (size.height == _height) return;
    setState(() => _height = size.height);
  }

  bool _onScroll(ScrollNotification n) {
    // Only the screen's own vertical list; ignore nested chip rows/carousels.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _updateScroll(n.metrics);
    return false;
  }

  void _updateScroll(ScrollMetrics metrics) {
    final scrolled = metrics.extentBefore > 0.5;
    final collapsed =
        widget.collapsedHeader != null &&
        metrics.extentBefore > widget.collapseAfter;
    if (scrolled != _scrolled || collapsed != _collapsed) {
      setState(() {
        _scrolled = scrolled;
        _collapsed = collapsed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ExpndGlass.enabled) {
      return Column(
        children: [
          widget.header,
          ?widget.overlay,
          Expanded(child: widget.body(context, 0)),
        ],
      );
    }

    final oc = context.oc;
    final dark = oc.brightness == Brightness.dark;
    final translucent = ExpndGlass.translucent(context);
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical) {
                  _updateScroll(notification.metrics);
                }
                return false;
              },
              child: widget.body(context, _height),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              enabled: translucent && _scrolled,
              filter: ImageFilter.blur(
                sigmaX: ExpndGlass.blur,
                sigmaY: ExpndGlass.blur,
              ),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  // At rest the plate matches the page, so the header looks
                  // exactly as before; it only reads as glass once content
                  // slides under it.
                  color: oc.bg.withValues(
                    alpha: _scrolled && translucent
                        ? ExpndGlass.tint(oc.brightness)
                        : 1,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: _scrolled
                          ? (dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : oc.border)
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SizeReporter(
                      onSize: _onHeaderSize,
                      // The glass runs under the status bar (callers drop
                      // their top SafeArea in glass mode), so the header
                      // carries that inset itself.
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top,
                        ),
                        child: AnimatedSize(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _collapsed
                              ? widget.collapsedHeader!
                              : widget.header,
                        ),
                      ),
                    ),
                    ?widget.overlay,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports its child's laid-out size after each layout that changes it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;
  const _SizeReporter({required this.onSize, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  ValueChanged<Size> onSize;
  Size? _last;
  _RenderSizeReporter(this.onSize);

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}
