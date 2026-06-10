import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

enum StudioButtonTone { primary, secondary, ghost, danger, warning }

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
      StudioButtonTone.warning => StudioTokens.onPrimary,
    };
    final background = switch (tone) {
      StudioButtonTone.primary => StudioTokens.primary,
      StudioButtonTone.secondary => StudioTokens.secondary,
      StudioButtonTone.ghost => StudioTokens.surface2,
      StudioButtonTone.danger => StudioTokens.danger,
      StudioButtonTone.warning => StudioTokens.warning,
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
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return StudioTokens.textMuted;
          }
          return foreground;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return StudioTokens.surface2;
          }
          if (states.contains(WidgetState.pressed)) {
            return _pressedBackground(background);
          }
          if (states.contains(WidgetState.hovered)) {
            return _hoveredBackground(background);
          }
          return background;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.black.withAlpha(18);
          }
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withAlpha(16);
          }
          return null;
        }),
        shape: WidgetStateProperty.all(const StadiumBorder()),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: WidgetStateProperty.all(0),
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
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return StudioTokens.textMuted;
            }
            return selected
                ? StudioTokens.onPrimary
                : StudioTokens.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return StudioTokens.surface2;
            }
            final background =
                selected ? StudioTokens.primary : StudioTokens.surface2;
            if (states.contains(WidgetState.pressed)) {
              return _pressedBackground(background);
            }
            if (states.contains(WidgetState.hovered)) {
              return selected ? StudioTokens.secondary : StudioTokens.surface3;
            }
            return background;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return StudioTokens.primary.withAlpha(40);
            }
            if (states.contains(WidgetState.hovered)) {
              return StudioTokens.primary.withAlpha(24);
            }
            return null;
          }),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

Color _hoveredBackground(Color backgroundColor) {
  if (backgroundColor == StudioTokens.primary) {
    return const Color(0xFFFFF04A);
  }
  if (backgroundColor == StudioTokens.secondary) {
    return const Color(0xFFB8EC4E);
  }
  if (backgroundColor == StudioTokens.warning) {
    return const Color(0xFFFFAD63);
  }
  if (backgroundColor == StudioTokens.danger) {
    return const Color(0xFFFF6666);
  }
  if (backgroundColor == StudioTokens.surface2) {
    return StudioTokens.surface3;
  }
  return Color.lerp(backgroundColor, Colors.white, 0.08) ?? backgroundColor;
}

Color _pressedBackground(Color backgroundColor) {
  return Color.lerp(backgroundColor, Colors.black, 0.08) ?? backgroundColor;
}
