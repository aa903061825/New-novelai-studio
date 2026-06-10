import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class StudioMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  const StudioMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor = StudioTokens.primary,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      padding: const EdgeInsets.all(14),
      color: StudioTokens.surface2,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withAlpha(32),
              borderRadius: StudioTokens.radiusPill,
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(icon, size: 18, color: accentColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
