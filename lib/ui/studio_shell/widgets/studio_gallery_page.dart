import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_metric_card.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class StudioGalleryPage extends StatefulWidget {
  final GenerationPageViewmodel viewModel;
  final StudioGalleryService galleryService;
  final PayloadConfig payloadConfig;

  const StudioGalleryPage({
    super.key,
    required this.viewModel,
    required this.galleryService,
    required this.payloadConfig,
  });

  @override
  State<StudioGalleryPage> createState() => _StudioGalleryPageState();
}

enum _GalleryFilter { all, parsed, missing }

class _StudioGalleryPageState extends State<StudioGalleryPage> {
  late Future<List<StudioGalleryRecord>> _recordsFuture;
  String _query = '';
  _GalleryFilter _filter = _GalleryFilter.all;
  String? _selectedRecordId;

  @override
  void initState() {
    super.initState();
    _recordsFuture = widget.galleryService.loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioTokens.surface1,
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final resultCount = widget.viewModel.commandList.length;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(StudioTokens.pagePadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GalleryHeader(
                      key: const ValueKey('gallery-header-title'),
                      resultCount: resultCount,
                      onRefresh: _reloadRecords,
                    ),
                    const SizedBox(height: 18),
                    StudioMetricCard(
                      key: const ValueKey('gallery-session-metric'),
                      label: '当前会话结果',
                      value: resultCount.toString(),
                      icon: Icons.auto_awesome,
                      accentColor: StudioTokens.info,
                    ),
                    const SizedBox(height: 18),
                    FutureBuilder<List<StudioGalleryRecord>>(
                      future: _recordsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const _GalleryStatusPanel(
                            icon: Icons.hourglass_empty,
                            title: '正在读取画廊',
                            subtitle: '整理已保存的生成结果中，请稍候。',
                          );
                        }

                        if (snapshot.hasError) {
                          return _GalleryStatusPanel(
                            icon: Icons.error_outline,
                            title: '画廊暂时不可用',
                            subtitle: snapshot.error.toString(),
                          );
                        }

                        final displayItems = (snapshot.data ?? const [])
                            .map(_GalleryDisplayItem.fromRecord)
                            .toList(growable: false);
                        if (displayItems.isEmpty) {
                          return const _GalleryStatusPanel(
                            icon: Icons.collections_bookmark_outlined,
                            title: '还没有保存记录',
                            subtitle: '生成完成后，结果会沉淀到这里，并可重新送回工作台。',
                          );
                        }

                        final filteredItems = _filterItems(displayItems);
                        final selectedItem = _resolveSelection(filteredItems);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _GalleryControls(
                              query: _query,
                              selectedFilter: _filter,
                              resultCount: filteredItems.length,
                              onQueryChanged: (value) => setState(() {
                                _query = value;
                              }),
                              onFilterChanged: (filter) => setState(() {
                                _filter = filter;
                              }),
                              onRefresh: _reloadRecords,
                            ),
                            const SizedBox(height: 14),
                            _GalleryContent(
                              items: filteredItems,
                              selectedItem: selectedItem,
                              onSelect: (item) => setState(() {
                                _selectedRecordId = item.record.id;
                              }),
                              onRestore: _restoreRecord,
                            ),
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
      ),
    );
  }

  List<_GalleryDisplayItem> _filterItems(List<_GalleryDisplayItem> items) {
    final normalizedQuery = _query.trim().toLowerCase();
    return items.where((item) {
      final filterMatches = switch (_filter) {
        _GalleryFilter.all => true,
        _GalleryFilter.parsed => item.hasMetadata,
        _GalleryFilter.missing => !item.hasMetadata,
      };
      final queryMatches =
          normalizedQuery.isEmpty || item.matches(normalizedQuery);
      return filterMatches && queryMatches;
    }).toList(growable: false);
  }

  _GalleryDisplayItem? _resolveSelection(List<_GalleryDisplayItem> items) {
    if (items.isEmpty) return null;
    for (final item in items) {
      if (item.record.id == _selectedRecordId) {
        return item;
      }
    }
    return items.first;
  }

  void _reloadRecords() {
    setState(() {
      _recordsFuture = widget.galleryService.loadRecords();
    });
  }

  void _restoreRecord(StudioGalleryRecord record) {
    widget.galleryService.restoreToWorkbench(record, widget.payloadConfig);
    widget.viewModel.setOverridePrompt(widget.payloadConfig.overridePrompt);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已送回工作台')),
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  final int resultCount;
  final VoidCallback onRefresh;

  const _GalleryHeader({
    super.key,
    required this.resultCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final description = resultCount == 0
        ? '这里会沉淀每次生成后的记录、metadata 和回流入口。'
        : '当前会话已有 $resultCount 条结果，可筛选、查看详情并回流到工作台。';
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: StudioTokens.primary,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: StudioTokens.onPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '画廊',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          StudioIconButton(
            tooltip: '刷新画廊',
            icon: Icons.refresh,
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _GalleryControls extends StatelessWidget {
  final String query;
  final _GalleryFilter selectedFilter;
  final int resultCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_GalleryFilter> onFilterChanged;
  final VoidCallback onRefresh;

  const _GalleryControls({
    required this.query,
    required this.selectedFilter,
    required this.resultCount,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('gallery-search'),
            controller: TextEditingController(text: query)
              ..selection = TextSelection.collapsed(offset: query.length),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索画廊记录、prompt 或 metadata',
              isDense: true,
            ),
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KeyedSubtree(
                key: const ValueKey('gallery-filter-all'),
                child: StudioChip(
                  label: '全部',
                  selected: selectedFilter == _GalleryFilter.all,
                  onTap: () => onFilterChanged(_GalleryFilter.all),
                ),
              ),
              KeyedSubtree(
                key: const ValueKey('gallery-filter-parsed'),
                child: StudioChip(
                  label: 'metadata 完整',
                  icon: Icons.check_circle_outline,
                  selected: selectedFilter == _GalleryFilter.parsed,
                  onTap: () => onFilterChanged(_GalleryFilter.parsed),
                  accentColor: StudioTokens.active,
                ),
              ),
              KeyedSubtree(
                key: const ValueKey('gallery-filter-missing'),
                child: StudioChip(
                  label: 'metadata 缺失',
                  icon: Icons.warning_amber_outlined,
                  selected: selectedFilter == _GalleryFilter.missing,
                  onTap: () => onFilterChanged(_GalleryFilter.missing),
                  accentColor: StudioTokens.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '匹配记录 $resultCount',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              StudioIconButton(
                tooltip: '刷新记录',
                icon: Icons.refresh,
                onPressed: onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GalleryContent extends StatelessWidget {
  final List<_GalleryDisplayItem> items;
  final _GalleryDisplayItem? selectedItem;
  final ValueChanged<_GalleryDisplayItem> onSelect;
  final ValueChanged<StudioGalleryRecord> onRestore;

  const _GalleryContent({
    required this.items,
    required this.selectedItem,
    required this.onSelect,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _GalleryStatusPanel(
        icon: Icons.search_off,
        title: '没有匹配结果',
        subtitle: '调整关键词或 metadata 状态筛选后再试一次。',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final board = _GalleryBoard(
          items: items,
          selectedId: selectedItem?.record.id,
          onSelect: onSelect,
          onRestore: onRestore,
        );
        final drawer = _GalleryDetailDrawer(
          item: selectedItem,
          onRestore: onRestore,
        );

        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              board,
              const SizedBox(height: 14),
              drawer,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: board),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: drawer),
          ],
        );
      },
    );
  }
}

class _GalleryBoard extends StatelessWidget {
  final List<_GalleryDisplayItem> items;
  final String? selectedId;
  final ValueChanged<_GalleryDisplayItem> onSelect;
  final ValueChanged<StudioGalleryRecord> onRestore;

  const _GalleryBoard({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 620
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 1.45 : 1.15,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _GalleryCard(
              item: item,
              selected: item.record.id == selectedId,
              onSelect: () => onSelect(item),
              onRestore: () => onRestore(item.record),
            );
          },
        );
      },
    );
  }
}

class _GalleryCard extends StatelessWidget {
  final _GalleryDisplayItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRestore;

  const _GalleryCard({
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('gallery-card-${item.record.id}'),
      color:
          selected ? StudioTokens.primary.withAlpha(20) : StudioTokens.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: StudioTokens.radiusCard,
        side: BorderSide(
          color: selected ? StudioTokens.primary : StudioTokens.cardOutline,
        ),
      ),
      child: InkWell(
        borderRadius: StudioTokens.radiusCard,
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _MetadataStatusChip(item: item),
                  const Spacer(),
                  StudioIconButton(
                    key: ValueKey('gallery-card-restore-${item.record.id}'),
                    tooltip: '送回工作台',
                    icon: Icons.keyboard_return,
                    onPressed: onRestore,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                item.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              Text(
                item.footer,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryDetailDrawer extends StatelessWidget {
  final _GalleryDisplayItem? item;
  final ValueChanged<StudioGalleryRecord> onRestore;

  const _GalleryDetailDrawer({
    required this.item,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final entry = item;
    if (entry == null) {
      return const StudioPanel(
        key: ValueKey('gallery-detail-drawer'),
        color: StudioTokens.surface2,
        child: _GalleryEmptyState(
          title: '选择一条记录',
          subtitle: '查看 metadata 详情、降级信息，并把结果送回工作台。',
        ),
      );
    }

    return StudioPanel(
      key: const ValueKey('gallery-detail-drawer'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '记录详情',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SizedBox(
                width: 154,
                child: StudioButton(
                  key: const ValueKey('gallery-detail-restore'),
                  label: '送回工作台',
                  icon: Icons.keyboard_return,
                  onPressed: () => onRestore(entry.record),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetadataStatusChip(item: entry),
          const SizedBox(height: 12),
          Text(
            entry.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          _DetailBlock(
            label: 'Prompt',
            value: entry.summary,
          ),
          _DetailBlock(
            label: 'Created',
            value: entry.createdLabel,
          ),
          if (entry.record.imagePath != null && entry.record.imagePath!.isNotEmpty)
            _DetailBlock(
              label: 'File',
              value: entry.record.imagePath!,
            ),
          if (entry.metadataEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Metadata',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            for (final detail in entry.metadataEntries)
              _DetailBlock(
                label: detail.label,
                value: detail.value,
              ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Fallback',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            _DetailBlock(
              label: 'Status',
              value: 'Metadata missing; showing file-level context only.',
            ),
            _DetailBlock(
              label: 'Title',
              value: entry.record.title,
            ),
            if (entry.record.imagePath != null && entry.record.imagePath!.isNotEmpty)
              _DetailBlock(
                label: 'Image path',
                value: entry.record.imagePath!,
              ),
            _DetailBlock(
              label: 'Saved at',
              value: entry.createdLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetadataStatusChip extends StatelessWidget {
  final _GalleryDisplayItem item;

  const _MetadataStatusChip({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.hasMetadata) {
      return const StudioChip(
        label: 'metadata 完整',
        icon: Icons.check_circle_outline,
        selected: true,
        accentColor: StudioTokens.active,
      );
    }

    return const StudioChip(
      label: 'metadata 缺失',
      icon: Icons.warning_amber_outlined,
      selected: true,
      accentColor: StudioTokens.warning,
    );
  }
}

class _GalleryStatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _GalleryStatusPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      child: Row(
        children: [
          Icon(icon, color: StudioTokens.info, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _GalleryEmptyState({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.photo_library_outlined,
          color: StudioTokens.info,
          size: 28,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String label;
  final String value;

  const _DetailBlock({
    required this.label,
    required this.value,
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
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: StudioTokens.textMuted,
                ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _GalleryDisplayItem {
  final StudioGalleryRecord record;
  final String title;
  final String summary;
  final String footer;
  final String createdLabel;
  final List<_GalleryDetailLine> metadataEntries;
  final String searchText;

  const _GalleryDisplayItem({
    required this.record,
    required this.title,
    required this.summary,
    required this.footer,
    required this.createdLabel,
    required this.metadataEntries,
    required this.searchText,
  });

  factory _GalleryDisplayItem.fromRecord(StudioGalleryRecord record) {
    final metadataEntries = _metadataEntries(record.additionalInfo);
    final title = record.title.trim().isEmpty ? 'Untitled record' : record.title;
    final summary = record.info.trim().isEmpty
        ? 'No prompt preview was saved with this record.'
        : record.info.trim();
    final createdLabel = _formatTimestamp(record.createdAt);
    final footerParts = <String>[
      createdLabel,
      metadataEntries.isEmpty ? 'Metadata missing' : '${metadataEntries.length} metadata fields',
      if (record.imagePath != null && record.imagePath!.trim().isNotEmpty)
        record.imagePath!,
    ];

    final searchParts = <String>[
      title,
      summary,
      createdLabel,
      if (record.imagePath != null) record.imagePath!,
      for (final detail in metadataEntries) '${detail.label} ${detail.value}',
    ];

    return _GalleryDisplayItem(
      record: record,
      title: title,
      summary: summary,
      footer: footerParts.join(' · '),
      createdLabel: createdLabel,
      metadataEntries: metadataEntries,
      searchText: searchParts.join('\n').toLowerCase(),
    );
  }

  bool get hasMetadata => metadataEntries.isNotEmpty;

  bool matches(String query) {
    return searchText.contains(query);
  }
}

class _GalleryDetailLine {
  final String label;
  final String value;

  const _GalleryDetailLine({
    required this.label,
    required this.value,
  });
}

List<_GalleryDetailLine> _metadataEntries(Map<String, dynamic> source) {
  final entries = <_GalleryDetailLine>[];
  final sortedKeys = source.keys.toList(growable: false)..sort();
  for (final key in sortedKeys) {
    final value = _stringifyMetadataValue(source[key]);
    if (value.isEmpty) continue;
    entries.add(_GalleryDetailLine(label: key, value: value));
  }
  return entries;
}

String _stringifyMetadataValue(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  if (value is List || value is Map) {
    return jsonEncode(value);
  }
  return value.toString();
}

String _formatTimestamp(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
