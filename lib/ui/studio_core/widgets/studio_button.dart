import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

enum StudioButtonTone { primary, secondary, ghost, danger }

class StudioButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final StudioButtonTone tone;

  const StudioButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = StudioButtonTone.primary,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = switch (tone) {
      StudioButtonTone.primary => StudioTokens.onPrimary,
      StudioButtonTone.secondary => StudioTokens.onPrimary,
      StudioButtonTone.ghost => StudioTokens.textPrimary,
      StudioButtonTone.danger => Colors.white,
    };
    final background = switch (tone) {
      StudioButtonTone.primary => StudioTokens.primary,
      StudioButtonTone.secondary => StudioTokens.secondary,
      StudioButtonTone.ghost => StudioTokens.surface2,
      StudioButtonTone.danger => StudioTokens.danger,
    };

    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label, overflow: TextOverflow.ellipsis),
            ],
          );

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: StudioTokens.surface2,
        disabledForegroundColor: StudioTokens.textMuted,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

class StudioIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  const StudioIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor:
              selected ? StudioTokens.primary : StudioTokens.surface2,
          foregroundColor:
              selected ? StudioTokens.onPrimary : StudioTokens.textSecondary,
          disabledBackgroundColor: StudioTokens.surface2,
          disabledForegroundColor: StudioTokens.textMuted,
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
