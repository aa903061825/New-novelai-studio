import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/core/theme/playful_geometric_theme.dart';

class PlayfulGeometricBackground extends StatelessWidget {
  final Widget child;

  const PlayfulGeometricBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PlayfulGeometricColors.background,
      child: CustomPaint(
        painter: const _PlayfulGeometricPatternPainter(),
        child: child,
      ),
    );
  }
}

class PlayfulGeometricSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color shadowColor;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Offset shadowOffset;
  final double borderWidth;
  final BorderRadius borderRadius;
  final bool liftOnHover;
  final bool pressOnTap;
  final bool wiggleOnHover;
  final MouseCursor? mouseCursor;

  const PlayfulGeometricSurface({
    super.key,
    required this.child,
    this.onTap,
    this.color = PlayfulGeometricColors.card,
    this.shadowColor = PlayfulGeometricColors.border,
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
    this.shadowOffset = PlayfulGeometricShadows.sticker,
    this.borderWidth = PlayfulGeometricBorders.chunky,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(PlayfulGeometricRadius.large)),
    this.liftOnHover = true,
    this.pressOnTap = true,
    this.wiggleOnHover = false,
    this.mouseCursor,
  });

  @override
  State<PlayfulGeometricSurface> createState() =>
      _PlayfulGeometricSurfaceState();
}

class _PlayfulGeometricSurfaceState extends State<PlayfulGeometricSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final canInteract = widget.onTap != null;
    final isLifted = canInteract && widget.liftOnHover && _hovered && !_pressed;
    final isPressed = canInteract && widget.pressOnTap && _pressed;
    final prefersReducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shadowOffset = isPressed
        ? PlayfulGeometricShadows.press
        : isLifted
            ? widget.shadowOffset + const Offset(2, 2)
            : widget.shadowOffset;
    final dx = isPressed ? 2.0 : 0.0;
    final dy = isPressed
        ? 2.0
        : isLifted
            ? -2.0
            : 0.0;
    final scale = !prefersReducedMotion && isLifted ? 1.02 : 1.0;
    final turns = !prefersReducedMotion && widget.wiggleOnHover && isLifted
        ? -0.006
        : 0.0;

    Widget surface = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      margin: widget.margin,
      padding: widget.padding,
      transform: Matrix4.translationValues(dx, dy, 0),
      decoration: PlayfulGeometricDecorations.sticker(
        color: widget.color,
        shadowColor: widget.shadowColor,
        borderWidth: widget.borderWidth,
        shadowOffset: shadowOffset,
        borderRadius: widget.borderRadius,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          onHover: canInteract
              ? (hovered) => setState(() {
                    _hovered = hovered;
                    if (!hovered) {
                      _pressed = false;
                    }
                  })
              : null,
          onTapDown:
              canInteract ? (_) => setState(() => _pressed = true) : null,
          onTapUp: canInteract ? (_) => setState(() => _pressed = false) : null,
          onTapCancel:
              canInteract ? () => setState(() => _pressed = false) : null,
          canRequestFocus: canInteract,
          mouseCursor: widget.mouseCursor ??
              (canInteract ? SystemMouseCursors.click : MouseCursor.defer),
          child: widget.child,
        ),
      ),
    );
    surface = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: surface,
      ),
    );

    return surface;
  }
}

class PlayfulGeometricFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? tooltip;
  final Object? heroTag;
  final Widget child;
  final Color color;
  final Color foregroundColor;

  const PlayfulGeometricFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.heroTag,
    this.color = PlayfulGeometricColors.accent,
    this.foregroundColor = PlayfulGeometricColors.accentForeground,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    Widget button = Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: PlayfulGeometricSurface(
        onTap: onPressed,
        color: enabled ? color : PlayfulGeometricColors.muted,
        shadowColor: PlayfulGeometricColors.foreground,
        shadowOffset: PlayfulGeometricShadows.pop,
        borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
        padding: EdgeInsets.zero,
        wiggleOnHover: true,
        child: SizedBox.square(
          dimension: 56,
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                color: enabled
                    ? foregroundColor
                    : PlayfulGeometricColors.mutedForeground,
                size: 28,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    if (heroTag != null) {
      button = Hero(tag: heroTag!, child: button);
    }
    return button;
  }
}

class _PlayfulGeometricPatternPainter extends CustomPainter {
  const _PlayfulGeometricPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = PlayfulGeometricColors.foreground.withAlpha(20);
    for (double x = 18; x <= size.width; x += 36) {
      for (double y = 18; y <= size.height; y += 36) {
        canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
      }
    }

    _drawCircle(
      canvas,
      center: Offset(size.width * 0.83, size.height * 0.2),
      radius: 56,
      color: PlayfulGeometricColors.tertiary.withAlpha(90),
    );
    _drawCircle(
      canvas,
      center: Offset(size.width * 0.12, size.height * 0.72),
      radius: 38,
      color: PlayfulGeometricColors.secondary.withAlpha(72),
    );
    _drawSquare(
      canvas,
      center: Offset(size.width * 0.72, size.height * 0.78),
      size: 42,
      color: PlayfulGeometricColors.quaternary.withAlpha(60),
      rotation: math.pi / 8,
    );
    _drawTriangle(
      canvas,
      center: Offset(size.width * 0.25, size.height * 0.18),
      size: 48,
      color: PlayfulGeometricColors.accent.withAlpha(58),
      rotation: -math.pi / 12,
    );
  }

  void _drawCircle(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  void _drawSquare(
    Canvas canvas, {
    required Offset center,
    required double size,
    required Color color,
    required double rotation,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
        const Radius.circular(PlayfulGeometricRadius.small),
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  void _drawTriangle(
    Canvas canvas, {
    required Offset center,
    required double size,
    required Color color,
    required double rotation,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(0, -size / 2)
      ..lineTo(size / 2, size / 2)
      ..lineTo(-size / 2, size / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
