import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/services/studio_batch_plan_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class StudioBatchPage extends StatefulWidget {
  final GenerationPageViewmodel viewmodel;
  final StudioBatchPlanService batchPlanService;
  final Widget configEditor;
  final Widget resultPanel;

  const StudioBatchPage({
    super.key,
    required this.viewmodel,
    required this.batchPlanService,
    required this.configEditor,
    required this.resultPanel,
  });

  @override
  State<StudioBatchPage> createState() => _StudioBatchPageState();
}

class _StudioBatchPageState extends State<StudioBatchPage> {
  late Future<List<StudioBatchQueuePlan>> _plansFuture;
  String? _lastAppliedLabel;

  @override
  void initState() {
    super.initState();
    _plansFuture = widget.batchPlanService.loadQueuePlans();
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.configEditor;

    return Scaffold(
      backgroundColor: StudioTokens.surface1,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final queue = _BatchPlanQueuePanel(
            plansFuture: _plansFuture,
            lastAppliedLabel: _lastAppliedLabel,
            onReload: _reloadPlans,
            onApply: _applyQueueItem,
          );
          final controls = _BatchExecutionPanel(viewmodel: widget.viewmodel);
          final results = widget.resultPanel;
          if (constraints.maxWidth < 1180) {
            return ListView(
              key: const ValueKey('studio-batch-page-compact'),
              padding: const EdgeInsets.all(12),
              children: [
                SizedBox(height: 360, child: queue),
                const SizedBox(height: 12),
                SizedBox(height: 520, child: editor),
                const SizedBox(height: 12),
                controls,
                const SizedBox(height: 12),
                SizedBox(height: 620, child: results),
              ],
            );
          }

          return Padding(
            key: const ValueKey('studio-batch-page-wide'),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(width: 320, child: queue),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: editor),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      controls,
                      const SizedBox(height: 12),
                      Expanded(child: results),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _reloadPlans() {
    setState(() {
      _plansFuture = widget.batchPlanService.loadQueuePlans();
    });
  }

  void _applyQueueItem(StudioBatchQueueItem item) {
    final result = widget.batchPlanService.applyQueueItem(
      item: item,
      target: widget.viewmodel.payloadConfig,
    );
    setState(() {
      _lastAppliedLabel = item.title;
    });

    final changedParts = <String>[
      if (result.positivePrompt != null) 'Prompt',
      if (result.negativePrompt != null) '负面词',
      if (result.paramChangeCount > 0) '参数 ${result.paramChangeCount}',
      if (result.batchSettingChangeCount > 0)
        '批量 ${result.batchSettingChangeCount}',
    ];
    final changedLabel =
        changedParts.isEmpty ? '无可套用字段' : changedParts.join(' / ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已套用 ${item.title}: $changedLabel')),
    );
  }
}

class _BatchPlanQueuePanel extends StatelessWidget {
  final Future<List<StudioBatchQueuePlan>> plansFuture;
  final String? lastAppliedLabel;
  final VoidCallback onReload;
  final ValueChanged<StudioBatchQueueItem> onApply;

  const _BatchPlanQueuePanel({
    required this.plansFuture,
    required this.lastAppliedLabel,
    required this.onReload,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('studio-batch-queue-panel'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.queue_play_next, color: StudioTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '批量队列',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StudioIconButton(
                key: const ValueKey('studio-batch-refresh-plans'),
                tooltip: '刷新队列',
                icon: Icons.refresh,
                onPressed: onReload,
              ),
            ],
          ),
          if (lastAppliedLabel != null) ...[
            const SizedBox(height: 10),
            StudioChip(
              key: const ValueKey('studio-batch-last-applied'),
              icon: Icons.check_circle_outline,
              label: lastAppliedLabel!,
              selected: true,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<StudioBatchQueuePlan>>(
              future: plansFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _QueueEmptyState(
                    icon: Icons.error_outline,
                    title: '无法读取批量方案',
                    message: snapshot.error.toString(),
                  );
                }
                final plans = snapshot.data ?? const [];
                final itemCount = plans.fold<int>(
                  0,
                  (count, plan) => count + plan.items.length,
                );
                if (plans.isEmpty || itemCount == 0) {
                  return const _QueueEmptyState(
                    icon: Icons.playlist_add,
                    title: '暂无批量方案',
                    message: '素材库导入的 batch plans 会显示在这里。',
                  );
                }
                return ListView.separated(
                  itemCount: plans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _BatchPlanCard(
                      plan: plans[index],
                      onApply: onApply,
                    );
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

class _BatchPlanCard extends StatelessWidget {
  final StudioBatchQueuePlan plan;
  final ValueChanged<StudioBatchQueueItem> onApply;

  const _BatchPlanCard({
    required this.plan,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('studio-batch-plan-${plan.plan.id}'),
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
              Expanded(
                child: Text(
                  plan.plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              StudioChip(
                icon: Icons.segment,
                label: '${plan.items.length}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in plan.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BatchPlanItemRow(item: item, onApply: onApply),
            ),
        ],
      ),
    );
  }
}

class _BatchPlanItemRow extends StatelessWidget {
  final StudioBatchQueueItem item;
  final ValueChanged<StudioBatchQueueItem> onApply;

  const _BatchPlanItemRow({
    required this.item,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('studio-batch-plan-item-${item.id}'),
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase,
        borderRadius: StudioTokens.radiusBadge,
        border: Border.all(color: StudioTokens.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (item.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: StudioButton(
              key: ValueKey('studio-batch-apply-${item.id}'),
              label: '套用',
              icon: Icons.input,
              onPressed: () => onApply(item),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchExecutionPanel extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _BatchExecutionPanel({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('studio-batch-execution-panel'),
      color: StudioTokens.surface2,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          viewmodel,
          viewmodel.commandStatus.isBatchActive,
          viewmodel.commandStatus.isCoolingDown,
        ]),
        builder: (context, _) {
          final active = viewmodel.commandStatus.isBatchActive.value;
          final coolingDown = viewmodel.commandStatus.isCoolingDown.value;
          final settings = viewmodel.payloadConfig.settings;
          final runtime = viewmodel.payloadConfig.generationRuntimeState;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_tree_outlined,
                      color: StudioTokens.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '执行控制',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
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
                            ? '运行中'
                            : '待机',
                    selected: active || coolingDown,
                    accentColor: coolingDown
                        ? StudioTokens.warning
                        : StudioTokens.active,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StudioChip(
                    icon: Icons.image_outlined,
                    label: settings.numberOfRequests == 0
                        ? '总量 ∞'
                        : '总量 ${settings.numberOfRequests}',
                  ),
                  StudioChip(
                    icon: Icons.layers_outlined,
                    label: '每批 ${settings.batchCount}',
                  ),
                  StudioChip(
                    icon: Icons.timer_outlined,
                    label: '${settings.batchIntervalSec}s',
                  ),
                  StudioChip(
                    icon: Icons.replay_circle_filled_outlined,
                    label: settings.retryOn429Enabled
                        ? '429 ${settings.retryOn429DelaySec}s'
                        : '429 常规',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: StudioButton(
                      key: const ValueKey('studio-batch-start-stop'),
                      label: active ? '暂停批量' : '启动批量',
                      icon: active ? Icons.stop : Icons.play_arrow,
                      onPressed: active
                          ? viewmodel.stopBatch
                          : viewmodel.startBatchFromScratch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  StudioIconButton(
                    key: const ValueKey('studio-batch-resume-last'),
                    tooltip: '续跑上次',
                    icon: Icons.history,
                    onPressed: (!active && runtime.hasPendingBatchResume)
                        ? viewmodel.resumeBatchFromLast
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _BatchProgressStrip(viewmodel: viewmodel),
            ],
          );
        },
      ),
    );
  }
}

class _BatchProgressStrip extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _BatchProgressStrip({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    final settings = viewmodel.payloadConfig.settings;
    final total = settings.numberOfRequests;
    final current = viewmodel.commandStatus.currentTotalCount;
    final progress = total <= 0 ? null : (current / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                total <= 0 ? '已生成 $current' : '已生成 $current / $total',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(
              '当前批次 ${viewmodel.commandStatus.currentBatchCount}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: StudioTokens.radiusPill,
          child: LinearProgressIndicator(
            minHeight: 8,
            value: progress,
            backgroundColor: StudioTokens.surfaceBase,
            color: StudioTokens.primary,
          ),
        ),
      ],
    );
  }
}

class _QueueEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _QueueEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: StudioTokens.cardBorder,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: StudioTokens.textMuted),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
