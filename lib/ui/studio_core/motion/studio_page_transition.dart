import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

enum StudioPageMotion { showcase, utility, none }

class StudioPageTransition extends StatefulWidget {
  final Key transitionKey;
  final Widget child;
  final StudioPageMotion motion;
  final bool keyChild;

  const StudioPageTransition({
    super.key,
    required this.transitionKey,
    required this.child,
    this.motion = StudioPageMotion.showcase,
    this.keyChild = true,
  });

  @override
  State<StudioPageTransition> createState() => _StudioPageTransitionState();
}

class _StudioPageTransitionState extends State<StudioPageTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void didUpdateWidget(covariant StudioPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _duration();
    if (oldWidget.transitionKey != widget.transitionKey ||
        oldWidget.motion != widget.motion) {
      if (_duration() <= Duration.zero) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = _duration();
    if (StudioMotionScope.animationsDisabled(context)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.motion == StudioPageMotion.none ||
        StudioMotionScope.animationsDisabled(context)) {
      return _buildChild();
    }
    final animation = _controller.drive(
      CurveTween(
        curve: widget.motion == StudioPageMotion.showcase
            ? StudioMotionTokens.showcaseCurve
            : Curves.linearToEaseOut,
      ),
    );
    final offset = widget.motion == StudioPageMotion.showcase
        ? const Offset(0, 0.028)
        : const Offset(0, 0.012);
    final scale = widget.motion == StudioPageMotion.showcase
        ? Tween<double>(begin: 0.982, end: 1).animate(animation)
        : Tween<double>(begin: 0.996, end: 1).animate(animation);
    return FadeTransition(
      key: const ValueKey('studio-page-transition'),
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: offset,
          end: Offset.zero,
        ).animate(animation),
        child: ScaleTransition(
          alignment: Alignment.topCenter,
          scale: scale,
          child: _buildChild(),
        ),
      ),
    );
  }

  Widget _buildChild() {
    final child = RepaintBoundary(child: widget.child);
    if (!widget.keyChild) {
      return child;
    }
    return KeyedSubtree(
      key: widget.transitionKey,
      child: child,
    );
  }

  Duration _duration() {
    return StudioMotionScope.duration(
      context,
      switch (widget.motion) {
        StudioPageMotion.showcase => StudioMotionTokens.showcase,
        StudioPageMotion.utility => StudioMotionTokens.fast,
        StudioPageMotion.none => Duration.zero,
      },
    );
  }
}
