import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

class StudioAnimatedPresence extends StatefulWidget {
  final bool visible;
  final Widget? child;
  final WidgetBuilder? builder;
  final bool maintainState;
  final Duration duration;
  final Curve curve;
  final Curve reverseCurve;
  final Offset beginOffset;
  final Axis axis;
  final double axisAlignment;

  const StudioAnimatedPresence({
    super.key,
    required this.visible,
    this.child,
    this.builder,
    this.maintainState = false,
    this.duration = StudioMotionTokens.medium,
    this.curve = StudioMotionTokens.showcaseCurve,
    this.reverseCurve = StudioMotionTokens.utilityCurve,
    this.beginOffset = const Offset(0, 0.035),
    this.axis = Axis.vertical,
    this.axisAlignment = -1,
  }) : assert(child != null || builder != null);

  @override
  State<StudioAnimatedPresence> createState() => _StudioAnimatedPresenceState();
}

class _StudioAnimatedPresenceState extends State<StudioAnimatedPresence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
    duration: widget.duration,
  )..addStatusListener(_handleStatusChanged);
  late bool _shouldRender = widget.visible || widget.maintainState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = _duration();
    if (StudioMotionScope.animationsDisabled(context)) {
      _controller.value = widget.visible ? 1 : 0;
      _shouldRender = widget.visible || widget.maintainState;
    }
  }

  @override
  void didUpdateWidget(covariant StudioAnimatedPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _duration();
    if (oldWidget.visible == widget.visible &&
        oldWidget.maintainState == widget.maintainState) {
      return;
    }
    if (StudioMotionScope.animationsDisabled(context)) {
      _controller.value = widget.visible ? 1 : 0;
      setState(() {
        _shouldRender = widget.visible || widget.maintainState;
      });
      return;
    }
    if (widget.visible) {
      setState(() => _shouldRender = true);
      _controller.forward();
    } else {
      _controller.reverse().whenComplete(_hideWhenDismissed);
      if (widget.maintainState) {
        setState(() => _shouldRender = true);
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldRender) {
      return const SizedBox.shrink();
    }
    if (StudioMotionScope.animationsDisabled(context)) {
      return widget.visible || widget.maintainState
          ? _buildChild(context)
          : const SizedBox.shrink();
    }
    final animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
      reverseCurve: widget.reverseCurve,
    );
    return ClipRect(
      child: SizeTransition(
        axis: widget.axis,
        axisAlignment: widget.axisAlignment,
        sizeFactor: animation,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: widget.beginOffset,
              end: Offset.zero,
            ).animate(animation),
            child: _buildChild(context),
          ),
        ),
      ),
    );
  }

  Widget _buildChild(BuildContext context) {
    return widget.builder?.call(context) ?? widget.child!;
  }

  Duration _duration() {
    return StudioMotionScope.duration(context, widget.duration);
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (!mounted ||
        status != AnimationStatus.dismissed ||
        widget.visible ||
        widget.maintainState) {
      return;
    }
    _hideWhenDismissed();
  }

  void _hideWhenDismissed() {
    if (!mounted ||
        _controller.status != AnimationStatus.dismissed ||
        widget.visible ||
        widget.maintainState ||
        !_shouldRender) {
      return;
    }
    setState(() => _shouldRender = false);
  }
}
