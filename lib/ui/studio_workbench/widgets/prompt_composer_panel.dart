import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class PromptComposerPanel extends StatelessWidget {
  final StudioWorkbenchAssetService service;

  const PromptComposerPanel({
    super.key,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        return StudioPanel(
          color: StudioTokens.surface2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.view_column_outlined,
                      color: StudioTokens.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Prompt 编排',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    StudioChip(
                      icon: Icons.layers_outlined,
                      label: service.fragments.length.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('workbench-manual-positive-field'),
                  initialValue: service.manualPositivePrompt,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '手写 Prompt',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                  keyboardType: TextInputType.multiline,
                  onChanged: service.setManualPositivePrompt,
                ),
                const SizedBox(height: 12),
                if (service.fragments.isEmpty)
                  const _EmptyBlockStack()
                else
                  for (var index = 0;
                      index < service.fragments.length;
                      index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PromptBlockRow(
                        service: service,
                        fragment: service.fragments[index],
                        canMoveUp: index > 0,
                        canMoveDown: index < service.fragments.length - 1,
                      ),
                    ),
                const SizedBox(height: 2),
                TextFormField(
                  key: const ValueKey('workbench-negative-field'),
                  initialValue: service.manualNegativePrompt,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '负面词',
                    prefixIcon: Icon(Icons.do_not_disturb),
                  ),
                  keyboardType: TextInputType.multiline,
                  onChanged: service.setManualNegativePrompt,
                ),
                const SizedBox(height: 12),
                _PromptPreview(
                  positive: service.payloadConfig.overridePrompt,
                  negative: service.payloadConfig.paramConfig.negativePrompt,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromptBlockRow extends StatelessWidget {
  final StudioWorkbenchAssetService service;
  final StudioWorkbenchAssetFragment fragment;
  final bool canMoveUp;
  final bool canMoveDown;

  const _PromptBlockRow({
    required this.service,
    required this.fragment,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StudioChip(
                icon: Icons.auto_awesome_mosaic_outlined,
                label: fragment.typeLabel,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fragment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              StudioIconButton(
                key: ValueKey('prompt-block-up-${fragment.id}'),
                tooltip: '上移',
                icon: Icons.keyboard_arrow_up,
                onPressed: canMoveUp
                    ? () => service.moveFragment(
                          fragment.id,
                          service.fragments.indexOf(fragment) - 1,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                key: ValueKey('prompt-block-down-${fragment.id}'),
                tooltip: '下移',
                icon: Icons.keyboard_arrow_down,
                onPressed: canMoveDown
                    ? () => service.moveFragment(
                          fragment.id,
                          service.fragments.indexOf(fragment) + 1,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                key: ValueKey('prompt-block-remove-${fragment.id}'),
                tooltip: '移除',
                icon: Icons.close,
                onPressed: () => service.removeFragment(fragment.id),
              ),
              if (service.canSaveBack(fragment)) ...[
                const SizedBox(width: 6),
                StudioIconButton(
                  key: ValueKey('prompt-block-save-${fragment.id}'),
                  tooltip: '保存回素材库',
                  icon: Icons.save_outlined,
                  onPressed: () {
                    unawaited(_saveBack(context));
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('prompt-block-field-${fragment.id}'),
            initialValue: fragment.positiveText,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Prompt 块',
              isDense: true,
            ),
            keyboardType: TextInputType.multiline,
            onChanged: (value) => service.updatePositiveText(
              fragment.id,
              value,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBack(BuildContext context) async {
    try {
      await service.saveBack(fragment.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存回素材库')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }
}

class _PromptPreview extends StatelessWidget {
  final String positive;
  final String negative;

  const _PromptPreview({
    required this.positive,
    required this.negative,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('正向预览', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            positive.trim().isEmpty ? '暂无正向 Prompt' : positive,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: positive.trim().isEmpty
                      ? StudioTokens.textMuted
                      : StudioTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          Text('负面预览', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            negative.trim().isEmpty ? '暂无负面词' : negative,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: negative.trim().isEmpty
                      ? StudioTokens.textMuted
                      : StudioTokens.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBlockStack extends StatelessWidget {
  const _EmptyBlockStack();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Text(
        '还没有 Prompt 块',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
