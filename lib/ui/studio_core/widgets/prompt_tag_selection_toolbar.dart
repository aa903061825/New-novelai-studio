import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

class PromptTagSelectionToolbar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final Key toolbarKey;
  final Key clearButtonKey;
  final bool alignRight;

  const PromptTagSelectionToolbar({
    super.key,
    required this.count,
    required this.onClear,
    required this.toolbarKey,
    required this.clearButtonKey,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final toolbar = DecoratedBox(
      key: toolbarKey,
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusBadge,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 9, right: 4, top: 3, bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\u5df2\u9009 $count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StudioTokens.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            TextButton(
              key: clearButtonKey,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: StudioTokens.textSecondary,
              ),
              onPressed: onClear,
              child: const Text('\u6e05\u7a7a'),
            ),
          ],
        ),
      ),
    );

    if (!alignRight) {
      return toolbar;
    }
    return Align(
      alignment: Alignment.centerRight,
      child: toolbar,
    );
  }
}
