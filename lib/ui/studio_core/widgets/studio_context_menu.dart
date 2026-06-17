import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

enum StudioContextMenuAnchorCorner {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
}

enum StudioContextMenuItemTone {
  normal,
  highlight,
  destructive,
}

sealed class StudioContextMenuEntry<T> {
  const StudioContextMenuEntry();
}

class StudioContextMenuDivider<T> extends StudioContextMenuEntry<T> {
  const StudioContextMenuDivider();
}

class StudioContextMenuItem<T> extends StudioContextMenuEntry<T> {
  final Key? key;
  final T value;
  final IconData icon;
  final String label;
  final String? shortcut;
  final bool enabled;
  final StudioContextMenuItemTone tone;

  const StudioContextMenuItem({
    this.key,
    required this.value,
    required this.icon,
    required this.label,
    this.shortcut,
    this.enabled = true,
    this.tone = StudioContextMenuItemTone.normal,
  });
}

class StudioContextMenu {
  static Future<T?> show<T>({
    required BuildContext context,
    required Offset position,
    required List<StudioContextMenuEntry<T>> items,
    String? targetLabel,
    StudioContextMenuAnchorCorner anchorCorner =
        StudioContextMenuAnchorCorner.topLeft,
  }) {
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: const Color(0xFF181818),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: anchorBorderRadius(anchorCorner),
        side: const BorderSide(color: StudioTokens.borderStrong),
      ),
      constraints: const BoxConstraints(minWidth: 236, maxWidth: 320),
      items: [
        if (targetLabel != null && targetLabel.trim().isNotEmpty)
          PopupMenuItem<T>(
            enabled: false,
            height: 34,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(
                targetLabel.trim(),
                key: const ValueKey('studio-context-menu-target-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        for (final item in items) _entry(context, item),
      ],
    );
  }

  static BorderRadius anchorBorderRadius(
    StudioContextMenuAnchorCorner corner,
  ) {
    const round = Radius.circular(18);
    return BorderRadius.only(
      topLeft:
          corner == StudioContextMenuAnchorCorner.topLeft ? Radius.zero : round,
      topRight: corner == StudioContextMenuAnchorCorner.topRight
          ? Radius.zero
          : round,
      bottomRight: corner == StudioContextMenuAnchorCorner.bottomRight
          ? Radius.zero
          : round,
      bottomLeft: corner == StudioContextMenuAnchorCorner.bottomLeft
          ? Radius.zero
          : round,
    );
  }

  static PopupMenuEntry<T> _entry<T>(
    BuildContext context,
    StudioContextMenuEntry<T> entry,
  ) {
    if (entry is StudioContextMenuDivider<T>) {
      return const PopupMenuDivider(height: 12);
    }
    final item = entry as StudioContextMenuItem<T>;
    return PopupMenuItem<T>(
      key: item.key,
      value: item.value,
      enabled: item.enabled,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _StudioContextMenuRow<T>(item: item),
    );
  }

  const StudioContextMenu._();
}

class _StudioContextMenuRow<T> extends StatelessWidget {
  final StudioContextMenuItem<T> item;

  const _StudioContextMenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.tone) {
      StudioContextMenuItemTone.destructive => StudioTokens.danger,
      StudioContextMenuItemTone.highlight => StudioTokens.textPrimary,
      StudioContextMenuItemTone.normal => StudioTokens.textPrimary,
    };
    final iconColor = switch (item.tone) {
      StudioContextMenuItemTone.destructive => StudioTokens.danger,
      StudioContextMenuItemTone.highlight => StudioTokens.primary,
      StudioContextMenuItemTone.normal => StudioTokens.primary,
    };
    final background = switch (item.tone) {
      StudioContextMenuItemTone.highlight => StudioTokens.primary.withAlpha(32),
      _ => Colors.transparent,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(item.icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (item.shortcut != null && item.shortcut!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                item.shortcut!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
