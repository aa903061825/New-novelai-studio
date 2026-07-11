import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/models/studio_director_tool.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_metric_card.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_wheel_zoom.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';

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

enum _GalleryRecordAction {
  restore,
  useAsI2i,
  enhance,
  upscale,
  directorTool,
  inpaint,
  delete,
}

const _galleryDesktopBreakpoint = 1180.0;
const _galleryDetailMinWidth = 520.0;
const _galleryDetailMaxWidth = 720.0;
const _galleryCardColumnWidth = 320.0;
const _galleryActionUseAsI2iLabel = '设为图生图';
const _galleryActionEnhanceLabel = '增强';
const _galleryActionUpscaleLabel = '放大';
const _galleryActionDirectorLabel = '导演工具';
const _galleryActionInpaintLabel = '重绘';
const _galleryActionRestoreLabel = '送回工作台';
const _galleryActionDeleteLabel = '删除记录';

class _StudioGalleryPageState extends State<StudioGalleryPage> {
  late Future<List<StudioGalleryRecord>> _recordsFuture;
  String _query = '';
  _GalleryFilter _filter = _GalleryFilter.all;
  String? _selectedRecordId;
  Set<String> _selectedRecordIds = const {};

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
                    final visibleSelectedIds = {
                      for (final item in filteredItems)
                        if (_selectedRecordIds.contains(item.record.id))
                          item.record.id,
                    };

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
                          selectedRecordIds: visibleSelectedIds,
                          onSelect: (item) => setState(() {
                            _selectedRecordId = item.record.id;
                            _selectedRecordIds = const {};
                          }),
                          onSelectionChanged: _selectRecords,
                          onPreview: _showPreview,
                          onRestore: _restoreRecord,
                          onUseAsI2iSource: _useRecordAsI2iSource,
                          onEnhance: _enhanceRecord,
                          onUpscale: _upscaleRecord,
                          onDirectorTool: _directorToolRecord,
                          onInpaint: _inpaintRecord,
                          onDelete: _deleteRecord,
                          onDeleteSelected: _deleteRecords,
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

  void _selectRecords(Set<String> recordIds) {
    setState(() {
      _selectedRecordIds = Set.unmodifiable(recordIds);
      if (recordIds.isEmpty) {
        return;
      }
      if (_selectedRecordId == null || !recordIds.contains(_selectedRecordId)) {
        _selectedRecordId = recordIds.first;
      }
    });
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
      footerBuilder: (context, generatedItem, fullscreen) {
        final galleryItem = generatedItem.source as _GalleryDisplayItem;
        return _GalleryPreviewPromptPanel(
          item: galleryItem,
          fullscreen: fullscreen,
          assetCaptureHost: assetCaptureHost,
          onUseAsI2iSource: galleryItem.hasExistingImage
              ? () async {
                  Navigator.of(context).pop();
                  await _useRecordAsI2iSource(galleryItem.record);
                }
              : null,
          onEnhance: galleryItem.hasExistingImage
              ? () async {
                  Navigator.of(context).pop();
                  await _enhanceRecord(galleryItem.record);
                }
              : null,
          onUpscale: galleryItem.hasExistingImage
              ? () async {
                  Navigator.of(context).pop();
                  await _upscaleRecord(galleryItem.record);
                }
              : null,
          onDirectorTool: galleryItem.hasExistingImage
              ? () async {
                  Navigator.of(context).pop();
                  await _directorToolRecord(galleryItem.record);
                }
              : null,
          onInpaint: galleryItem.hasExistingImage
              ? () async {
                  Navigator.of(context).pop();
                  await _inpaintRecord(galleryItem.record);
                }
              : null,
          onRestore: () => _restoreRecord(galleryItem.record),
          onDelete: () async {
            Navigator.of(context).pop();
            await _deleteRecord(galleryItem.record);
          },
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

  Future<void> _deleteRecord(StudioGalleryRecord record) {
    return _deleteRecords([record]);
  }

  Future<void> _deleteRecords(List<StudioGalleryRecord> records) async {
    final seenRecordIds = <String>{};
    final targets = [
      for (final record in records)
        if (seenRecordIds.add(record.id)) record,
    ];
    if (targets.isEmpty) return;

    final deleteImageFile = await showDialog<bool>(
      context: context,
      builder: (context) {
        final singleTitle =
            targets.length == 1 ? targets.first.title.trim() : null;
        final contentText = targets.length == 1
            ? '将从画廊移除“${singleTitle == null || singleTitle.isEmpty ? '未命名记录' : singleTitle}”。默认只删除画廊记录，'
                '不会删除本地图片文件。'
            : '将从画廊移除 ${targets.length} 条记录。默认只删除画廊记录，不会删除本地图片文件。';
        var deleteLocalFile = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              key: const ValueKey('gallery-delete-dialog'),
              title: const Text('删除画廊记录？'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contentText),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('gallery-delete-local-file-checkbox'),
                    value: deleteLocalFile,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('同时删除本地图片文件'),
                    subtitle: const Text('勾选后会尝试删除这条记录里的 imagePath 文件。'),
                    onChanged: (value) {
                      setDialogState(() {
                        deleteLocalFile = value ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  key: const ValueKey('gallery-delete-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  key: const ValueKey('gallery-delete-confirm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: StudioTokens.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(deleteLocalFile),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text(_galleryActionDeleteLabel),
                ),
              ],
            );
          },
        );
      },
    );
    if (deleteImageFile == null || !mounted) return;

    try {
      for (final record in targets) {
        await widget.galleryService.removeRecord(
          record.id,
          deleteImageFile: deleteImageFile,
        );
      }
      if (!mounted) return;
      final targetIds = targets.map((record) => record.id).toSet();
      setState(() {
        if (_selectedRecordId != null &&
            targetIds.contains(_selectedRecordId)) {
          _selectedRecordId = null;
        }
        _selectedRecordIds = _selectedRecordIds.difference(targetIds);
        _recordsFuture = widget.galleryService.loadCreativeRecords();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteImageFile
                ? '已从画廊移除 ${targets.length} 条记录，并尝试删除本地图片文件。'
                : '已从画廊移除 ${targets.length} 条记录，图片文件已保留。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<void> _useRecordAsI2iSource(StudioGalleryRecord record) async {
    try {
      _showGallerySnackBar('正在设置图生图源图...');
      await widget.galleryService.useRecordAsI2iSource(
        record,
        widget.payloadConfig,
      );
      widget.viewModel.notifyConfigChanged();
      if (!mounted) return;
      _showGallerySnackBar('已设为图生图源图');
    } catch (error) {
      if (!mounted) return;
      _showGallerySnackBar(error.toString());
    }
  }

  Future<void> _enhanceRecord(StudioGalleryRecord record) {
    return _runGalleryOperation(
      () => widget.viewModel.enhanceGalleryRecord(record),
      pendingMessage: '正在提交增强...',
      successMessage: '已开始增强',
    );
  }

  Future<void> _upscaleRecord(StudioGalleryRecord record) {
    return _runGalleryOperation(
      () => widget.viewModel.upscaleGalleryRecord(record),
      pendingMessage: '正在提交放大...',
      successMessage: '已开始放大',
    );
  }

  Future<void> _directorToolRecord(StudioGalleryRecord record) async {
    final options = await showDialog<StudioDirectorToolOptions>(
      context: context,
      builder: (context) => const _DirectorToolDialog(),
    );
    if (options == null) return;
    return _runGalleryOperation(
      () => widget.viewModel.runDirectorToolGalleryRecord(record, options),
      pendingMessage: '正在提交导演工具处理...',
      successMessage: '已开始导演工具处理',
    );
  }

  Future<void> _inpaintRecord(StudioGalleryRecord record) async {
    final result = await showDialog<_InpaintDialogResult>(
      context: context,
      builder: (context) => _InpaintDialog(record: record),
    );
    if (result == null) return;
    return _runGalleryOperation(
      () => widget.viewModel.runInpaintGalleryRecord(
        record,
        maskImagePath: result.maskImagePath,
        strength: result.strength,
      ),
      pendingMessage: '正在提交重绘...',
      successMessage: '已开始重绘',
    );
  }

  Future<void> _runGalleryOperation(
    Future<void> Function() operation, {
    required String pendingMessage,
    required String successMessage,
  }) async {
    try {
      _showGallerySnackBar(pendingMessage);
      await operation();
      if (!mounted) return;
      _showGallerySnackBar(successMessage);
    } catch (error) {
      if (!mounted) return;
      _showGallerySnackBar(error.toString());
    }
  }

  void _showGallerySnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DirectorToolDialog extends StatefulWidget {
  const _DirectorToolDialog();

  @override
  State<_DirectorToolDialog> createState() => _DirectorToolDialogState();
}

class _DirectorToolDialogState extends State<_DirectorToolDialog> {
  final _promptController = TextEditingController();
  StudioDirectorTool _selectedTool = StudioDirectorTool.removeBackground;
  int _defry = 0;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usesPrompt = _selectedTool == StudioDirectorTool.colorize ||
        _selectedTool == StudioDirectorTool.emotion;
    return AlertDialog(
      key: const ValueKey('gallery-director-tool-dialog'),
      title: const Text(_galleryActionDirectorLabel),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tool in StudioDirectorTool.values)
                    _DirectorToolChoice(
                      tool: tool,
                      selected: tool == _selectedTool,
                      onPressed: () => setState(() {
                        _selectedTool = tool;
                      }),
                    ),
                ],
              ),
              if (usesPrompt) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('gallery-director-tool-prompt'),
                  controller: _promptController,
                  decoration: const InputDecoration(
                    labelText: '提示词',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('gallery-director-tool-defry'),
                  initialValue: _defry,
                  decoration: const InputDecoration(
                    labelText: '去伪影强度',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var value = 0; value <= 5; value++)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.toString()),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _defry = value ?? 0;
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('gallery-director-tool-run'),
          onPressed: () => Navigator.of(context).pop(
            StudioDirectorToolOptions(
              tool: _selectedTool,
              prompt: _promptController.text,
              defry: _defry,
            ),
          ),
          child: const Text('执行'),
        ),
      ],
    );
  }
}

class _DirectorToolChoice extends StatelessWidget {
  final StudioDirectorTool tool;
  final bool selected;
  final VoidCallback onPressed;

  const _DirectorToolChoice({
    required this.tool,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (tool) {
      StudioDirectorTool.removeBackground => '移除背景',
      StudioDirectorTool.lineArt => '线稿',
      StudioDirectorTool.sketch => '草图',
      StudioDirectorTool.colorize => '上色',
      StudioDirectorTool.emotion => '表情',
      StudioDirectorTool.declutter => '去杂物',
    };
    final child = Text(label);
    if (selected) {
      return FilledButton(
        key: ValueKey('gallery-director-tool-option-${tool.name}'),
        onPressed: onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      key: ValueKey('gallery-director-tool-option-${tool.name}'),
      onPressed: onPressed,
      child: child,
    );
  }
}

class _InpaintDialogResult {
  final String maskImagePath;
  final double strength;

  const _InpaintDialogResult({
    required this.maskImagePath,
    required this.strength,
  });
}

class _InpaintDialog extends StatefulWidget {
  final StudioGalleryRecord record;

  const _InpaintDialog({required this.record});

  @override
  State<_InpaintDialog> createState() => _InpaintDialogState();
}

class _InpaintDialogState extends State<_InpaintDialog> {
  String? _maskImagePath;
  double _strength = 1;
  bool _writingMask = false;
  String? _error;

  Future<void> _paintFullMask() async {
    setState(() {
      _writingMask = true;
      _error = null;
    });

    try {
      final sourcePath = widget.record.imagePath?.trim();
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError('这条记录没有可用的源图。');
      }

      final sourceFile = File(sourcePath);
      final sourceImage = img.decodeImage(sourceFile.readAsBytesSync());
      if (sourceImage == null) {
        throw StateError('无法读取源图像。');
      }

      final mask = img.Image(
        width: sourceImage.width,
        height: sourceImage.height,
        numChannels: 4,
      );
      img.fill(mask, color: img.ColorRgba8(255, 255, 255, 255));

      final safeId =
          widget.record.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final maskFile = File(
        '${sourceFile.parent.path}${Platform.pathSeparator}'
        'nai-inpaint-mask-$safeId-$stamp.png',
      );
      maskFile.writeAsBytesSync(img.encodePng(mask), flush: true);

      if (!mounted) return;
      setState(() {
        _maskImagePath = maskFile.path;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _maskImagePath = null;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _writingMask = false;
        });
      }
    }
  }

  void _clearMask() {
    setState(() {
      _maskImagePath = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canRun = _maskImagePath != null && !_writingMask;
    final maskLabel = _maskImagePath == null
        ? '需要先生成遮罩'
        : '遮罩已生成：${File(_maskImagePath!).uri.pathSegments.last}';
    final recordTitle = widget.record.title.trim();

    return AlertDialog(
      key: const ValueKey('gallery-inpaint-dialog'),
      title: const Text(_galleryActionInpaintLabel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                recordTitle.isEmpty ? widget.record.id : recordTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: StudioTokens.border),
                  borderRadius: BorderRadius.circular(8),
                  color: StudioTokens.surface2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      maskLabel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: StudioTokens.danger,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('gallery-inpaint-paint-mask'),
                          onPressed: _writingMask ? null : _paintFullMask,
                          icon: _writingMask
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.brush_outlined),
                          label: const Text('生成全图遮罩'),
                        ),
                        TextButton.icon(
                          key: const ValueKey('gallery-inpaint-clear-mask'),
                          onPressed: _maskImagePath == null ? null : _clearMask,
                          icon: const Icon(Icons.layers_clear_outlined),
                          label: const Text('清空'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '重绘强度 ${_strength.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Slider(
                value: _strength,
                min: 0,
                max: 1,
                divisions: 20,
                label: _strength.toStringAsFixed(2),
                onChanged: (value) => setState(() {
                  _strength = value;
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('gallery-inpaint-run'),
          onPressed: canRun
              ? () => Navigator.of(context).pop(
                    _InpaintDialogResult(
                      maskImagePath: _maskImagePath!,
                      strength: _strength,
                    ),
                  )
              : null,
          child: const Text('开始重绘'),
        ),
      ],
    );
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
      label: title.isEmpty ? '画廊条目' : title,
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
        ? '这里会沉淀每次生成后的记录、元数据和回流入口。'
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
              hintText: '搜索画廊记录、提示词或元数据',
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
                  label: '元数据完整',
                  icon: Icons.check_circle_outline,
                  selected: selectedFilter == _GalleryFilter.parsed,
                  onTap: () => onFilterChanged(_GalleryFilter.parsed),
                  accentColor: StudioTokens.active,
                ),
              ),
              KeyedSubtree(
                key: const ValueKey('gallery-filter-missing'),
                child: StudioChip(
                  label: '元数据缺失',
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
  final Set<String> selectedRecordIds;
  final ValueChanged<_GalleryDisplayItem> onSelect;
  final ValueChanged<Set<String>> onSelectionChanged;
  final void Function(_GalleryDisplayItem item, List<_GalleryDisplayItem> items)
      onPreview;
  final ValueChanged<StudioGalleryRecord> onRestore;
  final ValueChanged<StudioGalleryRecord> onUseAsI2iSource;
  final ValueChanged<StudioGalleryRecord> onEnhance;
  final ValueChanged<StudioGalleryRecord> onUpscale;
  final ValueChanged<StudioGalleryRecord> onDirectorTool;
  final ValueChanged<StudioGalleryRecord> onInpaint;
  final ValueChanged<StudioGalleryRecord> onDelete;
  final ValueChanged<List<StudioGalleryRecord>> onDeleteSelected;

  const _GalleryContent({
    required this.items,
    required this.selectedItem,
    required this.selectedRecordIds,
    required this.onSelect,
    required this.onSelectionChanged,
    required this.onPreview,
    required this.onRestore,
    required this.onUseAsI2iSource,
    required this.onEnhance,
    required this.onUpscale,
    required this.onDirectorTool,
    required this.onInpaint,
    required this.onDelete,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _GalleryStatusPanel(
        icon: Icons.search_off,
        title: '没有匹配结果',
        subtitle: '调整关键词或元数据状态筛选后再试一次。',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final board = _GalleryBoard(
          items: items,
          selectedId: selectedItem?.record.id,
          selectedRecordIds: selectedRecordIds,
          onSelect: onSelect,
          onSelectionChanged: onSelectionChanged,
          onPreview: onPreview,
          onRestore: onRestore,
          onUseAsI2iSource: onUseAsI2iSource,
          onEnhance: onEnhance,
          onUpscale: onUpscale,
          onDirectorTool: onDirectorTool,
          onInpaint: onInpaint,
          onDelete: onDelete,
        );
        final selectedItems = [
          for (final item in items)
            if (selectedRecordIds.contains(item.record.id)) item,
        ];
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectedItems.isNotEmpty) ...[
              _GallerySelectionToolbar(
                selectedCount: selectedItems.length,
                onClear: () => onSelectionChanged(const {}),
                onDelete: () => onDeleteSelected(
                  selectedItems.map((item) => item.record).toList(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            board,
          ],
        );
        final drawer = _GalleryDetailDrawer(
          item: selectedItem,
          items: items,
          onPreview: onPreview,
          onRestore: onRestore,
          onUseAsI2iSource: onUseAsI2iSource,
          onEnhance: onEnhance,
          onUpscale: onUpscale,
          onDirectorTool: onDirectorTool,
          onInpaint: onInpaint,
          onDelete: onDelete,
        );

        if (constraints.maxWidth < _galleryDesktopBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [content, const SizedBox(height: 14), drawer],
          );
        }

        final drawerWidth = min(
          _galleryDetailMaxWidth,
          max(_galleryDetailMinWidth, constraints.maxWidth * 0.36),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            const SizedBox(width: 14),
            SizedBox(width: drawerWidth, child: drawer),
          ],
        );
      },
    );
  }
}

class _GallerySelectionToolbar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  const _GallerySelectionToolbar({
    required this.selectedCount,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('gallery-selection-toolbar'),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        border: Border.all(color: StudioTokens.cardOutline),
        borderRadius: StudioTokens.radiusCard,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.select_all_outlined,
              size: 18,
              color: StudioTokens.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '已选 $selectedCount',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            StudioIconButton(
              key: const ValueKey('gallery-selection-clear'),
              tooltip: '清空选择',
              icon: Icons.close,
              onPressed: onClear,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('gallery-selection-delete'),
              style: FilledButton.styleFrom(
                backgroundColor: StudioTokens.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryBoard extends StatefulWidget {
  final List<_GalleryDisplayItem> items;
  final String? selectedId;
  final Set<String> selectedRecordIds;
  final ValueChanged<_GalleryDisplayItem> onSelect;
  final ValueChanged<Set<String>> onSelectionChanged;
  final void Function(_GalleryDisplayItem item, List<_GalleryDisplayItem> items)
      onPreview;
  final ValueChanged<StudioGalleryRecord> onRestore;
  final ValueChanged<StudioGalleryRecord> onUseAsI2iSource;
  final ValueChanged<StudioGalleryRecord> onEnhance;
  final ValueChanged<StudioGalleryRecord> onUpscale;
  final ValueChanged<StudioGalleryRecord> onDirectorTool;
  final ValueChanged<StudioGalleryRecord> onInpaint;
  final ValueChanged<StudioGalleryRecord> onDelete;

  const _GalleryBoard({
    required this.items,
    required this.selectedId,
    required this.selectedRecordIds,
    required this.onSelect,
    required this.onSelectionChanged,
    required this.onPreview,
    required this.onRestore,
    required this.onUseAsI2iSource,
    required this.onEnhance,
    required this.onUpscale,
    required this.onDirectorTool,
    required this.onInpaint,
    required this.onDelete,
  });

  @override
  State<_GalleryBoard> createState() => _GalleryBoardState();
}

class _GalleryBoardState extends State<_GalleryBoard> {
  static const double _marqueeStartSlop = 6;

  final GlobalKey _boardKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  Offset? _marqueeStartLocal;
  Offset? _marqueeCurrentLocal;
  Offset? _marqueeStartGlobal;
  Offset? _marqueeCurrentGlobal;
  bool _marqueeActive = false;
  Set<String> _lastMarqueeSelection = const {};

  @override
  void didUpdateWidget(_GalleryBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = widget.items.map((item) => item.record.id).toSet();
    _itemKeys.removeWhere((recordId, key) => !liveIds.contains(recordId));
  }

  @override
  Widget build(BuildContext context) {
    final galleryItems = widget.items.map(_galleryGeneratedImageItem).toList();
    return Listener(
      key: _boardKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          StudioGeneratedImageGallery(
            items: galleryItems,
            selectedId: widget.selectedId,
            selectedIds: widget.selectedRecordIds,
            itemKeys: {
              for (final item in widget.items)
                item.record.id: _keyForRecord(item.record.id),
            },
            columnWidth: _galleryCardColumnWidth,
            cardKeyPrefix: 'gallery-card',
            imageKeyPrefix: 'gallery-card-image',
            onOpen: (context, generatedItem) {
              final item = generatedItem.source as _GalleryDisplayItem;
              widget.onSelect(item);
              widget.onPreview(item, widget.items);
            },
            trailingBuilder: (context, generatedItem) {
              final item = generatedItem.source as _GalleryDisplayItem;
              return _GalleryCardActionMenu(
                recordId: item.record.id,
                hasExistingImage: item.hasExistingImage,
                onSelected: (action) {
                  switch (action) {
                    case _GalleryRecordAction.restore:
                      widget.onRestore(item.record);
                      break;
                    case _GalleryRecordAction.useAsI2i:
                      widget.onUseAsI2iSource(item.record);
                      break;
                    case _GalleryRecordAction.enhance:
                      widget.onEnhance(item.record);
                      break;
                    case _GalleryRecordAction.upscale:
                      widget.onUpscale(item.record);
                      break;
                    case _GalleryRecordAction.directorTool:
                      widget.onDirectorTool(item.record);
                      break;
                    case _GalleryRecordAction.inpaint:
                      widget.onInpaint(item.record);
                      break;
                    case _GalleryRecordAction.delete:
                      widget.onDelete(item.record);
                      break;
                  }
                },
              );
            },
          ),
          if (_marqueeRect case final rect?)
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: StudioTokens.primary.withValues(alpha: 0.12),
                    border: Border.all(
                      color: StudioTokens.primary,
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  GlobalKey _keyForRecord(String recordId) {
    return _itemKeys.putIfAbsent(
      recordId,
      () => GlobalKey(debugLabel: 'gallery-card-key-$recordId'),
    );
  }

  Rect? get _marqueeRect {
    if (!_marqueeActive) return null;
    final start = _marqueeStartLocal;
    final current = _marqueeCurrentLocal;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    _marqueeStartGlobal = event.position;
    _marqueeCurrentGlobal = event.position;
    _marqueeStartLocal = _localPosition(event.position);
    _marqueeCurrentLocal = _marqueeStartLocal;
    _marqueeActive = false;
    _lastMarqueeSelection = const {};
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _marqueeStartGlobal;
    if (start == null) return;
    final shouldActivate = _marqueeActive ||
        (event.position - start).distance >= _marqueeStartSlop;
    if (!shouldActivate) return;
    setState(() {
      _marqueeActive = true;
      _marqueeCurrentGlobal = event.position;
      _marqueeCurrentLocal = _localPosition(event.position);
    });
    _updateMarqueeSelection();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_marqueeStartGlobal == null) return;
    _finishMarquee();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_marqueeStartGlobal == null) return;
    _finishMarquee();
  }

  void _finishMarquee() {
    setState(() {
      _marqueeStartGlobal = null;
      _marqueeCurrentGlobal = null;
      _marqueeStartLocal = null;
      _marqueeCurrentLocal = null;
      _marqueeActive = false;
      _lastMarqueeSelection = const {};
    });
  }

  void _updateMarqueeSelection() {
    final start = _marqueeStartGlobal;
    final current = _marqueeCurrentGlobal;
    if (start == null || current == null) return;
    final marquee = Rect.fromPoints(start, current);
    final selected = <String>{};
    for (final item in widget.items) {
      final rect = _cardRect(item.record.id);
      if (rect != null && rect.overlaps(marquee)) {
        selected.add(item.record.id);
      }
    }
    if (setEquals(selected, _lastMarqueeSelection)) return;
    _lastMarqueeSelection = selected;
    widget.onSelectionChanged(selected);
  }

  Offset _localPosition(Offset globalPosition) {
    final renderObject = _boardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return globalPosition;
    return renderObject.globalToLocal(globalPosition);
  }

  Rect? _cardRect(String recordId) {
    final renderObject =
        _itemKeys[recordId]?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}

class _GalleryCardActionMenu extends StatelessWidget {
  final String recordId;
  final bool hasExistingImage;
  final ValueChanged<_GalleryRecordAction> onSelected;

  const _GalleryCardActionMenu({
    required this.recordId,
    required this.hasExistingImage,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '更多处理',
      child: PopupMenuButton<_GalleryRecordAction>(
        key: ValueKey('gallery-card-more-$recordId'),
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final action
              in _galleryRecordActions(hasExistingImage: hasExistingImage))
            PopupMenuItem(
              key: ValueKey('gallery-card-menu-${action.name}-$recordId'),
              value: action,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_galleryRecordActionIcon(action), size: 18),
                  const SizedBox(width: 8),
                  Text(_galleryRecordActionLabel(action)),
                ],
              ),
            ),
        ],
        child: SizedBox.square(
          dimension: 34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: StudioTokens.surface2,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(
              Icons.more_horiz,
              size: 20,
              color: StudioTokens.textSecondary,
            ),
          ),
        ),
      ),
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
                  title: '图像无法读取',
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
  final ValueChanged<StudioGalleryRecord> onUseAsI2iSource;
  final ValueChanged<StudioGalleryRecord> onEnhance;
  final ValueChanged<StudioGalleryRecord> onUpscale;
  final ValueChanged<StudioGalleryRecord> onDirectorTool;
  final ValueChanged<StudioGalleryRecord> onInpaint;
  final ValueChanged<StudioGalleryRecord> onDelete;

  const _GalleryDetailDrawer({
    required this.item,
    required this.items,
    required this.onPreview,
    required this.onRestore,
    required this.onUseAsI2iSource,
    required this.onEnhance,
    required this.onUpscale,
    required this.onDirectorTool,
    required this.onInpaint,
    required this.onDelete,
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
          subtitle: '查看元数据详情、降级信息，并把结果送回工作台。',
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
          Text(
            '记录详情',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            key: const ValueKey('gallery-detail-actions'),
            spacing: 8,
            runSpacing: 8,
            children: [
              if (entry.hasExistingImage) ...[
                _GalleryDetailActionButton(
                  key: const ValueKey('gallery-detail-use-as-i2i'),
                  label: _galleryActionUseAsI2iLabel,
                  icon: Icons.image_search_outlined,
                  tone: StudioButtonTone.secondary,
                  onPressed: () => onUseAsI2iSource(entry.record),
                ),
                _GalleryDetailActionButton(
                  key: const ValueKey('gallery-detail-enhance'),
                  label: _galleryActionEnhanceLabel,
                  icon: Icons.auto_fix_high_outlined,
                  tone: StudioButtonTone.secondary,
                  onPressed: () => onEnhance(entry.record),
                ),
                _GalleryDetailActionButton(
                  key: const ValueKey('gallery-detail-upscale'),
                  label: _galleryActionUpscaleLabel,
                  icon: Icons.zoom_out_map_outlined,
                  tone: StudioButtonTone.secondary,
                  onPressed: () => onUpscale(entry.record),
                ),
                _GalleryDetailActionButton(
                  key: const ValueKey('gallery-detail-director'),
                  label: _galleryActionDirectorLabel,
                  icon: Icons.auto_awesome_motion_outlined,
                  tone: StudioButtonTone.secondary,
                  onPressed: () => onDirectorTool(entry.record),
                ),
                _GalleryDetailActionButton(
                  key: const ValueKey('gallery-detail-inpaint'),
                  label: _galleryActionInpaintLabel,
                  icon: Icons.brush_outlined,
                  tone: StudioButtonTone.secondary,
                  onPressed: () => onInpaint(entry.record),
                ),
              ],
              _GalleryDetailActionButton(
                key: const ValueKey('gallery-detail-restore'),
                label: _galleryActionRestoreLabel,
                icon: Icons.keyboard_return,
                onPressed: () => onRestore(entry.record),
              ),
              _GalleryDetailActionButton(
                key: const ValueKey('gallery-detail-delete'),
                label: _galleryActionDeleteLabel,
                icon: Icons.delete_outline,
                tone: StudioButtonTone.danger,
                onPressed: () => onDelete(entry.record),
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
          _GalleryLineageBlock(
            key: ValueKey('gallery-detail-lineage-${entry.record.id}'),
            lineage: entry.record.lineage,
          ),
          _DetailPromptBlock(label: '提示词', item: entry),
          if (captureDrafts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _GalleryAssetCaptureActions(
              recordId: entry.record.id,
              drafts: captureDrafts,
            ),
          ],
          _DetailBlock(label: '保存时间', value: entry.createdLabel),
          if (entry.record.imagePath != null &&
              entry.record.imagePath!.isNotEmpty)
            _DetailBlock(label: '文件', value: entry.record.imagePath!),
          if (entry.metadataEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('元数据', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final detail in entry.metadataEntries)
              _DetailBlock(label: detail.label, value: detail.value),
          ] else ...[
            const SizedBox(height: 8),
            Text('降级信息', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _DetailBlock(
              label: '状态',
              value: '缺少元数据，仅显示文件级上下文。',
            ),
            _DetailBlock(label: '标题', value: entry.record.title),
            if (entry.record.imagePath != null &&
                entry.record.imagePath!.isNotEmpty)
              _DetailBlock(label: '图像路径', value: entry.record.imagePath!),
            _DetailBlock(label: '保存时间', value: entry.createdLabel),
          ],
        ],
      ),
    );
  }
}

class _GalleryDetailActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final StudioButtonTone tone;
  final VoidCallback? onPressed;

  const _GalleryDetailActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.tone = StudioButtonTone.primary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 168),
      child: StudioButton(
        label: label,
        icon: icon,
        tone: tone,
        onPressed: onPressed,
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

class _GalleryLineageBlock extends StatelessWidget {
  final StudioGalleryLineage? lineage;
  final bool dense;

  const _GalleryLineageBlock({
    super.key,
    required this.lineage,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final value = lineage;
    if (value == null) {
      return const SizedBox.shrink();
    }
    final details = [
      _GalleryDetailLine(
        label: '操作',
        value: _galleryOperationLabel(value.operation),
      ),
      if (value.sourceRecordId != null && value.sourceRecordId!.isNotEmpty)
        _GalleryDetailLine(label: '来源记录', value: value.sourceRecordId!),
      if (value.sourceImagePath != null && value.sourceImagePath!.isNotEmpty)
        _GalleryDetailLine(label: '来源图像', value: value.sourceImagePath!),
      if (value.parameters.isNotEmpty)
        _GalleryDetailLine(
          label: '参数',
          value: _stringifyLineageParameters(value.parameters),
        ),
    ];

    if (dense) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final detail in details)
              StudioChip(
                label: '${detail.label}: ${detail.value}',
                icon: detail.label == '操作'
                    ? Icons.history_outlined
                    : Icons.account_tree_outlined,
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusCard,
          border: Border.all(color: StudioTokens.cardOutline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('操作来源', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final detail in details)
                _DetailBlock(label: detail.label, value: detail.value),
            ],
          ),
        ),
      ),
    );
  }
}

String _galleryOperationLabel(StudioGalleryOperation operation) {
  return switch (operation) {
    StudioGalleryOperation.generate => '生成',
    StudioGalleryOperation.imageToImage => '图生图',
    StudioGalleryOperation.enhance => _galleryActionEnhanceLabel,
    StudioGalleryOperation.upscale => _galleryActionUpscaleLabel,
    StudioGalleryOperation.inpaint => _galleryActionInpaintLabel,
    StudioGalleryOperation.directorTool => _galleryActionDirectorLabel,
  };
}

String _galleryRecordActionLabel(_GalleryRecordAction action) {
  return switch (action) {
    _GalleryRecordAction.restore => _galleryActionRestoreLabel,
    _GalleryRecordAction.useAsI2i => _galleryActionUseAsI2iLabel,
    _GalleryRecordAction.enhance => _galleryActionEnhanceLabel,
    _GalleryRecordAction.upscale => _galleryActionUpscaleLabel,
    _GalleryRecordAction.directorTool => _galleryActionDirectorLabel,
    _GalleryRecordAction.inpaint => _galleryActionInpaintLabel,
    _GalleryRecordAction.delete => _galleryActionDeleteLabel,
  };
}

IconData _galleryRecordActionIcon(_GalleryRecordAction action) {
  return switch (action) {
    _GalleryRecordAction.restore => Icons.keyboard_return,
    _GalleryRecordAction.useAsI2i => Icons.image_search_outlined,
    _GalleryRecordAction.enhance => Icons.auto_fix_high_outlined,
    _GalleryRecordAction.upscale => Icons.zoom_out_map_outlined,
    _GalleryRecordAction.directorTool => Icons.auto_awesome_motion_outlined,
    _GalleryRecordAction.inpaint => Icons.brush_outlined,
    _GalleryRecordAction.delete => Icons.delete_outline,
  };
}

List<_GalleryRecordAction> _galleryRecordActions({
  required bool hasExistingImage,
}) {
  if (!hasExistingImage) {
    return const [
      _GalleryRecordAction.restore,
      _GalleryRecordAction.delete,
    ];
  }
  return const [
    _GalleryRecordAction.restore,
    _GalleryRecordAction.useAsI2i,
    _GalleryRecordAction.enhance,
    _GalleryRecordAction.upscale,
    _GalleryRecordAction.directorTool,
    _GalleryRecordAction.inpaint,
    _GalleryRecordAction.delete,
  ];
}

String _stringifyLineageParameters(Map<String, dynamic> parameters) {
  final keys = parameters.keys.toList(growable: false)..sort();
  return [
    for (final key in keys)
      if (_stringifyMetadataValue(parameters[key]).isNotEmpty)
        '$key: ${_stringifyMetadataValue(parameters[key])}',
  ].join(', ');
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
        label: '元数据完整',
        icon: Icons.check_circle_outline,
        selected: true,
        accentColor: StudioTokens.active,
      );
    }

    return const StudioChip(
      label: '元数据缺失',
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
  late final StudioWheelZoomController _wheelZoom = StudioWheelZoomController(
    transformationController: _controller,
    minScale: _minScale,
    maxScale: _maxScale,
    requireControlModifier: true,
  );

  @override
  void didUpdateWidget(covariant _GalleryZoomableImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.record.id != widget.item.record.id) {
      _reset();
    }
  }

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
        final width = max(1.0, constraints.maxWidth);
        final height = max(1.0, constraints.maxHeight);
        final file = _existingImageFile(widget.item.record.imagePath);
        return Listener(
          key: const ValueKey('gallery-zoomable-image-viewer'),
          onPointerSignal: _wheelZoom.handlePointerSignal,
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
                              title: '图像无法读取',
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

  void _reset() {
    _wheelZoom.reset();
  }
}

class _GalleryPreviewPromptPanel extends StatelessWidget {
  final _GalleryDisplayItem item;
  final bool fullscreen;
  final StudioAssetCaptureHostState? assetCaptureHost;
  final VoidCallback? onUseAsI2iSource;
  final VoidCallback? onEnhance;
  final VoidCallback? onUpscale;
  final VoidCallback? onDirectorTool;
  final VoidCallback? onInpaint;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  const _GalleryPreviewPromptPanel({
    required this.item,
    required this.fullscreen,
    required this.assetCaptureHost,
    this.onUseAsI2iSource,
    this.onEnhance,
    this.onUpscale,
    this.onDirectorTool,
    this.onInpaint,
    this.onRestore,
    this.onDelete,
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
    final hasActions = onUseAsI2iSource != null ||
        onEnhance != null ||
        onUpscale != null ||
        onDirectorTool != null ||
        onInpaint != null ||
        onRestore != null ||
        onDelete != null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasActions) ...[
          _GalleryPreviewActionStrip(
            onUseAsI2iSource: onUseAsI2iSource,
            onEnhance: onEnhance,
            onUpscale: onUpscale,
            onDirectorTool: onDirectorTool,
            onInpaint: onInpaint,
            onRestore: onRestore,
            onDelete: onDelete,
          ),
          const SizedBox(height: 10),
        ],
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
        _GalleryLineageBlock(
          key: ValueKey('gallery-preview-lineage-${item.record.id}'),
          lineage: item.record.lineage,
          dense: true,
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

class _GalleryPreviewActionStrip extends StatelessWidget {
  final VoidCallback? onUseAsI2iSource;
  final VoidCallback? onEnhance;
  final VoidCallback? onUpscale;
  final VoidCallback? onDirectorTool;
  final VoidCallback? onInpaint;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  const _GalleryPreviewActionStrip({
    required this.onUseAsI2iSource,
    required this.onEnhance,
    required this.onUpscale,
    required this.onDirectorTool,
    required this.onInpaint,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onUseAsI2iSource != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-use-as-i2i'),
          onPressed: onUseAsI2iSource,
          icon: const Icon(Icons.image_search_outlined),
          label: _galleryActionUseAsI2iLabel,
          tone: _GalleryPreviewActionTone.primary,
        ),
      if (onEnhance != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-enhance'),
          onPressed: onEnhance,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: _galleryActionEnhanceLabel,
          tone: _GalleryPreviewActionTone.primary,
        ),
      if (onUpscale != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-upscale'),
          onPressed: onUpscale,
          icon: const Icon(Icons.zoom_out_map_outlined),
          label: _galleryActionUpscaleLabel,
        ),
      if (onDirectorTool != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-director'),
          onPressed: onDirectorTool,
          icon: const Icon(Icons.auto_awesome_motion_outlined),
          label: _galleryActionDirectorLabel,
        ),
      if (onInpaint != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-inpaint'),
          onPressed: onInpaint,
          icon: const Icon(Icons.brush_outlined),
          label: _galleryActionInpaintLabel,
        ),
      if (onRestore != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-restore'),
          onPressed: onRestore,
          icon: const Icon(Icons.keyboard_return),
          label: _galleryActionRestoreLabel,
          tone: _GalleryPreviewActionTone.primary,
        ),
      if (onDelete != null)
        _GalleryPreviewExpandingActionButton(
          key: const ValueKey('gallery-preview-delete'),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          label: _galleryActionDeleteLabel,
          tone: _GalleryPreviewActionTone.danger,
        ),
    ];

    return Wrap(
      key: const ValueKey('gallery-preview-actions'),
      spacing: 8,
      runSpacing: 8,
      children: actions,
    );
  }
}

enum _GalleryPreviewActionTone { primary, secondary, danger }

class _GalleryPreviewExpandingActionButton extends StatefulWidget {
  final Key? actionKey;
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final _GalleryPreviewActionTone tone;

  const _GalleryPreviewExpandingActionButton({
    Key? key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.tone = _GalleryPreviewActionTone.secondary,
  })  : actionKey = key,
        super(key: null);

  @override
  State<_GalleryPreviewExpandingActionButton> createState() =>
      _GalleryPreviewExpandingActionButtonState();
}

class _GalleryPreviewExpandingActionButtonState
    extends State<_GalleryPreviewExpandingActionButton> {
  bool _hovered = false;
  bool _focused = false;

  bool get _expanded => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _GalleryPreviewActionColors.forTone(widget.tone);
    final expandedWidth = _expandedWidth(widget.label);
    final foreground =
        widget.onPressed == null ? StudioTokens.textMuted : colors.foreground;

    final button = MouseRegion(
      onEnter: widget.onPressed == null
          ? null
          : (_) => setState(() {
                _hovered = true;
              }),
      onExit: widget.onPressed == null
          ? null
          : (_) => setState(() {
                _hovered = false;
              }),
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        onShowFocusHighlight: (value) => setState(() {
          _focused = value;
        }),
        child: AnimatedContainer(
          key: widget.actionKey,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: _expanded ? expandedWidth : 44,
          height: 40,
          decoration: ShapeDecoration(
            color:
                widget.onPressed == null ? StudioTokens.surface2 : colors.fill,
            shape: StadiumBorder(side: BorderSide(color: colors.border)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showLabel = _expanded && constraints.maxWidth >= 82;
                return InkWell(
                  onTap: widget.onPressed,
                  customBorder: const StadiumBorder(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: showLabel ? 14 : 0,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize:
                            showLabel ? MainAxisSize.max : MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconTheme(
                            data: IconThemeData(size: 18, color: foreground),
                            child: widget.icon,
                          ),
                          if (showLabel) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return _expanded ? button : Tooltip(message: widget.label, child: button);
  }

  double _expandedWidth(String label) {
    return (72 + label.length * 14).clamp(96, 168).toDouble();
  }
}

class _GalleryPreviewActionColors {
  final Color fill;
  final Color border;
  final Color foreground;

  const _GalleryPreviewActionColors({
    required this.fill,
    required this.border,
    required this.foreground,
  });

  factory _GalleryPreviewActionColors.forTone(_GalleryPreviewActionTone tone) {
    return switch (tone) {
      _GalleryPreviewActionTone.primary => const _GalleryPreviewActionColors(
          fill: StudioTokens.primary,
          border: StudioTokens.primary,
          foreground: StudioTokens.onPrimary,
        ),
      _GalleryPreviewActionTone.secondary => const _GalleryPreviewActionColors(
          fill: StudioTokens.surface2,
          border: StudioTokens.border,
          foreground: StudioTokens.textPrimary,
        ),
      _GalleryPreviewActionTone.danger => const _GalleryPreviewActionColors(
          fill: StudioTokens.surface2,
          border: StudioTokens.danger,
          foreground: StudioTokens.danger,
        ),
    };
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
    final title = record.title.trim().isEmpty ? '未命名记录' : record.title;
    final summary =
        record.info.trim().isEmpty ? '这条记录没有保存提示词预览。' : record.info.trim();
    final createdLabel = _formatTimestamp(record.createdAt);
    final footerParts = <String>[
      createdLabel,
      metadataEntries.isEmpty ? '元数据缺失' : '元数据 ${metadataEntries.length} 项',
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

  bool get hasExistingImage => _existingImageFile(record.imagePath) != null;

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
