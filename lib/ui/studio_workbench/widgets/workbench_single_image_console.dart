import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/core/constants/parameters.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/generation_presets.dart';
import 'package:novel_studio/data/models/info_card_content.dart';
import 'package:novel_studio/data/services/nai_account_usage_service.dart';
import 'package:novel_studio/data/services/nai_image_cost_estimator.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/ui/generation_page/widgets/info_card.dart';
import 'package:novel_studio/ui/i2i_config/widgets/i2i_config_view.dart';
import 'package:novel_studio/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_presence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:novel_studio/ui/vibe_config_v4/viewmodels/vibe_config_v4_list_viewmodel.dart';
import 'package:novel_studio/ui/vibe_config_v4/widgets/vibe_config_v4_list_view.dart';

const _characterCardRadius = BorderRadius.only(
  topLeft: Radius.circular(StudioTokens.radiusSmall),
  topRight: Radius.circular(StudioTokens.radiusSmall),
  bottomLeft: Radius.circular(StudioTokens.radiusSmall),
  bottomRight: Radius.zero,
);

class WorkbenchGenerationResultsPanel extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const WorkbenchGenerationResultsPanel({
    super.key,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('workbench-generation-results-panel'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResultsHeader(viewmodel: viewmodel),
          const SizedBox(height: 10),
          Expanded(child: _GenerationResultList(viewmodel: viewmodel)),
        ],
      ),
    );
  }
}

class WorkbenchCreativeInputsPanel extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;

  const WorkbenchCreativeInputsPanel({
    super.key,
    required this.parametersViewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('workbench-creative-inputs-panel'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.brush_outlined, color: StudioTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '画面输入',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListenableBuilder(
              listenable: parametersViewmodel,
              builder: (context, _) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StudioMotionSequenceRegion(
                        region: StudioMotionRegion.editor,
                        child: _CharacterSection(
                          viewmodel: parametersViewmodel,
                        ),
                      ),
                      const Divider(height: 24),
                      StudioMotionSequenceRegion(
                        region: StudioMotionRegion.editor,
                        order: 1,
                        child: _ReferenceInputSection(
                          viewmodel: parametersViewmodel,
                        ),
                      ),
                      const Divider(height: 24),
                      StudioMotionSequenceRegion(
                        region: StudioMotionRegion.editor,
                        order: 2,
                        child: _PromptControlSection(
                          viewmodel: parametersViewmodel,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WorkbenchSingleImageConsole extends StatefulWidget {
  final GenerationPageViewmodel generationViewmodel;
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;
  final StudioWorkbenchAssetService workbenchAssetService;
  final WorkbenchTransferViewModel? transferViewModel;
  final bool showExecutionControls;

  const WorkbenchSingleImageConsole({
    super.key,
    required this.generationViewmodel,
    required this.parametersViewmodel,
    required this.workbenchAssetService,
    this.transferViewModel,
    this.showExecutionControls = true,
  });

  @override
  State<WorkbenchSingleImageConsole> createState() =>
      _WorkbenchSingleImageConsoleState();
}

class _WorkbenchSingleImageConsoleState
    extends State<WorkbenchSingleImageConsole> {
  late String _lastModel;

  @override
  void initState() {
    super.initState();
    _lastModel = widget.parametersViewmodel.config.model;
    widget.parametersViewmodel.addListener(_handleParameterChange);
    unawaited(widget.generationViewmodel.refreshNaiAccountUsage());
  }

  @override
  void didUpdateWidget(covariant WorkbenchSingleImageConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parametersViewmodel != widget.parametersViewmodel) {
      oldWidget.parametersViewmodel.removeListener(_handleParameterChange);
      _lastModel = widget.parametersViewmodel.config.model;
      widget.parametersViewmodel.addListener(_handleParameterChange);
    }
    if (oldWidget.generationViewmodel != widget.generationViewmodel) {
      unawaited(widget.generationViewmodel.refreshNaiAccountUsage());
    }
  }

  @override
  void dispose() {
    widget.parametersViewmodel.removeListener(_handleParameterChange);
    super.dispose();
  }

  void _handleParameterChange() {
    final model = widget.parametersViewmodel.config.model;
    if (model == _lastModel) return;
    _lastModel = model;
    unawaited(widget.generationViewmodel.refreshNaiAccountUsage());
  }

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('workbench-single-image-console'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConsoleHeader(
            viewmodel: widget.generationViewmodel,
            transferViewModel: widget.transferViewModel,
          ),
          if (widget.showExecutionControls) ...[
            const SizedBox(height: 12),
            StudioMotionSequenceRegion(
              region: StudioMotionRegion.controls,
              child: _ExecutionSection(
                viewmodel: widget.generationViewmodel,
                parametersViewmodel: widget.parametersViewmodel,
                workbenchAssetService: widget.workbenchAssetService,
                transferViewModel: widget.transferViewModel,
              ),
            ),
          ],
          const Divider(height: 24),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.parametersViewmodel,
              builder: (context, _) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.showExecutionControls) ...[
                        _NaiAccountUsagePanel(
                          service:
                              widget.generationViewmodel.naiAccountUsageService,
                          showV5Allowance:
                              widget.parametersViewmodel.capabilities.isV5,
                          onRefresh:
                              widget.generationViewmodel.refreshNaiAccountUsage,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _CoreOutputSection(viewmodel: widget.parametersViewmodel),
                      const Divider(height: 24),
                      _AdvancedSection(viewmodel: widget.parametersViewmodel),
                      const Divider(height: 24),
                      _RandomnessSection(viewmodel: widget.parametersViewmodel),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _ResultsHeader({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Row(
          children: [
            const Icon(Icons.image_outlined, color: StudioTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '生成结果',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            StudioChip(
              icon: Icons.collections_outlined,
              label: viewmodel.commandList.length.toString(),
            ),
          ],
        );
      },
    );
  }
}

class _ConsoleHeader extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;
  final WorkbenchTransferViewModel? transferViewModel;

  const _ConsoleHeader({
    required this.viewmodel,
    required this.transferViewModel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewmodel,
        viewmodel.commandStatus.isBatchActive,
        viewmodel.commandStatus.isCoolingDown,
        transferViewModel,
      ]),
      builder: (context, _) {
        final active = viewmodel.commandStatus.isBatchActive.value;
        final coolingDown = viewmodel.commandStatus.isCoolingDown.value;
        return Row(
          children: [
            const Icon(Icons.auto_awesome, color: StudioTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '生成控制',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            StudioChip(
              icon: coolingDown
                  ? Icons.hourglass_bottom
                  : active
                      ? Icons.bolt
                      : Icons.radio_button_unchecked,
              label: coolingDown
                  ? '冷却'
                  : active
                      ? '生成中'
                      : '待机',
              selected: active || coolingDown,
              accentColor:
                  coolingDown ? StudioTokens.warning : StudioTokens.active,
            ),
            if (transferViewModel != null) ...[
              const SizedBox(width: 8),
              StudioIconButton(
                key: const ValueKey('workbench-export-action'),
                tooltip: '导出工作台',
                icon: Icons.file_download_outlined,
                onPressed: transferViewModel!.exportToFile,
              ),
            ],
          ],
        );
      },
    );
  }
}

class WorkbenchGenerationActions extends StatelessWidget {
  final GenerationPageViewmodel generationViewmodel;
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;
  final StudioWorkbenchAssetService workbenchAssetService;
  final WorkbenchTransferViewModel? transferViewModel;

  const WorkbenchGenerationActions({
    super.key,
    required this.generationViewmodel,
    required this.parametersViewmodel,
    required this.workbenchAssetService,
    this.transferViewModel,
  });

  @override
  Widget build(BuildContext context) => _ExecutionSection(
        viewmodel: generationViewmodel,
        parametersViewmodel: parametersViewmodel,
        workbenchAssetService: workbenchAssetService,
        transferViewModel: transferViewModel,
        showAccountUsage: false,
      );
}

class _ExecutionSection extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;
  final StudioWorkbenchAssetService workbenchAssetService;
  final WorkbenchTransferViewModel? transferViewModel;
  final bool showAccountUsage;

  const _ExecutionSection({
    required this.viewmodel,
    required this.parametersViewmodel,
    required this.workbenchAssetService,
    required this.transferViewModel,
    this.showAccountUsage = true,
  });

  @override
  Widget build(BuildContext context) {
    final usageService = viewmodel.naiAccountUsageService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewmodel.commandStatus.isBatchActive,
        viewmodel.commandStatus.isCoolingDown,
        parametersViewmodel,
        if (usageService != null) usageService,
      ]),
      builder: (context, _) {
        final active = viewmodel.commandStatus.isBatchActive.value;
        final estimate = parametersViewmodel.estimateAnlas(
          usageService?.snapshot,
        );
        final estimatedAmount = estimate.isExact
            ? '${estimate.maximumAnlas}'
            : '${estimate.minimumAnlas}–${estimate.maximumAnlas}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showAccountUsage) ...[
              _NaiAccountUsagePanel(
                service: usageService,
                showV5Allowance: parametersViewmodel.capabilities.isV5,
                onRefresh: viewmodel.refreshNaiAccountUsage,
              ),
              const SizedBox(height: 10),
            ],
            if (!active && parametersViewmodel.knownExtraAnlas > 0)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StudioChip(
                    key: const ValueKey('workbench-known-extra-anlas'),
                    icon: Icons.bolt_outlined,
                    label: parametersViewmodel.knownExtraAnlasLabel,
                    selected: true,
                    accentColor: StudioTokens.warning,
                  ),
                ],
              ),
            if (!active && parametersViewmodel.knownExtraAnlas > 0)
              const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              final generate = KeyedSubtree(
                key: const ValueKey('workbench-generation-cost-estimate'),
                child: StudioButton(
                  key: const ValueKey('workbench-start-generation-button'),
                  label: active ? '停止生成' : '$estimatedAmount Anlas · 开始生成',
                  icon: active ? Icons.stop : Icons.toll_outlined,
                  tone: active
                      ? StudioButtonTone.danger
                      : StudioButtonTone.primary,
                  onPressed: active
                      ? () => viewmodel.stopBatch()
                      : () => _startGeneration(context),
                ),
              );
              final count = _GenerationCountField(
                viewmodel: parametersViewmodel,
                enabled: !active,
              );
              final secondary = <Widget>[
                if (transferViewModel != null) ...[
                  const SizedBox(width: 10),
                  StudioButton(
                    key: const ValueKey('workbench-import-action'),
                    label: '导入',
                    icon: Icons.file_upload_outlined,
                    tone: StudioButtonTone.secondary,
                    onPressed: () => transferViewModel!.importFromFile(context),
                  ),
                ],
                const SizedBox(width: 10),
                StudioIconButton(
                  key: const ValueKey('workbench-reset-action'),
                  tooltip: context.tr('reset'),
                  icon: Icons.restart_alt,
                  onPressed: active
                      ? null
                      : () {
                          workbenchAssetService.resetCreativeState();
                          parametersViewmodel.refreshFromPayload();
                        },
                ),
              ];
              if (constraints.maxWidth < 520) {
                return Column(children: [
                  Row(children: [
                    Expanded(child: generate),
                    const SizedBox(width: 10),
                    count,
                  ]),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                        mainAxisSize: MainAxisSize.min, children: secondary),
                  ),
                ]);
              }
              return Row(children: [
                Expanded(child: generate),
                const SizedBox(width: 10),
                count,
                ...secondary,
              ]);
            }),
          ],
        );
      },
    );
  }

  Future<void> _startGeneration(BuildContext context) async {
    parametersViewmodel.commitPendingInputs();
    await viewmodel.refreshNaiAccountUsage();
    if (!context.mounted) return;
    final snapshot = viewmodel.naiAccountUsageService?.snapshot;
    final estimate = parametersViewmodel.estimateAnlas(snapshot);
    if (estimate.requiresConfirmation) {
      final anlas = snapshot?.totalAnlas;
      final balanceWarning = anlas != null && anlas < estimate.maximumAnlas
          ? '\n注意：当前余额可能不足。'
          : '';
      final continueGeneration = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            estimate.chargeState == NaiAnlasChargeState.uncertain
                ? '暂时无法确认是否收费'
                : '本次生成预计消耗点数',
          ),
          content: Text(
            '点数消耗预估：${estimate.amountDescription}'
            '${anlas == null ? '' : '\n当前可用 Anlas：$anlas'}'
            '\n计划生成：${parametersViewmodel.generationCount} 张。'
            '\n${estimate.reason}'
            '$balanceWarning'
            '\n实际扣费以 NovelAI 返回结果为准。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('workbench-confirm-v5-anlas-generation'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                estimate.isExact
                    ? '继续（预计 ${estimate.maximumAnlas} Anlas）'
                    : '继续生成',
              ),
            ),
          ],
        ),
      );
      if (continueGeneration != true || !context.mounted) return;
    }
    viewmodel.startSingleImageGeneration(
      count: parametersViewmodel.generationCount,
    );
  }
}

class _NaiAccountUsagePanel extends StatelessWidget {
  final NaiAccountUsageService? service;
  final bool showV5Allowance;
  final Future<void> Function() onRefresh;

  const _NaiAccountUsagePanel({
    required this.service,
    required this.showV5Allowance,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = service?.snapshot;
    final usage = snapshot?.opusUsage;
    final loading = service?.isLoading == true;
    final unavailable = service == null ||
        service?.state == NaiAccountUsageLoadState.unavailable;
    final exhausted = usage?.isNegative == true;
    final color = exhausted ? StudioTokens.warning : StudioTokens.primary;

    String balanceLabel;
    String balanceDetail;
    if (loading && snapshot == null) {
      balanceLabel = '正在同步账户点数';
      balanceDetail = '从 NovelAI 获取可用 Anlas…';
    } else if (snapshot?.totalAnlas != null) {
      balanceLabel = '可用点数 ${snapshot!.totalAnlas} Anlas';
      balanceDetail = '订阅点数 ${snapshot.subscriptionAnlas ?? '--'}'
          ' · 已购点数 ${snapshot.purchasedAnlas ?? '--'}';
    } else {
      balanceLabel = '账户点数暂不可用';
      balanceDetail =
          service?.errorMessage ?? '需要有效的 NovelAI Persistent API Token。';
    }

    String? opusLabel;
    String? opusDetail;
    if (showV5Allowance && snapshot != null && !snapshot.isOpus) {
      opusLabel = '当前账号不是有效的 Opus 订阅';
      opusDetail = 'V5 生成将按 NovelAI 规则消耗 Anlas。';
    } else if (showV5Allowance && usage != null) {
      final refill = usage.refillPercentPerDay;
      opusLabel = exhausted
          ? 'V5 Opus 免费额度已用尽'
          : 'V5 Opus 剩余 ${usage.visiblePercent.toStringAsFixed(1)}%';
      opusDetail = exhausted
          ? '继续生成将消耗 Anlas，额度会随时间恢复。'
          : '约 ${usage.estimatedNormalImages} 张普通生成'
              '${refill == null ? '' : ' · 每日恢复约 $refill%'}';
    } else if (showV5Allowance) {
      opusLabel = loading ? '正在同步 V5 Opus 额度' : 'V5 Opus 额度暂不可用';
      opusDetail = loading
          ? '等待账户数据返回…'
          : service?.errorMessage ?? '需要有效的 NovelAI Persistent API Token。';
    }

    return Container(
      key: const ValueKey('workbench-nai-account-usage-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(StudioTokens.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  balanceLabel,
                  key: const ValueKey('workbench-anlas-balance'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  balanceDetail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StudioTokens.textMuted,
                      ),
                ),
                if (opusLabel != null && opusDetail != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('workbench-v5-opus-usage-panel'),
                    padding: const EdgeInsets.only(top: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: StudioTokens.border),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          opusLabel,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: StudioTokens.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opusDetail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: StudioTokens.textMuted,
                                  ),
                        ),
                        if (usage != null) ...[
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            key: const ValueKey(
                              'workbench-v5-opus-usage-progress',
                            ),
                            value: usage.visiblePercent / 100,
                            minHeight: 5,
                            color: color,
                            backgroundColor: StudioTokens.surface3,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            KeyedSubtree(
              key: const ValueKey('workbench-refresh-nai-account-usage'),
              child: StudioIconButton(
                key: const ValueKey('workbench-refresh-v5-opus-usage'),
                tooltip: unavailable ? '重试同步账户' : '刷新账户',
                icon: Icons.refresh,
                onPressed: () => unawaited(onRefresh()),
              ),
            ),
        ],
      ),
    );
  }
}

class _GenerationCountField extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;
  final bool enabled;

  const _GenerationCountField({
    required this.viewmodel,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: KeyedSubtree(
        key:
            ValueKey('workbench-generation-count-${viewmodel.generationCount}'),
        child: TextFormField(
          key: const ValueKey('workbench-generation-count-field'),
          initialValue: viewmodel.generationCount.toString(),
          enabled: enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '张数',
            isDense: true,
            prefixIcon: Icon(Icons.collections_outlined, size: 18),
            prefixIconConstraints: BoxConstraints.tightFor(width: 32),
          ),
          onChanged: viewmodel.setGenerationCount,
          onFieldSubmitted: viewmodel.setGenerationCount,
        ),
      ),
    );
  }
}

class _GenerationResultList extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _GenerationResultList({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final itemCount = viewmodel.commandList.length;
        if (itemCount == 0) {
          return Center(
            child: Text(
              '暂无结果',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          );
        }
        final items = [
          for (var index = itemCount - 1; index >= 0; index -= 1)
            _workbenchGeneratedImageItem(
              viewmodel.commandList[index].value,
              displayIndex: itemCount - index,
              executing: viewmodel.commandList[index].isExecuting.value,
            ),
        ];
        return StudioGeneratedImageGallery(
          items: items,
          columnWidth: 220,
          scrollable: true,
          padding: const EdgeInsets.all(2),
          onOpen: (context, item) {
            StudioGeneratedImageViewerDialog.show(
              context,
              items: items,
              initialItemId: item.id,
              footerBuilder: _workbenchGeneratedImagePreviewFooter,
            );
          },
        );
      },
    );
  }
}

StudioGeneratedImageItem _workbenchGeneratedImageItem(
  InfoCardContent content, {
  required int displayIndex,
  required bool executing,
}) {
  final title = content.title.toString().trim();
  final order = content.contentOrderText?.toString().trim();
  final nameParts = <String>[
    if (order != null && order.isNotEmpty) order else '#$displayIndex',
    if (title.isNotEmpty) title,
  ];
  final name = nameParts.join(' ');
  final imagePath = executing ? null : content.imagePath?.trim();
  if (imagePath != null && imagePath.isNotEmpty) {
    return StudioGeneratedImageItem.file(
      id: 'workbench-$displayIndex',
      name: name,
      imagePath: imagePath,
      source: content,
    );
  }
  final bytes = executing ? null : content.imageBytes;
  if (bytes != null) {
    return StudioGeneratedImageItem.memory(
      id: 'workbench-$displayIndex',
      name: name,
      imageBytes: bytes,
      source: content,
    );
  }
  return StudioGeneratedImageItem(
    id: 'workbench-$displayIndex',
    name: name.isEmpty ? '#$displayIndex' : name,
    source: content,
    placeholder: executing
        ? '生成中'
        : content.info.trim().isNotEmpty
            ? content.info.trim()
            : '暂无图片',
  );
}

Widget _workbenchGeneratedImagePreviewFooter(
  BuildContext context,
  StudioGeneratedImageItem item,
  bool fullscreen,
) {
  final source = item.source;
  if (source is! InfoCardContent) return const SizedBox.shrink();
  if (source.title.trim().isEmpty &&
      source.info.trim().isEmpty &&
      source.additionalInfo.isEmpty) {
    return const SizedBox.shrink();
  }
  return StudioImagePreviewPromptScroll(
    key: const ValueKey('workbench-generated-image-detail-preview'),
    child: InfoCardDetailPanel(
      content: source,
      dense: true,
      showCopyActions: false,
      popOnCopy: false,
      padding: const EdgeInsets.all(10),
    ),
  );
}

class _CoreOutputSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CoreOutputSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    final samplerOptions =
        viewmodel.supportsSmeaControls ? samplers : samplersV4;
    final noiseOptions = viewmodel.isV4 ? noiseSchedulesV4 : noiseSchedules;

    return Column(
      key: const ValueKey('workbench-core-output-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.tune, title: '出图核心'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const ValueKey('workbench-model-control'),
          initialValue: _safeDropdownValue(config.model, models),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '生成模型',
            prefixIcon: Icon(Icons.auto_awesome_outlined),
          ),
          items: _items(models),
          onChanged: (value) {
            if (value != null) viewmodel.setModel(value);
          },
        ),
        const SizedBox(height: 10),
        if (viewmodel.supportsTransparency) ...[
          SwitchListTile(
            key: const ValueKey('workbench-transparent-background-control'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.layers_clear_outlined),
            title: const Text('透明背景'),
            subtitle: const Text('输出带 Alpha 通道的图片'),
            value: config.transparentBackground,
            onChanged: viewmodel.setTransparentBackground,
          ),
          const SizedBox(height: 4),
        ],
        if (viewmodel.supportsQualityPresets) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('workbench-quality-preset-control'),
            initialValue: _safeDropdownValue(
              config.qualityPreset,
              generationQualityPresets,
            ),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'V5 质量预设',
              prefixIcon: Icon(Icons.auto_awesome),
            ),
            items: _items(generationQualityPresets),
            onChanged: (value) {
              if (value != null) viewmodel.setQualityPreset(value);
            },
          ),
          const SizedBox(height: 10),
        ],
        if (viewmodel.supportsUcPresets) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('workbench-uc-preset-control'),
            initialValue: _safeDropdownValue(
              config.ucPresetMode,
              generationUcPresets,
            ),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'V5 排除内容预设',
              prefixIcon: Icon(Icons.shield_outlined),
            ),
            items: _items(generationUcPresets),
            onChanged: (value) {
              if (value != null) viewmodel.setUcPresetMode(value);
            },
          ),
          const SizedBox(height: 10),
        ],
        _SizeSelector(viewmodel: viewmodel),
        const SizedBox(height: 10),
        _SliderRow(
          key: const ValueKey('workbench-steps-slider'),
          label: 'Steps',
          valueText: config.steps.toString(),
          value: config.steps.toDouble(),
          min: 0,
          max: 28,
          divisions: 28,
          onChanged: (value) => viewmodel.setSteps(value.round()),
        ),
        _SliderRow(
          key: const ValueKey('workbench-scale-slider'),
          label: 'Prompt Guidance',
          valueText: config.scale.toStringAsFixed(1),
          value: config.scale,
          min: 0,
          max: 10,
          divisions: 100,
          onChanged: viewmodel.setScale,
        ),
        _SliderRow(
          key: const ValueKey('workbench-cfg-rescale-slider'),
          label: 'Prompt Guidance Rescale',
          valueText: config.cfgRescale.toStringAsFixed(2),
          value: config.cfgRescale,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: viewmodel.setCfgRescale,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const ValueKey('workbench-sampler-control'),
          initialValue: _safeDropdownValue(config.sampler, samplerOptions),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '采样器',
            prefixIcon: Icon(Icons.manage_search),
          ),
          items: _items(samplerOptions),
          onChanged: (value) {
            if (value != null) viewmodel.setSampler(value);
          },
        ),
        if (viewmodel.supportsNoiseSchedule) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('workbench-noise-schedule-control'),
            initialValue:
                _safeDropdownValue(config.noiseSchedule, noiseOptions),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '噪声调度',
              prefixIcon: Icon(Icons.waves),
            ),
            items: _items(noiseOptions),
            onChanged: (value) {
              if (value != null) viewmodel.setNoiseScheduler(value);
            },
          ),
        ],
      ],
    );
  }
}

class _SizeSelector extends StatefulWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _SizeSelector({required this.viewmodel});

  @override
  State<_SizeSelector> createState() => _SizeSelectorState();
}

class _SizeSelectorState extends State<_SizeSelector> {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  WorkbenchSingleImageParametersViewmodel get viewmodel => widget.viewmodel;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: viewmodel.draftWidthText);
    _heightController = TextEditingController(text: viewmodel.draftHeightText);
  }

  @override
  void didUpdateWidget(covariant _SizeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerText(_widthController, viewmodel.draftWidthText);
    _syncControllerText(_heightController, viewmodel.draftHeightText);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSize = viewmodel.selectedSize;
    return Column(
      key: const ValueKey('workbench-size-control'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '图像尺寸',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in defaultSizes)
              ChoiceChip(
                label: Text('${size.width} x ${size.height}'),
                selected: selectedSize == size,
                onSelected: (_) => viewmodel.setSize(size),
              ),
          ],
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: ValueKey('size-${selectedSize.width}-${selectedSize.height}'),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('workbench-width-field'),
                  controller: _widthController,
                  decoration: const InputDecoration(
                    labelText: '宽度',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: viewmodel.setDraftWidthText,
                  onFieldSubmitted: (_) => viewmodel.commitDraftSize(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('workbench-height-field'),
                  controller: _heightController,
                  decoration: const InputDecoration(
                    labelText: '高度',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: viewmodel.setDraftHeightText,
                  onFieldSubmitted: (_) => viewmodel.commitDraftSize(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _syncControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }
}

class _PromptControlSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _PromptControlSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    return Column(
      key: const ValueKey('workbench-prompt-control-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('workbench-negative-prompt-editor'),
          child: PromptTagEditor(
            value: config.negativePrompt,
            label: '负面提示词',
            emptyText: '暂无负面提示词',
            negative: true,
            onChanged: viewmodel.setNegativePrompt,
          ),
        ),
      ],
    );
  }
}

class _ReferenceInputSection extends StatefulWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _ReferenceInputSection({required this.viewmodel});

  @override
  State<_ReferenceInputSection> createState() => _ReferenceInputSectionState();
}

class _ReferenceInputSectionState extends State<_ReferenceInputSection> {
  bool _vibeEnabled = false;
  bool _i2iEnabled = false;
  late String _lastVibeSignature;

  @override
  void initState() {
    super.initState();
    _lastVibeSignature = _vibeSignature;
    _vibeEnabled =
        widget.viewmodel.vibeEnabled && widget.viewmodel.hasVibeReferences;
    _i2iEnabled = widget.viewmodel.hasI2iImage;
  }

  @override
  void didUpdateWidget(covariant _ReferenceInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final vibeSignature = _vibeSignature;
    if (vibeSignature != _lastVibeSignature) {
      _lastVibeSignature = vibeSignature;
      if (widget.viewmodel.vibeEnabled && widget.viewmodel.hasVibeReferences) {
        _vibeEnabled = true;
      }
    }
    if (!oldWidget.viewmodel.hasI2iImage && widget.viewmodel.hasI2iImage) {
      _i2iEnabled = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    return ListenableBuilder(
      listenable: viewmodel.payloadConfig.i2iConfig,
      builder: (context, _) {
        final payload = viewmodel.payloadConfig;
        final i2iConfig = payload.i2iConfig;
        final vibeCount =
            payload.vibeConfigList.length + payload.vibeConfigListV4.length;
        final vibeSupported = viewmodel.supportsVibeTransfer;
        final vibeSectionExpanded = vibeSupported && _vibeEnabled;
        final hasSourceImage = viewmodel.hasI2iImage;
        final sourceSize = i2iConfig.width > 0 && i2iConfig.height > 0
            ? '${i2iConfig.width} x ${i2iConfig.height}'
            : '已选择';
        return Column(
          key: const ValueKey('workbench-reference-input-section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReferenceSectionHeader(
              icon: Icons.auto_awesome_outlined,
              title: '风格参考（Vibe）',
              chips: [
                if (vibeCount > 0)
                  StudioChip(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Vibe $vibeCount',
                    selected: vibeSupported && viewmodel.vibeEnabled,
                  ),
                if (!vibeSupported)
                  const StudioChip(
                    icon: Icons.block_outlined,
                    label: '当前模型不支持',
                  ),
              ],
              toggle: StudioChip(
                key: const ValueKey('workbench-vibe-section-toggle'),
                icon: !vibeSupported
                    ? Icons.lock_outline
                    : vibeSectionExpanded
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                label: !vibeSupported
                    ? '不可用'
                    : vibeSectionExpanded
                        ? '关闭'
                        : '开启',
                selected: vibeSectionExpanded,
                onTap: vibeSupported ? _toggleVibeEnabled : null,
              ),
            ),
            if (!vibeSupported) ...[
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('workbench-vibe-unsupported-hint'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: StudioTokens.surface2,
                  borderRadius:
                      BorderRadius.circular(StudioTokens.radiusMedium),
                  border: Border.all(color: StudioTokens.cardOutline),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: StudioTokens.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vibeCount > 0
                            ? 'V5 暂不支持 Vibe；已保留 $vibeCount 条配置，切回 V4 / V4.5 后可继续使用。'
                            : 'V5 暂不支持 Vibe；切换到 V4 / V4.5 后即可添加风格参考。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: StudioTokens.textMuted,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            StudioAnimatedPresence(
              key: const ValueKey('workbench-vibe-presence'),
              visible: vibeSectionExpanded,
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: const ValueKey('workbench-vibe-editor'),
                    child: VibeConfigV4ListView(
                      viewmodel: VibeConfigV4ListViewmodel(),
                      vibeEnabled: viewmodel.vibeEnabled,
                      onVibeEnabledChanged: viewmodel.setVibeEnabled,
                      onConfigChanged: viewmodel.notifyReferenceInputsChanged,
                      compact: true,
                      showEnabledSwitch: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReferenceSectionHeader(
              icon: Icons.compare_outlined,
              title: hasSourceImage ? '图生图已配置' : '图生图（可选）',
              chips: [
                if (_i2iEnabled)
                  StudioChip(
                    icon: hasSourceImage
                        ? Icons.image_outlined
                        : Icons.add_photo_alternate_outlined,
                    label: hasSourceImage ? '底图 $sourceSize' : '未选择底图',
                    selected: hasSourceImage,
                  ),
              ],
              toggle: StudioChip(
                key: const ValueKey('workbench-i2i-section-toggle'),
                icon: _i2iEnabled
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                label: _i2iEnabled ? '关闭' : '开启',
                selected: _i2iEnabled,
                onTap: _toggleI2iEnabled,
              ),
            ),
            StudioAnimatedPresence(
              key: const ValueKey('workbench-i2i-presence'),
              visible: _i2iEnabled,
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: const ValueKey('workbench-i2i-editor'),
                    child: I2iConfigView(
                      key: const ValueKey('workbench-i2i-config-view'),
                      viewmodel: I2iTabViewmodel().createI2iViewmodel(),
                      compact: true,
                      showPromptOverride: false,
                      showSizeControl: false,
                      showPresetControl: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String get _vibeSignature {
    final payload = widget.viewmodel.payloadConfig;
    final encodings = [
      for (final vibe in payload.vibeConfigListV4) vibe.vibeB64.trim(),
      for (final vibe in payload.vibeConfigList) vibe.imageB64.trim(),
    ].join('|');
    return '${payload.generationRuntimeState.vibeEnabled}|$encodings';
  }

  void _toggleVibeEnabled() {
    final nextEnabled = !_vibeEnabled;
    widget.viewmodel.setVibeEnabled(nextEnabled);
    setState(() {
      _vibeEnabled = nextEnabled;
      _lastVibeSignature = _vibeSignature;
    });
  }

  void _toggleI2iEnabled() {
    final nextEnabled = !_i2iEnabled;
    if (!nextEnabled) {
      widget.viewmodel.disableI2iInputs();
    }
    setState(() => _i2iEnabled = nextEnabled);
  }
}

class _ReferenceSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> chips;
  final Widget toggle;

  const _ReferenceSectionHeader({
    required this.icon,
    required this.title,
    required this.chips,
    required this.toggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _SectionTitle(
              icon: icon,
              title: title,
            ),
          ),
          for (final chip in chips) ...[
            chip,
            const SizedBox(width: 8),
          ],
          toggle,
        ],
      ),
    );
  }
}

class _CharacterSection extends StatefulWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CharacterSection({required this.viewmodel});

  @override
  State<_CharacterSection> createState() => _CharacterSectionState();
}

class _CharacterSectionState extends State<_CharacterSection> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final characters = viewmodel.payloadConfig.characterConfigList;
    final expandedIndex = _expandedIndex != null &&
            _expandedIndex! >= 0 &&
            _expandedIndex! < characters.length
        ? _expandedIndex
        : null;
    return Column(
      key: const ValueKey('workbench-character-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionTitle(icon: Icons.group_outlined, title: '角色词'),
            ),
            StudioIconButton(
              key: const ValueKey('workbench-add-character'),
              tooltip: '新增角色',
              icon: Icons.person_add_alt_1_outlined,
              onPressed: characters.length >= viewmodel.maxCharacterCount
                  ? null
                  : _addCharacter,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.merge_type),
          title: const Text('手写 Prompt 覆盖时保留角色词'),
          value: viewmodel.payloadConfig.useCharacterPromptWithOverride,
          onChanged: viewmodel.setUseCharacterPromptWithOverride,
        ),
        if (characters.isNotEmpty && viewmodel.supportsAutoPosition) ...[
          _CharacterPositionEditor(
            viewmodel: viewmodel,
            selectedIndex: expandedIndex ?? 0,
            onSelected: (index) {
              setState(() => _expandedIndex = index);
            },
          ),
          const SizedBox(height: 12),
        ],
        if (characters.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: StudioTokens.surface3,
              borderRadius: _characterCardRadius,
              border: StudioTokens.cardBorder,
            ),
            child: Text(
              '暂无角色。可以从左侧素材库添加角色，或导入 NovelAI PNG / JSON 解析角色提示词。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final width = _cardWidthFor(constraints.maxWidth, gap);
              return Wrap(
                key: const ValueKey('workbench-character-card-strip'),
                spacing: gap,
                runSpacing: 12,
                children: [
                  for (final (index, character) in characters.indexed)
                    _CharacterTileCard(
                      index: index,
                      width: width,
                      character: character,
                      selected: expandedIndex == index,
                      onTap: () => _selectCharacter(index),
                      onDrop: (data) {
                        viewmodel.applyCharacterDrop(index, data);
                        setState(() => _expandedIndex = index);
                      },
                    ),
                ],
              );
            },
          ),
        if (expandedIndex != null) ...[
          const SizedBox(height: 12),
          _CharacterExpandedCard(
            index: expandedIndex,
            character: characters[expandedIndex],
            viewmodel: viewmodel,
            onRemove: () => _removeCharacter(expandedIndex),
          ),
        ],
      ],
    );
  }

  void _selectCharacter(int index) {
    setState(() {
      _expandedIndex = _expandedIndex == index ? null : index;
    });
  }

  void _addCharacter() {
    final nextIndex = widget.viewmodel.payloadConfig.characterConfigList.length;
    widget.viewmodel.addCharacter();
    setState(() => _expandedIndex = nextIndex);
  }

  void _removeCharacter(int index) {
    setState(() {
      if (_expandedIndex == index) {
        _expandedIndex = null;
      } else if (_expandedIndex != null && _expandedIndex! > index) {
        _expandedIndex = _expandedIndex! - 1;
      }
    });
    widget.viewmodel.removeCharacter(index);
  }

  double _cardWidthFor(double maxWidth, double gap) {
    final available = maxWidth.isFinite ? maxWidth : 852.0;
    final maxCount = widget.viewmodel.maxCharacterCount;
    final rawWidth = (available - gap * (maxCount - 1)) / maxCount;
    return rawWidth.clamp(96.0, 132.0).toDouble();
  }
}

class _CharacterPositionEditor extends StatefulWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _CharacterPositionEditor({
    required this.viewmodel,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<_CharacterPositionEditor> createState() =>
      _CharacterPositionEditorState();
}

class _CharacterPositionEditorState extends State<_CharacterPositionEditor> {
  int? _draggingIndex;

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final characters = viewmodel.payloadConfig.characterConfigList;
    final selectedIndex =
        widget.selectedIndex.clamp(0, characters.length - 1).toInt();
    final overlaps = viewmodel.overlappingCharacterIndexes();
    final size = viewmodel.selectedSize;
    final aspectRatio = (size.width / size.height).clamp(0.55, 2.2).toDouble();
    final freeform = viewmodel.supportsFreeformCharacterPosition;
    final custom = !viewmodel.config.autoPosition;

    return Container(
      key: ValueKey(
        freeform
            ? 'workbench-v5-character-position-canvas'
            : 'workbench-grid-character-position-canvas',
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: _characterCardRadius,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                freeform ? Icons.open_with : Icons.grid_4x4_outlined,
                size: 19,
                color: StudioTokens.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  freeform ? 'V5 自由角色位置' : '角色格点位置',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              ChoiceChip(
                label: const Text('AI 自选'),
                selected: !custom,
                onSelected: (_) => viewmodel.setAutoPosition(true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('自定义'),
                selected: custom,
                onSelected: (_) => viewmodel.setAutoPosition(false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            custom
                ? freeform
                    ? '拖动编号或点击画布，可精确到 0.1%。'
                    : '拖动编号或点击画布，位置会吸附到 5×5 格点。'
                : 'AI 自选已开启；拖动画布会自动切换为自定义。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StudioTokens.textMuted,
                ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const maxHeight = 230.0;
              final canvasWidth = min(
                constraints.maxWidth,
                maxHeight * aspectRatio,
              );
              final canvasHeight = canvasWidth / aspectRatio;
              return Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: canvasWidth,
                  height: canvasHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final index = _nearestCharacter(
                            details.localPosition,
                            Size(canvasWidth, canvasHeight),
                          ) ??
                          selectedIndex;
                      _moveCharacter(
                        index,
                        details.localPosition,
                        Size(canvasWidth, canvasHeight),
                      );
                    },
                    onPanStart: (details) {
                      final index = _nearestCharacter(
                            details.localPosition,
                            Size(canvasWidth, canvasHeight),
                          ) ??
                          selectedIndex;
                      _draggingIndex = index;
                      _moveCharacter(
                        index,
                        details.localPosition,
                        Size(canvasWidth, canvasHeight),
                      );
                    },
                    onPanUpdate: (details) {
                      final index = _draggingIndex;
                      if (index == null) return;
                      _moveCharacter(
                        index,
                        details.localPosition,
                        Size(canvasWidth, canvasHeight),
                      );
                    },
                    onPanEnd: (_) => _draggingIndex = null,
                    onPanCancel: () => _draggingIndex = null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: StudioTokens.surface2,
                        borderRadius:
                            BorderRadius.circular(StudioTokens.radiusSmall),
                        border: Border.all(
                          color: custom
                              ? StudioTokens.primary.withValues(alpha: 0.7)
                              : StudioTokens.border,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(StudioTokens.radiusSmall),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CharacterPositionGridPainter(
                                  freeform: freeform,
                                  active: custom,
                                ),
                              ),
                            ),
                            for (final (index, character) in characters.indexed)
                              if (character.enabled)
                                _CharacterPositionMarker(
                                  index: index,
                                  position: viewmodel.characterPosition(index),
                                  canvasSize: Size(canvasWidth, canvasHeight),
                                  selected: index == selectedIndex,
                                  warning: overlaps.contains(index),
                                  label:
                                      viewmodel.characterPositionLabel(index),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (overlaps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '角色 ${overlaps.map((index) => index + 1).join('、')} 距离过近，可能降低角色分离效果。',
              key: const ValueKey(
                  'workbench-character-position-overlap-warning'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.warning,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  int? _nearestCharacter(Offset localPosition, Size canvasSize) {
    var nearestDistance = 28.0;
    int? nearest;
    for (final (index, character)
        in widget.viewmodel.payloadConfig.characterConfigList.indexed) {
      if (!character.enabled) continue;
      final position = widget.viewmodel.characterPosition(index);
      final marker = Offset(
        position.x * canvasSize.width,
        position.y * canvasSize.height,
      );
      final distance = (marker - localPosition).distance;
      if (distance <= nearestDistance) {
        nearestDistance = distance;
        nearest = index;
      }
    }
    return nearest;
  }

  void _moveCharacter(int index, Offset localPosition, Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    widget.onSelected(index);
    if (widget.viewmodel.config.autoPosition) {
      widget.viewmodel.setAutoPosition(false);
    }
    widget.viewmodel.setCharacterPosition(
      index,
      Point<double>(
        (localPosition.dx / canvasSize.width).clamp(0.0, 1.0).toDouble(),
        (localPosition.dy / canvasSize.height).clamp(0.0, 1.0).toDouble(),
      ),
    );
  }
}

class _CharacterPositionMarker extends StatelessWidget {
  static const diameter = 30.0;

  final int index;
  final Point<double> position;
  final Size canvasSize;
  final bool selected;
  final bool warning;
  final String label;

  const _CharacterPositionMarker({
    required this.index,
    required this.position,
    required this.canvasSize,
    required this.selected,
    required this.warning,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? StudioTokens.warning
        : selected
            ? StudioTokens.primary
            : StudioTokens.active;
    return Positioned(
      key: ValueKey('workbench-character-position-marker-$index'),
      left: position.x * canvasSize.width - diameter / 2,
      top: position.y * canvasSize.height - diameter / 2,
      child: IgnorePointer(
        child: Tooltip(
          message: '角色 ${index + 1} · $label',
          child: Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: StudioTokens.textPrimary,
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.surface1,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterPositionGridPainter extends CustomPainter {
  final bool freeform;
  final bool active;

  const _CharacterPositionGridPainter({
    required this.freeform,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = StudioTokens.border.withValues(alpha: active ? 0.75 : 0.4)
      ..strokeWidth = 1;
    final divisions =
        freeform ? const [1 / 3, 2 / 3] : const [0.2, 0.4, 0.6, 0.8];
    for (final value in divisions) {
      canvas
        ..drawLine(
          Offset(size.width * value, 0),
          Offset(size.width * value, size.height),
          paint,
        )
        ..drawLine(
          Offset(0, size.height * value),
          Offset(size.width, size.height * value),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _CharacterPositionGridPainter oldDelegate) {
    return oldDelegate.freeform != freeform || oldDelegate.active != active;
  }
}

class _CharacterTileCard extends StatelessWidget {
  final int index;
  final double width;
  final CharacterConfig character;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<StudioWorkbenchCharacterDropData> onDrop;

  const _CharacterTileCard({
    required this.index,
    required this.width,
    required this.character,
    required this.selected,
    required this.onTap,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    final name = _characterName(character, index);
    final textTheme = Theme.of(context).textTheme;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is StudioWorkbenchCharacterDropData,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is StudioWorkbenchCharacterDropData) {
          onDrop(data);
        }
      },
      builder: (context, candidates, rejected) {
        final dropActive = candidates.isNotEmpty;
        return StudioInteractiveSurface(
          borderRadius: _characterCardRadius,
          hoverScale: 1.014,
          hoverBorderColor: StudioTokens.primary.withValues(alpha: 0.36),
          hoverOverlayColor: StudioTokens.primary.withValues(alpha: 0.025),
          child: SizedBox(
            width: width,
            height: 172,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('workbench-character-card-$index'),
                borderRadius: _characterCardRadius,
                onTap: onTap,
                child: AnimatedContainer(
                  duration: StudioMotionScope.duration(
                    context,
                    StudioMotionTokens.fast,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dropActive || selected
                        ? StudioTokens.surface2
                        : StudioTokens.surface3,
                    borderRadius: _characterCardRadius,
                    border: Border.all(
                      color: dropActive || selected
                          ? StudioTokens.primary
                          : character.enabled
                              ? StudioTokens.border
                              : StudioTokens.border.withValues(alpha: 0.5),
                      width: dropActive || selected ? 2 : 1,
                    ),
                  ),
                  child: Opacity(
                    opacity: character.enabled ? 1 : 0.52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              character.enabled
                                  ? Icons.person_outline
                                  : Icons.person_off_outlined,
                              size: 18,
                              color: selected
                                  ? StudioTokens.primary
                                  : StudioTokens.textMuted,
                            ),
                            const Spacer(),
                            Icon(
                              selected ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: StudioTokens.textMuted,
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: textTheme.displaySmall?.copyWith(
                                color: selected
                                    ? StudioTokens.primary
                                    : StudioTokens.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: StudioTokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _characterName(CharacterConfig character, int index) {
    final name = character.name.trim();
    return name.isEmpty ? '角色 ${index + 1}' : name;
  }
}

class _CharacterExpandedCard extends StatelessWidget {
  final int index;
  final CharacterConfig character;
  final WorkbenchSingleImageParametersViewmodel viewmodel;
  final VoidCallback onRemove;

  const _CharacterExpandedCard({
    required this.index,
    required this.character,
    required this.viewmodel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = _characterName(character, index);
    return Container(
      key: ValueKey('workbench-character-expanded-card-$index'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: _characterCardRadius,
        border: Border.all(
          color: character.enabled
              ? StudioTokens.primary.withValues(alpha: 0.72)
              : StudioTokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StudioChip(
                icon: Icons.person_outline,
                label: name,
                selected: character.enabled,
              ),
              const Spacer(),
              Text(
                character.enabled ? '启用' : '停用',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: character.enabled
                          ? StudioTokens.primary
                          : StudioTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: character.enabled,
                onChanged: (value) =>
                    viewmodel.setCharacterEnabled(index, value),
              ),
              const SizedBox(width: 4),
              StudioIconButton(
                tooltip: '移除角色',
                icon: Icons.close,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('workbench-character-name-$index'),
            initialValue: name,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: '角色名',
              prefixIcon: Icon(Icons.drive_file_rename_outline),
            ),
            onChanged: (value) => viewmodel.setCharacterName(index, value),
          ),
          const SizedBox(height: 10),
          _CharacterPromptStack(
            characterIndex: index,
            character: character,
            viewmodel: viewmodel,
          ),
        ],
      ),
    );
  }

  String _characterName(CharacterConfig character, int index) {
    final name = character.name.trim();
    return name.isEmpty ? '角色 ${index + 1}' : name;
  }
}

class _CharacterPromptStack extends StatelessWidget {
  final int characterIndex;
  final CharacterConfig character;
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CharacterPromptStack({
    required this.characterIndex,
    required this.character,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = character.positivePromptConfig.strs;
    final displayBlocks = blocks.isEmpty ? const [''] : blocks;
    final tagified = viewmodel.isCharacterPromptTagified(characterIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StudioChip(
              icon: Icons.badge_outlined,
              label: 'Prompt 块',
              selected: blocks.isNotEmpty,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '可拖入角色、动作、服装等素材并叠加',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '标签化',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tagified
                        ? StudioTokens.primary
                        : StudioTokens.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Switch(
              key:
                  ValueKey('workbench-character-tagify-toggle-$characterIndex'),
              value: tagified,
              onChanged: (value) =>
                  viewmodel.setCharacterPromptTagified(characterIndex, value),
              activeThumbColor: StudioTokens.primary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tagified)
          Container(
            key: ValueKey('workbench-character-tagified-tags-$characterIndex'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: StudioTokens.surface2,
              borderRadius: StudioTokens.radiusSlot,
              border: Border.all(color: StudioTokens.primary.withAlpha(180)),
            ),
            child: PromptTagDisplay(
              text: blocks.join(', '),
              defaultTranslated: true,
              dense: true,
              enableTagActions: true,
              emptyText: '当前角色没有可标签化的角色词',
            ),
          )
        else ...[
          _CharacterPromptDropTarget(
            characterIndex: characterIndex,
            targetIndex: 0,
            viewmodel: viewmodel,
          ),
          for (final (blockIndex, block) in displayBlocks.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  _CharacterPromptBlockDraggable(
                    characterIndex: characterIndex,
                    blockIndex: blockIndex,
                    prompt: block,
                    enabled: blocks.isNotEmpty,
                    child: _CharacterPromptBlockRow(
                      characterIndex: characterIndex,
                      blockIndex: blockIndex,
                      prompt: block,
                      viewmodel: viewmodel,
                      canMoveUp: blocks.isNotEmpty && blockIndex > 0,
                      canMoveDown:
                          blocks.isNotEmpty && blockIndex < blocks.length - 1,
                      canRemove: blocks.isNotEmpty,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _CharacterPromptDropTarget(
                    characterIndex: characterIndex,
                    targetIndex: blockIndex + 1,
                    viewmodel: viewmodel,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _CharacterPromptDropTarget extends StatelessWidget {
  final int characterIndex;
  final int targetIndex;
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _CharacterPromptDropTarget({
    required this.characterIndex,
    required this.targetIndex,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is _CharacterPromptBlockDropData) {
          return data.characterIndex == characterIndex;
        }
        return data is StudioWorkbenchCharacterDropData &&
            data.characterPrompt.trim().isNotEmpty;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is _CharacterPromptBlockDropData) {
          viewmodel.moveCharacterPromptBlock(
            characterIndex,
            data.blockIndex,
            targetIndex,
          );
          return;
        }
        if (data is StudioWorkbenchCharacterDropData) {
          viewmodel.insertCharacterPromptBlock(
            characterIndex,
            targetIndex,
            data.characterPrompt,
          );
        }
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          key: ValueKey(
            'workbench-character-prompt-drop-$characterIndex-$targetIndex',
          ),
          duration: StudioMotionScope.duration(
            context,
            StudioMotionTokens.fast,
          ),
          margin: const EdgeInsets.only(bottom: 6),
          height: active ? 32 : 18,
          decoration: BoxDecoration(
            color: active
                ? StudioTokens.primary.withAlpha(28)
                : StudioTokens.surface2.withAlpha(120),
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(
              color: active ? StudioTokens.primary : StudioTokens.cardOutline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            active ? '松开叠加到这里' : '拖到这里',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: active ? StudioTokens.primary : StudioTokens.textMuted,
                ),
          ),
        );
      },
    );
  }
}

class _CharacterPromptBlockDraggable extends StatelessWidget {
  final int characterIndex;
  final int blockIndex;
  final String prompt;
  final bool enabled;
  final Widget child;

  const _CharacterPromptBlockDraggable({
    required this.characterIndex,
    required this.blockIndex,
    required this.prompt,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final label = 'Prompt 块 ${blockIndex + 1}';
    return LongPressDraggable<Object>(
      data: _CharacterPromptBlockDropData(
        characterIndex: characterIndex,
        blockIndex: blockIndex,
        label: label,
        characterPrompt: prompt,
      ),
      feedback: _CharacterPromptDragFeedback(label: label),
      childWhenDragging: Opacity(opacity: 0.38, child: child),
      child: child,
    );
  }
}

class _CharacterPromptBlockDropData
    implements StudioWorkbenchCharacterDropData {
  final int characterIndex;
  final int blockIndex;

  @override
  final String label;

  @override
  final String characterPrompt;

  const _CharacterPromptBlockDropData({
    required this.characterIndex,
    required this.blockIndex,
    required this.label,
    required this.characterPrompt,
  });

  @override
  String get characterName => '';
}

class _CharacterPromptDragFeedback extends StatelessWidget {
  final String label;

  const _CharacterPromptDragFeedback({required this.label});

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

class _CharacterPromptBlockRow extends StatelessWidget {
  final int characterIndex;
  final int blockIndex;
  final String prompt;
  final WorkbenchSingleImageParametersViewmodel viewmodel;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;

  const _CharacterPromptBlockRow({
    required this.characterIndex,
    required this.blockIndex,
    required this.prompt,
    required this.viewmodel,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(
        'workbench-character-prompt-block-$characterIndex-$blockIndex',
      ),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
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
                label: '块 ${blockIndex + 1}',
              ),
              const Spacer(),
              StudioIconButton(
                key: ValueKey(
                  'workbench-character-prompt-up-$characterIndex-$blockIndex',
                ),
                tooltip: '上移',
                icon: Icons.keyboard_arrow_up,
                onPressed: canMoveUp
                    ? () => viewmodel.moveCharacterPromptBlock(
                          characterIndex,
                          blockIndex,
                          blockIndex - 1,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                key: ValueKey(
                  'workbench-character-prompt-down-$characterIndex-$blockIndex',
                ),
                tooltip: '下移',
                icon: Icons.keyboard_arrow_down,
                onPressed: canMoveDown
                    ? () => viewmodel.moveCharacterPromptBlock(
                          characterIndex,
                          blockIndex,
                          blockIndex + 2,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                key: ValueKey(
                  'workbench-character-prompt-remove-$characterIndex-$blockIndex',
                ),
                tooltip: '移除',
                icon: Icons.close,
                onPressed: canRemove
                    ? () => viewmodel.removeCharacterPromptBlock(
                          characterIndex,
                          blockIndex,
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: _fieldKey,
            child: PromptTagEditor(
              value: prompt,
              label: '角色词',
              dense: true,
              onChanged: (value) => viewmodel.setCharacterPromptBlock(
                characterIndex,
                blockIndex,
                value,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Key get _fieldKey {
    if (blockIndex == 0) {
      return ValueKey('workbench-character-prompt-$characterIndex');
    }
    return ValueKey('workbench-character-prompt-$characterIndex-$blockIndex');
  }
}

class _AdvancedSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _AdvancedSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    return Column(
      key: const ValueKey('workbench-advanced-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.tune_outlined, title: '高级'),
        if (viewmodel.supportsLegacyUc)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.do_not_disturb),
            title: const Text('旧版提示词条件模式'),
            value: config.legacyUc,
            onChanged: viewmodel.setLegacyUc,
          ),
        if (viewmodel.supportsAutoPosition)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.not_listed_location_outlined),
            title: const Text('自动角色位置'),
            value: config.autoPosition,
            onChanged: viewmodel.setAutoPosition,
          ),
        if (viewmodel.supportsSmeaControls)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.keyboard_double_arrow_right),
            title: const Text('SMEA'),
            value: config.sm,
            onChanged: viewmodel.setSm,
          ),
        if (viewmodel.supportsSmeaControls)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.keyboard_double_arrow_right),
            title: const Text('SMEA DYN'),
            value: config.smDyn,
            onChanged: viewmodel.setSmDyn,
          ),
        if (viewmodel.supportsDynamicThresholding)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.dynamic_form_outlined),
            title: const Text('动态阈值'),
            value: config.dynamicThresholding,
            onChanged: viewmodel.setDynamicThresholding,
          ),
      ],
    );
  }
}

class _RandomnessSection extends StatelessWidget {
  final WorkbenchSingleImageParametersViewmodel viewmodel;

  const _RandomnessSection({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final config = viewmodel.config;
    return Column(
      key: const ValueKey('workbench-randomness-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.shuffle, title: '随机性'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.casino_outlined),
          title: const Text('使用随机种子'),
          value: config.randomSeed,
          onChanged: viewmodel.setRandomSeedEnabled,
        ),
        StudioAnimatedPresence(
          key: const ValueKey('workbench-seed-presence'),
          visible: !config.randomSeed,
          builder: (context) => KeyedSubtree(
            key: ValueKey('seed-${config.seed}'),
            child: TextFormField(
              key: const ValueKey('workbench-seed-field'),
              initialValue: config.seed.toString(),
              decoration: const InputDecoration(
                labelText: '种子',
                prefixIcon: Icon(Icons.tag),
              ),
              keyboardType: TextInputType.number,
              onChanged: viewmodel.setSeed,
            ),
          ),
        ),
        if (viewmodel.supportsVarietyPlus)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.add),
            title: const Text('Variety+'),
            value: config.varietyPlus,
            onChanged: viewmodel.setVarietyPlus,
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: StudioTokens.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: StudioTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(
              valueText,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: StudioTokens.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

List<DropdownMenuItem<String>> _items(List<String> values) {
  return values
      .map(
        (value) => DropdownMenuItem<String>(
          value: value,
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      )
      .toList(growable: false);
}

String? _safeDropdownValue(String value, List<String> options) {
  return options.contains(value) ? value : null;
}
