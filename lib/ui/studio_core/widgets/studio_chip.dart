import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

class StudioChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color? accentColor;

  const StudioChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final fill =
        selected ? accentColor ?? StudioTokens.primary : StudioTokens.surface2;
    final foreground =
        selected ? StudioTokens.onPrimary : StudioTokens.textSecondary;
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );

    final shape = RoundedRectangleBorder(
      borderRadius: StudioTokens.radiusTag,
      side: BorderSide(
        color: selected ? fill : StudioTokens.border,
      ),
    );

    return Material(
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              );
              final iconSpace = icon == null ? 0.0 : 21.0;
              final labelWidget = constraints.maxWidth.isFinite
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (constraints.maxWidth - iconSpace)
                            .clamp(0.0, constraints.maxWidth)
                            .toDouble(),
                      ),
                      child: text,
                    )
                  : text;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  labelWidget,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
