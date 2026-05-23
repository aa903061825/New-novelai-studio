import 'package:flutter/material.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';

class StudioToolsPage extends StatelessWidget {
  final PayloadConfig payloadConfig;

  const StudioToolsPage({
    super.key,
    required this.payloadConfig,
  });

  @override
  Widget build(BuildContext context) {
    final summaryCards = [
      _MetricCardData(
        icon: Icons.rule,
        title: '替换规则',
        count: payloadConfig.promptReplaceRules.length,
      ),
      _MetricCardData(
        icon: Icons.bookmark_border,
        title: '保存配置',
        count: payloadConfig.savedPromptConfigList.length,
      ),
      _MetricCardData(
        icon: Icons.image_search,
        title: '参考图',
        count: payloadConfig.preciseReferenceList.length,
      ),
      _MetricCardData(
        icon: Icons.auto_fix_high,
        title: 'Vibe 配置',
        count: payloadConfig.vibeConfigList.length +
            payloadConfig.vibeConfigListV4.length,
      ),
    ];
    const toolEntries = [
      _ToolEntryData(
        id: 'tag-splitter',
        icon: Icons.splitscreen,
        title: '标签拆分',
        chips: ['本地规则', '分桶'],
      ),
      _ToolEntryData(
        id: 'filter-rules',
        icon: Icons.filter_alt,
        title: '过滤规则',
        chips: ['Workspace', '脱敏'],
      ),
      _ToolEntryData(
        id: 'metadata-sorter',
        icon: Icons.dataset,
        title: 'Metadata 整理',
        chips: ['单图', '批处理'],
      ),
      _ToolEntryData(
        id: 'translation-cache',
        icon: Icons.translate,
        title: '翻译缓存',
        chips: ['手工', '缓存'],
      ),
      _ToolEntryData(
        id: 'ai-classifier',
        icon: Icons.psychology_alt,
        title: 'AI 分类',
        chips: ['在线', '回退'],
      ),
    ];

    return Scaffold(
      backgroundColor: StudioTokens.surfaceBase,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(StudioTokens.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '素材工具',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in summaryCards) _ToolSummaryCard(card),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  '画师串工具',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in toolEntries) _ToolEntryCard(entry),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCardData {
  final IconData icon;
  final String title;
  final int count;

  const _MetricCardData({
    required this.icon,
    required this.title,
    required this.count,
  });
}

class _ToolEntryData {
  final String id;
  final IconData icon;
  final String title;
  final List<String> chips;

  const _ToolEntryData({
    required this.id,
    required this.icon,
    required this.title,
    required this.chips,
  });
}

class _ToolSummaryCard extends StatelessWidget {
  final _MetricCardData data;

  const _ToolSummaryCard(this.data);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Container(
        decoration: const BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusCard,
          border: StudioTokens.cardBorder,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _IconSlot(icon: data.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              data.count.toString(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: StudioTokens.primary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolEntryCard extends StatelessWidget {
  final _ToolEntryData data;

  const _ToolEntryCard(this.data);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Container(
        key: ValueKey('studio-tool-card-${data.id}'),
        decoration: const BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusCard,
          border: StudioTokens.cardBorder,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: StudioTokens.radiusCard,
          child: InkWell(
            borderRadius: StudioTokens.radiusCard,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(data.title)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _IconSlot(icon: data.icon),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: StudioTokens.textSecondary,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: StudioTokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final chip in data.chips) StudioChip(label: chip),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconSlot extends StatelessWidget {
  final IconData icon;

  const _IconSlot({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: StudioTokens.primary,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Icon(icon, color: StudioTokens.onPrimary, size: 21),
    );
  }
}
