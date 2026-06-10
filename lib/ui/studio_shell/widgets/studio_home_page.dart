import 'package:flutter/material.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_metric_card.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_shell/models/studio_shell_section.dart';

class StudioHomePage extends StatefulWidget {
  final StudioAssetCatalogService catalogService;
  final StudioGalleryService galleryService;
  final StudioWorkbenchAssetService workbenchAssetService;
  final PayloadConfig payloadConfig;
  final ValueChanged<StudioShellSection> onNavigate;

  const StudioHomePage({
    super.key,
    required this.catalogService,
    required this.galleryService,
    required this.workbenchAssetService,
    required this.payloadConfig,
    required this.onNavigate,
  });

  @override
  State<StudioHomePage> createState() => _StudioHomePageState();
}

class _StudioHomePageState extends State<StudioHomePage> {
  late Future<_StudioHomeSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  @override
  void didUpdateWidget(covariant StudioHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService ||
        oldWidget.galleryService != widget.galleryService) {
      _snapshotFuture = _loadSnapshot();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.workbenchAssetService,
      builder: (context, _) {
        return FutureBuilder<_StudioHomeSnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final isLoading = snapshot.connectionState != ConnectionState.done;
            final hasError = snapshot.hasError;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(StudioTokens.pagePadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HomeHero(
                        prompt: widget.payloadConfig.overridePrompt,
                        fragmentCount:
                            widget.workbenchAssetService.fragments.length,
                        onContinue: () => widget.onNavigate(
                          StudioShellSection.workbench,
                        ),
                        onOpenAssets: () => widget.onNavigate(
                          StudioShellSection.assets,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (hasError)
                        _HomeStatusPanel(
                          icon: Icons.error_outline,
                          title: '本地数据暂时不可用',
                          message: snapshot.error.toString(),
                          onRetry: _reload,
                        )
                      else
                        _MetricStrip(
                          isLoading: isLoading,
                          assetCount: data?.assetCount ?? 0,
                          galleryCount: data?.galleryCount ?? 0,
                          workbenchCount:
                              widget.workbenchAssetService.fragments.length,
                          batchCount:
                              widget.payloadConfig.settings.numberOfRequests,
                        ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final recentPanel = _RecentGalleryPanel(
                            records: data?.recentRecords ?? const [],
                            isLoading: isLoading,
                            onOpenGallery: () => widget.onNavigate(
                              StudioShellSection.gallery,
                            ),
                          );
                          final actionPanel = _ActionPanel(
                            onWorkbench: () => widget.onNavigate(
                              StudioShellSection.workbench,
                            ),
                            onBatch: () => widget.onNavigate(
                              StudioShellSection.batch,
                            ),
                            onSettings: () => widget.onNavigate(
                              StudioShellSection.settings,
                            ),
                          );
                          if (!isWide) {
                            return Column(
                              children: [
                                recentPanel,
                                const SizedBox(height: 18),
                                actionPanel,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: recentPanel),
                              const SizedBox(width: 18),
                              Expanded(flex: 2, child: actionPanel),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<_StudioHomeSnapshot> _loadSnapshot() async {
    final summary = await widget.catalogService.loadSummary();
    final records = await widget.galleryService.loadCreativeRecords();
    return _StudioHomeSnapshot(
      assetCount: summary.totalAssetCount,
      galleryCount: records.length,
      recentRecords: records.take(4).toList(growable: false),
    );
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
  }
}

class _HomeHero extends StatelessWidget {
  final String prompt;
  final int fragmentCount;
  final VoidCallback onContinue;
  final VoidCallback onOpenAssets;

  const _HomeHero({
    required this.prompt,
    required this.fragmentCount,
    required this.onContinue,
    required this.onOpenAssets,
  });

  @override
  Widget build(BuildContext context) {
    final promptPreview = prompt.trim().isEmpty ? '当前工作台还没有内容' : prompt;
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Novel Studio',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '本地 Prompt 与生成工作台',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: StudioTokens.textSecondary,
                    ),
              ),
              const SizedBox(height: 18),
              _HomePromptCard(
                  prompt: promptPreview, isEmpty: prompt.trim().isEmpty),
            ],
          );
          final actions = Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
            children: [
              _FragmentBadge(count: fragmentCount),
              const SizedBox(height: 16),
              StudioButton(
                label: '继续创作',
                icon: Icons.play_arrow_rounded,
                onPressed: onContinue,
              ),
              const SizedBox(height: 10),
              StudioButton(
                label: '打开素材库',
                icon: Icons.inventory_2_outlined,
                tone: StudioButtonTone.ghost,
                onPressed: onOpenAssets,
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 20),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 24),
              SizedBox(width: 190, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _HomePromptCard extends StatelessWidget {
  final String prompt;
  final bool isEmpty;

  const _HomePromptCard({required this.prompt, required this.isEmpty});

  @override
  Widget build(BuildContext context) {
    final tags = prompt
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(8)
        .toList(growable: false);
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase,
        borderRadius: StudioTokens.radiusCard,
        border: StudioTokens.cardBorder,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 18, color: StudioTokens.primary),
              const SizedBox(width: 8),
              Text(
                '当前提示词',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isEmpty)
            Text(
              prompt,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: StudioTokens.textMuted),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: StudioTokens.primary.withAlpha(20),
                      borderRadius: StudioTokens.radiusPill,
                      border: Border.all(
                        color: StudioTokens.primary.withAlpha(90),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        tag,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: StudioTokens.primary),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _FragmentBadge extends StatelessWidget {
  final int count;

  const _FragmentBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: count > 0
            ? StudioTokens.active.withAlpha(26)
            : StudioTokens.surface3,
        borderRadius: StudioTokens.radiusPill,
        border: Border.all(
          color: count > 0 ? StudioTokens.active : StudioTokens.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '素材栈 $count',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: count > 0
                    ? StudioTokens.active
                    : StudioTokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  final bool isLoading;
  final int assetCount;
  final int galleryCount;
  final int workbenchCount;
  final int batchCount;

  const _MetricStrip({
    required this.isLoading,
    required this.assetCount,
    required this.galleryCount,
    required this.workbenchCount,
    required this.batchCount,
  });

  @override
  Widget build(BuildContext context) {
    final value = isLoading ? '--' : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 1 ? 5.4 : 3.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            StudioMetricCard(
              label: '素材库',
              value: value ?? assetCount.toString(),
              icon: Icons.inventory_2_outlined,
            ),
            StudioMetricCard(
              label: '画廊记录',
              value: value ?? galleryCount.toString(),
              icon: Icons.photo_library_outlined,
              accentColor: StudioTokens.info,
            ),
            StudioMetricCard(
              label: '当前素材栈',
              value: workbenchCount.toString(),
              icon: Icons.dashboard_customize_outlined,
              accentColor: StudioTokens.active,
            ),
            StudioMetricCard(
              label: '批量目标',
              value: batchCount <= 0 ? '不限' : batchCount.toString(),
              icon: Icons.account_tree_outlined,
              accentColor: StudioTokens.warning,
            ),
          ],
        );
      },
    );
  }
}

class _RecentGalleryPanel extends StatelessWidget {
  final List<StudioGalleryRecord> records;
  final bool isLoading;
  final VoidCallback onOpenGallery;

  const _RecentGalleryPanel({
    required this.records,
    required this.isLoading,
    required this.onOpenGallery,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: '最近结果',
            icon: Icons.photo_library_outlined,
            actionLabel: '打开画廊',
            onAction: onOpenGallery,
          ),
          const SizedBox(height: 14),
          if (isLoading)
            const _InlineState(message: '正在读取本地记录...')
          else if (records.isEmpty)
            const _InlineState(message: '生成完成后，结果会自动沉淀到这里。')
          else
            for (final record in records) _RecentRecordRow(record: record),
        ],
      ),
    );
  }
}

class _RecentRecordRow extends StatelessWidget {
  final StudioGalleryRecord record;

  const _RecentRecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final title = record.title.trim().isEmpty ? '未命名记录' : record.title;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Row(
        children: [
          const Icon(Icons.image_outlined, color: StudioTokens.info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(record.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  final VoidCallback onWorkbench;
  final VoidCallback onBatch;
  final VoidCallback onSettings;

  const _ActionPanel({
    required this.onWorkbench,
    required this.onBatch,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeader(
            title: '常用入口',
            icon: Icons.bolt_outlined,
          ),
          const SizedBox(height: 14),
          StudioButton(
            label: '进入工作台',
            icon: Icons.dashboard_customize_outlined,
            onPressed: onWorkbench,
          ),
          const SizedBox(height: 10),
          StudioButton(
            label: '批量产线',
            icon: Icons.account_tree_outlined,
            tone: StudioButtonTone.ghost,
            onPressed: onBatch,
          ),
          const SizedBox(height: 10),
          StudioButton(
            label: '设置',
            icon: Icons.tune,
            tone: StudioButtonTone.ghost,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _HomeStatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _HomeStatusPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Row(
        children: [
          Icon(icon, color: StudioTokens.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PanelHeader({
    required this.title,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: StudioTokens.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _InlineState extends StatelessWidget {
  final String message;

  const _InlineState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _StudioHomeSnapshot {
  final int assetCount;
  final int galleryCount;
  final List<StudioGalleryRecord> recentRecords;

  const _StudioHomeSnapshot({
    required this.assetCount,
    required this.galleryCount,
    required this.recentRecords,
  });
}

String _formatDate(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
