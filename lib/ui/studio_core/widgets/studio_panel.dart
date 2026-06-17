import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

class StudioPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;

  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(StudioTokens.panelPadding),
    this.margin,
    this.color = StudioTokens.surface3,
    this.borderColor = StudioTokens.cardOutline,
    this.borderRadius = StudioTokens.radiusCard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
