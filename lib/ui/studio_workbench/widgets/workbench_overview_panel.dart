import 'package:flutter/material.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';

class WorkbenchOverviewPanel extends StatelessWidget {
  final PayloadConfig payloadConfig;
  final StudioWorkbenchAssetService? assetService;

  const WorkbenchOverviewPanel({
    super.key,
    required this.payloadConfig,
    this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    final service = assetService;
    if (service != null) {
      return ListenableBuilder(
        listenable: service,
        builder: (context, _) => _buildPanel(context, service),
      );
    }
    return _buildPanel(context, null);
  }

  Widget _buildPanel(
    BuildContext context,
    StudioWorkbenchAssetService? service,
  ) {
    final prompt = payloadConfig.useOverridePrompt
        ? payloadConfig.overridePrompt
        : payloadConfig.rootPromptConfig.comment;
    final promptGroups = promptTagGroupsFromPayloadConfig(payloadConfig);
    final fragments = service?.fragments ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: StudioPanel(
        color: StudioTokens.surface2,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.dashboard_customize_outlined,
                  color: StudioTokens.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '工作台',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (fragments.isNotEmpty)
                  StudioIconButton(
                    tooltip: '清空素材栈',
                    icon: Icons.clear_all,
                    onPressed: service?.clearFragments,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(minHeight: 54, maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StudioTokens.surfaceBase,
                borderRadius: StudioTokens.radiusSlot,
                border: StudioTokens.cardBorder,
              ),
              child: SingleChildScrollView(
                child: promptGroups.isNotEmpty
                    ? PromptTagGroupDisplay(
                        key: const ValueKey('workbench-overview-prompt-tags'),
                        groups: promptGroups,
                        groupKeyPrefix: 'workbench-overview-prompt-group',
                        tagKeyPrefix: 'workbench-overview-prompt-group-tags',
                        defaultTranslated: true,
                        dense: true,
                        maxTags: 8,
                        enableHoverShortcut: true,
                        initialLayoutMode: PromptTagLayoutMode.grouped,
                      )
                    : PromptTagDisplay(
                        text: prompt,
                        dense: true,
                        maxTags: 8,
                        emptyText:
                            '\u628a\u7d20\u6750\u9001\u8fdb\u6765\uff0c\u6216\u76f4\u63a5\u5199\u4e0b\u8fd9\u6b21\u60f3\u751f\u6210\u7684 Prompt\u3002',
                        enableHoverShortcut: prompt.trim().isNotEmpty,
                      ),
              ),
            ),
            if (fragments.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '素材栈',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fragments.length.toString(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: StudioTokens.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fragment in fragments)
                    StudioChip(
                      icon: Icons.add_link,
                      label: '${fragment.typeLabel} · ${fragment.name}',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StudioChip(
                  icon: Icons.group_outlined,
                  label: '角色 ${payloadConfig.characterConfigList.length}',
                ),
                StudioChip(
                  icon: Icons.bookmark_border,
                  label: '保存配置 ${payloadConfig.savedPromptConfigList.length}',
                ),
                StudioChip(
                  icon: Icons.rule,
                  label: '替换规则 ${payloadConfig.promptReplaceRules.length}',
                ),
                StudioChip(
                  icon: Icons.tune,
                  label: 'Steps ${payloadConfig.paramConfig.steps}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
