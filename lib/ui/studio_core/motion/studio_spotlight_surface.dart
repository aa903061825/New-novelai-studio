import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

class StudioSpotlightSurface extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Color spotlightColor;
  final double radius;
  final BorderRadius borderRadius;

  const StudioSpotlightSurface({
    super.key,
    required this.child,
    this.enabled = true,
    this.spotlightColor = const Color(0x1CFFE500),
    this.radius = 420,
    this.borderRadius = StudioTokens.radiusCard,
  });

  @override
  State<StudioSpotlightSurface> createState() => _StudioSpotlightSurfaceState();
}

class _StudioSpotlightSurfaceState extends State<StudioSpotlightSurface> {
  bool _hovered = false;
  Offset _position = Offset.zero;

  void _show(PointerEvent event) {
    setState(() {
      _hovered = true;
      _position = event.localPosition;
    });
  }

  void _move(PointerEvent event) {
    if (event.localPosition == _position) return;
    setState(() => _position = event.localPosition);
  }

  void _hide(PointerEvent _) {
    if (!_hovered) return;
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final canAnimate =
        widget.enabled && !StudioMotionScope.animationsDisabled(context);
    if (!canAnimate) return widget.child;

    return MouseRegion(
      onEnter: _show,
      onHover: _move,
      onExit: _hide,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: StudioMotionTokens.fast,
                  curve: StudioMotionTokens.utilityCurve,
                  child: CustomPaint(
                    painter: _StudioSpotlightPainter(
                      center: _position,
                      color: widget.spotlightColor,
                      radius: widget.radius,
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioSpotlightPainter extends CustomPainter {
  final Offset center;
  final Color color;
  final double radius;
  final BorderRadius borderRadius;

  const _StudioSpotlightPainter({
    required this.center,
    required this.color,
    required this.radius,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || radius <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [color, color.withAlpha(0)],
        const [0, 1],
      );
    canvas.drawRRect(borderRadius.toRRect(rect), paint);
  }

  @override
  bool shouldRepaint(covariant _StudioSpotlightPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.borderRadius != borderRadius;
  }
}
