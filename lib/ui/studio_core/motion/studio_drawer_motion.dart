import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_presence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

class StudioDrawerPushTransition extends StatefulWidget {
  final int depth;
  final Key transitionKey;
  final Widget child;
  final Duration duration;
  final bool instantReverse;

  const StudioDrawerPushTransition({
    super.key,
    required this.depth,
    required this.transitionKey,
    required this.child,
    this.duration = StudioMotionTokens.medium,
    this.instantReverse = false,
  });

  @override
  State<StudioDrawerPushTransition> createState() =>
      _StudioDrawerPushTransitionState();
}

class _StudioDrawerPushTransitionState
    extends State<StudioDrawerPushTransition> {
  var _forward = true;

  @override
  void didUpdateWidget(covariant StudioDrawerPushTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.depth != widget.depth ||
        oldWidget.transitionKey != widget.transitionKey) {
      _forward = widget.depth >= oldWidget.depth;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (StudioMotionScope.animationsDisabled(context) ||
        (widget.instantReverse && !_forward)) {
      return KeyedSubtree(
        key: widget.transitionKey,
        child: widget.child,
      );
    }
    return ClipRect(
      child: AnimatedSwitcher(
        duration: StudioMotionScope.duration(context, widget.duration),
        reverseDuration: StudioMotionScope.duration(
          context,
          StudioMotionTokens.fast,
        ),
        switchInCurve: StudioMotionTokens.showcaseCurve,
        switchOutCurve: StudioMotionTokens.utilityCurve,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.topLeft,
            children: [
              for (final previousChild in previousChildren)
                IgnorePointer(child: previousChild),
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final incoming = child.key == widget.transitionKey;
          final begin = incoming
              ? (_forward ? const Offset(0.16, 0) : const Offset(-0.12, 0))
              : (_forward ? const Offset(-0.08, 0) : const Offset(0.1, 0));
          final curved = CurvedAnimation(
            parent: animation,
            curve: incoming
                ? StudioMotionTokens.showcaseCurve
                : StudioMotionTokens.utilityCurve,
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              transformHitTests: false,
              position: Tween<Offset>(
                begin: begin,
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: widget.transitionKey,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

class StudioDrawerShelf extends StatelessWidget {
  final bool visible;
  final WidgetBuilder builder;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double railOpacity;

  const StudioDrawerShelf({
    super.key,
    required this.visible,
    required this.builder,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.only(left: 12),
    this.railOpacity = 0.46,
  });

  @override
  Widget build(BuildContext context) {
    final railBorder = railOpacity <= 0
        ? BorderSide.none
        : BorderSide(
            color: StudioTokens.primary.withValues(alpha: railOpacity),
            width: 2,
          );
    return StudioAnimatedPresence(
      visible: visible,
      duration: StudioMotionTokens.medium,
      beginOffset: const Offset(0.035, 0),
      builder: (context) => Padding(
        padding: margin,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: railBorder,
            ),
          ),
          child: Padding(
            padding: padding,
            child: builder(context),
          ),
        ),
      ),
    );
  }
}
