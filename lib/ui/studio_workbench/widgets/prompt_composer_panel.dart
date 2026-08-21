import 'dart:async';

import 'package:flutter/material.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';

enum _PromptComposerLayout { grouped, inline }

class PromptComposerPanel extends StatefulWidget {
  final StudioWorkbenchAssetService service;

  const PromptComposerPanel({
    super.key,
    required this.service,
  });

  @override
  State<PromptComposerPanel> createState() => _PromptComposerPanelState();
}

class _PromptComposerPanelState extends State<PromptComposerPanel> {
  final Map<String, GlobalKey> _fragmentKeys = <String, GlobalKey>{};
  final TextEditingController _inlineAddController = TextEditingController();
  final FocusNode _inlineAddFocusNode = FocusNode(
    debugLabel: 'workbench-inline-prompt-add',
  );
  _PromptComposerLayout _layout = _PromptComposerLayout.grouped;
  int? _hoveredDropIndex;
  bool _inlineAdding = false;

  StudioWorkbenchAssetService get service => widget.service;

  @override
  void dispose() {
    _inlineAddController.dispose();
    _inlineAddFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        _fragmentKeys.removeWhere(
          (id, _) => service.fragments.every((fragment) => fragment.id != id),
        );
        return DragTarget<Object>(
          key: const ValueKey('workbench-prompt-drop-surface'),
          hitTestBehavior: HitTestBehavior.translucent,
          onWillAcceptWithDetails: (details) {
            if (details.data is! StudioWorkbenchPromptDropData) {
              return false;
            }
            _updateHoveredDropIndex(details.offset);
            return true;
          },
          onMove: (details) {
            if (details.data is StudioWorkbenchPromptDropData) {
              _updateHoveredDropIndex(details.offset);
            }
          },
          onLeave: (data) {
            if (data is StudioWorkbenchPromptDropData) {
              _clearHoveredDropIndex();
            }
          },
          onAcceptWithDetails: (details) {
            final data = details.data;
            if (data is! StudioWorkbenchPromptDropData) {
              return;
            }
            final targetIndex = _dropIndexForOffset(details.offset);
            final movedExisting = data is StudioWorkbenchFragmentDropData;
            data.insertAt(targetIndex);
            _clearHoveredDropIndex();
            _showDropConfirmation(
              context,
              movedExisting ? '已移动「${data.label}」' : '已加入「${data.label}」',
            );
          },
          builder: (context, candidates, rejected) => StudioPanel(
            color: StudioTokens.surface2,
            child: ListView(
              padding: EdgeInsets.zero,
              primary: false,
              shrinkWrap: true,
              children: [
                _buildHeader(context),
                const SizedBox(height: 14),
                if (_layout == _PromptComposerLayout.grouped)
                  ..._buildGroupedComposer()
                else
                  _buildInlineComposer(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
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
        SegmentedButton<_PromptComposerLayout>(
          key: const ValueKey('workbench-prompt-layout'),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelSmall,
            ),
          ),
          segments: const [
            ButtonSegment<_PromptComposerLayout>(
              value: _PromptComposerLayout.grouped,
              label: Text('分区'),
            ),
            ButtonSegment<_PromptComposerLayout>(
              value: _PromptComposerLayout.inline,
              label: Text('整条'),
            ),
          ],
          selected: {_layout},
          onSelectionChanged: (selection) {
            if (selection.isEmpty || selection.first == _layout) {
              return;
            }
            setState(() {
              _layout = selection.first;
              _hoveredDropIndex = null;
              _inlineAdding = false;
              _inlineAddController.clear();
            });
          },
        ),
        const SizedBox(width: 10),
        StudioChip(
          icon: Icons.layers_outlined,
          label: service.fragments.length.toString(),
        ),
      ],
    );
  }

  List<Widget> _buildGroupedComposer() {
    return [
      KeyedSubtree(
        key: const ValueKey('workbench-manual-positive-editor'),
        child: PromptTagEditor(
          value: service.manualPositivePrompt,
          label: '手写 Prompt',
          emptyText: '暂无手写 Prompt',
          subtleAddButton: true,
          onChanged: service.setManualPositivePrompt,
        ),
      ),
      _PromptDropSlot(index: 0, active: _hoveredDropIndex == 0),
      for (var index = 0; index < service.fragments.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            children: [
              KeyedSubtree(
                key: _fragmentKeyFor(service.fragments[index].id),
                child: StudioStaggeredReveal(
                  key: ValueKey(
                    'prompt-block-reveal-${service.fragments[index].id}',
                  ),
                  index: index,
                  columns: 1,
                  maxStaggeredItems: 8,
                  duration: const Duration(milliseconds: 190),
                  itemDelay: const Duration(milliseconds: 22),
                  beginOffset: const Offset(0, 0.026),
                  beginScale: 0.985,
                  child: _PromptBlockDraggable(
                    service: service,
                    fragment: service.fragments[index],
                    child: _PromptBlockRow(
                      service: service,
                      fragment: service.fragments[index],
                      canMoveUp: index > 0,
                      canMoveDown: index < service.fragments.length - 1,
                    ),
                  ),
                ),
              ),
              _PromptDropSlot(
                index: index + 1,
                active: _hoveredDropIndex == index + 1,
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildInlineComposer(BuildContext context) {
    final promptEditors = <Widget>[
      if (service.manualPositivePrompt.trim().isNotEmpty)
        KeyedSubtree(
          key: const ValueKey('workbench-inline-manual-prompt'),
          child: PromptTagEditor(
            value: service.manualPositivePrompt,
            onChanged: service.setManualPositivePrompt,
            dense: true,
            allowAdd: false,
            showControls: false,
            inlineSurface: true,
          ),
        ),
      for (final fragment in service.fragments)
        if (fragment.positiveText.trim().isNotEmpty)
          KeyedSubtree(
            key: ValueKey('workbench-inline-fragment-${fragment.id}'),
            child: PromptTagEditor(
              value: fragment.positiveText,
              onChanged: (value) => service.updatePositiveText(
                fragment.id,
                value,
              ),
              dense: true,
              allowAdd: false,
              showControls: false,
              inlineSurface: true,
            ),
          ),
      if (_inlineAdding)
        SizedBox(
          width: 220,
          child: TextField(
            key: const ValueKey('workbench-inline-prompt-input'),
            controller: _inlineAddController,
            focusNode: _inlineAddFocusNode,
            autofocus: true,
            minLines: 1,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              hintText: '输入标签，逗号可批量分割',
              suffixIcon: IconButton(
                tooltip: '添加标签',
                icon: const Icon(Icons.check, size: 16),
                onPressed: _submitInlineTags,
              ),
            ),
            onSubmitted: (_) => _submitInlineTags(),
          ),
        )
      else
        Tooltip(
          message: '添加标签',
          child: IconButton.outlined(
            key: const ValueKey('workbench-inline-prompt-add'),
            icon: const Icon(Icons.add, size: 15),
            style: IconButton.styleFrom(
              foregroundColor: StudioTokens.textSecondary,
              side: const BorderSide(color: StudioTokens.borderStrong),
              minimumSize: const Size.square(30),
              maximumSize: const Size.square(30),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              setState(() {
                _inlineAdding = true;
              });
            },
          ),
        ),
    ];
    final hasPrompt = service.manualPositivePrompt.trim().isNotEmpty ||
        service.fragments
            .any((fragment) => fragment.positiveText.trim().isNotEmpty);
    final dropActive = _hoveredDropIndex != null;
    return AnimatedContainer(
      key: const ValueKey('workbench-prompt-inline-editor'),
      duration: StudioMotionScope.duration(
        context,
        StudioMotionTokens.fast,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dropActive
            ? StudioTokens.primary.withAlpha(12)
            : StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(
          color: dropActive ? StudioTokens.primary : StudioTokens.borderStrong,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '整条 Prompt',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: StudioTokens.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (!hasPrompt && !_inlineAdding)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '暂无 Prompt 标签',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: promptEditors,
          ),
          if (dropActive) ...[
            const SizedBox(height: 8),
            const _PromptInlineDropHint(),
          ],
        ],
      ),
    );
  }

  GlobalKey _fragmentKeyFor(String id) =>
      _fragmentKeys.putIfAbsent(id, GlobalKey.new);

  int _dropIndexForOffset(Offset globalOffset) {
    if (_layout == _PromptComposerLayout.inline) {
      return service.fragments.length;
    }
    for (var index = 0; index < service.fragments.length; index++) {
      final context =
          _fragmentKeys[service.fragments[index].id]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      if (globalOffset.dy < top + renderObject.size.height / 2) {
        return index;
      }
    }
    return service.fragments.length;
  }

  void _updateHoveredDropIndex(Offset globalOffset) {
    final nextIndex = _dropIndexForOffset(globalOffset);
    if (_hoveredDropIndex == nextIndex || !mounted) {
      return;
    }
    setState(() {
      _hoveredDropIndex = nextIndex;
    });
  }

  void _clearHoveredDropIndex() {
    if (_hoveredDropIndex == null || !mounted) {
      return;
    }
    setState(() {
      _hoveredDropIndex = null;
    });
  }

  void _submitInlineTags() {
    final value = _inlineAddController.text.trim();
    if (value.isEmpty) {
      return;
    }
    service.setManualPositivePrompt(
      [
        if (service.manualPositivePrompt.trim().isNotEmpty)
          service.manualPositivePrompt.trim(),
        value,
      ].join(', '),
    );
    _inlineAddController.clear();
    setState(() {
      _inlineAdding = false;
    });
  }

  void _showDropConfirmation(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1600),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _PromptDropSlot extends StatelessWidget {
  final int index;
  final bool active;

  const _PromptDropSlot({
    required this.index,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      key: ValueKey('prompt-drop-target-$index'),
      duration: StudioMotionScope.duration(
        context,
        StudioMotionTokens.fast,
      ),
      curve: StudioMotionTokens.utilityCurve,
      alignment: Alignment.center,
      child: active
          ? Semantics(
              liveRegion: true,
              label: '松开插入到第 ${index + 1} 个位置',
              child: Container(
                height: 36,
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: StudioTokens.primary.withAlpha(28),
                  borderRadius: StudioTokens.radiusSlot,
                  border: Border.all(color: StudioTokens.primary),
                ),
                alignment: Alignment.center,
                child: Text(
                  '松开插入到这里',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _PromptInlineDropHint extends StatelessWidget {
  const _PromptInlineDropHint();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '松开加入整条 Prompt',
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: StudioTokens.primary.withAlpha(20),
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.primary),
        ),
        alignment: Alignment.center,
        child: Text(
          '松开加入整条 Prompt',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: StudioTokens.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
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
              subtleAddButton: true,
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
