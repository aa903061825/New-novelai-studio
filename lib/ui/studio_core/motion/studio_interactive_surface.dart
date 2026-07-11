import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

class StudioInteractiveSurface extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressedScale;
  final Offset hoverOffset;
  final Offset pressedOffset;
  final BorderRadiusGeometry? borderRadius;
  final Color? hoverBorderColor;
  final Color? hoverOverlayColor;
  final List<BoxShadow>? hoverShadow;

  const StudioInteractiveSurface({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.018,
    this.pressedScale = 0.986,
    this.hoverOffset = const Offset(0, -0.009),
    this.pressedOffset = const Offset(0, 0.004),
    this.borderRadius,
    this.hoverBorderColor,
    this.hoverOverlayColor,
    this.hoverShadow,
  });

  @override
  State<StudioInteractiveSurface> createState() =>
      _StudioInteractiveSurfaceState();
}

class _StudioInteractiveSurfaceState extends State<StudioInteractiveSurface> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (!mounted) return;
    if (value == _hovered && (value || !_pressed)) return;
    setState(() {
      _hovered = value;
      if (!value) _pressed = false;
    });
  }

  void _setPressed(bool value) {
    if (!mounted || value == _pressed) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final canAnimate =
        widget.enabled && !StudioMotionScope.animationsDisabled(context);
    final scale = !canAnimate
        ? 1.0
        : _pressed
            ? widget.pressedScale
            : _hovered
                ? widget.hoverScale
                : 1.0;
    final offset = !canAnimate
        ? Offset.zero
        : _pressed
            ? widget.pressedOffset
            : _hovered
                ? widget.hoverOffset
                : Offset.zero;

    return MouseRegion(
      onEnter: widget.enabled ? (_) => _setHovered(true) : null,
      onExit: widget.enabled ? (_) => _setHovered(false) : null,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
        onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
        onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
        child: AnimatedSlide(
          offset: offset,
          duration:
              StudioMotionScope.duration(context, StudioMotionTokens.fast),
          curve: StudioMotionTokens.utilityCurve,
          child: AnimatedScale(
            scale: scale,
            duration:
                StudioMotionScope.duration(context, StudioMotionTokens.fast),
            curve: StudioMotionTokens.utilityCurve,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child,
                if (widget.hoverBorderColor != null ||
                    widget.hoverOverlayColor != null ||
                    widget.hoverShadow != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: StudioMotionScope.duration(
                          context,
                          StudioMotionTokens.fast,
                        ),
                        curve: StudioMotionTokens.utilityCurve,
                        decoration: BoxDecoration(
                          borderRadius: widget.borderRadius,
                          color: _hovered ? widget.hoverOverlayColor : null,
                          border: widget.hoverBorderColor == null
                              ? null
                              : Border.all(
                                  color: _hovered
                                      ? widget.hoverBorderColor!
                                      : Colors.transparent,
                                ),
                          boxShadow: _hovered ? widget.hoverShadow : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
