import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';

class PromptDashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const PromptDashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor =
        selected ? StudioTokens.primary.withAlpha(28) : StudioTokens.surface2;
    final borderColor = selected ? StudioTokens.primary : StudioTokens.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: StudioTokens.radiusCard,
        onTap: onTap,
        child: StudioPanel(
          color: cardColor,
          borderColor: borderColor,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 20, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color:
                        selected ? StudioTokens.primary : StudioTokens.surface4,
                    borderRadius: StudioTokens.radiusPill,
                    border: Border.all(
                      color:
                          selected ? StudioTokens.primary : StudioTokens.border,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? StudioTokens.onPrimary
                        : StudioTokens.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color:
                        selected ? StudioTokens.primary : StudioTokens.surface3,
                    borderRadius: StudioTokens.radiusPill,
                    border: Border.all(
                      color:
                          selected ? StudioTokens.primary : StudioTokens.border,
                    ),
                  ),
                  child: Icon(
                    selected ? Icons.expand_less : Icons.expand_more,
                    color: selected
                        ? StudioTokens.onPrimary
                        : StudioTokens.textPrimary,
                    size: 20,
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
