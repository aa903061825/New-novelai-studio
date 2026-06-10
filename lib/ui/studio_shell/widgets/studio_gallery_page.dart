import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_metric_card.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_image_preview_layout.dart';

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
    _recordsFuture = widget.galleryService.loadCreativeRecords();
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
                          onPreview: _showPreview,
                          onRestore: _restoreRecord,
                        ),
                      ],
                    );
                  },
                ),
              ],
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
      _recordsFuture = widget.galleryService.loadCreativeRecords();
    });
  }

  void _showPreview(_GalleryDisplayItem item, List<_GalleryDisplayItem> items) {
    final previewItems = items
        .where((candidate) => candidate.hasImagePath)
        .toList(growable: false);
    if (previewItems.isEmpty) return;
    final assetCaptureHost = StudioAssetCaptureHost.maybeOf(context);
    StudioGeneratedImageViewerDialog.show(
      context,
      items: previewItems.map(_galleryGeneratedImageItem).toList(),
      initialItemId: item.record.id,
      actionsBuilder: (context, generatedItem) {
        final galleryItem = generatedItem.source as _GalleryDisplayItem;
        return [
          KeyedSubtree(
            key: const ValueKey('gallery-preview-restore'),
            child: FilledButton.icon(
              onPressed: () => _restoreRecord(galleryItem.record),
              icon: const Icon(Icons.keyboard_return),
              label: const Text('送回工作台'),
            ),
          )
        ];
      },
      footerBuilder: (context, generatedItem, fullscreen) {
        final galleryItem = generatedItem.source as _GalleryDisplayItem;
        return _GalleryPreviewPromptPanel(
          item: galleryItem,
          fullscreen: fullscreen,
          assetCaptureHost: assetCaptureHost,
        );
      },
      dialogKey: const ValueKey('gallery-image-viewer-dialog'),
      windowedKey: const ValueKey('gallery-image-viewer-windowed'),
      fullscreenKey: const ValueKey('gallery-image-viewer-fullscreen'),
      zoomableKey: const ValueKey('gallery-zoomable-image-viewer'),
      fullscreenButtonKey: const ValueKey('gallery-preview-fullscreen-toggle'),
    );
  }

  void _restoreRecord(StudioGalleryRecord record) {
    widget.galleryService.restoreToWorkbench(record, widget.payloadConfig);
    widget.viewModel.setOverridePrompt(widget.payloadConfig.overridePrompt);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已送回工作台')));
  }
}

List<StudioAssetCaptureDraft> _captureDraftsForGalleryRecord(
  StudioGalleryRecord record,
) {
  final title = record.title.trim();
  return StudioAssetCaptureDrafts.fromWorkbenchDocument(
    record.document,
    source: StudioAssetCaptureSource(
      surface: 'gallery',
      label: title.isEmpty ? 'Gallery item' : title,
      sourceId: record.id,
      path: record.imagePath,
    ),
  );
}

Future<void> _showGalleryAssetCaptureDraft(
  BuildContext context,
  StudioAssetCaptureDraft draft, {
  StudioAssetCaptureHostState? host,
  bool closeBeforeShow = false,
}) async {
  final targetHost = host ?? StudioAssetCaptureHost.maybeOf(context);
  if (targetHost == null) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context) ??
      ScaffoldMessenger.maybeOf(targetHost.context);
  if (closeBeforeShow) {
    Navigator.of(context).pop();
  }
  try {
    await targetHost.showDraft(draft);
  } catch (error) {
    if (messenger == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
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
  final void Function(_GalleryDisplayItem item, List<_GalleryDisplayItem> items)
      onPreview;
  final ValueChanged<StudioGalleryRecord> onRestore;

  const _GalleryContent({
    required this.items,
    required this.selectedItem,
    required this.onSelect,
    required this.onPreview,
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
          onPreview: onPreview,
          onRestore: onRestore,
        );
        final drawer = _GalleryDetailDrawer(
          item: selectedItem,
          items: items,
          onPreview: onPreview,
          onRestore: onRestore,
        );

        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [board, const SizedBox(height: 14), drawer],
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
  final void Function(_GalleryDisplayItem item, List<_GalleryDisplayItem> items)
      onPreview;
  final ValueChanged<StudioGalleryRecord> onRestore;

  const _GalleryBoard({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.onPreview,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final galleryItems = items.map(_galleryGeneratedImageItem).toList();
    return StudioGeneratedImageGallery(
      items: galleryItems,
      selectedId: selectedId,
      columnWidth: 240,
      cardKeyPrefix: 'gallery-card',
      imageKeyPrefix: 'gallery-card-image',
      onOpen: (context, generatedItem) {
        final item = generatedItem.source as _GalleryDisplayItem;
        onSelect(item);
        onPreview(item, items);
      },
      trailingBuilder: (context, generatedItem) {
        final item = generatedItem.source as _GalleryDisplayItem;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StudioIconButton(
              key: ValueKey('gallery-card-details-${item.record.id}'),
              tooltip: '查看详情',
              icon: Icons.info_outline,
              selected: item.record.id == selectedId,
              onPressed: () => onSelect(item),
            ),
            const SizedBox(width: 4),
            StudioIconButton(
              key: ValueKey('gallery-card-restore-${item.record.id}'),
              tooltip: '送回工作台',
              icon: Icons.keyboard_return,
              onPressed: () => onRestore(item.record),
            ),
          ],
        );
      },
    );
  }
}

StudioGeneratedImageItem _galleryGeneratedImageItem(_GalleryDisplayItem item) {
  final imagePath = item.record.imagePath?.trim();
  if (_existingImageFile(imagePath) != null) {
    return StudioGeneratedImageItem.file(
      id: item.record.id,
      name: item.title,
      imagePath: imagePath!,
      source: item,
    );
  }
  return StudioGeneratedImageItem(
    id: item.record.id,
    name: item.title,
    source: item,
    placeholder: imagePath == null || imagePath.isEmpty ? '没有图像路径' : '图像文件不存在',
  );
}

// ignore: unused_element
class _GalleryCard extends StatelessWidget {
  final _GalleryDisplayItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPreview;
  final VoidCallback onRestore;

  const _GalleryCard({
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onPreview,
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: StudioTokens.radiusCard,
        onTap: item.hasImagePath ? onPreview : onSelect,
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
                    key: ValueKey('gallery-card-details-${item.record.id}'),
                    tooltip: '查看详情',
                    icon: Icons.info_outline,
                    selected: selected,
                    onPressed: onSelect,
                  ),
                  const SizedBox(width: 6),
                  StudioIconButton(
                    key: ValueKey('gallery-card-restore-${item.record.id}'),
                    tooltip: '送回工作台',
                    icon: Icons.keyboard_return,
                    onPressed: onRestore,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _GalleryThumbnail(
                key: ValueKey('gallery-card-image-${item.record.id}'),
                item: item,
                height: 136,
                previewKeyPrefix: 'gallery-card-preview',
                onPreview: null,
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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

class _GalleryThumbnail extends StatelessWidget {
  final _GalleryDisplayItem item;
  final double height;
  final BoxFit fit;
  final String previewKeyPrefix;
  final VoidCallback? onPreview;

  const _GalleryThumbnail({
    super.key,
    required this.item,
    required this.height,
    this.fit = BoxFit.cover,
    required this.previewKeyPrefix,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final file = _existingImageFile(item.record.imagePath);
    final imagePath = item.record.imagePath?.trim();
    final child = ClipRRect(
      borderRadius: StudioTokens.radiusCard,
      child: file == null
          ? _GalleryImagePlaceholder(
              title:
                  imagePath == null || imagePath.isEmpty ? '没有图像路径' : '图像文件不存在',
              subtitle: imagePath,
            )
          : Image.file(
              file,
              fit: fit,
              errorBuilder: (context, error, stackTrace) {
                return _GalleryImagePlaceholder(
                  title: 'Image could not be read',
                  subtitle: imagePath,
                );
              },
            ),
    );

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: StudioTokens.surfaceBase,
              borderRadius: StudioTokens.radiusCard,
              border: Border.all(color: StudioTokens.border),
            ),
            child: child,
          ),
          if (onPreview != null)
            Positioned(
              right: 8,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: StudioTokens.surfaceBase.withValues(alpha: 0.88),
                  borderRadius: StudioTokens.radiusPill,
                  border: Border.all(color: StudioTokens.cardOutline),
                ),
                child: IconButton(
                  key: ValueKey('$previewKeyPrefix-${item.record.id}'),
                  tooltip: '预览图像',
                  icon: const Icon(Icons.open_in_full_outlined),
                  onPressed: onPreview,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GalleryImagePlaceholder extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _GalleryImagePlaceholder({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final trimmedSubtitle = subtitle?.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_not_supported_outlined,
              color: StudioTokens.textMuted,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (trimmedSubtitle != null && trimmedSubtitle.isNotEmpty) ...[
              const SizedBox(height: 5),
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

class _GalleryDetailDrawer extends StatelessWidget {
  final _GalleryDisplayItem? item;
  final List<_GalleryDisplayItem> items;
  final void Function(_GalleryDisplayItem item, List<_GalleryDisplayItem> items)
      onPreview;
  final ValueChanged<StudioGalleryRecord> onRestore;

  const _GalleryDetailDrawer({
    required this.item,
    required this.items,
    required this.onPreview,
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

    final captureDrafts = _captureDraftsForGalleryRecord(entry.record);
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
          _GalleryThumbnail(
            key: ValueKey('gallery-detail-image-${entry.record.id}'),
            item: entry,
            height: 220,
            fit: BoxFit.contain,
            previewKeyPrefix: 'gallery-detail-preview',
            onPreview:
                entry.hasImagePath ? () => onPreview(entry, items) : null,
          ),
          const SizedBox(height: 12),
          Text(
            entry.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _DetailPromptBlock(label: 'Prompt', item: entry),
          if (captureDrafts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _GalleryAssetCaptureActions(
              recordId: entry.record.id,
              drafts: captureDrafts,
            ),
          ],
          _DetailBlock(label: 'Created', value: entry.createdLabel),
          if (entry.record.imagePath != null &&
              entry.record.imagePath!.isNotEmpty)
            _DetailBlock(label: 'File', value: entry.record.imagePath!),
          if (entry.metadataEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Metadata', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final detail in entry.metadataEntries)
              _DetailBlock(label: detail.label, value: detail.value),
          ] else ...[
            const SizedBox(height: 8),
            Text('Fallback', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _DetailBlock(
              label: 'Status',
              value: 'Metadata missing; showing file-level context only.',
            ),
            _DetailBlock(label: 'Title', value: entry.record.title),
            if (entry.record.imagePath != null &&
                entry.record.imagePath!.isNotEmpty)
              _DetailBlock(label: 'Image path', value: entry.record.imagePath!),
            _DetailBlock(label: 'Saved at', value: entry.createdLabel),
          ],
        ],
      ),
    );
  }
}

class _GalleryAssetCaptureActions extends StatelessWidget {
  final String recordId;
  final List<StudioAssetCaptureDraft> drafts;

  const _GalleryAssetCaptureActions({
    required this.recordId,
    required this.drafts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('保存为素材', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, draft) in drafts.indexed)
              StudioButton(
                key: ValueKey(
                  'gallery-save-asset-$recordId-'
                  '${draft.kind.storageKey}-$index',
                ),
                label: '保存素材',
                icon: _galleryAssetCaptureIcon(draft.kind),
                tone: StudioButtonTone.secondary,
                onPressed: () async {
                  await _showGalleryAssetCaptureDraft(context, draft);
                },
              ),
          ],
        ),
      ],
    );
  }
}

IconData _galleryAssetCaptureIcon(StudioAssetCaptureKind kind) {
  return switch (kind) {
    StudioAssetCaptureKind.artistChain => Icons.brush_outlined,
    StudioAssetCaptureKind.character => Icons.person_outline,
    StudioAssetCaptureKind.outfit => Icons.checkroom_outlined,
  };
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

  const _GalleryEmptyState({required this.title, required this.subtitle});

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

class _GalleryImageViewerDialog extends StatefulWidget {
  final List<_GalleryDisplayItem> items;
  final String initialItemId;
  final ValueChanged<StudioGalleryRecord> onRestore;
  final StudioAssetCaptureHostState? assetCaptureHost;

  const _GalleryImageViewerDialog({
    required this.items,
    required this.initialItemId,
    required this.onRestore,
    required this.assetCaptureHost,
  });

  @override
  State<_GalleryImageViewerDialog> createState() =>
      _GalleryImageViewerDialogState();
}

class _GalleryImageViewerDialogState extends State<_GalleryImageViewerDialog> {
  late int _index = _initialIndex();
  bool _fullscreen = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'gallery-image-viewer');

  _GalleryDisplayItem get _item => widget.items[_index];

  bool get _canNavigate => widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey('gallery-image-viewer-dialog'),
      insetPadding: _fullscreen ? EdgeInsets.zero : const EdgeInsets.all(24),
      backgroundColor: _fullscreen ? Colors.black : StudioTokens.surfaceBase,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: _fullscreen
            ? _buildFullscreenContent(context)
            : StudioResizableImagePreviewWindow(
                windowKey: const ValueKey('gallery-image-viewer-windowed'),
                child: _buildWindowedContent(context),
              ),
      ),
    );
  }

  Widget _buildWindowedContent(BuildContext context) {
    final item = _item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GalleryPreviewToolbar(
          item: item,
          currentIndex: _index,
          itemCount: widget.items.length,
          fullscreen: _fullscreen,
          canNavigate: _canNavigate,
          onPrevious: () => _navigate(-1),
          onNext: () => _navigate(1),
          onToggleFullscreen: _toggleFullscreen,
          onRestore: _restoreCurrent,
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: StudioTokens.radiusCard,
            child: _GalleryZoomableImageViewer(
              item: item,
              onTap: _toggleFullscreen,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GalleryPreviewPromptPanel(
          item: item,
          fullscreen: false,
          assetCaptureHost: widget.assetCaptureHost,
        ),
      ],
    );
  }

  Widget _buildFullscreenContent(BuildContext context) {
    final item = _item;
    return SizedBox.expand(
      key: const ValueKey('gallery-image-viewer-fullscreen'),
      child: Stack(
        children: [
          Positioned.fill(
            child: _GalleryZoomableImageViewer(item: item, fullscreen: true),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _GalleryOverlayPanel(
              child: _GalleryPreviewToolbar(
                item: item,
                currentIndex: _index,
                itemCount: widget.items.length,
                fullscreen: _fullscreen,
                canNavigate: _canNavigate,
                onPrevious: () => _navigate(-1),
                onNext: () => _navigate(1),
                onToggleFullscreen: _toggleFullscreen,
                onRestore: _restoreCurrent,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _navigate(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _navigate(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        setState(() => _fullscreen = false);
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _initialIndex() {
    final index = widget.items.indexWhere(
      (item) => item.record.id == widget.initialItemId,
    );
    return index < 0 ? 0 : index;
  }

  void _navigate(int delta) {
    if (!_canNavigate) return;
    setState(() {
      _index = (_index + delta) % widget.items.length;
      if (_index < 0) {
        _index += widget.items.length;
      }
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _fullscreen = !_fullscreen;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _restoreCurrent() {
    Navigator.of(context).pop();
    widget.onRestore(_item.record);
  }
}

class _GalleryPreviewToolbar extends StatelessWidget {
  final _GalleryDisplayItem item;
  final int currentIndex;
  final int itemCount;
  final bool fullscreen;
  final bool canNavigate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  const _GalleryPreviewToolbar({
    required this.item,
    required this.currentIndex,
    required this.itemCount,
    required this.fullscreen,
    required this.canNavigate,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleFullscreen,
    required this.onRestore,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('gallery-preview-previous'),
          tooltip: '上一张',
          onPressed: canNavigate ? onPrevious : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const ValueKey('gallery-preview-next'),
          tooltip: '下一张',
          onPressed: canNavigate ? onNext : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${currentIndex + 1}/$itemCount  ${item.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: StudioTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        IconButton(
          key: const ValueKey('gallery-preview-fullscreen-toggle'),
          tooltip: fullscreen ? '退出全屏' : '全屏查看',
          onPressed: onToggleFullscreen,
          icon: Icon(
            fullscreen
                ? Icons.fullscreen_exit_outlined
                : Icons.fullscreen_outlined,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('gallery-preview-restore'),
          onPressed: onRestore,
          icon: const Icon(Icons.keyboard_return),
          label: const Text('送回工作台'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '关闭',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _GalleryZoomableImageViewer extends StatefulWidget {
  final _GalleryDisplayItem item;
  final bool fullscreen;
  final VoidCallback? onTap;

  const _GalleryZoomableImageViewer({
    required this.item,
    this.fullscreen = false,
    this.onTap,
  });

  @override
  State<_GalleryZoomableImageViewer> createState() =>
      _GalleryZoomableImageViewerState();
}

class _GalleryZoomableImageViewerState
    extends State<_GalleryZoomableImageViewer> {
  static const double _minScale = 1;
  static const double _maxScale = 8;

  final TransformationController _controller = TransformationController();

  @override
  void didUpdateWidget(covariant _GalleryZoomableImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.record.id != widget.item.record.id) {
      _reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = max(1.0, constraints.maxWidth);
        final height = max(1.0, constraints.maxHeight);
        final file = _existingImageFile(widget.item.record.imagePath);
        return Listener(
          key: const ValueKey('gallery-zoomable-image-viewer'),
          onPointerSignal: _handlePointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: ColoredBox(
              color: Colors.black,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(4096),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: file == null
                      ? _GalleryImagePlaceholder(
                          title: '图像文件不存在',
                          subtitle: widget.item.record.imagePath,
                        )
                      : Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return _GalleryImagePlaceholder(
                              title: 'Image could not be read',
                              subtitle: widget.item.record.imagePath,
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }
    _scaleAt(event.localPosition, delta < 0 ? 1.12 : 0.88);
  }

  void _scaleAt(Offset focalPoint, double scaleFactor) {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final nextScale =
        (currentScale * scaleFactor).clamp(_minScale, _maxScale).toDouble();
    if (nextScale <= _minScale + 0.01) {
      _reset();
      return;
    }
    final effectiveScale = nextScale / currentScale;
    final next = _controller.value.clone()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(effectiveScale, effectiveScale, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _controller.value = next;
  }

  void _reset() {
    _controller.value = Matrix4.identity();
  }
}

class _GalleryPreviewPromptPanel extends StatelessWidget {
  final _GalleryDisplayItem item;
  final bool fullscreen;
  final StudioAssetCaptureHostState? assetCaptureHost;

  const _GalleryPreviewPromptPanel({
    required this.item,
    required this.fullscreen,
    required this.assetCaptureHost,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = item.summary.trim();
    final promptGroups = _galleryPromptGroups(item.record);
    final meta = [
      item.createdLabel,
      if (item.record.imagePath != null) item.record.imagePath!,
    ].join(' 路 ');
    final captureDrafts = _captureDraftsForGalleryRecord(item.record);
    final visibleCaptureGroupIds = _galleryVisibleCaptureGroupIds(prompt);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (promptGroups.isNotEmpty)
          PromptTagGroupDisplay(
            key: ValueKey('gallery-preview-prompt-tags-${item.record.id}'),
            groups: promptGroups,
            groupKeyPrefix: 'gallery-preview-prompt-group-${item.record.id}',
            tagKeyPrefix: 'gallery-preview-prompt-group-tags-${item.record.id}',
            defaultTranslated: true,
            dense: true,
            enableHoverShortcut: true,
            enableTagActions: true,
            showLayoutControls: !fullscreen,
            initialLayoutMode: PromptTagLayoutMode.grouped,
            groupActionBuilder: (context, groupContext) =>
                _galleryPreviewPromptGroupAction(
              context,
              groupContext,
              recordId: item.record.id,
              drafts: captureDrafts,
              assetCaptureHost: assetCaptureHost,
            ),
          )
        else if (prompt.isNotEmpty)
          PromptTagDisplay(
            key: ValueKey('gallery-preview-prompt-tags-${item.record.id}'),
            text: prompt,
            defaultTranslated: true,
            dense: true,
            enableHoverShortcut: true,
            enableTagActions: true,
            showLayoutControls: !fullscreen,
            initialLayoutMode: PromptTagLayoutMode.grouped,
            groupActionBuilder: (context, groupContext) =>
                _galleryPreviewPromptGroupAction(
              context,
              groupContext,
              recordId: item.record.id,
              drafts: captureDrafts,
              assetCaptureHost: assetCaptureHost,
            ),
          )
        else
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: StudioTokens.textSecondary),
          ),
        ..._galleryPreviewPromptFallbackActions(
          context,
          recordId: item.record.id,
          drafts: captureDrafts,
          visibleGroupIds: visibleCaptureGroupIds,
          assetCaptureHost: assetCaptureHost,
        ),
        const SizedBox(height: 6),
        Text(
          meta,
          maxLines: fullscreen ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: StudioTokens.textMuted),
        ),
      ],
    );
    if (fullscreen) {
      return content;
    }
    return StudioImagePreviewPromptScroll(
      key: const ValueKey('gallery-preview-prompt-scroll'),
      child: content,
    );
  }
}

Widget? _galleryPreviewPromptGroupAction(
  BuildContext context,
  PromptTagGroupActionContext groupContext, {
  required String recordId,
  required List<StudioAssetCaptureDraft> drafts,
  required StudioAssetCaptureHostState? assetCaptureHost,
}) {
  final entries = [
    for (final (index, draft) in drafts.indexed)
      if (_galleryAssetCaptureGroupId(draft.kind) == groupContext.group.id)
        (index, draft),
  ];
  if (entries.isEmpty) {
    return null;
  }
  final (index, draft) = entries.first;
  return _galleryPreviewPromptSaveButton(
    context,
    recordId: recordId,
    draft: _galleryDraftForVisiblePromptGroup(draft, groupContext),
    index: index,
    assetCaptureHost: assetCaptureHost,
  );
}

StudioAssetCaptureDraft _galleryDraftForVisiblePromptGroup(
  StudioAssetCaptureDraft draft,
  PromptTagGroupActionContext groupContext,
) {
  return switch (draft.kind) {
    StudioAssetCaptureKind.artistChain =>
      StudioAssetCaptureDrafts.artistFromVisibleTags(
        groupContext.promptTags,
        source: draft.source,
        name: draft.name,
        note: draft.note,
      ),
    StudioAssetCaptureKind.character =>
      StudioAssetCaptureDrafts.characterFromVisibleTags(
        groupContext.promptTags,
        source: draft.source,
        name: draft.name,
        note: draft.note,
      ),
    StudioAssetCaptureKind.outfit => draft,
  };
}

List<Widget> _galleryPreviewPromptFallbackActions(
  BuildContext context, {
  required String recordId,
  required List<StudioAssetCaptureDraft> drafts,
  required Set<String> visibleGroupIds,
  required StudioAssetCaptureHostState? assetCaptureHost,
}) {
  final missing = [
    for (final (index, draft) in drafts.indexed)
      if (!visibleGroupIds.contains(_galleryAssetCaptureGroupId(draft.kind)))
        (index, draft),
  ];
  if (missing.isEmpty) {
    return const [];
  }
  return [
    const SizedBox(height: 6),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (index, draft) in missing)
          _galleryPreviewPromptSaveButton(
            context,
            recordId: recordId,
            draft: draft,
            index: index,
            assetCaptureHost: assetCaptureHost,
          ),
      ],
    ),
  ];
}

Widget _galleryPreviewPromptSaveButton(
  BuildContext context, {
  required String recordId,
  required StudioAssetCaptureDraft draft,
  required int index,
  required StudioAssetCaptureHostState? assetCaptureHost,
}) {
  return TextButton.icon(
    key: ValueKey(
      'gallery-preview-prompt-save-asset-$recordId-'
      '${draft.kind.storageKey}-$index',
    ),
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: () async {
      await _showGalleryAssetCaptureDraft(
        context,
        draft,
        host: assetCaptureHost,
        closeBeforeShow: true,
      );
    },
    icon: Icon(_galleryAssetCaptureIcon(draft.kind), size: 15),
    label: const Text('保存为素材'),
  );
}

Set<String> _galleryVisibleCaptureGroupIds(String prompt) {
  return {
    for (final tag in PromptTagProcessor.analyzeWorkshopTags(prompt))
      PromptTagClassifier.classify(tag.displayText).group.id,
  };
}

List<PromptTagDisplayGroup> _galleryPromptGroups(StudioGalleryRecord record) {
  final paramConfig = _galleryMapValue(record.document.payload['param_config']);
  final parameterGroups = promptTagGroupsFromPromptParameters(paramConfig);
  if (parameterGroups.isNotEmpty) {
    return parameterGroups;
  }
  return promptTagGroupsFromWorkbenchPayload(record.document.payload);
}

Map<String, dynamic> _galleryMapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

String _galleryAssetCaptureGroupId(StudioAssetCaptureKind kind) {
  return switch (kind) {
    StudioAssetCaptureKind.artistChain => 'artist',
    StudioAssetCaptureKind.character => 'character',
    StudioAssetCaptureKind.outfit => 'clothing',
  };
}

class _GalleryOverlayPanel extends StatelessWidget {
  final Widget child;

  const _GalleryOverlayPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase.withValues(alpha: 0.88),
        borderRadius: StudioTokens.radiusCard,
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String label;
  final String value;

  const _DetailBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: StudioTokens.textMuted),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _DetailPromptBlock extends StatelessWidget {
  final String label;
  final _GalleryDisplayItem item;

  const _DetailPromptBlock({required this.label, required this.item});

  @override
  Widget build(BuildContext context) {
    final text = item.summary.trim();
    final groups = _galleryPromptGroups(item.record);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: StudioTokens.textMuted),
          ),
          const SizedBox(height: 4),
          if (groups.isEmpty && text.isEmpty)
            const Text('-')
          else if (groups.isNotEmpty)
            PromptTagGroupDisplay(
              key: ValueKey('gallery-detail-prompt-tags-${item.record.id}'),
              groups: groups,
              groupKeyPrefix: 'gallery-detail-prompt-group-${item.record.id}',
              tagKeyPrefix:
                  'gallery-detail-prompt-group-tags-${item.record.id}',
              defaultTranslated: true,
              dense: true,
              enableHoverShortcut: true,
              enableTagActions: true,
              showLayoutControls: true,
              initialLayoutMode: PromptTagLayoutMode.grouped,
            )
          else
            PromptTagDisplay(
              key: ValueKey('gallery-detail-prompt-tags-${item.record.id}'),
              text: text,
              defaultTranslated: true,
              dense: true,
              enableHoverShortcut: true,
              enableTagActions: true,
              showLayoutControls: true,
              initialLayoutMode: PromptTagLayoutMode.grouped,
            ),
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
    final title =
        record.title.trim().isEmpty ? 'Untitled record' : record.title;
    final summary = record.info.trim().isEmpty
        ? 'No prompt preview was saved with this record.'
        : record.info.trim();
    final createdLabel = _formatTimestamp(record.createdAt);
    final footerParts = <String>[
      createdLabel,
      metadataEntries.isEmpty
          ? 'Metadata missing'
          : '${metadataEntries.length} metadata fields',
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

  bool get hasImagePath => record.imagePath?.trim().isNotEmpty == true;

  bool matches(String query) {
    return searchText.contains(query);
  }
}

class _GalleryDetailLine {
  final String label;
  final String value;

  const _GalleryDetailLine({required this.label, required this.value});
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

File? _existingImageFile(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  try {
    final file = File(trimmed);
    return file.existsSync() ? file : null;
  } catch (_) {
    return null;
  }
}
