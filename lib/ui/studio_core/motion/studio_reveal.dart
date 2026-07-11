import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

class StudioReveal extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final double beginScale;
  final Offset beginOffset;

  const StudioReveal({
    super.key,
    required this.child,
    this.duration = StudioMotionTokens.expressive,
    this.delay = Duration.zero,
    this.curve = StudioMotionTokens.expressiveCurve,
    this.beginScale = 0.965,
    this.beginOffset = const Offset(0, 0.075),
  });

  @override
  State<StudioReveal> createState() => _StudioRevealState();
}

class _StudioRevealState extends State<StudioReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _totalDuration(),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
  void didUpdateWidget(covariant StudioReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _totalDuration();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMicroseconds = _totalDuration().inMicroseconds;
    final intervalStart = totalMicroseconds <= 0
        ? 0.0
        : widget.delay.inMicroseconds / totalMicroseconds;
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
          scale: Tween<double>(
            begin: widget.beginScale,
            end: 1,
          ).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }

  Duration _totalDuration() {
    return Duration(
      microseconds:
          widget.delay.inMicroseconds + widget.duration.inMicroseconds,
    );
  }
}
