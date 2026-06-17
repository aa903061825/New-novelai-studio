import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_studio/core/constants/parameters.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/models/generation_payload_document.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';

class StudioBatchPage extends StatefulWidget {
  final ProductionQueueViewModel viewModel;

  const StudioBatchPage({
    super.key,
    required this.viewModel,
  });

  @override
  State<StudioBatchPage> createState() => _StudioBatchPageState();
}

class _StudioBatchPageState extends State<StudioBatchPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.load());
  }

  @override
  void didUpdateWidget(StudioBatchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      unawaited(widget.viewModel.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      backgroundColor: StudioTokens.surface1,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1180;
          if (compact) {
            return ListView(
              key: const ValueKey('studio-batch-page-compact'),
              padding: const EdgeInsets.all(12),
              children: [
                _ViewModelRebuildGate(
                  viewModel: viewModel,
                  selector: _queueOverviewRebuildToken,
                  builder: (context) => _QueueOverviewPanel(
                    viewModel: viewModel,
                  ),
                ),
                const SizedBox(height: 12),
                _ViewModelRebuildGate(
                  viewModel: viewModel,
                  selector: _settingsRebuildToken,
                  builder: (context) => _ExecutionSettingsPanel(
                    viewModel: viewModel,
                  ),
                ),
                const SizedBox(height: 12),
                _ViewModelRebuildGate(
                  viewModel: viewModel,
                  selector: _tasksRebuildToken,
                  builder: (context) => _TaskListPanel(
                    viewModel: viewModel,
                    expandList: false,
                  ),
                ),
                const SizedBox(height: 12),
                _ViewModelRebuildGate(
                  viewModel: viewModel,
                  selector: _tasksRebuildToken,
                  builder: (context) => _ProductionResultsPanel(
                    viewModel: viewModel,
                    expandBody: false,
                  ),
                ),
              ],
            );
          }

          return Padding(
            key: const ValueKey('studio-batch-page-wide'),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _ViewModelRebuildGate(
                        viewModel: viewModel,
                        selector: _queueOverviewRebuildToken,
                        builder: (context) => _QueueOverviewPanel(
                          viewModel: viewModel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ViewModelRebuildGate(
                        viewModel: viewModel,
                        selector: _settingsRebuildToken,
                        builder: (context) => _ExecutionSettingsPanel(
                          viewModel: viewModel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _ViewModelRebuildGate(
                          viewModel: viewModel,
                          selector: _tasksRebuildToken,
                          builder: (context) => _TaskListPanel(
                            viewModel: viewModel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: _ViewModelRebuildGate(
                    viewModel: viewModel,
                    selector: _tasksRebuildToken,
                    builder: (context) => _ProductionResultsPanel(
                      viewModel: viewModel,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ViewModelRebuildGate<T> extends StatefulWidget {
  final ProductionQueueViewModel viewModel;
  final T Function(ProductionQueueViewModel viewModel) selector;
  final WidgetBuilder builder;

  const _ViewModelRebuildGate({
    required this.viewModel,
    required this.selector,
    required this.builder,
  });

  @override
  State<_ViewModelRebuildGate<T>> createState() =>
      _ViewModelRebuildGateState<T>();
}

class _ViewModelRebuildGateState<T> extends State<_ViewModelRebuildGate<T>> {
  late T _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.selector(widget.viewModel);
    widget.viewModel.addListener(_handleViewModelChanged);
  }

  @override
  void didUpdateWidget(_ViewModelRebuildGate<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_handleViewModelChanged);
      widget.viewModel.addListener(_handleViewModelChanged);
    }
    _selectedValue = widget.selector(widget.viewModel);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleViewModelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }

  void _handleViewModelChanged() {
    final nextValue = widget.selector(widget.viewModel);
    if (nextValue == _selectedValue) return;
    setState(() {
      _selectedValue = nextValue;
    });
  }
}

Object _queueOverviewRebuildToken(ProductionQueueViewModel viewModel) {
  final plan = viewModel.selectedPlan;
  return (
    planId: plan?.id,
    planName: plan?.name,
    planFingerprint: plan?.planFingerprint,
    totalTasks: viewModel.totalTasks,
    completedTasks: viewModel.completedTasks,
    failedTasks: viewModel.failedTasks,
    abnormalTasks: viewModel.abnormalTasks,
    runningTasks: viewModel.runningTasks,
    isExecuting: viewModel.isExecuting,
    pauseRequested: viewModel.pauseRequested,
    isPaused: viewModel.isPaused,
    canPause: viewModel.canPause,
    canResume: viewModel.canResume,
    canStop: viewModel.canStop,
    canClearCurrentPlan: viewModel.canClearCurrentPlan,
    canRenameSelectedPlan: viewModel.canRenameSelectedPlan,
  );
}

Object _settingsRebuildToken(ProductionQueueViewModel viewModel) {
  final selectedTask = viewModel.selectedTask;
  return (
    selectedTaskId: selectedTask?.id,
    selectedTaskUpdatedAt:
        selectedTask?.updatedAt.toUtc().microsecondsSinceEpoch,
    isExecuting: viewModel.isExecuting,
    useOriginalModel: viewModel.useOriginalModel,
    useOriginalSize: viewModel.useOriginalSize,
    useOriginalSampler: viewModel.useOriginalSampler,
    useOriginalSteps: viewModel.useOriginalSteps,
    useOriginalScale: viewModel.useOriginalScale,
    useOriginalSeed: viewModel.useOriginalSeed,
    batchModel: viewModel.batchModel,
    batchSampler: viewModel.batchSampler,
    batchWidth: viewModel.batchWidth,
    batchHeight: viewModel.batchHeight,
    batchSteps: viewModel.batchSteps,
    batchScale: viewModel.batchScale,
    batchSeed: viewModel.batchSeed,
    requestIntervalSeconds: viewModel.requestIntervalSeconds,
    requestIntervalRandomRangeSeconds:
        viewModel.requestIntervalRandomRangeSeconds,
    retryCount: viewModel.retryCount,
    retryIndefinitely: viewModel.retryIndefinitely,
    outputDirectory: viewModel.outputDirectory,
    canPickOutputDirectory: viewModel.canPickOutputDirectory,
  );
}

Object _tasksRebuildToken(ProductionQueueViewModel viewModel) {
  return (
    selectedTaskId: viewModel.selectedTask?.id,
    tasks: viewModel.selectedPlan?.tasks,
  );
}

Future<void> _exportSelectedTaskJson(
  BuildContext context,
  ProductionQueueViewModel viewModel,
) async {
  try {
    final exported = await viewModel.exportSelectedTaskJson();
    if (!context.mounted) return;
    _showProductionSnack(
      context,
      exported ? '已导出 JSON' : '已取消导出 JSON',
    );
  } catch (error) {
    if (!context.mounted) return;
    _showProductionSnack(context, '导出 JSON 失败：$error');
  }
}

void _showProductionSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _renameProductionPlan(
  BuildContext context,
  ProductionQueueViewModel viewModel,
) async {
  final initialLabel = viewModel.selectedPlan?.name ?? '';
  final label = await _showProductionRenameDialog(
    context: context,
    initialLabel: initialLabel,
  );
  if (label == null) return;
  await viewModel.renameSelectedPlan(label);
}

Future<String?> _showProductionRenameDialog({
  required BuildContext context,
  required String initialLabel,
}) async {
  var currentLabel = initialLabel;
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('重命名产线'),
        content: TextFormField(
          key: const ValueKey('studio-production-rename-plan-field'),
          initialValue: initialLabel,
          autofocus: true,
          decoration: const InputDecoration(labelText: '产线名称'),
          onChanged: (value) {
            currentLabel = value;
          },
          onFieldSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.of(context).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('studio-production-confirm-rename-plan'),
            onPressed: () {
              final trimmed = currentLabel.trim();
              if (trimmed.isNotEmpty) Navigator.of(context).pop(trimmed);
            },
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
}

class _QueueOverviewPanel extends StatelessWidget {
  final ProductionQueueViewModel viewModel;

  const _QueueOverviewPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final plan = viewModel.selectedPlan;
    final isExecuting = viewModel.isExecuting;
    final isPaused = viewModel.isPaused;
    final isWaitingForPause = isExecuting && viewModel.pauseRequested;
    final canContinue = isPaused || viewModel.canResume;
    final queueStateLabel = isWaitingForPause
        ? '暂停中'
        : isExecuting
            ? '运行中'
            : isPaused
                ? '已暂停'
                : '待机';
    final primaryLabel = isWaitingForPause
        ? '等待暂停'
        : isExecuting
            ? '暂停'
            : canContinue
                ? '继续'
                : '开始';
    final primaryIcon = isWaitingForPause
        ? Icons.hourglass_top
        : isExecuting
            ? Icons.pause
            : canContinue
                ? Icons.play_arrow
                : Icons.play_arrow;
    final VoidCallback? primaryAction = isWaitingForPause
        ? null
        : isExecuting
            ? viewModel.pause
            : canContinue
                ? () => unawaited(viewModel.resume())
                : viewModel.start;
    final primaryTone = isExecuting || isWaitingForPause
        ? StudioButtonTone.warning
        : StudioButtonTone.primary;
    return StudioPanel(
      key: const ValueKey('studio-batch-queue-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelHeading(
            icon: Icons.account_tree_outlined,
            title: '队列总览',
            trailing: StudioChip(
              icon: isExecuting
                  ? (isWaitingForPause
                      ? Icons.pause_circle_outline
                      : Icons.bolt)
                  : viewModel.isPaused
                      ? Icons.pause_circle_outline
                      : Icons.radio_button_unchecked,
              label: queueStateLabel,
              selected: isExecuting || isPaused,
              accentColor: isWaitingForPause
                  ? StudioTokens.warning
                  : StudioTokens.active,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  plan?.name ?? 'Deterministic Queue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              StudioIconButton(
                key: const ValueKey('studio-production-rename-plan'),
                icon: Icons.edit_outlined,
                tooltip: '重命名产线',
                onPressed: viewModel.canRenameSelectedPlan
                    ? () => unawaited(
                          _renameProductionPlan(context, viewModel),
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StudioChip(
                icon: Icons.format_list_numbered,
                label: '任务 ${viewModel.totalTasks}',
              ),
              StudioChip(
                icon: Icons.check_circle_outline,
                label: '完成 ${viewModel.completedTasks}',
                selected: viewModel.completedTasks > 0,
                accentColor: StudioTokens.active,
              ),
              StudioChip(
                icon: Icons.error_outline,
                label: '失败 ${viewModel.failedTasks}',
                selected: viewModel.failedTasks > 0,
                accentColor: StudioTokens.danger,
              ),
              if (plan != null)
                StudioChip(
                  icon: Icons.fingerprint,
                  label: _shortFingerprint(plan.planFingerprint),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StudioButton(
                  key: const ValueKey('studio-production-start'),
                  icon: primaryIcon,
                  label: primaryLabel,
                  tone: primaryTone,
                  onPressed: primaryAction,
                ),
              ),
              const SizedBox(width: 8),
              StudioIconButton(
                key: const ValueKey('studio-production-hard-stop'),
                icon: Icons.stop_circle_outlined,
                tooltip: '停止产线并从头开始',
                onPressed: viewModel.canStop
                    ? () => unawaited(viewModel.stop())
                    : null,
              ),
              const SizedBox(width: 8),
              StudioIconButton(
                key: const ValueKey('studio-production-resume'),
                icon: Icons.history,
                tooltip: '继续',
                onPressed: viewModel.canResume
                    ? () => unawaited(viewModel.resume())
                    : null,
              ),
              const SizedBox(width: 8),
              StudioButton(
                key: const ValueKey('studio-production-retry-failed'),
                icon: Icons.refresh,
                label: '重跑异常',
                tone: StudioButtonTone.secondary,
                onPressed: viewModel.hasAbnormalTasks
                    ? () => unawaited(viewModel.rerunAbnormalTasks())
                    : null,
              ),
              const SizedBox(width: 8),
              StudioIconButton(
                key: const ValueKey('studio-production-clear-current'),
                icon: Icons.delete_sweep_outlined,
                tooltip: '清空当前产线',
                onPressed: viewModel.canClearCurrentPlan
                    ? () => unawaited(viewModel.clearCurrentPlan())
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExecutionSettingsPanel extends StatelessWidget {
  final ProductionQueueViewModel viewModel;

  const _ExecutionSettingsPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    final generationSettings = _BatchGenerationSettings.from(viewModel);
    return StudioPanel(
      key: const ValueKey('studio-production-settings-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PanelHeading(
            icon: Icons.tune,
            title: '执行设置',
          ),
          const SizedBox(height: 12),
          _BatchGenerationParameterEditor(
            viewModel: viewModel,
            generationSettings: generationSettings,
          ),
          const SizedBox(height: 12),
          _BatchRuntimeSettingsEditor(viewModel: viewModel),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StudioChip(
                icon: Icons.key_outlined,
                label: 'Token ${settings.tokenReference}',
              ),
              StudioChip(
                icon: Icons.timer_outlined,
                label: '间隔 ${viewModel.requestIntervalSeconds}s',
              ),
              if (viewModel.requestIntervalRandomRangeSeconds > 0)
                StudioChip(
                  icon: Icons.shuffle,
                  label:
                      '随机 +0~${viewModel.requestIntervalRandomRangeSeconds}s',
                ),
              StudioChip(
                icon: Icons.replay_circle_filled_outlined,
                label: viewModel.retryIndefinitely
                    ? '重试 无限'
                    : '重试次数 ${viewModel.retryCount}',
              ),
              StudioChip(
                icon: Icons.casino_outlined,
                label: _seedSummary(viewModel),
              ),
              StudioChip(
                icon: Icons.folder_outlined,
                label: viewModel.outputDirectory.isEmpty
                    ? '输出 未设置'
                    : viewModel.outputDirectory,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatchGenerationParameterEditor extends StatelessWidget {
  final ProductionQueueViewModel viewModel;
  final _BatchGenerationSettings generationSettings;

  const _BatchGenerationParameterEditor({
    required this.viewModel,
    required this.generationSettings,
  });

  @override
  Widget build(BuildContext context) {
    const canEdit = true;
    final samplerOptions = _samplerOptionsForModel(generationSettings.model);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 20) / 3
            : constraints.maxWidth >= 520
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            _GenerationParameterTile(
              width: tileWidth,
              icon: Icons.memory_outlined,
              label: '模型',
              useOriginal: viewModel.useOriginalModel,
              switchKey: const ValueKey('studio-production-model-use-original'),
              canChange: canEdit,
              onUseOriginalChanged: viewModel.setUseOriginalModel,
              child: _BatchSettingSelectField(
                key: const ValueKey('studio-production-model-select'),
                value: viewModel.useOriginalModel
                    ? generationSettings.model
                    : viewModel.batchModel,
                label: 'model',
                options: models,
                enabled: canEdit && !viewModel.useOriginalModel,
                onChanged: viewModel.setBatchModel,
              ),
            ),
            _GenerationParameterTile(
              width: tileWidth,
              icon: Icons.photo_size_select_large_outlined,
              label: '尺寸',
              useOriginal: viewModel.useOriginalSize,
              switchKey: const ValueKey('studio-production-size-use-original'),
              canChange: canEdit,
              onUseOriginalChanged: viewModel.setUseOriginalSize,
              child: Row(
                children: [
                  Expanded(
                    child: _BatchSettingTextField(
                      key: const ValueKey('studio-production-width-input'),
                      value: _formatNullableInt(
                        viewModel.useOriginalSize
                            ? generationSettings.width
                            : viewModel.batchWidth,
                      ),
                      label: 'width',
                      enabled: canEdit && !viewModel.useOriginalSize,
                      keyboardType: TextInputType.number,
                      onChanged: viewModel.setBatchWidthText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BatchSettingTextField(
                      key: const ValueKey('studio-production-height-input'),
                      value: _formatNullableInt(
                        viewModel.useOriginalSize
                            ? generationSettings.height
                            : viewModel.batchHeight,
                      ),
                      label: 'height',
                      enabled: canEdit && !viewModel.useOriginalSize,
                      keyboardType: TextInputType.number,
                      onChanged: viewModel.setBatchHeightText,
                    ),
                  ),
                ],
              ),
            ),
            _GenerationParameterTile(
              width: tileWidth,
              icon: Icons.grain_outlined,
              label: '采样',
              useOriginal: viewModel.useOriginalSampler,
              switchKey:
                  const ValueKey('studio-production-sampler-use-original'),
              canChange: canEdit,
              onUseOriginalChanged: viewModel.setUseOriginalSampler,
              child: _BatchSettingSelectField(
                key: const ValueKey('studio-production-sampler-select'),
                value: viewModel.useOriginalSampler
                    ? generationSettings.sampler
                    : viewModel.batchSampler,
                label: 'sampler',
                options: samplerOptions,
                enabled: canEdit && !viewModel.useOriginalSampler,
                onChanged: viewModel.setBatchSampler,
              ),
            ),
            _GenerationParameterTile(
              width: tileWidth,
              icon: Icons.motion_photos_auto_outlined,
              label: '步数',
              useOriginal: viewModel.useOriginalSteps,
              switchKey: const ValueKey('studio-production-steps-use-original'),
              canChange: canEdit,
              onUseOriginalChanged: viewModel.setUseOriginalSteps,
              child: _BatchSettingTextField(
                key: const ValueKey('studio-production-steps-input'),
                value: _formatNullableInt(
                  viewModel.useOriginalSteps
                      ? generationSettings.steps
                      : viewModel.batchSteps,
                ),
                label: 'steps',
                enabled: canEdit && !viewModel.useOriginalSteps,
                keyboardType: TextInputType.number,
                onChanged: viewModel.setBatchStepsText,
              ),
            ),
            _GenerationParameterTile(
              width: tileWidth,
              icon: Icons.exposure_outlined,
              label: 'CFG',
              useOriginal: viewModel.useOriginalScale,
              switchKey: const ValueKey('studio-production-scale-use-original'),
              canChange: canEdit,
              onUseOriginalChanged: viewModel.setUseOriginalScale,
              child: _BatchSettingTextField(
                key: const ValueKey('studio-production-scale-input'),
                value: _formatNullableDouble(
                  viewModel.useOriginalScale
                      ? generationSettings.scale
                      : viewModel.batchScale,
                ),
                label: 'scale',
                enabled: canEdit && !viewModel.useOriginalScale,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: viewModel.setBatchScaleText,
              ),
            ),
            _GenerationParameterTile(
              width: tileWidth,
              icon: Icons.casino_outlined,
              label: 'Seed',
              useOriginal: viewModel.useOriginalSeed,
              switchKey: const ValueKey('studio-production-seed-use-original'),
              canChange: canEdit,
              onUseOriginalChanged: viewModel.setUseOriginalSeed,
              child: _BatchSettingTextField(
                key: const ValueKey('studio-production-seed-input'),
                value: _formatNullableInt(
                  viewModel.useOriginalSeed
                      ? generationSettings.seed
                      : viewModel.batchSeed,
                ),
                label: 'seed (-1=random)',
                enabled: canEdit && !viewModel.useOriginalSeed,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                onChanged: viewModel.setBatchSeedText,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BatchRuntimeSettingsEditor extends StatelessWidget {
  final ProductionQueueViewModel viewModel;

  const _BatchRuntimeSettingsEditor({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    const canEdit = true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth >= 960
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 760
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            _RuntimeSettingTile(
              width: tileWidth,
              icon: Icons.timer_outlined,
              label: '间隔',
              child: _BatchSettingTextField(
                key: const ValueKey('studio-production-interval-input'),
                value: viewModel.requestIntervalSeconds.toString(),
                label: 'seconds',
                enabled: canEdit,
                keyboardType: TextInputType.number,
                onChanged: viewModel.setRequestIntervalSecondsText,
              ),
            ),
            _RuntimeSettingTile(
              width: tileWidth,
              icon: Icons.shuffle,
              label: '随机范围',
              child: _BatchSettingTextField(
                key: const ValueKey(
                  'studio-production-random-interval-input',
                ),
                value: viewModel.requestIntervalRandomRangeSeconds.toString(),
                label: '+0~seconds',
                enabled: canEdit,
                keyboardType: TextInputType.number,
                onChanged: viewModel.setRequestIntervalRandomRangeText,
              ),
            ),
            _RuntimeSettingTile(
              width: tileWidth,
              icon: Icons.replay_circle_filled_outlined,
              label: '重试',
              child: _BatchRetrySettingField(
                value: viewModel.retryCount.toString(),
                enabled: canEdit,
                retryIndefinitely: viewModel.retryIndefinitely,
                onCountChanged: viewModel.setRetryCountText,
                onRetryIndefinitelyChanged: viewModel.setRetryIndefinitely,
              ),
            ),
            _RuntimeSettingTile(
              width: tileWidth,
              icon: Icons.folder_outlined,
              label: '输出',
              child: _BatchOutputDirectoryField(
                value: viewModel.outputDirectory,
                enabled: canEdit,
                onChanged: viewModel.setOutputDirectory,
                canBrowse: viewModel.canPickOutputDirectory,
                onBrowse: viewModel.pickOutputDirectory,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RuntimeSettingTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final Widget child;

  const _RuntimeSettingTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.surfaceBase,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: StudioTokens.textSecondary),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerationParameterTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final bool useOriginal;
  final Key switchKey;
  final bool canChange;
  final ValueChanged<bool> onUseOriginalChanged;
  final Widget child;

  const _GenerationParameterTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.useOriginal,
    required this.switchKey,
    required this.canChange,
    required this.onUseOriginalChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.surfaceBase,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: useOriginal ? StudioTokens.warning : StudioTokens.active,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: child),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(
                      '自定义',
                      key: ValueKey('$switchKey-custom'),
                    ),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('原始', key: switchKey),
                  ),
                ],
                selected: {useOriginal},
                showSelectedIcon: false,
                onSelectionChanged: canChange
                    ? (values) => onUseOriginalChanged(values.single)
                    : null,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return StudioTokens.onPrimary;
                    }
                    return StudioTokens.textSecondary;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return useOriginal
                          ? StudioTokens.warning
                          : StudioTokens.active;
                    }
                    return StudioTokens.surface2;
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchSettingSelectField extends StatelessWidget {
  final String value;
  final String label;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _BatchSettingSelectField({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = value.trim();
    final menuOptions = [
      ...options,
      if (trimmed.isNotEmpty && !options.contains(trimmed)) trimmed,
    ];
    return DropdownButtonFormField<String>(
      initialValue:
          trimmed.isEmpty || !menuOptions.contains(trimmed) ? null : trimmed,
      items: [
        for (final option in menuOptions)
          DropdownMenuItem<String>(
            value: option,
            child: Text(
              option,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      isExpanded: true,
      onChanged: enabled
          ? (next) {
              if (next != null) onChanged(next);
            }
          : null,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}

class _BatchRetrySettingField extends StatelessWidget {
  final String value;
  final bool enabled;
  final bool retryIndefinitely;
  final ValueChanged<String> onCountChanged;
  final ValueChanged<bool> onRetryIndefinitelyChanged;

  const _BatchRetrySettingField({
    required this.value,
    required this.enabled,
    required this.retryIndefinitely,
    required this.onCountChanged,
    required this.onRetryIndefinitelyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BatchSettingTextField(
            key: const ValueKey('studio-production-retry-input'),
            value: value,
            label: '重试次数',
            enabled: enabled && !retryIndefinitely,
            keyboardType: TextInputType.number,
            onChanged: onCountChanged,
          ),
        ),
        const SizedBox(width: 8),
        Checkbox(
          key: const ValueKey('studio-production-retry-infinite'),
          value: retryIndefinitely,
          onChanged: enabled
              ? (value) => onRetryIndefinitelyChanged(value ?? false)
              : null,
          visualDensity: VisualDensity.compact,
        ),
        Text(
          '无限',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color:
                    enabled ? StudioTokens.textPrimary : StudioTokens.textMuted,
              ),
        ),
      ],
    );
  }
}

class _BatchOutputDirectoryField extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool canBrowse;
  final Future<void> Function() onBrowse;

  const _BatchOutputDirectoryField({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.canBrowse,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BatchSettingTextField(
            key: const ValueKey('studio-production-output-input'),
            value: value,
            label: 'output directory',
            enabled: enabled,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        StudioIconButton(
          key: const ValueKey('studio-production-output-browse'),
          icon: Icons.folder_open_outlined,
          tooltip: '选择输出目录',
          onPressed: enabled && canBrowse ? () => unawaited(onBrowse()) : null,
        ),
      ],
    );
  }
}

class _BatchSettingTextField extends StatefulWidget {
  final String value;
  final String label;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  const _BatchSettingTextField({
    super.key,
    required this.value,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.keyboardType,
  });

  @override
  State<_BatchSettingTextField> createState() => _BatchSettingTextFieldState();
}

class _BatchSettingTextFieldState extends State<_BatchSettingTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_BatchSettingTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}

class _BatchGenerationSettings {
  final String model;
  final String sampler;
  final int? width;
  final int? height;
  final int? steps;
  final double? scale;
  final int? seed;

  const _BatchGenerationSettings({
    required this.model,
    required this.sampler,
    required this.width,
    required this.height,
    required this.steps,
    required this.scale,
    required this.seed,
  });

  bool get hasSize => width != null && height != null;

  factory _BatchGenerationSettings.from(ProductionQueueViewModel viewModel) {
    final settings = viewModel.settings;
    final task = viewModel.selectedTask ??
        ((viewModel.selectedPlan?.tasks.isEmpty ?? true)
            ? null
            : viewModel.selectedPlan!.tasks.first);
    final payload = task?.payload ?? const <String, dynamic>{};
    final parameters = _mapValue(payload['parameters']);
    final original = _BatchGenerationSettings(
      model: _stringValue(payload['model']) ??
          _stringValue(parameters['model']) ??
          settings.model,
      sampler: _stringValue(parameters['sampler']) ??
          _stringValue(payload['sampler']) ??
          settings.sampler,
      width: _intValue(parameters['width']) ??
          _intValue(payload['width']) ??
          settings.width,
      height: _intValue(parameters['height']) ??
          _intValue(payload['height']) ??
          settings.height,
      steps: _intValue(parameters['steps']) ??
          _intValue(payload['steps']) ??
          settings.steps,
      scale: _doubleValue(parameters['scale']) ??
          _doubleValue(payload['scale']) ??
          settings.scale,
      seed: _intValue(parameters['seed']) ??
          _intValue(payload['seed']) ??
          settings.seed,
    );
    return _BatchGenerationSettings(
      model: viewModel.useOriginalModel ? original.model : viewModel.batchModel,
      sampler: viewModel.useOriginalSampler
          ? original.sampler
          : viewModel.batchSampler,
      width: viewModel.useOriginalSize ? original.width : viewModel.batchWidth,
      height:
          viewModel.useOriginalSize ? original.height : viewModel.batchHeight,
      steps: viewModel.useOriginalSteps ? original.steps : viewModel.batchSteps,
      scale: viewModel.useOriginalScale ? original.scale : viewModel.batchScale,
      seed: viewModel.useOriginalSeed ? original.seed : viewModel.batchSeed,
    );
  }
}

class _TaskListPanel extends StatelessWidget {
  final ProductionQueueViewModel viewModel;
  final bool expandList;

  const _TaskListPanel({
    required this.viewModel,
    this.expandList = true,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = viewModel.selectedPlan?.tasks ?? const <ProductionTask>[];
    return StudioPanel(
      key: const ValueKey('studio-production-task-list-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeading(
            icon: Icons.view_list_outlined,
            title: '帧任务',
          ),
          const SizedBox(height: 12),
          if (tasks.isEmpty)
            _TaskListBody(
              expand: expandList,
              child: Center(
                child: Text(
                  '暂无生产任务',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            _TaskListBody(
              expand: expandList,
              child: ListView.separated(
                shrinkWrap: !expandList,
                physics:
                    expandList ? null : const NeverScrollableScrollPhysics(),
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return _TaskRow(
                    task: task,
                    selected: task.id == viewModel.selectedTask?.id,
                    onSelect: () => viewModel.selectTask(task),
                    onRerun: () {
                      unawaited(viewModel.queueRerunTask(task));
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskListBody extends StatelessWidget {
  final bool expand;
  final Widget child;

  const _TaskListBody({
    required this.expand,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return expand ? Expanded(child: child) : child;
  }
}

class _TaskRow extends StatelessWidget {
  final ProductionTask task;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRerun;

  const _TaskRow({
    required this.task,
    required this.selected,
    required this.onSelect,
    required this.onRerun,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
    return Material(
      color: selected ? StudioTokens.surface3 : StudioTokens.surfaceBase,
      borderRadius: StudioTokens.radiusCard,
      child: InkWell(
        borderRadius: StudioTokens.radiusCard,
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: StudioTokens.radiusPill,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.source.sourceFileName ?? task.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  task.outputImagePath ?? task.error ?? '等待执行',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: task.error == null
                            ? StudioTokens.textSecondary
                            : StudioTokens.danger,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              StudioChip(
                label: _statusLabel(task.status),
                selected: true,
                accentColor: statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                'x${task.attempts}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              StudioButton(
                key: ValueKey('studio-production-rerun-${task.id}'),
                icon: Icons.replay,
                label: '重跑',
                tone: StudioButtonTone.ghost,
                onPressed: onRerun,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductionResultsPanel extends StatelessWidget {
  final ProductionQueueViewModel viewModel;
  final bool expandBody;

  const _ProductionResultsPanel({
    required this.viewModel,
    this.expandBody = true,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = viewModel.selectedPlan?.tasks ?? const <ProductionTask>[];
    final selectedTask = viewModel.selectedTask;
    return StudioPanel(
      key: const ValueKey('studio-production-payload-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            icon: Icons.image_outlined,
            title: '生成结果',
            trailing: StudioButton(
              key: const ValueKey('studio-production-export-json'),
              icon: Icons.ios_share,
              label: '导出 JSON',
              tone: StudioButtonTone.secondary,
              onPressed: selectedTask == null
                  ? null
                  : () => _exportSelectedTaskJson(context, viewModel),
            ),
          ),
          const SizedBox(height: 12),
          if (tasks.isEmpty)
            _TaskListBody(
              expand: expandBody,
              child: Center(
                child: Text(
                  '暂无生成结果',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            _TaskListBody(
              expand: expandBody,
              child: _ProductionResultWaterfall(
                tasks: tasks,
                selectedTaskId: selectedTask?.id,
                scrollable: expandBody,
                onQuickRerun: (task) {
                  unawaited(viewModel.queueRerunTask(task));
                },
                onOpen: (task) {
                  viewModel.selectTask(task);
                  _showProductionResultDetails(
                    context,
                    viewModel: viewModel,
                    task: task,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductionResultWaterfall extends StatelessWidget {
  final List<ProductionTask> tasks;
  final String? selectedTaskId;
  final bool scrollable;
  final ValueChanged<ProductionTask> onOpen;
  final ValueChanged<ProductionTask> onQuickRerun;

  const _ProductionResultWaterfall({
    required this.tasks,
    required this.selectedTaskId,
    required this.scrollable,
    required this.onOpen,
    required this.onQuickRerun,
  });

  @override
  Widget build(BuildContext context) {
    final items = tasks.map(_productionGeneratedImageItem).toList();
    return StudioGeneratedImageGallery(
      key: const ValueKey('studio-production-results-waterfall'),
      items: items,
      selectedId: selectedTaskId,
      columnWidth: 250,
      scrollable: scrollable,
      cardKeyPrefix: 'studio-production-result-card',
      imageOverlayBuilder: (context, item) {
        final task = item.source as ProductionTask;
        return StudioIconButton(
          key: ValueKey('studio-production-quick-rerun-${task.id}'),
          icon: Icons.replay,
          tooltip: '插队重跑',
          onPressed: () => onQuickRerun(task),
        );
      },
      onOpen: (context, item) {
        final task = item.source as ProductionTask;
        onOpen(task);
      },
    );
  }
}

StudioGeneratedImageItem _productionGeneratedImageItem(ProductionTask task) {
  final outputPath = task.outputImagePath?.trim();
  return StudioGeneratedImageItem(
    id: task.id,
    name: task.title,
    imagePath: outputPath == null || outputPath.isEmpty ? null : outputPath,
    source: task,
    placeholder: _resultPreviewTitle(task),
  );
}

class _ProductionFileImage extends StatefulWidget {
  final File file;
  final BoxFit fit;
  final String cacheRevision;
  final ImageErrorWidgetBuilder errorBuilder;

  const _ProductionFileImage({
    required this.file,
    required this.fit,
    required this.cacheRevision,
    required this.errorBuilder,
  });

  @override
  State<_ProductionFileImage> createState() => _ProductionFileImageState();
}

class _ProductionFileImageState extends State<_ProductionFileImage> {
  @override
  void initState() {
    super.initState();
    _evictCurrentFile();
  }

  @override
  void didUpdateWidget(_ProductionFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.cacheRevision != widget.cacheRevision) {
      _evictCurrentFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      key: ValueKey(
          'production-image-${widget.file.path}-${widget.cacheRevision}'),
      image: FileImage(widget.file),
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
    );
  }

  void _evictCurrentFile() {
    try {
      unawaited(
        FileImage(widget.file).evict().catchError((_) => false),
      );
    } catch (_) {
      // Bad or transient file paths should fall back to the card placeholder.
    }
  }
}

File? _existingOutputFile(String? outputPath) {
  final trimmed = outputPath?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  try {
    final file = File(trimmed);
    return file.existsSync() ? file : null;
  } catch (_) {
    return null;
  }
}

Future<void> _revealExistingFileInManager(
  BuildContext context,
  File file,
) async {
  try {
    await FileService().revealInFileManager(file.path);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

String _imageCacheRevision(ProductionTask task) {
  return [
    task.updatedAt.toUtc().microsecondsSinceEpoch,
    task.completedAt?.toUtc().microsecondsSinceEpoch ?? 0,
    task.attempts,
    task.status.name,
  ].join(':');
}

void _showProductionResultDetails(
  BuildContext context, {
  required ProductionQueueViewModel viewModel,
  required ProductionTask task,
}) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        key: const ValueKey('studio-production-result-detail-dialog'),
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: StudioTokens.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioTokens.radiusPanel),
          side: BorderSide(color: StudioTokens.border),
        ),
        child: StudioResizableImagePreviewWindow(
          windowKey: const ValueKey('studio-production-result-detail-window'),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: _ProductionResultDetailContent(
                viewModel: viewModel,
                task: task,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ProductionResultDetailContent extends StatelessWidget {
  final ProductionQueueViewModel viewModel;
  final ProductionTask task;

  const _ProductionResultDetailContent({
    required this.viewModel,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    final positivePromptGroups = _positivePromptGroups(task.payload);
    final negativePromptGroups = _negativePromptGroups(task.payload);
    final positivePrompt = _positivePrompt(task.payload);
    final negativePrompt = _negativePrompt(task.payload);
    final parameterGroups = _visibleParameterGroups(task.payload);
    final outputFile = _existingOutputFile(task.outputImagePath);
    final metadata = KeyedSubtree(
      key: const ValueKey('studio-production-result-detail-metadata'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StudioChip(
                icon: Icons.movie_filter_outlined,
                label: '甯?${task.source.frameIndex ?? '-'}',
              ),
              StudioChip(
                icon: Icons.description_outlined,
                label: task.source.sourceFileName ?? task.title,
              ),
              StudioChip(
                icon: Icons.fingerprint,
                label: _shortFingerprint(task.payloadFingerprint),
              ),
            ],
          ),
          if (task.status == ProductionTaskStatus.completed) ...[
            const SizedBox(height: 12),
            _TaskRatingBar(
              task: task,
              onRate: (rating) => unawaited(viewModel.rateTask(task, rating)),
            ),
          ],
          const SizedBox(height: 12),
          _DetailLine('任务', task.id),
          _DetailLine('脚本', task.source.scriptId ?? '-'),
          _DetailLine('Run', task.source.recastRunId ?? '-'),
          _DetailLine('输出', task.outputImagePath ?? '-'),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelHeading(
          icon: Icons.image_outlined,
          title: task.title,
          trailing: StudioIconButton(
            icon: Icons.close,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: 12),
        _TaskResultPreview(task: task),
        if (outputFile != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: const ValueKey('studio-production-reveal-file'),
              onPressed: () => unawaited(
                _revealExistingFileInManager(context, outputFile),
              ),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('在资源管理器中显示'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _PromptTagBlock(
          key: const ValueKey('studio-production-positive-prompt'),
          title: '正向提示词',
          text: positivePrompt.isEmpty ? '-' : positivePrompt,
          groups: positivePromptGroups,
          tagKey: const ValueKey('studio-production-positive-prompt-tags'),
        ),
        if (negativePromptGroups.isNotEmpty || negativePrompt.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PromptTagBlock(
            key: const ValueKey('studio-production-negative-prompt'),
            title: '负向提示词',
            text: negativePrompt,
            groups: negativePromptGroups,
            tagKey: const ValueKey('studio-production-negative-prompt-tags'),
            negative: true,
          ),
        ],
        const SizedBox(height: 12),
        metadata,
        if (parameterGroups.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GenerationParameterPanel(
            key: const ValueKey('studio-production-parameter-summary'),
            groups: parameterGroups,
          ),
        ],
      ],
    );
  }
}

class _TaskResultPreview extends StatelessWidget {
  final ProductionTask task;

  const _TaskResultPreview({required this.task});

  @override
  Widget build(BuildContext context) {
    final outputPath = task.outputImagePath?.trim();
    final hasOutputPath = outputPath != null && outputPath.isNotEmpty;
    final outputFile = _existingOutputFile(outputPath);
    final imageExists = outputFile != null;
    final onTap = imageExists
        ? () => _showProductionImageZoomDialog(context, task)
        : null;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 400),
        child: MouseRegion(
          cursor:
              imageExists ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              key: const ValueKey('studio-production-result-preview'),
              decoration: BoxDecoration(
                color: StudioTokens.surfaceBase,
                borderRadius: StudioTokens.radiusCard,
                border: Border.all(color: StudioTokens.border),
              ),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: StudioTokens.radiusCard,
                  child: imageExists
                      ? _ProductionFileImage(
                          file: outputFile,
                          fit: BoxFit.contain,
                          cacheRevision: _imageCacheRevision(task),
                          errorBuilder: (context, error, stackTrace) {
                            return _ResultPreviewPlaceholder(
                              icon: Icons.broken_image_outlined,
                              title: '结果图片无法读取',
                              subtitle: outputPath,
                            );
                          },
                        )
                      : _ResultPreviewPlaceholder(
                          icon: _resultPreviewIcon(task.status),
                          title: _resultPreviewTitle(task),
                          subtitle: hasOutputPath ? outputPath : task.error,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showProductionImageZoomDialog(
  BuildContext context,
  ProductionTask task,
) {
  final outputFile = _existingOutputFile(task.outputImagePath);
  if (outputFile == null) return;
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      key: const ValueKey('studio-production-image-zoom-dialog'),
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.black,
      child: ConstrainedBox(
        key: const ValueKey('studio-production-image-zoom-window'),
        constraints: studioImagePreviewDialogConstraints,
        child: Stack(
          children: [
            Positioned.fill(
              child: _ProductionZoomableFileImage(
                file: outputFile,
                cacheRevision: _imageCacheRevision(task),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: StudioIconButton(
                key: const ValueKey('studio-production-zoom-reveal-file'),
                icon: Icons.folder_open_outlined,
                tooltip: '在资源管理器中显示',
                onPressed: () => unawaited(
                  _revealExistingFileInManager(context, outputFile),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: StudioIconButton(
                icon: Icons.close,
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProductionZoomableFileImage extends StatefulWidget {
  final File file;
  final String cacheRevision;

  const _ProductionZoomableFileImage({
    required this.file,
    required this.cacheRevision,
  });

  @override
  State<_ProductionZoomableFileImage> createState() =>
      _ProductionZoomableFileImageState();
}

class _ProductionZoomableFileImageState
    extends State<_ProductionZoomableFileImage> {
  static const double _minScale = 1;
  static const double _maxScale = 8;

  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          key: const ValueKey('studio-production-zoomable-image-viewer'),
          onPointerSignal: _handlePointerSignal,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: _minScale,
            maxScale: _maxScale,
            boundaryMargin: const EdgeInsets.all(4096),
            child: SizedBox(
              width: max(1.0, constraints.maxWidth),
              height: max(1.0, constraints.maxHeight),
              child: _ProductionFileImage(
                file: widget.file,
                fit: BoxFit.contain,
                cacheRevision: widget.cacheRevision,
                errorBuilder: (context, error, stackTrace) {
                  return _ResultPreviewPlaceholder(
                    icon: Icons.broken_image_outlined,
                    title: 'Image could not be read',
                    subtitle: widget.file.path,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    _scaleAt(event.localPosition, delta < 0 ? 1.12 : 0.88);
  }

  void _scaleAt(Offset focalPoint, double scaleFactor) {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final nextScale =
        (currentScale * scaleFactor).clamp(_minScale, _maxScale).toDouble();
    if (nextScale <= _minScale + 0.01) {
      _controller.value = Matrix4.identity();
      return;
    }
    final effectiveScale = nextScale / currentScale;
    final next = _controller.value.clone()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(effectiveScale, effectiveScale, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _controller.value = next;
  }
}

class _ResultPreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _ResultPreviewPlaceholder({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedSubtitle = subtitle?.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: StudioTokens.textMuted, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (trimmedSubtitle != null && trimmedSubtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                trimmedSubtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textSecondary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GenerationParameterPanel extends StatelessWidget {
  final List<_VisibleParameterGroup> groups;

  const _GenerationParameterPanel({
    super.key,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    final parameters = [
      for (final group in groups) ...group.parameters,
    ];
    final highlights = parameters.where((parameter) => parameter.highlight);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase,
        borderRadius: StudioTokens.radiusCard,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tune_outlined,
                  size: 18,
                  color: StudioTokens.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '生成参数',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                StudioChip(
                  icon: Icons.view_module_outlined,
                  label: '${parameters.length} 项',
                ),
                const SizedBox(width: 8),
                StudioIconButton(
                  key: const ValueKey('studio-production-copy-parameters'),
                  icon: Icons.copy_all_outlined,
                  tooltip: '复制参数',
                  onPressed: () => _copyGenerationParameters(context, groups),
                ),
              ],
            ),
            if (highlights.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final parameter in highlights)
                    _ParameterSummaryPill(parameter: parameter),
                ],
              ),
            ],
            const SizedBox(height: 12),
            for (final group in groups) ...[
              _ParameterGroupBlock(group: group),
              if (group != groups.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParameterSummaryPill extends StatelessWidget {
  final _VisibleParameter parameter;

  const _ParameterSummaryPill({required this.parameter});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${parameter.key}: ${parameter.value}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.primary.withAlpha(18),
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.primary.withAlpha(90)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(parameter.icon, size: 15, color: StudioTokens.primary),
              const SizedBox(width: 6),
              Text(
                parameter.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textSecondary,
                    ),
              ),
              const SizedBox(width: 6),
              Text(
                parameter.displayValue,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParameterGroupBlock extends StatelessWidget {
  final _VisibleParameterGroup group;

  const _ParameterGroupBlock({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(group.icon, size: 16, color: StudioTokens.textSecondary),
            const SizedBox(width: 6),
            Text(
              group.title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = _parameterTileWidth(constraints.maxWidth);
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final parameter in group.parameters)
                  SizedBox(
                    width: width,
                    child: _ParameterTile(parameter: parameter),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ParameterTile extends StatelessWidget {
  final _VisibleParameter parameter;

  const _ParameterTile({required this.parameter});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${parameter.key}: ${parameter.value}',
      waitDuration: const Duration(milliseconds: 450),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.surface2,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.cardOutline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: StudioTokens.surface3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  parameter.icon,
                  size: 16,
                  color: StudioTokens.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      parameter.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: StudioTokens.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      parameter.displayValue,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: StudioTokens.textPrimary,
                            fontFamily:
                                parameter.monospace ? 'monospace' : null,
                            height: 1.2,
                          ),
                    ),
                    if (parameter.label != parameter.key) ...[
                      const SizedBox(height: 3),
                      Text(
                        parameter.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: StudioTokens.textMuted,
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRatingBar extends StatelessWidget {
  final ProductionTask task;
  final ValueChanged<int> onRate;

  const _TaskRatingBar({
    required this.task,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.workspace_premium_outlined,
          size: 18,
          color: StudioTokens.primary,
        ),
        const SizedBox(width: 8),
        Text(
          'Rating',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(width: 8),
        for (var score = 1; score <= 5; score += 1) ...[
          StudioIconButton(
            key: ValueKey('production-task-rating-$score'),
            icon: task.rating != null && task.rating! >= score
                ? Icons.star
                : Icons.star_border,
            tooltip: '$score',
            selected: task.rating == score,
            onPressed: () => onRate(score),
          ),
          if (score < 5) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _PanelHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _PanelHeading({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: StudioTokens.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptTagBlock extends StatelessWidget {
  final String title;
  final String text;
  final List<PromptTagDisplayGroup> groups;
  final Key tagKey;
  final bool negative;

  const _PromptTagBlock({
    super.key,
    required this.title,
    required this.text,
    this.groups = const [],
    required this.tagKey,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    final visibleGroups =
        groups.where((group) => group.hasText).toList(growable: false);
    final tagKeyValue = tagKey is ValueKey ? (tagKey as ValueKey).value : title;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase,
        borderRadius: StudioTokens.radiusCard,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (visibleGroups.isEmpty && (trimmed.isEmpty || trimmed == '-'))
              const Text('-')
            else if (visibleGroups.isNotEmpty)
              PromptTagGroupDisplay(
                key: tagKey,
                groups: visibleGroups,
                groupKeyPrefix: '$tagKeyValue-group',
                tagKeyPrefix: '$tagKeyValue-group-tags',
                defaultTranslated: true,
                dense: true,
                enableHoverShortcut: true,
                enableTagActions: true,
                showLayoutControls: true,
                initialLayoutMode: PromptTagLayoutMode.grouped,
              )
            else
              PromptTagDisplay(
                key: tagKey,
                text: trimmed,
                defaultTranslated: true,
                dense: true,
                enableHoverShortcut: true,
                enableTagActions: true,
                showLayoutControls: true,
                initialLayoutMode: PromptTagLayoutMode.grouped,
                negative: negative,
              ),
          ],
        ),
      ),
    );
  }
}

String _positivePrompt(Map<String, dynamic> payload) {
  return GenerationPayloadDocument.fromMap(payload).positivePrompt;
}

List<PromptTagDisplayGroup> _positivePromptGroups(
    Map<String, dynamic> payload) {
  return promptTagGroupsFromV4Prompt(
    GenerationPayloadDocument.fromMap(payload).positiveV4Prompt,
  );
}

String _negativePrompt(Map<String, dynamic> payload) {
  return GenerationPayloadDocument.fromMap(payload).negativePrompt;
}

List<PromptTagDisplayGroup> _negativePromptGroups(
    Map<String, dynamic> payload) {
  return promptTagGroupsFromV4Prompt(
    GenerationPayloadDocument.fromMap(payload).negativeV4Prompt,
    negative: true,
  );
}

List<_VisibleParameterGroup> _visibleParameterGroups(
  Map<String, dynamic> payload,
) {
  return [
    for (final group
        in GenerationPayloadDocument.fromMap(payload).visibleParameterGroups)
      _VisibleParameterGroup(
        id: group.id,
        title: _parameterGroupSpecFor(group.id).title,
        icon: _parameterGroupSpecFor(group.id).icon,
        parameters: [
          for (final parameter in group.parameters)
            _visibleParameterFromDocument(parameter),
        ],
      ),
  ];
}

_VisibleParameter _visibleParameterFromDocument(GenerationParameter parameter) {
  final value = _formatParameterValue(parameter.rawValue);
  return _VisibleParameter(
    key: parameter.key,
    label: _parameterLabelFor(parameter.key),
    value: value,
    displayValue: _compactParameterValue(value),
    groupId: parameter.groupId,
    icon: _parameterIconForKey(parameter.key, parameter.rawValue),
    highlight: parameter.highlight,
    monospace: parameter.monospace,
  );
}

IconData _parameterIconForKey(String key, Object? value) {
  if (key == 'model') return Icons.auto_awesome_outlined;
  if (key == 'width' || key == 'height') return Icons.aspect_ratio;
  if (key == 'seed') return Icons.casino_outlined;
  if (key == 'steps') return Icons.stairs_outlined;
  if (key == 'scale' || key.contains('cfg')) return Icons.tune_outlined;
  if (key == 'sampler') return Icons.manage_search;
  if (key.contains('hash') || key.contains('fingerprint')) {
    return Icons.fingerprint;
  }
  if (key == 'request_type') return Icons.route_outlined;
  if (value is bool) return Icons.toggle_on_outlined;
  if (value is num) return Icons.numbers_outlined;
  return Icons.label_outline;
}

String _parameterLabelFor(String key) => _parameterLabels[key] ?? key;

String _formatParameterValue(Object? value) {
  return switch (value) {
    null => '-',
    bool() => value ? '是' : '否',
    num() => value.toString(),
    _ => value.toString(),
  };
}

String _compactParameterValue(String value) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= 72) return singleLine;
  return '${singleLine.substring(0, 40)}...'
      '${singleLine.substring(singleLine.length - 18)}';
}

double _parameterTileWidth(double maxWidth) {
  if (!maxWidth.isFinite) return 240;
  if (maxWidth >= 840) return (maxWidth - 16) / 3;
  if (maxWidth >= 560) return (maxWidth - 8) / 2;
  return maxWidth;
}

void _copyGenerationParameters(
  BuildContext context,
  List<_VisibleParameterGroup> groups,
) {
  unawaited(
    Clipboard.setData(
      ClipboardData(text: _parameterClipboardText(groups)),
    ),
  );
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('生成参数已复制')),
  );
}

String _parameterClipboardText(List<_VisibleParameterGroup> groups) {
  return [
    for (final group in groups)
      for (final parameter in group.parameters)
        '${parameter.key}: ${parameter.value}',
  ].join('\n');
}

IconData _resultPreviewIcon(ProductionTaskStatus status) {
  return switch (status) {
    ProductionTaskStatus.completed => Icons.image_not_supported_outlined,
    ProductionTaskStatus.failed => Icons.error_outline,
    ProductionTaskStatus.running => Icons.bolt,
    ProductionTaskStatus.queued => Icons.hourglass_empty,
    ProductionTaskStatus.skipped => Icons.skip_next,
  };
}

String _resultPreviewTitle(ProductionTask task) {
  if (task.status == ProductionTaskStatus.completed) {
    return task.outputImagePath == null ? '生成已完成' : '结果文件尚未找到';
  }
  if (task.status == ProductionTaskStatus.failed) {
    return '生成失败';
  }
  if (task.status == ProductionTaskStatus.running) {
    return '正在生成';
  }
  if (task.status == ProductionTaskStatus.skipped) {
    return '已跳过';
  }
  return '等待生成';
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, child) => MapEntry(key.toString(), child));
  }
  return const {};
}

String? _stringValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String _formatCompactNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _formatNullableInt(int? value) {
  return value?.toString() ?? '';
}

String _seedSummary(ProductionQueueViewModel viewModel) {
  if (viewModel.useOriginalSeed) return 'Seed original';
  final seed = viewModel.batchSeed;
  return seed == null || seed == -1 ? 'Seed random (-1)' : 'Seed $seed';
}

String _formatNullableDouble(double? value) {
  if (value == null) return '';
  return _formatCompactNumber(value);
}

List<String> _samplerOptionsForModel(String model) {
  if (model.contains('diffusion-4')) return samplersV4;
  return samplers;
}

String _shortFingerprint(String fingerprint) {
  if (fingerprint.length <= 8) return fingerprint;
  return fingerprint.substring(0, 8);
}

String _statusLabel(ProductionTaskStatus status) {
  return switch (status) {
    ProductionTaskStatus.queued => '排队',
    ProductionTaskStatus.running => '运行',
    ProductionTaskStatus.completed => '完成',
    ProductionTaskStatus.failed => '失败',
    ProductionTaskStatus.skipped => '跳过',
  };
}

Color _statusColor(ProductionTaskStatus status) {
  return switch (status) {
    ProductionTaskStatus.queued => StudioTokens.textMuted,
    ProductionTaskStatus.running => StudioTokens.primary,
    ProductionTaskStatus.completed => StudioTokens.active,
    ProductionTaskStatus.failed => StudioTokens.danger,
    ProductionTaskStatus.skipped => StudioTokens.warning,
  };
}

class _ParameterGroupSpec {
  final String id;
  final String title;
  final IconData icon;

  const _ParameterGroupSpec({
    required this.id,
    required this.title,
    required this.icon,
  });
}

class _VisibleParameterGroup {
  final String id;
  final String title;
  final IconData icon;
  final List<_VisibleParameter> parameters;

  const _VisibleParameterGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.parameters,
  });
}

class _VisibleParameter {
  final String key;
  final String label;
  final String value;
  final String displayValue;
  final String groupId;
  final IconData icon;
  final bool highlight;
  final bool monospace;

  const _VisibleParameter({
    required this.key,
    required this.label,
    required this.value,
    required this.displayValue,
    required this.groupId,
    required this.icon,
    required this.highlight,
    required this.monospace,
  });
}

const _parameterGroupSpecs = [
  _ParameterGroupSpec(
    id: 'core',
    title: '核心',
    icon: Icons.dashboard_customize_outlined,
  ),
  _ParameterGroupSpec(
    id: 'quality',
    title: '采样与画质',
    icon: Icons.auto_fix_high_outlined,
  ),
  _ParameterGroupSpec(
    id: 'request',
    title: '请求与追踪',
    icon: Icons.receipt_long_outlined,
  ),
  _ParameterGroupSpec(
    id: 'other',
    title: '其他',
    icon: Icons.more_horiz,
  ),
];

const _parameterLabels = {
  'cfg_schedule_eligibility': 'CFG 调度',
  'controlnet_strength': 'ControlNet 强度',
  'deliberate_euler_ancestral_bug': 'Euler A 兼容',
  'dynamic_thresholding_mimic_scale': '动态阈值 Mimic',
  'dynamic_thresholding_percentile': '动态阈值百分位',
  'eplike_fine_detail': 'EP-like 精细细节',
  'height': '高度',
  'minimize_sigma_inf': '最小化 Sigma Inf',
  'model': '模型',
  'n_samples': '张数',
  'params_version': '参数版本',
  'prefer_brownian': 'Brownian 采样',
  'request_type': '请求类型',
  'sampler': '采样器',
  'scale': '引导强度',
  'seed': '种子',
  'signed_hash': '签名哈希',
  'skip_cfg_above_sigma': '跳过高 Sigma CFG',
  'skip_cfg_below_sigma': '跳过低 Sigma CFG',
  'steps': '步数',
  'uncond_per_vibe': 'Vibe 独立负面条件',
  'version': '版本',
  'width': '宽度',
  'wonky_vibe_correlation': 'Vibe 相关性修正',
};

_ParameterGroupSpec _parameterGroupSpecFor(String id) {
  return _parameterGroupSpecs.firstWhere(
    (spec) => spec.id == id,
    orElse: () => _parameterGroupSpecs.last,
  );
}
