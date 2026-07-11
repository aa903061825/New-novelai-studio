import 'dart:async';

import 'package:flutter/material.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_presentation.dart';
import 'package:novel_studio/ui/studio_core/widgets/filter_rules_library_dialog.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_scrollbar.dart';

typedef StudioRecastKnowledgeBaseLoader = Future<Map<String, dynamic>>
    Function();
typedef StudioTranslationCacheSaver = Future<void> Function(
  TranslationCache cache,
);
typedef StudioRecastCachesLoader = Future<List<RecastScriptCache>> Function();
typedef StudioRecastCachesSaver = Future<void> Function(
  List<RecastScriptCache> caches,
);

class StudioToolsPage extends StatefulWidget {
  final PayloadConfig payloadConfig;
  final FilterRulesConfigLoader? loadFilterRuleConfig;
  final FilterRulesConfigSaver? saveFilterRuleConfig;
  final StudioRecastKnowledgeBaseLoader? loadRecastKnowledgeBase;
  final TranslationCache? translationCache;
  final PromptTagClassificationCache? classificationCache;
  final StudioTranslationCacheSaver? saveTranslationCache;
  final PromptTranslationService? translationService;
  final StudioRecastCachesLoader? loadRecastCaches;
  final StudioRecastCachesSaver? saveRecastCaches;
  final bool embedded;

  const StudioToolsPage({
    super.key,
    required this.payloadConfig,
    this.loadFilterRuleConfig,
    this.saveFilterRuleConfig,
    this.loadRecastKnowledgeBase,
    this.translationCache,
    this.classificationCache,
    this.saveTranslationCache,
    this.translationService,
    this.loadRecastCaches,
    this.saveRecastCaches,
    this.embedded = false,
  });

  @override
  State<StudioToolsPage> createState() => _StudioToolsPageState();
}

class _StudioToolsPageState extends State<StudioToolsPage>
    with TickerProviderStateMixin {
  final Set<String> _expandedEntryIds = {};
  @override
  Widget build(BuildContext context) {
    final summaryCards = [
      _MetricCardData(
        id: 'replace-rules',
        icon: Icons.rule,
        title: '替换规则',
        count: widget.payloadConfig.promptReplaceRules.length,
      ),
      _MetricCardData(
        id: 'saved-configs',
        icon: Icons.bookmark_border,
        title: '保存配置',
        count: widget.payloadConfig.savedPromptConfigList.length,
      ),
      _MetricCardData(
        id: 'references',
        icon: Icons.image_search,
        title: '参考图',
        count: widget.payloadConfig.preciseReferenceList.length,
      ),
      _MetricCardData(
        id: 'vibe-configs',
        icon: Icons.auto_fix_high,
        title: 'Vibe 配置',
        count: widget.payloadConfig.vibeConfigList.length +
            widget.payloadConfig.vibeConfigListV4.length,
      ),
    ];
    const toolEntries = [
      _ToolEntryData(
        id: 'knowledge-base',
        icon: Icons.school_outlined,
        title: '长期知识',
        description: '在剧本页确认角色后沉淀，只接收已确认内容。',
        chips: ['confirmed-only', 'script cache'],
        storagePath: 'script_recast/knowledge.json',
        stores: '确认后的角色资料、别名、证据 tag、帧范围、重要性和映射到的素材库角色。',
        takesEffect: '点击“保存长期知识沉淀”后写入；同一剧本优先从剧本缓存恢复，源文件变化时可选择沿用旧缓存或重新分析。',
        limitation: '长期知识文件目前只负责持久化已确认快照；跨剧本自动反哺分析还没有完全接上。',
      ),
      _ToolEntryData(
        id: 'filter-rules',
        icon: Icons.filter_alt,
        title: '过滤 / 屏蔽审核',
        description: '在剧本页查看命中、撤销范围和替换覆盖。',
        chips: ['review hits', 'range override'],
        storagePath: 'configs/filter_rules.json',
        stores:
            'delete_keywords、strong_filter_keywords、replace_rules、remove_weights、exact_match、delete_artist_tags。',
        takesEffect: '导入剧本时读取；剧本预览和发送到批量产线时会从最终 prompt 移除全局屏蔽词。',
        limitation: '当前 UI 主要暴露全局屏蔽词；强过滤、替换规则、删除画师 tag 的可视化审核还需要继续补。',
      ),
      _ToolEntryData(
        id: 'translation-cache',
        icon: Icons.translate,
        title: '翻译缓存',
        description: 'Prompt Workshop / 分词结果复用的翻译抓取入口。',
        chips: ['prompt workshop', 'reuse'],
        storagePath: r'E:\NAI的脚本群\trans_cache.json',
        stores: 'tag 到中文的 en2zh 缓存项，兼容旧字符串格式和包含 translation/source/ts 的结构化格式。',
        takesEffect:
            '应用启动时由 PromptWorkshopBridge 读取；分词 / Prompt Workshop 预览 tag 时优先查缓存，再查本地小词典。',
        limitation: '这部分目前还是外部桥接文件，不在 workspace 目录内；知识库页还没有提供编辑和写回入口。',
      ),
      _ToolEntryData(
        id: 'ai-classifier',
        icon: Icons.psychology_alt,
        title: 'AI ??',
        description: 'AI role extraction drafts stored per imported script.',
        chips: ['online ai', 'script cache', 'draft review'],
        storagePath:
            'Script cache: script_recast/cache/<scriptId>.json\nLong-term knowledge: script_recast/knowledge.json',
        stores:
            'Per-script AI role extraction drafts, chunk checkpoints, and mapping cache.',
        takesEffect:
            'Generated by the Script Recast AI role-field workflow and restored with the matching script fingerprint.',
        limitation:
            'Clearing this removes AI drafts only; confirmed long-term knowledge is stored separately.',
      ),
    ];

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '知识与规则',
              key: const ValueKey('studio-tools-heading'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: StudioTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '这里集中放置知识沉淀、过滤屏蔽、翻译缓存和剧本审核入口。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: StudioTokens.textSecondary,
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
              '工作区',
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
                for (final entry in toolEntries)
                  _ToolEntryCard(
                    data: entry,
                    expanded: _expandedEntryIds.contains(entry.id),
                    onTap: () => _toggleEntry(entry.id),
                    onOpenKnowledge: entry.id == 'knowledge-base' &&
                            widget.loadRecastKnowledgeBase != null
                        ? _openKnowledgeOverview
                        : null,
                    onOpenFilterRules: entry.id == 'filter-rules' &&
                            widget.loadFilterRuleConfig != null &&
                            widget.saveFilterRuleConfig != null
                        ? _openFilterRulesLibrary
                        : null,
                    onOpenTranslation: entry.id == 'translation-cache' &&
                            widget.translationCache != null &&
                            widget.saveTranslationCache != null
                        ? _openTranslationCache
                        : null,
                    onOpenAiAnalysis: entry.id == 'ai-classifier' &&
                            widget.loadRecastCaches != null &&
                            widget.saveRecastCaches != null
                        ? _openAiAnalysis
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return KeyedSubtree(
        key: const ValueKey('studio-tools-page'),
        child: content,
      );
    }

    return Scaffold(
      key: const ValueKey('studio-tools-page'),
      backgroundColor: StudioTokens.surfaceBase,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(StudioTokens.pagePadding),
        child: content,
      ),
    );
  }

  void _toggleEntry(String id) {
    setState(() {
      if (!_expandedEntryIds.add(id)) {
        _expandedEntryIds.remove(id);
      }
    });
  }

  Future<void> _openKnowledgeOverview() async {
    final loader = widget.loadRecastKnowledgeBase;
    if (loader == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _KnowledgeOverviewDialog(loadKnowledgeBase: loader),
    );
  }

  Future<void> _openFilterRulesLibrary() async {
    final loader = widget.loadFilterRuleConfig;
    final saver = widget.saveFilterRuleConfig;
    if (loader == null || saver == null) {
      return;
    }
    await showFilterRulesLibraryDialog(
      context,
      loadConfig: loader,
      saveConfig: saver,
    );
  }

  Future<void> _openTranslationCache() async {
    final cache = widget.translationCache;
    final saver = widget.saveTranslationCache;
    if (cache == null || saver == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _TranslationCacheDialog(
        initialCache: cache,
        saveTranslationCache: saver,
        classificationCache: widget.classificationCache,
        translationService: widget.translationService,
      ),
    );
  }

  Future<void> _openAiAnalysis() async {
    final loader = widget.loadRecastCaches;
    final saver = widget.saveRecastCaches;
    if (loader == null || saver == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AiAnalysisDialog(
        loadRecastCaches: loader,
        saveRecastCaches: saver,
      ),
    );
  }
}

class _MetricCardData {
  final String id;
  final IconData icon;
  final String title;
  final int count;

  const _MetricCardData({
    required this.id,
    required this.icon,
    required this.title,
    required this.count,
  });
}

class _ToolEntryData {
  final String id;
  final IconData icon;
  final String title;
  final String description;
  final List<String> chips;
  final String storagePath;
  final String stores;
  final String takesEffect;
  final String limitation;

  const _ToolEntryData({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.chips,
    required this.storagePath,
    required this.stores,
    required this.takesEffect,
    required this.limitation,
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
        key: ValueKey('studio-tool-summary-${data.id}'),
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
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onOpenKnowledge;
  final VoidCallback? onOpenFilterRules;
  final VoidCallback? onOpenTranslation;
  final VoidCallback? onOpenAiAnalysis;

  const _ToolEntryCard({
    required this.data,
    required this.expanded,
    required this.onTap,
    this.onOpenKnowledge,
    this.onOpenFilterRules,
    this.onOpenTranslation,
    this.onOpenAiAnalysis,
  });

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: StudioTokens.radiusCard,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _IconSlot(icon: data.icon),
                          const Spacer(),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: StudioTokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: StudioTokens.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final chip in data.chips)
                            StudioChip(label: chip),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: _ToolEntryDetails(
                          data: data,
                          onOpenKnowledge: onOpenKnowledge,
                          onOpenFilterRules: onOpenFilterRules,
                          onOpenTranslation: onOpenTranslation,
                          onOpenAiAnalysis: onOpenAiAnalysis,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolEntryDetails extends StatelessWidget {
  final _ToolEntryData data;
  final VoidCallback? onOpenKnowledge;
  final VoidCallback? onOpenFilterRules;
  final VoidCallback? onOpenTranslation;
  final VoidCallback? onOpenAiAnalysis;

  const _ToolEntryDetails({
    required this.data,
    this.onOpenKnowledge,
    this.onOpenFilterRules,
    this.onOpenTranslation,
    this.onOpenAiAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('studio-tool-details-${data.id}'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: StudioTokens.border),
          const SizedBox(height: 12),
          _DetailLine(label: '存储位置', value: data.storagePath, mono: true),
          _DetailLine(label: '存储内容', value: data.stores),
          _DetailLine(label: '什么时候生效', value: data.takesEffect),
          _DetailLine(label: '当前限制', value: data.limitation),
          if (onOpenKnowledge != null) ...[
            const SizedBox(height: 2),
            StudioButton(
              key: const ValueKey('studio-tools-knowledge-open'),
              label: '打开知识概览',
              icon: Icons.analytics_outlined,
              tone: StudioButtonTone.secondary,
              onPressed: onOpenKnowledge,
            ),
          ],
          if (onOpenFilterRules != null) ...[
            const SizedBox(height: 2),
            StudioButton(
              key: const ValueKey('studio-tools-filter-rules-open'),
              label: '打开屏蔽库',
              icon: Icons.tune,
              tone: StudioButtonTone.secondary,
              onPressed: onOpenFilterRules,
            ),
          ],
          if (onOpenTranslation != null) ...[
            const SizedBox(height: 2),
            StudioButton(
              key: const ValueKey('studio-tools-translation-open'),
              label: '打开翻译缓存',
              icon: Icons.translate,
              tone: StudioButtonTone.secondary,
              onPressed: onOpenTranslation,
            ),
          ],
          if (onOpenAiAnalysis != null) ...[
            const SizedBox(height: 2),
            StudioButton(
              key: const ValueKey('studio-tools-ai-analysis-open'),
              label: '打开 AI 分析',
              icon: Icons.psychology_alt,
              tone: StudioButtonTone.secondary,
              onPressed: onOpenAiAnalysis,
            ),
          ],
        ],
      ),
    );
  }
}

class _KnowledgeOverviewDialog extends StatelessWidget {
  final StudioRecastKnowledgeBaseLoader loadKnowledgeBase;

  const _KnowledgeOverviewDialog({required this.loadKnowledgeBase});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('knowledge-overview-dialog'),
      backgroundColor: StudioTokens.surface3,
      title: const Text('长期知识概览'),
      content: SizedBox(
        width: 620,
        child: FutureBuilder<Map<String, dynamic>>(
          future: loadKnowledgeBase(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                '读取失败：${snapshot.error}',
                style: const TextStyle(color: StudioTokens.danger),
              );
            }
            final summary = _KnowledgeSummary.fromBase(snapshot.data ?? {});
            if (summary.roleCount == 0) {
              return const Text('暂无已确认长期知识。');
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StudioChip(label: '脚本 ${summary.scriptCount}'),
                      StudioChip(label: '已确认角色 ${summary.roleCount}'),
                      StudioChip(label: '主角 ${summary.protagonistCount}'),
                      StudioChip(label: '配角 ${summary.supportingCount}'),
                      StudioChip(label: '临时 ${summary.temporaryCount}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final role in summary.samples)
                    _OverviewRow(
                      title: role.displayName,
                      subtitle: [
                        role.importance.name,
                        if (role.mappedCharacterId != null)
                          '映射 ${role.mappedCharacterId}',
                        if (role.aliases.isNotEmpty)
                          '别名 ${role.aliases.take(3).join(', ')}',
                      ].join(' · '),
                      detail: role.evidenceTags.take(6).join(', '),
                    ),
                ],
              ),
            );
          },
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

class _TranslationCacheDialog extends StatefulWidget {
  final TranslationCache initialCache;
  final StudioTranslationCacheSaver saveTranslationCache;
  final PromptTagClassificationCache? classificationCache;
  final PromptTranslationService? translationService;

  const _TranslationCacheDialog({
    required this.initialCache,
    required this.saveTranslationCache,
    this.classificationCache,
    this.translationService,
  });

  @override
  State<_TranslationCacheDialog> createState() =>
      _TranslationCacheDialogState();
}

class _TranslationCacheDialogState extends State<_TranslationCacheDialog> {
  late final List<_EditableTranslationEntry> _entries;
  String _query = '';
  String? _selectedCacheKey;
  String _status = '';
  bool _saving = false;
  bool _retranslating = false;

  @override
  void initState() {
    super.initState();
    _entries = [
      for (final entry in widget.initialCache.entries.entries)
        _EditableTranslationEntry(
          entry.key,
          entry.value,
          classification: _classifyTranslationEntry(entry.key),
        ),
    ]..sort(_compareTranslationEntries);
    if (_entries.isNotEmpty) {
      _selectedCacheKey = _entries.first.cacheKey;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = [
      for (final entry in _entries)
        if (_matchesQuery(entry)) entry,
    ];
    final selectedEntry = _selectedEntry(visibleEntries);
    return AlertDialog(
      key: const ValueKey('translation-cache-dialog'),
      backgroundColor: StudioTokens.surface3,
      title: const Text('翻译缓存'),
      content: SizedBox(
        width: 820,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StudioChip(label: '条目 ${_entries.length}'),
                for (final source in _sourceCounts().entries)
                  StudioChip(label: '${source.key} ${source.value}'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('translation-cache-search'),
              decoration: const InputDecoration(
                hintText: '搜索 tag 或翻译',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: visibleEntries.isEmpty
                  ? const Center(child: Text('没有匹配的翻译缓存。'))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _TranslationCacheEntryList(
                            entries: visibleEntries,
                            selectedCacheKey: selectedEntry?.cacheKey,
                            onSelected: _selectEntry,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: selectedEntry == null
                              ? const SizedBox.shrink()
                              : SingleChildScrollView(
                                  child: _TranslationCacheEditorPanel(
                                    entry: selectedEntry,
                                    retranslateEnabled:
                                        widget.translationService != null &&
                                            !_retranslating,
                                    onTranslationChanged: (value) =>
                                        _updateTranslation(
                                      selectedEntry,
                                      value,
                                    ),
                                    onRetranslate: () =>
                                        _retranslate(selectedEntry),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textSecondary,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const ValueKey('translation-cache-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('保存'),
        ),
      ],
    );
  }

  bool _matchesQuery(_EditableTranslationEntry entry) {
    if (_query.isEmpty) return true;
    final query = _query.toLowerCase();
    return entry.text.toLowerCase().contains(query) ||
        entry.translation.toLowerCase().contains(query);
  }

  _EditableTranslationEntry? _selectedEntry(
    List<_EditableTranslationEntry> visibleEntries,
  ) {
    if (visibleEntries.isEmpty) {
      return null;
    }
    for (final entry in visibleEntries) {
      if (entry.cacheKey == _selectedCacheKey) {
        return entry;
      }
    }
    return visibleEntries.first;
  }

  void _selectEntry(_EditableTranslationEntry entry) {
    setState(() => _selectedCacheKey = entry.cacheKey);
  }

  void _updateTranslation(_EditableTranslationEntry entry, String translation) {
    setState(() {
      entry.translation = translation;
      entry.source = 'manual';
    });
  }

  Map<String, int> _sourceCounts() {
    final counts = <String, int>{};
    for (final entry in _entries) {
      counts.update(entry.source, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  PromptTagClassification _classifyTranslationEntry(String cacheKey) {
    return classifyPromptTagForPresentation(
      TranslationCache.textFromCacheKey(cacheKey),
      cache: widget.classificationCache,
    );
  }

  int _compareTranslationEntries(
    _EditableTranslationEntry left,
    _EditableTranslationEntry right,
  ) {
    final groupCompare = _categorySortIndex(left.classification.category)
        .compareTo(_categorySortIndex(right.classification.category));
    if (groupCompare != 0) {
      return groupCompare;
    }
    return left.text.compareTo(right.text);
  }

  Future<void> _retranslate(_EditableTranslationEntry entry) async {
    final service = widget.translationService;
    if (service == null) {
      return;
    }
    setState(() {
      _retranslating = true;
      _status = '正在重译 ${entry.text}';
    });
    try {
      final result = await service.translate(
        OnlineTranslationRequest(
          text: entry.text,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        preferCache: false,
      );
      final translated = result.text.trim();
      if (translated.isEmpty) {
        setState(() => _status = '${entry.text} 重译失败：结果为空');
      } else {
        setState(() {
          entry.translation = translated;
          entry.source = 'ai-refresh';
          entry.ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          _status = '${entry.text} 已重译';
        });
      }
    } catch (error) {
      setState(() => _status = '${entry.text} 重译失败：$error');
    } finally {
      if (mounted) {
        setState(() => _retranslating = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = '正在保存翻译缓存';
    });
    try {
      await widget.saveTranslationCache(
        TranslationCache(
          entries: {
            for (final entry in _entries)
              if (entry.translation.trim().isNotEmpty)
                entry.cacheKey: TranslationCacheEntry(
                  translation: entry.translation.trim(),
                  source: entry.source,
                  ts: entry.ts,
                ),
          },
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _status = '保存失败：$error';
        });
      }
    }
  }
}

class _AiAnalysisDialog extends StatefulWidget {
  final StudioRecastCachesLoader loadRecastCaches;
  final StudioRecastCachesSaver saveRecastCaches;

  const _AiAnalysisDialog({
    required this.loadRecastCaches,
    required this.saveRecastCaches,
  });

  @override
  State<_AiAnalysisDialog> createState() => _AiAnalysisDialogState();
}

class _AiAnalysisDialogState extends State<_AiAnalysisDialog> {
  List<RecastScriptCache>? _caches;
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final scripts = [
      for (final cache in _caches ?? const <RecastScriptCache>[])
        if (_hasAiAnalysis(cache)) cache,
    ];
    return AlertDialog(
      key: const ValueKey('ai-analysis-dialog'),
      backgroundColor: StudioTokens.surface3,
      title: const Text('AI 分析缓存'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text(
                    '读取失败：$_error',
                    style: const TextStyle(color: StudioTokens.danger),
                  )
                : scripts.isEmpty
                    ? const Center(child: Text('暂无剧本 AI 分析缓存。'))
                    : ListView.separated(
                        itemCount: scripts.length,
                        separatorBuilder: (_, __) => const Divider(
                          color: StudioTokens.border,
                        ),
                        itemBuilder: (context, index) {
                          final cache = scripts[index];
                          return _AiAnalysisScriptRow(
                            cache: cache,
                            disabled: _saving,
                            onDelete: () => _deleteScriptAnalysis(cache),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final caches = await widget.loadRecastCaches();
      if (mounted) {
        setState(() {
          _caches = caches;
          _error = null;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteScriptAnalysis(RecastScriptCache target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StudioTokens.surface3,
        title: const Text('删除 AI 分析缓存？'),
        content: Text('只会清空「${target.scriptName}」的 AI 分析记录，不删除角色映射和长期知识。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('ai-analysis-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || _caches == null) {
      return;
    }
    setState(() => _saving = true);
    final next = [
      for (final cache in _caches!)
        cache.scriptId == target.scriptId ? _clearAiAnalysis(cache) : cache,
    ];
    await widget.saveRecastCaches(next);
    if (mounted) {
      setState(() {
        _caches = next;
        _saving = false;
      });
    }
  }
}

class _TranslationCacheEntryList extends StatefulWidget {
  final List<_EditableTranslationEntry> entries;
  final String? selectedCacheKey;
  final ValueChanged<_EditableTranslationEntry> onSelected;

  const _TranslationCacheEntryList({
    required this.entries,
    required this.selectedCacheKey,
    required this.onSelected,
  });

  @override
  State<_TranslationCacheEntryList> createState() =>
      _TranslationCacheEntryListState();
}

class _TranslationCacheEntryListState
    extends State<_TranslationCacheEntryList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: StudioScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.separated(
          key: const ValueKey('translation-cache-entry-list'),
          controller: _scrollController,
          primary: false,
          padding: const EdgeInsets.all(8),
          itemCount: widget.entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final entry = widget.entries[index];
            final selected = entry.cacheKey == widget.selectedCacheKey;
            return _TranslationCacheEntryRow(
              key: ValueKey('translation-cache-entry-${entry.cacheKey}'),
              entry: entry,
              selected: selected,
              onTap: () => widget.onSelected(entry),
            );
          },
        ),
      ),
    );
  }
}

class _TranslationCacheEntryRow extends StatelessWidget {
  final _EditableTranslationEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _TranslationCacheEntryRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = entry.classification.category;
    final categoryColor = _categoryColor(category);
    final borderColor = selected ? StudioTokens.primary : StudioTokens.border;
    final background =
        selected ? StudioTokens.primary.withAlpha(26) : StudioTokens.surface3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: StudioTokens.radiusSlot,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: StudioTokens.radiusSlot,
            border: Border.all(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 58,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: StudioTokens.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TranslationCacheMetaPill(
                              label: _categoryLabel(category),
                              color: categoryColor,
                            ),
                            const SizedBox(width: 6),
                            StudioChip(label: entry.source),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.translation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: StudioTokens.textSecondary,
                                  ),
                        ),
                      ],
                    ),
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

class _TranslationCacheMetaPill extends StatelessWidget {
  final String label;
  final Color color;

  const _TranslationCacheMetaPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: StudioTokens.radiusBadge,
        border: Border.all(color: color.withAlpha(130)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: StudioTokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _TranslationCacheEditorPanel extends StatefulWidget {
  final _EditableTranslationEntry entry;
  final bool retranslateEnabled;
  final ValueChanged<String> onTranslationChanged;
  final VoidCallback onRetranslate;

  const _TranslationCacheEditorPanel({
    required this.entry,
    required this.retranslateEnabled,
    required this.onTranslationChanged,
    required this.onRetranslate,
  });

  @override
  State<_TranslationCacheEditorPanel> createState() =>
      _TranslationCacheEditorPanelState();
}

class _TranslationCacheEditorPanelState
    extends State<_TranslationCacheEditorPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entry.translation);
  }

  @override
  void didUpdateWidget(covariant _TranslationCacheEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.entry.translation) {
      _controller.value = TextEditingValue(
        text: widget.entry.translation,
        selection: TextSelection.collapsed(
          offset: widget.entry.translation.length,
        ),
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
    final entry = widget.entry;
    return Container(
      key: const ValueKey('translation-cache-editor-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '正在编辑：${entry.text}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              StudioChip(label: entry.source),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('translation-cache-edit-${_keySlug(entry.text)}'),
            controller: _controller,
            minLines: 1,
            maxLines: 2,
            onChanged: widget.onTranslationChanged,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '中文翻译',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: StudioButton(
              key: ValueKey(
                'translation-cache-retranslate-${_keySlug(entry.text)}',
              ),
              label: '重新 AI 翻译',
              icon: Icons.auto_fix_high,
              tone: StudioButtonTone.secondary,
              onPressed:
                  widget.retranslateEnabled ? widget.onRetranslate : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiAnalysisScriptRow extends StatelessWidget {
  final RecastScriptCache cache;
  final bool disabled;
  final VoidCallback onDelete;

  const _AiAnalysisScriptRow({
    required this.cache,
    required this.disabled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final summary = _AiAnalysisSummary.fromCache(cache);
    final extraction = cache.aiRoleExtraction;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        cache.scriptName.trim().isEmpty ? cache.scriptId : cache.scriptName,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: StudioTokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
      ),
      subtitle: Text(
        [
          '角色 ${summary.roleCount}',
          '分块 ${summary.chunkCount}',
          '关注点 ${summary.attentionCount}',
        ].join(' / '),
      ),
      trailing: IconButton.filledTonal(
        key: ValueKey('ai-analysis-delete-script-${cache.scriptId}'),
        tooltip: '删除 AI 分析缓存',
        onPressed: disabled ? null : onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
      children: [
        for (final role in extraction.roles.take(6))
          _OverviewRow(
            title: role.displayName.trim().isEmpty
                ? role.sourceRoleId
                : role.displayName,
            subtitle:
                '${role.sourceKind} / ${(role.confidence * 100).round()}%',
            detail: role.stages
                .take(3)
                .map((stage) =>
                    stage.label.trim().isEmpty ? stage.stageId : stage.label)
                .where((label) => label.trim().isNotEmpty)
                .join(' / '),
          ),
      ],
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String detail;

  const _OverviewRow({
    required this.title,
    required this.subtitle,
    this.detail = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: StudioTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StudioTokens.textSecondary,
                ),
          ),
          if (detail.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              detail,
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

class _KnowledgeSummary {
  final int scriptCount;
  final int roleCount;
  final int protagonistCount;
  final int supportingCount;
  final int temporaryCount;
  final List<RecastRoleCandidate> samples;

  const _KnowledgeSummary({
    required this.scriptCount,
    required this.roleCount,
    required this.protagonistCount,
    required this.supportingCount,
    required this.temporaryCount,
    required this.samples,
  });

  factory _KnowledgeSummary.fromBase(Map<String, dynamic> knowledgeBase) {
    final scripts = knowledgeBase['scripts'];
    final candidates = confirmedKnowledgeCandidatesFromBase(knowledgeBase);
    return _KnowledgeSummary(
      scriptCount: scripts is Map ? scripts.length : 0,
      roleCount: candidates.length,
      protagonistCount: candidates
          .where((candidate) =>
              candidate.importance == RecastRoleImportance.protagonist)
          .length,
      supportingCount: candidates
          .where((candidate) =>
              candidate.importance == RecastRoleImportance.supporting)
          .length,
      temporaryCount: candidates
          .where((candidate) =>
              candidate.importance == RecastRoleImportance.temporary)
          .length,
      samples: candidates.take(12).toList(growable: false),
    );
  }
}

class _EditableTranslationEntry {
  final String cacheKey;
  final String text;
  final PromptTagClassification classification;
  String translation;
  String source;
  int ts;

  _EditableTranslationEntry(
    this.cacheKey,
    TranslationCacheEntry entry, {
    required this.classification,
  })  : text = TranslationCache.textFromCacheKey(cacheKey),
        translation = entry.translation,
        source = entry.source,
        ts = entry.ts;
}

class _AiAnalysisSummary {
  final int roleCount;
  final int chunkCount;
  final int attentionCount;

  const _AiAnalysisSummary({
    required this.roleCount,
    required this.chunkCount,
    required this.attentionCount,
  });

  factory _AiAnalysisSummary.fromCache(RecastScriptCache cache) {
    return _AiAnalysisSummary(
      roleCount: cache.aiRoleExtraction.roles.length,
      chunkCount: cache.aiRoleExtractionChunks.length,
      attentionCount: cache.aiRoleExtraction.attentionItems.length,
    );
  }
}

bool _hasAiAnalysis(RecastScriptCache cache) {
  return cache.aiRoleExtraction.status != ScriptAiRoleExtractionStatus.idle ||
      cache.aiRoleExtractionChunks.isNotEmpty;
}

RecastScriptCache _clearAiAnalysis(RecastScriptCache cache) {
  return RecastScriptCache(
    scriptId: cache.scriptId,
    scriptName: cache.scriptName,
    sourceRootPath: cache.sourceRootPath,
    sourceFingerprint: cache.sourceFingerprint,
    updatedAt: DateTime.now().toUtc(),
    mapping: cache.mapping,
    aiRoleExtraction: const ScriptAiRoleExtraction(),
    aiRoleExtractionChunks: const [],
    aiRoleExtractionDraftCollapsed: false,
    scriptBlockWords: cache.scriptBlockWords,
    knowledgeSnapshot: const {},
    scriptSnapshot: cache.scriptSnapshot,
  );
}

String _keySlug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'entry' : slug;
}

int _categorySortIndex(PromptTagCategory category) {
  return switch (PromptTagClassifier.groupFor(category).id) {
    'quality' => 0,
    'artist' => 1,
    'character' => 2,
    'clothing' => 3,
    'action' => 4,
    'scene' => 5,
    'style' => 6,
    'negative' => 7,
    'syntax' => 8,
    _ => 9,
  };
}

String _categoryLabel(PromptTagCategory category) {
  return switch (category) {
    PromptTagCategory.character => '角色',
    PromptTagCategory.upperBody => '上身',
    PromptTagCategory.lowerBody => '下身',
    PromptTagCategory.upperClothing => '上装',
    PromptTagCategory.lowerClothing => '下装',
    PromptTagCategory.accessory => '饰品',
    PromptTagCategory.clothingState => '服装状态',
    PromptTagCategory.clothing => '服装',
    PromptTagCategory.action => '动作',
    PromptTagCategory.scene => '场景',
    PromptTagCategory.camera => '镜头',
    PromptTagCategory.artist => '画师',
    PromptTagCategory.style => '风格',
    PromptTagCategory.quality => '画质',
    PromptTagCategory.negativeQuality => '负面画质',
    PromptTagCategory.negativeBody => '负面人体',
    PromptTagCategory.negativeArtist => '负面画师',
    PromptTagCategory.negativeContent => '负面内容',
    PromptTagCategory.promptSyntax => '语法',
    PromptTagCategory.other => '其它',
  };
}

Color _categoryColor(PromptTagCategory category) {
  return switch (PromptTagClassifier.groupFor(category).id) {
    'quality' => StudioTokens.primary,
    'artist' => StudioTokens.info,
    'character' => StudioTokens.secondary,
    'clothing' => const Color(0xFF2DD4BF),
    'action' => const Color(0xFFA78BFA),
    'scene' => const Color(0xFF38BDF8),
    'style' => const Color(0xFFF472B6),
    'negative' => StudioTokens.danger,
    'syntax' => StudioTokens.warning,
    _ => StudioTokens.textMuted,
  };
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailLine({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: StudioTokens.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: (mono
                    ? Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        )
                    : Theme.of(context).textTheme.bodySmall)
                ?.copyWith(
              color: StudioTokens.textSecondary,
              height: 1.35,
            ),
          ),
        ],
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
