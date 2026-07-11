import 'dart:math';

import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

class StudioStaggeredReveal extends StatefulWidget {
  final int index;
  final int columns;
  final int maxStaggeredItems;
  final Duration duration;
  final Duration itemDelay;
  final Curve curve;
  final Offset beginOffset;
  final double beginScale;
  final Alignment alignment;
  final bool initiallyRevealed;
  final Widget child;

  const StudioStaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.columns = 1,
    this.maxStaggeredItems = 12,
    this.duration = StudioMotionTokens.medium,
    this.itemDelay = const Duration(milliseconds: 26),
    this.curve = StudioMotionTokens.showcaseCurve,
    this.beginOffset = const Offset(0, 0.045),
    this.beginScale = 0.965,
    this.alignment = Alignment.topCenter,
    this.initiallyRevealed = false,
  });

  static Duration delayFor({
    required int index,
    required int columns,
    required Duration itemDelay,
    required int maxStaggeredItems,
  }) {
    final safeColumns = max(1, columns);
    final cappedIndex = max(0, min(index, max(0, maxStaggeredItems - 1)));
    final row = cappedIndex ~/ safeColumns;
    final column = cappedIndex % safeColumns;
    return Duration(
      microseconds: itemDelay.inMicroseconds * (row + column),
    );
  }

  @override
  State<StudioStaggeredReveal> createState() => _StudioStaggeredRevealState();
}

class _StudioStaggeredRevealState extends State<StudioStaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _totalDuration(),
    value: widget.initiallyRevealed ? 1 : 0,
  );
  late bool _started = widget.initiallyRevealed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = _totalDuration();
    if (StudioMotionScope.animationsDisabled(context)) {
      _controller.value = 1;
      _started = true;
      return;
    }
    if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant StudioStaggeredReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _totalDuration();
    if (widget.initiallyRevealed && !oldWidget.initiallyRevealed) {
      _controller.value = 1;
      _started = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMicroseconds = _totalDuration().inMicroseconds;
    final delay = _delay();
    final intervalStart =
        totalMicroseconds <= 0 ? 0.0 : delay.inMicroseconds / totalMicroseconds;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        intervalStart.clamp(0.0, 1.0),
        1,
        curve: widget.curve,
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.beginOffset,
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          alignment: widget.alignment,
          scale: Tween<double>(
            begin: widget.beginScale,
            end: 1,
          ).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }

  Duration _delay() {
    return StudioStaggeredReveal.delayFor(
      index: widget.index,
      columns: widget.columns,
      itemDelay: widget.itemDelay,
      maxStaggeredItems: widget.maxStaggeredItems,
    );
  }

  Duration _totalDuration() {
    return Duration(
      microseconds: _delay().inMicroseconds + widget.duration.inMicroseconds,
    );
  }
}
