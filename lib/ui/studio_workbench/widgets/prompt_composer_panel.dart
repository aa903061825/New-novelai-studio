import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_editor.dart';
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
          child: ListView(
            padding: EdgeInsets.zero,
            primary: false,
            shrinkWrap: true,
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
              KeyedSubtree(
                key: const ValueKey('workbench-manual-positive-editor'),
                child: PromptTagEditor(
                  value: service.manualPositivePrompt,
                  label: '手写 Prompt',
                  emptyText: '暂无手写 Prompt',
                  onChanged: service.setManualPositivePrompt,
                ),
              ),
              const SizedBox(height: 12),
              _PromptDropTarget(index: 0),
              for (var index = 0; index < service.fragments.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    children: [
                      _PromptBlockDraggable(
                        service: service,
                        fragment: service.fragments[index],
                        child: _PromptBlockRow(
                          service: service,
                          fragment: service.fragments[index],
                          canMoveUp: index > 0,
                          canMoveDown: index < service.fragments.length - 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _PromptDropTarget(index: index + 1),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PromptDropTarget extends StatelessWidget {
  final int index;

  const _PromptDropTarget({required this.index});

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is StudioWorkbenchPromptDropData,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is StudioWorkbenchPromptDropData) {
          data.insertAt(index);
        }
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          key: ValueKey('prompt-drop-target-$index'),
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          height: active ? 32 : 18,
          decoration: BoxDecoration(
            color: active
                ? StudioTokens.primary.withAlpha(28)
                : StudioTokens.surface3.withAlpha(120),
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: active ? StudioTokens.primary : StudioTokens.cardOutline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            active ? '松开插入到这里' : '拖到这里',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: active ? StudioTokens.primary : StudioTokens.textMuted,
                ),
          ),
        );
      },
    );
  }
}

class _PromptBlockDraggable extends StatelessWidget {
  final StudioWorkbenchAssetService service;
  final StudioWorkbenchAssetFragment fragment;
  final Widget child;

  const _PromptBlockDraggable({
    required this.service,
    required this.fragment,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<Object>(
      data: StudioWorkbenchFragmentDropData(
        service: service,
        fragmentId: fragment.id,
        label: fragment.name,
      ),
      feedback: _PromptDragFeedback(
        label: fragment.name,
        typeLabel: fragment.typeLabel,
      ),
      childWhenDragging: Opacity(
        opacity: 0.38,
        child: child,
      ),
      child: child,
    );
  }
}

class _PromptDragFeedback extends StatelessWidget {
  final String label;
  final String typeLabel;

  const _PromptDragFeedback({
    required this.label,
    required this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.primary),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.drag_indicator,
              size: 18,
              color: StudioTokens.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$typeLabel · $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
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
          KeyedSubtree(
            key: ValueKey('prompt-block-editor-${fragment.id}'),
            child: PromptTagEditor(
              value: fragment.positiveText,
              label: 'Prompt 块',
              dense: true,
              onChanged: (value) => service.updatePositiveText(
                fragment.id,
                value,
              ),
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
