import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_wheel_zoom.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';

typedef ScriptExhibitionSendHandler = FutureOr<void> Function(
  ScriptExhibitionFocus focus,
);
typedef ScriptExhibitionQuickRerunHandler = FutureOr<void> Function(
  ScriptExhibitionFocus focus,
);
typedef _ScriptExhibitionItemDeleteHandler = Future<bool> Function(
  BuildContext context,
  ScriptExhibitionItem item,
);
typedef _ScriptExhibitionScriptAction = Future<void> Function(
  ScriptExhibitionScript script,
);

class ScriptExhibitionRoomPage extends StatefulWidget {
  final ScriptExhibitionRoomViewModel viewModel;
  final ScriptExhibitionSendHandler onSendToScriptWorkbench;
  final ValueChanged<ScriptExhibitionFocus> onSendToWorkbench;
  final ScriptExhibitionQuickRerunHandler? onQuickRerunProductionTask;
  final ValueChanged<ScriptExhibitionFocus>? onOpenProductionTask;
  final bool deferInitialLoad;

  const ScriptExhibitionRoomPage({
    super.key,
    required this.viewModel,
    required this.onSendToScriptWorkbench,
    required this.onSendToWorkbench,
    this.onQuickRerunProductionTask,
    this.onOpenProductionTask,
    this.deferInitialLoad = false,
  });

  @override
  State<ScriptExhibitionRoomPage> createState() =>
      _ScriptExhibitionRoomPageState();
}

class _ScriptExhibitionRoomPageState extends State<ScriptExhibitionRoomPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalObjectKey> _focusedItemKeys = {};
  String? _lastScheduledFocusItemId;
  String? _pendingScriptWorkbenchId;
  String? _organizingScriptImagesScriptId;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_scheduleFocusedItemScroll);
    if (!widget.deferInitialLoad) {
      unawaited(widget.viewModel.ensureLoaded());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.viewModel.ensureLoaded());
    });
  }

  Future<void> _sendToScriptWorkbench(ScriptExhibitionFocus focus) async {
    if (!focus.canOpenWorkbench || _pendingScriptWorkbenchId != null) {
      return;
    }
    setState(() {
      _pendingScriptWorkbenchId = focus.scriptId;
    });
    try {
      await widget.onSendToScriptWorkbench(focus);
    } catch (error, stackTrace) {
      debugPrint('Script exhibition handoff failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted && _pendingScriptWorkbenchId == focus.scriptId) {
        setState(() {
          _pendingScriptWorkbenchId = null;
        });
      }
    }
  }

  @override
  void didUpdateWidget(ScriptExhibitionRoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) return;
    oldWidget.viewModel.removeListener(_scheduleFocusedItemScroll);
    widget.viewModel.addListener(_scheduleFocusedItemScroll);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_scheduleFocusedItemScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildSliverScrollView(context);
    return Material(
      key: const ValueKey('script-exhibition-room-page'),
      type: MaterialType.canvas,
      color: StudioTokens.surfaceBase,
      child: ListenableBuilder(
        listenable: widget.viewModel,
        child: content,
        builder: (context, _) {
          final viewModel = widget.viewModel;
          if (viewModel.isLoading && viewModel.snapshot.scripts.isEmpty) {
            return const SingleChildScrollView(
              padding: EdgeInsets.all(StudioTokens.pagePadding),
              child: _StatusPanel(
                icon: Icons.hourglass_empty_outlined,
                title: '正在整理剧本展览室',
                subtitle: '收纳原始剧本、批量产线和画廊记录中。',
              ),
            );
          }
          if (viewModel.loadError != null) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(StudioTokens.pagePadding),
              child: _StatusPanel(
                icon: Icons.error_outline,
                title: '剧本展览室暂时不可用',
                subtitle: viewModel.loadError.toString(),
                onRetry: viewModel.load,
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildSliverScrollView(BuildContext context) {
    final viewModel = widget.viewModel;
    const pagePadding = StudioTokens.pagePadding;
    return CustomScrollView(
      key: const ValueKey('script-exhibition-scroll-view'),
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            pagePadding,
            pagePadding,
            pagePadding,
            0,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _Header(
                onRefresh: viewModel.load,
                onImport: viewModel.canImportScripts
                    ? () => _importScript(context)
                    : null,
              ),
              const SizedBox(height: 14),
              ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) {
                  return _Metrics(
                    snapshot: viewModel.snapshot,
                    onNeedsActionPressed:
                        viewModel.snapshot.needsActionCount > 0
                            ? viewModel.jumpToFirstNeedsAction
                            : null,
                  );
                },
              ),
              const SizedBox(height: 14),
            ]),
          ),
        ),
        _buildCategoryHeaderSliver(context),
        _buildShelfSortSliver(),
        _buildShelfSliver(context),
        _buildDetailHeaderSliver(context),
        _buildDetailBoardSliver(context),
      ],
    );
  }

  Widget _buildCategoryHeaderSliver(BuildContext context) {
    final viewModel = widget.viewModel;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedCategoryStripDelegate(
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) {
            return _CategoryStrip(
              viewModel: viewModel,
              onAddCategory: viewModel.canCategorizeScripts
                  ? () => _createCategory(context)
                  : null,
              onScriptsDropped: viewModel.canCategorizeScripts
                  ? (scripts, category) =>
                      _assignScriptsToCategory(scripts, category)
                  : null,
              onDeleteCategory: (category) =>
                  _confirmDeleteCategory(context, category),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShelfSortSliver() {
    const pagePadding = StudioTokens.pagePadding;
    final viewModel = widget.viewModel;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.selectedScript != null ||
            viewModel.snapshot.scripts.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            pagePadding,
            12,
            pagePadding,
            18,
          ),
          sliver: SliverToBoxAdapter(
            child: _SortToolbar(
              title: '剧本排序',
              menu: _ScriptSortMenu(
                value: viewModel.scriptSort,
                onSelected: viewModel.selectScriptSort,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShelfSliver(BuildContext context) {
    const pagePadding = StudioTokens.pagePadding;
    final viewModel = widget.viewModel;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.snapshot.scripts.isEmpty) {
          return const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pagePadding,
              0,
              pagePadding,
              pagePadding,
            ),
            sliver: SliverToBoxAdapter(
              child: _StatusPanel(
                icon: Icons.auto_stories_outlined,
                title: '还没有可展览的剧本',
                subtitle: '导入剧本或跑完批量产线后，这里会自动形成剧本馆区。',
              ),
            ),
          );
        }
        if (viewModel.selectedScript != null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverToBoxAdapter(
          child: _ScriptShelf(
            contentPadding: const EdgeInsets.fromLTRB(
              pagePadding,
              0,
              pagePadding,
              pagePadding,
            ),
            scripts: viewModel.visibleScripts,
            query: viewModel.scriptSearchQuery,
            selectedScriptIds: viewModel.selectedScriptIds,
            onSelect: viewModel.selectScript,
            onSelectionChanged: viewModel.replaceShelfSelection,
            onQueryChanged: viewModel.updateScriptSearchQuery,
            onSend: _sendToScriptWorkbench,
            pendingScriptWorkbenchId: _pendingScriptWorkbenchId,
            onDelete: viewModel.canDeleteScripts ||
                    viewModel.canRemoveScriptCategories
                ? (script) => _confirmDeleteScript(context, script)
                : null,
            scrollController: _scrollController,
            canDeleteScript: _canUseScriptDeleteAction,
            deleteTooltipForScript: _deleteScriptActionTooltip,
            deleteIconForScript: _deleteScriptActionIcon,
            onRename: viewModel.canRenameScripts
                ? (script) => _renameScript(context, script)
                : null,
            onAssignCategory: viewModel.canCategorizeScripts
                ? (script) => _assignScriptCategory(context, script)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDetailHeaderSliver(BuildContext context) {
    const pagePadding = StudioTokens.pagePadding;
    final viewModel = widget.viewModel;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final selectedScript = viewModel.selectedScript;
        final selectedVersion =
            selectedScript == null ? null : viewModel.selectedVersion;
        if (selectedScript == null || selectedVersion == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return PinnedHeaderSliver(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: StudioTokens.surfaceBase,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                pagePadding,
                0,
                pagePadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ScriptDetailHeader(
                    script: selectedScript,
                    selectedVersion: selectedVersion,
                    selectedVersionIds: viewModel.selectedVersionIds,
                    selectedVersions: viewModel.selectedVersions,
                    detailFilters: viewModel.detailFilters,
                    selectedDetailFilterId: viewModel.selectedDetailFilterId,
                    onBack: viewModel.clearScriptSelection,
                    onVersionSelected: viewModel.selectVersion,
                    onVersionSelectionToggled: viewModel.toggleVersionSelection,
                    onClearVersionSelection: viewModel.clearVersionSelection,
                    onDetailFilterSelected: viewModel.selectDetailFilter,
                    onSend: _sendToScriptWorkbench,
                    pendingScriptWorkbenchId: _pendingScriptWorkbenchId,
                    onOpenProductionTask: widget.onOpenProductionTask,
                    onDeleteScript: _canUseScriptDeleteAction(selectedScript)
                        ? (script) => _confirmDeleteScript(context, script)
                        : null,
                    deleteTooltip: _deleteScriptActionTooltip(selectedScript),
                    deleteIcon: _deleteScriptActionIcon(selectedScript),
                    onRenameScript: viewModel.canRenameScripts
                        ? (script) => _renameScript(context, script)
                        : null,
                    onRenameVersion: viewModel.canRenameVersions
                        ? (script, version) =>
                            _renameVersion(context, script, version)
                        : null,
                    canDeleteVersion: viewModel.canDeleteVersion,
                    onDeleteVersion: viewModel.canDeleteVersions
                        ? (script, version) =>
                            _confirmDeleteVersion(context, script, version)
                        : null,
                    onDeleteSelectedVersions: viewModel.canDeleteVersions
                        ? (script, versions) =>
                            _confirmDeleteVersions(context, script, versions)
                        : null,
                    onImportImages: viewModel.canImportScriptImages
                        ? (script) => _importImagesForScript(context, script)
                        : null,
                    onOpenSourceFolder: (script) =>
                        _openSourceFolder(context, script),
                    onOrganizeScriptImages: (script) =>
                        _confirmOrganizeScriptImages(context, script),
                    organizingScriptImagesScriptId:
                        _organizingScriptImagesScriptId,
                  ),
                  const SizedBox(height: 12),
                  _SortToolbar(
                    title: '图片排序',
                    menu: _ItemSortMenu(
                      value: viewModel.itemSort,
                      onSelected: viewModel.selectItemSort,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailBoardSliver(BuildContext context) {
    const pagePadding = StudioTokens.pagePadding;
    final viewModel = widget.viewModel;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final selectedScript = viewModel.selectedScript;
        if (selectedScript == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        if (selectedScript.summaryOnly) {
          final isLoading = viewModel.isSelectedScriptDetailLoading;
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              pagePadding,
              12,
              pagePadding,
              pagePadding,
            ),
            sliver: SliverToBoxAdapter(
              child: _StatusPanel(
                key: const ValueKey(
                  'script-exhibition-detail-loading-status',
                ),
                icon: isLoading
                    ? Icons.hourglass_empty_outlined
                    : Icons.error_outline,
                title: isLoading ? '正在加载完整剧本' : '完整剧本尚未加载',
                subtitle:
                    isLoading ? '正在读取全部图片与版本，请稍候。' : '摘要封面已显示，但完整内容读取失败，可以重试。',
                onRetry: isLoading ? null : viewModel.retrySelectedScriptDetail,
              ),
            ),
          );
        }
        final focusedItemId = viewModel.focusedItemId;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            pagePadding,
            12,
            pagePadding,
            pagePadding,
          ),
          sliver: _SliverWaterfallBoard(
            items: viewModel.visibleVersionItems,
            focusedItemId: focusedItemId,
            focusedItemKey:
                focusedItemId == null ? null : _focusedItemKey(focusedItemId),
            scrollController: _scrollController,
            onQuickRerunProductionTask: widget.onQuickRerunProductionTask,
            onOpenProductionTask: widget.onOpenProductionTask,
            loadGenerationParams: viewModel.loadGenerationParamsForItem,
            onDelete: viewModel.canDeleteItems
                ? (deleteContext, item) =>
                    _confirmDeleteItem(deleteContext, item)
                : null,
            onRename: viewModel.canRenameItems
                ? (item) => _renameItem(context, item)
                : null,
            onSetCover: viewModel.canSetCoverItems
                ? (item) => _setCoverItem(context, item)
                : null,
          ),
        );
      },
    );
  }

  void _scheduleFocusedItemScroll() {
    final itemId = widget.viewModel.focusedItemId;
    if (itemId == null || itemId == _lastScheduledFocusItemId) return;
    _lastScheduledFocusItemId = itemId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToFocusedItem(itemId));
    });
  }

  Future<void> _scrollToFocusedItem(String itemId) async {
    if (!_scrollController.hasClients) return;
    final focusedContext = _focusedItemKey(itemId).currentContext;
    if (focusedContext != null) {
      await Scrollable.ensureVisible(
        focusedContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
      return;
    }

    final items = widget.viewModel.visibleVersionItems;
    final index = items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    final viewportWidth =
        context.size?.width ?? MediaQuery.sizeOf(context).width;
    final boardWidth = max(320.0, viewportWidth - StudioTokens.pagePadding * 2);
    final columns = max(1, boardWidth ~/ 320);
    var estimatedOffset = 430.0;
    for (var rowStart = 0; rowStart < index; rowStart += columns) {
      final rowEnd = min(rowStart + columns, items.length);
      final rowHeight = items
          .sublist(rowStart, rowEnd)
          .map(_estimatedWaterfallCardHeight)
          .fold<double>(0, max);
      estimatedOffset += rowHeight + 12;
    }
    final target = estimatedOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  GlobalObjectKey _focusedItemKey(String itemId) {
    return _focusedItemKeys.putIfAbsent(
      itemId,
      () => GlobalObjectKey('script-exhibition-focused-item-$itemId'),
    );
  }

  Future<void> _confirmDeleteScript(
    BuildContext context,
    ScriptExhibitionScript script,
  ) async {
    final selectedCategoryName =
        widget.viewModel.selectedCategoryNameForScript(script);
    if (selectedCategoryName != null) {
      if (!widget.viewModel.canRemoveScriptFromSelectedCategory(script)) {
        return;
      }
      final confirmed = await _showDeleteDialog(
        context: context,
        title: '从当前分类移除',
        message:
            '只会把“${script.title}”从“$selectedCategoryName”分类中移除；不会删除剧本、图片、批量结果或原始目录。',
        confirmKey:
            const ValueKey('script-exhibition-confirm-remove-script-category'),
        confirmLabel: '移除',
      );
      if (!confirmed || !mounted) return;
      await widget.viewModel.removeScriptFromSelectedCategory(script);
      return;
    }

    final result = await _showScriptDeleteDialog(
      context: context,
      title: '删除剧本展览记录',
      message: '会移除展览室中保存的剧本记录、批量产线任务和画廊收纳记录；不会删除原始剧本目录。',
      confirmKey: const ValueKey('script-exhibition-confirm-delete-script'),
    );
    if (!result.confirmed || !mounted) return;
    await widget.viewModel.deleteScript(
      script,
      deleteLocalFiles: result.deleteLocalFiles,
    );
  }

  String _deleteScriptActionTooltip(ScriptExhibitionScript script) {
    return widget.viewModel.canRemoveScriptFromSelectedCategory(script)
        ? '从当前分类移除'
        : '删除展览记录';
  }

  IconData _deleteScriptActionIcon(ScriptExhibitionScript script) {
    return widget.viewModel.canRemoveScriptFromSelectedCategory(script)
        ? Icons.remove_circle_outline
        : Icons.delete_outline;
  }

  bool _canUseScriptDeleteAction(ScriptExhibitionScript script) {
    if (widget.viewModel.selectedCategoryNameForScript(script) != null) {
      return widget.viewModel.canRemoveScriptFromSelectedCategory(script);
    }
    return widget.viewModel.canDeleteScripts ||
        widget.viewModel.canRemoveScriptFromSelectedCategory(script);
  }

  Future<bool> _confirmDeleteItem(
    BuildContext context,
    ScriptExhibitionItem item,
  ) async {
    final result = await _showScriptDeleteDialog(
      context: context,
      title: '删除展览图片',
      message: '会从展览室移除这条批量产线任务或画廊收纳记录；不会删除原始剧本文件。',
      confirmKey: const ValueKey('script-exhibition-confirm-delete-item'),
      localFilesKey: const ValueKey(
        'script-exhibition-delete-item-local-files',
      ),
      confirmLabel: '鍒犻櫎鍥剧墖',
    );
    if (!result.confirmed || !mounted) return false;
    await widget.viewModel.deleteItem(
      item,
      deleteLocalFiles: result.deleteLocalFiles,
    );
    return true;
  }

  Future<void> _confirmDeleteVersion(
    BuildContext context,
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  ) async {
    if (!widget.viewModel.canDeleteVersion(script, version)) return;
    final result = await _showScriptDeleteDialog(
      context: context,
      title: '删除版本',
      message:
          '会移除“${script.title}”里的“${version.label}”版本；可选择同时删除该版本的本地图片文件。不会删除整条剧本展览记录或原始剧本目录。',
      confirmKey: const ValueKey('script-exhibition-confirm-delete-version'),
      localFilesKey: const ValueKey(
        'script-exhibition-delete-version-local-files',
      ),
      confirmLabel: '删除版本',
    );
    if (!result.confirmed || !mounted) return;
    await widget.viewModel.deleteVersion(
      script,
      version,
      deleteLocalFiles: result.deleteLocalFiles,
    );
  }

  Future<void> _confirmDeleteVersions(
    BuildContext context,
    ScriptExhibitionScript script,
    List<ScriptExhibitionVersion> versions,
  ) async {
    final deletableVersions = [
      for (final version in versions)
        if (widget.viewModel.canDeleteVersion(script, version)) version,
    ];
    if (deletableVersions.isEmpty) return;
    final labels = deletableVersions.map((version) => '“${version.label}”');
    final result = await _showScriptDeleteDialog(
      context: context,
      title: '批量删除版本',
      message:
          '将删除 ${deletableVersions.length} 个版本：${labels.join('、')}。可选择同时删除这些版本的本地图片文件。不会删除整条剧本展览记录或原始剧本目录。',
      confirmKey: const ValueKey(
        'script-exhibition-confirm-delete-selected-versions',
      ),
      localFilesKey: const ValueKey(
        'script-exhibition-delete-selected-versions-local-files',
      ),
      confirmLabel: '删除所选版本',
    );
    if (!result.confirmed || !mounted) return;
    await widget.viewModel.deleteVersions(
      script,
      deletableVersions,
      deleteLocalFiles: result.deleteLocalFiles,
    );
  }

  Future<void> _openSourceFolder(
    BuildContext context,
    ScriptExhibitionScript script,
  ) async {
    final sourceFolder = script.sourceFolder.trim();
    if (sourceFolder.isEmpty) {
      _showSnackBar(context, '这个剧本没有记录源图目录。');
      return;
    }
    try {
      await FileService().openDirectoryInFileManager(sourceFolder);
    } catch (error) {
      if (!mounted || !context.mounted) return;
      _showSnackBar(context, '无法打开源图目录：$error');
    }
  }

  Future<void> _confirmOrganizeScriptImages(
    BuildContext context,
    ScriptExhibitionScript script,
  ) async {
    if (_organizingScriptImagesScriptId != null) {
      return;
    }
    setState(() {
      _organizingScriptImagesScriptId = script.scriptId;
    });
    try {
      final preview =
          await widget.viewModel.previewScriptImageOrganization(script);
      if (!mounted || !context.mounted) return;
      if (preview.moves.isEmpty && preview.orphanImagePaths.isEmpty) {
        _showSnackBar(context, '没有需要整理的剧本展览室生成图片。');
        return;
      }
      final confirmed = await _showScriptImageOrganizationDialog(
        context: context,
        preview: preview,
      );
      if (!confirmed || !mounted || !context.mounted) return;
      final result = await widget.viewModel.organizeScriptImages(
        script,
        preview: preview,
      );
      if (!mounted || !context.mounted) return;
      final failedText = result.failedImagePaths.isEmpty
          ? ''
          : '，${result.failedImagePaths.length} 个文件失败';
      _showSnackBar(
        context,
        '已整理 ${result.movedImagePaths.length} 张剧本展览室生成图片，删除 ${result.deletedOrphanImagePaths.length} 张孤儿图片$failedText。',
      );
    } catch (error) {
      if (!mounted || !context.mounted) return;
      _showSnackBar(context, '整理剧本展览室生成图片失败：$error');
    } finally {
      if (mounted && _organizingScriptImagesScriptId == script.scriptId) {
        setState(() {
          _organizingScriptImagesScriptId = null;
        });
      }
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final scaffold = Scaffold.maybeOf(context);
    if (messenger == null || scaffold == null) {
      debugPrint(message);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _renameScript(
    BuildContext context,
    ScriptExhibitionScript script,
  ) async {
    final label = await _showRenameDialog(
      context: context,
      initialLabel: script.title,
      title: '重命名剧本',
      confirmKey: const ValueKey('script-exhibition-confirm-rename-script'),
    );
    if (label == null || !mounted) return;
    await widget.viewModel.renameScript(script, label);
  }

  Future<void> _assignScriptCategory(
    BuildContext context,
    ScriptExhibitionScript script,
  ) async {
    final categoryName = await _showCategoryDialog(
      context: context,
      categories: widget.viewModel.categories
          .where(widget.viewModel.canAssignCategory)
          .toList(growable: false),
      title: '归入分类',
    );
    if (categoryName == null || !mounted) return;
    await widget.viewModel.assignScriptToCategory(script, categoryName);
  }

  Future<void> _createCategory(BuildContext context) async {
    final categoryName = await _showCategoryDialog(
      context: context,
      categories: widget.viewModel.categories
          .where(widget.viewModel.canAssignCategory)
          .toList(growable: false),
      title: '新建剧本分类',
    );
    if (categoryName == null || !mounted) return;
    await widget.viewModel.createCategory(categoryName);
  }

  Future<void> _assignScriptsToCategory(
    List<ScriptExhibitionScript> scripts,
    ScriptExhibitionCategory category,
  ) async {
    if (scripts.isEmpty) return;
    try {
      await widget.viewModel.assignScriptsToCategory(scripts, category.title);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('归入分类失败：$error')),
      );
    }
  }

  Future<void> _confirmDeleteCategory(
    BuildContext context,
    ScriptExhibitionCategory category,
  ) async {
    if (!widget.viewModel.canDeleteCategory(category)) return;
    final confirmed = await _showDeleteDialog(
      context: context,
      title: '删除分类',
      message: '只会移除“${category.title}”这个分类标签，不会删除任何剧本、图片或批量结果。',
      confirmKey: const ValueKey('script-exhibition-confirm-delete-category'),
    );
    if (!confirmed || !mounted) return;
    await widget.viewModel.deleteCategory(category);
  }

  Future<void> _renameItem(
    BuildContext context,
    ScriptExhibitionItem item,
  ) async {
    final label = await _showRenameDialog(
      context: context,
      initialLabel: item.title,
    );
    if (label == null || !mounted) return;
    await widget.viewModel.renameItem(item, label);
  }

  Future<void> _setCoverItem(
    BuildContext context,
    ScriptExhibitionItem item,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final scaffold = Scaffold.maybeOf(context);
    await widget.viewModel.setCoverItem(item);
    if (!mounted) return;
    if (messenger != null && scaffold != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('已设为当前剧本封面')),
      );
    }
  }

  Future<void> _renameVersion(
    BuildContext context,
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  ) async {
    final label = await _showRenameDialog(
      context: context,
      initialLabel: version.label,
      title: '重命名版本',
      confirmKey: const ValueKey('script-exhibition-confirm-rename-version'),
    );
    if (label == null || !mounted) return;
    await widget.viewModel.renameVersionLabel(script, version, label);
  }

  Future<void> _importScript(BuildContext context) async {
    try {
      await widget.viewModel.importScript();
    } catch (error, stackTrace) {
      debugPrint('Script exhibition import failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || !context.mounted) return;
      _showSnackBar(context, '导入剧本失败：$error');
    }
  }

  Future<void> _importImagesForScript(
    BuildContext context,
    ScriptExhibitionScript script,
  ) async {
    try {
      await widget.viewModel.importImagesForScript(script);
    } catch (error, stackTrace) {
      debugPrint('Script exhibition image import failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || !context.mounted) return;
      _showSnackBar(context, '导入图片失败：$error');
    }
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  final Future<void> Function()? onImport;

  const _Header({required this.onRefresh, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      key: const ValueKey('script-exhibition-header'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: StudioTokens.primary,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(
              Icons.auto_stories_outlined,
              color: StudioTokens.onPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '剧本展览室',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '按剧本收纳原始帧、批量跑图结果和单帧重跑版本，像图书馆一样回看每次创作。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: StudioTokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: '刷新',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey('script-exhibition-import-script'),
            onPressed: onImport == null ? null : () => unawaited(onImport!()),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('导入剧本'),
          ),
        ],
      ),
    );
  }
}

class _SortToolbar extends StatelessWidget {
  final String title;
  final Widget menu;

  const _SortToolbar({required this.title, required this.menu});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.sort, size: 18, color: StudioTokens.textMuted),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.textSecondary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const Spacer(),
        menu,
      ],
    );
  }
}

class _ScriptSortMenu extends StatelessWidget {
  final ScriptExhibitionScriptSort value;
  final ValueChanged<ScriptExhibitionScriptSort> onSelected;

  const _ScriptSortMenu({
    required this.value,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ScriptExhibitionScriptSort>(
      key: const ValueKey('script-exhibition-script-sort-menu'),
      tooltip: '剧本排序',
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        _scriptSortItem(ScriptExhibitionScriptSort.recent),
        _scriptSortItem(ScriptExhibitionScriptSort.title),
        _scriptSortItem(ScriptExhibitionScriptSort.imageCount),
        _scriptSortItem(ScriptExhibitionScriptSort.needsAction),
        _scriptSortItem(ScriptExhibitionScriptSort.unbatchedFirst),
      ],
      child: _SortMenuButton(label: _scriptSortLabel(value)),
    );
  }

  PopupMenuEntry<ScriptExhibitionScriptSort> _scriptSortItem(
    ScriptExhibitionScriptSort sort,
  ) {
    return PopupMenuItem<ScriptExhibitionScriptSort>(
      key: ValueKey('script-exhibition-script-sort-${sort.name}'),
      value: sort,
      child: Text(_scriptSortLabel(sort)),
    );
  }
}

class _ItemSortMenu extends StatelessWidget {
  final ScriptExhibitionItemSort value;
  final ValueChanged<ScriptExhibitionItemSort> onSelected;

  const _ItemSortMenu({
    required this.value,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ScriptExhibitionItemSort>(
      key: const ValueKey('script-exhibition-item-sort-menu'),
      tooltip: '图片排序',
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        _itemSortItem(ScriptExhibitionItemSort.frame),
        _itemSortItem(ScriptExhibitionItemSort.recent),
        _itemSortItem(ScriptExhibitionItemSort.oldest),
      ],
      child: _SortMenuButton(label: _itemSortLabel(value)),
    );
  }

  PopupMenuEntry<ScriptExhibitionItemSort> _itemSortItem(
    ScriptExhibitionItemSort sort,
  ) {
    return PopupMenuItem<ScriptExhibitionItemSort>(
      key: ValueKey('script-exhibition-item-sort-${sort.name}'),
      value: sort,
      child: Text(_itemSortLabel(sort)),
    );
  }
}

class _SortMenuButton extends StatelessWidget {
  final String label;

  const _SortMenuButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusPill,
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.expand_more,
              size: 18,
              color: StudioTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

String _scriptSortLabel(ScriptExhibitionScriptSort sort) {
  return switch (sort) {
    ScriptExhibitionScriptSort.recent => '最近更新',
    ScriptExhibitionScriptSort.title => '名称 A-Z',
    ScriptExhibitionScriptSort.imageCount => '图片数多到少',
    ScriptExhibitionScriptSort.needsAction => '需处理优先',
    ScriptExhibitionScriptSort.unbatchedFirst => '未批量生成优先',
  };
}

String _itemSortLabel(ScriptExhibitionItemSort sort) {
  return switch (sort) {
    ScriptExhibitionItemSort.frame => '帧号顺序',
    ScriptExhibitionItemSort.recent => '最近更新',
    ScriptExhibitionItemSort.oldest => '最早更新',
  };
}

class _Metrics extends StatelessWidget {
  final ScriptExhibitionSnapshot snapshot;
  final VoidCallback? onNeedsActionPressed;

  const _Metrics({required this.snapshot, required this.onNeedsActionPressed});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _MetricTile(
            key: const ValueKey('script-exhibition-metric-scripts'),
            label: '剧本',
            value: snapshot.totalScriptCount.toString(),
            icon: Icons.menu_book_outlined,
            accentColor: StudioTokens.primary,
          ),
          _MetricTile(
            key: const ValueKey('script-exhibition-metric-images'),
            label: '图片/帧',
            value: snapshot.totalImageCount.toString(),
            icon: Icons.photo_outlined,
            accentColor: StudioTokens.info,
          ),
          _MetricTile(
            key: const ValueKey('script-exhibition-metric-generated'),
            label: '新收纳',
            value: snapshot.generatedImageCount.toString(),
            icon: Icons.auto_awesome,
            accentColor: StudioTokens.active,
          ),
          _MetricTile(
            key: const ValueKey('script-exhibition-metric-needs-action'),
            label: '需处理',
            value: snapshot.needsActionCount.toString(),
            icon: Icons.report_problem_outlined,
            accentColor: StudioTokens.warning,
            onTap: onNeedsActionPressed,
          ),
        ];
        final width = constraints.maxWidth < 760
            ? constraints.maxWidth
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  const _MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final panel = StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: StudioTokens.radiusPill,
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.textMuted,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return panel;
    return Tooltip(
      message: '跳到第一个需处理项',
      child: Material(
        color: Colors.transparent,
        borderRadius: StudioTokens.radiusCard,
        child: InkWell(
          borderRadius: StudioTokens.radiusCard,
          onTap: onTap,
          child: panel,
        ),
      ),
    );
  }
}

const _categoryStripPinnedExtent = 128.0;
const _categoryStripPinnedBottomPadding = 12.0;

class _PinnedCategoryStripDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _PinnedCategoryStripDelegate({required this.child});

  @override
  double get minExtent => _categoryStripPinnedExtent;

  @override
  double get maxExtent => _categoryStripPinnedExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surfaceBase,
        boxShadow: shrinkOffset > 0 || overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : const [],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          StudioTokens.pagePadding,
          0,
          StudioTokens.pagePadding,
          _categoryStripPinnedBottomPadding,
        ),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedCategoryStripDelegate oldDelegate) {
    return true;
  }
}

class _CategoryStrip extends StatelessWidget {
  final ScriptExhibitionRoomViewModel viewModel;
  final VoidCallback? onAddCategory;
  final Future<void> Function(
    List<ScriptExhibitionScript> scripts,
    ScriptExhibitionCategory category,
  )? onScriptsDropped;
  final ValueChanged<ScriptExhibitionCategory> onDeleteCategory;

  const _CategoryStrip({
    required this.viewModel,
    required this.onAddCategory,
    required this.onScriptsDropped,
    required this.onDeleteCategory,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final categories = viewModel.categories;
        final canFill =
            constraints.maxWidth >= categories.length * 260 + 12 * 3;
        if (canFill) {
          return Row(
            children: [
              for (final (index, category) in categories.indexed) ...[
                Expanded(
                  child: _CategoryCard(
                    category: category,
                    selected: category.id == viewModel.selectedCategoryId,
                    onTap: () => viewModel.selectCategory(category.id),
                    onScriptsDropped: viewModel.canAssignCategory(category)
                        ? (scripts) async {
                            await onScriptsDropped?.call(scripts, category);
                          }
                        : null,
                    onDelete: viewModel.canDeleteCategory(category)
                        ? () => onDeleteCategory(category)
                        : null,
                    fillWidth: true,
                  ),
                ),
                if (index != categories.length - 1) const SizedBox(width: 12),
              ],
              if (onAddCategory != null) ...[
                const SizedBox(width: 12),
                _AddCategoryButton(onPressed: onAddCategory!),
              ],
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, category) in categories.indexed) ...[
                _CategoryCard(
                  category: category,
                  selected: category.id == viewModel.selectedCategoryId,
                  onTap: () => viewModel.selectCategory(category.id),
                  onScriptsDropped: viewModel.canAssignCategory(category)
                      ? (scripts) async {
                          await onScriptsDropped?.call(scripts, category);
                        }
                      : null,
                  onDelete: viewModel.canDeleteCategory(category)
                      ? () => onDeleteCategory(category)
                      : null,
                ),
                if (index != categories.length - 1) const SizedBox(width: 12),
              ],
              if (onAddCategory != null) ...[
                const SizedBox(width: 12),
                _AddCategoryButton(onPressed: onAddCategory!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AddCategoryButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddCategoryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 92,
      child: OutlinedButton.icon(
        key: const ValueKey('script-exhibition-add-category'),
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: const Text('新建分类'),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ScriptExhibitionCategory category;
  final bool selected;
  final VoidCallback onTap;
  final Future<void> Function(List<ScriptExhibitionScript> scripts)?
      onScriptsDropped;
  final VoidCallback? onDelete;
  final bool fillWidth;

  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.onScriptsDropped,
    required this.onDelete,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<List<ScriptExhibitionScript>>(
      onWillAcceptWithDetails: (details) =>
          onScriptsDropped != null && details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        final dropHandler = onScriptsDropped;
        if (dropHandler == null) return;
        unawaited(dropHandler(details.data));
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        final borderColor = highlighted || selected
            ? StudioTokens.primary
            : StudioTokens.cardOutline;
        final borderWidth = highlighted ? 2.0 : (selected ? 1.4 : 1.0);
        Widget card = Material(
          key: ValueKey('script-exhibition-category-${category.id}'),
          color: highlighted ? StudioTokens.surface3 : StudioTokens.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: StudioTokens.radiusCard,
            side: BorderSide(color: borderColor, width: borderWidth),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: fillWidth ? double.infinity : 288,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      bottom: -14,
                      child: Text(
                        category.count.toString().padLeft(2, '0'),
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(
                              color:
                                  StudioTokens.primary.withValues(alpha: 0.12),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                category.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: StudioTokens.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            if (onScriptsDropped != null) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.input_outlined,
                                size: 18,
                                color: StudioTokens.textMuted,
                              ),
                            ],
                            const SizedBox(width: 8),
                            Text(
                              category.count.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: StudioTokens.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          category.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: StudioTokens.textMuted,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in category.tags)
                              StudioChip(label: tag),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (onDelete == null) {
          return card;
        }
        return GestureDetector(
          onSecondaryTapDown: (details) => _showCategoryContextMenu(
            context,
            details.globalPosition,
            onDelete: onDelete!,
          ),
          child: card,
        );
      },
    );
  }
}

enum _CategoryContextAction { delete }

Future<void> _showCategoryContextMenu(
  BuildContext context,
  Offset position, {
  required VoidCallback onDelete,
}) async {
  final action = await showMenu<_CategoryContextAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: const [
      PopupMenuItem(
        value: _CategoryContextAction.delete,
        child: Text('删除分类'),
      ),
    ],
  );
  if (action == _CategoryContextAction.delete) {
    onDelete();
  }
}

class _ScriptShelf extends StatefulWidget {
  final EdgeInsetsGeometry contentPadding;
  final List<ScriptExhibitionScript> scripts;
  final String query;
  final Set<String> selectedScriptIds;
  final ValueChanged<String> onSelect;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<String> onQueryChanged;
  final ScriptExhibitionSendHandler onSend;
  final String? pendingScriptWorkbenchId;
  final ValueChanged<ScriptExhibitionScript>? onDelete;
  final ScrollController scrollController;
  final bool Function(ScriptExhibitionScript script) canDeleteScript;
  final String Function(ScriptExhibitionScript script) deleteTooltipForScript;
  final IconData Function(ScriptExhibitionScript script) deleteIconForScript;
  final ValueChanged<ScriptExhibitionScript>? onRename;
  final ValueChanged<ScriptExhibitionScript>? onAssignCategory;

  const _ScriptShelf({
    required this.contentPadding,
    required this.scripts,
    required this.query,
    required this.selectedScriptIds,
    required this.onSelect,
    required this.onSelectionChanged,
    required this.onQueryChanged,
    required this.onSend,
    required this.pendingScriptWorkbenchId,
    required this.onDelete,
    required this.scrollController,
    required this.canDeleteScript,
    required this.deleteTooltipForScript,
    required this.deleteIconForScript,
    required this.onRename,
    required this.onAssignCategory,
  });

  @override
  State<_ScriptShelf> createState() => _ScriptShelfState();
}

class _ScriptShelfState extends State<_ScriptShelf> {
  final GlobalKey _shelfKey = GlobalKey();
  final Map<String, Rect> _cardRects = {};
  final ValueNotifier<_ScriptShelfMarqueeOverlay?> _marqueeOverlayNotifier =
      ValueNotifier<_ScriptShelfMarqueeOverlay?>(null);
  late final TextEditingController _searchController;
  int _visibleScriptLimit = _scriptShelfInitialWindow;
  int _enabledCoverLimit = 0;
  Timer? _coverExpansionTimer;
  bool _scrollWindowCheckScheduled = false;
  Offset? _marqueeStartLocal;
  Offset? _marqueeStartGlobal;
  Offset? _marqueeCurrentGlobal;
  Set<String> _marqueeBaseSelection = const {};
  Set<String> _marqueeAccumulatedSelection = const {};
  Set<String> _pendingMarqueeSelection = const {};
  bool _marqueeMode = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
    widget.scrollController.addListener(_handleScrollPositionChanged);
    _resetVisibleScriptWindow();
    _resetCoverWindow();
  }

  @override
  void didUpdateWidget(_ScriptShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _searchController.text != widget.query) {
      _searchController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScrollPositionChanged);
      widget.scrollController.addListener(_handleScrollPositionChanged);
    }
    final liveIds = _visibleScriptIds;
    _cardRects.removeWhere((scriptId, rect) => !liveIds.contains(scriptId));
    if (!_sameScriptOrder(oldWidget.scripts, widget.scripts)) {
      _resetVisibleScriptWindow();
      _resetCoverWindow();
    } else {
      _scheduleVisibleScriptExpansion();
      _scheduleCoverExpansion();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScrollPositionChanged);
    _coverExpansionTimer?.cancel();
    _searchController.dispose();
    _marqueeOverlayNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Listener(
        key: _shelfKey,
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          children: [
            Padding(
              padding: widget.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShelfToolbar(context),
                  const SizedBox(height: 14),
                  if (widget.scripts.isEmpty)
                    _StatusPanel(
                      icon: Icons.search_off_outlined,
                      title:
                          widget.query.trim().isEmpty ? '当前分类没有剧本' : '没有匹配的剧本',
                      subtitle: widget.query.trim().isEmpty
                          ? '切换到全部馆区可以查看完整收纳结果。'
                          : '试试更换关键词或清空搜索。',
                    )
                  else
                    IgnorePointer(
                      ignoring: _marqueeMode,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = max(1, constraints.maxWidth ~/ 220);
                          const spacing = 12.0;
                          const aspectRatio = 0.72;
                          final cardWidth =
                              (constraints.maxWidth - spacing * (columns - 1)) /
                                  columns;
                          final cardSize =
                              Size(cardWidth, cardWidth / aspectRatio);
                          final minimumVisibleLimit =
                              _minimumVisibleScriptLimitFor(
                            context: context,
                            columns: columns,
                            cardHeight: cardSize.height,
                            spacing: spacing,
                          );
                          if (_visibleScriptLimit < minimumVisibleLimit) {
                            _visibleScriptLimit = minimumVisibleLimit;
                          }
                          _scheduleVisibleScriptExpansion();
                          final visibleScripts = _visibleScripts;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: visibleScripts.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              childAspectRatio: aspectRatio,
                            ),
                            itemBuilder: (context, index) {
                              final script = visibleScripts[index];
                              final selected = widget.selectedScriptIds
                                  .contains(script.scriptId);
                              final canDelete = widget.onDelete != null &&
                                  widget.canDeleteScript(script);
                              final isSending =
                                  widget.pendingScriptWorkbenchId ==
                                      script.scriptId;
                              final canSend =
                                  widget.pendingScriptWorkbenchId == null &&
                                      script.focus.canOpenWorkbench;
                              final card = _DraggableScriptShelfCard(
                                key: ValueKey(
                                  'script-exhibition-draggable-${script.scriptId}',
                                ),
                                script: script,
                                selected: selected,
                                dragScripts: _dragScriptsFor(script),
                                cardSize: cardSize,
                                onDragStarted: () {
                                  if (!selected) {
                                    widget.onSelectionChanged(
                                      {script.scriptId},
                                    );
                                  }
                                },
                                coverEnabled: index < _enabledCoverLimit,
                                onTap: () => widget.onSelect(script.scriptId),
                                onSend: canSend
                                    ? () => widget.onSend(script.focus)
                                    : null,
                                isSending: isSending,
                                onDelete: canDelete
                                    ? () => widget.onDelete!(script)
                                    : null,
                                deleteTooltip:
                                    widget.deleteTooltipForScript(script),
                                deleteIcon: widget.deleteIconForScript(script),
                                onRename: widget.onRename == null
                                    ? null
                                    : () => widget.onRename!(script),
                                onAssignCategory: widget.onAssignCategory ==
                                        null
                                    ? null
                                    : () => widget.onAssignCategory!(script),
                              );
                              final item = _ScriptShelfCardRectReporter(
                                scriptId: script.scriptId,
                                scrollController: widget.scrollController,
                                onRectChanged: _recordCardRect,
                                child: card,
                              );
                              return _ScriptShelfStreamEntry(
                                index: index,
                                columns: columns,
                                child: RepaintBoundary(child: item),
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            ValueListenableBuilder<_ScriptShelfMarqueeOverlay?>(
              valueListenable: _marqueeOverlayNotifier,
              builder: (context, overlay, _) {
                if (overlay == null) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('script-exhibition-marquee-overlay'),
                      painter: _ScriptShelfMarqueeOverlayPainter(overlay),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShelfToolbar(BuildContext context) {
    final selectedCount = widget.selectedScriptIds.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '剧本书架',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: StudioTokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '原图与批量产线结果按剧本聚合，保留批次、帧序和角色线索。',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: StudioTokens.textMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 420,
              child: TextField(
                key: const ValueKey('script-exhibition-search'),
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: widget.query.trim().isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey(
                            'script-exhibition-clear-search',
                          ),
                          tooltip: '清空搜索',
                          onPressed: () {
                            _searchController.clear();
                            widget.onQueryChanged('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  hintText: '搜索剧本、目录、帧或提示词',
                  isDense: true,
                ),
                onChanged: widget.onQueryChanged,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('script-exhibition-marquee-mode-toggle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _marqueeMode
                    ? StudioTokens.onPrimary
                    : StudioTokens.textPrimary,
                backgroundColor:
                    _marqueeMode ? StudioTokens.primary : StudioTokens.surface2,
                side: BorderSide(
                  color: _marqueeMode
                      ? StudioTokens.primary
                      : StudioTokens.cardOutline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _marqueeMode = !_marqueeMode;
                  if (!_marqueeMode) {
                    _cardRects.clear();
                    _marqueeOverlayNotifier.value = null;
                  }
                });
              },
              icon: const Icon(Icons.select_all_outlined, size: 18),
              label: Text(_marqueeMode ? '框选中' : '框选'),
            ),
            if (selectedCount > 0) ...[
              StudioChip(
                label: '已选 $selectedCount',
                icon: Icons.check_circle_outline,
                selected: true,
              ),
              IconButton(
                key: const ValueKey('script-exhibition-clear-selection'),
                tooltip: '清空选中',
                onPressed: () => widget.onSelectionChanged(const {}),
                icon: const Icon(Icons.clear_all_outlined),
              ),
            ],
          ],
        ),
      ],
    );
  }

  List<ScriptExhibitionScript> get _visibleScripts {
    final visibleCount =
        min(widget.scripts.length, max(0, _visibleScriptLimit));
    return widget.scripts.take(visibleCount).toList(growable: false);
  }

  int _minimumVisibleScriptLimitFor({
    required BuildContext context,
    required int columns,
    required double cardHeight,
    required double spacing,
  }) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final rowExtent = max(1.0, cardHeight + spacing);
    final rows = (viewportHeight / rowExtent).ceil() + 1;
    return min(
      widget.scripts.length,
      max(_scriptShelfInitialWindow, rows * columns),
    );
  }

  Set<String> get _visibleScriptIds {
    final visibleCount =
        min(widget.scripts.length, max(0, _visibleScriptLimit));
    return {
      for (var index = 0; index < visibleCount; index += 1)
        widget.scripts[index].scriptId,
    };
  }

  void _resetVisibleScriptWindow() {
    _visibleScriptLimit = min(
      widget.scripts.length,
      _scriptShelfInitialWindow,
    );
    _scheduleVisibleScriptExpansion();
  }

  void _scheduleVisibleScriptExpansion() {
    if (_scrollWindowCheckScheduled) {
      return;
    }
    _scrollWindowCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollWindowCheckScheduled = false;
      if (!mounted) return;
      _expandVisibleScriptsNearScrollEnd();
    });
  }

  void _handleScrollPositionChanged() {
    _preserveCurrentMarqueeHits();
    _expandVisibleScriptsNearScrollEnd();
  }

  void _expandVisibleScriptsNearScrollEnd() {
    if (_visibleScriptLimit >= widget.scripts.length ||
        !widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.extentAfter > _scriptShelfScrollExpansionThreshold) {
      return;
    }
    setState(() {
      _visibleScriptLimit = min(
        widget.scripts.length,
        _visibleScriptLimit + _scriptShelfWindowStep,
      );
    });
    _scheduleCoverExpansion();
    _scheduleVisibleScriptExpansion();
  }

  void _resetCoverWindow() {
    _coverExpansionTimer?.cancel();
    _enabledCoverLimit = min(
      widget.scripts.length,
      min(_visibleScriptLimit, _scriptShelfInitialCoverWindow),
    );
    _scheduleCoverExpansion();
  }

  void _scheduleCoverExpansion() {
    _coverExpansionTimer?.cancel();
    final coverTarget = min(widget.scripts.length, _visibleScriptLimit);
    if (_enabledCoverLimit >= coverTarget) {
      return;
    }
    _coverExpansionTimer = Timer(_scriptShelfCoverExpansionDelay, () {
      if (!mounted) return;
      setState(() {
        _enabledCoverLimit = min(
          min(widget.scripts.length, _visibleScriptLimit),
          _enabledCoverLimit + _scriptShelfCoverWindowStep,
        );
      });
      _scheduleCoverExpansion();
    });
  }

  bool _sameScriptOrder(
    List<ScriptExhibitionScript> left,
    List<ScriptExhibitionScript> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].scriptId != right[index].scriptId) return false;
    }
    return true;
  }

  void _recordCardRect(String scriptId, Rect? rect) {
    if (rect == null) {
      _cardRects.remove(scriptId);
      return;
    }
    _cardRects[scriptId] = rect;
    if (_marqueeStartGlobal != null) {
      _refreshMarqueeOverlay();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kPrimaryMouseButton == 0 ||
        (!_marqueeMode && _isInsideScriptCard(event.position))) {
      return;
    }
    _beginMarquee(
      event.position,
      _localPosition(event.position),
      additive: HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_marqueeStartGlobal == null) return;
    _marqueeCurrentGlobal = event.position;
    _refreshMarqueeOverlay();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_marqueeStartGlobal == null) return;
    _finishMarquee();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_marqueeStartGlobal == null) return;
    _finishMarquee();
  }

  void _beginMarquee(
    Offset globalPosition,
    Offset localPosition, {
    required bool additive,
  }) {
    _marqueeStartGlobal = globalPosition;
    _marqueeCurrentGlobal = globalPosition;
    _marqueeStartLocal = localPosition;
    _marqueeBaseSelection = additive ? widget.selectedScriptIds : const {};
    final startScriptId = _scriptIdAtPosition(globalPosition);
    _marqueeAccumulatedSelection =
        startScriptId == null ? const {} : {startScriptId};
    _pendingMarqueeSelection = {
      ..._marqueeBaseSelection,
      ..._marqueeAccumulatedSelection,
    };
    _refreshMarqueeOverlay();
  }

  void _finishMarquee() {
    final startGlobal = _marqueeStartGlobal;
    final currentGlobal = _marqueeCurrentGlobal;
    final shouldCommitSelection = _marqueeMode ||
        (startGlobal != null &&
            currentGlobal != null &&
            (currentGlobal - startGlobal).distance >= 6.0);
    final selected = _pendingMarqueeSelection;
    _marqueeStartGlobal = null;
    _marqueeCurrentGlobal = null;
    _marqueeStartLocal = null;
    _marqueeBaseSelection = const {};
    _marqueeAccumulatedSelection = const {};
    _pendingMarqueeSelection = const {};
    _marqueeOverlayNotifier.value = null;
    if (shouldCommitSelection) {
      widget.onSelectionChanged(selected);
    }
    setState(() {
      _marqueeMode = false;
    });
  }

  void _refreshMarqueeOverlay() {
    final startGlobal = _marqueeStartGlobal;
    final currentGlobal = _marqueeCurrentGlobal;
    final startLocal = _marqueeStartLocal;
    if (startGlobal == null || currentGlobal == null || startLocal == null) {
      return;
    }
    final marquee = Rect.fromPoints(startGlobal, currentGlobal);
    final selected = _selectionForMarquee(marquee);
    _accumulateMarqueeHits(selected);
    _pendingMarqueeSelection = selected;
    _marqueeOverlayNotifier.value = _ScriptShelfMarqueeOverlay(
      marqueeRect: Rect.fromPoints(startLocal, _localPosition(currentGlobal)),
      selectedRects: _localRectsForSelection(selected),
    );
  }

  Set<String> _selectionForMarquee(Rect marquee) {
    final selected = <String>{..._marqueeBaseSelection};
    selected.addAll(_marqueeAccumulatedSelection);
    for (final script in widget.scripts) {
      final rect = _cardRect(script.scriptId);
      if (rect != null && rect.overlaps(marquee)) {
        selected.add(script.scriptId);
      }
    }
    return selected;
  }

  void _accumulateMarqueeHits(Set<String> selectedIds) {
    final hits = selectedIds
        .where((scriptId) => !_marqueeBaseSelection.contains(scriptId))
        .toSet();
    if (hits.isEmpty) return;
    _marqueeAccumulatedSelection = {
      ..._marqueeAccumulatedSelection,
      ...hits,
    };
  }

  void _preserveCurrentMarqueeHits() {
    if (_marqueeStartGlobal == null || _pendingMarqueeSelection.isEmpty) {
      return;
    }
    _accumulateMarqueeHits(_pendingMarqueeSelection);
  }

  List<Rect> _localRectsForSelection(Set<String> selectedIds) {
    return [
      for (final script in widget.scripts)
        if (selectedIds.contains(script.scriptId))
          if (_cardRect(script.scriptId) case final rect?)
            Rect.fromPoints(
              _localPosition(rect.topLeft),
              _localPosition(rect.bottomRight),
            ),
    ];
  }

  Offset _localPosition(Offset globalPosition) {
    final renderObject = _shelfKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return globalPosition;
    return renderObject.globalToLocal(globalPosition);
  }

  Rect? _cardRect(String scriptId) {
    return _cardRects[scriptId];
  }

  bool _isInsideScriptCard(Offset globalPosition) {
    return _scriptIdAtPosition(globalPosition) != null;
  }

  String? _scriptIdAtPosition(Offset globalPosition) {
    for (final entry in _cardRects.entries) {
      if (entry.value.contains(globalPosition)) {
        return entry.key;
      }
    }
    return null;
  }

  List<ScriptExhibitionScript> _dragScriptsFor(ScriptExhibitionScript script) {
    if (!widget.selectedScriptIds.contains(script.scriptId)) {
      return [script];
    }
    final selectedIds = widget.selectedScriptIds;
    return [
      for (final candidate in widget.scripts)
        if (selectedIds.contains(candidate.scriptId)) candidate,
    ];
  }
}

class _ScriptShelfMarqueeOverlay {
  final Rect marqueeRect;
  final List<Rect> selectedRects;

  const _ScriptShelfMarqueeOverlay({
    required this.marqueeRect,
    required this.selectedRects,
  });
}

class _ScriptShelfMarqueeOverlayPainter extends CustomPainter {
  final _ScriptShelfMarqueeOverlay overlay;

  const _ScriptShelfMarqueeOverlayPainter(this.overlay);

  @override
  void paint(Canvas canvas, Size size) {
    final selectedFill = Paint()
      ..color = StudioTokens.primary.withValues(alpha: 0.10);
    final selectedStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = StudioTokens.primary.withValues(alpha: 0.95);
    for (final rect in overlay.selectedRects) {
      final selectedRect = RRect.fromRectAndRadius(
        rect.inflate(2),
        const Radius.circular(8),
      );
      canvas.drawRRect(selectedRect, selectedFill);
      canvas.drawRRect(selectedRect, selectedStroke);
    }

    final marqueeFill = Paint()
      ..color = StudioTokens.primary.withValues(alpha: 0.12);
    final marqueeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = StudioTokens.primary;
    final marqueeRect = RRect.fromRectAndRadius(
      overlay.marqueeRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(marqueeRect, marqueeFill);
    canvas.drawRRect(marqueeRect, marqueeStroke);
  }

  @override
  bool shouldRepaint(_ScriptShelfMarqueeOverlayPainter oldDelegate) {
    return oldDelegate.overlay != overlay;
  }
}

class _ScriptShelfCardRectReporter extends StatefulWidget {
  final String scriptId;
  final ScrollController scrollController;
  final void Function(String scriptId, Rect? rect) onRectChanged;
  final Widget child;

  const _ScriptShelfCardRectReporter({
    required this.scriptId,
    required this.scrollController,
    required this.onRectChanged,
    required this.child,
  });

  @override
  State<_ScriptShelfCardRectReporter> createState() =>
      _ScriptShelfCardRectReporterState();
}

class _ScriptShelfCardRectReporterState
    extends State<_ScriptShelfCardRectReporter> {
  Rect? _lastReportedRect;
  int _stableReportFrames = 0;
  bool _reportScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_scheduleRectReport);
  }

  @override
  void didUpdateWidget(_ScriptShelfCardRectReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scheduleRectReport);
      widget.scrollController.addListener(_scheduleRectReport);
      _lastReportedRect = null;
      _stableReportFrames = 0;
    }
    if (oldWidget.scriptId != widget.scriptId) {
      widget.onRectChanged(oldWidget.scriptId, null);
      _lastReportedRect = null;
      _stableReportFrames = 0;
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scheduleRectReport);
    widget.onRectChanged(widget.scriptId, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRectReport();
    return widget.child;
  }

  void _scheduleRectReport() {
    if (_reportScheduled || !mounted) {
      return;
    }
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      _reportRect();
    });
  }

  void _reportRect() {
    if (!mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      widget.onRectChanged(widget.scriptId, null);
      _lastReportedRect = null;
      _stableReportFrames = 0;
      return;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    if (!_sameRect(_lastReportedRect, rect)) {
      _lastReportedRect = rect;
      _stableReportFrames = 0;
      widget.onRectChanged(widget.scriptId, rect);
    } else {
      _stableReportFrames += 1;
    }
    if (_stableReportFrames < 2) {
      _scheduleRectReport();
    }
  }

  bool _sameRect(Rect? a, Rect b) {
    if (a == null) {
      return false;
    }
    const tolerance = 0.5;
    return (a.left - b.left).abs() <= tolerance &&
        (a.top - b.top).abs() <= tolerance &&
        (a.right - b.right).abs() <= tolerance &&
        (a.bottom - b.bottom).abs() <= tolerance;
  }
}

class _ScriptShelfStreamEntry extends StatelessWidget {
  final int index;
  final int columns;
  final Widget child;

  const _ScriptShelfStreamEntry({
    required this.index,
    required this.columns,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StudioStaggeredReveal(
      index: index,
      columns: columns,
      maxStaggeredItems: _scriptShelfWindowStep,
      duration: const Duration(milliseconds: 280),
      itemDelay: const Duration(milliseconds: 22),
      beginOffset: const Offset(0, 0.038),
      beginScale: 0.955,
      child: child,
    );
  }
}

class _DraggableScriptShelfCard extends StatelessWidget {
  final ScriptExhibitionScript script;
  final bool selected;
  final List<ScriptExhibitionScript> dragScripts;
  final Size cardSize;
  final VoidCallback onDragStarted;
  final bool coverEnabled;
  final VoidCallback onTap;
  final VoidCallback? onSend;
  final bool isSending;
  final VoidCallback? onDelete;
  final String deleteTooltip;
  final IconData deleteIcon;
  final VoidCallback? onRename;
  final VoidCallback? onAssignCategory;

  const _DraggableScriptShelfCard({
    super.key,
    required this.script,
    required this.selected,
    required this.dragScripts,
    required this.cardSize,
    required this.onDragStarted,
    required this.coverEnabled,
    required this.onTap,
    required this.onSend,
    required this.isSending,
    required this.onDelete,
    required this.deleteTooltip,
    required this.deleteIcon,
    required this.onRename,
    required this.onAssignCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<List<ScriptExhibitionScript>>(
      data: dragScripts,
      affinity: Axis.horizontal,
      onDragStarted: onDragStarted,
      feedback: _ScriptDragFeedback(
        scripts: dragScripts,
        cardSize: cardSize,
      ),
      childWhenDragging: Opacity(
        opacity: 0.48,
        child: _buildCard(),
      ),
      child: _buildCard(
        key: ValueKey('script-exhibition-script-card-${script.scriptId}'),
      ),
    );
  }

  Widget _buildCard({Key? key}) {
    return KeyedSubtree(
      key: key,
      child: _ScriptShelfCard(
        script: script,
        selected: selected,
        onTap: onTap,
        onSend: onSend,
        isSending: isSending,
        onDelete: onDelete,
        deleteTooltip: deleteTooltip,
        deleteIcon: deleteIcon,
        coverEnabled: coverEnabled,
        dragHandle: _ScriptDragHandle(
          script: script,
          dragScripts: dragScripts,
          cardSize: cardSize,
          onDragStarted: onDragStarted,
        ),
        onRename: onRename,
        onAssignCategory: onAssignCategory,
      ),
    );
  }
}

class _ScriptDragHandle extends StatelessWidget {
  final ScriptExhibitionScript script;
  final List<ScriptExhibitionScript> dragScripts;
  final Size cardSize;
  final VoidCallback onDragStarted;

  const _ScriptDragHandle({
    required this.script,
    required this.dragScripts,
    required this.cardSize,
    required this.onDragStarted,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<List<ScriptExhibitionScript>>(
      data: dragScripts,
      onDragStarted: onDragStarted,
      feedback: _ScriptDragFeedback(
        scripts: dragScripts,
        cardSize: cardSize,
      ),
      childWhenDragging: Opacity(opacity: 0.48, child: _buildHandle()),
      child: _buildHandle(),
    );
  }

  Widget _buildHandle() {
    return Tooltip(
      message: '拖拽归类',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: DecoratedBox(
          key: ValueKey('script-exhibition-drag-handle-${script.scriptId}'),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.drag_indicator_outlined,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScriptDragFeedback extends StatelessWidget {
  final List<ScriptExhibitionScript> scripts;
  final Size cardSize;

  const _ScriptDragFeedback({
    required this.scripts,
    required this.cardSize,
  });

  @override
  Widget build(BuildContext context) {
    final primary = scripts.first;
    final count = scripts.length;
    return Material(
      color: Colors.transparent,
      child: RepaintBoundary(
        child: SizedBox(
          key: ValueKey(
              'script-exhibition-drag-feedback-card-${primary.scriptId}'),
          width: cardSize.width,
          height: cardSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (count > 1)
                Positioned(
                  left: 10,
                  top: 10,
                  right: -10,
                  bottom: -10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: StudioTokens.surface3.withValues(alpha: 0.78),
                      borderRadius: StudioTokens.radiusCard,
                      border: Border.all(
                        color: StudioTokens.primary.withValues(alpha: 0.42),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: StudioTokens.surface2.withValues(alpha: 0.96),
                    borderRadius: StudioTokens.radiusCard,
                    border: Border.all(color: StudioTokens.primary, width: 1.6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.34),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_stories_outlined,
                              color: StudioTokens.primary,
                              size: 22,
                            ),
                            const Spacer(),
                            if (count > 1)
                              _ScriptCoverBadge(label: '$count 个剧本'),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          primary.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: StudioTokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '原始剧本 ${primary.originalCount} / 新图 ${primary.generatedImageCount} / 需处理 ${primary.pendingCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: StudioTokens.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final version in primary.versions.take(3))
                              _ScriptCoverBadge(
                                label: version.label,
                                muted: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ScriptContextAction { rename, assignCategory }

Future<void> _showScriptContextMenu(
  BuildContext context,
  Offset position, {
  required VoidCallback? onRename,
  required VoidCallback? onAssignCategory,
}) async {
  if (onRename == null && onAssignCategory == null) return;
  final action = await showMenu<_ScriptContextAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      if (onRename != null)
        const PopupMenuItem(
          value: _ScriptContextAction.rename,
          child: Text('重命名剧本'),
        ),
      if (onAssignCategory != null)
        const PopupMenuItem(
          value: _ScriptContextAction.assignCategory,
          child: Text('归入分类...'),
        ),
    ],
  );
  if (action == _ScriptContextAction.rename) {
    onRename?.call();
  }
  if (action == _ScriptContextAction.assignCategory) {
    onAssignCategory?.call();
  }
}

enum _VersionContextAction { rename, delete }

Future<void> _showVersionContextMenu(
  BuildContext context,
  Offset position, {
  VoidCallback? onRename,
  VoidCallback? onDelete,
}) async {
  final items = [
    if (onRename != null)
      const PopupMenuItem(
        value: _VersionContextAction.rename,
        child: Text('重命名版本'),
      ),
    if (onDelete != null)
      const PopupMenuItem(
        value: _VersionContextAction.delete,
        child: Text('删除版本'),
      ),
  ];
  if (items.isEmpty) return;
  final action = await showMenu<_VersionContextAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: items,
  );
  if (action == _VersionContextAction.rename) {
    onRename?.call();
  }
  if (action == _VersionContextAction.delete) {
    onDelete?.call();
  }
}

class _ScriptShelfCard extends StatelessWidget {
  final ScriptExhibitionScript script;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onSend;
  final bool isSending;
  final VoidCallback? onDelete;
  final String deleteTooltip;
  final IconData deleteIcon;
  final bool coverEnabled;
  final Widget? dragHandle;
  final VoidCallback? onRename;
  final VoidCallback? onAssignCategory;

  const _ScriptShelfCard({
    required this.script,
    required this.selected,
    required this.onTap,
    required this.onSend,
    required this.isSending,
    required this.onDelete,
    required this.deleteTooltip,
    required this.deleteIcon,
    required this.coverEnabled,
    this.dragHandle,
    required this.onRename,
    required this.onAssignCategory,
  });

  @override
  Widget build(BuildContext context) {
    final coverItem = coverEnabled ? script.coverItem : null;
    return GestureDetector(
      onSecondaryTapDown: (details) => _showScriptContextMenu(
        context,
        details.globalPosition,
        onRename: onRename,
        onAssignCategory: onAssignCategory,
      ),
      child: Material(
        color: StudioTokens.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: StudioTokens.radiusCard,
          side: selected
              ? const BorderSide(color: StudioTokens.primary, width: 1.6)
              : BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ScriptCoverBackground(
                key: ValueKey(
                  'script-exhibition-script-cover-${script.scriptId}',
                ),
                imageKey: ValueKey(
                  'script-exhibition-script-cover-image-${script.scriptId}',
                ),
                item: coverItem,
              ),
              const _ScriptCoverScrim(),
              Positioned(
                top: 10,
                left: 10,
                child: _ScriptCoverBadge(label: _coverSourceLabel(coverItem)),
              ),
              if (script.pendingCount > 0)
                Positioned(
                  top: 44,
                  left: 10,
                  child: _ScriptCoverBadge(
                    label: '需处理 ${script.pendingCount}',
                    accentColor: StudioTokens.warning,
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dragHandle != null) ...[
                      dragHandle!,
                      const SizedBox(width: 4),
                    ],
                    _ScriptCoverActionButton(
                      key: ValueKey(
                        'script-exhibition-send-script-${script.scriptId}',
                      ),
                      tooltip: '发送到剧本工作台',
                      onPressed: script.focus.canOpenWorkbench ? onSend : null,
                      icon: Icons.send_outlined,
                      isLoading: isSending,
                    ),
                    if (onRename != null) ...[
                      const SizedBox(width: 4),
                      _ScriptCoverActionButton(
                        key: ValueKey(
                          'script-exhibition-rename-script-${script.scriptId}',
                        ),
                        tooltip: '重命名剧本',
                        onPressed: onRename,
                        icon: Icons.edit_outlined,
                      ),
                    ],
                    const SizedBox(width: 4),
                    _ScriptCoverActionButton(
                      key: ValueKey(
                        'script-exhibition-delete-script-${script.scriptId}',
                      ),
                      tooltip: deleteTooltip,
                      onPressed: onDelete,
                      icon: deleteIcon,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      script.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '原始剧本 ${script.originalCount} / 新图 ${script.generatedImageCount} / 需处理 ${script.pendingCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final version in script.versions.take(3))
                          _ScriptCoverBadge(
                            label: version.label,
                            muted: true,
                          ),
                      ],
                    ),
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

class _ScriptCoverBackground extends StatelessWidget {
  final ScriptExhibitionItem? item;
  final Key imageKey;

  const _ScriptCoverBackground({
    super.key,
    required this.item,
    required this.imageKey,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = item?.imagePath.trim() ?? '';
    if (imagePath.isEmpty) {
      return _ScriptCoverFallback(item: item);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = _cacheImageExtentFor(
          constraints.maxWidth,
          devicePixelRatio,
          maxExtent: _scriptCoverMaxDecodeExtent,
        );
        final cacheHeight = _cacheImageExtentFor(
          constraints.maxHeight,
          devicePixelRatio,
          maxExtent: _scriptCoverMaxDecodeExtent,
        );
        return Image.file(
          File(imagePath),
          key: imageKey,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) =>
              _ScriptCoverFallback(item: item),
        );
      },
    );
  }
}

class _ScriptCoverFallback extends StatelessWidget {
  final ScriptExhibitionItem? item;

  const _ScriptCoverFallback({required this.item});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A3140), Color(0xFF111111)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -32,
            bottom: -24,
            child: Icon(
              item?.sourceKind == ScriptExhibitionItemSourceKind.failed
                  ? Icons.error_outline
                  : Icons.image_outlined,
              size: 148,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptCoverScrim extends StatelessWidget {
  const _ScriptCoverScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.12),
            Colors.black.withValues(alpha: 0.20),
            Colors.black.withValues(alpha: 0.88),
          ],
          stops: const [0.0, 0.42, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.black.withValues(alpha: 0.42),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.26),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptCoverBadge extends StatelessWidget {
  final String label;
  final bool muted;
  final Color? accentColor;

  const _ScriptCoverBadge({
    required this.label,
    this.muted = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? StudioTokens.primary;
    final fill = muted
        ? Colors.black.withValues(alpha: 0.38)
        : accent.withValues(alpha: 0.90);
    final foreground = muted ? Colors.white : StudioTokens.onPrimary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: StudioTokens.radiusBadge,
          border: Border.all(
            color: muted
                ? Colors.white.withValues(alpha: 0.16)
                : accent.withValues(alpha: 0.96),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _ScriptCoverActionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool isLoading;

  const _ScriptCoverActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: Colors.white,
        disabledColor: Colors.white.withValues(alpha: 0.34),
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
      ),
    );
  }
}

String _coverSourceLabel(ScriptExhibitionItem? item) {
  return switch (item?.sourceKind) {
    ScriptExhibitionItemSourceKind.generated => '新图封面',
    ScriptExhibitionItemSourceKind.gallery => '收纳封面',
    ScriptExhibitionItemSourceKind.attachment => '导入封面',
    ScriptExhibitionItemSourceKind.original => '原图封面',
    ScriptExhibitionItemSourceKind.failed => '异常封面',
    ScriptExhibitionItemSourceKind.queued => '排队封面',
    null => '无封面',
  };
}

class _ScriptDetailHeader extends StatelessWidget {
  final ScriptExhibitionScript script;
  final ScriptExhibitionVersion selectedVersion;
  final Set<String> selectedVersionIds;
  final List<ScriptExhibitionVersion> selectedVersions;
  final List<ScriptExhibitionDetailFilter> detailFilters;
  final String selectedDetailFilterId;
  final VoidCallback onBack;
  final ValueChanged<String> onVersionSelected;
  final ValueChanged<String> onVersionSelectionToggled;
  final VoidCallback onClearVersionSelection;
  final ValueChanged<String> onDetailFilterSelected;
  final ScriptExhibitionSendHandler onSend;
  final String? pendingScriptWorkbenchId;
  final ValueChanged<ScriptExhibitionFocus>? onOpenProductionTask;
  final ValueChanged<ScriptExhibitionScript>? onDeleteScript;
  final String deleteTooltip;
  final IconData deleteIcon;
  final ValueChanged<ScriptExhibitionScript>? onRenameScript;
  final void Function(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  )? onRenameVersion;
  final bool Function(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  ) canDeleteVersion;
  final void Function(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  )? onDeleteVersion;
  final void Function(
    ScriptExhibitionScript script,
    List<ScriptExhibitionVersion> versions,
  )? onDeleteSelectedVersions;
  final _ScriptExhibitionScriptAction? onImportImages;
  final ValueChanged<ScriptExhibitionScript>? onOpenSourceFolder;
  final ValueChanged<ScriptExhibitionScript>? onOrganizeScriptImages;
  final String? organizingScriptImagesScriptId;

  const _ScriptDetailHeader({
    required this.script,
    required this.selectedVersion,
    required this.selectedVersionIds,
    required this.selectedVersions,
    required this.detailFilters,
    required this.selectedDetailFilterId,
    required this.onBack,
    required this.onVersionSelected,
    required this.onVersionSelectionToggled,
    required this.onClearVersionSelection,
    required this.onDetailFilterSelected,
    required this.onSend,
    required this.pendingScriptWorkbenchId,
    required this.onOpenProductionTask,
    required this.onDeleteScript,
    required this.deleteTooltip,
    required this.deleteIcon,
    required this.onRenameScript,
    required this.onRenameVersion,
    required this.canDeleteVersion,
    required this.onDeleteVersion,
    required this.onDeleteSelectedVersions,
    required this.onImportImages,
    required this.onOpenSourceFolder,
    required this.onOrganizeScriptImages,
    required this.organizingScriptImagesScriptId,
  });

  @override
  Widget build(BuildContext context) {
    final productionFocus = _productionTaskFocus;
    final isSendingToScriptWorkbench =
        pendingScriptWorkbenchId == script.scriptId;
    final scriptWorkbenchSendDisabled = pendingScriptWorkbenchId != null;
    final sourceFolderKnown = script.sourceFolder.trim().isNotEmpty;
    final isOrganizingScriptImages =
        organizingScriptImagesScriptId == script.scriptId;
    return KeyedSubtree(
      key: ValueKey('script-exhibition-detail-${script.scriptId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回馆区'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      key: ValueKey(
                        'script-exhibition-detail-title-${script.scriptId}',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) => _showScriptContextMenu(
                        context,
                        details.globalPosition,
                        onRename: onRenameScript == null
                            ? null
                            : () => onRenameScript!(script),
                        onAssignCategory: null,
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              script.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: StudioTokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      script.sourceFolder.isEmpty
                          ? '来源目录未记录'
                          : script.sourceFolder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: StudioTokens.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const ValueKey(
                  'script-exhibition-detail-send-script-workbench',
                ),
                onPressed: _sendCallback(
                  script.focus,
                  onSend,
                  disabled: scriptWorkbenchSendDisabled,
                ),
                icon: isSendingToScriptWorkbench
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  isSendingToScriptWorkbench ? '正在打开...' : '发送到剧本工作台',
                ),
              ),
              if (productionFocus != null) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey(
                    'script-exhibition-detail-open-production',
                  ),
                  onPressed: onOpenProductionTask == null
                      ? null
                      : () => onOpenProductionTask!(productionFocus),
                  icon: const Icon(Icons.playlist_play_outlined),
                  label: const Text('打开批量产线'),
                ),
              ],
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('script-exhibition-import-script-images'),
                onPressed: onImportImages == null
                    ? null
                    : () => unawaited(onImportImages!(script)),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('导入图片'),
              ),
              IconButton(
                key: ValueKey(
                  'script-exhibition-open-source-folder-${script.scriptId}',
                ),
                tooltip: '打开源图目录',
                onPressed: !sourceFolderKnown || onOpenSourceFolder == null
                    ? null
                    : () => onOpenSourceFolder!(script),
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                key: ValueKey(
                  'script-exhibition-organize-script-images-${script.scriptId}',
                ),
                tooltip: '整理剧本展览室生成图片',
                onPressed:
                    onOrganizeScriptImages == null || isOrganizingScriptImages
                        ? null
                        : () => onOrganizeScriptImages!(script),
                icon: isOrganizingScriptImages
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.drive_file_move_outline),
              ),
              IconButton(
                key: ValueKey(
                  'script-exhibition-delete-script-detail-${script.scriptId}',
                ),
                tooltip: deleteTooltip,
                onPressed: onDeleteScript == null
                    ? null
                    : () => onDeleteScript!(script),
                icon: Icon(deleteIcon),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '版本',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: StudioTokens.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final version in script.versions)
                _buildVersionChip(context, version),
            ],
          ),
          if (selectedVersions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _VersionSelectionToolbar(
              count: selectedVersions.length,
              onClear: onClearVersionSelection,
              onDelete: onDeleteSelectedVersions == null
                  ? null
                  : () => onDeleteSelectedVersions!(script, selectedVersions),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '状态',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: StudioTokens.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in detailFilters)
                ChoiceChip(
                  key: ValueKey('script-exhibition-detail-filter-${filter.id}'),
                  label: Text('${filter.title} ${filter.count}'),
                  selected: filter.id == selectedDetailFilterId,
                  onSelected: (_) => onDetailFilterSelected(filter.id),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '顺序瀑布流',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: StudioTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            selectedVersion.description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: StudioTokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionChip(
    BuildContext context,
    ScriptExhibitionVersion version,
  ) {
    final canDelete =
        onDeleteVersion != null && canDeleteVersion(script, version);
    final canShowMenu = onRenameVersion != null || canDelete;
    return GestureDetector(
      onSecondaryTapDown: !canShowMenu
          ? null
          : (details) => _showVersionContextMenu(
                context,
                details.globalPosition,
                onRename: onRenameVersion == null
                    ? null
                    : () => onRenameVersion!(script, version),
                onDelete:
                    !canDelete ? null : () => onDeleteVersion!(script, version),
              ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canDelete)
            SizedBox(
              width: 34,
              height: 34,
              child: Checkbox(
                key: ValueKey(
                  'script-exhibition-version-select-${version.id}',
                ),
                value: selectedVersionIds.contains(version.id),
                onChanged: (_) => onVersionSelectionToggled(version.id),
              ),
            ),
          ChoiceChip(
            key: ValueKey('script-exhibition-version-${version.id}'),
            label: Text('${version.label} ${version.items.length}'),
            selected: version.id == selectedVersion.id,
            onSelected: (_) => onVersionSelected(version.id),
          ),
        ],
      ),
    );
  }

  ScriptExhibitionFocus? get _productionTaskFocus {
    for (final item in selectedVersion.items) {
      if (item.needsAction && item.focus.canOpenProductionTask) {
        return item.focus;
      }
    }
    final item = script.firstNeedsActionItem;
    if (item != null && item.focus.canOpenProductionTask) {
      return item.focus;
    }
    return null;
  }
}

class _VersionSelectionToolbar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback? onDelete;

  const _VersionSelectionToolbar({
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusCard,
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.checklist_outlined,
              size: 18,
              color: StudioTokens.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '已选 $count 个版本',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: StudioTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('script-exhibition-clear-selected-versions'),
              tooltip: '清空版本选择',
              onPressed: onClear,
              icon: const Icon(Icons.clear_all_outlined),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const ValueKey('script-exhibition-delete-selected-versions'),
              style: FilledButton.styleFrom(
                backgroundColor: StudioTokens.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除所选'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverWaterfallBoard extends StatefulWidget {
  final List<ScriptExhibitionItem> items;
  final String? focusedItemId;
  final GlobalKey? focusedItemKey;
  final ScrollController scrollController;
  final ScriptExhibitionQuickRerunHandler? onQuickRerunProductionTask;
  final ValueChanged<ScriptExhibitionFocus>? onOpenProductionTask;
  final ScriptExhibitionItemGenerationParamsLoader loadGenerationParams;
  final _ScriptExhibitionItemDeleteHandler? onDelete;
  final ValueChanged<ScriptExhibitionItem>? onRename;
  final ValueChanged<ScriptExhibitionItem>? onSetCover;

  const _SliverWaterfallBoard({
    required this.items,
    required this.focusedItemId,
    required this.focusedItemKey,
    required this.scrollController,
    required this.onQuickRerunProductionTask,
    required this.onOpenProductionTask,
    required this.loadGenerationParams,
    required this.onDelete,
    required this.onRename,
    required this.onSetCover,
  });

  @override
  State<_SliverWaterfallBoard> createState() => _SliverWaterfallBoardState();
}

class _SliverWaterfallBoardState extends State<_SliverWaterfallBoard> {
  int _visibleItemLimit = _scriptDetailInitialWindow;
  bool _scrollWindowCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScrollPositionChanged);
    _resetVisibleItemWindow();
  }

  @override
  void didUpdateWidget(_SliverWaterfallBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScrollPositionChanged);
      widget.scrollController.addListener(_handleScrollPositionChanged);
    }
    if (!_sameItemOrder(oldWidget.items, widget.items)) {
      _resetVisibleItemWindow();
      return;
    }
    final requiredLimit = _minimumVisibleItemLimit();
    if (_visibleItemLimit < requiredLimit) {
      _visibleItemLimit = min(widget.items.length, requiredLimit);
    }
    _scheduleVisibleItemExpansion();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScrollPositionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SliverToBoxAdapter(
        child: _StatusPanel(
          icon: Icons.photo_library_outlined,
          title: '该版本还没有图片',
          subtitle: '批量产线完成后会自动收纳到这里。',
        ),
      );
    }
    final visibleGroups = _visibleGroups;
    final groupsByDisplayId = {
      for (final group in visibleGroups) group.displayItem.id: group,
    };
    final galleryItems = [
      for (final group in visibleGroups)
        _scriptGeneratedImageItem(group.displayItem),
    ];
    return StudioGeneratedImageSliverGallery(
      key: const ValueKey('script-exhibition-waterfall-board'),
      items: galleryItems,
      selectedIds: {
        if (widget.focusedItemId != null)
          for (final group in visibleGroups)
            if (group.contains(widget.focusedItemId!)) group.displayItem.id,
      },
      columnWidth: 320,
      cardKeyPrefix: 'script-exhibition-item',
      imageKeyPrefix: 'script-exhibition-image',
      itemKeys: widget.focusedItemId == null || widget.focusedItemKey == null
          ? const {}
          : {widget.focusedItemId!: widget.focusedItemKey!},
      onOpen: (context, generatedItem) {
        final item = generatedItem.source as ScriptExhibitionItem;
        final previewItems = _scriptFrameVariantPreviewItems(widget.items);
        final previewIndex = previewItems.indexWhere(
          (previewItem) => previewItem.id == item.id,
        );
        _showPreview(
          context: context,
          items: previewItems,
          initialIndex: previewIndex < 0 ? 0 : previewIndex,
          wheelNavigationScopeIdsByItemId:
              _scriptFrameVariantScopeIdsByItemId(previewItems),
          onQuickRerunProductionTask: widget.onQuickRerunProductionTask,
          onOpenProductionTask: widget.onOpenProductionTask,
          loadGenerationParams: widget.loadGenerationParams,
          onDelete: widget.onDelete,
          onRename: widget.onRename,
        );
      },
      imageOverlayBuilder: (context, generatedItem) {
        final item = generatedItem.source as ScriptExhibitionItem;
        final group = groupsByDisplayId[item.id];
        if (group == null || group.items.length <= 1) {
          return const SizedBox.shrink();
        }
        return _ScriptFrameVariantDots(
          key: ValueKey(
            'script-exhibition-variant-indicator-${group.displayItem.id}',
          ),
          count: group.items.length,
          index: group.displayIndex,
        );
      },
      trailingBuilder: (context, generatedItem) {
        final item = generatedItem.source as ScriptExhibitionItem;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onSetCover != null)
              _ScriptSetCoverAction(
                item: item,
                onSetCover: widget.onSetCover!,
              ),
            IconButton(
              key: ValueKey('script-exhibition-rerun-${item.id}'),
              tooltip: '重跑',
              onPressed: item.focus.canOpenProductionTask &&
                      widget.onQuickRerunProductionTask != null
                  ? () {
                      unawaited(Future<void>.sync(
                        () => widget.onQuickRerunProductionTask!(item.focus),
                      ));
                    }
                  : null,
              icon: const Icon(Icons.refresh_outlined, size: 18),
            ),
            if (item.needsAction && item.focus.canOpenProductionTask)
              IconButton(
                key: ValueKey('script-exhibition-open-production-${item.id}'),
                tooltip: '打开批量产线',
                onPressed: widget.onOpenProductionTask == null
                    ? null
                    : () => widget.onOpenProductionTask!(item.focus),
                icon: const Icon(Icons.playlist_play_outlined, size: 18),
              ),
            IconButton(
              key: ValueKey('script-exhibition-delete-item-${item.id}'),
              tooltip: '删除展览图片',
              onPressed: item.canDelete && widget.onDelete != null
                  ? () => unawaited(widget.onDelete!(context, item))
                  : null,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
            if (item.canRename)
              IconButton(
                key: ValueKey('script-exhibition-rename-item-${item.id}'),
                tooltip: '重命名',
                onPressed: widget.onRename == null
                    ? null
                    : () => widget.onRename?.call(item),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
          ],
        );
      },
    );
  }

  List<_ScriptFrameVariantGroup> get _visibleGroups {
    final groups = _scriptFrameVariantGroups(widget.items);
    final visibleCount = min(groups.length, max(0, _visibleItemLimit));
    return groups.take(visibleCount).toList(growable: false);
  }

  void _resetVisibleItemWindow() {
    final groups = _scriptFrameVariantGroups(widget.items);
    _visibleItemLimit = min(groups.length, _minimumVisibleItemLimit(groups));
    _scheduleVisibleItemExpansion();
  }

  int _minimumVisibleItemLimit([List<_ScriptFrameVariantGroup>? groups]) {
    final variantGroups = groups ?? _scriptFrameVariantGroups(widget.items);
    final focusedItemId = widget.focusedItemId;
    final focusedIndex = focusedItemId == null
        ? -1
        : variantGroups.indexWhere((group) => group.contains(focusedItemId));
    return max(_scriptDetailInitialWindow, focusedIndex + 1);
  }

  void _scheduleVisibleItemExpansion() {
    if (_scrollWindowCheckScheduled) {
      return;
    }
    _scrollWindowCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollWindowCheckScheduled = false;
      if (!mounted) return;
      _expandVisibleItemsNearScrollEnd();
    });
  }

  void _handleScrollPositionChanged() {
    _expandVisibleItemsNearScrollEnd();
  }

  void _expandVisibleItemsNearScrollEnd() {
    final groupCount = _scriptFrameVariantGroups(widget.items).length;
    if (_visibleItemLimit >= groupCount ||
        !widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.extentAfter > _scriptDetailScrollExpansionThreshold) {
      return;
    }
    setState(() {
      _visibleItemLimit = min(
        groupCount,
        _visibleItemLimit + _scriptDetailWindowStep,
      );
    });
    _scheduleVisibleItemExpansion();
  }

  bool _sameItemOrder(
    List<ScriptExhibitionItem> left,
    List<ScriptExhibitionItem> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].id != right[index].id) return false;
    }
    return true;
  }
}

class _ScriptFrameVariantGroup {
  final List<ScriptExhibitionItem> items;

  const _ScriptFrameVariantGroup(this.items);

  ScriptExhibitionItem get displayItem {
    return items.reduce(_newerScriptExhibitionItem);
  }

  int get displayIndex {
    final displayId = displayItem.id;
    final index = items.indexWhere((item) => item.id == displayId);
    return index < 0 ? 0 : index;
  }

  bool contains(String itemId) {
    return items.any((item) => item.id == itemId);
  }
}

List<_ScriptFrameVariantGroup> _scriptFrameVariantGroups(
  List<ScriptExhibitionItem> items,
) {
  final order = <String>[];
  final grouped = <String, List<ScriptExhibitionItem>>{};
  for (final item in items) {
    final key = _scriptFrameVariantKey(item) ?? 'item:${item.id}';
    if (!grouped.containsKey(key)) {
      order.add(key);
      grouped[key] = <ScriptExhibitionItem>[];
    }
    grouped[key]!.add(item);
  }
  return [
    for (final key in order)
      _ScriptFrameVariantGroup(List.unmodifiable(grouped[key]!)),
  ];
}

Map<String, List<String>> _scriptFrameVariantScopeIdsByItemId(
  List<ScriptExhibitionItem> items,
) {
  return {
    for (final group in _scriptFrameVariantGroups(items))
      for (final item in group.items)
        item.id: [for (final scopedItem in group.items) scopedItem.id],
  };
}

List<ScriptExhibitionItem> _scriptFrameVariantPreviewItems(
  List<ScriptExhibitionItem> items,
) {
  final result = <ScriptExhibitionItem>[];
  final seen = <String>{};
  for (final group in _scriptFrameVariantGroups(items)) {
    final displayItem = group.displayItem;
    if (seen.add(displayItem.id)) {
      result.add(displayItem);
    }
    for (final item in group.items) {
      if (item.id != displayItem.id && seen.add(item.id)) {
        result.add(item);
      }
    }
  }
  return List.unmodifiable(result);
}

String? _scriptFrameVariantKey(ScriptExhibitionItem item) {
  final frameIndex = item.frameIndex;
  if (frameIndex == null) return null;
  return [
    item.scriptId,
    item.versionId,
    frameIndex.toString(),
  ].join('|');
}

ScriptExhibitionItem _newerScriptExhibitionItem(
  ScriptExhibitionItem left,
  ScriptExhibitionItem right,
) {
  final timeCompare = left.updatedAt.compareTo(right.updatedAt);
  if (timeCompare != 0) {
    return timeCompare < 0 ? right : left;
  }
  return left.id.compareTo(right.id) <= 0 ? right : left;
}

StudioGeneratedImageItem _scriptGeneratedImageItem(ScriptExhibitionItem item) {
  final imagePath = item.imagePath.trim();
  final imageHeight = _waterfallImageHeight(item);
  if (imagePath.isNotEmpty) {
    return StudioGeneratedImageItem.file(
      id: item.id,
      name: item.title,
      leadingLabel: _scriptExhibitionFrameLabel(item),
      imagePath: imagePath,
      source: item,
      imageHeight: imageHeight,
    );
  }
  return StudioGeneratedImageItem(
    id: item.id,
    name: item.title,
    leadingLabel: _scriptExhibitionFrameLabel(item),
    source: item,
    placeholder: item.statusLabel,
    imageHeight: imageHeight,
  );
}

String? _scriptExhibitionFrameLabel(ScriptExhibitionItem item) {
  return item.frameIndex?.toString();
}

class _ScriptFrameVariantDots extends StatelessWidget {
  final int count;
  final int index;

  const _ScriptFrameVariantDots({
    super.key,
    required this.count,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final dotCount = min(count, 9);
    final activeIndex = count <= dotCount
        ? index.clamp(0, dotCount - 1)
        : ((index / count) * dotCount).floor().clamp(0, dotCount - 1);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          label: '图片 ${index + 1}/$count',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var dot = 0; dot < dotCount; dot += 1) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: dot == activeIndex ? 8 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dot == activeIndex
                            ? StudioTokens.primary
                            : Colors.white.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    if (dot != dotCount - 1) const SizedBox(width: 4),
                  ],
                  if (count > dotCount) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _waterfallImageHeight(ScriptExhibitionItem item) {
  return item.sourceKind == ScriptExhibitionItemSourceKind.original
      ? 170.0
      : item.sourceKind == ScriptExhibitionItemSourceKind.failed
          ? 120.0
          : 230.0;
}

double _estimatedWaterfallCardHeight(ScriptExhibitionItem item) {
  return _waterfallImageHeight(item) + 148;
}

class _ImagePreview extends StatelessWidget {
  final ScriptExhibitionItem item;
  final BoxFit fit;

  const _ImagePreview({
    required this.item,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = item.imagePath.trim();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF263241), Color(0xFF111318)],
        ),
      ),
      child: imagePath.isEmpty
          ? _ImageFallback(item: item)
          : Image.file(
              File(imagePath),
              fit: fit,
              errorBuilder: (context, error, stackTrace) =>
                  _ImageFallback(item: item),
            ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final ScriptExhibitionItem item;

  const _ImageFallback({required this.item});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          right: -22,
          bottom: -20,
          child: Icon(
            item.sourceKind == ScriptExhibitionItemSourceKind.failed
                ? Icons.error_outline
                : Icons.image_outlined,
            size: 110,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              item.sourceFileName ?? item.versionLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  const _StatusPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, size: 36, color: StudioTokens.textMuted),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: StudioTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: StudioTokens.textMuted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showPreview({
  required BuildContext context,
  required List<ScriptExhibitionItem> items,
  required int initialIndex,
  required Map<String, List<String>> wheelNavigationScopeIdsByItemId,
  required ScriptExhibitionQuickRerunHandler? onQuickRerunProductionTask,
  required ValueChanged<ScriptExhibitionFocus>? onOpenProductionTask,
  required ScriptExhibitionItemGenerationParamsLoader loadGenerationParams,
  required _ScriptExhibitionItemDeleteHandler? onDelete,
  required ValueChanged<ScriptExhibitionItem>? onRename,
}) {
  final assetCaptureHost = StudioAssetCaptureHost.maybeOf(context);
  final generatedItems = items.map(_scriptGeneratedImageItem).toList();
  return StudioGeneratedImageViewerDialog.show(
    context,
    items: generatedItems,
    initialItemId: generatedItems[initialIndex].id,
    actionsBuilder: (context, generatedItem) {
      final item = generatedItem.source as ScriptExhibitionItem;
      return [
        FilledButton.icon(
          key: const ValueKey('script-exhibition-preview-rerun'),
          onPressed: item.focus.canOpenProductionTask &&
                  onQuickRerunProductionTask != null
              ? () {
                  Navigator.of(context).pop();
                  unawaited(Future<void>.sync(
                    () => onQuickRerunProductionTask(item.focus),
                  ));
                }
              : null,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('重跑'),
        ),
        if (item.needsAction && item.focus.canOpenProductionTask)
          FilledButton.icon(
            key: const ValueKey('script-exhibition-preview-open-production'),
            onPressed: onOpenProductionTask == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onOpenProductionTask(item.focus);
                  },
            icon: const Icon(Icons.playlist_play_outlined),
            label: const Text('批量产线'),
          ),
        IconButton(
          key: const ValueKey('script-exhibition-preview-delete'),
          tooltip: '删除展览图片',
          onPressed: item.canDelete && onDelete != null
              ? () async {
                  final deleted = await onDelete(context, item);
                  if (deleted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              : null,
          icon: const Icon(Icons.delete_outline),
        ),
        if (item.canRename)
          IconButton(
            key: const ValueKey('script-exhibition-preview-rename'),
            tooltip: '重命名',
            onPressed: onRename == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onRename(item);
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
      ];
    },
    footerBuilder: (context, generatedItem, fullscreen) {
      final item = generatedItem.source as ScriptExhibitionItem;
      return _PreviewPromptPanel(
        item: item,
        fullscreen: fullscreen,
        assetCaptureHost: assetCaptureHost,
        loadGenerationParams: loadGenerationParams,
      );
    },
    dialogKey: const ValueKey('script-exhibition-fullscreen-preview'),
    windowedKey: const ValueKey('script-exhibition-image-viewer-windowed'),
    fullscreenKey: const ValueKey('script-exhibition-image-viewer-fullscreen'),
    zoomableKey: const ValueKey('script-exhibition-zoomable-image-viewer'),
    fullscreenButtonKey:
        const ValueKey('script-exhibition-preview-fullscreen-toggle'),
    showFooterInFullscreen: false,
    wheelNavigationEnabled: true,
    wheelNavigationScopeIdsByItemId: wheelNavigationScopeIdsByItemId,
  );
}

class _ScriptExhibitionPreviewDialog extends StatefulWidget {
  final List<ScriptExhibitionItem> items;
  final int initialIndex;
  final ValueChanged<ScriptExhibitionFocus> onSend;
  final ValueChanged<ScriptExhibitionItem>? onDelete;
  final ValueChanged<ScriptExhibitionItem>? onRename;
  final StudioAssetCaptureHostState? assetCaptureHost;

  const _ScriptExhibitionPreviewDialog({
    required this.items,
    required this.initialIndex,
    required this.onSend,
    required this.onDelete,
    required this.onRename,
    required this.assetCaptureHost,
  });

  @override
  State<_ScriptExhibitionPreviewDialog> createState() =>
      _ScriptExhibitionPreviewDialogState();
}

class _ScriptExhibitionPreviewDialogState
    extends State<_ScriptExhibitionPreviewDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'script-preview-dialog');
  late int _index = widget.initialIndex.clamp(0, widget.items.length - 1);
  bool _fullscreen = false;

  ScriptExhibitionItem get _item => widget.items[_index];

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
    final screenSize = MediaQuery.sizeOf(context);
    final child = _fullscreen
        ? SizedBox(
            key: const ValueKey('script-exhibition-image-viewer-fullscreen'),
            width: screenSize.width,
            height: screenSize.height,
            child: _buildFullscreenContent(context),
          )
        : StudioResizableImagePreviewWindow(
            windowKey: const ValueKey(
              'script-exhibition-image-viewer-windowed',
            ),
            child: _buildWindowedContent(context),
          );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        insetPadding: _fullscreen ? EdgeInsets.zero : const EdgeInsets.all(24),
        backgroundColor: _fullscreen ? Colors.black : StudioTokens.surfaceBase,
        child: KeyedSubtree(
          key: const ValueKey('script-exhibition-fullscreen-preview'),
          child: child,
        ),
      ),
    );
  }

  Widget _buildWindowedContent(BuildContext context) {
    final item = _item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewToolbar(
          item: item,
          currentIndex: _index,
          itemCount: widget.items.length,
          fullscreen: _fullscreen,
          canNavigate: _canNavigate,
          onPrevious: () => _navigate(-1),
          onNext: () => _navigate(1),
          onToggleFullscreen: _toggleFullscreen,
          onSend: _sendCurrent,
          onDelete: _deleteCurrent,
          onRename: _renameCurrent,
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: StudioTokens.radiusCard,
            child: _ZoomableImageViewer(item: item, onTap: _toggleFullscreen),
          ),
        ),
        const SizedBox(height: 12),
        _PreviewPromptPanel(
          item: item,
          fullscreen: false,
          assetCaptureHost: widget.assetCaptureHost,
          loadGenerationParams: null,
        ),
      ],
    );
  }

  Widget _buildFullscreenContent(BuildContext context) {
    final item = _item;
    return Stack(
      children: [
        Positioned.fill(
          child: _ZoomableImageViewer(item: item, fullscreen: true),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _OverlayPanel(
            child: _PreviewToolbar(
              item: item,
              currentIndex: _index,
              itemCount: widget.items.length,
              fullscreen: _fullscreen,
              canNavigate: _canNavigate,
              onPrevious: () => _navigate(-1),
              onNext: () => _navigate(1),
              onToggleFullscreen: _toggleFullscreen,
              onSend: _sendCurrent,
              onDelete: _deleteCurrent,
              onRename: _renameCurrent,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ],
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

  void _sendCurrent() {
    final callback = _sendSingleWorkbenchCallback(_item.focus, (focus) {
      Navigator.of(context).pop();
      widget.onSend(focus);
    });
    callback?.call();
  }

  void _deleteCurrent() {
    final onDelete = widget.onDelete;
    if (!_item.canDelete || onDelete == null) return;
    final item = _item;
    Navigator.of(context).pop();
    onDelete(item);
  }

  void _renameCurrent() {
    final onRename = widget.onRename;
    if (!_item.canRename || onRename == null) return;
    final item = _item;
    Navigator.of(context).pop();
    onRename(item);
  }
}

class _PreviewToolbar extends StatelessWidget {
  final ScriptExhibitionItem item;
  final int currentIndex;
  final int itemCount;
  final bool fullscreen;
  final bool canNavigate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onSend;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onClose;

  const _PreviewToolbar({
    required this.item,
    required this.currentIndex,
    required this.itemCount,
    required this.fullscreen,
    required this.canNavigate,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleFullscreen,
    required this.onSend,
    required this.onDelete,
    required this.onRename,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('script-exhibition-preview-previous'),
          tooltip: '上一张',
          onPressed: canNavigate ? onPrevious : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const ValueKey('script-exhibition-preview-next'),
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
          key: const ValueKey('script-exhibition-preview-fullscreen-toggle'),
          tooltip: fullscreen ? '退出全屏' : '全屏',
          onPressed: onToggleFullscreen,
          icon: Icon(
            fullscreen
                ? Icons.fullscreen_exit_outlined
                : Icons.fullscreen_outlined,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('script-exhibition-preview-send'),
          onPressed: _sendSingleWorkbenchCallback(item.focus, (_) {}) == null
              ? null
              : onSend,
          icon: const Icon(Icons.send_outlined),
          label: const Text('发送'),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('script-exhibition-preview-delete'),
          tooltip: '删除',
          onPressed: item.canDelete ? onDelete : null,
          icon: const Icon(Icons.delete_outline),
        ),
        if (item.canRename) ...[
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('script-exhibition-preview-rename'),
            tooltip: '重命名',
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
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

class _ScriptSetCoverAction extends StatelessWidget {
  final ScriptExhibitionItem item;
  final ValueChanged<ScriptExhibitionItem> onSetCover;

  const _ScriptSetCoverAction({
    required this.item,
    required this.onSetCover,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('script-exhibition-set-cover-${item.id}'),
      tooltip: '设为当前剧本封面',
      onPressed: item.hasImage ? () => onSetCover(item) : null,
      icon: const Icon(Icons.wallpaper_outlined, size: 18),
    );
  }
}

List<StudioAssetCaptureDraft> _captureDraftsForExhibitionItem(
  ScriptExhibitionItem item,
) {
  final title = item.title.trim();
  final source = StudioAssetCaptureSource(
    surface: 'script_exhibition',
    label: title.isEmpty ? 'Exhibition item' : title,
    sourceId: item.id,
    path: item.imagePath,
  );
  final record = item.galleryRecord;
  final document = record?.document ??
      (item.assetCapturePayload == null
          ? null
          : StudioGalleryRecord.documentFromNaiPayload(
              item.assetCapturePayload!,
            ));
  if (document != null) {
    final documentDrafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
      document,
      source: source,
    );
    if (documentDrafts.isNotEmpty) {
      return documentDrafts;
    }
  }
  return _capturePromptDraftsForExhibitionItem(item, source);
}

List<StudioAssetCaptureDraft> _capturePromptDraftsForExhibitionItem(
  ScriptExhibitionItem item,
  StudioAssetCaptureSource source,
) {
  final prompt = item.prompt.trim();
  if (prompt.isEmpty) {
    return const <StudioAssetCaptureDraft>[];
  }
  final draft = StudioAssetCaptureDrafts.artistFromPrompt(
    prompt,
    source: source,
  );
  if (draft.artistChain?.tags.isEmpty ?? true) {
    return const <StudioAssetCaptureDraft>[];
  }
  return [draft];
}

Future<void> _showExhibitionAssetCaptureDraft(
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

IconData _exhibitionAssetCaptureIcon(StudioAssetCaptureKind kind) {
  return switch (kind) {
    StudioAssetCaptureKind.artistChain => Icons.brush_outlined,
    StudioAssetCaptureKind.character => Icons.person_outline,
    StudioAssetCaptureKind.outfit => Icons.checkroom_outlined,
  };
}

class _ZoomableImageViewer extends StatefulWidget {
  final ScriptExhibitionItem item;
  final bool fullscreen;
  final VoidCallback? onTap;

  const _ZoomableImageViewer({
    required this.item,
    this.fullscreen = false,
    this.onTap,
  });

  @override
  State<_ZoomableImageViewer> createState() => _ZoomableImageViewerState();
}

class _ZoomableImageViewerState extends State<_ZoomableImageViewer> {
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
  void didUpdateWidget(covariant _ZoomableImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
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
        return Listener(
          key: const ValueKey('script-exhibition-zoomable-image-viewer'),
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
                  child: _ImagePreview(item: widget.item, fit: BoxFit.contain),
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

class _PreviewPromptPanel extends StatelessWidget {
  final ScriptExhibitionItem item;
  final bool fullscreen;
  final StudioAssetCaptureHostState? assetCaptureHost;
  final ScriptExhibitionItemGenerationParamsLoader? loadGenerationParams;

  const _PreviewPromptPanel({
    required this.item,
    required this.fullscreen,
    required this.assetCaptureHost,
    required this.loadGenerationParams,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = item.prompt.trim();
    final promptGroups = _exhibitionPromptGroups(item);
    final generationDetails = _exhibitionGenerationDetailLabels(item);
    final meta = [
      item.versionLabel,
      item.statusLabel,
      if (item.sourceFileName != null) item.sourceFileName!,
      if (item.imagePath.isNotEmpty) item.imagePath,
    ].join(' 路 ');
    final captureDrafts = _captureDraftsForExhibitionItem(item);
    final visibleCaptureGroupIds = _exhibitionVisibleCaptureGroupIds(prompt);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (promptGroups.isNotEmpty)
          PromptTagGroupDisplay(
            key: ValueKey('script-exhibition-preview-prompt-tags-${item.id}'),
            groups: promptGroups,
            groupKeyPrefix: 'script-exhibition-preview-prompt-group-${item.id}',
            tagKeyPrefix:
                'script-exhibition-preview-prompt-group-tags-${item.id}',
            defaultTranslated: true,
            dense: true,
            enableHoverShortcut: true,
            enableTagActions: true,
            showLayoutControls: !fullscreen,
            initialLayoutMode: PromptTagLayoutMode.grouped,
            groupActionBuilder: (context, groupContext) =>
                _exhibitionPreviewPromptGroupAction(
              context,
              groupContext,
              itemId: item.id,
              drafts: captureDrafts,
              assetCaptureHost: assetCaptureHost,
            ),
          )
        else if (prompt.isNotEmpty)
          PromptTagDisplay(
            key: ValueKey('script-exhibition-preview-prompt-tags-${item.id}'),
            text: prompt,
            defaultTranslated: true,
            dense: true,
            enableHoverShortcut: true,
            enableTagActions: true,
            showLayoutControls: !fullscreen,
            initialLayoutMode: PromptTagLayoutMode.grouped,
            groupActionBuilder: (context, groupContext) =>
                _exhibitionPreviewPromptGroupAction(
              context,
              groupContext,
              itemId: item.id,
              drafts: captureDrafts,
              assetCaptureHost: assetCaptureHost,
            ),
          )
        else
          Text(
            item.subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: StudioTokens.textSecondary),
          ),
        ..._exhibitionGenerationDetailWidgets(
          item: item,
          details: generationDetails,
          loadGenerationParams: loadGenerationParams,
        ),
        ..._exhibitionPreviewPromptFallbackActions(
          context,
          itemId: item.id,
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
      key: const ValueKey('script-exhibition-preview-prompt-scroll'),
      child: content,
    );
  }
}

Widget? _exhibitionPreviewPromptGroupAction(
  BuildContext context,
  PromptTagGroupActionContext groupContext, {
  required String itemId,
  required List<StudioAssetCaptureDraft> drafts,
  required StudioAssetCaptureHostState? assetCaptureHost,
}) {
  final entries = [
    for (final (index, draft) in drafts.indexed)
      if (_exhibitionAssetCaptureGroupId(draft.kind) == groupContext.group.id)
        (index, draft),
  ];
  if (entries.isEmpty) {
    return null;
  }
  final (index, draft) = entries.first;
  return _exhibitionPreviewPromptSaveButton(
    context,
    itemId: itemId,
    draft: _exhibitionDraftForVisiblePromptGroup(draft, groupContext),
    index: index,
    assetCaptureHost: assetCaptureHost,
  );
}

StudioAssetCaptureDraft _exhibitionDraftForVisiblePromptGroup(
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

List<Widget> _exhibitionPreviewPromptFallbackActions(
  BuildContext context, {
  required String itemId,
  required List<StudioAssetCaptureDraft> drafts,
  required Set<String> visibleGroupIds,
  required StudioAssetCaptureHostState? assetCaptureHost,
}) {
  final missing = [
    for (final (index, draft) in drafts.indexed)
      if (!visibleGroupIds.contains(_exhibitionAssetCaptureGroupId(draft.kind)))
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
          _exhibitionPreviewPromptSaveButton(
            context,
            itemId: itemId,
            draft: draft,
            index: index,
            assetCaptureHost: assetCaptureHost,
          ),
      ],
    ),
  ];
}

Widget _exhibitionPreviewPromptSaveButton(
  BuildContext context, {
  required String itemId,
  required StudioAssetCaptureDraft draft,
  required int index,
  required StudioAssetCaptureHostState? assetCaptureHost,
}) {
  return TextButton.icon(
    key: ValueKey(
      'script-exhibition-preview-prompt-save-asset-$itemId-'
      '${draft.kind.storageKey}-$index',
    ),
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: () async {
      await _showExhibitionAssetCaptureDraft(
        context,
        draft,
        host: assetCaptureHost,
        closeBeforeShow: true,
      );
    },
    icon: Icon(_exhibitionAssetCaptureIcon(draft.kind), size: 15),
    label: const Text('保存为素材'),
  );
}

Set<String> _exhibitionVisibleCaptureGroupIds(String prompt) {
  return {
    for (final tag in PromptTagProcessor.analyzeWorkshopTags(prompt))
      PromptTagClassifier.classify(tag.displayText).group.id,
  };
}

List<PromptTagDisplayGroup> _exhibitionPromptGroups(
  ScriptExhibitionItem item,
) {
  final recordParamConfig = _exhibitionMapValue(
    item.galleryRecord?.document.payload['param_config'],
  );
  final recordGroups = promptTagGroupsFromPromptParameters(recordParamConfig);
  if (recordGroups.isNotEmpty) {
    return recordGroups;
  }
  final workbenchGroups = promptTagGroupsFromWorkbenchPayload(
    item.galleryRecord?.document.payload,
  );
  if (workbenchGroups.isNotEmpty) {
    return workbenchGroups;
  }

  final payloadParameters = _exhibitionMapValue(
    item.assetCapturePayload?['parameters'],
  );
  return promptTagGroupsFromPromptParameters(payloadParameters);
}

List<String> _exhibitionGenerationDetailLabels(
  ScriptExhibitionItem item,
) {
  final params = _exhibitionGenerationParams(item);
  return _exhibitionGenerationDetailLabelsFromParams(params);
}

List<String> _exhibitionGenerationDetailLabelsFromParams(
  Map<String, dynamic> params,
) {
  if (params.isEmpty) {
    return const [];
  }
  final details = <String>[
    if (_exhibitionParamText(params['seed']) case final seed?) 'Seed $seed',
    if (_exhibitionParamText(params['steps']) case final steps?) 'Steps $steps',
    if (_exhibitionParamText(params['sampler']) case final sampler?)
      'Sampler $sampler',
    if (_exhibitionParamText(params['scale']) case final scale?) 'Scale $scale',
    if (_exhibitionParamText(params['cfg_rescale']) case final cfg?) 'CFG $cfg',
    if (_exhibitionSizeLabel(params) case final size?) size,
    if (_exhibitionParamText(params['noise_schedule']) case final noise?)
      'Noise $noise',
  ];
  return details;
}

List<Widget> _exhibitionGenerationDetailWidgets({
  required ScriptExhibitionItem item,
  required List<String> details,
  required ScriptExhibitionItemGenerationParamsLoader? loadGenerationParams,
}) {
  if (details.isNotEmpty) {
    return [
      const SizedBox(height: 6),
      _GenerationDetailChips(itemId: item.id, details: details),
    ];
  }
  if (loadGenerationParams == null) {
    return const [];
  }
  return [
    FutureBuilder<Map<String, dynamic>>(
      future: loadGenerationParams(item),
      builder: (context, snapshot) {
        final loadedDetails = _exhibitionGenerationDetailLabelsFromParams(
          snapshot.data ?? const <String, dynamic>{},
        );
        if (loadedDetails.isEmpty) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _MissingGenerationMetadataNotice(),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _GenerationDetailChips(
            itemId: item.id,
            details: loadedDetails,
          ),
        );
      },
    ),
  ];
}

class _MissingGenerationMetadataNotice extends StatelessWidget {
  const _MissingGenerationMetadataNotice();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: StudioChip(
        label: '未找到 Seed/Steps 元数据',
        icon: Icons.info_outline,
      ),
    );
  }
}

class _GenerationDetailChips extends StatelessWidget {
  final String itemId;
  final List<String> details;

  const _GenerationDetailChips({
    required this.itemId,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: ValueKey('script-exhibition-preview-generation-params-$itemId'),
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final detail in details)
          StudioChip(
            label: detail,
            icon: Icons.tune_outlined,
          ),
      ],
    );
  }
}

Map<String, dynamic> _exhibitionGenerationParams(
  ScriptExhibitionItem item,
) {
  if (item.generationParams.isNotEmpty) {
    return item.generationParams;
  }
  final recordParamConfig = _exhibitionMapValue(
    item.galleryRecord?.document.payload['param_config'],
  );
  if (recordParamConfig.isNotEmpty) {
    return recordParamConfig;
  }
  return _exhibitionMapValue(item.assetCapturePayload?['parameters']);
}

String? _exhibitionSizeLabel(Map<String, dynamic> params) {
  final width = _exhibitionParamText(params['width']);
  final height = _exhibitionParamText(params['height']);
  if (width == null || height == null) {
    return null;
  }
  return 'Size ${width}x$height';
}

String? _exhibitionParamText(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

Map<String, dynamic> _exhibitionMapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

String _exhibitionAssetCaptureGroupId(StudioAssetCaptureKind kind) {
  return switch (kind) {
    StudioAssetCaptureKind.artistChain => 'artist',
    StudioAssetCaptureKind.character => 'character',
    StudioAssetCaptureKind.outfit => 'clothing',
  };
}

class _OverlayPanel extends StatelessWidget {
  final Widget child;

  const _OverlayPanel({required this.child});

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

class _DeleteDialogResult {
  final bool confirmed;
  final bool deleteLocalFiles;

  const _DeleteDialogResult({
    required this.confirmed,
    this.deleteLocalFiles = false,
  });

  static const cancelled = _DeleteDialogResult(confirmed: false);
}

Future<_DeleteDialogResult> _showScriptDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  required ValueKey<String> confirmKey,
  ValueKey<String> localFilesKey =
      const ValueKey('script-exhibition-delete-local-files'),
  String confirmLabel = '删除',
}) async {
  var deleteLocalFiles = false;
  final isItemDelete =
      confirmKey.value == 'script-exhibition-confirm-delete-item';
  final resolvedTitle = isItemDelete ? '删除图片' : title;
  final resolvedMessage = isItemDelete
      ? '只会移除当前帧的当前图片，不会删除整条版本、整条剧本或同帧其它图片。如果这是该帧最后一张生成图，会保留待处理状态。'
      : message;
  final resolvedConfirmLabel = isItemDelete ? '删除图片' : confirmLabel;
  final result = await showDialog<_DeleteDialogResult>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: StudioTokens.surface2,
            title: Text(resolvedTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(resolvedMessage),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: localFilesKey,
                  value: deleteLocalFiles,
                  onChanged: (value) {
                    setDialogState(() {
                      deleteLocalFiles = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时删除本地图片文件'),
                  subtitle: const Text('不会删除原始剧本目录或源文件。'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_DeleteDialogResult.cancelled),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                key: confirmKey,
                onPressed: () => Navigator.of(context).pop(
                  _DeleteDialogResult(
                    confirmed: true,
                    deleteLocalFiles: deleteLocalFiles,
                  ),
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(resolvedConfirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
  return result ?? _DeleteDialogResult.cancelled;
}

Future<bool> _showDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  required ValueKey<String> confirmKey,
  String confirmLabel = '删除',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: StudioTokens.surface2,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: confirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

Future<bool> _showScriptImageOrganizationDialog({
  required BuildContext context,
  required ScriptExhibitionImageOrganizationPreview preview,
}) async {
  final moveSamples =
      preview.moves.map((move) => move.destinationPath).take(4).toList();
  final orphanSamples = preview.orphanImagePaths.take(4).toList();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: StudioTokens.surface2,
        title: const Text('整理剧本展览室生成图片'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '将移动 ${preview.moves.length} 张剧本展览室生成图片，并删除 '
                '${preview.orphanImagePaths.length} 张不在画廊和剧本展览室记录中的孤儿图片。',
              ),
              if (moveSamples.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '将整理到：',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: StudioTokens.textMuted,
                      ),
                ),
                const SizedBox(height: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: StudioTokens.surface3,
                    borderRadius: StudioTokens.radiusCard,
                    border: Border.all(color: StudioTokens.cardOutline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final path in moveSamples)
                          Text(
                            _exhibitionFileNameFromPath(path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: StudioTokens.textSecondary,
                                    ),
                          ),
                        if (preview.moves.length > moveSamples.length)
                          Text(
                            '还有 ${preview.moves.length - moveSamples.length} 张...',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: StudioTokens.textMuted,
                                    ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (orphanSamples.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '将删除孤儿图片：',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: StudioTokens.textMuted,
                      ),
                ),
                const SizedBox(height: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: StudioTokens.surface3,
                    borderRadius: StudioTokens.radiusCard,
                    border: Border.all(color: StudioTokens.cardOutline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final path in orphanSamples)
                          Text(
                            _exhibitionFileNameFromPath(path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: StudioTokens.textSecondary,
                                    ),
                          ),
                        if (preview.orphanImagePaths.length >
                            orphanSamples.length)
                          Text(
                            '还有 ${preview.orphanImagePaths.length - orphanSamples.length} 张...',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: StudioTokens.textMuted,
                                    ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const ValueKey(
              'script-exhibition-confirm-organize-script-images',
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('开始整理'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

String _exhibitionFileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? path : parts.last;
}

Future<String?> _showRenameDialog({
  required BuildContext context,
  required String initialLabel,
  String title = '重命名图片',
  ValueKey<String> confirmKey = const ValueKey(
    'script-exhibition-confirm-rename-item',
  ),
}) async {
  final controller = TextEditingController(text: initialLabel);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: StudioTokens.surface2,
        title: Text(title),
        content: TextField(
          key: const ValueKey('script-exhibition-rename-label-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: confirmKey,
            onPressed: () => Navigator.of(context).pop(controller.text),
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      );
    },
  );
  final trimmed = result?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<String?> _showCategoryDialog({
  required BuildContext context,
  required List<ScriptExhibitionCategory> categories,
  required String title,
}) async {
  final controller = TextEditingController();
  String? selectedName;
  final customCategories = categories
      .where(
        (category) =>
            category.id != ScriptExhibitionRoomViewModel.allCategoryId,
      )
      .toList(growable: false);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: StudioTokens.surface2,
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (customCategories.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in customCategories)
                          ChoiceChip(
                            key: ValueKey(
                              'script-exhibition-category-choice-${category.id}',
                            ),
                            label: Text(category.title),
                            selected: selectedName == category.title,
                            onSelected: (_) {
                              setState(() {
                                selectedName = category.title;
                                controller.text = category.title;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    key: const ValueKey(
                      'script-exhibition-category-name-field',
                    ),
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '分类名称'),
                    onChanged: (value) {
                      setState(() {
                        selectedName = value.trim().isEmpty ? null : value;
                      });
                    },
                    onSubmitted: (value) => Navigator.of(context).pop(value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                key: const ValueKey('script-exhibition-confirm-category'),
                onPressed: () {
                  Navigator.of(context).pop(
                    controller.text.trim().isEmpty
                        ? selectedName
                        : controller.text,
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
  final trimmed = result?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

VoidCallback? _sendCallback(
  ScriptExhibitionFocus? focus,
  ScriptExhibitionSendHandler onSend, {
  bool disabled = false,
}) {
  if (disabled || focus == null || !focus.canOpenWorkbench) {
    return null;
  }
  return () {
    unawaited(Future<void>.sync(() => onSend(focus)));
  };
}

VoidCallback? _sendSingleWorkbenchCallback(
  ScriptExhibitionFocus? focus,
  ValueChanged<ScriptExhibitionFocus> onSend,
) {
  if (focus == null || !focus.canOpenSingleWorkbench) {
    return null;
  }
  return () => onSend(focus);
}

int? _cacheImageExtentFor(
  double extent,
  double devicePixelRatio, {
  required int maxExtent,
}) {
  if (!extent.isFinite || extent <= 0 || devicePixelRatio <= 0) {
    return null;
  }
  return (extent * devicePixelRatio).ceil().clamp(1, maxExtent).toInt();
}

const _scriptShelfInitialWindow = 12;
const _scriptShelfWindowStep = 12;
const _scriptShelfScrollExpansionThreshold = 560.0;
const _scriptShelfInitialCoverWindow = 4;
const _scriptShelfCoverWindowStep = 4;
const _scriptShelfCoverExpansionDelay = Duration(milliseconds: 48);
const _scriptCoverMaxDecodeExtent = 1024;
const _scriptDetailInitialWindow = 12;
const _scriptDetailWindowStep = 12;
const _scriptDetailScrollExpansionThreshold = 720.0;
