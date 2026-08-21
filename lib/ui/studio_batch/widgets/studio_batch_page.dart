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
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_scrollbar.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_wheel_zoom.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class StudioBatchPage extends StatefulWidget {
  final ProductionQueueViewModel viewModel;
  final bool skipInitialLoad;
  final bool deferInitialLoad;

  const StudioBatchPage({
    super.key,
    required this.viewModel,
    this.skipInitialLoad = false,
    this.deferInitialLoad = false,
  });

  @override
  State<StudioBatchPage> createState() => _StudioBatchPageState();
}

class _StudioBatchPageState extends State<StudioBatchPage> {
  @override
  void initState() {
    super.initState();
    if (!widget.skipInitialLoad) {
      _loadViewModel();
    }
  }

  @override
  void didUpdateWidget(StudioBatchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel && !widget.skipInitialLoad) {
      _loadViewModel();
    }
  }

  void _loadViewModel() {
    if (!widget.deferInitialLoad) {
      unawaited(widget.viewModel.load());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.viewModel.load());
    });
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
                  child: SingleChildScrollView(
                    key: const ValueKey('studio-batch-left-scroll'),
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
                        SizedBox(
                          height: constraints.maxHeight * 0.55,
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
  final activePlan = viewModel.activePlan;
  return (
    plans: viewModel.visiblePlans
        .map((plan) =>
            '${plan.id}\u0000${plan.name}\u0000${plan.updatedAt}\u0000${viewModel.canDeletePlan(plan.id)}')
        .join('\u0001'),
    planId: plan?.id,
    planName: plan?.name,
    planFingerprint: plan?.planFingerprint,
    activePlanId: activePlan?.id,
    activePlanName: activePlan?.name,
    isViewingActivePlan: viewModel.isViewingActivePlan,
    totalTasks: viewModel.totalTasks,
    completedTasks: viewModel.completedTasks,
    completedTasksPendingDismissal: viewModel.completedTasksPendingDismissal,
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
    canClearCompletedTasks: viewModel.canClearCompletedTasks,
    canRenameSelectedPlan: viewModel.canRenameSelectedPlan,
  );
}

Object _settingsRebuildToken(ProductionQueueViewModel viewModel) {
  final selectedTask = viewModel.selectedTask;
  return (
    selectedPlanId: viewModel.selectedPlan?.id,
    activePlanId: viewModel.activePlan?.id,
    canEditSelectedPlanSettings: viewModel.canEditSelectedPlanSettings,
    selectedTaskId: selectedTask?.id,
    selectedTaskUpdatedAt:
        selectedTask?.updatedAt.toUtc().microsecondsSinceEpoch,
    isExecuting: viewModel.isExecuting,
    useOriginalModel: viewModel.useOriginalModel,
    useOriginalSize: viewModel.useOriginalSize,
    useOriginalSampler: viewModel.useOriginalSampler,
    useOriginalSteps: viewModel.useOriginalSteps,
    useOriginalScale: viewModel.useOriginalScale,
    useOriginalCfgRescale: viewModel.useOriginalCfgRescale,
    useOriginalNoiseSchedule: viewModel.useOriginalNoiseSchedule,
    useOriginalSm: viewModel.useOriginalSm,
    useOriginalSmDyn: viewModel.useOriginalSmDyn,
    useOriginalDynamicThresholding: viewModel.useOriginalDynamicThresholding,
    useOriginalVarietyPlus: viewModel.useOriginalVarietyPlus,
    useOriginalAutoPosition: viewModel.useOriginalAutoPosition,
    useOriginalLegacyUc: viewModel.useOriginalLegacyUc,
    useOriginalSeed: viewModel.useOriginalSeed,
    batchModel: viewModel.batchModel,
    batchSampler: viewModel.batchSampler,
    batchWidth: viewModel.batchWidth,
    batchHeight: viewModel.batchHeight,
    batchSteps: viewModel.batchSteps,
    batchScale: viewModel.batchScale,
    batchCfgRescale: viewModel.batchCfgRescale,
    batchNoiseSchedule: viewModel.batchNoiseSchedule,
    batchSm: viewModel.batchSm,
    batchSmDyn: viewModel.batchSmDyn,
    batchDynamicThresholding: viewModel.batchDynamicThresholding,
    batchVarietyPlus: viewModel.batchVarietyPlus,
    batchAutoPosition: viewModel.batchAutoPosition,
    batchLegacyUc: viewModel.batchLegacyUc,
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
    selectedPlanId: viewModel.selectedPlan?.id,
    selectedTaskId: viewModel.selectedTask?.id,
    tasks: viewModel.visibleTasksForPlan(viewModel.selectedPlan),
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

Future<void> _clearCompletedProductionTasks(
  BuildContext context,
  ProductionQueueViewModel viewModel,
) async {
  try {
    final count = await viewModel.clearCompletedTasks();
    if (!context.mounted) return;
    _showProductionSnack(
      context,
      count > 0 ? '已清理 $count 个已完成任务，生成结果已保留' : '暂无可清理的已完成任务',
    );
  } catch (error) {
    if (!context.mounted) return;
    _showProductionSnack(context, '清理已完成任务失败：$error');
  }
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

Future<void> _deleteProductionPlan(
  BuildContext context,
  ProductionQueueViewModel viewModel,
  ProductionPlan plan,
) async {
  final deleteLocalImages = await _showProductionDeleteDialog(
    context: context,
    plan: plan,
  );
  if (deleteLocalImages == null) return;
  try {
    final result = await viewModel.deletePlan(
      plan.id,
      deleteLocalImages: deleteLocalImages,
    );
    if (!context.mounted) return;
    if (!result.deleted) {
      _showProductionSnack(context, '运行中或暂停中的队列不能删除');
      return;
    }
    if (result.failedImagePaths.isNotEmpty) {
      _showProductionSnack(
        context,
        '队列已删除，${result.failedImagePaths.length} 个本地图片未能删除',
      );
      return;
    }
    _showProductionSnack(
      context,
      deleteLocalImages
          ? '队列已删除，本地图片已清理 ${result.deletedImageCount} 张'
          : '队列已删除，本地图片已保留',
    );
  } catch (error) {
    if (!context.mounted) return;
    _showProductionSnack(context, '删除队列失败：$error');
  }
}

Future<bool?> _showProductionDeleteDialog({
  required BuildContext context,
  required ProductionPlan plan,
}) {
  var deleteLocalImages = false;
  final outputCount = {
    for (final task in plan.tasks)
      if (task.outputImagePath?.trim().isNotEmpty == true)
        task.outputImagePath!.trim(),
  }.length;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('删除队列标签'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('将删除“${plan.name}”及其 ${plan.tasks.length} 条任务记录。'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey(
                    'studio-production-delete-local-images',
                  ),
                  contentPadding: EdgeInsets.zero,
                  value: deleteLocalImages,
                  onChanged: outputCount == 0
                      ? null
                      : (value) {
                          setState(() {
                            deleteLocalImages = value ?? false;
                          });
                        },
                  title: Text('同时删除本地图片（$outputCount 张）'),
                  subtitle: const Text('默认保留图片；不会删除文件夹。'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey(
                  'studio-production-confirm-delete-plan',
                ),
                onPressed: () => Navigator.of(context).pop(deleteLocalImages),
                child: const Text('删除'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ProductionQueueTabs extends StatelessWidget {
  final ProductionQueueViewModel viewModel;
  final ValueChanged<ProductionPlan> onDeletePlan;

  const _ProductionQueueTabs({
    required this.viewModel,
    required this.onDeletePlan,
  });

  @override
  Widget build(BuildContext context) {
    final visiblePlans = viewModel.visiblePlans;
    if (visiblePlans.isEmpty) {
      return Text(
        '暂无队列',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: StudioTokens.textSecondary,
            ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('studio-production-plan-tabs-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        key: const ValueKey('studio-production-plan-tabs'),
        children: [
          for (var index = 0; index < visiblePlans.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            _ProductionQueueTab(
              plan: visiblePlans[index],
              selected: viewModel.selectedPlan?.id == visiblePlans[index].id,
              active: viewModel.activePlan?.id == visiblePlans[index].id,
              paused: viewModel.isPaused &&
                  viewModel.activePlan?.id == visiblePlans[index].id,
              canDelete: viewModel.canDeletePlan(visiblePlans[index].id),
              onTap: () => viewModel.selectPlan(visiblePlans[index].id),
              onDelete: () => onDeletePlan(visiblePlans[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductionQueueTab extends StatelessWidget {
  final ProductionPlan plan;
  final bool selected;
  final bool active;
  final bool paused;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductionQueueTab({
    required this.plan,
    required this.selected,
    required this.active,
    required this.paused,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? StudioTokens.primary.withValues(alpha: 0.18)
        : StudioTokens.surface1;
    final borderColor = active
        ? paused
            ? StudioTokens.warning
            : StudioTokens.active
        : selected
            ? StudioTokens.primary
            : StudioTokens.border;
    final foreground =
        selected ? StudioTokens.textPrimary : StudioTokens.textSecondary;
    final shape = RoundedRectangleBorder(
      borderRadius: StudioTokens.radiusTag,
      side: BorderSide(color: borderColor),
    );
    final deleteTooltip =
        canDelete ? '删除队列标签：${plan.name}' : '当前队列正在运行或暂停，不能删除：${plan.name}';
    final deleteButton = IconButton(
      key: ValueKey(
        'studio-production-delete-plan-${plan.id}',
      ),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: 28,
        height: 28,
      ),
      padding: EdgeInsets.zero,
      tooltip: deleteTooltip,
      icon: const Icon(Icons.delete_outline, size: 16),
      color: canDelete ? StudioTokens.textSecondary : StudioTokens.textMuted,
      onPressed: canDelete ? onDelete : null,
    );
    return Material(
      key: ValueKey('studio-production-plan-tab-${plan.id}'),
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Padding(
            padding: EdgeInsets.only(
              left: 11,
              right: 3,
              top: 5,
              bottom: 5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active
                      ? paused
                          ? Icons.pause_circle_outline
                          : Icons.bolt
                      : Icons.queue_outlined,
                  size: 15,
                  color: active ? borderColor : foreground,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    plan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  button: true,
                  enabled: canDelete,
                  label: deleteTooltip,
                  child: Tooltip(
                    message: deleteTooltip,
                    child: canDelete
                        ? deleteButton
                        : AbsorbPointer(child: deleteButton),
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

class _QueueOverviewPanel extends StatelessWidget {
  final ProductionQueueViewModel viewModel;

  const _QueueOverviewPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final plan = viewModel.selectedPlan;
    final activePlan = viewModel.activePlan;
    final isExecuting = viewModel.isExecuting;
    final isPaused = viewModel.isPaused;
    final isViewingActivePlan = viewModel.isViewingActivePlan;
    final isWaitingForPause = isExecuting && viewModel.pauseRequested;
    final canContinue = viewModel.canResume;
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
                : viewModel.canStartSelectedPlan
                    ? viewModel.start
                    : null;
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
                child: _ProductionQueueTabs(
                  viewModel: viewModel,
                  onDeletePlan: (plan) => unawaited(
                    _deleteProductionPlan(context, viewModel, plan),
                  ),
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
          if (!isViewingActivePlan && activePlan != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('studio-production-read-only-queue-notice'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: StudioTokens.warning.withValues(alpha: 0.12),
                borderRadius: StudioTokens.radiusTag,
                border: Border.all(
                  color: StudioTokens.warning.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                '“${activePlan.name}”正在运行；当前仅查看“${plan?.name ?? ''}”，不会改变排队顺序。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textSecondary,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            key: const ValueKey('studio-production-queue-stats-actions'),
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
              Semantics(
                button: true,
                enabled: viewModel.canClearCompletedTasks,
                label: viewModel.completedTasksPendingDismissal > 0
                    ? '清理已完成：可清理 ${viewModel.completedTasksPendingDismissal} 个任务，生成结果保留'
                    : '清理已完成：暂无可清理任务，生成结果保留',
                child: Tooltip(
                  message: viewModel.completedTasksPendingDismissal > 0
                      ? '可清理 ${viewModel.completedTasksPendingDismissal} 个已完成任务；生成结果保留'
                      : '暂无可清理的已完成任务；生成结果保留',
                  child: StudioButton(
                    key: const ValueKey('studio-production-clear-completed'),
                    icon: Icons.cleaning_services_outlined,
                    label: '清理已完成',
                    tone: StudioButtonTone.secondary,
                    onPressed: viewModel.canClearCompletedTasks
                        ? () => unawaited(
                              _clearCompletedProductionTasks(
                                  context, viewModel),
                            )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProductionQueueCommandRow(
            viewModel: viewModel,
            primaryIcon: primaryIcon,
            primaryLabel: primaryLabel,
            primaryTone: primaryTone,
            primaryAction: primaryAction,
          ),
        ],
      ),
    );
  }
}

class _ProductionQueueCommandRow extends StatelessWidget {
  final ProductionQueueViewModel viewModel;
  final IconData primaryIcon;
  final String primaryLabel;
  final StudioButtonTone primaryTone;
  final VoidCallback? primaryAction;

  const _ProductionQueueCommandRow({
    required this.viewModel,
    required this.primaryIcon,
    required this.primaryLabel,
    required this.primaryTone,
    required this.primaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final primaryButton = StudioButton(
      key: const ValueKey('studio-production-start'),
      icon: primaryIcon,
      label: primaryLabel,
      tone: primaryTone,
      onPressed: primaryAction,
    );
    final secondaryCommands = <Widget>[
      StudioIconButton(
        key: const ValueKey('studio-production-hard-stop'),
        icon: Icons.stop_circle_outlined,
        tooltip: '停止产线并从头开始',
        onPressed: viewModel.canStop ? () => unawaited(viewModel.stop()) : null,
      ),
      StudioIconButton(
        key: const ValueKey('studio-production-resume'),
        icon: Icons.history,
        tooltip: '继续',
        onPressed:
            viewModel.canResume ? () => unawaited(viewModel.resume()) : null,
      ),
      StudioButton(
        key: const ValueKey('studio-production-retry-failed'),
        icon: Icons.refresh,
        label: '重跑异常',
        tone: StudioButtonTone.secondary,
        onPressed: viewModel.activePlan == null && viewModel.hasAbnormalTasks
            ? () => unawaited(viewModel.rerunAbnormalTasks())
            : null,
      ),
      StudioIconButton(
        key: const ValueKey('studio-production-clear-current'),
        icon: Icons.delete_sweep_outlined,
        tooltip: '清空当前产线',
        onPressed: viewModel.canClearCurrentPlan
            ? () => unawaited(viewModel.clearCurrentPlan())
            : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: constraints.maxWidth,
                child: primaryButton,
              ),
              ...secondaryCommands,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: primaryButton),
            for (final command in secondaryCommands) ...[
              const SizedBox(width: 8),
              command,
            ],
          ],
        );
      },
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
          if (!viewModel.canEditSelectedPlanSettings) ...[
            const SizedBox(height: 10),
            const StudioChip(
              icon: Icons.lock_outline,
              label: '其他队列正在运行，当前设置为只读',
            ),
          ],
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
                    ? '重试 无限 · 重跑间隔 ${viewModel.retryOn429DelaySeconds}s'
                    : '重试次数 ${viewModel.retryCount} · 重跑间隔 ${viewModel.retryOn429DelaySeconds}s',
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
    final canEdit = viewModel.canEditSelectedPlanSettings;
    final samplerOptions = _samplerOptionsForModel(generationSettings.model);
    final noiseScheduleOptions =
        _noiseScheduleOptionsForModel(generationSettings.model);
    final isV4 = generationSettings.model.contains('diffusion-4');
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 20) / 3
            : constraints.maxWidth >= 520
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
        final advancedTileWidth = constraints.maxWidth >= 1180
            ? (constraints.maxWidth - 32) / 3
            : constraints.maxWidth >= 620
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
        final coreTiles = <Widget>[
          _GenerationParameterTile(
            width: tileWidth,
            icon: Icons.memory_outlined,
            label: '模型',
            tooltip: _modelTooltip,
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
            tooltip: _sizeTooltip,
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
            tooltip: _samplerTooltip,
            useOriginal: viewModel.useOriginalSampler,
            switchKey: const ValueKey('studio-production-sampler-use-original'),
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
            tooltip: _stepsTooltip,
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
            tooltip: _cfgTooltip,
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
            icon: Icons.tonality_outlined,
            label: 'CFG Rescale',
            tooltip: _cfgRescaleTooltip,
            useOriginal: viewModel.useOriginalCfgRescale,
            switchKey: const ValueKey(
              'studio-production-cfg-rescale-use-original',
            ),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalCfgRescale,
            child: _BatchSettingTextField(
              key: const ValueKey('studio-production-cfg-rescale-input'),
              value: _formatNullableDouble(
                viewModel.useOriginalCfgRescale
                    ? generationSettings.cfgRescale
                    : viewModel.batchCfgRescale,
              ),
              label: '0.0~1.0',
              enabled: canEdit && !viewModel.useOriginalCfgRescale,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.setBatchCfgRescaleText,
            ),
          ),
          _GenerationParameterTile(
            width: tileWidth,
            icon: Icons.waves_outlined,
            label: '噪声调度',
            tooltip: _noiseScheduleTooltip,
            useOriginal: viewModel.useOriginalNoiseSchedule,
            switchKey: const ValueKey(
              'studio-production-noise-schedule-use-original',
            ),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalNoiseSchedule,
            child: _BatchSettingSelectField(
              key: const ValueKey(
                'studio-production-noise-schedule-select',
              ),
              value: viewModel.useOriginalNoiseSchedule
                  ? generationSettings.noiseSchedule
                  : viewModel.batchNoiseSchedule,
              label: 'schedule',
              options: noiseScheduleOptions,
              enabled: canEdit && !viewModel.useOriginalNoiseSchedule,
              onChanged: viewModel.setBatchNoiseSchedule,
            ),
          ),
          _GenerationParameterTile(
            width: tileWidth,
            icon: Icons.casino_outlined,
            label: 'Seed',
            tooltip: _seedTooltip,
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
        ];
        final advancedTiles = <Widget>[
          _GenerationParameterTile(
            width: advancedTileWidth,
            icon: Icons.auto_fix_high_outlined,
            label: 'SMEA',
            tooltip: _smeaTooltip,
            useOriginal: viewModel.useOriginalSm,
            switchKey: const ValueKey('studio-production-sm-use-original'),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalSm,
            child: _BatchSettingSwitchField(
              key: const ValueKey('studio-production-sm-switch'),
              value: (viewModel.useOriginalSm
                      ? generationSettings.sm
                      : viewModel.batchSm) ??
                  false,
              enabled: canEdit && !viewModel.useOriginalSm && !isV4,
              onChanged: viewModel.setBatchSm,
            ),
          ),
          _GenerationParameterTile(
            width: advancedTileWidth,
            icon: Icons.auto_awesome_motion_outlined,
            label: 'SMEA DYN',
            tooltip: _smeaDynTooltip,
            useOriginal: viewModel.useOriginalSmDyn,
            switchKey: const ValueKey('studio-production-sm-dyn-use-original'),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalSmDyn,
            child: _BatchSettingSwitchField(
              key: const ValueKey('studio-production-sm-dyn-switch'),
              value: (viewModel.useOriginalSmDyn
                      ? generationSettings.smDyn
                      : viewModel.batchSmDyn) ??
                  false,
              enabled: canEdit && !viewModel.useOriginalSmDyn && !isV4,
              onChanged: viewModel.setBatchSmDyn,
            ),
          ),
          _GenerationParameterTile(
            width: advancedTileWidth,
            icon: Icons.dynamic_form_outlined,
            label: '动态阈值',
            tooltip: _dynamicThresholdingTooltip,
            useOriginal: viewModel.useOriginalDynamicThresholding,
            switchKey: const ValueKey(
              'studio-production-dynamic-thresholding-use-original',
            ),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalDynamicThresholding,
            child: _BatchSettingSwitchField(
              key: const ValueKey(
                'studio-production-dynamic-thresholding-switch',
              ),
              value: (viewModel.useOriginalDynamicThresholding
                      ? generationSettings.dynamicThresholding
                      : viewModel.batchDynamicThresholding) ??
                  false,
              enabled: canEdit && !viewModel.useOriginalDynamicThresholding,
              onChanged: viewModel.setBatchDynamicThresholding,
            ),
          ),
          _GenerationParameterTile(
            width: advancedTileWidth,
            icon: Icons.shuffle_outlined,
            label: 'Variety+',
            tooltip: _varietyPlusTooltip,
            useOriginal: viewModel.useOriginalVarietyPlus,
            switchKey: const ValueKey('studio-production-variety-use-original'),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalVarietyPlus,
            child: _BatchSettingSwitchField(
              key: const ValueKey('studio-production-variety-switch'),
              value: (viewModel.useOriginalVarietyPlus
                      ? generationSettings.varietyPlus
                      : viewModel.batchVarietyPlus) ??
                  false,
              enabled: canEdit && !viewModel.useOriginalVarietyPlus,
              onChanged: viewModel.setBatchVarietyPlus,
            ),
          ),
          _GenerationParameterTile(
            width: advancedTileWidth,
            icon: Icons.location_searching_outlined,
            label: '自动位置',
            tooltip: _autoPositionTooltip,
            useOriginal: viewModel.useOriginalAutoPosition,
            switchKey: const ValueKey(
              'studio-production-auto-position-use-original',
            ),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalAutoPosition,
            child: _BatchSettingSwitchField(
              key: const ValueKey('studio-production-auto-position-switch'),
              value: (viewModel.useOriginalAutoPosition
                      ? generationSettings.autoPosition
                      : viewModel.batchAutoPosition) ??
                  false,
              enabled: canEdit && !viewModel.useOriginalAutoPosition && isV4,
              onChanged: viewModel.setBatchAutoPosition,
            ),
          ),
          _GenerationParameterTile(
            width: advancedTileWidth,
            icon: Icons.history_toggle_off_outlined,
            label: 'Legacy UC',
            tooltip: _legacyUcTooltip,
            useOriginal: viewModel.useOriginalLegacyUc,
            switchKey:
                const ValueKey('studio-production-legacy-uc-use-original'),
            canChange: canEdit,
            onUseOriginalChanged: viewModel.setUseOriginalLegacyUc,
            child: _BatchSettingSwitchField(
              key: const ValueKey('studio-production-legacy-uc-switch'),
              value: (viewModel.useOriginalLegacyUc
                      ? generationSettings.legacyUc
                      : viewModel.batchLegacyUc) ??
                  false,
              enabled: canEdit && !viewModel.useOriginalLegacyUc,
              onChanged: viewModel.setBatchLegacyUc,
            ),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BatchParameterGroupLabel(label: '核心生成参数'),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 10, children: coreTiles),
            const SizedBox(height: 12),
            ExpansionTile(
              key: const ValueKey('studio-production-advanced-expansion'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              title: const _BatchParameterGroupLabel(label: '高级生成参数'),
              subtitle: const Text('SMEA、动态阈值、Variety+、角色位置与 Legacy UC'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    children: advancedTiles,
                  ),
                ),
              ],
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
    final canEdit = viewModel.canEditSelectedPlanSettings;
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
              tooltip: _intervalTooltip,
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
              tooltip: _randomIntervalTooltip,
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
              tooltip: _retryTooltip,
              child: _BatchRetrySettingField(
                value: viewModel.retryCount.toString(),
                retryOn429DelayValue:
                    viewModel.retryOn429DelaySeconds.toString(),
                enabled: canEdit,
                retryIndefinitely: viewModel.retryIndefinitely,
                onCountChanged: viewModel.setRetryCountText,
                onRetryOn429DelayChanged:
                    viewModel.setRetryOn429DelaySecondsText,
                onRetryIndefinitelyChanged: viewModel.setRetryIndefinitely,
              ),
            ),
            _RuntimeSettingTile(
              width: tileWidth,
              icon: Icons.folder_outlined,
              label: '输出',
              tooltip: _outputTooltip,
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
  final String tooltip;
  final Widget child;

  const _RuntimeSettingTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.tooltip,
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
              _BatchHelpIcon(
                icon: icon,
                tooltip: tooltip,
                color: StudioTokens.textSecondary,
              ),
              const SizedBox(width: 8),
              _BatchTermLabel(label: label),
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
  final String tooltip;
  final bool useOriginal;
  final Key switchKey;
  final bool canChange;
  final ValueChanged<bool> onUseOriginalChanged;
  final Widget child;

  const _GenerationParameterTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.tooltip,
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
              _BatchHelpIcon(
                icon: icon,
                tooltip: tooltip,
                color: useOriginal ? StudioTokens.warning : StudioTokens.active,
              ),
              const SizedBox(width: 8),
              _BatchTermLabel(label: label),
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

class _BatchParameterGroupLabel extends StatelessWidget {
  final String label;

  const _BatchParameterGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: StudioTokens.textSecondary,
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _BatchTermLabel extends StatelessWidget {
  final String label;

  const _BatchTermLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _BatchHelpIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;

  const _BatchHelpIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: SizedBox(
        width: 18,
        height: 18,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 18, color: color),
            const Positioned(
              right: -3,
              top: -5,
              child: Icon(
                Icons.priority_high_rounded,
                size: 11,
                color: StudioTokens.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchSettingSwitchField extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _BatchSettingSwitchField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            value ? '开启' : '关闭',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: enabled
                      ? StudioTokens.textPrimary
                      : StudioTokens.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
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
  final String retryOn429DelayValue;
  final bool enabled;
  final bool retryIndefinitely;
  final ValueChanged<String> onCountChanged;
  final ValueChanged<String> onRetryOn429DelayChanged;
  final ValueChanged<bool> onRetryIndefinitelyChanged;

  const _BatchRetrySettingField({
    required this.value,
    required this.retryOn429DelayValue,
    required this.enabled,
    required this.retryIndefinitely,
    required this.onCountChanged,
    required this.onRetryOn429DelayChanged,
    required this.onRetryIndefinitelyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _BatchSettingTextField(
                key: const ValueKey('studio-production-retry-input'),
                value: value,
                label: '次数',
                enabled: enabled && !retryIndefinitely,
                keyboardType: TextInputType.number,
                onChanged: onCountChanged,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '无限重试',
              child: Checkbox(
                key: const ValueKey('studio-production-retry-infinite'),
                value: retryIndefinitely,
                onChanged: enabled
                    ? (value) => onRetryIndefinitelyChanged(value ?? false)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _BatchSettingTextField(
          key: const ValueKey('studio-production-429-delay-input'),
          value: retryOn429DelayValue,
          label: '重跑间隔',
          enabled: enabled,
          keyboardType: TextInputType.number,
          onChanged: onRetryOn429DelayChanged,
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
  final double? cfgRescale;
  final String noiseSchedule;
  final bool? sm;
  final bool? smDyn;
  final bool? dynamicThresholding;
  final bool? varietyPlus;
  final bool? autoPosition;
  final bool? legacyUc;
  final int? seed;

  const _BatchGenerationSettings({
    required this.model,
    required this.sampler,
    required this.width,
    required this.height,
    required this.steps,
    required this.scale,
    required this.cfgRescale,
    required this.noiseSchedule,
    required this.sm,
    required this.smDyn,
    required this.dynamicThresholding,
    required this.varietyPlus,
    required this.autoPosition,
    required this.legacyUc,
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
    final v4Prompt = _mapValue(parameters['v4_prompt']);
    final v4NegativePrompt = _mapValue(parameters['v4_negative_prompt']);
    final originalUseCoords = _boolValue(v4Prompt['use_coords']);
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
      cfgRescale: _doubleValue(parameters['cfg_rescale']) ??
          _doubleValue(payload['cfg_rescale']) ??
          settings.cfgRescale,
      noiseSchedule: _stringValue(parameters['noise_schedule']) ??
          _stringValue(payload['noise_schedule']) ??
          settings.noiseSchedule,
      sm: _boolValue(parameters['sm']) ??
          _boolValue(payload['sm']) ??
          settings.sm,
      smDyn: _boolValue(parameters['sm_dyn']) ??
          _boolValue(payload['sm_dyn']) ??
          settings.smDyn,
      dynamicThresholding: _boolValue(parameters['dynamic_thresholding']) ??
          _boolValue(payload['dynamic_thresholding']) ??
          settings.dynamicThresholding,
      varietyPlus: parameters.containsKey('skip_cfg_above_sigma')
          ? parameters['skip_cfg_above_sigma'] != null
          : settings.varietyPlus,
      autoPosition: originalUseCoords == null
          ? settings.autoPosition
          : !originalUseCoords,
      legacyUc: _boolValue(v4NegativePrompt['legacy_uc']) ??
          _boolValue(parameters['legacy_uc']) ??
          settings.legacyUc,
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
      cfgRescale: viewModel.useOriginalCfgRescale
          ? original.cfgRescale
          : viewModel.batchCfgRescale,
      noiseSchedule: viewModel.useOriginalNoiseSchedule
          ? original.noiseSchedule
          : viewModel.batchNoiseSchedule,
      sm: viewModel.useOriginalSm ? original.sm : viewModel.batchSm,
      smDyn: viewModel.useOriginalSmDyn ? original.smDyn : viewModel.batchSmDyn,
      dynamicThresholding: viewModel.useOriginalDynamicThresholding
          ? original.dynamicThresholding
          : viewModel.batchDynamicThresholding,
      varietyPlus: viewModel.useOriginalVarietyPlus
          ? original.varietyPlus
          : viewModel.batchVarietyPlus,
      autoPosition: viewModel.useOriginalAutoPosition
          ? original.autoPosition
          : viewModel.batchAutoPosition,
      legacyUc: viewModel.useOriginalLegacyUc
          ? original.legacyUc
          : viewModel.batchLegacyUc,
      seed: viewModel.useOriginalSeed ? original.seed : viewModel.batchSeed,
    );
  }
}

class _ProductionTaskGroup {
  final String id;
  final List<ProductionTask> tasks;

  const _ProductionTaskGroup({
    required this.id,
    required this.tasks,
  });

  ProductionTask get primaryTask => tasks.first;

  int get variantCount => tasks.length;

  String get title => _variantTitle(primaryTask.title, variantCount);

  bool containsTaskId(String? taskId) =>
      taskId != null && tasks.any((task) => task.id == taskId);

  ProductionTask displayTask(String? selectedTaskId) {
    if (selectedTaskId != null) {
      for (final task in tasks) {
        if (task.id == selectedTaskId) return task;
      }
    }
    return tasks.last;
  }
}

final Expando<List<_ProductionTaskGroup>> _productionTaskGroupsCache =
    Expando<List<_ProductionTaskGroup>>('production-task-groups');

List<_ProductionTaskGroup> _productionTaskGroups(List<ProductionTask> tasks) {
  final cached = _productionTaskGroupsCache[tasks];
  if (cached != null) return cached;
  final orderedKeys = <String>[];
  final grouped = <String, List<ProductionTask>>{};
  for (final task in tasks) {
    final key = _productionTaskGroupKey(task);
    grouped.putIfAbsent(key, () {
      orderedKeys.add(key);
      return <ProductionTask>[];
    }).add(task);
  }
  final groups = [
    for (final key in orderedKeys)
      _ProductionTaskGroup(
        id: grouped[key]!.first.id,
        tasks: List.unmodifiable(grouped[key]!),
      ),
  ];
  _productionTaskGroupsCache[tasks] = groups;
  return groups;
}

String _productionTaskGroupKey(ProductionTask task) {
  if (task.taskType == ProductionTaskType.scriptRecastFrame &&
      task.source.frameIndex != null) {
    final source = task.source;
    return [
      task.planId,
      task.taskType.name,
      source.scriptId ?? '',
      source.recastRunId ?? '',
      source.mappingConfigFingerprint ?? '',
      source.frameIndex,
      source.sourceFileName ?? '',
    ].join('|');
  }
  return '${task.planId}|${task.id}';
}

String _variantTitle(String title, int count) {
  return count > 1 ? '$title x$count' : title;
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
    final tasks = viewModel.visibleTasksForPlan(viewModel.selectedPlan);
    final groups = _productionTaskGroups(tasks);
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
          if (groups.isEmpty)
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
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final selected = group.containsTaskId(
                    viewModel.selectedTask?.id,
                  );
                  final task = group.displayTask(viewModel.selectedTask?.id);
                  return _TaskRow(
                    task: task,
                    title: group.title,
                    selected: selected,
                    onSelect: () => viewModel.selectTask(task),
                    onRerun: () {
                      unawaited(viewModel.quickRerunTask(task));
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
  final String title;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRerun;

  const _TaskRow({
    required this.task,
    required this.title,
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
                      title,
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
    final tasks = viewModel.visibleTasksForPlan(viewModel.selectedPlan);
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
                  unawaited(viewModel.quickRerunTask(task));
                },
                onOpen: (task) {
                  viewModel.selectTask(task);
                  _showProductionResultDetails(
                    context,
                    viewModel: viewModel,
                    task: task,
                    tasks: tasks,
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
    final groups = _productionTaskGroups(tasks);
    if (groups.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 250;
        final columns = max(1, width ~/ 250);
        return WaterfallFlow.builder(
          key: const ValueKey('studio-production-results-waterfall'),
          primary: false,
          shrinkWrap: !scrollable,
          physics: scrollable
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return _ProductionResultGroupCard(
              group: group,
              selected: group.containsTaskId(selectedTaskId),
              selectedTaskId: selectedTaskId,
              onOpen: onOpen,
              onQuickRerun: onQuickRerun,
            );
          },
        );
      },
    );
  }
}

class _ProductionResultGroupCard extends StatelessWidget {
  final _ProductionTaskGroup group;
  final bool selected;
  final String? selectedTaskId;
  final ValueChanged<ProductionTask> onOpen;
  final ValueChanged<ProductionTask> onQuickRerun;

  const _ProductionResultGroupCard({
    required this.group,
    required this.selected,
    required this.selectedTaskId,
    required this.onOpen,
    required this.onQuickRerun,
  });

  @override
  Widget build(BuildContext context) {
    final task = group.displayTask(selectedTaskId);
    return _ProductionResultCardSurface(
      key: ValueKey('studio-production-result-card-${group.id}'),
      group: group,
      task: task,
      previewPath: null,
      selected: selected,
      onOpen: () => onOpen(task),
      onQuickRerun: () => onQuickRerun(task),
    );
  }
}

class _ProductionResultCardSurface extends StatelessWidget {
  final _ProductionTaskGroup group;
  final ProductionTask task;
  final String? previewPath;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onQuickRerun;

  const _ProductionResultCardSurface({
    super.key,
    required this.group,
    required this.task,
    required this.previewPath,
    required this.selected,
    required this.onOpen,
    required this.onQuickRerun,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? StudioTokens.primary.withAlpha(18) : StudioTokens.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: StudioTokens.radiusCard,
        side: BorderSide(
          color: selected ? StudioTokens.primary : StudioTokens.cardOutline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                _ProductionResultCardImage(
                  task: task,
                  previewPath: previewPath,
                  imageKey: ValueKey(
                    'studio-production-result-image-${group.id}',
                  ),
                ),
                if (task.source.frameIndex != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _ProductionFrameBadge(
                      key: ValueKey(
                        'studio-production-result-frame-badge-${group.id}',
                      ),
                      frameIndex: task.source.frameIndex!,
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: StudioIconButton(
                    key: ValueKey('studio-production-quick-rerun-${group.id}'),
                    icon: Icons.replay,
                    tooltip: '\u63d2\u961f\u91cd\u8dd1',
                    onPressed: onQuickRerun,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                group.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductionFrameBadge extends StatelessWidget {
  final int frameIndex;

  const _ProductionFrameBadge({
    super.key,
    required this.frameIndex,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '$frameIndex',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _ProductionResultCardImage extends StatelessWidget {
  final ProductionTask task;
  final String? previewPath;
  final Key imageKey;

  const _ProductionResultCardImage({
    required this.task,
    required this.previewPath,
    required this.imageKey,
  });

  @override
  Widget build(BuildContext context) {
    final path = previewPath ?? task.outputImagePath?.trim();
    final cacheRevision = _imageCacheRevision(task);
    final outputFile = _existingOutputFile(
      path,
      cacheRevision: cacheRevision,
    );
    return AspectRatio(
      aspectRatio: _taskAspectRatio(task),
      child: ColoredBox(
        color: StudioTokens.surfaceBase,
        child: outputFile == null
            ? _ResultPreviewPlaceholder(
                icon: _resultPreviewIcon(task.status),
                title: _resultPreviewTitle(task),
                subtitle: path?.isNotEmpty == true ? path : task.error,
              )
            : _ProductionFileImage(
                key: imageKey,
                file: outputFile,
                fit: BoxFit.cover,
                cacheRevision: cacheRevision,
                maxDecodeExtent: _productionCardMaxDecodeExtent,
                errorBuilder: (context, error, stackTrace) {
                  return _ResultPreviewPlaceholder(
                    icon: Icons.broken_image_outlined,
                    title: '\u7ed3\u679c\u56fe\u7247\u65e0\u6cd5\u8bfb\u53d6',
                    subtitle: path,
                  );
                },
              ),
      ),
    );
  }
}

double _taskAspectRatio(ProductionTask task) {
  final parameters = _mapValue(task.payload['parameters']);
  final width =
      _intValue(parameters['width']) ?? _intValue(task.payload['width']);
  final height =
      _intValue(parameters['height']) ?? _intValue(task.payload['height']);
  if (width != null && width > 0 && height != null && height > 0) {
    return width / height;
  }
  return 1;
}

class _ProductionFileImage extends StatefulWidget {
  final File file;
  final BoxFit fit;
  final String cacheRevision;
  final int maxDecodeExtent;
  final ImageErrorWidgetBuilder errorBuilder;

  const _ProductionFileImage({
    super.key,
    required this.file,
    required this.fit,
    required this.cacheRevision,
    required this.maxDecodeExtent,
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
        oldWidget.cacheRevision != widget.cacheRevision ||
        oldWidget.maxDecodeExtent != widget.maxDecodeExtent) {
      _evictCurrentFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      key: ValueKey(
          'production-image-${widget.file.path}-${widget.cacheRevision}'),
      image: _imageProvider(),
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
    );
  }

  ImageProvider<Object> _imageProvider() {
    return ResizeImage(
      FileImage(widget.file),
      width: widget.maxDecodeExtent,
      height: widget.maxDecodeExtent,
      policy: ResizeImagePolicy.fit,
    );
  }

  void _evictCurrentFile() {
    try {
      unawaited(
        _imageProvider().evict().catchError((_) => false),
      );
    } catch (_) {
      // Bad or transient file paths should fall back to the card placeholder.
    }
  }
}

final Map<String, File?> _existingOutputFileCache = {};

File? _existingOutputFile(
  String? outputPath, {
  String cacheRevision = '',
}) {
  final trimmed = outputPath?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final cacheKey = '$trimmed\n$cacheRevision';
  if (_existingOutputFileCache.containsKey(cacheKey)) {
    return _existingOutputFileCache[cacheKey];
  }
  try {
    final file = File(trimmed);
    final result = file.existsSync() ? file : null;
    if (_existingOutputFileCache.length > 512) {
      _existingOutputFileCache.clear();
    }
    _existingOutputFileCache[cacheKey] = result;
    return result;
  } catch (_) {
    _existingOutputFileCache[cacheKey] = null;
    return null;
  }
}

const _productionCardMaxDecodeExtent = 768;
const _productionDetailMaxDecodeExtent = 1024;
const _productionZoomMaxDecodeExtent = 2048;

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

List<ProductionTask> _productionTaskVariantsFor(
  List<ProductionTask> tasks,
  ProductionTask task,
) {
  for (final group in _productionTaskGroups(tasks)) {
    if (group.containsTaskId(task.id)) return group.tasks;
  }
  return [task];
}

void _showProductionResultDetails(
  BuildContext context, {
  required ProductionQueueViewModel viewModel,
  required ProductionTask task,
  required List<ProductionTask> tasks,
}) {
  final variants = _productionTaskVariantsFor(tasks, task);
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
          child: StudioScrollbar(
            child: SingleChildScrollView(
              child: _ProductionResultDetailContent(
                viewModel: viewModel,
                task: task,
                variants: variants,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ProductionResultDetailContent extends StatefulWidget {
  final ProductionQueueViewModel viewModel;
  final ProductionTask task;
  final List<ProductionTask> variants;

  const _ProductionResultDetailContent({
    required this.viewModel,
    required this.task,
    required this.variants,
  });

  @override
  State<_ProductionResultDetailContent> createState() =>
      _ProductionResultDetailContentState();
}

class _ProductionResultDetailContentState
    extends State<_ProductionResultDetailContent> {
  late int _variantIndex;

  ProductionTask get _task => _variants[_variantIndex];

  List<ProductionTask> get _variants =>
      widget.variants.isEmpty ? [widget.task] : widget.variants;

  @override
  void initState() {
    super.initState();
    _variantIndex = _initialVariantIndex();
  }

  @override
  void didUpdateWidget(covariant _ProductionResultDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.variants.length != widget.variants.length) {
      _variantIndex = _initialVariantIndex();
    }
  }

  int _initialVariantIndex() {
    final variants = _variants;
    final index = variants.indexWhere((task) => task.id == widget.task.id);
    return index < 0 ? 0 : index;
  }

  void _switchVariant(int delta) {
    final variants = _variants;
    if (variants.length < 2) return;
    setState(() {
      _variantIndex = (_variantIndex + delta) % variants.length;
      if (_variantIndex < 0) _variantIndex = variants.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final variants = _variants;
    final viewModel = widget.viewModel;
    final positivePromptGroups = _positivePromptGroups(task.payload);
    final negativePromptGroups = _negativePromptGroups(task.payload);
    final positivePrompt = _positivePrompt(task.payload);
    final negativePrompt = _negativePrompt(task.payload);
    final parameterGroups = _visibleParameterGroups(task.payload);
    final cacheRevision = _imageCacheRevision(task);
    final outputFile = _existingOutputFile(
      task.outputImagePath,
      cacheRevision: cacheRevision,
    );
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
                label: '? ${task.source.frameIndex ?? '-'}',
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
          _DetailLine('??', task.id),
          _DetailLine('??', task.source.scriptId ?? '-'),
          _DetailLine('Run', task.source.recastRunId ?? '-'),
          _DetailLine('??', task.outputImagePath ?? '-'),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelHeading(
          icon: Icons.image_outlined,
          title: _variantTitle(task.title, variants.length),
          trailing: StudioIconButton(
            icon: Icons.close,
            tooltip: '??',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: 12),
        _TaskResultPreview(
          task: task,
          variantCount: variants.length,
          onVariantScroll: _switchVariant,
        ),
        if (variants.length > 1) ...[
          const SizedBox(height: 8),
          _ProductionVariantDots(
            groupId: variants.first.id,
            count: variants.length,
            index: _variantIndex,
            onSelect: (index) {
              setState(() {
                _variantIndex = index;
              });
            },
          ),
        ],
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
              label: const Text(
                  '\u5728\u8d44\u6e90\u7ba1\u7406\u5668\u4e2d\u663e\u793a'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _PromptTagBlock(
          key: const ValueKey('studio-production-positive-prompt'),
          title: '\u6b63\u5411\u63d0\u793a\u8bcd',
          text: positivePrompt.isEmpty ? '-' : positivePrompt,
          groups: positivePromptGroups,
          tagKey: const ValueKey('studio-production-positive-prompt-tags'),
        ),
        if (negativePromptGroups.isNotEmpty || negativePrompt.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PromptTagBlock(
            key: const ValueKey('studio-production-negative-prompt'),
            title: '\u8d1f\u5411\u63d0\u793a\u8bcd',
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

class _ProductionVariantDots extends StatelessWidget {
  final String groupId;
  final int count;
  final int index;
  final ValueChanged<int> onSelect;

  const _ProductionVariantDots({
    required this.groupId,
    required this.count,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        key: const ValueKey('studio-production-result-variant-dots'),
        spacing: 7,
        runSpacing: 7,
        children: [
          for (var dotIndex = 0; dotIndex < count; dotIndex += 1)
            GestureDetector(
              key: ValueKey(
                'studio-production-result-variant-dot-$groupId-$dotIndex',
              ),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(dotIndex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: dotIndex == index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotIndex == index
                      ? StudioTokens.primary
                      : StudioTokens.textMuted.withAlpha(120),
                  borderRadius: StudioTokens.radiusPill,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskResultPreview extends StatelessWidget {
  final ProductionTask task;
  final int variantCount;
  final ValueChanged<int>? onVariantScroll;

  const _TaskResultPreview({
    required this.task,
    this.variantCount = 1,
    this.onVariantScroll,
  });

  @override
  Widget build(BuildContext context) {
    final outputPath = task.outputImagePath?.trim();
    final hasOutputPath = outputPath != null && outputPath.isNotEmpty;
    final cacheRevision = _imageCacheRevision(task);
    final outputFile = _existingOutputFile(
      outputPath,
      cacheRevision: cacheRevision,
    );
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
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: _handlePointerSignal,
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
                            cacheRevision: cacheRevision,
                            maxDecodeExtent: _productionDetailMaxDecodeExtent,
                            errorBuilder: (context, error, stackTrace) {
                              return _ResultPreviewPlaceholder(
                                icon: Icons.broken_image_outlined,
                                title:
                                    '\u7ed3\u679c\u56fe\u7247\u65e0\u6cd5\u8bfb\u53d6',
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
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final onScroll = onVariantScroll;
    if (event is! PointerScrollEvent || variantCount < 2 || onScroll == null) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      final delta = scrollEvent.scrollDelta.dy == 0
          ? scrollEvent.scrollDelta.dx
          : scrollEvent.scrollDelta.dy;
      if (delta == 0) return;
      onScroll(delta > 0 ? 1 : -1);
    });
  }
}

void _showProductionImageZoomDialog(
  BuildContext context,
  ProductionTask task,
) {
  final cacheRevision = _imageCacheRevision(task);
  final outputFile = _existingOutputFile(
    task.outputImagePath,
    cacheRevision: cacheRevision,
  );
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
                cacheRevision: cacheRevision,
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
  late final StudioWheelZoomController _wheelZoom = StudioWheelZoomController(
    transformationController: _controller,
    minScale: _minScale,
    maxScale: _maxScale,
    requireControlModifier: true,
  );

  @override
  void dispose() {
    _wheelZoom.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          key: const ValueKey('studio-production-zoomable-image-viewer'),
          onPointerSignal: _wheelZoom.handlePointerSignal,
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
                maxDecodeExtent: _productionZoomMaxDecodeExtent,
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

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
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

List<String> _noiseScheduleOptionsForModel(String model) {
  if (model.contains('diffusion-4')) return noiseSchedulesV4;
  return noiseSchedules;
}

const _modelTooltip = '选择 NovelAI 的生成模型。不同模型支持的采样器和高级参数不同，切换模型会同步整理不兼容参数。';
const _sizeTooltip = '设置输出图像的宽度和高度。更大的尺寸通常需要更长生成时间，并会改变构图空间。';
const _samplerTooltip = '采样器决定模型逐步去噪的算法，会影响画面风格、细节、稳定性以及与噪声调度的组合效果。';
const _stepsTooltip = 'Steps 是去噪迭代次数。更多步数通常带来更充分的细化，但并非越高越好，也会增加生成时间。';
const _cfgTooltip =
    'CFG（Prompt Guidance）控制画面遵循提示词的强度。数值越高越贴近提示词，但过高可能带来过饱和、对比失衡或伪影。';
const _cfgRescaleTooltip = 'CFG Rescale 用于缓和较高 CFG 引起的过曝和色彩失真，同时尽量保留提示词引导。';
const _noiseScheduleTooltip =
    '噪声调度决定各个 Steps 如何分配去噪强度，会影响构图形成和细节收敛；部分模型不支持 native。';
const _seedTooltip =
    'Seed 是初始随机噪声。相同模型、参数、提示词和 Seed 有助于复现结果；-1 会让每个任务使用随机 Seed。';
const _smeaTooltip = 'SMEA 是 V3 模型的采样增强选项，用于改善部分尺寸下的构图与细节；V4 模型会忽略它。';
const _smeaDynTooltip = 'SMEA DYN 是动态版 SMEA，仅适用于 V3；它会进一步改变采样过程和构图表现。';
const _dynamicThresholdingTooltip =
    '动态阈值会限制去噪过程中的极端响应，常用于减轻高引导强度下的过曝、颜色失控和细节崩坏。';
const _varietyPlusTooltip =
    'Variety+ 会在采样前段降低 CFG 的约束，让同一提示词产生更丰富的构图变化；批量执行会按当前尺寸计算配套阈值。';
const _autoPositionTooltip = '自动位置让 V4 模型自行安排角色提示词的位置，而不是使用固定坐标；V3 模型不使用此选项。';
const _legacyUcTooltip = 'Legacy UC 使用旧版负面提示词解释方式，主要用于复现旧参数或兼容旧作品。';
const _intervalTooltip = '每个请求完成后等待的基础秒数，可用于控制请求节奏。';
const _randomIntervalTooltip = '在基础间隔上额外加入 0 到设定秒数的随机等待，避免请求节奏完全固定。';
const _retryTooltip = '任务请求失败时的重试策略；遇到 HTTP 429 时会使用单独的重跑间隔。';
const _outputTooltip = '生成图片和相关结果写入的本地目录。留空时由执行环境决定默认位置。';

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
