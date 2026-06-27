import 'dart:convert';
import 'dart:io';

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/services/prompt_workshop_bridge.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_presence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_drawer_motion.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_list_utils.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/filter_rules_library_dialog.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_drag.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_drawer_shell.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_hover_preview_thumbnail.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_metric_card.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_recast_plan.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';

const _scriptPromptFilterRuleTargets = [
  PromptTagFilterRuleTarget.deleteKeywords,
  PromptTagFilterRuleTarget.strongFilterKeywords,
  PromptTagFilterRuleTarget.replaceSource,
  PromptTagFilterRuleTarget.scriptScopedBlockWords,
];

typedef ScriptAssetFavoriteKeysLoader = Future<Set<String>> Function();
typedef ScriptAssetFavoriteSetter = Future<void> Function(
  String key,
  bool isFavorite,
);
typedef ScriptProductionSendHandler = FutureOr<void> Function(
  Future<bool> sendFuture,
);
typedef _ViewModelSelectorBuilder<T> = Widget Function(
  BuildContext context,
  T selected,
);

class _ViewModelSelector<T> extends StatefulWidget {
  final StudioScriptViewModel viewModel;
  final T Function(StudioScriptViewModel viewModel) select;
  final _ViewModelSelectorBuilder<T> builder;

  const _ViewModelSelector({
    required this.viewModel,
    required this.select,
    required this.builder,
  });

  @override
  State<_ViewModelSelector<T>> createState() => _ViewModelSelectorState<T>();
}

class _ViewModelSelectorState<T> extends State<_ViewModelSelector<T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.select(widget.viewModel);
    widget.viewModel.addListener(_handleViewModelChanged);
  }

  @override
  void didUpdateWidget(covariant _ViewModelSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_handleViewModelChanged);
      widget.viewModel.addListener(_handleViewModelChanged);
    }
    _selected = widget.select(widget.viewModel);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleViewModelChanged);
    super.dispose();
  }

  void _handleViewModelChanged() {
    final next = widget.select(widget.viewModel);
    if (next == _selected) {
      return;
    }
    setState(() {
      _selected = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _selected);
  }
}

class StudioScriptPage extends StatefulWidget {
  final StudioScriptViewModel viewModel;
  final ScriptProductionSendHandler? onSentToProduction;
  final StudioScriptAssetFocus? assetFocus;
  final ScriptAssetFavoriteKeysLoader? loadAssetFavoriteKeys;
  final ScriptAssetFavoriteSetter? setAssetFavorite;

  const StudioScriptPage({
    super.key,
    required this.viewModel,
    this.onSentToProduction,
    this.assetFocus,
    this.loadAssetFavoriteKeys,
    this.setAssetFavorite,
  });

  @override
  State<StudioScriptPage> createState() => _StudioScriptPageState();
}

class _StudioScriptPageState extends State<StudioScriptPage> {
  static const int _contentReadyPhase = 4;

  int _contentWarmupPhase = _contentReadyPhase;
  int _contentWarmupGeneration = 0;
  bool _wasImportingScript = false;

  @override
  void initState() {
    super.initState();
    _wasImportingScript = widget.viewModel.isImportingScript;
    _contentWarmupPhase = _wasImportingScript ? 0 : _contentReadyPhase;
    widget.viewModel.addListener(_handleImportStateChanged);
  }

  @override
  void didUpdateWidget(covariant StudioScriptPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) return;
    oldWidget.viewModel.removeListener(_handleImportStateChanged);
    _wasImportingScript = widget.viewModel.isImportingScript;
    _contentWarmupPhase = _wasImportingScript ? 0 : _contentReadyPhase;
    widget.viewModel.addListener(_handleImportStateChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleImportStateChanged);
    super.dispose();
  }

  void _handleImportStateChanged() {
    final importing = widget.viewModel.isImportingScript;
    if (importing) {
      _contentWarmupGeneration += 1;
      _wasImportingScript = true;
      if (_contentWarmupPhase != 0 && mounted) {
        setState(() {
          _contentWarmupPhase = 0;
        });
      }
      return;
    }
    if (!_wasImportingScript) {
      return;
    }
    _wasImportingScript = false;
    _startContentWarmup();
  }

  void _startContentWarmup() {
    final generation = ++_contentWarmupGeneration;
    if (mounted) {
      setState(() {
        _contentWarmupPhase = 0;
      });
    }
    unawaited(_advanceContentWarmup(generation));
  }

  Future<void> _advanceContentWarmup(int generation) async {
    for (var phase = 1; phase <= _contentReadyPhase; phase += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted ||
          generation != _contentWarmupGeneration ||
          widget.viewModel.isImportingScript) {
        return;
      }
      setState(() {
        _contentWarmupPhase = phase;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Material(
      color: StudioTokens.surface1,
      child: SingleChildScrollView(
        key: const ValueKey('studio-script-page-body'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ViewModelSelector(
              viewModel: viewModel,
              select: (viewModel) => (
                viewModel.folderStatus,
                viewModel.isImportingScript,
                viewModel.importProgressLabel,
                viewModel.importProgressValue,
                viewModel.aiStatus,
                viewModel.isAiBusy,
                viewModel.isExtractingAiRoleEvidence,
                viewModel.isApplyingAiRoleExtraction,
                viewModel.showAiProgressPanel,
                viewModel.aiProgressSteps,
                viewModel.lastProductionPlanName,
                viewModel.isSendingToProduction,
                viewModel.sentToProduction,
              ),
              builder: (context, _) => _Header(
                viewModel: viewModel,
                onSentToProduction: widget.onSentToProduction,
              ),
            ),
            _ViewModelSelector(
              viewModel: viewModel,
              select: (viewModel) => (
                viewModel.showAiProgressPanel,
                viewModel.aiProgressSteps,
                viewModel.isAiBusy,
                viewModel.aiProgressTitle,
                viewModel.aiStatus,
                viewModel.aiRoleExtractionRequestPreview,
                viewModel.aiRoleExtractionTraceEvents,
                viewModel.aiRoleExtractionReasoningContent,
                viewModel.aiRoleExtractionStreamingContent,
                viewModel.aiRoleExtractionRequestCount,
                viewModel.aiRoleExtraction,
              ),
              builder: (context, _) {
                return StudioAnimatedPresence(
                  key: const ValueKey('script-ai-progress-presence'),
                  visible: viewModel.showAiProgressPanel,
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      _AiProgressPanel(viewModel: viewModel),
                    ],
                  ),
                );
              },
            ),
            if (viewModel.isImportingScript) ...[
              const SizedBox(height: 16),
              _ScriptImportQueuePanel(viewModel: viewModel),
            ] else ...[
              const SizedBox(height: 16),
              _ViewModelSelector(
                viewModel: viewModel,
                select: (viewModel) => (
                  viewModel.frameCount,
                  viewModel.parsedCount,
                  viewModel.warningCount,
                  viewModel.roleCount,
                ),
                builder: (context, _) => _Metrics(viewModel: viewModel),
              ),
              _ViewModelSelector(
                viewModel: viewModel,
                select: (viewModel) => viewModel.hasChangedSourceCache,
                builder: (context, hasChangedSourceCache) {
                  return StudioAnimatedPresence(
                    key: const ValueKey('script-changed-source-cache-presence'),
                    visible: hasChangedSourceCache,
                    builder: (context) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        _ChangedSourceCacheActions(viewModel: viewModel),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_contentWarmupPhase < 1)
                _ScriptContentWarmupPanel(
                  phase: _contentWarmupPhase,
                  totalPhases: _contentReadyPhase,
                )
              else
                _ScriptWorkbenchLayout(
                  viewModel: viewModel,
                  assetFocus: widget.assetFocus,
                  loadAssetFavoriteKeys: widget.loadAssetFavoriteKeys,
                  setAssetFavorite: widget.setAssetFavorite,
                ),
              const SizedBox(height: 16),
              if (_contentWarmupPhase < 2)
                const SizedBox.shrink()
              else
                _ViewModelSelector(
                  viewModel: viewModel,
                  select: (viewModel) => viewModel.timeline,
                  builder: (context, _) => KeyedSubtree(
                    key: const ValueKey('script-layout-bottom-timeline'),
                    child: _TimelinePanel(viewModel: viewModel),
                  ),
                ),
              const SizedBox(height: 16),
              if (_contentWarmupPhase < 3)
                const SizedBox.shrink()
              else
                _ViewModelSelector(
                  viewModel: viewModel,
                  select: (viewModel) => (
                    viewModel.selectedFrameTagGroups,
                    viewModel.selectedFramePreviews,
                  ),
                  builder: (context, _) => KeyedSubtree(
                    key: const ValueKey('script-layout-bottom-replaced-prompt'),
                    child: _SelectedFrameReplacedPrompt(
                      viewModel: viewModel,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_contentWarmupPhase < 4)
                const SizedBox.shrink()
              else
                _ViewModelSelector(
                  viewModel: viewModel,
                  select: (viewModel) => (
                    viewModel.recastPlan.frameReviews,
                    viewModel.selectedFramePreviews,
                    viewModel.roleReplacementMappings,
                    viewModel.sceneReplacementMappings,
                    viewModel.selectedFrameIndex,
                  ),
                  builder: (context, _) => KeyedSubtree(
                    key: const ValueKey('script-layout-bottom-frame-cards'),
                    child: _SelectedFrameCards(viewModel: viewModel),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScriptImportQueuePanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ScriptImportQueuePanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final value = viewModel.importProgressValue;
    final percent =
        value == null ? null : '${(value.clamp(0, 1) * 100).round()}%';
    return StudioPanel(
      key: const ValueKey('script-import-queue-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pending_actions_outlined,
                color: StudioTokens.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  viewModel.importProgressLabel.isEmpty
                      ? '正在队列加载剧本工作中...'
                      : viewModel.importProgressLabel,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              if (percent != null) ...[
                const SizedBox(width: 12),
                Text(
                  percent,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: StudioTokens.primary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: StudioTokens.radiusPill,
            child: LinearProgressIndicator(
              key: const ValueKey('script-import-queue-progress-bar'),
              value: value,
              minHeight: 7,
              backgroundColor: StudioTokens.surface3,
              color: StudioTokens.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '素材和角色字段会分批挂载，当前页面先保持可响应。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StudioTokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScriptContentWarmupPanel extends StatelessWidget {
  final int phase;
  final int totalPhases;

  const _ScriptContentWarmupPanel({
    required this.phase,
    required this.totalPhases,
  });

  @override
  Widget build(BuildContext context) {
    final safeTotal = totalPhases <= 0 ? 1 : totalPhases;
    final value = (phase / safeTotal).clamp(0.0, 1.0).toDouble();
    return StudioPanel(
      key: const ValueKey('script-content-warmup-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.view_week_outlined,
                color: StudioTokens.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '正在分批挂载工作台内容...',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: StudioTokens.primary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: StudioTokens.radiusPill,
            child: LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: StudioTokens.surface3,
              color: StudioTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptWorkbenchLayout extends StatelessWidget {
  final StudioScriptViewModel viewModel;
  final StudioScriptAssetFocus? assetFocus;
  final ScriptAssetFavoriteKeysLoader? loadAssetFavoriteKeys;
  final ScriptAssetFavoriteSetter? setAssetFavorite;

  const _ScriptWorkbenchLayout({
    required this.viewModel,
    required this.assetFocus,
    required this.loadAssetFavoriteKeys,
    required this.setAssetFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final mainWorkspace = _ScriptRecastPlanWorkspace(viewModel: viewModel);
        if (!wide) {
          return Column(
            children: [
              SizedBox(
                key: const ValueKey('script-layout-left-drawer'),
                height: 360,
                child: _ScopedScriptAssetDrawer(
                  viewModel: viewModel,
                  assetFocus: assetFocus,
                  loadAssetFavoriteKeys: loadAssetFavoriteKeys,
                  setAssetFavorite: setAssetFavorite,
                ),
              ),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: const ValueKey('script-layout-main-workspace'),
                child: mainWorkspace,
              ),
            ],
          );
        }
        final preferredWorkspaceHeight =
            MediaQuery.sizeOf(context).height - 220;
        final workspaceHeight =
            preferredWorkspaceHeight < 620 ? 620.0 : preferredWorkspaceHeight;
        return ConstrainedBox(
          constraints: BoxConstraints.tightFor(
            height: workspaceHeight,
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: studioAssetDrawerWidth + studioAssetDrawerGap,
                ),
                child: KeyedSubtree(
                  key: const ValueKey(
                    'script-layout-main-workspace',
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey(
                      'script-layout-main-workspace-scroll',
                    ),
                    child: mainWorkspace,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: studioAssetDrawerWidth,
                child: SizedBox(
                  key: const ValueKey('script-layout-left-drawer'),
                  child: _ScopedScriptAssetDrawer(
                    viewModel: viewModel,
                    assetFocus: assetFocus,
                    loadAssetFavoriteKeys: loadAssetFavoriteKeys,
                    setAssetFavorite: setAssetFavorite,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScopedScriptAssetDrawer extends StatelessWidget {
  final StudioScriptViewModel viewModel;
  final StudioScriptAssetFocus? assetFocus;
  final ScriptAssetFavoriteKeysLoader? loadAssetFavoriteKeys;
  final ScriptAssetFavoriteSetter? setAssetFavorite;

  const _ScopedScriptAssetDrawer({
    required this.viewModel,
    required this.assetFocus,
    required this.loadAssetFavoriteKeys,
    required this.setAssetFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return _ViewModelSelector(
      viewModel: viewModel,
      select: (viewModel) => (
        viewModel.characterOptions,
        viewModel.artistChainOptions,
        _scriptAssetDrawerPreviewSignature(viewModel),
      ),
      builder: (context, _) => _ScriptAssetDrawer(
        viewModel: viewModel,
        assetFocus: assetFocus,
        loadAssetFavoriteKeys: loadAssetFavoriteKeys,
        setAssetFavorite: setAssetFavorite,
      ),
    );
  }
}

String _scriptAssetDrawerPreviewSignature(StudioScriptViewModel viewModel) {
  final parts = <String>[];
  for (final character in viewModel.characterOptions) {
    parts.addAll(viewModel.characterPreviewPaths(character));
    for (final outfit in character.outfits) {
      parts.addAll(viewModel.outfitPreviewPaths(character, outfit));
    }
  }
  for (final chain in viewModel.artistChainOptions) {
    parts.addAll(viewModel.artistChainPreviewPaths(chain));
  }
  return parts.join('\u001f');
}

Future<void> _showAssetCaptureDraft(
  BuildContext context,
  StudioAssetCaptureDraft draft,
) async {
  final host = StudioAssetCaptureHost.maybeOf(context);
  if (host == null) {
    return;
  }
  try {
    await host.showDraft(draft);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

class _Header extends StatelessWidget {
  final StudioScriptViewModel viewModel;
  final ScriptProductionSendHandler? onSentToProduction;

  const _Header({
    required this.viewModel,
    this.onSentToProduction,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('script-header-panel'),
      color: StudioTokens.surface2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = _HeaderSummary(viewModel: viewModel);
          final actions = _HeaderActions(
            viewModel: viewModel,
            onSentToProduction: onSentToProduction,
          );
          if (constraints.maxWidth < 980) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 14),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: summary),
              const SizedBox(width: 20),
              Flexible(
                child: Align(
                  alignment: Alignment.topRight,
                  child: actions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlobalPromptPrefixTagRow extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _GlobalPromptPrefixTagRow({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('script-global-prompt-prefix-row'),
      child: PromptTagEditor(
        key: const ValueKey('script-global-prompt-prefix'),
        label: '提示词',
        value: viewModel.globalPromptPrefix,
        dense: true,
        emptyText: '未设置',
        allowAdd: true,
        enableTagActions: true,
        showControls: true,
        onAddToFilterRules: viewModel.addTagsToFilterRulesLibrary,
        onChanged: viewModel.setGlobalPromptPrefix,
      ),
    );
  }
}

class _GlobalPromptPrefixPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _GlobalPromptPrefixPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      key: const ValueKey('script-global-prompt-prefix-panel'),
      title: '全局前置提示词',
      icon: Icons.vertical_align_top_outlined,
      children: [
        _GlobalPromptPrefixTagRow(viewModel: viewModel),
      ],
    );
  }
}

class _HeaderSummary extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _HeaderSummary({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '剧本',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: StudioTokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          viewModel.folderStatus,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (viewModel.isImportingScript) ...[
          const SizedBox(height: 8),
          _ImportProgressBanner(viewModel: viewModel),
        ],
        const SizedBox(height: 8),
        _AiStatusBanner(viewModel: viewModel),
        if (viewModel.lastProductionPlanName != null) ...[
          const SizedBox(height: 6),
          Text(
            viewModel.lastProductionPlanName!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ],
    );
  }
}

class _ImportProgressBanner extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ImportProgressBanner({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final progressValue = viewModel.importProgressValue;
    final percentLabel = progressValue == null
        ? null
        : '${(progressValue.clamp(0, 1) * 100).round()}%';
    return Container(
      key: const ValueKey('script-import-progress-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.primary.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.hourglass_top_outlined,
                size: 18,
                color: StudioTokens.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  viewModel.importProgressLabel.isEmpty
                      ? '正在导入剧本...'
                      : viewModel.importProgressLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (percentLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  percentLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.primary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: StudioTokens.radiusPill,
            child: LinearProgressIndicator(
              key: const ValueKey('script-import-progress-bar'),
              value: progressValue,
              minHeight: 6,
              backgroundColor: StudioTokens.surface3,
              color: StudioTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActions extends StatefulWidget {
  final StudioScriptViewModel viewModel;
  final ScriptProductionSendHandler? onSentToProduction;

  const _HeaderActions({
    required this.viewModel,
    this.onSentToProduction,
  });

  @override
  State<_HeaderActions> createState() => _HeaderActionsState();
}

class _HeaderActionsState extends State<_HeaderActions> {
  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final isAiActionBusy = viewModel.isAiBusy;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StudioButton(
          label: '导入剧本',
          icon: viewModel.isImportingScript
              ? Icons.hourglass_top_outlined
              : Icons.folder_open_outlined,
          tone: StudioButtonTone.secondary,
          onPressed: viewModel.isImportingScript
              ? null
              : () {
                  viewModel.importScriptFolder();
                },
        ),
        if (viewModel.isAiBusy)
          StudioButton(
            key: const ValueKey('script-ai-stop-processing'),
            label: '停止 AI',
            icon: Icons.stop_circle_outlined,
            tone: StudioButtonTone.danger,
            onPressed: viewModel.stopAiProcessing,
          ),
        StudioButton(
          label: viewModel.isExtractingAiRoleEvidence ? '字段整理中' : 'AI 整理角色字段',
          icon: viewModel.isExtractingAiRoleEvidence
              ? Icons.hourglass_top_outlined
              : Icons.auto_awesome_outlined,
          tone: StudioButtonTone.secondary,
          onPressed: isAiActionBusy
              ? null
              : () {
                  viewModel.generateAiRoleExtraction();
                },
        ),
        _GlobalBlockWordsButton(viewModel: viewModel),
        StudioButton(
          key: const ValueKey('script-send-production'),
          label: viewModel.isSendingToProduction
              ? '发送中...'
              : viewModel.sentToProduction
                  ? '已发送到批量产线'
                  : '发送到批量产线',
          icon: viewModel.isSendingToProduction
              ? Icons.hourglass_top_outlined
              : Icons.outbox_outlined,
          onPressed: viewModel.isSendingToProduction
              ? null
              : () {
                  final sendFuture = viewModel.sendToProduction();
                  final handler = widget.onSentToProduction;
                  if (handler == null) {
                    return;
                  }
                  unawaited(Future<void>.sync(
                    () => handler(sendFuture),
                  ));
                },
        ),
      ],
    );
  }
}

class _GlobalBlockWordsButton extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _GlobalBlockWordsButton({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return StudioButton(
      key: const ValueKey('script-filter-rules-library-button'),
      label: '屏蔽库',
      icon: Icons.block_outlined,
      tone: StudioButtonTone.secondary,
      onPressed: () => _showDialog(context),
    );
  }

  Future<void> _showDialog(BuildContext context) async {
    await showFilterRulesLibraryDialog(
      context,
      loadConfig: viewModel.loadFilterRuleConfig,
      saveConfig: viewModel.saveFilterRuleConfig,
    );
  }
}

class _GlobalBlockWordsDialog extends StatefulWidget {
  final StudioScriptViewModel viewModel;

  const _GlobalBlockWordsDialog({required this.viewModel});

  @override
  State<_GlobalBlockWordsDialog> createState() =>
      _GlobalBlockWordsDialogState();
}

class _GlobalBlockWordsDialogState extends State<_GlobalBlockWordsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.viewModel.globalBlockWords);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StudioTokens.surface2,
      title: const Text('全局屏蔽词'),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const ValueKey('script-global-block-words-field'),
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '用逗号或换行分隔',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('script-global-block-words-save'),
          onPressed: () async {
            await widget.viewModel.saveGlobalBlockWords(_controller.text);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _Metrics({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 4 ? 3.7 : 3.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            StudioMetricCard(
              label: '帧数',
              value: viewModel.frameCount.toString(),
              icon: Icons.movie_creation_outlined,
            ),
            StudioMetricCard(
              label: '已解析',
              value: viewModel.parsedCount.toString(),
              icon: Icons.fact_check_outlined,
              accentColor: StudioTokens.active,
            ),
            StudioMetricCard(
              label: '警告',
              value: viewModel.warningCount.toString(),
              icon: Icons.warning_amber_outlined,
              accentColor: StudioTokens.warning,
            ),
            StudioMetricCard(
              label: '角色槽',
              value: viewModel.roleCount.toString(),
              icon: Icons.groups_2_outlined,
              accentColor: StudioTokens.info,
            ),
          ],
        );
      },
    );
  }
}

enum _ScriptAssetDragKind { character, outfit, outfitPart, artistChain }

class _ScriptAssetDragData {
  final _ScriptAssetDragKind kind;
  final String label;
  final String? characterId;
  final String? outfitId;
  final String? artistChainId;
  final StudioScriptRolePart? rolePart;
  final String? partValue;

  const _ScriptAssetDragData.character({
    required this.characterId,
    required this.label,
  })  : kind = _ScriptAssetDragKind.character,
        outfitId = null,
        artistChainId = null,
        rolePart = null,
        partValue = null;

  const _ScriptAssetDragData.outfit({
    required this.characterId,
    required this.outfitId,
    required this.label,
  })  : kind = _ScriptAssetDragKind.outfit,
        artistChainId = null,
        rolePart = null,
        partValue = null;

  const _ScriptAssetDragData.outfitPart({
    required this.rolePart,
    required this.partValue,
    required this.label,
  })  : kind = _ScriptAssetDragKind.outfitPart,
        characterId = null,
        outfitId = null,
        artistChainId = null;

  const _ScriptAssetDragData.artistChain({
    required this.artistChainId,
    required this.label,
  })  : kind = _ScriptAssetDragKind.artistChain,
        characterId = null,
        outfitId = null,
        rolePart = null,
        partValue = null;
}

enum _ScriptAssetDrawerCategory {
  character(
    keySuffix: 'character',
    title: '角色',
    icon: Icons.person_outline,
  ),
  outfit(
    keySuffix: 'outfit',
    title: 'Outfit / 造型',
    icon: Icons.checkroom_outlined,
  ),
  artist(
    keySuffix: 'artist',
    title: '画师串',
    icon: Icons.palette_outlined,
  );

  final String keySuffix;
  final String title;
  final IconData icon;

  static const topLevelValues = [
    character,
    artist,
  ];

  const _ScriptAssetDrawerCategory({
    required this.keySuffix,
    required this.title,
    required this.icon,
  });

  int countFrom(StudioScriptViewModel viewModel) {
    return switch (this) {
      _ScriptAssetDrawerCategory.character => viewModel.characterOptions.length,
      _ScriptAssetDrawerCategory.outfit => viewModel.characterOptions.fold<int>(
          0,
          (count, character) => count + character.outfits.length,
        ),
      _ScriptAssetDrawerCategory.artist => viewModel.artistChainOptions.length,
    };
  }
}

class _ScriptAssetDrawer extends StatefulWidget {
  final StudioScriptViewModel viewModel;
  final StudioScriptAssetFocus? assetFocus;
  final ScriptAssetFavoriteKeysLoader? loadAssetFavoriteKeys;
  final ScriptAssetFavoriteSetter? setAssetFavorite;

  const _ScriptAssetDrawer({
    required this.viewModel,
    required this.assetFocus,
    required this.loadAssetFavoriteKeys,
    required this.setAssetFavorite,
  });

  @override
  State<_ScriptAssetDrawer> createState() => _ScriptAssetDrawerState();
}

class _ScriptAssetDrawerState extends State<_ScriptAssetDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _detailScrollController = ScrollController();
  _ScriptAssetDrawerCategory? _selectedCategory;
  String _searchQuery = '';
  bool _revealCategoriesImmediately = false;
  int? _appliedFocusNonce;
  Set<String> _favoriteKeys = const {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_updateSearchQuery);
    _applyFocus(widget.assetFocus);
    _loadFavoriteKeys();
  }

  @override
  void didUpdateWidget(covariant _ScriptAssetDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetFocus != widget.assetFocus) {
      _applyFocus(widget.assetFocus);
    }
    if (oldWidget.viewModel != widget.viewModel ||
        oldWidget.loadAssetFavoriteKeys != widget.loadAssetFavoriteKeys) {
      _favoriteKeys = const {};
      _loadFavoriteKeys();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_updateSearchQuery);
    _searchController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _ScriptAssetDrawerCategory.topLevelValues.fold<int>(
      0,
      (count, category) => count + category.countFrom(widget.viewModel),
    );
    final child = totalCount == 0
        ? const StudioAssetDrawerStateMessage(
            icon: Icons.inventory_2_outlined,
            title: '素材抽屉',
            message: '导入剧本后会显示可用角色和画师串，服装可在角色内展开',
          )
        : _selectedCategory == null
            ? _ScriptDrawerCategoryList(
                key: const ValueKey('script-drawer-home'),
                viewModel: widget.viewModel,
                revealImmediately: _revealCategoriesImmediately,
                onSelect: _selectCategory,
              )
            : _ScriptDrawerCategoryDetail(
                key: ValueKey(
                  'script-drawer-detail-${_selectedCategory!.keySuffix}',
                ),
                items: _itemsFor(_selectedCategory!),
                searchController: _searchController,
                searchQuery: _searchQuery,
                scrollController: _detailScrollController,
                focusedCardKey: widget.assetFocus?.drawerCardKey,
                favoriteKeys: _favoriteKeys,
                onFavoriteChanged: _setFavorite,
              );
    return StudioAssetDrawerShell(
      title: _selectedCategory?.title ?? '素材抽屉',
      count: _selectedCategory?.countFrom(widget.viewModel) ?? totalCount,
      onBack: _selectedCategory == null ? null : _showCategories,
      backButtonKey: const ValueKey('script-drawer-back'),
      scrollConfigurationKey:
          const ValueKey('script-drawer-scrollbar-suppression'),
      suppressScrollbars: true,
      child: child,
    );
  }

  void _selectCategory(_ScriptAssetDrawerCategory category) {
    setState(() {
      _selectedCategory = category;
      _searchController.clear();
      _searchQuery = '';
      _revealCategoriesImmediately = false;
    });
  }

  void _applyFocus(StudioScriptAssetFocus? focus) {
    if (focus == null || _appliedFocusNonce == focus.nonce) return;
    _appliedFocusNonce = focus.nonce;
    _selectedCategory = _categoryForFocus(focus);
    _searchController.clear();
    _searchQuery = '';
    _scheduleFocusedCardScroll(focus);
  }

  void _scheduleFocusedCardScroll(
    StudioScriptAssetFocus focus, {
    int attempts = 2,
  }) {
    if (attempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollFocusedCardIntoView(focus);
      _scheduleFocusedCardScroll(focus, attempts: attempts - 1);
    });
  }

  _ScriptAssetDrawerCategory _categoryForFocus(StudioScriptAssetFocus focus) {
    return switch (focus.kind) {
      StudioScriptAssetFocusKind.character =>
        _ScriptAssetDrawerCategory.character,
      StudioScriptAssetFocusKind.outfit => _ScriptAssetDrawerCategory.character,
      StudioScriptAssetFocusKind.artistChain =>
        _ScriptAssetDrawerCategory.artist,
    };
  }

  void _showCategories() {
    setState(() {
      _selectedCategory = null;
      _searchController.clear();
      _searchQuery = '';
      _revealCategoriesImmediately = true;
    });
  }

  void _updateSearchQuery() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
    });
  }

  List<_ScriptDrawerAssetItem> _itemsFor(
    _ScriptAssetDrawerCategory category,
  ) {
    return switch (category) {
      _ScriptAssetDrawerCategory.character => [
          for (final character in widget.viewModel.characterOptions)
            _ScriptDrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.character(character.id),
              favoriteButtonKey: ValueKey(
                'script-asset-favorite-character-${character.id}',
              ),
              key: ValueKey('script-asset-character-${character.id}'),
              previewKey:
                  ValueKey('script-asset-preview-character-${character.id}'),
              icon: Icons.person_outline,
              title: character.name,
              subtitle: character.traits.frontFull,
              previewPaths: _characterDrawerPreviewPaths(character),
              searchableText: [
                character.name,
                character.traits.frontFull,
                character.traits.frontUpper ?? '',
                character.traits.frontLower ?? '',
                for (final outfit in character.outfits) ...[
                  outfit.name,
                  outfit.tags.frontFull,
                  outfit.tags.frontUpper ?? '',
                  outfit.tags.frontLower ?? '',
                  outfit.partTags.upperBodyTags.join(', '),
                  outfit.partTags.upperClothingTags.join(', '),
                  outfit.partTags.lowerBodyTags.join(', '),
                  outfit.partTags.lowerClothingTags.join(', '),
                ],
              ].join(' '),
              outfits: _drawerOutfitsForCharacter(character),
              data: _ScriptAssetDragData.character(
                characterId: character.id,
                label: character.name,
              ),
            ),
        ],
      _ScriptAssetDrawerCategory.outfit => [
          for (final character in widget.viewModel.characterOptions)
            for (final outfit in character.outfits)
              _ScriptDrawerAssetItem(
                favoriteKey: StudioAssetFavoriteKeys.outfit(
                  character.id,
                  outfit.id,
                ),
                favoriteButtonKey: ValueKey(
                  'script-asset-favorite-outfit-${character.id}-${outfit.id}',
                ),
                key: ValueKey(
                  'script-asset-outfit-${character.id}-${outfit.id}',
                ),
                previewKey: ValueKey(
                  'script-asset-preview-outfit-${character.id}-${outfit.id}',
                ),
                icon: Icons.checkroom_outlined,
                title: '${character.name} / ${outfit.name}',
                subtitle: _outfitLabel(outfit),
                previewPaths:
                    widget.viewModel.outfitPreviewPaths(character, outfit),
                searchableText: [
                  character.name,
                  outfit.name,
                  outfit.tags.frontFull,
                  outfit.tags.frontUpper ?? '',
                  outfit.tags.frontLower ?? '',
                  outfit.partTags.upperBodyTags.join(', '),
                  outfit.partTags.upperClothingTags.join(', '),
                  outfit.partTags.lowerBodyTags.join(', '),
                  outfit.partTags.lowerClothingTags.join(', '),
                ].join(' '),
                data: _ScriptAssetDragData.outfit(
                  characterId: character.id,
                  outfitId: outfit.id,
                  label: '${character.name} / ${outfit.name}',
                ),
              ),
        ],
      _ScriptAssetDrawerCategory.artist => [
          for (final chain in widget.viewModel.artistChainOptions)
            _ScriptDrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.artistChain(chain.id),
              favoriteButtonKey: ValueKey(
                'script-asset-favorite-artist-${chain.id}',
              ),
              key: ValueKey('script-asset-artist-${chain.id}'),
              previewKey: ValueKey('script-asset-preview-artist-${chain.id}'),
              icon: Icons.palette_outlined,
              title: chain.name,
              subtitle: _artistChainLabel(chain),
              previewPaths: widget.viewModel.artistChainPreviewPaths(chain),
              searchableText: '${chain.name} ${_artistChainLabel(chain)}',
              data: _ScriptAssetDragData.artistChain(
                artistChainId: chain.id,
                label: chain.name,
              ),
            ),
        ],
    };
  }

  List<_ScriptDrawerOutfitItem> _drawerOutfitsForCharacter(
    CharacterEntry character,
  ) {
    return [
      for (final outfit in _uniqueOutfitsById(character.outfits))
        _ScriptDrawerOutfitItem(
          itemKey: ValueKey(
            'script-asset-character-${character.id}-outfit-${outfit.id}',
          ),
          previewKey: ValueKey(
            'script-asset-preview-character-${character.id}-outfit-${outfit.id}',
          ),
          title: outfit.name,
          subtitle: character.name,
          fullPrompt: outfit.tags.frontFull,
          previewPaths: widget.viewModel.outfitPreviewPaths(character, outfit),
          parts: _outfitParts(
            upperBodyPrompt: promptTagsToPrompt(outfit.partTags.upperBodyTags),
            upperClothingPrompt: promptTagsToPrompt(
              outfit.partTags.upperClothingTags,
            ),
            lowerBodyPrompt: promptTagsToPrompt(outfit.partTags.lowerBodyTags),
            lowerClothingPrompt: promptTagsToPrompt(
              outfit.partTags.lowerClothingTags,
            ),
            includeEmpty: true,
          ),
          data: _ScriptAssetDragData.outfit(
            characterId: character.id,
            outfitId: outfit.id,
            label: '${character.name} / ${outfit.name}',
          ),
        ),
    ];
  }

  List<String> _characterDrawerPreviewPaths(CharacterEntry character) {
    final paths = <String>[];
    void addPaths(Iterable<String> nextPaths) {
      for (final path in nextPaths) {
        final trimmed = path.trim();
        if (trimmed.isEmpty || paths.contains(trimmed)) {
          continue;
        }
        paths.add(trimmed);
      }
    }

    addPaths(widget.viewModel.characterPreviewPaths(character));
    for (final outfit in _uniqueOutfitsById(character.outfits)) {
      addPaths(widget.viewModel.outfitPreviewPaths(character, outfit));
    }
    return List.unmodifiable(paths);
  }

  Iterable<WorkspaceOutfit> _uniqueOutfitsById(
    Iterable<WorkspaceOutfit> outfits,
  ) sync* {
    final seen = <String>{};
    for (final outfit in outfits) {
      if (seen.add(outfit.id)) {
        yield outfit;
      }
    }
  }

  List<_ScriptDrawerOutfitPartItem> _outfitParts({
    String upperBodyPrompt = '',
    String upperClothingPrompt = '',
    String lowerBodyPrompt = '',
    String lowerClothingPrompt = '',
    bool includeEmpty = false,
  }) {
    final parts = [
      _ScriptDrawerOutfitPartItem(
        keySuffix: 'upper-body',
        label: '上身',
        value: upperBodyPrompt,
        rolePart: StudioScriptRolePart.upperBody,
      ),
      _ScriptDrawerOutfitPartItem(
        keySuffix: 'upper-clothing',
        label: '上装',
        value: upperClothingPrompt,
        rolePart: StudioScriptRolePart.upperClothing,
      ),
      _ScriptDrawerOutfitPartItem(
        keySuffix: 'lower-body',
        label: '下身',
        value: lowerBodyPrompt,
        rolePart: StudioScriptRolePart.lowerBody,
      ),
      _ScriptDrawerOutfitPartItem(
        keySuffix: 'lower-clothing',
        label: '下装',
        value: lowerClothingPrompt,
        rolePart: StudioScriptRolePart.lowerClothing,
      ),
    ];
    if (includeEmpty) {
      return List.unmodifiable(parts);
    }
    return parts
        .where((part) => part.value.trim().isNotEmpty)
        .toList(growable: false);
  }

  void _scrollFocusedCardIntoView(StudioScriptAssetFocus focus) {
    if (!_detailScrollController.hasClients) return;
    final category = _categoryForFocus(focus);
    if (_selectedCategory != category) return;
    final targetIndex = _focusedItemIndex(
      focus,
      _favoriteSortedScriptItems(_itemsFor(category), _favoriteKeys),
    );
    if (targetIndex < 0) return;
    final targetOffset = targetIndex * _ScriptDrawerAssetRow.rowExtent +
        (focus.kind == StudioScriptAssetFocusKind.outfit
            ? _ScriptDrawerAssetRow.rowExtent
            : 0);
    final maxOffset = _detailScrollController.position.maxScrollExtent;
    _detailScrollController.jumpTo(targetOffset.clamp(0, maxOffset).toDouble());
  }

  int _focusedItemIndex(
    StudioScriptAssetFocus focus,
    List<_ScriptDrawerAssetItem> items,
  ) {
    return items.indexWhere((item) {
      final key = item.key;
      if (key is ValueKey && key.value == focus.drawerCardKey) {
        return true;
      }
      return item.outfits.any((outfit) {
        final outfitKey = outfit.itemKey;
        return outfitKey is ValueKey && outfitKey.value == focus.drawerCardKey;
      });
    });
  }

  Future<void> _loadFavoriteKeys() async {
    try {
      final loader = widget.loadAssetFavoriteKeys;
      final favoriteKeys = loader != null
          ? await loader()
          : GetIt.I.isRegistered<StudioAssetCatalogService>()
              ? await GetIt.I<StudioAssetCatalogService>()
                  .loadAssetFavoriteKeys()
              : const <String>{};
      if (!mounted) return;
      setState(() {
        _favoriteKeys = favoriteKeys;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteKeys = const {};
      });
    }
  }

  Future<void> _setFavorite(
    _ScriptDrawerAssetItem item,
    bool isFavorite,
  ) async {
    final previous = _favoriteKeys;
    setState(() {
      final next = {..._favoriteKeys};
      if (isFavorite) {
        next.add(item.favoriteKey);
      } else {
        next.remove(item.favoriteKey);
      }
      _favoriteKeys = next;
    });
    try {
      final setter = widget.setAssetFavorite;
      if (setter != null) {
        await setter(item.favoriteKey, isFavorite);
      } else if (GetIt.I.isRegistered<StudioAssetCatalogService>()) {
        await GetIt.I<StudioAssetCatalogService>().setAssetFavorite(
          item.favoriteKey,
          isFavorite,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteKeys = previous;
      });
    }
  }
}

class _ScriptDrawerCategoryList extends StatelessWidget {
  final StudioScriptViewModel viewModel;
  final bool revealImmediately;
  final ValueChanged<_ScriptAssetDrawerCategory> onSelect;

  const _ScriptDrawerCategoryList({
    super.key,
    required this.viewModel,
    this.revealImmediately = false,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final category in _ScriptAssetDrawerCategory.topLevelValues)
        if (category.countFrom(viewModel) > 0)
          StudioAssetDrawerCategory<_ScriptAssetDrawerCategory>(
            value: category,
            keySuffix: category.keySuffix,
            title: category.title,
            icon: category.icon,
            count: category.countFrom(viewModel),
            leading: _ScriptDrawerCategoryPreviewStrip(
              icon: category.icon,
              previewPaths: _previewPathsFor(category),
            ),
          ),
    ];
    return StudioAssetDrawerCategoryList<_ScriptAssetDrawerCategory>(
      categories: categories,
      keyPrefix: 'script',
      revealImmediately: revealImmediately,
      onSelect: onSelect,
    );
  }

  List<String> _previewPathsFor(_ScriptAssetDrawerCategory category) {
    final paths = switch (category) {
      _ScriptAssetDrawerCategory.character => [
          for (final character in viewModel.characterOptions)
            ...viewModel.characterPreviewPaths(character),
        ],
      _ScriptAssetDrawerCategory.artist => [
          for (final chain in viewModel.artistChainOptions)
            ...viewModel.artistChainPreviewPaths(chain),
        ],
      _ScriptAssetDrawerCategory.outfit => const <String>[],
    };
    return paths.take(3).toList(growable: false);
  }
}

class _ScriptDrawerCategoryPreviewStrip extends StatelessWidget {
  final IconData icon;
  final List<String> previewPaths;

  const _ScriptDrawerCategoryPreviewStrip({
    required this.icon,
    required this.previewPaths,
  });

  @override
  Widget build(BuildContext context) {
    if (previewPaths.isEmpty) {
      return Container(
        width: 42,
        height: 34,
        decoration: BoxDecoration(
          color: StudioTokens.surface2,
          borderRadius: StudioTokens.radiusSlot,
          border: StudioTokens.cardBorder,
        ),
        child: Icon(icon, size: 18, color: StudioTokens.primary),
      );
    }
    return SizedBox(
      width: 50,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, path) in previewPaths.indexed)
            Positioned(
              left: index * 12,
              top: index == 1 ? 2 : 0,
              child: _ScriptDrawerSmallPreview(
                icon: icon,
                previewPaths: previewPaths,
                activePreviewPath: path,
                size: 32,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScriptDrawerCategoryDetail extends StatelessWidget {
  final List<_ScriptDrawerAssetItem> items;
  final TextEditingController searchController;
  final String searchQuery;
  final ScrollController scrollController;
  final String? focusedCardKey;
  final Set<String> favoriteKeys;
  final void Function(_ScriptDrawerAssetItem item, bool isFavorite)
      onFavoriteChanged;

  const _ScriptDrawerCategoryDetail({
    super.key,
    required this.items,
    required this.searchController,
    required this.searchQuery,
    required this.scrollController,
    required this.focusedCardKey,
    required this.favoriteKeys,
    required this.onFavoriteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final matchingItems = searchQuery.isEmpty
        ? items
        : [
            for (final item in items)
              if (item.searchableText.toLowerCase().contains(searchQuery)) item,
          ];
    final filteredItems =
        _favoriteSortedScriptItems(matchingItems, favoriteKeys);
    return StudioAssetDrawerSearchList<_ScriptDrawerAssetItem>(
      searchFieldKey: const ValueKey('script-drawer-category-search'),
      searchController: searchController,
      scrollController: scrollController,
      items: filteredItems,
      emptyState: const StudioAssetDrawerStateMessage(
        icon: Icons.search_off,
        title: '没有匹配素材',
        message: '换个关键词试试',
      ),
      itemBuilder: (context, item, index) {
        return _ScriptDrawerAssetRow(
          key: ValueKey('script-drawer-row-${item.favoriteKey}'),
          item: item,
          focusedCardKey: focusedCardKey,
          focused: item.key is ValueKey &&
              (item.key as ValueKey).value == focusedCardKey,
          isFavorite: favoriteKeys.contains(item.favoriteKey),
          onFavoriteChanged: (isFavorite) =>
              onFavoriteChanged(item, isFavorite),
        );
      },
    );
  }
}

List<_ScriptDrawerAssetItem> _favoriteSortedScriptItems(
  List<_ScriptDrawerAssetItem> items,
  Set<String> favoriteKeys,
) {
  final pinnedItems = <_ScriptDrawerAssetItem>[];
  final regularItems = <_ScriptDrawerAssetItem>[];
  for (final item in items) {
    if (favoriteKeys.contains(item.favoriteKey)) {
      pinnedItems.add(item);
    } else {
      regularItems.add(item);
    }
  }
  return [...pinnedItems, ...regularItems];
}

class _ScriptDrawerAssetItem {
  final String favoriteKey;
  final Key favoriteButtonKey;
  final Key key;
  final Key previewKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> previewPaths;
  final _ScriptAssetDragData data;
  final String searchableText;
  final List<_ScriptDrawerOutfitItem> outfits;

  const _ScriptDrawerAssetItem({
    required this.favoriteKey,
    required this.favoriteButtonKey,
    required this.key,
    required this.previewKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.previewPaths,
    required this.data,
    required this.searchableText,
    this.outfits = const [],
  });
}

class _ScriptDrawerOutfitItem {
  final Key itemKey;
  final Key previewKey;
  final String title;
  final String subtitle;
  final String fullPrompt;
  final List<String> previewPaths;
  final List<_ScriptDrawerOutfitPartItem> parts;
  final _ScriptAssetDragData data;

  const _ScriptDrawerOutfitItem({
    required this.itemKey,
    required this.previewKey,
    required this.title,
    required this.subtitle,
    required this.fullPrompt,
    required this.previewPaths,
    required this.parts,
    required this.data,
  });
}

class _ScriptDrawerOutfitPartItem {
  final String keySuffix;
  final String label;
  final String value;
  final StudioScriptRolePart rolePart;

  const _ScriptDrawerOutfitPartItem({
    required this.keySuffix,
    required this.label,
    required this.value,
    required this.rolePart,
  });
}

class _ScriptDrawerAssetRow extends StatefulWidget {
  static const double rowExtent = 84;

  final _ScriptDrawerAssetItem item;
  final String? focusedCardKey;
  final bool focused;
  final bool isFavorite;
  final ValueChanged<bool> onFavoriteChanged;

  const _ScriptDrawerAssetRow({
    super.key,
    required this.item,
    required this.focusedCardKey,
    required this.focused,
    required this.isFavorite,
    required this.onFavoriteChanged,
  });

  @override
  State<_ScriptDrawerAssetRow> createState() => _ScriptDrawerAssetRowState();
}

class _ScriptDrawerAssetRowState extends State<_ScriptDrawerAssetRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasFocusedOutfit = item.outfits.any((outfit) {
      final key = outfit.itemKey;
      return key is ValueKey && key.value == widget.focusedCardKey;
    });
    final expanded = _expanded || hasFocusedOutfit;
    final card = StudioAssetDrawerCardSurface(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: item.key,
        onTap: item.outfits.isEmpty
            ? null
            : () => setState(() {
                  _expanded = !_expanded;
                }),
        borderRadius: StudioTokens.radiusSlot,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: StudioTokens.surface3,
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: widget.focused
                  ? StudioTokens.primary
                  : StudioTokens.cardOutline,
              width: widget.focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              StudioHoverPreviewThumbnail(
                previewPaths: item.previewPaths,
                overlayKey: ValueKey(
                  '${(item.previewKey as ValueKey).value}-overlay',
                ),
                builder: (context, previewPath) => _ScriptDrawerSmallPreview(
                  key: item.previewKey,
                  icon: item.icon,
                  previewPaths: item.previewPaths,
                  activePreviewPath: previewPath,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (item.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (item.outfits.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${item.outfits.length} 套服装',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: StudioTokens.textMuted,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.outfits.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: StudioTokens.textSecondary,
                ),
              ],
              const SizedBox(width: 8),
              StudioIconButton(
                key: item.favoriteButtonKey,
                tooltip: widget.isFavorite ? '取消收藏' : '收藏',
                icon: widget.isFavorite ? Icons.star : Icons.star_border,
                selected: widget.isFavorite,
                onPressed: () => widget.onFavoriteChanged(!widget.isFavorite),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.drag_indicator,
                size: 18,
                color: StudioTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );

    final draggable = Draggable<_ScriptAssetDragData>(
      data: item.data,
      feedback: _ScriptDrawerDragFeedback(
        label: item.title,
        icon: item.icon,
        previewPath: _firstScriptPreviewPath(item.previewPaths),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        draggable,
        StudioDrawerShelf(
          visible: expanded,
          margin: const EdgeInsets.only(
            left: 18,
            right: studioAssetDrawerHoverInset,
            bottom: 10,
          ),
          railOpacity: 0,
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final outfit in item.outfits)
                _ScriptDrawerOutfitRow(
                  outfit: outfit,
                  focused: outfit.itemKey is ValueKey &&
                      (outfit.itemKey as ValueKey).value ==
                          widget.focusedCardKey,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScriptDrawerOutfitRow extends StatefulWidget {
  final _ScriptDrawerOutfitItem outfit;
  final bool focused;

  const _ScriptDrawerOutfitRow({
    required this.outfit,
    required this.focused,
  });

  @override
  State<_ScriptDrawerOutfitRow> createState() => _ScriptDrawerOutfitRowState();
}

class _ScriptDrawerOutfitRowState extends State<_ScriptDrawerOutfitRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final outfit = widget.outfit;
    final card = StudioAssetDrawerCardSurface(
      child: InkWell(
        key: outfit.itemKey,
        onTap: outfit.parts.isEmpty
            ? null
            : () => setState(() {
                  _expanded = !_expanded;
                }),
        borderRadius: StudioTokens.radiusSlot,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: StudioTokens.surface2,
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: widget.focused
                  ? StudioTokens.primary
                  : StudioTokens.cardOutline,
              width: widget.focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              StudioHoverPreviewThumbnail(
                previewPaths: outfit.previewPaths,
                overlayKey: ValueKey(
                  '${(outfit.previewKey as ValueKey).value}-overlay',
                ),
                builder: (context, previewPath) => _ScriptDrawerSmallPreview(
                  key: outfit.previewKey,
                  icon: Icons.checkroom_outlined,
                  previewPaths: outfit.previewPaths,
                  activePreviewPath: previewPath,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outfit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (outfit.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        outfit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: StudioTokens.textMuted,
                            ),
                      ),
                    ],
                    if (outfit.fullPrompt.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        outfit.fullPrompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (outfit.parts.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: StudioTokens.textSecondary,
                ),
              ],
              const SizedBox(width: 8),
              const Icon(
                Icons.drag_indicator,
                size: 18,
                color: StudioTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );

    final draggable = Draggable<_ScriptAssetDragData>(
      data: outfit.data,
      feedback: _ScriptDrawerDragFeedback(
        label: outfit.data.label,
        icon: Icons.checkroom_outlined,
        previewPath: _firstScriptPreviewPath(outfit.previewPaths),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        draggable,
        StudioDrawerShelf(
          visible: _expanded,
          margin: const EdgeInsets.only(
            left: 18,
            right: studioAssetDrawerHoverInset,
            bottom: 10,
          ),
          railOpacity: 0,
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final part in outfit.parts) ...[
                _ScriptDrawerPromptPartCard(
                  outfitKey: outfit.itemKey,
                  part: part,
                ),
                if (part != outfit.parts.last) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ScriptDrawerPromptPartCard extends StatelessWidget {
  final Key outfitKey;
  final _ScriptDrawerOutfitPartItem part;

  const _ScriptDrawerPromptPartCard({
    required this.outfitKey,
    required this.part,
  });

  @override
  Widget build(BuildContext context) {
    final value = part.value.trim();
    final partKey = _partKey('part');
    final card = StudioAssetDrawerCardSurface(
      enabled: value.isNotEmpty,
      padding: EdgeInsets.zero,
      child: Container(
        key: ValueKey(partKey),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Text(
                part.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isEmpty ? '未记录' : value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            StudioIconButton(
              key: ValueKey(_partKey('copy-part')),
              tooltip: '复制提示词',
              icon: Icons.copy_outlined,
              onPressed: value.isEmpty ? null : () => _copy(context, value),
            ),
          ],
        ),
      ),
    );
    if (value.isEmpty) {
      return card;
    }
    final data = _ScriptAssetDragData.outfitPart(
      rolePart: part.rolePart,
      partValue: value,
      label: '${part.label}: $value',
    );
    return Draggable<_ScriptAssetDragData>(
      data: data,
      feedback: _ScriptDrawerDragFeedback(
        label: data.label,
        icon: Icons.segment_outlined,
        previewPath: null,
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );
  }

  String _partKey(String prefix) {
    final rawKey = outfitKey is ValueKey
        ? (outfitKey as ValueKey).value.toString()
        : outfitKey.toString();
    final suffix = rawKey.replaceFirst('script-asset-', '');
    return 'script-asset-$prefix-$suffix-${part.keySuffix}';
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制提示词')),
    );
  }
}

class _ScriptDrawerSmallPreview extends StatelessWidget {
  final IconData icon;
  final List<String> previewPaths;
  final String? activePreviewPath;
  final double size;

  const _ScriptDrawerSmallPreview({
    super.key,
    required this.icon,
    this.previewPaths = const [],
    this.activePreviewPath,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    final previewPath = _firstExistingPreviewPath(
      activePreviewPath,
      previewPaths,
    );
    return ClipRRect(
      borderRadius: StudioTokens.radiusSlot,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: StudioTokens.surface2,
          border: StudioTokens.cardBorder,
        ),
        child: previewPath == null
            ? Icon(icon, size: size * 0.48, color: StudioTokens.primary)
            : Image.file(
                File(previewPath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    icon,
                    size: size * 0.48,
                    color: StudioTokens.primary,
                  );
                },
              ),
      ),
    );
  }
}

String? _firstExistingPreviewPath(
  String? preferredPath,
  List<String> previewPaths,
) {
  final candidates = <String>[
    if (preferredPath != null) preferredPath,
    ...previewPaths,
  ];
  final seen = <String>{};
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    final file = File(trimmed);
    if (file.isAbsolute && file.existsSync()) {
      return file.path;
    }
  }
  return null;
}

class _ScriptDrawerDragFeedback extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? previewPath;

  const _ScriptDrawerDragFeedback({
    required this.label,
    required this.icon,
    required this.previewPath,
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
            _ScriptDrawerSmallPreview(
              icon: icon,
              activePreviewPath: previewPath,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
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

class _SelectedFrameReplacedPrompt extends StatefulWidget {
  final StudioScriptViewModel viewModel;

  const _SelectedFrameReplacedPrompt({required this.viewModel});

  @override
  State<_SelectedFrameReplacedPrompt> createState() =>
      _SelectedFrameReplacedPromptState();
}

class _SelectedFrameReplacedPromptState
    extends State<_SelectedFrameReplacedPrompt> {
  bool _grouped = false;
  bool _showDiff = false;

  @override
  Widget build(BuildContext context) {
    final groups =
        _replacedPromptGroups(widget.viewModel.selectedFrameTagGroups);
    final diffGroups =
        _promptDiffGroups(widget.viewModel.selectedFramePreviews);
    final canShowDiff = diffGroups.isNotEmpty;
    return _SectionPanel(
      title: '替换后的提示词',
      icon: Icons.swap_horiz_outlined,
      children: [
        if (groups.isEmpty)
          const _EmptyHint(text: '导入剧本并选择帧后会显示替换后的提示词')
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _PromptDiffToggle(
                  value: _showDiff && canShowDiff,
                  enabled: canShowDiff,
                  onChanged: (value) {
                    setState(() {
                      _showDiff = value;
                    });
                  },
                ),
                if (!_showDiff)
                  OutlinedButton.icon(
                    key: const ValueKey('script-replaced-prompt-layout-toggle'),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: WidgetStatePropertyAll(
                        Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _grouped = !_grouped;
                      });
                    },
                    icon: Icon(
                      _grouped
                          ? Icons.view_agenda_outlined
                          : Icons.dashboard_outlined,
                      size: 16,
                    ),
                    label: Text(_grouped ? '原序' : '分块'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_showDiff && canShowDiff)
            PromptTagGroupDisplay(
              key: const ValueKey('script-replaced-prompt-tags'),
              groups: [
                for (final group in diffGroups)
                  PromptTagDisplayGroup.fromTags(
                    id: group.id,
                    label: group.label,
                    tags: [for (final tag in group.tags) tag.text],
                  ),
              ],
              groupKeyPrefix: 'script-replaced-prompt-group',
              tagKeyPrefix: 'script-replaced-prompt-tags',
              defaultTranslated: true,
              enableTagActions: true,
              onAddToFilterRules: widget.viewModel.addTagsToFilterRulesLibrary,
              filterRuleTargets: _scriptPromptFilterRuleTargets,
              showLayoutControls: false,
              initialLayoutMode: _grouped
                  ? PromptTagLayoutMode.grouped
                  : PromptTagLayoutMode.sourceOrder,
              respectInitialLayoutMode: true,
              dense: true,
              emptyText: '未检测到源词',
              diffStateForTag: (groupId, tag) =>
                  _promptDiffStateForTag(diffGroups, groupId, tag),
              showTagWarnings: false,
            )
          else
            PromptTagGroupDisplay(
              key: const ValueKey('script-replaced-prompt-tags'),
              groups: [
                for (final group in groups)
                  PromptTagDisplayGroup.fromTags(
                    id: group.id,
                    label: group.label,
                    tags: group.tags,
                  ),
              ],
              groupKeyPrefix: 'script-replaced-prompt-group',
              tagKeyPrefix: 'script-replaced-prompt-tags',
              defaultTranslated: true,
              enableTagActions: true,
              onAddToFilterRules: widget.viewModel.addTagsToFilterRulesLibrary,
              filterRuleTargets: _scriptPromptFilterRuleTargets,
              showLayoutControls: false,
              initialLayoutMode: _grouped
                  ? PromptTagLayoutMode.grouped
                  : PromptTagLayoutMode.sourceOrder,
              respectInitialLayoutMode: true,
              dense: true,
              showTagWarnings: false,
              emptyText: '未检测到源词',
            ),
        ],
      ],
    );
  }

  List<_PromptDiffGroup> _promptDiffGroups(
    List<StudioScriptFrameSplitPreview> previews,
  ) {
    final before =
        previews.where((preview) => preview.id == 'before').firstOrNull;
    final after =
        previews.where((preview) => preview.id == 'after').firstOrNull;
    if (before == null || after == null) {
      return const [];
    }
    final beforeGroups = _groupsByDiffId(before.groups);
    final afterGroups = _groupsByDiffId(after.groups);
    final groupIds = <String>[];
    void addGroupIds(Iterable<String> ids) {
      for (final id in ids) {
        if (!groupIds.contains(id)) {
          groupIds.add(id);
        }
      }
    }

    addGroupIds(afterGroups.keys);
    addGroupIds(beforeGroups.keys);
    return [
      for (final id in groupIds)
        if (_promptDiffTags(
          beforeGroups[id]?.tags ?? const [],
          afterGroups[id]?.tags ?? const [],
        ).isNotEmpty)
          _PromptDiffGroup(
            id: id,
            label: afterGroups[id]?.label ?? beforeGroups[id]?.label ?? id,
            tags: _promptDiffTags(
              beforeGroups[id]?.tags ?? const [],
              afterGroups[id]?.tags ?? const [],
            ),
          ),
    ];
  }

  Map<String, StudioScriptFrameTagGroup> _groupsByDiffId(
    List<StudioScriptFrameTagGroup> groups,
  ) {
    return {
      for (final group in groups) _diffGroupId(group.id): group,
    };
  }

  String _diffGroupId(String id) {
    if (id.startsWith('before-')) {
      return id.substring('before-'.length);
    }
    if (id.startsWith('after-')) {
      return id.substring('after-'.length);
    }
    return id;
  }

  List<_PromptDiffTag> _promptDiffTags(
    List<String> beforeTags,
    List<String> afterTags,
  ) {
    final beforeByKey = <String, String>{};
    for (final tag in _visiblePromptTags(beforeTags)) {
      final key = _promptDiffKey(tag);
      if (key.isNotEmpty) {
        beforeByKey.putIfAbsent(key, () => tag);
      }
    }
    final afterKeys = <String>{};
    final result = <_PromptDiffTag>[];
    for (final tag in _visiblePromptTags(afterTags)) {
      final key = _promptDiffKey(tag);
      if (key.isEmpty) {
        continue;
      }
      afterKeys.add(key);
      result.add(
        _PromptDiffTag(
          text: tag,
          kind: beforeByKey.containsKey(key)
              ? _PromptDiffKind.unchanged
              : _PromptDiffKind.added,
        ),
      );
    }
    for (final tag in _visiblePromptTags(beforeTags)) {
      final key = _promptDiffKey(tag);
      if (key.isNotEmpty && !afterKeys.contains(key)) {
        result.add(_PromptDiffTag(text: tag, kind: _PromptDiffKind.removed));
      }
    }
    return List.unmodifiable(result);
  }

  String _promptDiffKey(String tag) {
    final cleaned = PromptTagProcessor.cleanTagDisplay(tag).trim();
    final normalized = PromptTagProcessor.normalizeMatchKey(cleaned);
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return cleaned.toLowerCase();
  }

  PromptTagChipDiffState _promptDiffStateForTag(
    List<_PromptDiffGroup> groups,
    String groupId,
    String tag,
  ) {
    final key = _promptDiffKey(tag);
    if (key.isEmpty) {
      return PromptTagChipDiffState.unchanged;
    }
    for (final group in groups) {
      if (group.id != groupId) {
        continue;
      }
      for (final entry in group.tags) {
        if (_promptDiffKey(entry.text) == key) {
          return switch (entry.kind) {
            _PromptDiffKind.added => PromptTagChipDiffState.added,
            _PromptDiffKind.removed => PromptTagChipDiffState.removed,
            _PromptDiffKind.unchanged => PromptTagChipDiffState.unchanged,
          };
        }
      }
    }
    return PromptTagChipDiffState.unchanged;
  }

  List<StudioScriptFrameTagGroup> _replacedPromptGroups(
    List<StudioScriptFrameTagGroup> groups,
  ) {
    return [
      for (final group in groups)
        if (_visiblePromptTags(group.tags).isNotEmpty)
          StudioScriptFrameTagGroup(
            id: group.id,
            label: group.label,
            tags: _visiblePromptTags(group.tags),
          ),
    ];
  }

  List<String> _visiblePromptTags(List<String> tags) {
    return [
      for (final tag in tags)
        if (tag.trim().isNotEmpty && tag != '未检测') tag,
    ];
  }
}

enum _PromptDiffKind { unchanged, added, removed }

class _PromptDiffTag {
  final String text;
  final _PromptDiffKind kind;

  const _PromptDiffTag({
    required this.text,
    required this.kind,
  });
}

class _PromptDiffGroup {
  final String id;
  final String label;
  final List<_PromptDiffTag> tags;

  const _PromptDiffGroup({
    required this.id,
    required this.label,
    required this.tags,
  });
}

class _PromptDiffToggle extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _PromptDiffToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '\u53ea\u6709\u5f00\u542f\u65f6\u624d\u5bf9\u6bd4',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\u5bf9\u6bd4\u9ad8\u4eae',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: enabled
                      ? StudioTokens.textSecondary
                      : StudioTokens.textMuted,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 6),
          Switch(
            key: const ValueKey('script-replaced-prompt-diff-toggle'),
            value: value,
            onChanged: enabled ? onChanged : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _SourceReplacementCompareToggle extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  const _SourceReplacementCompareToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.switchKey,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '显示源词是否已加入待替换区',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '待替换对比',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: enabled
                      ? StudioTokens.textSecondary
                      : StudioTokens.textMuted,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 6),
          Switch(
            key: switchKey,
            value: value,
            onChanged: enabled ? onChanged : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _ReplacementAreaSourceTagIndex {
  final Set<String> keys;

  const _ReplacementAreaSourceTagIndex(this.keys);

  PromptTagChipDiffState diffStateForTag(String tag) {
    final key = _replacementAreaSourceTagKey(tag);
    if (key.isEmpty) {
      return PromptTagChipDiffState.unchanged;
    }
    return keys.contains(key)
        ? PromptTagChipDiffState.added
        : PromptTagChipDiffState.removed;
  }

  String? diffTooltipForTag(String tag) {
    final key = _replacementAreaSourceTagKey(tag);
    if (key.isEmpty) {
      return null;
    }
    return keys.contains(key) ? '已在待替换区' : '未加入待替换区';
  }
}

_ReplacementAreaSourceTagIndex _replacementAreaSourceTagIndex(
  StudioScriptViewModel viewModel,
) {
  final selectedFrameIndex = viewModel.selectedFrameIndex;
  final keys = <String>{};

  void collectRules(Iterable<StudioScriptReplacementRuleItem> rules) {
    for (final rule in rules) {
      for (final term in rule.sourceTerms) {
        if (!_replacementTermAppliesToFrame(term, selectedFrameIndex)) {
          continue;
        }
        final key = _replacementAreaSourceTagKey(term.text);
        if (key.isNotEmpty) {
          keys.add(key);
        }
      }
    }
  }

  for (final replacement in viewModel.roleReplacementMappings) {
    collectRules(replacement.rules);
  }
  for (final replacement in viewModel.sceneReplacementMappings) {
    collectRules(replacement.rules);
  }
  return _ReplacementAreaSourceTagIndex(Set.unmodifiable(keys));
}

bool _replacementTermAppliesToFrame(
  ScriptPromptReplacementTerm term,
  int? selectedFrameIndex,
) {
  if (selectedFrameIndex == null || term.frameIndexes.isEmpty) {
    return true;
  }
  return term.frameIndexes.contains(selectedFrameIndex);
}

String _replacementAreaSourceTagKey(String tag) {
  final cleaned = PromptTagProcessor.cleanTagDisplay(tag).trim();
  final normalized = PromptTagProcessor.normalizeMatchKey(cleaned);
  if (normalized.isNotEmpty) {
    return normalized;
  }
  return cleaned.toLowerCase();
}

class _SelectedFrameCards extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _SelectedFrameCards({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final frameReviews = viewModel.recastPlan.frameReviews;
    final previews = viewModel.selectedFramePreviews;
    final replacementSourceTags = _replacementAreaSourceTagIndex(viewModel);
    return _SectionPanel(
      title: '当前帧拆分',
      icon: Icons.dashboard_customize_outlined,
      children: [
        if (frameReviews.isNotEmpty)
          for (final (index, review) in frameReviews.indexed) ...[
            _KeyframeReviewPanel(
              review: review,
              viewModel: viewModel,
              replacementSourceTags: replacementSourceTags,
            ),
            if (index != frameReviews.length - 1) const SizedBox(height: 12),
          ]
        else if (previews.isEmpty)
          const _EmptyHint(text: '点击帧时间线后会显示处理前和处理后预览')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              if (!wide) {
                return Column(
                  children: [
                    for (final (index, preview) in previews.indexed) ...[
                      _FramePreviewColumn(
                        preview: preview,
                        onAddToFilterRules:
                            viewModel.addTagsToFilterRulesLibrary,
                        allowReplacementComparison: preview.id == 'before',
                        replacementDiffStateForTag:
                            replacementSourceTags.diffStateForTag,
                        replacementDiffTooltipForTag:
                            replacementSourceTags.diffTooltipForTag,
                        contextMenuActionBuilder: preview.id == 'before'
                            ? _selectedFramePreviewReplacementActions(
                                viewModel: viewModel,
                              )
                            : null,
                      ),
                      if (index != previews.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, preview) in previews.indexed) ...[
                    Expanded(
                      child: _FramePreviewColumn(
                        preview: preview,
                        onAddToFilterRules:
                            viewModel.addTagsToFilterRulesLibrary,
                        allowReplacementComparison: preview.id == 'before',
                        replacementDiffStateForTag:
                            replacementSourceTags.diffStateForTag,
                        replacementDiffTooltipForTag:
                            replacementSourceTags.diffTooltipForTag,
                        contextMenuActionBuilder: preview.id == 'before'
                            ? _selectedFramePreviewReplacementActions(
                                viewModel: viewModel,
                              )
                            : null,
                      ),
                    ),
                    if (index != previews.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

class _KeyframeReviewPanel extends StatelessWidget {
  final StudioScriptFrameReview review;
  final StudioScriptViewModel viewModel;
  final _ReplacementAreaSourceTagIndex replacementSourceTags;

  const _KeyframeReviewPanel({
    required this.review,
    required this.viewModel,
    required this.replacementSourceTags,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(review.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final columns = [
                _KeyframeTokenColumn(
                  key: const ValueKey('script-keyframe-positive-column'),
                  title: '正向源词',
                  icon: Icons.add_circle_outline,
                  tokens: review.positiveTokens,
                  tokenGroups: review.effectivePositiveTokenGroups,
                  groupKeyPrefix: 'script-keyframe-positive-group',
                  tagKeyPrefix: 'script-keyframe-positive-tags',
                  negative: false,
                  allowGrouping: true,
                  onAddToFilterRules: viewModel.addTagsToFilterRulesLibrary,
                  contextMenuActionBuilder: _frameReviewReplacementActions(
                    viewModel: viewModel,
                    review: review,
                  ),
                  allowReplacementComparison: true,
                  replacementDiffStateForTag:
                      replacementSourceTags.diffStateForTag,
                  replacementDiffTooltipForTag:
                      replacementSourceTags.diffTooltipForTag,
                  classificationCache: viewModel.classificationCache,
                  saveClassificationCache: viewModel.saveClassificationCache,
                  classificationOverrides:
                      viewModel.reviewTagClassificationOverrides(
                    negative: false,
                  ),
                  onClassificationChanged: viewModel.refreshReviewTagCategories,
                ),
                _KeyframeTokenColumn(
                  key: const ValueKey('script-keyframe-negative-column'),
                  title: '负面源词',
                  icon: Icons.remove_circle_outline,
                  tokens: review.negativeTokens,
                  tokenGroups: review.effectiveNegativeTokenGroups,
                  groupKeyPrefix: 'script-keyframe-negative-group',
                  tagKeyPrefix: 'script-keyframe-negative-tags',
                  negative: true,
                  trailing: const _NegativePromptStrategyControl(
                    key: ValueKey('script-keyframe-negative-strategy'),
                  ),
                  onAddToFilterRules: viewModel.addTagsToFilterRulesLibrary,
                  classificationCache: viewModel.classificationCache,
                  saveClassificationCache: viewModel.saveClassificationCache,
                  classificationOverrides:
                      viewModel.reviewTagClassificationOverrides(
                    negative: true,
                  ),
                  onClassificationChanged: viewModel.refreshReviewTagCategories,
                ),
              ];
              if (!wide) {
                return Column(
                  children: [
                    columns.first,
                    const SizedBox(height: 12),
                    columns.last,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: columns.first),
                  const SizedBox(width: 12),
                  Expanded(child: columns.last),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KeyframeTokenColumn extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<StudioScriptReviewToken> tokens;
  final List<StudioScriptReviewTokenGroup> tokenGroups;
  final String groupKeyPrefix;
  final String tagKeyPrefix;
  final Widget? trailing;
  final bool negative;
  final bool allowGrouping;
  final PromptTagFilterRuleAdder? onAddToFilterRules;
  final PromptTagContextMenuActionBuilder? contextMenuActionBuilder;
  final bool allowReplacementComparison;
  final PromptTagDisplayDiffResolver? replacementDiffStateForTag;
  final PromptTagDisplayDiffTooltipResolver? replacementDiffTooltipForTag;
  final PromptTagClassificationCache? classificationCache;
  final PromptTagClassificationCacheSaver? saveClassificationCache;
  final Map<String, PromptTagCategory> classificationOverrides;
  final VoidCallback? onClassificationChanged;

  const _KeyframeTokenColumn({
    super.key,
    required this.title,
    required this.icon,
    required this.tokens,
    this.tokenGroups = const [],
    this.groupKeyPrefix = 'script-keyframe-token-group',
    this.tagKeyPrefix = 'script-keyframe-token-tags',
    this.trailing,
    this.negative = false,
    this.allowGrouping = false,
    this.onAddToFilterRules,
    this.contextMenuActionBuilder,
    this.allowReplacementComparison = false,
    this.replacementDiffStateForTag,
    this.replacementDiffTooltipForTag,
    this.classificationCache,
    this.saveClassificationCache,
    this.classificationOverrides = const {},
    this.onClassificationChanged,
  });

  @override
  State<_KeyframeTokenColumn> createState() => _KeyframeTokenColumnState();
}

class _KeyframeTokenColumnState extends State<_KeyframeTokenColumn> {
  bool _grouped = false;
  bool _showReplacementComparison = false;

  @override
  Widget build(BuildContext context) {
    final tokenGroups = widget.tokenGroups
        .where((group) => group.tokens.isNotEmpty)
        .toList(growable: false);
    final displayTokens = tokenGroups.isEmpty
        ? widget.tokens
        : [
            for (final group in tokenGroups) ...group.tokens,
          ];
    final canCompareReplacement = widget.allowReplacementComparison &&
        displayTokens.isNotEmpty &&
        widget.replacementDiffStateForTag != null;
    final actions = <Widget>[
      if (canCompareReplacement)
        _SourceReplacementCompareToggle(
          switchKey:
              const ValueKey('script-keyframe-replacement-compare-toggle'),
          value: _showReplacementComparison,
          enabled: canCompareReplacement,
          onChanged: (value) {
            setState(() {
              _showReplacementComparison = value;
            });
          },
        ),
      if (widget.allowGrouping && displayTokens.isNotEmpty)
        OutlinedButton.icon(
          key: const ValueKey('script-keyframe-positive-layout-toggle'),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelSmall,
            ),
          ),
          onPressed: () {
            setState(() {
              _grouped = !_grouped;
            });
          },
          icon: Icon(
            _grouped ? Icons.view_agenda_outlined : Icons.dashboard_outlined,
            size: 16,
          ),
          label: Text(_grouped ? '原序' : '分块'),
        ),
      if (widget.trailing != null) widget.trailing!,
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface1,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 18, color: StudioTokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (displayTokens.isEmpty)
            const _EmptyHint(text: '未检测到源词')
          else ...[
            _TokenColorLegend(categories: _legendCategories(displayTokens)),
            const SizedBox(height: 10),
            if (tokenGroups.isNotEmpty)
              PromptTagGroupDisplay(
                groups: [
                  for (final group in tokenGroups)
                    PromptTagDisplayGroup(
                      id: group.id,
                      label: group.label,
                      text:
                          group.tokens.map((token) => token.source).join(', '),
                      negative: widget.negative,
                    ),
                ],
                groupKeyPrefix: widget.groupKeyPrefix,
                tagKeyPrefix: widget.tagKeyPrefix,
                defaultTranslated: true,
                enableTagActions: true,
                onAddToFilterRules: widget.onAddToFilterRules,
                contextMenuActionBuilder: widget.contextMenuActionBuilder,
                filterRuleTargets: _scriptPromptFilterRuleTargets,
                diffStateForTag: _showReplacementComparison &&
                        widget.replacementDiffStateForTag != null
                    ? (_, tag) => widget.replacementDiffStateForTag!(tag)
                    : null,
                diffTooltipForTag: _showReplacementComparison &&
                        widget.replacementDiffTooltipForTag != null
                    ? (_, tag) => widget.replacementDiffTooltipForTag!(tag)
                    : null,
                classificationCache: widget.classificationCache,
                saveClassificationCache: widget.saveClassificationCache,
                classificationOverrides: widget.classificationOverrides,
                onClassificationChanged: widget.onClassificationChanged,
                showLayoutControls: false,
                initialLayoutMode: _grouped && widget.allowGrouping
                    ? PromptTagLayoutMode.grouped
                    : PromptTagLayoutMode.sourceOrder,
                respectInitialLayoutMode: true,
                dense: true,
                emptyText: '未检测到源词',
              )
            else
              PromptTagDisplay(
                text: widget.tokens.map((token) => token.source).join(', '),
                defaultTranslated: true,
                enableTagActions: true,
                onAddToFilterRules: widget.onAddToFilterRules,
                contextMenuActionBuilder: widget.contextMenuActionBuilder,
                filterRuleTargets: _scriptPromptFilterRuleTargets,
                diffStateForTag: _showReplacementComparison
                    ? widget.replacementDiffStateForTag
                    : null,
                diffTooltipForTag: _showReplacementComparison
                    ? widget.replacementDiffTooltipForTag
                    : null,
                classificationCache: widget.classificationCache,
                saveClassificationCache: widget.saveClassificationCache,
                classificationOverrides: widget.classificationOverrides,
                onClassificationChanged: widget.onClassificationChanged,
                showLayoutControls: false,
                initialLayoutMode: _grouped && widget.allowGrouping
                    ? PromptTagLayoutMode.grouped
                    : PromptTagLayoutMode.sourceOrder,
                respectInitialLayoutMode: true,
                negative: widget.negative,
              ),
          ],
        ],
      ),
    );
  }
}

PromptTagContextMenuActionBuilder _frameReviewReplacementActions({
  required StudioScriptViewModel viewModel,
  required StudioScriptFrameReview review,
}) {
  return (context, actionContext) {
    if (actionContext.negative) {
      return const <PromptTagContextMenuAction>[];
    }
    final terms = _frameReviewReplacementTermDrafts(actionContext);
    if (terms.isEmpty) {
      return const <PromptTagContextMenuAction>[];
    }
    return [
      PromptTagContextMenuAction(
        key: const ValueKey('script-frame-add-to-replacement-area'),
        icon: Icons.add_box_outlined,
        label: '加入待替换区',
        onSelected: (context, actionContext) async {
          final added =
              await _addFrameReviewTermsToReplacementAreaWithTargetPicker(
            context: context,
            viewModel: viewModel,
            frameIndex: review.frameIndex,
            actionContext: actionContext,
            fallbackSourceLocation: review.title,
          );
          if (added != null && context.mounted) {
            _showFrameReviewReplacementSnack(context, added);
          }
        },
      ),
      if (viewModel.hasSingleSelectedReplacementRule)
        PromptTagContextMenuAction(
          key: const ValueKey('script-frame-add-to-current-replacement-rule'),
          icon: Icons.playlist_add_outlined,
          label: '加入当前替换规则',
          onSelected: (context, actionContext) {
            final added =
                viewModel.addFrameReviewTermsToSelectedReplacementRule(
              frameIndex: review.frameIndex,
              sourceLocation: actionContext.groupLabel ??
                  actionContext.groupId ??
                  review.title,
              terms: _frameReviewReplacementTermDrafts(actionContext),
            );
            if (context.mounted) {
              _showFrameReviewReplacementSnack(context, added);
            }
          },
        ),
    ];
  };
}

enum _ReplacementTargetKind { currentSource, role, scene }

class _ReplacementTargetChoice {
  final _ReplacementTargetKind kind;
  final String id;
  final String label;
  final String preview;
  final bool recommended;

  const _ReplacementTargetChoice({
    required this.kind,
    required this.id,
    required this.label,
    this.preview = '',
    this.recommended = false,
  });

  ValueKey<String> get key {
    return switch (kind) {
      _ReplacementTargetKind.role =>
        ValueKey<String>('script-replacement-target-role-$id'),
      _ReplacementTargetKind.scene =>
        ValueKey<String>('script-replacement-target-scene-$id'),
      _ReplacementTargetKind.currentSource =>
        const ValueKey<String>('script-replacement-target-current-source'),
    };
  }
}

Future<bool?> _addFrameReviewTermsToReplacementAreaWithTargetPicker({
  required BuildContext context,
  required StudioScriptViewModel viewModel,
  required int frameIndex,
  required PromptTagContextMenuContext actionContext,
  required String fallbackSourceLocation,
}) async {
  final sourceGroupId = actionContext.groupId ?? '';
  final sourceLocation = _replacementSourceLocation(
    actionContext,
    fallbackSourceLocation,
  );
  final terms = _frameReviewReplacementTermDrafts(actionContext);
  final choices = _replacementTargetChoices(
    viewModel: viewModel,
    actionContext: actionContext,
    sourceLocation: sourceLocation,
  );
  if (choices.length <= 1) {
    return viewModel.addFrameReviewTermsToReplacementArea(
      frameIndex: frameIndex,
      sourceGroupId: sourceGroupId,
      sourceLocation: sourceLocation,
      terms: terms,
    );
  }
  final target = await _showReplacementTargetPicker(context, choices);
  if (target == null) {
    return null;
  }
  return switch (target.kind) {
    _ReplacementTargetKind.role =>
      viewModel.addFrameReviewTermsToRoleReplacementArea(
        sourceRoleId: target.id,
        frameIndex: frameIndex,
        sourceLocation: target.label,
        terms: terms,
      ),
    _ReplacementTargetKind.scene =>
      viewModel.addFrameReviewTermsToSceneReplacementArea(
        groupId: target.id,
        frameIndex: frameIndex,
        sourceLocation: target.label,
        terms: terms,
      ),
    _ReplacementTargetKind.currentSource =>
      viewModel.addFrameReviewTermsToReplacementArea(
        frameIndex: frameIndex,
        sourceGroupId: sourceGroupId,
        sourceLocation: sourceLocation,
        terms: terms,
      ),
  };
}

Future<bool?> _addSelectedFramePreviewTermsToReplacementAreaWithTargetPicker({
  required BuildContext context,
  required StudioScriptViewModel viewModel,
  required PromptTagContextMenuContext actionContext,
}) async {
  final sourceGroupId = actionContext.groupId ?? '';
  final sourceLocation = _replacementSourceLocation(actionContext, '源帧');
  final terms = _frameReviewReplacementTermDrafts(actionContext);
  final choices = _replacementTargetChoices(
    viewModel: viewModel,
    actionContext: actionContext,
    sourceLocation: sourceLocation,
  );
  if (choices.length <= 1) {
    return viewModel.addSelectedFramePreviewTermsToReplacementArea(
      sourceGroupId: sourceGroupId,
      sourceLocation: sourceLocation,
      terms: terms,
    );
  }
  final target = await _showReplacementTargetPicker(context, choices);
  if (target == null) {
    return null;
  }
  return switch (target.kind) {
    _ReplacementTargetKind.role =>
      viewModel.addSelectedFramePreviewTermsToRoleReplacementArea(
        sourceRoleId: target.id,
        sourceLocation: target.label,
        terms: terms,
      ),
    _ReplacementTargetKind.scene =>
      viewModel.addSelectedFramePreviewTermsToSceneReplacementArea(
        groupId: target.id,
        sourceLocation: target.label,
        terms: terms,
      ),
    _ReplacementTargetKind.currentSource =>
      viewModel.addSelectedFramePreviewTermsToReplacementArea(
        sourceGroupId: sourceGroupId,
        sourceLocation: sourceLocation,
        terms: terms,
      ),
  };
}

List<_ReplacementTargetChoice> _replacementTargetChoices({
  required StudioScriptViewModel viewModel,
  required PromptTagContextMenuContext actionContext,
  required String sourceLocation,
}) {
  final sourceGroupId = actionContext.groupId ?? '';
  final preferredRoleId = _preferredReplacementRoleId(
    viewModel,
    sourceGroupId,
  );
  final sourceIsRole = _isRoleFrameReviewGroup(sourceGroupId);
  final choices = <_ReplacementTargetChoice>[
    for (final role in viewModel.roleReplacementMappings)
      _ReplacementTargetChoice(
        kind: _ReplacementTargetKind.role,
        id: role.sourceRoleId,
        label: role.sourceLabel,
        preview: role.sourcePreview,
        recommended: role.sourceRoleId == preferredRoleId,
      ),
    for (final scene in viewModel.sceneReplacementMappings)
      _ReplacementTargetChoice(
        kind: _ReplacementTargetKind.scene,
        id: scene.id,
        label: scene.label,
        preview: '场景替换',
      ),
  ];
  if (!sourceIsRole) {
    choices.add(
      _ReplacementTargetChoice(
        kind: _ReplacementTargetKind.currentSource,
        id: sourceGroupId,
        label: sourceLocation,
        preview: '当前来源分组',
        recommended: true,
      ),
    );
  }
  choices.sort((left, right) {
    if (left.recommended != right.recommended) {
      return left.recommended ? -1 : 1;
    }
    return 0;
  });
  return choices;
}

Future<_ReplacementTargetChoice?> _showReplacementTargetPicker(
  BuildContext context,
  List<_ReplacementTargetChoice> choices,
) {
  return showDialog<_ReplacementTargetChoice>(
    context: context,
    builder: (context) {
      return AlertDialog(
        key: const ValueKey('script-replacement-target-picker'),
        backgroundColor: StudioTokens.surface1,
        title: const Text('选择待替换目标'),
        content: SizedBox(
          width: 440,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in choices)
                    ListTile(
                      key: choice.key,
                      leading: Icon(_replacementTargetIcon(choice.kind)),
                      title: Text(choice.label),
                      subtitle: Text(
                        _replacementTargetSubtitle(choice),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: choice.recommended
                          ? const Text(
                              '默认',
                              style: TextStyle(color: StudioTokens.primary),
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(choice),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
}

IconData _replacementTargetIcon(_ReplacementTargetKind kind) {
  return switch (kind) {
    _ReplacementTargetKind.role => Icons.manage_accounts_outlined,
    _ReplacementTargetKind.scene => Icons.landscape_outlined,
    _ReplacementTargetKind.currentSource => Icons.my_location_outlined,
  };
}

String _replacementTargetSubtitle(_ReplacementTargetChoice choice) {
  final type = switch (choice.kind) {
    _ReplacementTargetKind.role => '角色替换',
    _ReplacementTargetKind.scene => '场景替换',
    _ReplacementTargetKind.currentSource => '当前来源',
  };
  final preview = choice.preview.trim();
  if (preview.isEmpty) {
    return type;
  }
  return '$type · $preview';
}

String _replacementSourceLocation(
  PromptTagContextMenuContext actionContext,
  String fallback,
) {
  final groupLabel = actionContext.groupLabel?.trim();
  if (groupLabel != null && groupLabel.isNotEmpty) {
    return groupLabel;
  }
  final groupId = actionContext.groupId?.trim();
  if (groupId != null && groupId.isNotEmpty) {
    return groupId;
  }
  return fallback;
}

String? _preferredReplacementRoleId(
  StudioScriptViewModel viewModel,
  String sourceGroupId,
) {
  final match = RegExp(
    r'^role-(\d+)$',
  ).firstMatch(_normalizedFrameReviewGroupId(sourceGroupId));
  if (match == null) {
    return null;
  }
  final index = int.tryParse(match.group(1) ?? '');
  if (index == null || index <= 0) {
    return null;
  }
  final roles = viewModel.roleReplacementMappings;
  if (index <= roles.length) {
    return roles[index - 1].sourceRoleId;
  }
  if (roles.length == 1) {
    return roles.single.sourceRoleId;
  }
  return null;
}

bool _isRoleFrameReviewGroup(String sourceGroupId) {
  return RegExp(
    r'^role-\d+$',
  ).hasMatch(_normalizedFrameReviewGroupId(sourceGroupId));
}

String _normalizedFrameReviewGroupId(String sourceGroupId) {
  final trimmed = sourceGroupId.trim();
  if (trimmed.startsWith('before-')) {
    return trimmed.substring('before-'.length);
  }
  return trimmed;
}

List<StudioScriptReplacementSourceTermDraft> _frameReviewReplacementTermDrafts(
  PromptTagContextMenuContext context,
) {
  final seen = <String>{};
  return [
    for (final tag in context.selectedTags)
      if (seen.add(PromptTagProcessor.normalizeMatchKey(tag.displayText)))
        StudioScriptReplacementSourceTermDraft(
          text: tag.promptText,
          category: tag.classification.category,
        ),
  ];
}

void _showFrameReviewReplacementSnack(BuildContext context, bool added) {
  if (Scaffold.maybeOf(context) == null) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        added ? '已加入当前替换规则' : '未找到可加入的替换规则',
      ),
    ),
  );
}

class _ReviewTokenCollection extends StatefulWidget {
  final List<StudioScriptReviewToken> tokens;
  final bool grouped;

  const _ReviewTokenCollection({
    required this.tokens,
    required this.grouped,
  });

  @override
  State<_ReviewTokenCollection> createState() => _ReviewTokenCollectionState();
}

class _ReviewTokenCollectionState extends State<_ReviewTokenCollection> {
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};
  final Map<String, String> _translationOverrides = <String, String>{};
  final List<String> _autoTranslationQueue = <String>[];
  final Set<String> _autoTranslationPending = <String>{};
  final Set<int> _selectedIndexes = <int>{};
  bool _autoTranslationRunning = false;
  bool _isDragSelecting = false;
  int? _dragAnchorIndex;
  int? _hoveredIndex;

  @override
  void didUpdateWidget(covariant _ReviewTokenCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tokenSignature(oldWidget.tokens) != _tokenSignature(widget.tokens)) {
      _chipKeys.clear();
      _translationOverrides.clear();
      _autoTranslationQueue.clear();
      _autoTranslationPending.clear();
      _selectedIndexes.clear();
      _autoTranslationRunning = false;
      _isDragSelecting = false;
      _dragAnchorIndex = null;
      _hoveredIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _enqueueAutoTranslations(widget.tokens);
    });

    final items = [
      for (final (index, token) in widget.tokens.indexed)
        _ReviewTokenItem(index: index, token: token),
    ];
    late final Widget body;
    if (!widget.grouped) {
      body = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items) _buildChip(context, item),
        ],
      );
    } else {
      final groupWidgets = <Widget>[];
      for (final group in _reviewTokenGroupOrder) {
        final groupItems = items
            .where((item) =>
                _reviewTokenGroupForCategory(item.token.category).id ==
                group.id)
            .toList(growable: false);
        if (groupItems.isEmpty) {
          continue;
        }
        groupWidgets.add(
          _ReviewTokenGroupBlock(
            key: ValueKey('script-review-token-group-${group.id}'),
            group: group,
            children: [
              for (final item in groupItems) _buildChip(context, item),
            ],
          ),
        );
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, group) in groupWidgets.indexed) ...[
            group,
            if (index != groupWidgets.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    return Listener(
      key: ValueKey(
        widget.grouped
            ? 'script-review-token-collection-grouped'
            : 'script-review-token-collection-original',
      ),
      onPointerUp: (_) => _stopDragSelection(),
      onPointerCancel: (_) => _stopDragSelection(),
      child: body,
    );
  }

  Widget _buildChip(BuildContext context, _ReviewTokenItem item) {
    return _ReviewTokenChip(
      hitKey: _keyForChip(item.index),
      token: item.token,
      translation: _translationFor(item.token),
      loading: _autoTranslationPending.contains(item.token.source),
      selected: _selectedIndexes.contains(item.index),
      hovered: _hoveredIndex == item.index,
      onTap: () => _toggleSelectedIndex(item.index),
      onSelectStart: () => _startDragSelection(item.index),
      onPointerTraverse: _extendDragSelectionFromPosition,
      onHoverChanged: (hovered) {
        if (_hoveredIndex == item.index && !hovered) {
          setState(() {
            _hoveredIndex = null;
          });
        } else if (hovered && _hoveredIndex != item.index) {
          setState(() {
            _hoveredIndex = item.index;
          });
        }
      },
      onSecondaryTapDown: (details) => _showTokenMenu(
        context,
        details.globalPosition,
        item,
      ),
    );
  }

  GlobalKey _keyForChip(int index) {
    return _chipKeys.putIfAbsent(index, GlobalKey.new);
  }

  String _tokenSignature(List<StudioScriptReviewToken> tokens) {
    return tokens
        .map(
          (token) => [
            token.source,
            token.translation,
            token.category.name,
            token.emphasis.name,
          ].join('|'),
        )
        .join('||');
  }

  TranslationCache _translationCache() {
    if (GetIt.I.isRegistered<TranslationCache>()) {
      return GetIt.I<TranslationCache>();
    }
    return TranslationCache();
  }

  PromptTranslationService? _promptTranslationService() {
    if (GetIt.I.isRegistered<PromptTranslationService>()) {
      return GetIt.I<PromptTranslationService>();
    }
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      return DefaultPromptTranslationService(
        translationCache: _translationCache(),
        settingsProvider: () => GetIt.I<PayloadConfig>().settings,
        translationCacheReloader: PromptWorkshopBridge.loadTranslationCache,
      );
    }
    return null;
  }

  String _translationFor(StudioScriptReviewToken token) {
    final override = _translationOverrides[token.source];
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    if (token.translation.trim().isNotEmpty) {
      return token.translation;
    }
    return _translationCache().translate(token.source).text;
  }

  void _enqueueAutoTranslations(Iterable<StudioScriptReviewToken> tokens) {
    final service = _promptTranslationService();
    if (service == null) {
      return;
    }
    var added = false;
    for (final token in tokens) {
      final source = token.source.trim();
      if (source.isEmpty || _translationFor(token).trim().isNotEmpty) {
        continue;
      }
      if (_autoTranslationPending.contains(source)) {
        continue;
      }
      _autoTranslationPending.add(source);
      _autoTranslationQueue.add(source);
      added = true;
    }
    if (added && mounted) {
      setState(() {});
    }
    if (!_autoTranslationRunning) {
      _processAutoTranslationQueue(service);
    }
  }

  Future<void> _processAutoTranslationQueue(
    PromptTranslationService service,
  ) async {
    if (_autoTranslationRunning) {
      return;
    }
    _autoTranslationRunning = true;
    while (_autoTranslationQueue.isNotEmpty) {
      final source = _autoTranslationQueue.removeAt(0);
      final result = await service.translate(
        OnlineTranslationRequest(
          text: source,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
      );
      final translated = result.text.trim();
      if (translated.isNotEmpty) {
        if (result.source == OnlineAiResultSource.online) {
          final cache = _translationCache();
          cache.setCached(
            source,
            translated,
            source: result.providerName ?? service.currentMode.name,
          );
          await _saveTranslationCache(cache);
        }
        _translationOverrides[source] = translated;
      }
      _autoTranslationPending.remove(source);
      if (mounted) {
        setState(() {});
      }
    }
    _autoTranslationRunning = false;
  }

  void _toggleSelectedIndex(int index) {
    setState(() {
      if (!_selectedIndexes.add(index)) {
        _selectedIndexes.remove(index);
      }
    });
  }

  void _startDragSelection(int index) {
    setState(() {
      _isDragSelecting = true;
      _dragAnchorIndex = index;
      _selectedIndexes.clear();
    });
  }

  void _extendDragSelectionFromPosition(Offset globalPosition) {
    if (!_isDragSelecting) {
      return;
    }
    for (final entry in _chipKeys.entries) {
      final context = entry.value.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPosition)) {
        final anchorIndex = _dragAnchorIndex;
        if (anchorIndex != null) {
          _selectedIndexes.add(anchorIndex);
        }
        if (_selectedIndexes.add(entry.key) || anchorIndex != null) {
          setState(() {});
        }
        return;
      }
    }
  }

  void _stopDragSelection() {
    if (!_isDragSelecting) {
      return;
    }
    setState(() {
      _isDragSelecting = false;
      _dragAnchorIndex = null;
    });
  }

  Future<void> _showTokenMenu(
    BuildContext context,
    Offset position,
    _ReviewTokenItem item,
  ) async {
    final action = await showMenu<_ReviewTokenMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: _ReviewTokenMenuAction.retranslate,
          child: Text(_retranslateMenuLabel()),
        ),
        const PopupMenuItem(
          value: _ReviewTokenMenuAction.manualEdit,
          child: Text('手动编辑翻译'),
        ),
        const PopupMenuItem(
          value: _ReviewTokenMenuAction.copy,
          child: Text('复制源词'),
        ),
      ],
    );
    if (!mounted || !context.mounted || action == null) {
      return;
    }
    switch (action) {
      case _ReviewTokenMenuAction.retranslate:
        await _retranslateToken(context, item.token);
      case _ReviewTokenMenuAction.manualEdit:
        await _editTranslation(context, item.token);
      case _ReviewTokenMenuAction.copy:
        await _copyTokens(context, fallbackIndex: item.index);
    }
  }

  String _retranslateMenuLabel() {
    final service = _promptTranslationService();
    if (service == null) {
      return '重新翻译';
    }
    return switch (service.currentMode) {
      OnlineAiMode.google => 'Google 重译',
      OnlineAiMode.ai => 'AI 重译',
    };
  }

  Future<void> _retranslateToken(
    BuildContext context,
    StudioScriptReviewToken token,
  ) async {
    final service = _promptTranslationService();
    final result = service == null
        ? const OnlineTranslationResult(
            text: '',
            source: OnlineAiResultSource.emptyFallback,
            error: '未配置翻译服务',
          )
        : await service.translate(
            OnlineTranslationRequest(
              text: token.source,
              sourceLanguage: 'en',
              targetLanguage: 'zh',
            ),
            preferCache: false,
          );
    final translated = result.text.trim();
    if (!mounted || !context.mounted) {
      return;
    }
    if (translated.isEmpty) {
      _showSnack(context, result.error ?? '暂无可用翻译');
      return;
    }
    final cache = _translationCache();
    cache.setCached(
      token.source,
      translated,
      source: result.providerName ?? service?.currentMode.name ?? 'manual',
    );
    await _saveTranslationCache(cache);
    setState(() {
      _translationOverrides[token.source] = translated;
    });
    if (context.mounted) {
      _showSnack(context, '已更新翻译');
    }
  }

  Future<void> _editTranslation(
    BuildContext context,
    StudioScriptReviewToken token,
  ) async {
    final controller = TextEditingController(text: _translationFor(token));
    final translated = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: StudioTokens.surface2,
          title: const Text('手动编辑翻译'),
          content: SizedBox(
            width: 420,
            child: TextField(
              key: const ValueKey('script-review-token-manual-translation'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: token.source,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final trimmed = translated?.trim();
    if (!mounted || !context.mounted || trimmed == null || trimmed.isEmpty) {
      return;
    }
    final cache = _translationCache();
    cache.setManual(token.source, trimmed);
    await _saveTranslationCache(cache);
    setState(() {
      _translationOverrides[token.source] = trimmed;
    });
    if (context.mounted) {
      _showSnack(context, '已保存翻译');
    }
  }

  Future<void> _copyTokens(
    BuildContext context, {
    required int fallbackIndex,
  }) async {
    final indexes = _selectedIndexes.isEmpty
        ? [fallbackIndex]
        : (_selectedIndexes.toList()..sort());
    final tags = [
      for (final index in indexes)
        if (index >= 0 && index < widget.tokens.length)
          widget.tokens[index].source,
    ];
    await Clipboard.setData(ClipboardData(text: tags.join(', ')));
    if (context.mounted) {
      _showSnack(context, tags.length > 1 ? '已复制选中源词' : '已复制源词');
    }
  }

  Future<void> _saveTranslationCache(TranslationCache cache) async {
    try {
      await PromptWorkshopBridge.saveTranslationCache(cache);
    } catch (_) {
      // Saving the external prompt-workshop cache is best effort; the in-memory
      // translation is still useful for the current review session.
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReviewTokenChip extends StatelessWidget {
  final GlobalKey? hitKey;
  final StudioScriptReviewToken token;
  final String translation;
  final bool loading;
  final bool selected;
  final bool hovered;
  final VoidCallback? onTap;
  final VoidCallback? onSelectStart;
  final ValueChanged<Offset>? onPointerTraverse;
  final ValueChanged<bool>? onHoverChanged;
  final GestureTapDownCallback? onSecondaryTapDown;

  const _ReviewTokenChip({
    this.hitKey,
    required this.token,
    required this.translation,
    this.loading = false,
    this.selected = false,
    this.hovered = false,
    this.onTap,
    this.onSelectStart,
    this.onPointerTraverse,
    this.onHoverChanged,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = _tokenCategoryColor(token.category);
    final emphasized = token.emphasis != StudioScriptTokenEmphasis.normal;
    final emphasisLabel = _emphasisLabel(token.emphasis);
    final hasTranslation = translation.trim().isNotEmpty;
    final showLoading = loading && !hasTranslation;
    final borderColor = selected
        ? StudioTokens.primary
        : hovered
            ? StudioTokens.borderStrong
            : StudioTokens.border;
    final backgroundColor = selected
        ? const Color(0xFF22200B)
        : hovered
            ? const Color(0xFF1C1C1C)
            : const Color(0xFF181818);
    final chipBody = Container(
      key: ValueKey(
        'script-review-token-${token.source}-${token.category.name}-${token.emphasis.name}',
      ),
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 280),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: StudioTokens.radiusTag,
        border: Border.all(color: borderColor),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0xCCFFE500),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              key: ValueKey('script-review-token-stripe-${token.source}'),
              decoration: BoxDecoration(
                color: categoryColor,
                borderRadius: StudioTokens.radiusTagStripe,
              ),
              child: const SizedBox(width: 3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 11, 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        token.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: StudioTokens.textPrimary,
                                  fontWeight: emphasized
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                ),
                      ),
                    ),
                    if (emphasisLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(
                        _emphasisIcon(token.emphasis),
                        size: 13,
                        color: categoryColor,
                      ),
                    ],
                  ],
                ),
                if (hasTranslation || showLoading) ...[
                  const SizedBox(height: 2),
                  Text(
                    hasTranslation ? translation : '翻译中...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StudioTokens.textSecondary,
                        ),
                  ),
                ],
                if (emphasisLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    emphasisLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: categoryColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final chip = Stack(
      clipBehavior: Clip.none,
      children: [
        chipBody,
        if (selected)
          Positioned(
            top: -7,
            right: -6,
            child: DecoratedBox(
              key: ValueKey('script-review-token-check-${token.source}'),
              decoration: const BoxDecoration(
                color: StudioTokens.primary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 18,
                height: 18,
                child: Center(
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: StudioTokens.onPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final wrappedChip = KeyedSubtree(key: hitKey, child: chip);
    return Listener(
      onPointerMove: (event) => onPointerTraverse?.call(event.position),
      onPointerHover: (event) => onPointerTraverse?.call(event.position),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (event) {
          onHoverChanged?.call(true);
          onPointerTraverse?.call(event.position);
        },
        onExit: (_) => onHoverChanged?.call(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onTapDown: (_) => onSelectStart?.call(),
          onSecondaryTapDown: onSecondaryTapDown,
          child: Semantics(
            selected: selected,
            button: true,
            label: token.source,
            child: wrappedChip,
          ),
        ),
      ),
    );
  }
}

class _ReviewTokenItem {
  final int index;
  final StudioScriptReviewToken token;

  const _ReviewTokenItem({
    required this.index,
    required this.token,
  });
}

enum _ReviewTokenMenuAction { retranslate, manualEdit, copy }

class _ReviewTokenGroupSpec {
  final String id;
  final String label;
  final IconData icon;

  const _ReviewTokenGroupSpec({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class _ReviewTokenGroupBlock extends StatelessWidget {
  final _ReviewTokenGroupSpec group;
  final List<Widget> children;

  const _ReviewTokenGroupBlock({
    super.key,
    required this.group,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(group.icon, size: 16, color: StudioTokens.primary),
              const SizedBox(width: 6),
              Text(
                group.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _TokenColorLegend extends StatelessWidget {
  final List<StudioScriptTokenCategory> categories;

  const _TokenColorLegend({required this.categories});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final category in categories)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _tokenCategoryColor(category),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _tokenCategoryLabel(category),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
            ],
          ),
      ],
    );
  }
}

class _NegativePromptStrategyControl extends StatefulWidget {
  const _NegativePromptStrategyControl({super.key});

  @override
  State<_NegativePromptStrategyControl> createState() =>
      _NegativePromptStrategyControlState();
}

class _NegativePromptStrategyControlState
    extends State<_NegativePromptStrategyControl> {
  String _strategy = 'keep';

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
      ),
      segments: const [
        ButtonSegment(value: 'keep', label: Text('保留')),
        ButtonSegment(value: 'follow', label: Text('跟随')),
        ButtonSegment(value: 'override', label: Text('覆盖')),
      ],
      selected: {_strategy},
      onSelectionChanged: (selection) {
        setState(() {
          _strategy = selection.first;
        });
      },
    );
  }
}

const _reviewTokenGroupOrder = [
  _ReviewTokenGroupSpec(
    id: 'quality',
    label: '画质区',
    icon: Icons.star_border,
  ),
  _ReviewTokenGroupSpec(
    id: 'artist',
    label: '画师区',
    icon: Icons.palette_outlined,
  ),
  _ReviewTokenGroupSpec(
    id: 'character',
    label: '角色区',
    icon: Icons.person_outline,
  ),
  _ReviewTokenGroupSpec(
    id: 'clothing',
    label: '服装/身体',
    icon: Icons.checkroom_outlined,
  ),
  _ReviewTokenGroupSpec(
    id: 'action',
    label: '动作区',
    icon: Icons.directions_run,
  ),
  _ReviewTokenGroupSpec(
    id: 'scene',
    label: '场景/镜头',
    icon: Icons.landscape_outlined,
  ),
  _ReviewTokenGroupSpec(
    id: 'style',
    label: '风格区',
    icon: Icons.tune_outlined,
  ),
  _ReviewTokenGroupSpec(
    id: 'negative',
    label: '负面区',
    icon: Icons.block_outlined,
  ),
  _ReviewTokenGroupSpec(
    id: 'other',
    label: '其它',
    icon: Icons.more_horiz,
  ),
];

_ReviewTokenGroupSpec _reviewTokenGroupForCategory(
  StudioScriptTokenCategory category,
) {
  final id = switch (category) {
    StudioScriptTokenCategory.quality ||
    StudioScriptTokenCategory.negativeQuality =>
      'quality',
    StudioScriptTokenCategory.artistChain ||
    StudioScriptTokenCategory.negativeArtist =>
      'artist',
    StudioScriptTokenCategory.character => 'character',
    StudioScriptTokenCategory.upperBody ||
    StudioScriptTokenCategory.lowerBody ||
    StudioScriptTokenCategory.upperClothing ||
    StudioScriptTokenCategory.lowerClothing ||
    StudioScriptTokenCategory.negativeBody =>
      'clothing',
    StudioScriptTokenCategory.action => 'action',
    StudioScriptTokenCategory.scene ||
    StudioScriptTokenCategory.camera =>
      'scene',
    StudioScriptTokenCategory.style => 'style',
    StudioScriptTokenCategory.negativeContent => 'negative',
    StudioScriptTokenCategory.other => 'other',
  };
  return _reviewTokenGroupOrder.firstWhere((group) => group.id == id);
}

List<StudioScriptTokenCategory> _legendCategories(
  List<StudioScriptReviewToken> tokens,
) {
  final present = tokens.map((token) => token.category).toSet();
  return [
    for (final category in StudioScriptTokenCategory.values)
      if (present.contains(category)) category,
  ];
}

String _tokenCategoryLabel(StudioScriptTokenCategory category) {
  return switch (category) {
    StudioScriptTokenCategory.character => '角色',
    StudioScriptTokenCategory.upperBody => '上身',
    StudioScriptTokenCategory.lowerBody => '下身',
    StudioScriptTokenCategory.upperClothing => '上装',
    StudioScriptTokenCategory.lowerClothing => '下装',
    StudioScriptTokenCategory.action => '动作',
    StudioScriptTokenCategory.scene => '场景',
    StudioScriptTokenCategory.camera => '镜头',
    StudioScriptTokenCategory.artistChain => '画师',
    StudioScriptTokenCategory.style => '风格',
    StudioScriptTokenCategory.quality => '画质',
    StudioScriptTokenCategory.negativeQuality => '负面画质',
    StudioScriptTokenCategory.negativeBody => '负面人体',
    StudioScriptTokenCategory.negativeArtist => '负面画师',
    StudioScriptTokenCategory.negativeContent => '负面内容',
    StudioScriptTokenCategory.other => '其它',
  };
}

Color _tokenCategoryColor(StudioScriptTokenCategory category) {
  return switch (category) {
    StudioScriptTokenCategory.character => const Color(0xFF4F8DF7),
    StudioScriptTokenCategory.upperBody => const Color(0xFF7B61FF),
    StudioScriptTokenCategory.lowerBody => const Color(0xFF6D79D8),
    StudioScriptTokenCategory.upperClothing => const Color(0xFF00A676),
    StudioScriptTokenCategory.lowerClothing => const Color(0xFF2E9F9F),
    StudioScriptTokenCategory.action => const Color(0xFFE58A00),
    StudioScriptTokenCategory.scene => const Color(0xFF5E9F3D),
    StudioScriptTokenCategory.camera => const Color(0xFF6574A6),
    StudioScriptTokenCategory.artistChain => const Color(0xFFC850A0),
    StudioScriptTokenCategory.style => const Color(0xFF9A6B34),
    StudioScriptTokenCategory.quality => const Color(0xFFD1A300),
    StudioScriptTokenCategory.negativeQuality => const Color(0xFFD95757),
    StudioScriptTokenCategory.negativeBody => const Color(0xFFC13B6A),
    StudioScriptTokenCategory.negativeArtist => const Color(0xFF9B4BC4),
    StudioScriptTokenCategory.negativeContent => const Color(0xFF9A6A5D),
    StudioScriptTokenCategory.other => const Color(0xFF7A8799),
  };
}

String _emphasisLabel(StudioScriptTokenEmphasis emphasis) {
  return switch (emphasis) {
    StudioScriptTokenEmphasis.normal => '',
    StudioScriptTokenEmphasis.aiRecognized => 'AI',
    StudioScriptTokenEmphasis.cacheHit => 'Cache',
    StudioScriptTokenEmphasis.userConfirmed => 'Confirmed',
    StudioScriptTokenEmphasis.replacementAffected => 'Replacement',
  };
}

IconData _emphasisIcon(StudioScriptTokenEmphasis emphasis) {
  return switch (emphasis) {
    StudioScriptTokenEmphasis.normal => Icons.circle_outlined,
    StudioScriptTokenEmphasis.aiRecognized => Icons.auto_awesome_outlined,
    StudioScriptTokenEmphasis.cacheHit => Icons.cached_outlined,
    StudioScriptTokenEmphasis.userConfirmed => Icons.verified_outlined,
    StudioScriptTokenEmphasis.replacementAffected => Icons.swap_horiz_outlined,
  };
}

class _FramePreviewColumn extends StatefulWidget {
  final StudioScriptFrameSplitPreview preview;
  final PromptTagFilterRuleAdder? onAddToFilterRules;
  final PromptTagContextMenuActionBuilder? contextMenuActionBuilder;
  final bool allowReplacementComparison;
  final PromptTagDisplayDiffResolver? replacementDiffStateForTag;
  final PromptTagDisplayDiffTooltipResolver? replacementDiffTooltipForTag;

  const _FramePreviewColumn({
    required this.preview,
    this.onAddToFilterRules,
    this.contextMenuActionBuilder,
    this.allowReplacementComparison = false,
    this.replacementDiffStateForTag,
    this.replacementDiffTooltipForTag,
  });

  @override
  State<_FramePreviewColumn> createState() => _FramePreviewColumnState();
}

class _FramePreviewColumnState extends State<_FramePreviewColumn> {
  bool _showReplacementComparison = false;

  @override
  Widget build(BuildContext context) {
    final canCompareReplacement = widget.allowReplacementComparison &&
        widget.preview.groups.any((group) => group.tags.isNotEmpty) &&
        widget.replacementDiffStateForTag != null;
    return Container(
      key: ValueKey('selected-frame-preview-${widget.preview.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.preview.id == 'after'
            ? StudioTokens.surface3
            : StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.preview.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (canCompareReplacement)
                _SourceReplacementCompareToggle(
                  switchKey: ValueKey(
                    'script-frame-preview-${widget.preview.id}-'
                    'replacement-compare-toggle',
                  ),
                  value: _showReplacementComparison,
                  enabled: canCompareReplacement,
                  onChanged: (value) {
                    setState(() {
                      _showReplacementComparison = value;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 860
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final group in widget.preview.groups)
                    SizedBox(
                      width: cardWidth,
                      child: _FrameTagCard(
                        group: group,
                        onAddToFilterRules: widget.onAddToFilterRules,
                        contextMenuActionBuilder:
                            widget.contextMenuActionBuilder,
                        diffStateForTag: _showReplacementComparison
                            ? widget.replacementDiffStateForTag
                            : null,
                        diffTooltipForTag: _showReplacementComparison
                            ? widget.replacementDiffTooltipForTag
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FrameTagCard extends StatelessWidget {
  final StudioScriptFrameTagGroup group;
  final PromptTagFilterRuleAdder? onAddToFilterRules;
  final PromptTagContextMenuActionBuilder? contextMenuActionBuilder;
  final PromptTagDisplayDiffResolver? diffStateForTag;
  final PromptTagDisplayDiffTooltipResolver? diffTooltipForTag;

  const _FrameTagCard({
    required this.group,
    this.onAddToFilterRules,
    this.contextMenuActionBuilder,
    this.diffStateForTag,
    this.diffTooltipForTag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('selected-frame-card-${group.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(group.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          PromptTagDisplay(
            text: group.tags.join(', '),
            defaultTranslated: true,
            enableTagActions: true,
            onAddToFilterRules: onAddToFilterRules,
            contextMenuActionBuilder: contextMenuActionBuilder == null
                ? null
                : (context, actionContext) {
                    final scopedContext = actionContext.copyWith(
                      groupId: group.id,
                      groupLabel: group.label,
                    );
                    return [
                      for (final action in contextMenuActionBuilder!(
                        context,
                        scopedContext,
                      ))
                        action.copyWith(
                          onSelected: (context, _) =>
                              action.onSelected(context, scopedContext),
                        ),
                    ];
                  },
            filterRuleTargets: _scriptPromptFilterRuleTargets,
            diffStateForTag: diffStateForTag,
            diffTooltipForTag: diffTooltipForTag,
            dense: true,
            emptyText: '未检测',
          ),
        ],
      ),
    );
  }
}

PromptTagContextMenuActionBuilder _selectedFramePreviewReplacementActions({
  required StudioScriptViewModel viewModel,
}) {
  return (context, actionContext) {
    if (actionContext.negative) {
      return const <PromptTagContextMenuAction>[];
    }
    final terms = _frameReviewReplacementTermDrafts(actionContext);
    if (terms.isEmpty) {
      return const <PromptTagContextMenuAction>[];
    }
    return [
      PromptTagContextMenuAction(
        key: const ValueKey('script-frame-add-to-replacement-area'),
        icon: Icons.add_box_outlined,
        label: '加入待替换区',
        onSelected: (context, actionContext) async {
          final added =
              await _addSelectedFramePreviewTermsToReplacementAreaWithTargetPicker(
            context: context,
            viewModel: viewModel,
            actionContext: actionContext,
          );
          if (added != null && context.mounted) {
            _showFrameReviewReplacementSnack(context, added);
          }
        },
      ),
      if (viewModel.hasSingleSelectedReplacementRule)
        PromptTagContextMenuAction(
          key: const ValueKey('script-frame-add-to-current-replacement-rule'),
          icon: Icons.playlist_add_outlined,
          label: '加入当前替换规则',
          onSelected: (context, actionContext) {
            final added =
                viewModel.addSelectedFramePreviewTermsToSelectedReplacementRule(
              sourceLocation:
                  actionContext.groupLabel ?? actionContext.groupId ?? '源帧',
              terms: _frameReviewReplacementTermDrafts(actionContext),
            );
            if (context.mounted) {
              _showFrameReviewReplacementSnack(context, added);
            }
          },
        ),
    ];
  };
}

class _ScriptRecastPlanWorkspace extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ScriptRecastPlanWorkspace({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioStaggeredReveal(
          index: 0,
          child: _ViewModelSelector(
            viewModel: viewModel,
            select: (viewModel) => viewModel.globalPromptPrefix,
            builder: (context, _) =>
                _GlobalPromptPrefixPanel(viewModel: viewModel),
          ),
        ),
        const SizedBox(height: 16),
        StudioStaggeredReveal(
          index: 1,
          child: _AiRoleExtractionDraftSlot(viewModel: viewModel),
        ),
        const SizedBox(height: 16),
        StudioStaggeredReveal(
          index: 2,
          child: _ViewModelSelector(
            viewModel: viewModel,
            select: (viewModel) => (
              viewModel.recastPlan.roles.isEmpty,
              viewModel.recastPlan.hasAiBackedPlan,
              viewModel.artistMappings.isEmpty,
              viewModel.roleReplacementMappings,
              viewModel.sceneReplacementMappings,
            ),
            builder: (context, _) => _RecastPlanPanel(viewModel: viewModel),
          ),
        ),
        const SizedBox(height: 16),
        StudioStaggeredReveal(
          index: 3,
          child: _ViewModelSelector(
            viewModel: viewModel,
            select: (viewModel) => viewModel.recastPlan.issues,
            builder: (context, _) => _NeedsAttentionPanel(viewModel: viewModel),
          ),
        ),
      ],
    );
  }
}

class _AiRoleExtractionDraftSlot extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _AiRoleExtractionDraftSlot({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return _ViewModelSelector(
      viewModel: viewModel,
      select: (viewModel) => (
        viewModel.isAiRoleExtractionDraftCollapsed,
        viewModel.showAiRoleExtractionDraftPanel,
        viewModel.aiRoleExtraction,
        viewModel.hasAiRoleExtractionCacheAdjustments,
        viewModel.isAiBusy,
      ),
      builder: (context, _) {
        final visible = viewModel.isAiRoleExtractionDraftCollapsed ||
            viewModel.showAiRoleExtractionDraftPanel;
        return StudioAnimatedPresence(
          key: const ValueKey('script-ai-role-extraction-draft-presence'),
          visible: visible,
          builder: (context) {
            return AnimatedSwitcher(
              duration: StudioMotionTokens.fast,
              switchInCurve: StudioMotionTokens.showcaseCurve,
              switchOutCurve: StudioMotionTokens.utilityCurve,
              child: viewModel.isAiRoleExtractionDraftCollapsed
                  ? KeyedSubtree(
                      key: const ValueKey('script-ai-draft-collapsed-state'),
                      child: _CollapsedAiRoleExtractionDraftPanel(
                        viewModel: viewModel,
                      ),
                    )
                  : viewModel.showAiRoleExtractionDraftPanel
                      ? KeyedSubtree(
                          key: const ValueKey('script-ai-draft-expanded-state'),
                          child: _AiRoleExtractionDraftPanel(
                            viewModel: viewModel,
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('script-ai-draft-hidden-state'),
                        ),
            );
          },
        );
      },
    );
  }
}

class _CollapsedAiRoleExtractionDraftPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _CollapsedAiRoleExtractionDraftPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final extraction = viewModel.aiRoleExtraction;
    final summary = extraction.isReady
        ? '已收起 · ${extraction.roles.length} 个角色 · '
            '${_aiRoleExtractionStageCount(extraction)} 个阶段'
        : extraction.isFailed
            ? '已收起 · 角色字段整理失败'
            : '已收起';
    return StudioPanel(
      key: const ValueKey('script-ai-role-extraction-draft-collapsed'),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            size: 19,
            color: StudioTokens.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 角色字段草稿',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(summary, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          StudioIconButton(
            icon: Icons.expand_more_outlined,
            tooltip: '展开 AI 角色字段草稿',
            onPressed: () {
              unawaited(viewModel.expandAiRoleExtractionDraft());
            },
          ),
        ],
      ),
    );
  }
}

class _AiRoleExtractionDraftPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _AiRoleExtractionDraftPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final extraction = viewModel.aiRoleExtraction;
    final displayRoles = _aiRoleExtractionDisplayRoles(extraction);
    final isReady = extraction.isReady;
    final isFailed = extraction.isFailed;
    return _SectionPanel(
      key: const ValueKey('script-ai-role-extraction-draft-panel'),
      title: 'AI 角色字段草稿',
      icon: isFailed ? Icons.error_outline : Icons.auto_awesome_outlined,
      actions: [
        if (isReady || isFailed)
          StudioIconButton(
            icon: Icons.expand_less_outlined,
            tooltip: '收起 AI 角色字段草稿',
            onPressed: () {
              unawaited(viewModel.collapseAiRoleExtractionDraft());
            },
          ),
      ],
      children: [
        if (!isReady && !isFailed) ...[
          const _EmptyHint(text: '点击 AI 整理角色字段后，会在这里显示可应用的字段草稿'),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isFailed
                  ? StudioTokens.warning.withValues(alpha: 0.1)
                  : StudioTokens.surface2,
              borderRadius: StudioTokens.radiusSlot,
              border: StudioTokens.cardBorder,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isFailed
                        ? '角色字段整理失败'
                        : '可应用草稿 · ${extraction.roles.length} 个角色 · '
                            '${_aiRoleExtractionStageCount(extraction)} 个阶段 · '
                            '整体置信度 ${(extraction.confidence * 100).round()}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isFailed ? StudioTokens.warning : null,
                        ),
                  ),
                ),
                if (isReady) ...[
                  const SizedBox(width: 12),
                  StudioIconButton(
                    icon: Icons.subject_outlined,
                    tooltip: '查看 AI 处理详情',
                    onPressed: () =>
                        _showAiProcessingDetails(context, viewModel),
                  ),
                  const SizedBox(width: 8),
                  if (viewModel.hasAiRoleExtractionCacheAdjustments) ...[
                    StudioButton(
                      key: const ValueKey(
                        'script-ai-role-apply-cache-adjustment',
                      ),
                      label: '按照缓存调整',
                      icon: Icons.auto_fix_high_outlined,
                      tone: StudioButtonTone.secondary,
                      onPressed: viewModel.isAiBusy
                          ? null
                          : () {
                              unawaited(
                                viewModel
                                    .applyAiRoleExtractionCacheAdjustment(),
                              );
                            },
                    ),
                    const SizedBox(width: 8),
                  ],
                  StudioButton(
                    label: '应用字段',
                    icon: Icons.playlist_add_check_outlined,
                    tone: StudioButtonTone.secondary,
                    onPressed: viewModel.isAiBusy
                        ? null
                        : () {
                            unawaited(
                              viewModel.applyAiRoleExtraction(),
                            );
                          },
                  ),
                ] else if (isFailed) ...[
                  const SizedBox(width: 12),
                  StudioIconButton(
                    icon: Icons.subject_outlined,
                    tooltip: '查看 AI 处理详情',
                    onPressed: () =>
                        _showAiProcessingDetails(context, viewModel),
                  ),
                  const SizedBox(width: 8),
                  StudioButton(
                    label: '手动重连',
                    icon: Icons.refresh_outlined,
                    tone: StudioButtonTone.secondary,
                    onPressed: viewModel.isAiBusy
                        ? null
                        : () {
                            unawaited(viewModel.generateAiRoleExtraction());
                          },
                  ),
                ],
              ],
            ),
          ),
          if (isReady) ...[
            const SizedBox(height: 8),
            _AiRoleExtractionCompactNotice(extraction: extraction),
          ],
          if (displayRoles.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final (index, role) in displayRoles.indexed)
              _AiRoleExtractionRoleRow(
                role: role,
                roleIndex: index,
                viewModel: viewModel,
              ),
          ] else if (isReady) ...[
            const SizedBox(height: 12),
            const _EmptyHint(text: 'AI 未返回可应用角色字段'),
          ],
          if (extraction.attentionItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final item in extraction.attentionItems)
              _AiRoleExtractionAttentionRow(
                item: item,
                fallbackRawResponse: extraction.rawResponse,
              ),
          ],
        ],
      ],
    );
  }
}

class _AiRoleExtractionRoleRow extends StatefulWidget {
  final ScriptAiExtractedRole role;
  final int roleIndex;
  final StudioScriptViewModel viewModel;

  const _AiRoleExtractionRoleRow({
    required this.role,
    required this.roleIndex,
    required this.viewModel,
  });

  @override
  State<_AiRoleExtractionRoleRow> createState() =>
      _AiRoleExtractionRoleRowState();
}

class _AiRoleExtractionRoleRowState extends State<_AiRoleExtractionRoleRow> {
  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final confidence = role.confidence <= 0
        ? ''
        : ' · 置信度 ${(role.confidence * 100).round()}%';
    final displayName = role.displayName.trim().isEmpty
        ? role.sourceRoleId.trim()
        : role.displayName.trim();
    final title = [
      '角色 ${widget.roleIndex + 1}',
      if (displayName.isNotEmpty) displayName,
    ].where((part) => part.isNotEmpty).join(' · ');
    final roleFrameIndexes = _aiRoleExtractionRoleFrameIndexes(role);
    final promptTerms = _aiRoleExtractionRolePromptTerms(role);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: title,
                  child: Text(
                    '${title.isEmpty ? '未命名角色' : title}$confidence',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: ValueKey('script-ai-role-save-${role.sourceRoleId}'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  unawaited(
                    _showAssetCaptureDraft(
                      context,
                      StudioAssetCaptureDrafts.characterFromAiRole(
                        role,
                        source: StudioAssetCaptureSource(
                          surface: 'script',
                          label: 'AI role extraction',
                          sourceId: role.sourceRoleId,
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.library_add_outlined, size: 16),
                label: const Text('保存素材'),
              ),
            ],
          ),
          if (roleFrameIndexes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AiRoleExtractionFrameChip(frameIndexes: roleFrameIndexes),
          ],
          if (role.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AiRoleExtractionWarningList(warnings: role.warnings),
          ],
          if (promptTerms.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AiRoleExtractionTermGroup(
              title: '角色替换来源词',
              icon: Icons.sell_outlined,
              translationCache: widget.viewModel.translationCache,
              terms: promptTerms,
            ),
          ],
        ],
      ),
    );
  }
}

class _AiRoleExtractionCompactNotice extends StatelessWidget {
  final ScriptAiRoleExtraction extraction;

  const _AiRoleExtractionCompactNotice({required this.extraction});

  @override
  Widget build(BuildContext context) {
    final notes = <String>[
      if (extraction.artistChains.isNotEmpty)
        '画风/画师证据 ${extraction.artistChains.length} 组',
      if (extraction.strongFilterKeywords.isNotEmpty)
        '强过滤词 ${extraction.strongFilterKeywords.length} 个，应用时会写入过滤库',
      if (extraction.unassignedTerms.isNotEmpty)
        '未使用证据 ${extraction.unassignedTerms.length} 个，已收进处理详情',
    ];
    if (notes.isEmpty) {
      return Text(
        '这里只显示会写入五字段的草稿；证据明细可在 AI 处理详情中查看。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final note in notes)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: StudioTokens.surface1,
              borderRadius: StudioTokens.radiusTag,
              border: Border.all(color: StudioTokens.border),
            ),
            child: Text(
              note,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
      ],
    );
  }
}

class _AiRoleExtractionFrameChip extends StatelessWidget {
  final List<int> frameIndexes;

  const _AiRoleExtractionFrameChip({required this.frameIndexes});

  @override
  Widget build(BuildContext context) {
    final label = _aiRoleExtractionFrameLabel(frameIndexes);
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return _AiRoleExtractionMetaChip(
      label: label,
      icon: Icons.movie_creation_outlined,
      highlighted: true,
    );
  }
}

class _AiRoleExtractionMetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool highlighted;

  const _AiRoleExtractionMetaChip({
    required this.label,
    this.icon,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        highlighted ? StudioTokens.primary : StudioTokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusPill,
        border: Border.all(
          color: highlighted ? StudioTokens.primary : StudioTokens.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

int _aiRoleExtractionStageCount(ScriptAiRoleExtraction extraction) {
  return extraction.roles.fold<int>(
    0,
    (count, role) => count + role.stages.length,
  );
}

List<ScriptAiExtractedRole> _aiRoleExtractionDisplayRoles(
  ScriptAiRoleExtraction extraction,
) {
  final roles = extraction.roles.indexed.toList(growable: false);
  roles.sort((left, right) {
    final priority = _aiRoleExtractionGenderPriority(
      left.$2,
    ).compareTo(_aiRoleExtractionGenderPriority(right.$2));
    if (priority != 0) {
      return priority;
    }
    return left.$1.compareTo(right.$1);
  });
  return List.unmodifiable([
    for (final (_, role) in roles) role,
  ]);
}

int _aiRoleExtractionGenderPriority(ScriptAiExtractedRole role) {
  final hasFemaleTerms = _aiRoleExtractionHasGenderTerms(
    role,
    _femaleAiRoleIdentityPattern,
  );
  final hasMaleTerms = _aiRoleExtractionHasGenderTerms(
    role,
    _maleAiRoleIdentityPattern,
  );
  if (hasFemaleTerms && !hasMaleTerms) {
    return 0;
  }
  if (hasMaleTerms && !hasFemaleTerms) {
    return 2;
  }
  return 1;
}

bool _aiRoleExtractionHasGenderTerms(
  ScriptAiExtractedRole role,
  RegExp pattern,
) {
  final texts = <String>[
    role.displayName,
    role.canonicalName,
    ...role.rawIdentityTags,
    for (final stage in role.stages) stage.identity,
  ];
  for (final text in texts) {
    final normalized = _normalizedAiLabel(text).replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (normalized.isNotEmpty && pattern.hasMatch(normalized)) {
      return true;
    }
  }
  return false;
}

final RegExp _femaleAiRoleIdentityPattern = RegExp(
  r'(^| )(?:\d+\s*)?(?:girl|girls|female|females|woman|women|lady|ladies)( |$)',
);

final RegExp _maleAiRoleIdentityPattern = RegExp(
  r'(^| )(?:\d+\s*)?(?:boy|boys|male|males|man|men|gentleman|gentlemen)( |$)',
);

List<int> _aiRoleExtractionRoleFrameIndexes(ScriptAiExtractedRole role) {
  final frameIndexes = <int>{};
  frameIndexes.addAll(_normalizedFrameIndexes(role.frameIndexes));
  for (final appearance in role.appearances) {
    frameIndexes.addAll(_normalizedFrameIndexes(appearance.frameIndexes));
  }
  for (final stage in role.stages) {
    frameIndexes.addAll(_normalizedFrameIndexes(stage.frameIndexes));
  }
  return frameIndexes.toList(growable: false)..sort();
}

List<String> _aiRoleExtractionRolePromptTerms(ScriptAiExtractedRole role) {
  final terms = <String>[];
  if (role.promptTerms.isNotEmpty) {
    for (final term in role.promptTerms) {
      final text = term.text.trim();
      if (text.isNotEmpty) {
        terms.add(text);
      }
    }
  } else {
    for (final stage in role.stages) {
      terms.addAll(_splitAiRolePromptTerms(stage.identity));
      terms.addAll(_splitAiRolePromptTerms(stage.upperBody));
      terms.addAll(_splitAiRolePromptTerms(stage.lowerBody));
      terms.addAll(_splitAiRolePromptTerms(stage.upperClothing));
      terms.addAll(_splitAiRolePromptTerms(stage.lowerClothing));
    }
  }
  final seen = <String>{};
  return List.unmodifiable([
    for (final term in terms)
      if (seen.add(PromptTagProcessor.normalizeMatchKey(term))) term,
  ]);
}

Iterable<String> _splitAiRolePromptTerms(String value) {
  return value
      .split(',')
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty);
}

List<int> _normalizedFrameIndexes(Iterable<int> frameIndexes) {
  final normalized = <int>{};
  for (final frameIndex in frameIndexes) {
    if (frameIndex >= 0) {
      normalized.add(frameIndex);
    }
  }
  return normalized.toList(growable: false)..sort();
}

String _aiRoleExtractionFrameLabel(List<int> frameIndexes) {
  final normalized = _normalizedFrameIndexes(frameIndexes);
  if (normalized.isEmpty) {
    return '';
  }
  const maxVisibleFrames = 6;
  final visible = normalized.take(maxVisibleFrames).join(', ');
  final remaining = normalized.length - maxVisibleFrames;
  if (remaining > 0) {
    return '所在帧 $visible +$remaining';
  }
  return '所在帧 $visible';
}

String _aiRoleExtractionWarningText(String warning) {
  final normalized = warning.trim();
  return switch (normalized) {
    'missing_identity' => '缺少身份字段',
    'missing_upper_body' => '缺少上身字段',
    'missing_lower_body' => '缺少下身字段',
    'missing_upper_clothing' => '缺少上装字段',
    'missing_lower_clothing' => '缺少下装字段',
    'identity' => '缺少身份字段',
    'upper_body' => '缺少上身字段',
    'lower_body' => '缺少下身字段',
    'upper_clothing' => '缺少上装字段',
    'lower_clothing' => '缺少下装字段',
    'full_outfit_unsplit' => '整套服装暂未拆成上下装',
    'ambiguous_global_roles' => '全局角色证据不够明确',
    'cannot_assign_terms_to_role' => '部分标签无法安全归到某个角色',
    _
        when normalized.contains('lower_body') &&
            normalized.toLowerCase().contains('review') =>
      '下身字段需要确认',
    _
        when normalized.contains('upper_body') &&
            normalized.toLowerCase().contains('review') =>
      '上身字段需要确认',
    _
        when normalized.contains('upper_clothing') &&
            normalized.toLowerCase().contains('review') =>
      '上装字段需要确认',
    _
        when normalized.contains('lower_clothing') &&
            normalized.toLowerCase().contains('review') =>
      '下装字段需要确认',
    _
        when normalized.contains('lower_body') &&
            normalized.toLowerCase().contains('empty') =>
      '下身字段为空',
    _
        when normalized.contains('upper_body') &&
            normalized.toLowerCase().contains('empty') =>
      '上身字段为空',
    _
        when normalized.contains('upper_clothing') &&
            normalized.toLowerCase().contains('empty') =>
      '上装字段为空',
    _
        when normalized.contains('lower_clothing') &&
            normalized.toLowerCase().contains('empty') =>
      '下装字段为空',
    _ => normalized,
  };
}

String _aiRoleExtractionAttentionText(ScriptAiExtractionAttentionItem item) {
  final message = item.message.trim();
  if (message.isEmpty) {
    return '需要人工确认';
  }
  final mapped = _aiRoleExtractionWarningText(message);
  if (mapped != message) {
    return mapped;
  }
  return switch (item.kind.trim()) {
    'merge_request_failed' => 'AI 合并请求未完成，已使用分块结果降级合并：$message',
    'parse_failure' when item.blocking => 'AI 返回解析失败：$message',
    'parse_failure' => 'AI 处理提醒：$message',
    'low_confidence' => '置信度提醒：$message',
    'ambiguous_global_roles' => '全局角色证据待确认：$message',
    'missing_field' => '字段待确认：$message',
    _ when item.blocking => 'AI 处理失败：$message',
    _ => 'AI 处理提醒：$message',
  };
}

class _AiRoleExtractionTermGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final TranslationCache translationCache;
  final List<String> terms;

  const _AiRoleExtractionTermGroup({
    required this.title,
    required this.icon,
    required this.translationCache,
    required this.terms,
  });

  @override
  Widget build(BuildContext context) {
    final visibleTerms = terms
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (visibleTerms.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: StudioTokens.textMuted),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PromptTagDisplay(
            text: visibleTerms.join(', '),
            defaultTranslated: true,
            dense: true,
            enableTagActions: true,
            initialLayoutMode: PromptTagLayoutMode.sourceOrder,
            respectInitialLayoutMode: true,
            translationCache: translationCache,
            emptyText: '暂无来源词',
          ),
        ],
      ),
    );
  }
}

class _AiRoleExtractionWarningList extends StatelessWidget {
  final List<String> warnings;

  const _AiRoleExtractionWarningList({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final visibleWarnings = warnings
        .map((warning) => warning.trim())
        .where((warning) => warning.isNotEmpty)
        .map(_aiRoleExtractionWarningText)
        .toList(growable: false);
    if (visibleWarnings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final warning in visibleWarnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              warning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.warning,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
      ],
    );
  }
}

class _AiRoleExtractionAttentionRow extends StatelessWidget {
  final ScriptAiExtractionAttentionItem item;
  final String fallbackRawResponse;

  const _AiRoleExtractionAttentionRow({
    required this.item,
    required this.fallbackRawResponse,
  });

  @override
  Widget build(BuildContext context) {
    final rawResponse = item.blocking ? fallbackRawResponse.trim() : '';
    final color = item.blocking ? StudioTokens.danger : StudioTokens.info;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: item.blocking ? 0.1 : 0.06),
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.blocking ? Icons.error_outline : Icons.info_outline,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _aiRoleExtractionAttentionText(item),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: item.blocking
                            ? StudioTokens.textPrimary
                            : StudioTokens.textSecondary,
                      ),
                ),
              ),
            ],
          ),
          if (rawResponse.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _aiRawResponseExcerpt(rawResponse),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecastPlanPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _RecastPlanPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final plan = viewModel.recastPlan;
    final hasReplacementMappings =
        viewModel.roleReplacementMappings.isNotEmpty ||
            viewModel.sceneReplacementMappings.isNotEmpty;
    final isEmpty = plan.roles.isEmpty &&
        viewModel.artistMappings.isEmpty &&
        !hasReplacementMappings;
    return _SectionPanel(
      key: const ValueKey('script-recast-plan-panel'),
      title: 'AI 换角方案',
      icon: plan.hasAiBackedPlan
          ? Icons.auto_awesome_outlined
          : Icons.account_tree_outlined,
      children: [
        if (isEmpty)
          const _EmptyHint(text: '导入剧本后会显示 AI 换角方案')
        else ...[
          _ViewModelSelector(
            viewModel: viewModel,
            select: (viewModel) => (
              viewModel.artistMappings,
              viewModel.promptBlockMappings,
              viewModel.artistChainOptions,
              viewModel.sourceVibeOptions,
              viewModel.vibeOptions,
              viewModel.selectedManualVibes,
            ),
            builder: (context, _) => _ArtistMapping(viewModel: viewModel),
          ),
          const SizedBox(height: 16),
          _ViewModelSelector(
            viewModel: viewModel,
            select: (viewModel) => (
              viewModel.roleReplacementMappings,
              viewModel.sceneReplacementMappings,
              viewModel.characterOptions,
            ),
            builder: (context, _) => _ReplacementMapping(viewModel: viewModel),
          ),
        ],
      ],
    );
  }
}

class _NeedsAttentionPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _NeedsAttentionPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final issues = viewModel.recastPlan.issues;
    return _SectionPanel(
      key: const ValueKey('script-needs-attention-panel'),
      title: '需要注意',
      icon: Icons.report_problem_outlined,
      children: [
        if (issues.isEmpty)
          const _EmptyHint(text: '暂无需要处理的问题')
        else
          for (final (index, issue) in issues.indexed)
            StudioStaggeredReveal(
              index: index,
              child: _PlanIssueRow(issue: issue),
            ),
      ],
    );
  }
}

class _PlanIssueRow extends StatelessWidget {
  final StudioScriptPlanIssue issue;

  const _PlanIssueRow({required this.issue});

  @override
  Widget build(BuildContext context) {
    final frames = issue.frameIndexes.isEmpty
        ? ''
        : ' · 帧 ${issue.frameIndexes.join(', ')}';
    final detail = issue.detail.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _planIssueIcon(issue.kind),
            size: 18,
            color: _planIssueColor(issue.kind),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_planIssueTitle(issue)}$frames',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StudioTokens.textMuted,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _planIssueTitle(StudioScriptPlanIssue issue) {
  return switch (issue.kind) {
    StudioScriptPlanIssueKind.lowConfidence => '低置信建议',
    StudioScriptPlanIssueKind.duplicateRole => '可能重复角色',
    StudioScriptPlanIssueKind.cacheConflict => '缓存冲突',
    StudioScriptPlanIssueKind.assetConflict => '素材匹配冲突',
    StudioScriptPlanIssueKind.aiBatchFailed => 'AI 批次失败',
    StudioScriptPlanIssueKind.highImpact => '影响范围较大',
  };
}

IconData _planIssueIcon(StudioScriptPlanIssueKind kind) {
  return switch (kind) {
    StudioScriptPlanIssueKind.lowConfidence => Icons.help_outline,
    StudioScriptPlanIssueKind.duplicateRole => Icons.content_copy_outlined,
    StudioScriptPlanIssueKind.cacheConflict => Icons.cached_outlined,
    StudioScriptPlanIssueKind.assetConflict => Icons.inventory_2_outlined,
    StudioScriptPlanIssueKind.aiBatchFailed => Icons.error_outline,
    StudioScriptPlanIssueKind.highImpact => Icons.priority_high_outlined,
  };
}

Color _planIssueColor(StudioScriptPlanIssueKind kind) {
  return switch (kind) {
    StudioScriptPlanIssueKind.lowConfidence => StudioTokens.warning,
    StudioScriptPlanIssueKind.duplicateRole => StudioTokens.info,
    StudioScriptPlanIssueKind.cacheConflict => StudioTokens.warning,
    StudioScriptPlanIssueKind.assetConflict => StudioTokens.warning,
    StudioScriptPlanIssueKind.aiBatchFailed => StudioTokens.danger,
    StudioScriptPlanIssueKind.highImpact => StudioTokens.primary,
  };
}

class _ReplacementMapping extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ReplacementMapping({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('script-replacement-mapping-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleReplacementSection(viewModel: viewModel),
          const SizedBox(height: 16),
          _SceneReplacementSection(viewModel: viewModel),
        ],
      ),
    );
  }
}

class _RoleReplacementSection extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _RoleReplacementSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final roles = viewModel.roleReplacementMappings;
    return _SectionPanel(
      key: const ValueKey('script-role-replacement-section'),
      title: '角色替换',
      icon: Icons.manage_accounts_outlined,
      children: [
        if (roles.isEmpty)
          const _EmptyHint(text: '暂无角色替换规则')
        else
          for (final (index, role) in roles.indexed)
            StudioStaggeredReveal(
              index: index,
              child: _RoleReplacementCard(
                item: role,
                characters: viewModel.characterOptions,
                translationCache: viewModel.translationCache,
                classificationCache: viewModel.classificationCache,
                saveClassificationCache: viewModel.saveClassificationCache,
                suppressedTagWarningKeys:
                    viewModel.suppressedPromptTagWarningKeys,
                onSuppressTagWarningForScope:
                    viewModel.suppressPromptTagWarningForCurrentScript,
                onTargetAssetDropped: (data) {
                  if (data.kind == _ScriptAssetDragKind.outfitPart) {
                    viewModel.appendRoleReplacementPendingPrompt(
                      role.sourceRoleId,
                      data.partValue ?? '',
                    );
                    return;
                  }
                  viewModel.setRoleReplacementTargetCharacter(
                    role.sourceRoleId,
                    data.characterId ?? '',
                    outfitId: data.outfitId,
                  );
                },
                onIdentityChanged: (value) =>
                    viewModel.setRoleReplacementIdentityPrompt(
                  role.sourceRoleId,
                  value,
                ),
                onRuleTargetChanged: (ruleId, value) =>
                    viewModel.setRoleReplacementRuleTarget(
                  role.sourceRoleId,
                  ruleId,
                  value,
                ),
                onRuleTargetTagsDropped: (ruleId, tags) =>
                    viewModel.appendRoleReplacementRuleTargetTags(
                  role.sourceRoleId,
                  ruleId,
                  tags,
                ),
                onRuleWeightMultiplierChanged: (ruleId, multiplier) =>
                    viewModel.scaleRoleReplacementRuleWeight(
                  role.sourceRoleId,
                  ruleId,
                  multiplier,
                ),
                onRuleSourceTagsDropped: (targetRuleId, sourceRuleId, tags) =>
                    viewModel.mergeRoleReplacementSourceTerms(
                  sourceRoleId: role.sourceRoleId,
                  sourceRuleId: sourceRuleId,
                  targetRuleId: targetRuleId,
                  tags: tags,
                ),
                onRuleSourceRulesTagsDropped:
                    (targetRuleId, sourceRuleIds, tags) =>
                        viewModel.mergeRoleReplacementSourceTermsFromRules(
                  sourceRoleId: role.sourceRoleId,
                  sourceRuleIds: sourceRuleIds,
                  targetRuleId: targetRuleId,
                  tags: tags,
                ),
                onRuleSourceTagsSplitOut: (sourceRuleId, tags) =>
                    viewModel.splitRoleReplacementSourceTerms(
                  sourceRoleId: role.sourceRoleId,
                  sourceRuleId: sourceRuleId,
                  tags: tags,
                ),
                onRuleMerged: (sourceRuleId, targetRuleId) =>
                    viewModel.mergeRoleReplacementRules(
                  sourceRoleId: role.sourceRoleId,
                  sourceRuleId: sourceRuleId,
                  targetRuleId: targetRuleId,
                ),
                onRuleDeletedChanged: (ruleId, deleted) =>
                    viewModel.setRoleReplacementRuleDeleted(
                  role.sourceRoleId,
                  ruleId,
                  deleted,
                ),
                onRuleRemoved: (ruleId) => viewModel.removeRoleReplacementRule(
                  role.sourceRoleId,
                  ruleId,
                ),
                onRuleMatchModeChanged: (ruleId, mode) =>
                    viewModel.setRoleReplacementRuleMatchMode(
                  role.sourceRoleId,
                  ruleId,
                  mode,
                ),
                onRuleTermExcludedChanged: (ruleId, termId, excluded) =>
                    viewModel.setRoleReplacementRuleTermExcluded(
                  role.sourceRoleId,
                  ruleId,
                  termId,
                  excluded,
                ),
                onRuleSelectedChanged: (ruleId, selected) =>
                    viewModel.setRoleReplacementRuleSelected(
                  role.sourceRoleId,
                  ruleId,
                  selected,
                ),
                onClearRuleSelection: () =>
                    viewModel.clearRoleReplacementRuleSelection(
                  role.sourceRoleId,
                ),
                onMergeSelectedRules: () =>
                    viewModel.mergeSelectedRoleReplacementRules(
                  role.sourceRoleId,
                ),
                onSyncIdentityToSelectedRules: () =>
                    viewModel.syncRoleReplacementTargetToSelectedRules(
                  role.sourceRoleId,
                ),
                onResetReplacementGroup: () =>
                    viewModel.resetRoleReplacementGroup(role.sourceRoleId),
              ),
            ),
      ],
    );
  }
}

class _SceneReplacementSection extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _SceneReplacementSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final groups = viewModel.sceneReplacementMappings;
    return _SectionPanel(
      key: const ValueKey('script-scene-replacement-section'),
      title: '场景替换',
      icon: Icons.landscape_outlined,
      children: [
        if (groups.isEmpty)
          const _EmptyHint(text: '暂无场景替换规则')
        else
          for (final (index, group) in groups.indexed)
            StudioStaggeredReveal(
              index: index,
              child: _SceneReplacementCard(
                item: group,
                translationCache: viewModel.translationCache,
                onRuleTargetChanged: (ruleId, value) =>
                    viewModel.setSceneReplacementRuleTarget(
                  group.id,
                  ruleId,
                  value,
                ),
                onRuleWeightMultiplierChanged: (ruleId, multiplier) =>
                    viewModel.scaleSceneReplacementRuleWeight(
                  group.id,
                  ruleId,
                  multiplier,
                ),
                onRuleSourceTagsDropped: (targetRuleId, sourceRuleId, tags) =>
                    viewModel.mergeSceneReplacementSourceTerms(
                  groupId: group.id,
                  sourceRuleId: sourceRuleId,
                  targetRuleId: targetRuleId,
                  tags: tags,
                ),
                onRuleSourceRulesTagsDropped:
                    (targetRuleId, sourceRuleIds, tags) =>
                        viewModel.mergeSceneReplacementSourceTermsFromRules(
                  groupId: group.id,
                  sourceRuleIds: sourceRuleIds,
                  targetRuleId: targetRuleId,
                  tags: tags,
                ),
                onRuleSourceTagsSplitOut: (sourceRuleId, tags) =>
                    viewModel.splitSceneReplacementSourceTerms(
                  groupId: group.id,
                  sourceRuleId: sourceRuleId,
                  tags: tags,
                ),
                onRuleMerged: (sourceRuleId, targetRuleId) =>
                    viewModel.mergeSceneReplacementRules(
                  groupId: group.id,
                  sourceRuleId: sourceRuleId,
                  targetRuleId: targetRuleId,
                ),
                onRuleDeletedChanged: (ruleId, deleted) =>
                    viewModel.setSceneReplacementRuleDeleted(
                  group.id,
                  ruleId,
                  deleted,
                ),
                onRuleRemoved: (ruleId) => viewModel.removeSceneReplacementRule(
                  group.id,
                  ruleId,
                ),
                onRuleSelectedChanged: (ruleId, selected) =>
                    viewModel.setSceneReplacementRuleSelected(
                  group.id,
                  ruleId,
                  selected,
                ),
                onClearRuleSelection: () =>
                    viewModel.clearSceneReplacementRuleSelection(group.id),
                onMergeSelectedRules: () =>
                    viewModel.mergeSelectedSceneReplacementRules(group.id),
                onResetReplacementGroup: () =>
                    viewModel.resetSceneReplacementGroup(group.id),
              ),
            ),
      ],
    );
  }
}

class _ReplacementRuleSelectionScope extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    PromptTagSelectionController selectionController,
  ) builder;
  final VoidCallback? onBlankTap;

  const _ReplacementRuleSelectionScope({
    required this.builder,
    this.onBlankTap,
  });

  @override
  State<_ReplacementRuleSelectionScope> createState() =>
      _ReplacementRuleSelectionScopeState();
}

class _ReplacementRuleSelectionScopeState
    extends State<_ReplacementRuleSelectionScope> {
  final PromptTagSelectionController _selectionController =
      PromptTagSelectionController();
  final _ReplacementRuleInteractionRegistry _interactionRegistry =
      _ReplacementRuleInteractionRegistry();
  final GlobalKey _selectionAreaKey = GlobalKey();
  final ValueNotifier<Rect?> _selectionOverlayRect = ValueNotifier<Rect?>(null);
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  Offset? _selectionAnchorGlobal;
  Rect? _lastPreviewGlobalRect;
  bool _selectionMoved = false;
  bool _selectionAdditive = false;

  @override
  void dispose() {
    _selectionOverlayRect.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _selectionAreaKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleSelectionPointerDown,
      onPointerMove: _handleSelectionPointerMove,
      onPointerUp: _handleSelectionPointerUp,
      onPointerCancel: _handleSelectionPointerCancel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _ReplacementRuleInteractionScope(
            registry: _interactionRegistry,
            child: widget.builder(context, _selectionController),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<Rect?>(
                valueListenable: _selectionOverlayRect,
                builder: (context, rect, child) {
                  if (rect == null) {
                    return const SizedBox.shrink();
                  }
                  return Stack(
                    children: [
                      Positioned(
                        key: const ValueKey('replacement-rule-marquee-overlay'),
                        left: rect.left,
                        top: rect.top,
                        width: rect.width,
                        height: rect.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: StudioTokens.primary.withAlpha(24),
                            borderRadius: StudioTokens.radiusSlot,
                            border: Border.all(color: StudioTokens.primary),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSelectionPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }
    if (_selectionController.hasItemAt(event.position) ||
        _interactionRegistry.hasRegionAt(event.position)) {
      return;
    }
    final local = _selectionLocalPosition(event.position);
    if (local == null) {
      return;
    }
    _selectionStart = local;
    _selectionCurrent = local;
    _selectionAnchorGlobal = event.position;
    _selectionMoved = false;
    _selectionAdditive = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    _lastPreviewGlobalRect = null;
    _selectionOverlayRect.value = null;
    _selectionController.beginSelectionSnapshot();
    _selectionController.clearPreview();
  }

  void _handleSelectionPointerMove(PointerMoveEvent event) {
    final start = _selectionStart;
    if (start == null) {
      return;
    }
    final local = _selectionLocalPosition(event.position);
    if (local == null) {
      return;
    }
    final moved = (local - start).distance > 4;
    if (moved == _selectionMoved && local == _selectionCurrent) {
      return;
    }
    _selectionCurrent = local;
    _selectionMoved = moved;
    _selectionOverlayRect.value = moved ? _selectionRect() : null;
    final rect = _selectionGlobalRect();
    if (moved && rect != null) {
      if (_shouldRefreshSelectionPreview(rect)) {
        _lastPreviewGlobalRect = rect;
        _selectionController.previewIntersecting(
          rect,
          additive: _selectionAdditive,
          anchorPosition: _selectionAnchorGlobal,
        );
      }
    } else {
      _lastPreviewGlobalRect = null;
      _selectionController.clearPreview();
    }
  }

  void _handleSelectionPointerUp(PointerUpEvent event) {
    final rect = _selectionGlobalRect();
    if (rect != null && _selectionMoved) {
      _selectionController.selectIntersecting(
        rect,
        additive: _selectionAdditive,
        anchorPosition: _selectionAnchorGlobal,
      );
    } else if (_selectionStart != null && !_selectionAdditive) {
      _selectionController.clear();
      widget.onBlankTap?.call();
    }
    _clearSelectionInteraction();
  }

  void _handleSelectionPointerCancel(PointerCancelEvent event) {
    _clearSelectionInteraction();
  }

  void _clearSelectionInteraction() {
    _selectionController.clearPreview();
    _selectionController.endSelectionSnapshot();
    _selectionOverlayRect.value = null;
    _selectionStart = null;
    _selectionCurrent = null;
    _selectionAnchorGlobal = null;
    _lastPreviewGlobalRect = null;
    _selectionMoved = false;
    _selectionAdditive = false;
  }

  bool _shouldRefreshSelectionPreview(Rect rect) {
    final last = _lastPreviewGlobalRect;
    if (last == null) {
      return true;
    }
    return (rect.left - last.left).abs() > 6 ||
        (rect.top - last.top).abs() > 6 ||
        (rect.right - last.right).abs() > 6 ||
        (rect.bottom - last.bottom).abs() > 6;
  }

  Offset? _selectionLocalPosition(Offset globalPosition) {
    final box = _selectionAreaKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return null;
    }
    return box.globalToLocal(globalPosition);
  }

  Rect? _selectionRect() {
    final start = _selectionStart;
    final current = _selectionCurrent;
    if (start == null || current == null) {
      return null;
    }
    return Rect.fromLTRB(
      start.dx < current.dx ? start.dx : current.dx,
      start.dy < current.dy ? start.dy : current.dy,
      start.dx > current.dx ? start.dx : current.dx,
      start.dy > current.dy ? start.dy : current.dy,
    );
  }

  Rect? _selectionGlobalRect() {
    final localRect = _selectionRect();
    final box = _selectionAreaKey.currentContext?.findRenderObject();
    if (localRect == null || box is! RenderBox) {
      return null;
    }
    final topLeft = box.localToGlobal(localRect.topLeft);
    final bottomRight = box.localToGlobal(localRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }
}

class _ReplacementRuleInteractionRegistry {
  final Set<GlobalKey> _regionKeys = <GlobalKey>{};

  void register(GlobalKey key) {
    _regionKeys.add(key);
  }

  void unregister(GlobalKey key) {
    _regionKeys.remove(key);
  }

  bool hasRegionAt(Offset globalPosition) {
    for (final key in _regionKeys.toList(growable: false).reversed) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) {
        continue;
      }
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPosition)) {
        return true;
      }
    }
    return false;
  }
}

class _ReplacementRuleInteractionScope extends InheritedWidget {
  final _ReplacementRuleInteractionRegistry registry;

  const _ReplacementRuleInteractionScope({
    required this.registry,
    required super.child,
  });

  static _ReplacementRuleInteractionRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ReplacementRuleInteractionScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(_ReplacementRuleInteractionScope oldWidget) =>
      registry != oldWidget.registry;
}

class _ReplacementRuleInteractionRegion extends StatefulWidget {
  final Widget child;

  const _ReplacementRuleInteractionRegion({required this.child});

  @override
  State<_ReplacementRuleInteractionRegion> createState() =>
      _ReplacementRuleInteractionRegionState();
}

class _ReplacementRuleInteractionRegionState
    extends State<_ReplacementRuleInteractionRegion> {
  final GlobalKey _regionKey = GlobalKey();
  _ReplacementRuleInteractionRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _ReplacementRuleInteractionScope.maybeOf(context);
    if (next == _registry) {
      return;
    }
    _registry?.unregister(_regionKey);
    _registry = next;
    _registry?.register(_regionKey);
  }

  @override
  void dispose() {
    _registry?.unregister(_regionKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _regionKey,
      child: widget.child,
    );
  }
}

class _RoleReplacementCard extends StatefulWidget {
  final StudioScriptRoleReplacementItem item;
  final List<CharacterEntry> characters;
  final TranslationCache translationCache;
  final PromptTagClassificationCache classificationCache;
  final PromptTagClassificationCacheSaver? saveClassificationCache;
  final Set<String> suppressedTagWarningKeys;
  final PromptTagWarningScopeSuppressor onSuppressTagWarningForScope;
  final ValueChanged<_ScriptAssetDragData> onTargetAssetDropped;
  final ValueChanged<String> onIdentityChanged;
  final void Function(String ruleId, String value) onRuleTargetChanged;
  final void Function(String ruleId, List<String> tags) onRuleTargetTagsDropped;
  final void Function(String ruleId, double multiplier)
      onRuleWeightMultiplierChanged;
  final void Function(
          String targetRuleId, String sourceRuleId, List<String> tags)
      onRuleSourceTagsDropped;
  final void Function(
          String targetRuleId, Set<String> sourceRuleIds, List<String> tags)
      onRuleSourceRulesTagsDropped;
  final void Function(String sourceRuleId, List<String> tags)
      onRuleSourceTagsSplitOut;
  final void Function(String sourceRuleId, String targetRuleId) onRuleMerged;
  final void Function(String ruleId, bool deleted) onRuleDeletedChanged;
  final ValueChanged<String> onRuleRemoved;
  final void Function(String ruleId, ScriptPromptReplacementMatchMode mode)
      onRuleMatchModeChanged;
  final void Function(String ruleId, String termId, bool excluded)
      onRuleTermExcludedChanged;
  final void Function(String ruleId, bool selected) onRuleSelectedChanged;
  final VoidCallback onClearRuleSelection;
  final VoidCallback onMergeSelectedRules;
  final VoidCallback onResetReplacementGroup;
  final VoidCallback onSyncIdentityToSelectedRules;

  const _RoleReplacementCard({
    required this.item,
    required this.characters,
    required this.translationCache,
    required this.classificationCache,
    required this.saveClassificationCache,
    required this.suppressedTagWarningKeys,
    required this.onSuppressTagWarningForScope,
    required this.onTargetAssetDropped,
    required this.onIdentityChanged,
    required this.onRuleTargetChanged,
    required this.onRuleTargetTagsDropped,
    required this.onRuleWeightMultiplierChanged,
    required this.onRuleSourceTagsDropped,
    required this.onRuleSourceRulesTagsDropped,
    required this.onRuleSourceTagsSplitOut,
    required this.onRuleMerged,
    required this.onRuleDeletedChanged,
    required this.onRuleRemoved,
    required this.onRuleMatchModeChanged,
    required this.onRuleTermExcludedChanged,
    required this.onRuleSelectedChanged,
    required this.onClearRuleSelection,
    required this.onMergeSelectedRules,
    required this.onSyncIdentityToSelectedRules,
    required this.onResetReplacementGroup,
  });

  @override
  State<_RoleReplacementCard> createState() => _RoleReplacementCardState();
}

class _RoleReplacementCardState extends State<_RoleReplacementCard> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final characters = widget.characters;
    final translationCache = widget.translationCache;
    final classificationCache = widget.classificationCache;
    final saveClassificationCache = widget.saveClassificationCache;
    final suppressedTagWarningKeys = widget.suppressedTagWarningKeys;
    final onSuppressTagWarningForScope = widget.onSuppressTagWarningForScope;
    final onTargetAssetDropped = widget.onTargetAssetDropped;
    final onIdentityChanged = widget.onIdentityChanged;
    final onRuleTargetChanged = widget.onRuleTargetChanged;
    final onRuleTargetTagsDropped = widget.onRuleTargetTagsDropped;
    final onRuleWeightMultiplierChanged = widget.onRuleWeightMultiplierChanged;
    final onRuleSourceTagsDropped = widget.onRuleSourceTagsDropped;
    final onRuleSourceRulesTagsDropped = widget.onRuleSourceRulesTagsDropped;
    final onRuleSourceTagsSplitOut = widget.onRuleSourceTagsSplitOut;
    final onRuleMerged = widget.onRuleMerged;
    final onRuleDeletedChanged = widget.onRuleDeletedChanged;
    final onRuleRemoved = widget.onRuleRemoved;
    final onRuleMatchModeChanged = widget.onRuleMatchModeChanged;
    final onRuleTermExcludedChanged = widget.onRuleTermExcludedChanged;
    final onRuleSelectedChanged = widget.onRuleSelectedChanged;
    final onClearRuleSelection = widget.onClearRuleSelection;
    final onMergeSelectedRules = widget.onMergeSelectedRules;
    final onResetReplacementGroup = widget.onResetReplacementGroup;
    final onSyncIdentityToSelectedRules = widget.onSyncIdentityToSelectedRules;
    final selectedCount = item.rules.where((rule) => rule.selected).length;
    final selectedCharacter =
        _characterById(characters, item.targetCharacterId);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: selectedCount == 0 ? null : onClearRuleSelection,
      child: Container(
        key: ValueKey('role-replacement-card-${item.sourceRoleId}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: StudioTokens.surface2,
          borderRadius: StudioTokens.radiusCard,
          border: StudioTokens.cardBorder,
        ),
        child: _collapsed
            ? _CollapsedRoleReplacementCardSummary(
                item: item,
                onExpanded: () {
                  setState(() {
                    _collapsed = false;
                  });
                },
              )
            : _ReplacementRuleSelectionScope(
                onBlankTap: onClearRuleSelection,
                builder: (context, selectionController) {
                  final selectionGroupId = _replacementRuleSelectionGroupId(
                    'role',
                    item.sourceRoleId,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: StudioTokens.info.withValues(alpha: 0.16),
                              borderRadius: StudioTokens.radiusPill,
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              size: 20,
                              color: StudioTokens.info,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.sourceLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '源角色：${item.sourcePreview}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: StudioTokens.textMuted,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StudioIconButton(
                            key: ValueKey(
                              'role-replacement-collapse-${item.sourceRoleId}',
                            ),
                            icon: Icons.expand_less_outlined,
                            tooltip: '收起角色替换卡片',
                            onPressed: () {
                              setState(() {
                                _collapsed = true;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _RoleReplacementIdentityEditor(
                        sourceRoleId: item.sourceRoleId,
                        value: item.targetIdentityPrompt,
                        characterName: selectedCharacter?.name,
                        selectionController: selectionController,
                        selectionGroupId: selectionGroupId,
                        onChanged: onIdentityChanged,
                        onTargetAssetDropped: onTargetAssetDropped,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '替换规则',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey(
                              'role-replacement-reset-${item.sourceRoleId}',
                            ),
                            icon: const Icon(Icons.restart_alt_outlined,
                                size: 16),
                            label: const Text('重置本组'),
                            onPressed: onResetReplacementGroup,
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            key: ValueKey(
                              'role-replacement-sync-identity-${item.sourceRoleId}',
                            ),
                            icon: const Icon(Icons.drive_file_move_outline,
                                size: 16),
                            label: const Text('同步到选中规则'),
                            onPressed: selectedCount == 0
                                ? null
                                : onSyncIdentityToSelectedRules,
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            key: ValueKey(
                              'role-replacement-merge-selected-${item.sourceRoleId}',
                            ),
                            icon:
                                const Icon(Icons.call_merge_outlined, size: 16),
                            label: Text('合并选中($selectedCount)'),
                            onPressed:
                                selectedCount < 2 ? null : onMergeSelectedRules,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ReplacementRuleGrid(
                        scope: 'role',
                        ownerId: item.sourceRoleId,
                        selectionController: selectionController,
                        selectionGroupId: selectionGroupId,
                        rules: item.rules,
                        translationCache: translationCache,
                        classificationCache: classificationCache,
                        saveClassificationCache: saveClassificationCache,
                        suppressedTagWarningKeys: suppressedTagWarningKeys,
                        onSuppressTagWarningForScope:
                            onSuppressTagWarningForScope,
                        acceptedPromptTagSourceFieldIds: {
                          _replacementRoleIdentityFieldId(item.sourceRoleId),
                        },
                        onRuleTargetChanged: onRuleTargetChanged,
                        onRuleTargetTagsDropped: onRuleTargetTagsDropped,
                        onRuleWeightMultiplierChanged:
                            onRuleWeightMultiplierChanged,
                        onRuleSourceTagsDropped: onRuleSourceTagsDropped,
                        onRuleSourceRulesTagsDropped:
                            onRuleSourceRulesTagsDropped,
                        onRuleSourceTagsSplitOut: onRuleSourceTagsSplitOut,
                        onRuleMerged: onRuleMerged,
                        onRuleDeletedChanged: onRuleDeletedChanged,
                        onRuleRemoved: onRuleRemoved,
                        onRuleMatchModeChanged: onRuleMatchModeChanged,
                        onRuleTermExcludedChanged: onRuleTermExcludedChanged,
                        onRuleSelectedChanged: onRuleSelectedChanged,
                        onMergeSelectedRules: onMergeSelectedRules,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _CollapsedRoleReplacementCardSummary extends StatelessWidget {
  final StudioScriptRoleReplacementItem item;
  final VoidCallback onExpanded;

  const _CollapsedRoleReplacementCardSummary({
    required this.item,
    required this.onExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = item.rules.length;
    final mappedCount = item.rules.where(_replacementRuleHasResult).length;
    return Row(
      key: ValueKey(
        'role-replacement-collapsed-summary-${item.sourceRoleId}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: StudioTokens.info.withValues(alpha: 0.16),
            borderRadius: StudioTokens.radiusPill,
          ),
          child: const Icon(
            Icons.person_outline,
            size: 20,
            color: StudioTokens.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '源角色：${item.sourcePreview}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StudioChip(label: '$totalCount 个'),
                  StudioChip(label: '$mappedCount 个已映射'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StudioIconButton(
          key: ValueKey('role-replacement-expand-${item.sourceRoleId}'),
          icon: Icons.expand_more_outlined,
          tooltip: '展开角色替换卡片',
          onPressed: onExpanded,
        ),
      ],
    );
  }
}

class _RoleReplacementIdentityEditor extends StatelessWidget {
  final String sourceRoleId;
  final String value;
  final String? characterName;
  final PromptTagSelectionController selectionController;
  final String selectionGroupId;
  final ValueChanged<String> onChanged;
  final ValueChanged<_ScriptAssetDragData> onTargetAssetDropped;

  const _RoleReplacementIdentityEditor({
    required this.sourceRoleId,
    required this.value,
    required this.characterName,
    required this.selectionController,
    required this.selectionGroupId,
    required this.onChanged,
    required this.onTargetAssetDropped,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_ScriptAssetDragData>(
      key: ValueKey('role-replacement-identity-drop-$sourceRoleId'),
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data.kind == _ScriptAssetDragKind.outfitPart) {
          return data.partValue?.trim().isNotEmpty ?? false;
        }
        return data.characterId != null &&
            (data.kind == _ScriptAssetDragKind.character ||
                data.kind == _ScriptAssetDragKind.outfit);
      },
      onAcceptWithDetails: (details) {
        onTargetAssetDropped(details.data);
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active
                ? StudioTokens.primary.withAlpha(18)
                : StudioTokens.surface1,
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: active ? StudioTokens.primary : StudioTokens.cardOutline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      characterName == null ? '待选区' : '待选区：$characterName',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: StudioTokens.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Icon(
                    active
                        ? Icons.download_done_outlined
                        : Icons.badge_outlined,
                    size: 16,
                    color: active
                        ? StudioTokens.primary
                        : StudioTokens.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              KeyedSubtree(
                key: ValueKey('role-replacement-identity-$sourceRoleId'),
                child: PromptTagEditor(
                  value: value,
                  dense: true,
                  selectionController: selectionController,
                  selectionFieldId:
                      _replacementRoleIdentityFieldId(sourceRoleId),
                  selectionGroupId: selectionGroupId,
                  emptyText: '拖入角色/套装，或手动添加待选词',
                  showSelectionToolbar: false,
                  preferTranslatedLabels: true,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SceneReplacementCard extends StatelessWidget {
  final StudioScriptSceneReplacementItem item;
  final TranslationCache translationCache;
  final void Function(String ruleId, String value) onRuleTargetChanged;
  final void Function(String ruleId, double multiplier)
      onRuleWeightMultiplierChanged;
  final void Function(
          String targetRuleId, String sourceRuleId, List<String> tags)
      onRuleSourceTagsDropped;
  final void Function(
          String targetRuleId, Set<String> sourceRuleIds, List<String> tags)
      onRuleSourceRulesTagsDropped;
  final void Function(String sourceRuleId, List<String> tags)
      onRuleSourceTagsSplitOut;
  final void Function(String sourceRuleId, String targetRuleId) onRuleMerged;
  final void Function(String ruleId, bool deleted) onRuleDeletedChanged;
  final ValueChanged<String> onRuleRemoved;
  final void Function(String ruleId, bool selected) onRuleSelectedChanged;
  final VoidCallback onClearRuleSelection;
  final VoidCallback onMergeSelectedRules;
  final VoidCallback onResetReplacementGroup;

  const _SceneReplacementCard({
    required this.item,
    required this.translationCache,
    required this.onRuleTargetChanged,
    required this.onRuleWeightMultiplierChanged,
    required this.onRuleSourceTagsDropped,
    required this.onRuleSourceRulesTagsDropped,
    required this.onRuleSourceTagsSplitOut,
    required this.onRuleMerged,
    required this.onRuleDeletedChanged,
    required this.onRuleRemoved,
    required this.onRuleSelectedChanged,
    required this.onClearRuleSelection,
    required this.onMergeSelectedRules,
    required this.onResetReplacementGroup,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCount = item.rules.where((rule) => rule.selected).length;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: selectedCount == 0 ? null : onClearRuleSelection,
      child: Container(
        key: ValueKey('scene-replacement-card-${item.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: StudioTokens.surface2,
          borderRadius: StudioTokens.radiusCard,
          border: StudioTokens.cardBorder,
        ),
        child: _ReplacementRuleSelectionScope(
          onBlankTap: onClearRuleSelection,
          builder: (context, selectionController) {
            final selectionGroupId = _replacementRuleSelectionGroupId(
              'scene',
              item.id,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: ValueKey('scene-replacement-reset-${item.id}'),
                      icon: const Icon(Icons.restart_alt_outlined, size: 16),
                      label: const Text('重置本组'),
                      onPressed: onResetReplacementGroup,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: ValueKey(
                          'scene-replacement-merge-selected-${item.id}'),
                      icon: const Icon(Icons.call_merge_outlined, size: 16),
                      label: Text('合并选中($selectedCount)'),
                      onPressed:
                          selectedCount < 2 ? null : onMergeSelectedRules,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ReplacementRuleGrid(
                  scope: 'scene',
                  ownerId: item.id,
                  selectionController: selectionController,
                  selectionGroupId: selectionGroupId,
                  rules: item.rules,
                  translationCache: translationCache,
                  onRuleTargetChanged: onRuleTargetChanged,
                  onRuleWeightMultiplierChanged: onRuleWeightMultiplierChanged,
                  onRuleSourceTagsDropped: onRuleSourceTagsDropped,
                  onRuleSourceRulesTagsDropped: onRuleSourceRulesTagsDropped,
                  onRuleSourceTagsSplitOut: onRuleSourceTagsSplitOut,
                  onRuleMerged: onRuleMerged,
                  onRuleDeletedChanged: onRuleDeletedChanged,
                  onRuleRemoved: onRuleRemoved,
                  onRuleSelectedChanged: onRuleSelectedChanged,
                  onMergeSelectedRules: onMergeSelectedRules,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReplacementRuleGrid extends StatelessWidget {
  final String scope;
  final String ownerId;
  final PromptTagSelectionController selectionController;
  final String selectionGroupId;
  final List<StudioScriptReplacementRuleItem> rules;
  final TranslationCache translationCache;
  final PromptTagClassificationCache? classificationCache;
  final PromptTagClassificationCacheSaver? saveClassificationCache;
  final Set<String> suppressedTagWarningKeys;
  final PromptTagWarningScopeSuppressor? onSuppressTagWarningForScope;
  final Set<String> acceptedPromptTagSourceFieldIds;
  final void Function(String ruleId, String value) onRuleTargetChanged;
  final void Function(String ruleId, List<String> tags)?
      onRuleTargetTagsDropped;
  final void Function(String ruleId, double multiplier)
      onRuleWeightMultiplierChanged;
  final void Function(
          String targetRuleId, String sourceRuleId, List<String> tags)?
      onRuleSourceTagsDropped;
  final void Function(
          String targetRuleId, Set<String> sourceRuleIds, List<String> tags)?
      onRuleSourceRulesTagsDropped;
  final void Function(String sourceRuleId, List<String> tags)
      onRuleSourceTagsSplitOut;
  final void Function(String sourceRuleId, String targetRuleId) onRuleMerged;
  final void Function(String ruleId, bool deleted) onRuleDeletedChanged;
  final ValueChanged<String> onRuleRemoved;
  final void Function(String ruleId, ScriptPromptReplacementMatchMode mode)?
      onRuleMatchModeChanged;
  final void Function(String ruleId, String termId, bool excluded)?
      onRuleTermExcludedChanged;
  final void Function(String ruleId, bool selected) onRuleSelectedChanged;
  final VoidCallback onMergeSelectedRules;

  const _ReplacementRuleGrid({
    required this.scope,
    required this.ownerId,
    required this.selectionController,
    required this.selectionGroupId,
    required this.rules,
    required this.translationCache,
    this.classificationCache,
    this.saveClassificationCache,
    this.suppressedTagWarningKeys = const {},
    this.onSuppressTagWarningForScope,
    this.acceptedPromptTagSourceFieldIds = const {},
    required this.onRuleTargetChanged,
    this.onRuleTargetTagsDropped,
    required this.onRuleWeightMultiplierChanged,
    this.onRuleSourceTagsDropped,
    this.onRuleSourceRulesTagsDropped,
    required this.onRuleSourceTagsSplitOut,
    required this.onRuleMerged,
    required this.onRuleDeletedChanged,
    required this.onRuleRemoved,
    this.onRuleMatchModeChanged,
    this.onRuleTermExcludedChanged,
    required this.onRuleSelectedChanged,
    required this.onMergeSelectedRules,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _replacementRuleGroups(scope, rules);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          _ReplacementRuleGroupHeader(
            label: group.label,
            totalCount: group.rules.length,
            mappedCount: group.rules.where(_replacementRuleHasResult).length,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rule in group.rules)
                _ReplacementRuleRow(
                  key: ValueKey('replacement-rule-$scope-$ownerId-${rule.id}'),
                  scope: scope,
                  ownerId: ownerId,
                  selectionController: selectionController,
                  selectionGroupId: selectionGroupId,
                  rule: rule,
                  translationCache: translationCache,
                  classificationCache: classificationCache,
                  saveClassificationCache: saveClassificationCache,
                  suppressedTagWarningKeys: suppressedTagWarningKeys,
                  onSuppressTagWarningForScope: onSuppressTagWarningForScope,
                  acceptedPromptTagSourceFieldIds:
                      acceptedPromptTagSourceFieldIds,
                  onTargetChanged: (value) =>
                      onRuleTargetChanged(rule.id, value),
                  onPromptTagsDropped: onRuleTargetTagsDropped == null
                      ? null
                      : (tags) => onRuleTargetTagsDropped!(rule.id, tags),
                  onWeightMultiplierChanged: (multiplier) =>
                      onRuleWeightMultiplierChanged(rule.id, multiplier),
                  onSourceTagsDropped: onRuleSourceTagsDropped == null
                      ? null
                      : (sourceRuleId, tags) => onRuleSourceTagsDropped!(
                            rule.id,
                            sourceRuleId,
                            tags,
                          ),
                  onSourceRulesTagsDropped: onRuleSourceRulesTagsDropped == null
                      ? null
                      : (sourceRuleIds, tags) => onRuleSourceRulesTagsDropped!(
                            rule.id,
                            sourceRuleIds,
                            tags,
                          ),
                  onSourceTagsDraggedOut: (tags) =>
                      onRuleSourceTagsSplitOut(rule.id, tags),
                  onDeletedChanged: (deleted) =>
                      onRuleDeletedChanged(rule.id, deleted),
                  onRemoved: () => onRuleRemoved(rule.id),
                  onMatchModeChanged: onRuleMatchModeChanged == null
                      ? null
                      : (mode) => onRuleMatchModeChanged!(rule.id, mode),
                  onTermExcludedChanged: onRuleTermExcludedChanged == null
                      ? null
                      : (termId, excluded) => onRuleTermExcludedChanged!(
                            rule.id,
                            termId,
                            excluded,
                          ),
                  onSelectedChanged: (selected) =>
                      onRuleSelectedChanged(rule.id, selected),
                  onMergeWithRule: (sourceRuleId) {
                    if (sourceRuleId == rule.id) {
                      return;
                    }
                    onRuleMerged(sourceRuleId, rule.id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _ReplacementRuleSplitDropTarget(
          scope: scope,
          ownerId: ownerId,
          onSourceTagsSplitOut: onRuleSourceTagsSplitOut,
        ),
      ],
    );
  }
}

class _ReplacementRuleGroupHeader extends StatelessWidget {
  final String label;
  final int totalCount;
  final int mappedCount;

  const _ReplacementRuleGroupHeader({
    required this.label,
    required this.totalCount,
    required this.mappedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(width: 8),
        Text(
          '$totalCount 个 · $mappedCount 个已映射',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: StudioTokens.textMuted,
              ),
        ),
      ],
    );
  }
}

class _ReplacementRuleSplitDropTarget extends StatelessWidget {
  final String scope;
  final String ownerId;
  final void Function(String sourceRuleId, List<String> tags)
      onSourceTagsSplitOut;

  const _ReplacementRuleSplitDropTarget({
    required this.scope,
    required this.ownerId,
    required this.onSourceTagsSplitOut,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<PromptTagDragData>(
      key: ValueKey('replacement-rule-split-drop-$scope-$ownerId'),
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: (details) =>
          _replacementRuleIdForDraggedSourceTags(
            details.data,
            scope: scope,
            ownerId: ownerId,
          ) !=
          null,
      onAcceptWithDetails: (details) {
        final sourceRuleId = _replacementRuleIdForDraggedSourceTags(
          details.data,
          scope: scope,
          ownerId: ownerId,
        );
        if (sourceRuleId == null) {
          return;
        }
        onSourceTagsSplitOut(sourceRuleId, details.data.tags);
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 96,
            height: 34,
            decoration: BoxDecoration(
              color: active
                  ? StudioTokens.primary.withAlpha(18)
                  : StudioTokens.surface1,
              borderRadius: StudioTokens.radiusSlot,
              border: Border.all(
                color: active ? StudioTokens.primary : StudioTokens.border,
              ),
            ),
            child: Icon(
              Icons.open_in_new_outlined,
              size: 16,
              color: active ? StudioTokens.primary : StudioTokens.textMuted,
            ),
          ),
        );
      },
    );
  }
}

class _ReplacementRuleRow extends StatefulWidget {
  final String scope;
  final String ownerId;
  final PromptTagSelectionController selectionController;
  final String selectionGroupId;
  final StudioScriptReplacementRuleItem rule;
  final TranslationCache translationCache;
  final PromptTagClassificationCache? classificationCache;
  final PromptTagClassificationCacheSaver? saveClassificationCache;
  final Set<String> suppressedTagWarningKeys;
  final PromptTagWarningScopeSuppressor? onSuppressTagWarningForScope;
  final Set<String> acceptedPromptTagSourceFieldIds;
  final ValueChanged<String> onTargetChanged;
  final ValueChanged<List<String>>? onPromptTagsDropped;
  final ValueChanged<double> onWeightMultiplierChanged;
  final void Function(String sourceRuleId, List<String> tags)?
      onSourceTagsDropped;
  final void Function(Set<String> sourceRuleIds, List<String> tags)?
      onSourceRulesTagsDropped;
  final ValueChanged<List<String>>? onSourceTagsDraggedOut;
  final ValueChanged<bool> onDeletedChanged;
  final VoidCallback onRemoved;
  final ValueChanged<ScriptPromptReplacementMatchMode>? onMatchModeChanged;
  final void Function(String termId, bool excluded)? onTermExcludedChanged;
  final ValueChanged<bool> onSelectedChanged;
  final ValueChanged<String> onMergeWithRule;

  const _ReplacementRuleRow({
    super.key,
    required this.scope,
    required this.ownerId,
    required this.selectionController,
    required this.selectionGroupId,
    required this.rule,
    required this.translationCache,
    this.classificationCache,
    this.saveClassificationCache,
    this.suppressedTagWarningKeys = const {},
    this.onSuppressTagWarningForScope,
    this.acceptedPromptTagSourceFieldIds = const {},
    required this.onTargetChanged,
    this.onPromptTagsDropped,
    required this.onWeightMultiplierChanged,
    this.onSourceTagsDropped,
    this.onSourceRulesTagsDropped,
    this.onSourceTagsDraggedOut,
    required this.onDeletedChanged,
    required this.onRemoved,
    this.onMatchModeChanged,
    this.onTermExcludedChanged,
    required this.onSelectedChanged,
    required this.onMergeWithRule,
  });

  @override
  State<_ReplacementRuleRow> createState() => _ReplacementRuleRowState();
}

class _ReplacementRuleRowState extends State<_ReplacementRuleRow> {
  final GlobalKey _cardKey = GlobalKey();
  bool _editingTarget = false;
  bool _draggingRule = false;

  @override
  void didUpdateWidget(covariant _ReplacementRuleRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rule.id != oldWidget.rule.id ||
        widget.rule.targetPrompt.trim().isNotEmpty ||
        widget.rule.action == ScriptPromptReplacementAction.delete) {
      _editingTarget = false;
    }
  }

  bool _canAcceptPromptTags(PromptTagDragData data) {
    if (widget.onPromptTagsDropped == null ||
        widget.acceptedPromptTagSourceFieldIds.isEmpty ||
        data.tags.every((tag) => tag.trim().isEmpty)) {
      return false;
    }
    if (data.sourceFieldIds.length != 1) {
      return false;
    }
    final fieldId = data.sourceFieldIds.single;
    if (widget.acceptedPromptTagSourceFieldIds.contains(fieldId)) {
      return true;
    }
    final sourceTargetRuleId = _replacementRuleIdForDraggedTargetTags(
      data,
      scope: widget.scope,
      ownerId: widget.ownerId,
    );
    return sourceTargetRuleId != null && sourceTargetRuleId != widget.rule.id;
  }

  Set<String> _sourceRuleIdsForDraggedTags(PromptTagDragData data) {
    final sourceRuleIds = _replacementRuleIdsForDraggedSourceTags(
      data,
      scope: widget.scope,
      ownerId: widget.ownerId,
    );
    return {
      for (final ruleId in sourceRuleIds)
        if (ruleId != widget.rule.id) ruleId,
    };
  }

  bool _canAcceptSourceTagsForMerge(PromptTagDragData data) {
    return (widget.onSourceTagsDropped != null ||
            widget.onSourceRulesTagsDropped != null) &&
        _sourceRuleIdsForDraggedTags(data).isNotEmpty;
  }

  bool _isOutsideCurrentCard(Offset globalOffset) {
    final renderObject = _cardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return !rect.inflate(8).contains(globalOffset);
  }

  void _handleSourceTagDragEnd(
    PromptTagDragData data,
    DraggableDetails details,
  ) {
    if (details.wasAccepted ||
        widget.onSourceTagsDraggedOut == null ||
        data.tags.every((tag) => tag.trim().isEmpty)) {
      return;
    }
    final sourceRuleId = _replacementRuleIdForDraggedSourceTags(
      data,
      scope: widget.scope,
      ownerId: widget.ownerId,
    );
    if (sourceRuleId != widget.rule.id ||
        !_isOutsideCurrentCard(details.offset)) {
      return;
    }
    widget.onSourceTagsDraggedOut!(data.tags);
  }

  Future<void> _editWeightMultiplier(BuildContext context) async {
    final controller = TextEditingController(text: '1.2');
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('replacement-rule-weight-multiplier-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: const Text('按倍率调整权重'),
          content: SizedBox(
            width: 320,
            child: TextField(
              key: const ValueKey('replacement-rule-weight-multiplier-field'),
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              decoration: const InputDecoration(
                labelText: '倍率',
                hintText: '1.2',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(context).pop(controller.text),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('replacement-rule-weight-multiplier-save'),
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('应用'),
            ),
          ],
        );
      },
    );
    if (!mounted || value == null) {
      return;
    }
    final multiplier = double.tryParse(value.trim());
    if (multiplier == null || !multiplier.isFinite || multiplier <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('请输入大于 0 的数字倍率')),
        );
      }
      return;
    }
    widget.onWeightMultiplierChanged(multiplier);
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.rule;
    final deleted = rule.action == ScriptPromptReplacementAction.delete;
    final hasTarget = rule.targetPrompt.trim().isNotEmpty;
    final hasResult = hasTarget;
    final sourcePrompt = _replacementAllTermsPrompt(rule);
    final ruleKey = '${widget.scope}-${widget.ownerId}-${rule.id}';
    final frameLabel = _replacementRuleFrameLabel(rule);
    final showingTarget = hasResult || _editingTarget;
    final sourcePromptWidth = _replacementSourcePromptWidth(
      rule,
      hasFrameLabel: frameLabel.isNotEmpty,
      showingTarget: showingTarget,
    );
    final targetPromptWidth = showingTarget
        ? _replacementTargetPromptWidth(
            rule.targetPrompt,
            editing: _editingTarget,
          )
        : 0.0;
    final ruleMaxWidth = _replacementRuleCardMaxWidth(
      sourcePromptWidth: sourcePromptWidth,
      targetPromptWidth: targetPromptWidth,
      showingTarget: showingTarget,
    );
    final borderColor = deleted
        ? StudioTokens.danger
        : rule.selected
            ? StudioTokens.primary
            : hasTarget
                ? StudioTokens.active
                : StudioTokens.borderStrong;
    final backgroundColor = rule.selected
        ? StudioTokens.primary.withAlpha(14)
        : deleted
            ? StudioTokens.danger.withAlpha(10)
            : StudioTokens.surface2;

    Widget sourcePromptArea() {
      return Flexible(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelectedChanged(!rule.selected),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: sourcePromptWidth,
              ),
              child: SizedBox(
                width: sourcePromptWidth,
                child: PromptTagDisplay(
                  key: ValueKey(
                    'replacement-rule-source-$ruleKey',
                  ),
                  text: sourcePrompt,
                  defaultTranslated: true,
                  dense: true,
                  initialLayoutMode: PromptTagLayoutMode.sourceOrder,
                  respectInitialLayoutMode: true,
                  sourceOrderCollapsedTagMaxWidth:
                      _replacementRuleCollapsedTagMaxWidth,
                  sourceOrderHoveredTagMaxWidth:
                      _replacementRuleCollapsedTagMaxWidth,
                  enableTagActions: true,
                  translationCache: widget.translationCache,
                  classificationCache: widget.classificationCache,
                  saveClassificationCache: widget.saveClassificationCache,
                  suppressedTagWarningKeys: widget.suppressedTagWarningKeys,
                  onSuppressTagWarningForScope:
                      widget.onSuppressTagWarningForScope,
                  selectionController: widget.selectionController,
                  selectionFieldId: _replacementRuleSourceFieldId(
                    widget.scope,
                    widget.ownerId,
                    rule.id,
                  ),
                  selectionGroupId: widget.selectionGroupId,
                  showSelectionToolbar: false,
                  onTagDragEnd: _handleSourceTagDragEnd,
                  emptyText: '暂无来源词',
                  onTagTap: widget.onTermExcludedChanged == null
                      ? null
                      : (tag) {
                          final termId = _replacementTermIdForTag(rule, tag);
                          if (termId == null) {
                            return;
                          }
                          widget.onTermExcludedChanged!(
                            termId,
                            !rule.excludedTermIds.contains(termId),
                          );
                        },
                  diffStateForTag: (tag) {
                    final termId = _replacementTermIdForTag(
                      rule,
                      tag,
                    );
                    if (deleted ||
                        (termId != null &&
                            rule.excludedTermIds.contains(termId))) {
                      return PromptTagChipDiffState.removed;
                    }
                    return PromptTagChipDiffState.unchanged;
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    List<Widget> frameLabelWidgets() {
      if (frameLabel.isEmpty) {
        return const [];
      }
      return [
        const SizedBox(width: 5),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _ReplacementFrameIcon(
            label: frameLabel,
          ),
        ),
      ];
    }

    Widget targetArrow() {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '→',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.primary,
                fontWeight: FontWeight.w900,
              ),
        ),
      );
    }

    Widget targetPromptArea() {
      return Flexible(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: targetPromptWidth,
          ),
          child: _ReplacementTargetPromptBox(
            ruleKey: ruleKey,
            width: targetPromptWidth,
            weightMultiplier: null,
            child: _editingTarget
                ? PromptTagEditor(
                    key: ValueKey(
                      'replacement-rule-target-input-$ruleKey',
                    ),
                    value: rule.targetPrompt,
                    dense: true,
                    emptyText: '',
                    showControls: false,
                    showSelectionToolbar: false,
                    preferTranslatedLabels: true,
                    copyDraggedTagsWithAlt: true,
                    enableKeyboardPaste: true,
                    selectionController: widget.selectionController,
                    selectionFieldId: _replacementRuleTargetFieldId(
                      widget.scope,
                      widget.ownerId,
                      rule.id,
                    ),
                    selectionGroupId: widget.selectionGroupId,
                    onChanged: widget.onTargetChanged,
                  )
                : PromptTagDisplay(
                    key: ValueKey(
                      'replacement-rule-target-$ruleKey',
                    ),
                    text: rule.targetPrompt,
                    defaultTranslated: true,
                    dense: true,
                    initialLayoutMode: PromptTagLayoutMode.sourceOrder,
                    respectInitialLayoutMode: true,
                    sourceOrderCollapsedTagMaxWidth:
                        _replacementRuleCollapsedTagMaxWidth,
                    sourceOrderHoveredTagMaxWidth:
                        _replacementRuleCollapsedTagMaxWidth,
                    enableTagActions: true,
                    translationCache: widget.translationCache,
                    classificationCache: widget.classificationCache,
                    saveClassificationCache: widget.saveClassificationCache,
                    suppressedTagWarningKeys: widget.suppressedTagWarningKeys,
                    onSuppressTagWarningForScope:
                        widget.onSuppressTagWarningForScope,
                    selectionController: widget.selectionController,
                    selectionFieldId: _replacementRuleTargetFieldId(
                      widget.scope,
                      widget.ownerId,
                      rule.id,
                    ),
                    selectionGroupId: widget.selectionGroupId,
                    showSelectionToolbar: false,
                    copyDraggedTagsWithAlt: true,
                    enableKeyboardPaste: true,
                    onChanged: widget.onTargetChanged,
                  ),
          ),
        ),
      );
    }

    Widget promptFlow() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sourcePromptArea(),
          ...frameLabelWidgets(),
          if (showingTarget) ...[
            const SizedBox(width: 8),
            targetArrow(),
            const SizedBox(width: 8),
            targetPromptArea(),
          ],
        ],
      );
    }

    return _ReplacementRuleInteractionRegion(
      child: DragTarget<_ReplacementRuleDragData>(
        onWillAcceptWithDetails: (details) =>
            details.data.scope == widget.scope &&
            details.data.ownerId == widget.ownerId &&
            details.data.ruleId != rule.id,
        onAcceptWithDetails: (details) => widget.onMergeWithRule(
          details.data.ruleId,
        ),
        builder: (context, candidateData, rejectedData) {
          final mergeTargetActive = candidateData.isNotEmpty;
          final dragLabel = _replacementTermsPrompt(rule);
          final dragData = _ReplacementRuleDragData(
            scope: widget.scope,
            ownerId: widget.ownerId,
            ruleId: rule.id,
            label: dragLabel,
          );
          return DragTarget<PromptTagDragData>(
            key: ValueKey('replacement-rule-prompt-drop-$ruleKey'),
            hitTestBehavior: HitTestBehavior.translucent,
            onWillAcceptWithDetails: (details) =>
                _canAcceptPromptTags(details.data) ||
                _canAcceptSourceTagsForMerge(details.data),
            onAcceptWithDetails: (details) {
              final data = details.data;
              final sourceRuleIds = _sourceRuleIdsForDraggedTags(data);
              if (sourceRuleIds.isNotEmpty) {
                if (sourceRuleIds.length == 1 &&
                    widget.onSourceTagsDropped != null) {
                  widget.onSourceTagsDropped!(sourceRuleIds.single, data.tags);
                  return;
                }
                widget.onSourceRulesTagsDropped?.call(
                  sourceRuleIds,
                  data.tags,
                );
                return;
              }
              widget.onPromptTagsDropped?.call(data.tags);
              if (!data.copyOnly) {
                data.removeFromSource?.call(data.indexes);
              }
            },
            builder: (context, promptTagCandidateData, rejectedPromptTagData) {
              final promptTagTargetActive = promptTagCandidateData.isNotEmpty;
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 90),
                opacity: _draggingRule ? 0.32 : 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ruleMaxWidth,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: rule.selected
                        ? () => widget.onSelectedChanged(false)
                        : null,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          key: _cardKey,
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.fromLTRB(8, 7, 5, 7),
                          decoration: BoxDecoration(
                            color: promptTagTargetActive
                                ? StudioTokens.primary.withAlpha(18)
                                : backgroundColor,
                            borderRadius: StudioTokens.radiusSlot,
                            border: Border.all(
                              color: mergeTargetActive || promptTagTargetActive
                                  ? StudioTokens.primary
                                  : borderColor,
                            ),
                            boxShadow: rule.selected
                                ? [
                                    BoxShadow(
                                      color: StudioTokens.primary.withAlpha(38),
                                      blurRadius: 0,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : const [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ReplacementRuleDragHandle(
                                key: ValueKey(
                                  'replacement-rule-drag-handle-$ruleKey',
                                ),
                                data: dragData,
                                label: dragLabel,
                                ruleKey: ruleKey,
                                sourcePrompt: sourcePrompt,
                                targetPrompt: rule.targetPrompt,
                                deleted: deleted,
                                onDragStarted: () {
                                  setState(() {
                                    _draggingRule = true;
                                  });
                                },
                                onDragEnded: () {
                                  if (!mounted) {
                                    return;
                                  }
                                  setState(() {
                                    _draggingRule = false;
                                  });
                                },
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    promptFlow(),
                                    if (widget.onMatchModeChanged != null ||
                                        !deleted) ...[
                                      const SizedBox(height: 5),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          if (widget.onMatchModeChanged != null)
                                            _ReplacementMatchModeSelector(
                                              ruleKey: ruleKey,
                                              value: rule.matchMode,
                                              onChanged:
                                                  widget.onMatchModeChanged!,
                                            ),
                                          if (!deleted)
                                            _ReplacementRuleActionButton(
                                              key: ValueKey(
                                                'replacement-rule-scale-weight-$ruleKey',
                                              ),
                                              tooltip: '按倍率调整整块权重',
                                              icon:
                                                  Icons.monitor_weight_outlined,
                                              color: StudioTokens.primary,
                                              onPressed: () => unawaited(
                                                _editWeightMultiplier(context),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ReplacementRuleActionButton(
                                    key: ValueKey(
                                      'replacement-rule-remove-$ruleKey',
                                    ),
                                    tooltip: '移除规则卡片',
                                    icon: Icons.delete_outline,
                                    color: StudioTokens.danger,
                                    onPressed: widget.onRemoved,
                                  ),
                                  const SizedBox(height: 8),
                                  _ReplacementRuleActionButton(
                                    tooltip: deleted ? '恢复此规则' : '删除此规则',
                                    icon: deleted
                                        ? Icons.undo_outlined
                                        : Icons.close,
                                    color: deleted
                                        ? StudioTokens.warning
                                        : StudioTokens.textMuted,
                                    onPressed: () =>
                                        widget.onDeletedChanged(!deleted),
                                  ),
                                  if (!deleted) ...[
                                    const SizedBox(height: 8),
                                    _ReplacementRuleActionButton(
                                      tooltip: '添加目标词',
                                      icon: Icons.add,
                                      color: StudioTokens.primary,
                                      onPressed: () {
                                        setState(() {
                                          _editingTarget = true;
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (rule.targetWeightMultiplier != null &&
                            ((rule.targetWeightMultiplier ?? 1.0) - 1.0)
                                    .abs() >=
                                0.000001)
                          Positioned(
                            right: -5,
                            top: -8,
                            child: _ReplacementWeightBadge(
                              weight: rule.targetWeightMultiplier!,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReplacementRuleDragData {
  final String scope;
  final String ownerId;
  final String ruleId;
  final String label;

  const _ReplacementRuleDragData({
    required this.scope,
    required this.ownerId,
    required this.ruleId,
    required this.label,
  });
}

class _ReplacementRuleDragFeedback extends StatelessWidget {
  final String ruleKey;
  final String label;
  final String sourcePrompt;
  final String targetPrompt;
  final bool deleted;

  const _ReplacementRuleDragFeedback({
    required this.ruleKey,
    required this.label,
    required this.sourcePrompt,
    required this.targetPrompt,
    required this.deleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('replacement-rule-card-feedback-$ruleKey'),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(
          color: deleted ? StudioTokens.danger : StudioTokens.primary,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 46,
            decoration: BoxDecoration(
              color: StudioTokens.surface1,
              borderRadius: StudioTokens.radiusBadge,
              border: Border.all(color: StudioTokens.border),
            ),
            child: const Icon(
              Icons.drag_indicator,
              size: 16,
              color: StudioTokens.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sourcePrompt.isEmpty ? label : sourcePrompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                if (targetPrompt.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_forward,
                        size: 13,
                        color: StudioTokens.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          targetPrompt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: StudioTokens.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplacementRuleDragHandle extends StatelessWidget {
  final _ReplacementRuleDragData data;
  final String label;
  final String ruleKey;
  final String sourcePrompt;
  final String targetPrompt;
  final bool deleted;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  const _ReplacementRuleDragHandle({
    super.key,
    required this.data,
    required this.label,
    required this.ruleKey,
    required this.sourcePrompt,
    required this.targetPrompt,
    required this.deleted,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  @override
  Widget build(BuildContext context) {
    final handle = Tooltip(
      message: '拖动合并整块规则',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          width: 22,
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(
            color: StudioTokens.surface1,
            borderRadius: StudioTokens.radiusBadge,
            border: Border.all(color: StudioTokens.border),
          ),
          child: Center(
            child: Icon(
              Icons.drag_indicator,
              size: 16,
              color: StudioTokens.textMuted,
            ),
          ),
        ),
      ),
    );
    return Draggable<_ReplacementRuleDragData>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded(),
      feedback: Material(
        color: Colors.transparent,
        child: _ReplacementRuleDragFeedback(
          ruleKey: ruleKey,
          label: label,
          sourcePrompt: sourcePrompt,
          targetPrompt: targetPrompt,
          deleted: deleted,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: handle),
      child: handle,
    );
  }
}

class _ReplacementRuleActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ReplacementRuleActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 24,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          iconSize: 15,
          color: color,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _ReplacementFrameIcon extends StatelessWidget {
  final String label;

  const _ReplacementFrameIcon({required this.label});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: StudioTokens.surface1,
          borderRadius: StudioTokens.radiusBadge,
          border: Border.all(color: StudioTokens.primary.withAlpha(100)),
        ),
        child: Icon(
          Icons.filter_none_outlined,
          size: 12,
          color: StudioTokens.primary.withAlpha(210),
        ),
      ),
    );
  }
}

class _ReplacementTargetPromptBox extends StatelessWidget {
  final String ruleKey;
  final double width;
  final double? weightMultiplier;
  final Widget child;

  const _ReplacementTargetPromptBox({
    required this.ruleKey,
    required this.width,
    required this.weightMultiplier,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final weight = weightMultiplier;
    final body = SizedBox(width: width, child: child);
    if (weight == null || (weight - 1.0).abs() < 0.000001) {
      return body;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        body,
        Positioned(
          key: ValueKey('replacement-rule-target-block-weight-$ruleKey'),
          right: -5,
          top: -8,
          child: _ReplacementWeightBadge(weight: weight),
        ),
      ],
    );
  }
}

class _ReplacementWeightBadge extends StatelessWidget {
  final double weight;

  const _ReplacementWeightBadge({required this.weight});

  @override
  Widget build(BuildContext context) {
    final isNegative = weight < 0;
    final color = isNegative ? StudioTokens.danger : StudioTokens.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(isNegative ? 30 : 28),
        borderRadius: StudioTokens.radiusBadge,
        border: Border.all(color: color.withAlpha(isNegative ? 150 : 120)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          'x${weight.toStringAsFixed(2)}',
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}

class _ReplacementRuleGroup {
  final PromptTagCategory category;
  final String label;
  final List<StudioScriptReplacementRuleItem> rules;

  const _ReplacementRuleGroup({
    required this.category,
    required this.label,
    required this.rules,
  });
}

List<_ReplacementRuleGroup> _replacementRuleGroups(
  String scope,
  List<StudioScriptReplacementRuleItem> rules,
) {
  final byCategory =
      <PromptTagCategory, List<StudioScriptReplacementRuleItem>>{};
  for (final rule in rules) {
    final category = _replacementRuleCategory(scope, rule);
    (byCategory[category] ??= []).add(rule);
  }
  final orderedCategories = [
    if (scope == 'scene') ...[
      PromptTagCategory.scene,
      PromptTagCategory.camera,
      PromptTagCategory.action,
      PromptTagCategory.other,
    ] else ...[
      PromptTagCategory.character,
      PromptTagCategory.upperBody,
      PromptTagCategory.lowerBody,
      PromptTagCategory.upperClothing,
      PromptTagCategory.lowerClothing,
      PromptTagCategory.accessory,
      PromptTagCategory.clothingState,
      PromptTagCategory.clothing,
      PromptTagCategory.other,
    ],
    for (final category in byCategory.keys)
      if (scope == 'scene'
          ? category != PromptTagCategory.scene &&
              category != PromptTagCategory.camera &&
              category != PromptTagCategory.action &&
              category != PromptTagCategory.other
          : category != PromptTagCategory.character &&
              category != PromptTagCategory.upperBody &&
              category != PromptTagCategory.lowerBody &&
              category != PromptTagCategory.upperClothing &&
              category != PromptTagCategory.lowerClothing &&
              category != PromptTagCategory.accessory &&
              category != PromptTagCategory.clothingState &&
              category != PromptTagCategory.clothing &&
              category != PromptTagCategory.other)
        category,
  ];
  return [
    for (final category in orderedCategories)
      if (byCategory[category]?.isNotEmpty ?? false)
        _ReplacementRuleGroup(
          category: category,
          label: _replacementRuleCategoryLabel(scope, category),
          rules: List.unmodifiable(byCategory[category]!),
        ),
  ];
}

PromptTagCategory _replacementRuleCategory(
  String scope,
  StudioScriptReplacementRuleItem rule,
) {
  final terms = rule.sourceTerms.where((term) => term.text.trim().isNotEmpty);
  for (final term in terms) {
    if (scope == 'scene') {
      if (term.category == PromptTagCategory.scene ||
          term.category == PromptTagCategory.camera ||
          term.category == PromptTagCategory.action) {
        return term.category;
      }
      continue;
    }
    if (term.category == PromptTagCategory.character ||
        term.category == PromptTagCategory.upperBody ||
        term.category == PromptTagCategory.lowerBody ||
        term.category == PromptTagCategory.upperClothing ||
        term.category == PromptTagCategory.lowerClothing ||
        term.category == PromptTagCategory.accessory ||
        term.category == PromptTagCategory.clothingState ||
        term.category == PromptTagCategory.clothing) {
      return term.category;
    }
  }
  return scope == 'scene' ? PromptTagCategory.scene : PromptTagCategory.other;
}

String _replacementRuleCategoryLabel(
  String scope,
  PromptTagCategory category,
) {
  if (scope == 'scene') {
    return switch (category) {
      PromptTagCategory.camera => '镜头',
      PromptTagCategory.action => '动作',
      PromptTagCategory.scene => '场景',
      _ => '其它场景词',
    };
  }
  return switch (category) {
    PromptTagCategory.character => '角色身份',
    PromptTagCategory.upperBody => '上身',
    PromptTagCategory.lowerBody => '下身',
    PromptTagCategory.upperClothing => '上装',
    PromptTagCategory.lowerClothing => '下装',
    PromptTagCategory.accessory => '饰品',
    PromptTagCategory.clothingState => '服装状态/动作',
    PromptTagCategory.clothing => '其它服装',
    _ => '其它角色词',
  };
}

bool _replacementRuleHasResult(StudioScriptReplacementRuleItem rule) {
  return rule.action == ScriptPromptReplacementAction.delete ||
      rule.targetPrompt.trim().isNotEmpty;
}

const double _replacementRuleCollapsedTagMaxWidth = 144;
const double _replacementPromptBridgeWidth = 42;
const double _replacementRuleChromeWidth = 52;

double _replacementSourcePromptWidth(
  StudioScriptReplacementRuleItem rule, {
  required bool hasFrameLabel,
  required bool showingTarget,
}) {
  return _replacementPromptFlowWidth(
    _replacementSourcePromptTags(rule),
    minWidth: 112,
    maxWidth: showingTarget ? 420 : 620,
    extraWidth: hasFrameLabel ? 30 : 0,
  );
}

double _replacementTargetPromptWidth(
  String prompt, {
  required bool editing,
}) {
  final width = _replacementPromptFlowWidth(
    _replacementTargetPromptTags(prompt),
    minWidth: editing ? 320 : 112,
    maxWidth: 620,
  );
  return editing && width < 320 ? 320 : width;
}

double _replacementRuleCardMaxWidth({
  required double sourcePromptWidth,
  required double targetPromptWidth,
  required bool showingTarget,
}) {
  final promptWidth = sourcePromptWidth > targetPromptWidth
      ? sourcePromptWidth
      : targetPromptWidth;
  final contentWidth = sourcePromptWidth +
      (showingTarget ? targetPromptWidth + _replacementPromptBridgeWidth : 0) +
      _replacementRuleChromeWidth;
  final balancedFlexWidth =
      showingTarget ? promptWidth * 2 + 140 : contentWidth;
  final width =
      contentWidth > balancedFlexWidth ? contentWidth : balancedFlexWidth;
  return width.clamp(showingTarget ? 320 : 180, showingTarget ? 1040 : 700);
}

List<String> _replacementSourcePromptTags(
  StudioScriptReplacementRuleItem rule,
) {
  return [
    for (final term in rule.sourceTerms)
      if (term.text.trim().isNotEmpty) term.text.trim(),
  ];
}

List<String> _replacementTargetPromptTags(String prompt) {
  return [
    for (final analysis in PromptTagProcessor.analyzeWorkshopTags(prompt))
      if (analysis.text.trim().isNotEmpty)
        PromptTagProcessor.cleanTagDisplay(analysis.text),
  ];
}

double _replacementPromptFlowWidth(
  Iterable<String> tags, {
  required double minWidth,
  required double maxWidth,
  double extraWidth = 0,
}) {
  final visibleTags = [
    for (final tag in tags)
      if (tag.trim().isNotEmpty) tag.trim(),
  ];
  if (visibleTags.isEmpty) {
    return minWidth;
  }
  final tagWidth = visibleTags.fold<double>(
    0,
    (sum, tag) => sum + _replacementPromptTagWidth(tag),
  );
  final spacing = (visibleTags.length - 1).clamp(0, 1000) * 4.0;
  return (tagWidth + spacing + extraWidth).clamp(minWidth, maxWidth);
}

double _replacementPromptTagWidth(String tag) {
  final text = PromptTagProcessor.cleanTagDisplay(tag).trim();
  if (text.isEmpty) {
    return _replacementRuleCollapsedTagMaxWidth;
  }
  return _replacementRuleCollapsedTagMaxWidth;
}

String _replacementRuleFrameLabel(StudioScriptReplacementRuleItem rule) {
  final frames = <int>{};
  for (final term in rule.sourceTerms) {
    frames.addAll(term.frameIndexes);
  }
  if (frames.isEmpty) {
    return '';
  }
  final sorted = frames.toList()..sort();
  return '出现帧：${_compactFrameRanges(sorted)}';
}

String _compactFrameRanges(List<int> frames) {
  if (frames.isEmpty) {
    return '';
  }
  final ranges = <String>[];
  var start = frames.first;
  var previous = frames.first;
  for (final frame in frames.skip(1)) {
    if (frame == previous + 1) {
      previous = frame;
      continue;
    }
    ranges.add(start == previous ? '$start' : '$start-$previous');
    start = frame;
    previous = frame;
  }
  ranges.add(start == previous ? '$start' : '$start-$previous');
  return ranges.join(', ');
}

class _ReplacementMatchModeSelector extends StatelessWidget {
  final String ruleKey;
  final ScriptPromptReplacementMatchMode value;
  final ValueChanged<ScriptPromptReplacementMatchMode> onChanged;

  const _ReplacementMatchModeSelector({
    required this.ruleKey,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final next = _nextMode(value);
    return Tooltip(
      key: ValueKey('replacement-rule-match-$ruleKey'),
      message: '匹配模式：${_modeLongLabel(value)}；点击切换为${_modeLongLabel(next)}',
      child: InkWell(
        borderRadius: StudioTokens.radiusBadge,
        onTap: () => onChanged(next),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: StudioTokens.surface1,
            borderRadius: StudioTokens.radiusBadge,
            border: Border.all(color: StudioTokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _modeIcon(value),
                size: 13,
                color: StudioTokens.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                _modeLabel(value),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ScriptPromptReplacementMatchMode _nextMode(
    ScriptPromptReplacementMatchMode mode,
  ) {
    return switch (mode) {
      ScriptPromptReplacementMatchMode.any =>
        ScriptPromptReplacementMatchMode.all,
      ScriptPromptReplacementMatchMode.all =>
        ScriptPromptReplacementMatchMode.anchor,
      ScriptPromptReplacementMatchMode.anchor =>
        ScriptPromptReplacementMatchMode.any,
    };
  }

  IconData _modeIcon(ScriptPromptReplacementMatchMode mode) {
    return switch (mode) {
      ScriptPromptReplacementMatchMode.any => Icons.filter_1_outlined,
      ScriptPromptReplacementMatchMode.all => Icons.done_all_outlined,
      ScriptPromptReplacementMatchMode.anchor => Icons.adjust_outlined,
    };
  }

  String _modeLongLabel(ScriptPromptReplacementMatchMode mode) {
    return switch (mode) {
      ScriptPromptReplacementMatchMode.any => '任一出现',
      ScriptPromptReplacementMatchMode.all => '同时出现',
      ScriptPromptReplacementMatchMode.anchor => '锚点触发',
    };
  }

  String _modeLabel(ScriptPromptReplacementMatchMode mode) {
    return switch (mode) {
      ScriptPromptReplacementMatchMode.any => '任一',
      ScriptPromptReplacementMatchMode.all => '同时',
      ScriptPromptReplacementMatchMode.anchor => '锚点',
    };
  }
}

String _replacementRuleSelectionGroupId(String scope, String ownerId) {
  return 'replacement-rule-group-$scope-$ownerId';
}

String _replacementRuleSourceFieldId(
  String scope,
  String ownerId,
  String ruleId,
) {
  return 'replacement-rule-source-field-$scope-$ownerId-$ruleId';
}

String? _replacementRuleIdForDraggedSourceTags(
  PromptTagDragData data, {
  required String scope,
  required String ownerId,
}) {
  final sourceRuleIds = _replacementRuleIdsForDraggedSourceTags(
    data,
    scope: scope,
    ownerId: ownerId,
  );
  return sourceRuleIds.length == 1 ? sourceRuleIds.single : null;
}

Set<String> _replacementRuleIdsForDraggedSourceTags(
  PromptTagDragData data, {
  required String scope,
  required String ownerId,
}) {
  if (data.sourceFieldIds.isEmpty ||
      data.tags.every((tag) => tag.trim().isEmpty)) {
    return const {};
  }
  final prefix = _replacementRuleSourceFieldId(scope, ownerId, '');
  final ruleIds = <String>{};
  for (final fieldId in data.sourceFieldIds) {
    if (!fieldId.startsWith(prefix)) {
      continue;
    }
    final sourceRuleId = fieldId.substring(prefix.length);
    if (sourceRuleId.isNotEmpty) {
      ruleIds.add(sourceRuleId);
    }
  }
  return Set.unmodifiable(ruleIds);
}

String? _replacementRuleIdForDraggedTargetTags(
  PromptTagDragData data, {
  required String scope,
  required String ownerId,
}) {
  if (data.sourceFieldIds.length != 1 ||
      data.tags.every((tag) => tag.trim().isEmpty)) {
    return null;
  }
  final prefix = _replacementRuleTargetFieldId(scope, ownerId, '');
  final fieldId = data.sourceFieldIds.single;
  if (!fieldId.startsWith(prefix)) {
    return null;
  }
  final sourceRuleId = fieldId.substring(prefix.length);
  return sourceRuleId.isEmpty ? null : sourceRuleId;
}

String _replacementRuleTargetFieldId(
  String scope,
  String ownerId,
  String ruleId,
) {
  return 'replacement-rule-target-field-$scope-$ownerId-$ruleId';
}

String _replacementRoleIdentityFieldId(String sourceRoleId) {
  return 'replacement-role-identity-field-$sourceRoleId';
}

String _replacementTermsPrompt(StudioScriptReplacementRuleItem rule) {
  final excludedIds = rule.excludedTermIds.toSet();
  final selectedTerms = [
    for (final term in rule.sourceTerms)
      if (!excludedIds.contains(term.id) && term.text.trim().isNotEmpty)
        term.text.trim(),
  ];
  final terms = selectedTerms.isEmpty
      ? [
          for (final term in rule.sourceTerms)
            if (term.text.trim().isNotEmpty) term.text.trim(),
        ]
      : selectedTerms;
  return terms.join(', ');
}

String _replacementAllTermsPrompt(StudioScriptReplacementRuleItem rule) {
  return [
    for (final term in rule.sourceTerms)
      if (term.text.trim().isNotEmpty) term.text.trim(),
  ].join(', ');
}

String? _replacementTermIdForTag(
  StudioScriptReplacementRuleItem rule,
  String tag,
) {
  final key = PromptTagProcessor.normalizeMatchKey(tag);
  if (key.isEmpty) {
    return null;
  }
  for (final term in rule.sourceTerms) {
    if (PromptTagProcessor.normalizeMatchKey(term.text) == key) {
      return term.id;
    }
  }
  return null;
}

class _ArtistMapping extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ArtistMapping({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('script-artist-mapping-section'),
      child: _SectionPanel(
        title: '画师串',
        icon: Icons.brush_outlined,
        children: [
          if (viewModel.artistMappings.isEmpty)
            const _EmptyHint(text: '导入剧本后会显示源画师串'),
          for (final (index, chain) in viewModel.artistMappings.indexed)
            StudioStaggeredReveal(
              index: index,
              child: _ArtistMappingRow(
                item: chain,
                index: index,
                artistChains: viewModel.artistChainOptions,
                sourceVibes: viewModel.sourceVibeOptions,
                vibeOptions: viewModel.vibeOptions,
                selectedManualVibes: viewModel.selectedManualVibes,
                translationCache: viewModel.translationCache,
                onAssetDropped: (data) {
                  if (data.kind == _ScriptAssetDragKind.artistChain) {
                    viewModel.setArtistChain(data.artistChainId);
                  }
                },
                onSourceChanged: viewModel.setArtistSourceLabel,
                onTargetChanged: viewModel.setManualArtistPrompt,
                onManualVibeChanged: (vibeId, selected) =>
                    viewModel.setManualVibe(vibeId, selected, notify: false),
                onManualVibeStrengthChanged: (vibeId, strength) => viewModel
                    .setManualVibeStrength(vibeId, strength, notify: false),
                onImportVibes: viewModel.importManualVibes,
                onClear: () => viewModel.setArtistChain(null),
                onDeleted: viewModel.setArtistSourceDeleted,
              ),
            ),
          for (final (index, block) in viewModel.promptBlockMappings.indexed)
            StudioStaggeredReveal(
              index: viewModel.artistMappings.length + index,
              child: _PromptBlockMappingRow(
                item: block,
                index: index,
                translationCache: viewModel.translationCache,
                onSourceChanged: (value) =>
                    viewModel.setPromptBlockSource(block.block, value),
                onTargetChanged: (value) =>
                    viewModel.setPromptBlockManualPrompt(block.block, value),
                onDeleted: (deleted) =>
                    viewModel.setPromptBlockDeleted(block.block, deleted),
              ),
            ),
        ],
      ),
    );
  }
}

class _AiStatusBanner extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _AiStatusBanner({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final status = viewModel.aiStatus.trim().isEmpty
        ? '尚未进行 AI 分析'
        : viewModel.aiStatus.trim();
    final isError = status.contains('失败') ||
        status.contains('未配置') ||
        status.contains('请先配置');
    final color = viewModel.isAiBusy
        ? StudioTokens.primary
        : isError
            ? StudioTokens.warning
            : StudioTokens.textSecondary;
    final background = viewModel.isAiBusy
        ? StudioTokens.primary.withAlpha(22)
        : isError
            ? StudioTokens.warning.withAlpha(20)
            : StudioTokens.surface3;
    final detail = viewModel.isExtractingAiRoleEvidence
        ? '正在提取 AI 角色证据'
        : viewModel.isApplyingAiRoleExtraction
            ? '正在应用 AI 角色结果'
            : '就绪';

    return Container(
      key: const ValueKey('script-ai-feedback-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: color.withAlpha(130)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Icon(
              viewModel.isAiBusy
                  ? Icons.pending_actions_outlined
                  : isError
                      ? Icons.error_outline
                      : Icons.smart_toy_outlined,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (viewModel.showAiProgressPanel) ...[
                  const SizedBox(height: 2),
                  Text(
                    _aiProgressLabel(viewModel),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: StudioTokens.primary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiProgressPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _AiProgressPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final steps = viewModel.aiProgressSteps;
    final failed = steps.any(
      (step) => step.state == StudioScriptAiProgressStepState.failed,
    );
    final progressValue = _aiProgressFraction(viewModel);
    final accent = failed
        ? StudioTokens.warning
        : viewModel.isAiBusy
            ? StudioTokens.primary
            : StudioTokens.active;
    final progressLabel = _aiProgressLabel(viewModel);

    return StudioPanel(
      key: const ValueKey('script-ai-progress-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: StudioTokens.radiusSlot,
                  border: Border.all(color: accent.withAlpha(150)),
                ),
                child: Icon(
                  viewModel.isAiBusy
                      ? Icons.pending_actions_outlined
                      : failed
                          ? Icons.error_outline
                          : Icons.task_alt_outlined,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            viewModel.aiProgressTitle.isEmpty
                                ? 'AI 工作进度'
                                : viewModel.aiProgressTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: StudioTokens.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(22),
                            borderRadius: StudioTokens.radiusPill,
                            border: Border.all(color: accent.withAlpha(120)),
                          ),
                          child: Text(
                            progressLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        if (_hasAiRoleExtractionDetails(viewModel)) ...[
                          const SizedBox(width: 8),
                          StudioIconButton(
                            icon: Icons.subject_outlined,
                            tooltip: '查看 AI 处理详情',
                            onPressed: () =>
                                _showAiProcessingDetails(context, viewModel),
                          ),
                        ],
                        if (_canManualReconnectRoleExtraction(viewModel)) ...[
                          const SizedBox(width: 8),
                          StudioButton(
                            label: '手动重连',
                            icon: Icons.refresh_outlined,
                            tone: StudioButtonTone.secondary,
                            onPressed: () {
                              unawaited(viewModel.generateAiRoleExtraction());
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      viewModel.aiStatus,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (_aiLiveMetricItems(viewModel).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _AiLiveMetricStrip(
                        items: _aiLiveMetricItems(viewModel),
                        accent: accent,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AiProgressHero(
            steps: steps,
            progressValue: progressValue,
            progressLabel: progressLabel,
            accent: accent,
            failed: failed,
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, step) in steps.indexed)
                _AiProgressStepRow(index: index + 1, step: step),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiProgressHero extends StatelessWidget {
  final List<StudioScriptAiProgressStep> steps;
  final double progressValue;
  final String progressLabel;
  final Color accent;
  final bool failed;

  const _AiProgressHero({
    required this.steps,
    required this.progressValue,
    required this.progressLabel,
    required this.accent,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final activeIndex = steps.indexWhere(
      (step) => step.state == StudioScriptAiProgressStepState.active,
    );
    final failedIndex = steps.indexWhere(
      (step) => step.state == StudioScriptAiProgressStepState.failed,
    );
    final currentIndex = activeIndex >= 0
        ? activeIndex
        : failedIndex >= 0
            ? failedIndex
            : (steps.lastIndexWhere(
                (step) => step.state == StudioScriptAiProgressStepState.done,
              )).clamp(0, steps.isEmpty ? 0 : steps.length - 1);
    final currentStep = steps.isEmpty ? null : steps[currentIndex];
    final currentTitle = currentStep == null
        ? 'Waiting for AI task'
        : '${currentIndex + 1}/${steps.length} / ${currentStep.label}';
    final currentState = currentStep == null
        ? 'waiting'
        : switch (currentStep.state) {
            StudioScriptAiProgressStepState.waiting => 'waiting',
            StudioScriptAiProgressStepState.active => 'active',
            StudioScriptAiProgressStepState.done => 'done',
            StudioScriptAiProgressStepState.failed => 'failed',
          };

    return Container(
      key: const ValueKey('script-ai-progress-hero'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface1,
        borderRadius: BorderRadius.circular(StudioTokens.radiusPanel),
        border: Border.all(color: accent.withAlpha(failed ? 130 : 80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _AiCurrentStepCard(
                  title: currentTitle,
                  stateText: currentState,
                  accent: accent,
                ),
              ),
              const SizedBox(width: 12),
              _AiProgressPercentBadge(
                label: progressLabel,
                progressValue: progressValue,
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AiProgressStepRail(
            steps: steps,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _AiCurrentStepCard extends StatelessWidget {
  final String title;
  final String stateText;
  final Color accent;

  const _AiCurrentStepCard({
    required this.title,
    required this.stateText,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('script-ai-progress-current-step'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前阶段',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stateText,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _AiProgressPercentBadge extends StatelessWidget {
  final String label;
  final double progressValue;
  final Color accent;

  const _AiProgressPercentBadge({
    required this.label,
    required this.progressValue,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progressValue * 100).round();
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Column(
        children: [
          Text(
            '$percent%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            _compactProgressLabel(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: StudioTokens.textMuted,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }

  String _compactProgressLabel(String label) {
    final withoutPrefix = label.replaceFirst('进度 ', '');
    final separator = withoutPrefix.indexOf(' · ');
    return separator < 0
        ? withoutPrefix
        : withoutPrefix.substring(0, separator);
  }
}

class _AiProgressStepRail extends StatelessWidget {
  final List<StudioScriptAiProgressStep> steps;
  final Color accent;

  const _AiProgressStepRail({
    required this.steps,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('script-ai-progress-step-rail'),
      children: [
        for (final (index, step) in steps.indexed) ...[
          Expanded(
            child: _AiProgressRailSegment(
              index: index,
              step: step,
              accent: accent,
            ),
          ),
          if (index != steps.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _AiProgressRailSegment extends StatelessWidget {
  final int index;
  final StudioScriptAiProgressStep step;
  final Color accent;

  const _AiProgressRailSegment({
    required this.index,
    required this.step,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final active = step.state == StudioScriptAiProgressStepState.active;
    final done = step.state == StudioScriptAiProgressStepState.done;
    final failed = step.state == StudioScriptAiProgressStepState.failed;
    final color = failed
        ? StudioTokens.warning
        : active
            ? accent
            : done
                ? StudioTokens.active
                : StudioTokens.surface4;

    return Tooltip(
      message: '${index + 1}. ${step.label}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: active ? 12 : 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: StudioTokens.radiusPill,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withAlpha(70),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _AiLiveMetricItem {
  final String label;
  final String value;

  const _AiLiveMetricItem(this.label, this.value);
}

class _AiLiveMetricStrip extends StatelessWidget {
  final List<_AiLiveMetricItem> items;
  final Color accent;

  const _AiLiveMetricStrip({
    required this.items,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: StudioTokens.surface1,
              borderRadius: StudioTokens.radiusBadge,
              border: Border.all(color: accent.withAlpha(75)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 6),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

List<_AiLiveMetricItem> _aiLiveMetricItems(StudioScriptViewModel viewModel) {
  final preview = viewModel.aiRoleExtractionRequestPreview;
  final items = <_AiLiveMetricItem>[];
  if (viewModel.aiRoleExtractionRequestCount > 0) {
    items.add(
      _AiLiveMetricItem(
        '请求',
        viewModel.aiRoleExtractionRequestCount.toString(),
      ),
    );
  }
  final requestKind = preview['request_kind']?.toString().trim();
  if (requestKind != null && requestKind.isNotEmpty) {
    items.add(
      _AiLiveMetricItem('Kind', _aiRoleRequestKindLabel(requestKind)),
    );
  }
  final chunkId = preview['chunk_id']?.toString().trim();
  if (chunkId != null && chunkId.isNotEmpty) {
    items.add(_AiLiveMetricItem('Chunk', chunkId));
  }
  final sources = preview['sources'];
  if (sources is List) {
    items.add(_AiLiveMetricItem('证据源', sources.length.toString()));
  }
  final script = preview['script'];
  if (script is Map && script['frame_count'] != null) {
    items.add(_AiLiveMetricItem('帧', script['frame_count'].toString()));
  }
  final reasoningChars = viewModel.aiRoleExtractionReasoningContent.length;
  if (reasoningChars > 0) {
    items.add(_AiLiveMetricItem('思考字数', reasoningChars.toString()));
  }
  final contentChars = viewModel.aiRoleExtractionStreamingContent.length;
  if (contentChars > 0) {
    items.add(_AiLiveMetricItem('返回字数', contentChars.toString()));
  }
  return items;
}

String _aiRoleRequestKindLabel(String kind) {
  return switch (kind) {
    'chunk_extract_v2' => 'chunk_extract_v2',
    'evidence_followup' => 'evidence_followup',
    'merge_extractions' => 'merge_extractions',
    'chunk_extract' => 'chunk_extract',
    _ => kind,
  };
}

void _showAiProcessingDetails(
  BuildContext context,
  StudioScriptViewModel viewModel,
) {
  showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => _AiProcessingDetailsDialog(viewModel: viewModel),
    ),
  );
}

class _AiProcessingDetailsDialog extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _AiProcessingDetailsDialog({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final reasoning = viewModel.aiRoleExtractionReasoningContent.trim();
    final response = viewModel.aiRoleExtractionStreamingContent.trim();
    return AlertDialog(
      backgroundColor: StudioTokens.surface1,
      title: const Text('AI 处理详情'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AiProcessingDetailSection(
                title: '当前流程',
                icon: Icons.route_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, step)
                        in viewModel.aiProgressSteps.indexed)
                      _AiProgressStepRow(index: index + 1, step: step),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AiProcessingDetailSection(
                title: '请求摘要',
                icon: Icons.receipt_long_outlined,
                child: _AiProcessingTextList(
                  lines: _aiRoleExtractionRequestSummary(viewModel),
                ),
              ),
              const SizedBox(height: 12),
              _AiProcessingDetailSection(
                title: '请求与返回流',
                icon: Icons.stream_outlined,
                child: _AiProcessingLiveStream(viewModel: viewModel),
              ),
              const SizedBox(height: 12),
              _AiProcessingDetailSection(
                title: 'DeepSeek 思考过程',
                icon: Icons.psychology_alt_outlined,
                child: _AiCompactTextBlock(
                  key: const ValueKey('script-ai-reasoning-preview'),
                  title: '最近思考片段',
                  text: reasoning,
                  emptyText: '当前模型未返回 reasoning_content，仅展示处理明细。',
                  maxChars: 1100,
                  maxSegments: 4,
                  color: StudioTokens.primary,
                ),
              ),
              const SizedBox(height: 12),
              _AiProcessingDetailSection(
                title: 'AI 返回摘要',
                icon: Icons.auto_awesome_outlined,
                child: _AiProcessingTextList(
                  lines: _aiRoleExtractionResultSummary(viewModel),
                ),
              ),
              const SizedBox(height: 12),
              _AiProcessingExpandableSection(
                title: '完整日志与证据',
                icon: Icons.manage_search_outlined,
                summary: '默认只展示最近片段；展开后可查看完整 JSON、完整思考过程和隐藏证据。',
                children: [
                  if (viewModel.aiRoleExtractionRequestPreview.isNotEmpty)
                    _AiDeferredDetailBlock(
                      title: '完整请求 JSON',
                      icon: Icons.data_object_outlined,
                      color: StudioTokens.secondary,
                      childBuilder: () => _AiStreamTextBlock(
                        title: 'aiRoleExtractionRequestPreview',
                        text: _aiRoleExtractionRequestPreviewJson(viewModel),
                        color: StudioTokens.secondary,
                      ),
                    ),
                  if (reasoning.isNotEmpty)
                    _AiDeferredDetailBlock(
                      title: '完整 DeepSeek 思考过程',
                      icon: Icons.psychology_alt_outlined,
                      color: StudioTokens.primary,
                      childBuilder: () => _AiStreamTextBlock(
                        title: 'reasoning_content',
                        text: reasoning,
                        color: StudioTokens.primary,
                      ),
                    ),
                  if (response.isNotEmpty)
                    _AiDeferredDetailBlock(
                      title: '完整返回流',
                      icon: Icons.data_object_outlined,
                      color: StudioTokens.info,
                      childBuilder: () => _AiStreamTextBlock(
                        title: '返回流',
                        text: response,
                        color: StudioTokens.info,
                      ),
                    ),
                  _AiDeferredDetailBlock(
                    title: '隐藏证据',
                    icon: Icons.visibility_off_outlined,
                    color: StudioTokens.warning,
                    childBuilder: () => _AiRoleExtractionHiddenEvidence(
                      extraction: viewModel.aiRoleExtraction,
                      translationCache: viewModel.translationCache,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _AiProcessingDetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _AiProcessingDetailSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: StudioTokens.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _AiProcessingExpandableSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final String summary;
  final List<Widget> children;

  const _AiProcessingExpandableSection({
    required this.title,
    required this.icon,
    required this.summary,
    required this.children,
  });

  @override
  State<_AiProcessingExpandableSection> createState() =>
      _AiProcessingExpandableSectionState();
}

class _AiProcessingExpandableSectionState
    extends State<_AiProcessingExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: StudioTokens.radiusSlot,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(widget.icon, size: 16, color: StudioTokens.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: StudioTokens.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StudioTokens.textMuted,
                  height: 1.35,
                ),
          ),
          StudioAnimatedPresence(
            visible: _expanded,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                for (final (index, child) in widget.children.indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDeferredDetailBlock extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget Function() childBuilder;

  const _AiDeferredDetailBlock({
    required this.title,
    required this.icon,
    required this.color,
    required this.childBuilder,
  });

  @override
  State<_AiDeferredDetailBlock> createState() => _AiDeferredDetailBlockState();
}

class _AiDeferredDetailBlockState extends State<_AiDeferredDetailBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface1,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: widget.color.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: StudioTokens.radiusSlot,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(widget.icon, size: 15, color: widget.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: widget.color,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: StudioTokens.textMuted,
                ),
              ],
            ),
          ),
          StudioAnimatedPresence(
            visible: _expanded,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                widget.childBuilder(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCompactTextBlock extends StatelessWidget {
  final String title;
  final String text;
  final String emptyText;
  final int maxChars;
  final int maxSegments;
  final Color color;

  const _AiCompactTextBlock({
    super.key,
    required this.title,
    required this.text,
    required this.emptyText,
    required this.maxChars,
    required this.maxSegments,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final snippet = _aiRecentTextSnippet(
      text,
      maxChars: maxChars,
      maxSegments: maxSegments,
    );
    final body = snippet.text;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface1,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          if (body.isEmpty)
            Text(
              emptyText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textMuted,
                    height: 1.4,
                  ),
            )
          else ...[
            if (snippet.isTruncated)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '仅显示最新几段，完整内容可在下方“完整日志与证据”中展开。',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            Text(
              body,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textPrimary,
                    height: 1.45,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiProcessingTextList extends StatelessWidget {
  final List<String> lines;

  const _AiProcessingTextList({required this.lines});

  @override
  Widget build(BuildContext context) {
    final visibleLines = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (visibleLines.isEmpty) {
      return Text(
        '暂无明细',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in visibleLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textSecondary,
                    height: 1.35,
                  ),
            ),
          ),
      ],
    );
  }
}

class _AiProcessingLiveStream extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _AiProcessingLiveStream({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final events = viewModel.aiRoleExtractionTraceEvents;
    final content = viewModel.aiRoleExtractionStreamingContent.trim();
    if (events.isEmpty && content.isEmpty) {
      return Text(
        '等待 AI 请求开始，请求阶段和返回内容会在这里实时追加。',
        key: const ValueKey('script-ai-live-stream'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Column(
      key: const ValueKey('script-ai-live-stream'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (events.isNotEmpty) ...[
          if (events.length > 5)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                '仅显示最新 5 条请求事件，完整证据可在下方展开。',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          for (final event in events.reversed.take(5).toList().reversed)
            _AiTraceEventRow(event: event),
        ],
        if (content.isNotEmpty) ...[
          const SizedBox(height: 10),
          _AiCompactTextBlock(
            key: const ValueKey('script-ai-response-preview'),
            title: '返回流最近片段',
            text: content,
            emptyText: '等待 AI 返回内容。',
            maxChars: 900,
            maxSegments: 4,
            color: StudioTokens.info,
          ),
        ],
      ],
    );
  }
}

class _AiTraceEventRow extends StatelessWidget {
  final StudioScriptAiTraceEvent event;

  const _AiTraceEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = _aiTraceEventColor(event.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_aiTraceEventIcon(event.kind), size: 15, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textSecondary,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiStreamTextBlock extends StatelessWidget {
  final String title;
  final String text;
  final Color color;

  const _AiStreamTextBlock({
    required this.title,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface1,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StudioTokens.textSecondary,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

({String text, bool isTruncated}) _aiRecentTextSnippet(
  String value, {
  required int maxChars,
  required int maxSegments,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return (text: '', isTruncated: false);
  }

  final segments = trimmed
      .split(RegExp(r'(?:\r?\n){2,}|\r?\n'))
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final selectedSegments = segments.length > maxSegments
      ? segments.sublist(segments.length - maxSegments)
      : segments;
  var preview =
      selectedSegments.isEmpty ? trimmed : selectedSegments.join('\n\n').trim();
  var isTruncated = selectedSegments.length < segments.length;

  if (preview.length > maxChars) {
    preview = preview.substring(preview.length - maxChars).trimLeft();
    isTruncated = true;
  }

  if (isTruncated) {
    preview = '...$preview';
  }
  return (text: preview, isTruncated: isTruncated);
}

IconData _aiTraceEventIcon(StudioScriptAiTraceEventKind kind) {
  return switch (kind) {
    StudioScriptAiTraceEventKind.input => Icons.input_outlined,
    StudioScriptAiTraceEventKind.reasoning => Icons.psychology_alt_outlined,
    StudioScriptAiTraceEventKind.content => Icons.data_object_outlined,
    StudioScriptAiTraceEventKind.parse => Icons.schema_outlined,
    StudioScriptAiTraceEventKind.result => Icons.task_alt_outlined,
    StudioScriptAiTraceEventKind.error => Icons.error_outline,
  };
}

Color _aiTraceEventColor(StudioScriptAiTraceEventKind kind) {
  return switch (kind) {
    StudioScriptAiTraceEventKind.input => StudioTokens.secondary,
    StudioScriptAiTraceEventKind.reasoning => StudioTokens.primary,
    StudioScriptAiTraceEventKind.content => StudioTokens.info,
    StudioScriptAiTraceEventKind.parse => StudioTokens.warning,
    StudioScriptAiTraceEventKind.result => StudioTokens.active,
    StudioScriptAiTraceEventKind.error => StudioTokens.danger,
  };
}

class _AiRoleExtractionHiddenEvidence extends StatelessWidget {
  final ScriptAiRoleExtraction extraction;
  final TranslationCache translationCache;

  const _AiRoleExtractionHiddenEvidence({
    required this.extraction,
    required this.translationCache,
  });

  @override
  Widget build(BuildContext context) {
    final pendingTerms = _aiRoleExtractionPendingTerms(extraction);
    final groups = <Widget>[
      if (extraction.artistChains.isNotEmpty)
        _AiRoleExtractionTermGroup(
          title: '画风/画师证据：用于提示风格来源，不直接改角色字段',
          icon: Icons.brush_outlined,
          translationCache: translationCache,
          terms: [
            for (final chain in extraction.artistChains) ...[
              if (chain.label.trim().isNotEmpty) chain.label,
              ...chain.terms,
              ...chain.evidenceTerms,
            ],
          ],
        ),
      if (extraction.strongFilterKeywords.isNotEmpty)
        _AiRoleExtractionTermGroup(
          title: '强过滤词：点击应用后写入过滤库',
          icon: Icons.block_outlined,
          translationCache: translationCache,
          terms: [
            for (final keyword in extraction.strongFilterKeywords) keyword.term,
          ],
        ),
      if (pendingTerms.isNotEmpty)
        _AiRoleExtractionTermGroup(
          title: '未使用证据：AI 没有写入五字段，仅供排查',
          icon: Icons.label_off_outlined,
          translationCache: translationCache,
          terms: [
            for (final term in extraction.unassignedTerms.take(80))
              if (term.reason.trim().isEmpty)
                term.term
              else
                '${term.term} 路 ${term.reason}',
          ],
        ),
    ];
    if (groups.isEmpty) {
      return Text(
        '暂无隐藏证据。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (extraction.artistChains.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, chain) in extraction.artistChains.indexed)
                TextButton.icon(
                  key: ValueKey('script-ai-artist-chain-save-$index'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    unawaited(
                      _showAssetCaptureDraft(
                        context,
                        StudioAssetCaptureDrafts.artistFromAiEvidence(
                          chain,
                          source: StudioAssetCaptureSource(
                            surface: 'script',
                            label: 'AI 画师串证据',
                            sourceId: 'artist-chain-$index',
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.library_add_outlined, size: 16),
                  label: const Text('保存素材'),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const SizedBox(height: 10),
          group,
        ],
      ],
    );
  }
}

class _AiRoleExtractionPendingTerm {
  final String term;
  final String source;
  final String reason;
  final List<int> frameIndexes;

  const _AiRoleExtractionPendingTerm({
    required this.term,
    required this.source,
    required this.reason,
    required this.frameIndexes,
  });

  String get detailLabel {
    final details = [
      if (source.trim().isNotEmpty) source.trim(),
      if (reason.trim().isNotEmpty) reason.trim(),
      if (frameIndexes.isNotEmpty)
        'frames ${_aiRoleExtractionFrameLabel(frameIndexes)}',
    ];
    if (details.isEmpty) return term;
    return '$term - ${details.join(' / ')}';
  }

  String get tooltip => detailLabel;
}

List<_AiRoleExtractionPendingTerm> _aiRoleExtractionPendingTerms(
  ScriptAiRoleExtraction extraction,
) {
  final terms = <_AiRoleExtractionPendingTerm>[];
  final seen = <String>{};

  void addTerm({
    required String rawTerm,
    required String source,
    required String reason,
    required List<int> frameIndexes,
  }) {
    final display = PromptTagProcessor.cleanTagDisplay(
      rawTerm,
      removeWeights: false,
    ).trim();
    final clean = PromptTagProcessor.cleanTagDisplay(rawTerm).trim();
    final normalizedFrames = _normalizedFrameIndexes(frameIndexes);
    final key = [
      PromptTagProcessor.normalizeMatchKey(clean),
      source.trim(),
      reason.trim(),
      ...normalizedFrames.map((index) => index.toString()),
    ].join('|');
    if (display.isEmpty || clean.isEmpty || !seen.add(key)) {
      return;
    }
    terms.add(
      _AiRoleExtractionPendingTerm(
        term: display,
        source: source,
        reason: reason,
        frameIndexes: normalizedFrames,
      ),
    );
  }

  for (final term in extraction.unassignedTerms) {
    addTerm(
      rawTerm: term.term,
      source: 'global',
      reason: term.reason,
      frameIndexes: term.frameIndexes,
    );
  }
  for (final role in extraction.roles) {
    final roleSource = role.sourceRoleId.trim().isEmpty
        ? role.displayName.trim()
        : role.sourceRoleId.trim();
    for (final term in role.unassignedTerms) {
      addTerm(
        rawTerm: term.term,
        source: roleSource,
        reason: term.reason,
        frameIndexes: term.frameIndexes,
      );
    }
    for (final stage in role.stages) {
      final stageSource = [
        if (roleSource.isNotEmpty) roleSource,
        if (stage.stageId.trim().isNotEmpty) stage.stageId.trim(),
      ].join(' / ');
      for (final term in PromptTagProcessor.splitWorkshopTags(stage.nonRole)) {
        addTerm(
          rawTerm: term,
          source: stageSource,
          reason: 'stage pending field',
          frameIndexes: stage.frameIndexes,
        );
      }
    }
  }
  return List.unmodifiable(terms);
}

List<String> _aiRoleExtractionRequestSummary(StudioScriptViewModel viewModel) {
  final preview = viewModel.aiRoleExtractionRequestPreview;
  final script = preview['script'];
  final sources = preview['sources'];
  final chunks = preview['chunks'];
  return [
    'AI 请求次数：${viewModel.aiRoleExtractionRequestCount}',
    if (preview['request_kind'] != null)
      '请求类型：${_aiRoleRequestKindLabel(preview['request_kind'].toString())}',
    if (preview['chunk_id'] != null) 'Chunk：${preview['chunk_id']}',
    if (script is Map && script['name'] != null) '剧本：${script['name']}',
    if (script is Map && script['frame_count'] != null)
      '解析帧数：${script['frame_count']}',
    if (sources is List) '证据来源：${sources.length} 个',
    if (chunks is List) '合并 chunks：${chunks.length} 个',
  ];
}

String _aiRoleExtractionRequestPreviewJson(StudioScriptViewModel viewModel) {
  return const JsonEncoder.withIndent('  ')
      .convert(viewModel.aiRoleExtractionRequestPreview);
}

List<String> _aiRoleExtractionResultSummary(StudioScriptViewModel viewModel) {
  final extraction = viewModel.aiRoleExtraction;
  final displayRoles = _aiRoleExtractionDisplayRoles(extraction);
  return [
    '状态：${extraction.status.name}',
    '整体置信度：${(extraction.confidence * 100).round()}%',
    '角色数量：${extraction.roles.length}',
    '画师串证据：${extraction.artistChains.length}',
    '强过滤关键词：${extraction.strongFilterKeywords.length}',
    '注意事项：${extraction.attentionItems.length}',
    for (final role in displayRoles.take(6))
      '角色 ${role.sourceRoleId}: '
          '${role.displayName.trim().isEmpty ? '未命名' : role.displayName}: '
          '${role.stages.length} 个阶段，'
          '置信度 ${(role.confidence * 100).round()}%',
  ];
}

double _aiProgressFraction(StudioScriptViewModel viewModel) {
  final steps = viewModel.aiProgressSteps;
  if (steps.isEmpty) {
    return 0.0;
  }
  final activeIndex = steps.indexWhere(
    (step) => step.state == StudioScriptAiProgressStepState.active,
  );
  final doneCount = steps
      .where((step) => step.state == StudioScriptAiProgressStepState.done)
      .length;
  final progressUnits = viewModel.isAiBusy && activeIndex >= 0
      ? activeIndex + 0.65
      : doneCount.toDouble();
  return (progressUnits / steps.length).clamp(0.0, 1.0);
}

String _aiProgressLabel(StudioScriptViewModel viewModel) {
  final steps = viewModel.aiProgressSteps;
  if (steps.isEmpty) {
    return '进度 0/0';
  }
  final activeIndex = steps.indexWhere(
    (step) => step.state == StudioScriptAiProgressStepState.active,
  );
  final failedIndex = steps.indexWhere(
    (step) => step.state == StudioScriptAiProgressStepState.failed,
  );
  final doneCount = steps
      .where((step) => step.state == StudioScriptAiProgressStepState.done)
      .length;
  final current = activeIndex >= 0
      ? activeIndex + 1
      : failedIndex >= 0
          ? failedIndex + 1
          : doneCount;
  final percent = (_aiProgressFraction(viewModel) * 100).round();
  return '进度 $current/${steps.length} · $percent%';
}

bool _canManualReconnectRoleExtraction(StudioScriptViewModel viewModel) {
  return !viewModel.isAiBusy &&
      viewModel.aiRoleExtraction.isFailed &&
      viewModel.aiProgressTitle.contains('角色字段');
}

bool _hasAiRoleExtractionDetails(StudioScriptViewModel viewModel) {
  return viewModel.aiRoleExtractionRequestPreview.isNotEmpty ||
      viewModel.aiRoleExtractionTraceEvents.isNotEmpty ||
      viewModel.aiRoleExtractionReasoningContent.trim().isNotEmpty ||
      viewModel.aiRoleExtractionStreamingContent.trim().isNotEmpty ||
      viewModel.aiRoleExtraction.status != ScriptAiRoleExtractionStatus.idle;
}

class _AiProgressStepRow extends StatelessWidget {
  final int index;
  final StudioScriptAiProgressStep step;

  const _AiProgressStepRow({
    required this.index,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, stateText) = switch (step.state) {
      StudioScriptAiProgressStepState.waiting => (
          Icons.radio_button_unchecked,
          StudioTokens.textMuted,
          '等待',
        ),
      StudioScriptAiProgressStepState.active => (
          Icons.play_circle_outline,
          StudioTokens.primary,
          '进行中',
        ),
      StudioScriptAiProgressStepState.done => (
          Icons.check_circle_outline,
          StudioTokens.active,
          '已完成',
        ),
      StudioScriptAiProgressStepState.failed => (
          Icons.error_outline,
          StudioTokens.warning,
          '需要处理',
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$index.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StudioTokens.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              step.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            stateText,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _ChangedSourceCacheActions extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ChangedSourceCacheActions({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '检测到同一剧本的旧缓存，但源文件已变化。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('use-fresh-recast-parse'),
                onPressed: viewModel.useFreshParseForChangedSource,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('重新解析当前源'),
              ),
              TextButton.icon(
                key: const ValueKey('restore-changed-source-cache'),
                onPressed: viewModel.restoreChangedSourceCache,
                icon: const Icon(Icons.history_outlined),
                label: const Text('沿用旧缓存复现'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelinePanel extends StatefulWidget {
  final StudioScriptViewModel viewModel;

  const _TimelinePanel({required this.viewModel});

  @override
  State<_TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<_TimelinePanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: '帧时间线',
      icon: Icons.timeline_outlined,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey('script-timeline-scroll'),
              controller: _scrollController,
              primary: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in widget.viewModel.timeline)
                      _FrameChip(
                        key: ValueKey(
                          'script-timeline-frame-${item.frameIndex}',
                        ),
                        label: item.label,
                        selected: item.selected,
                        warning: item.warning,
                        statuses: item.statuses,
                        onPressed: () =>
                            widget.viewModel.selectFrame(item.frameIndex),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> actions;
  final List<Widget> children;

  const _SectionPanel({
    super.key,
    required this.title,
    required this.icon,
    this.actions = const [],
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: StudioTokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...actions,
              ],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _ArtistMappingRow extends StatelessWidget {
  final StudioScriptArtistMappingItem item;
  final int index;
  final List<ArtistChain> artistChains;
  final List<WorkspaceVibeReference> sourceVibes;
  final List<WorkspaceVibeReference> vibeOptions;
  final List<WorkspaceVibeReference> selectedManualVibes;
  final TranslationCache translationCache;
  final ValueChanged<_ScriptAssetDragData> onAssetDropped;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTargetChanged;
  final void Function(String vibeId, bool selected) onManualVibeChanged;
  final void Function(String vibeId, double strength)
      onManualVibeStrengthChanged;
  final Future<List<WorkspaceVibeReference>> Function()? onImportVibes;
  final VoidCallback onClear;
  final ValueChanged<bool> onDeleted;

  const _ArtistMappingRow({
    required this.item,
    required this.index,
    required this.artistChains,
    required this.sourceVibes,
    required this.vibeOptions,
    required this.selectedManualVibes,
    required this.translationCache,
    required this.onAssetDropped,
    required this.onSourceChanged,
    required this.onTargetChanged,
    required this.onManualVibeChanged,
    required this.onManualVibeStrengthChanged,
    required this.onImportVibes,
    required this.onClear,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final selectedChain =
        _artistChainById(artistChains, item.selectedArtistChainId);
    final manualPrompt = item.manualPrompt.trim();
    final targetPrompt =
        selectedChain == null ? manualPrompt : _artistChainLabel(selectedChain);
    final hasTargetPrompt = targetPrompt.trim().isNotEmpty;
    final hasSourcePrompt = item.sourceLabel.trim().isNotEmpty;
    final deleteSource = item.deleteSource;
    return DragTarget<_ScriptAssetDragData>(
      key: ValueKey('artist-drop-target-$index'),
      onWillAcceptWithDetails: (details) =>
          details.data.kind == _ScriptAssetDragKind.artistChain,
      onAcceptWithDetails: (details) => onAssetDropped(details.data),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        final sourceCell = _ArtistPromptCell(
          key: ValueKey('artist-source-tags-$index'),
          title: '源画师串',
          text: item.sourceLabel,
          translationCache: translationCache,
          emptyText: '未检测到',
          onChanged: onSourceChanged,
          trailing: hasSourcePrompt
              ? _SaveArtistPromptAssetButton(
                  key: ValueKey('script-artist-mapping-save-source-$index'),
                  prompt: item.sourceLabel,
                  source: StudioAssetCaptureSource(
                    surface: 'script',
                    label: '源画师串',
                    sourceId: 'artist-mapping-source-$index',
                  ),
                  defaultName: '源画师串 ${index + 1}',
                )
              : null,
          footer: _ArtistSourceVibeSlot(
            index: index,
            sourceVibes: sourceVibes,
            selectedVibes: selectedManualVibes,
          ),
        );
        final targetCell = _ArtistPromptCell(
          key: ValueKey('artist-output-tags-$index'),
          inputKey: ValueKey('artist-output-input-$index'),
          title: '替换后画师串',
          text: targetPrompt,
          translationCache: translationCache,
          active: active,
          editable: true,
          emptyText: '拖入或手动输入画师串替换',
          onChanged: onTargetChanged,
          trailing: !hasTargetPrompt
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SaveArtistPromptAssetButton(
                      key: ValueKey(
                        'script-artist-mapping-save-target-$index',
                      ),
                      prompt: targetPrompt,
                      artistChain: selectedChain,
                      source: StudioAssetCaptureSource(
                        surface: 'script',
                        label: '画师串替换目标',
                        sourceId: 'artist-mapping-target-$index',
                      ),
                      defaultName: '画师串映射 ${index + 1}',
                    ),
                    const SizedBox(width: 6),
                    StudioIconButton(
                      tooltip: '清空画师串替换',
                      icon: Icons.delete_outline,
                      onPressed: onClear,
                    ),
                  ],
                ),
          footer: _ArtistVibeSlot(
            index: index,
            vibeOptions: vibeOptions,
            selectedManualVibes: selectedManualVibes,
            onManualVibeChanged: onManualVibeChanged,
            onManualVibeStrengthChanged: onManualVibeStrengthChanged,
            onImportVibes: onImportVibes,
          ),
        );
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? StudioTokens.surface3 : StudioTokens.surface2,
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: active ? StudioTokens.primary : StudioTokens.cardOutline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sourceCell,
              const SizedBox(height: 8),
              targetCell,
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ValueKey('artist-delete-source-$index'),
                  onPressed: () => onDeleted(!deleteSource),
                  icon: Icon(
                    deleteSource
                        ? Icons.undo_outlined
                        : Icons.delete_forever_outlined,
                    size: 16,
                  ),
                  label: Text(
                    deleteSource ? 'Keep source block' : 'Delete source block',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PromptBlockMappingRow extends StatelessWidget {
  final StudioScriptPromptBlockMappingItem item;
  final int index;
  final TranslationCache translationCache;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTargetChanged;
  final ValueChanged<bool> onDeleted;

  const _PromptBlockMappingRow({
    required this.item,
    required this.index,
    required this.translationCache,
    required this.onSourceChanged,
    required this.onTargetChanged,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('prompt-block-mapping-${item.block}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              TextButton.icon(
                key: ValueKey('prompt-block-delete-${item.block}'),
                onPressed: () => onDeleted(!item.deleteSource),
                icon: Icon(
                  item.deleteSource
                      ? Icons.undo_outlined
                      : Icons.delete_forever_outlined,
                  size: 16,
                ),
                label: Text(
                  item.deleteSource
                      ? 'Keep source block'
                      : 'Delete source block',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ArtistPromptCell(
            key: ValueKey('prompt-block-source-${item.block}'),
            title: 'Source ${item.label}',
            text: item.sourcePrompt,
            translationCache: translationCache,
            editable: true,
            emptyText: 'No source terms',
            onChanged: onSourceChanged,
          ),
          const SizedBox(height: 8),
          _ArtistPromptCell(
            key: ValueKey('prompt-block-target-${item.block}'),
            inputKey: ValueKey('prompt-block-target-input-${item.block}'),
            title: 'Replacement ${item.label}',
            text: item.manualPrompt,
            translationCache: translationCache,
            editable: true,
            emptyText: item.deleteSource
                ? 'Marked deleted'
                : 'Leave blank to keep source',
            onChanged: onTargetChanged,
          ),
        ],
      ),
    );
  }
}

class _SaveArtistPromptAssetButton extends StatelessWidget {
  final String prompt;
  final ArtistChain? artistChain;
  final StudioAssetCaptureSource source;
  final String defaultName;

  const _SaveArtistPromptAssetButton({
    super.key,
    required this.prompt,
    this.artistChain,
    required this.source,
    required this.defaultName,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () {
        final draft = artistChain == null
            ? StudioAssetCaptureDrafts.artistFromPrompt(
                prompt,
                source: source,
                name: defaultName,
              )
            : StudioAssetCaptureDraft.artistChain(
                artistChain: artistChain!,
                source: source,
                name: artistChain!.name,
              );
        unawaited(_showAssetCaptureDraft(context, draft));
      },
      icon: const Icon(Icons.library_add_outlined, size: 16),
      label: const Text('保存素材'),
    );
  }
}

class _ArtistSourceVibeSlot extends StatelessWidget {
  final int index;
  final List<WorkspaceVibeReference> sourceVibes;
  final List<WorkspaceVibeReference> selectedVibes;

  const _ArtistSourceVibeSlot({
    required this.index,
    required this.sourceVibes,
    required this.selectedVibes,
  });

  @override
  Widget build(BuildContext context) {
    final vibes = _mergeArtistVibeSources(sourceVibes);
    if (vibes.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectedIds = selectedVibes.map((vibe) => vibe.id).toSet();
    return Container(
      key: ValueKey('artist-source-vibe-slot-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: StudioTokens.surface1.withAlpha(150),
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ArtistVibeSectionLabel(label: '剧本源 Vibe'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final vibe in vibes)
                _ArtistSourceVibeChip(
                  key: ValueKey('artist-vibe-source-${vibe.id}'),
                  vibe: vibe,
                  active: selectedIds.contains(vibe.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtistVibeSlot extends StatefulWidget {
  final int index;
  final List<WorkspaceVibeReference> vibeOptions;
  final List<WorkspaceVibeReference> selectedManualVibes;
  final void Function(String vibeId, bool selected) onManualVibeChanged;
  final void Function(String vibeId, double strength)
      onManualVibeStrengthChanged;
  final Future<List<WorkspaceVibeReference>> Function()? onImportVibes;

  const _ArtistVibeSlot({
    required this.index,
    required this.vibeOptions,
    required this.selectedManualVibes,
    required this.onManualVibeChanged,
    required this.onManualVibeStrengthChanged,
    required this.onImportVibes,
  });

  @override
  State<_ArtistVibeSlot> createState() => _ArtistVibeSlotState();
}

class _ArtistVibeSlotState extends State<_ArtistVibeSlot> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = _idsFor(widget.selectedManualVibes);
  }

  @override
  void didUpdateWidget(covariant _ArtistVibeSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedManualVibes != widget.selectedManualVibes) {
      _selectedIds = _idsFor(widget.selectedManualVibes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedById = {
      for (final vibe in widget.selectedManualVibes) vibe.id: vibe,
    };
    final sourceVibes = _mergeArtistVibeSources(widget.vibeOptions);
    return Container(
      key: ValueKey('artist-vibe-slot-${widget.index}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.image_search_outlined,
                size: 16,
                color: StudioTokens.info,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已启用 Vibe',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.info,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              if (widget.onImportVibes != null) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  key: ValueKey('artist-vibe-add-${widget.index}'),
                  onPressed: () async {
                    try {
                      final imported = await widget.onImportVibes!.call();
                      if (!context.mounted || imported.isEmpty) {
                        return;
                      }
                      setState(() {
                        _selectedIds.addAll(imported.map((vibe) => vibe.id));
                      });
                      if (Scaffold.maybeOf(context) != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已添加 ${imported.length} 个 Vibe'),
                          ),
                        );
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      if (Scaffold.maybeOf(context) != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('导入 Vibe 失败：$error')),
                        );
                      }
                    }
                  },
                  icon:
                      const Icon(Icons.add_photo_alternate_outlined, size: 16),
                  label: const Text('添加 Vibe'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildActiveDropZone(context, selectedById, sourceVibes),
        ],
      ),
    );
  }

  Widget _buildActiveDropZone(
    BuildContext context,
    Map<String, WorkspaceVibeReference> selectedById,
    List<WorkspaceVibeReference> sourceVibes,
  ) {
    return DragTarget<WorkspaceVibeReference>(
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: (details) =>
          details.data.vibeB64.trim().isNotEmpty &&
          !_selectedIds.contains(details.data.id),
      onAcceptWithDetails: (details) => _activateVibe(details.data),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        final sourceById = {
          for (final vibe in sourceVibes) vibe.id: vibe,
        };
        final activeVibes = [
          for (final vibeId in _selectedIds)
            if (selectedById[vibeId] != null || sourceById[vibeId] != null)
              selectedById[vibeId] ?? sourceById[vibeId]!,
        ];
        return AnimatedContainer(
          key: ValueKey('artist-vibe-active-drop-zone-${widget.index}'),
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? StudioTokens.info.withAlpha(24)
                : StudioTokens.surface1.withAlpha(180),
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: active ? StudioTokens.info : StudioTokens.border,
            ),
          ),
          child: activeVibes.isEmpty
              ? Center(
                  child: Text(
                    active ? '松开启用' : '拖入源 Vibe 启用',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: active
                              ? StudioTokens.info
                              : StudioTokens.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                )
              : Column(
                  children: [
                    for (final vibe in activeVibes)
                      _ArtistManualVibeTile(
                        key: ValueKey('artist-vibe-active-${vibe.id}'),
                        removeKey: ValueKey('artist-vibe-remove-${vibe.id}'),
                        sliderKey: ValueKey('artist-vibe-strength-${vibe.id}'),
                        vibe: selectedById[vibe.id] ?? vibe,
                        onRemoved: () => _deactivateVibe(vibe.id),
                        onStrengthChanged: (strength) => widget
                            .onManualVibeStrengthChanged(vibe.id, strength),
                      ),
                  ],
                ),
        );
      },
    );
  }

  void _activateVibe(WorkspaceVibeReference vibe) {
    if (_selectedIds.contains(vibe.id)) {
      return;
    }
    setState(() {
      _selectedIds.add(vibe.id);
    });
    widget.onManualVibeChanged(vibe.id, true);
  }

  void _deactivateVibe(String vibeId) {
    if (!_selectedIds.contains(vibeId)) {
      return;
    }
    setState(() {
      _selectedIds.remove(vibeId);
    });
    widget.onManualVibeChanged(vibeId, false);
  }

  Set<String> _idsFor(List<WorkspaceVibeReference> vibes) {
    return vibes.map((vibe) => vibe.id).toSet();
  }
}

class _ArtistSourceVibeChip extends StatelessWidget {
  final WorkspaceVibeReference vibe;
  final bool active;

  const _ArtistSourceVibeChip({
    super.key,
    required this.vibe,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final chip = StudioChip(
      label: _vibeLabel(vibe),
      icon: active ? Icons.check_circle_outline : Icons.drag_indicator,
      selected: active,
      accentColor: StudioTokens.info,
    );
    return Draggable<WorkspaceVibeReference>(
      data: vibe,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: StudioChip(
          label: _vibeLabel(vibe),
          icon: Icons.drag_indicator,
          selected: true,
          accentColor: StudioTokens.info,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: chip),
      child: chip,
    );
  }
}

class _ArtistManualVibeTile extends StatefulWidget {
  final Key removeKey;
  final Key sliderKey;
  final WorkspaceVibeReference vibe;
  final VoidCallback onRemoved;
  final ValueChanged<double> onStrengthChanged;

  const _ArtistManualVibeTile({
    super.key,
    required this.removeKey,
    required this.sliderKey,
    required this.vibe,
    required this.onRemoved,
    required this.onStrengthChanged,
  });

  @override
  State<_ArtistManualVibeTile> createState() => _ArtistManualVibeTileState();
}

class _ArtistManualVibeTileState extends State<_ArtistManualVibeTile> {
  late double _draftStrength;

  @override
  void initState() {
    super.initState();
    _draftStrength = widget.vibe.referenceStrength.clamp(0.0, 1.0).toDouble();
  }

  @override
  void didUpdateWidget(covariant _ArtistManualVibeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.vibe.referenceStrength.clamp(0.0, 1.0).toDouble();
    if (oldWidget.vibe.id != widget.vibe.id ||
        oldWidget.vibe.referenceStrength != widget.vibe.referenceStrength) {
      _draftStrength = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_outlined,
                size: 16,
                color: StudioTokens.info,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _vibeLabel(widget.vibe),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _draftStrength.toStringAsFixed(2),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: StudioTokens.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              IconButton(
                key: widget.removeKey,
                visualDensity: VisualDensity.compact,
                tooltip: '移除 Vibe',
                onPressed: widget.onRemoved,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: StudioTokens.danger,
                ),
              ),
            ],
          ),
          Slider(
            key: widget.sliderKey,
            value: _draftStrength,
            min: 0,
            max: 1,
            divisions: 100,
            label: _draftStrength.toStringAsFixed(2),
            onChanged: (value) => setState(() {
              _draftStrength = value;
            }),
            onChangeEnd: widget.onStrengthChanged,
          ),
        ],
      ),
    );
  }
}

class _ArtistVibeSectionLabel extends StatelessWidget {
  final String label;

  const _ArtistVibeSectionLabel({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: StudioTokens.textMuted,
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

List<WorkspaceVibeReference> _mergeArtistVibeSources(
  Iterable<WorkspaceVibeReference> vibes,
) {
  final seen = <String>{};
  final result = <WorkspaceVibeReference>[];
  for (final vibe in vibes) {
    final key = _artistVibeSourceKey(vibe);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(vibe);
  }
  return result;
}

String _artistVibeSourceKey(WorkspaceVibeReference vibe) {
  final encoding = vibe.vibeB64.trim();
  return encoding.isEmpty ? vibe.id : encoding;
}

String _vibeLabel(WorkspaceVibeReference vibe) {
  return vibe.name.trim().isEmpty ? vibe.id : vibe.name;
}

class _ArtistPromptCell extends StatelessWidget {
  final Key? inputKey;
  final String title;
  final String text;
  final TranslationCache translationCache;
  final bool active;
  final bool editable;
  final String emptyText;
  final Widget? trailing;
  final Widget? footer;
  final ValueChanged<String>? onChanged;

  const _ArtistPromptCell({
    super.key,
    this.inputKey,
    required this.title,
    required this.text,
    required this.translationCache,
    this.active = false,
    this.editable = false,
    this.emptyText = '未选择',
    this.trailing,
    this.footer,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            active ? StudioTokens.primary.withAlpha(18) : StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(
          color: active ? StudioTokens.primary : StudioTokens.cardOutline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.primary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 3),
          if (editable) ...[
            _ArtistPromptInput(
              fieldKey: inputKey,
              text: normalized,
              hintText: emptyText,
              onChanged: onChanged ?? (_) {},
            ),
            if (normalized.isNotEmpty) const SizedBox(height: 6),
          ],
          if (!editable || normalized.isNotEmpty)
            PromptTagDisplay(
              text: normalized,
              defaultTranslated: true,
              dense: true,
              enableTagActions: true,
              translationCache: translationCache,
              emptyText: emptyText,
              onChanged: onChanged,
            ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _ArtistPromptInput extends StatefulWidget {
  final Key? fieldKey;
  final String text;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _ArtistPromptInput({
    required this.fieldKey,
    required this.text,
    required this.hintText,
    required this.onChanged,
  });

  @override
  State<_ArtistPromptInput> createState() => _ArtistPromptInputState();
}

class _ArtistPromptInputState extends State<_ArtistPromptInput> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(covariant _ArtistPromptInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      minLines: 1,
      maxLines: 3,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        filled: true,
        fillColor: StudioTokens.surface1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: StudioTokens.cardOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: StudioTokens.cardOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: StudioTokens.primary),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;

  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

CharacterEntry? _characterById(List<CharacterEntry> characters, String? id) {
  if (id == null) {
    return null;
  }
  for (final character in characters) {
    if (character.id == id) {
      return character;
    }
  }
  return null;
}

ArtistChain? _artistChainById(List<ArtistChain> chains, String? id) {
  if (id == null || id.trim().isEmpty) {
    return null;
  }
  for (final chain in chains) {
    if (chain.id == id) {
      return chain;
    }
  }
  return null;
}

String? _firstScriptPreviewPath(List<String> previewPaths) {
  for (final path in previewPaths) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String _aiRawResponseExcerpt(String rawResponse) {
  final normalized = rawResponse.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 280) {
    return normalized;
  }
  return '${normalized.substring(0, 280)}...';
}

String _normalizedAiLabel(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _outfitLabel(WorkspaceOutfit outfit) {
  final upper = outfit.tags.frontUpper?.trim();
  final lower = outfit.tags.frontLower?.trim();
  final parts = [
    if (upper != null && upper.isNotEmpty) upper,
    if (lower != null && lower.isNotEmpty) lower,
  ];
  if (parts.isNotEmpty) {
    return parts.join(' / ');
  }
  final full = outfit.tags.frontFull.trim();
  if (full.isNotEmpty) {
    return full;
  }
  return outfit.name;
}

String _artistChainLabel(ArtistChain chain) {
  final prompt = chain.prompt.trim();
  if (prompt.isNotEmpty) {
    return prompt;
  }
  return [
    ...chain.tags,
    ...chain.styleTags,
  ].join(', ');
}

class _FrameChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool warning;
  final List<StudioScriptTimelineStatus> statuses;
  final VoidCallback onPressed;

  const _FrameChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.warning = false,
    this.statuses = const [],
  });

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? StudioTokens.warning
        : selected
            ? StudioTokens.primary
            : StudioTokens.textSecondary;
    return ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor:
          selected ? StudioTokens.primary.withAlpha(22) : StudioTokens.surface3,
      side: BorderSide(
        color: warning || selected ? color : StudioTokens.cardOutline,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          for (final status in statuses) ...[
            const SizedBox(width: 5),
            Text(
              _timelineStatusLabel(status),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
      onPressed: onPressed,
    );
  }
}

String _timelineStatusLabel(StudioScriptTimelineStatus status) {
  return switch (status) {
    StudioScriptTimelineStatus.warning => '警告',
    StudioScriptTimelineStatus.error => '错误',
    StudioScriptTimelineStatus.sent => '已发送',
    StudioScriptTimelineStatus.failed => '失败',
  };
}
