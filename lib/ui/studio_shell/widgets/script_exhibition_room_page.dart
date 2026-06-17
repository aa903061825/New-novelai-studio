import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_generated_image_gallery.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';

class ScriptExhibitionRoomPage extends StatefulWidget {
  final ScriptExhibitionRoomViewModel viewModel;
  final ValueChanged<ScriptExhibitionFocus> onSendToScriptWorkbench;
  final ValueChanged<ScriptExhibitionFocus> onSendToWorkbench;

  const ScriptExhibitionRoomPage({
    super.key,
    required this.viewModel,
    required this.onSendToScriptWorkbench,
    required this.onSendToWorkbench,
  });

  @override
  State<ScriptExhibitionRoomPage> createState() =>
      _ScriptExhibitionRoomPageState();
}

class _ScriptExhibitionRoomPageState extends State<ScriptExhibitionRoomPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalObjectKey> _focusedItemKeys = {};
  String? _lastScheduledFocusItemId;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_scheduleFocusedItemScroll);
    unawaited(widget.viewModel.ensureLoaded());
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
    return Material(
      key: const ValueKey('script-exhibition-room-page'),
      type: MaterialType.canvas,
      color: StudioTokens.surfaceBase,
      child: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          return _buildSliverScrollView(context);
        },
      ),
    );
  }

  Widget _buildSliverScrollView(BuildContext context) {
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

    const pagePadding = StudioTokens.pagePadding;
    return CustomScrollView(
      key: const ValueKey('script-exhibition-scroll-view'),
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(pagePadding),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _Header(
                onRefresh: viewModel.load,
                onImport: viewModel.canImportScripts
                    ? widget.viewModel.importScript
                    : null,
              ),
              const SizedBox(height: 14),
              _Metrics(
                snapshot: viewModel.snapshot,
                onNeedsActionPressed: viewModel.snapshot.needsActionCount > 0
                    ? viewModel.jumpToFirstNeedsAction
                    : null,
              ),
              const SizedBox(height: 14),
              _CategoryStrip(
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
              ),
              if (viewModel.selectedScript == null &&
                  viewModel.snapshot.scripts.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SortToolbar(
                  title: '剧本排序',
                  menu: _ScriptSortMenu(
                    value: viewModel.scriptSort,
                    onSelected: viewModel.selectScriptSort,
                  ),
                ),
              ],
              const SizedBox(height: 18),
            ]),
          ),
        ),
        if (viewModel.snapshot.scripts.isEmpty)
          const SliverPadding(
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
          )
        else if (viewModel.selectedScript == null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              pagePadding,
              0,
              pagePadding,
              pagePadding,
            ),
            sliver: SliverToBoxAdapter(
              child: _ScriptShelf(
                scripts: viewModel.visibleScripts,
                selectedScriptIds: viewModel.selectedScriptIds,
                onSelect: viewModel.selectScript,
                onSelectionChanged: viewModel.replaceShelfSelection,
                onSend: widget.onSendToScriptWorkbench,
                onDelete: viewModel.canDeleteScripts ||
                        viewModel.canRemoveScriptCategories
                    ? (script) => _confirmDeleteScript(context, script)
                    : null,
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
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, 0),
            sliver: SliverToBoxAdapter(
              child: _ScriptDetailHeader(
                script: viewModel.selectedScript!,
                selectedVersion: viewModel.selectedVersion!,
                detailFilters: viewModel.detailFilters,
                selectedDetailFilterId: viewModel.selectedDetailFilterId,
                onBack: viewModel.clearScriptSelection,
                onVersionSelected: viewModel.selectVersion,
                onDetailFilterSelected: viewModel.selectDetailFilter,
                onSend: widget.onSendToScriptWorkbench,
                onDeleteScript: _canUseScriptDeleteAction(
                  viewModel.selectedScript!,
                )
                    ? (script) => _confirmDeleteScript(context, script)
                    : null,
                deleteTooltip: _deleteScriptActionTooltip(
                  viewModel.selectedScript!,
                ),
                deleteIcon: _deleteScriptActionIcon(viewModel.selectedScript!),
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
                onImportImages: viewModel.canImportScriptImages
                    ? viewModel.importImagesForScript
                    : null,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              pagePadding,
              12,
              pagePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _SortToolbar(
                title: '图片排序',
                menu: _ItemSortMenu(
                  value: viewModel.itemSort,
                  onSelected: viewModel.selectItemSort,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              pagePadding,
              12,
              pagePadding,
              pagePadding,
            ),
            sliver: _SliverWaterfallBoard(
              items: viewModel.visibleVersionItems,
              focusedItemId: viewModel.focusedItemId,
              focusedItemKey: viewModel.focusedItemId == null
                  ? null
                  : _focusedItemKey(viewModel.focusedItemId!),
              onSend: widget.onSendToWorkbench,
              onDelete: viewModel.canDeleteItems
                  ? (item) => _confirmDeleteItem(context, item)
                  : null,
              onRename: viewModel.canRenameItems
                  ? (item) => _renameItem(context, item)
                  : null,
              onSetCover: viewModel.canSetCoverItems
                  ? (item) => _setCoverItem(context, item)
                  : null,
            ),
          ),
        ],
      ],
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

  Future<void> _confirmDeleteItem(
    BuildContext context,
    ScriptExhibitionItem item,
  ) async {
    final confirmed = await _showDeleteDialog(
      context: context,
      title: '删除展览图片',
      message: '会从展览室移除这条批量产线任务或画廊收纳记录；不会删除原始剧本文件。',
      confirmKey: const ValueKey('script-exhibition-confirm-delete-item'),
    );
    if (!confirmed || !mounted) return;
    await widget.viewModel.deleteItem(item);
  }

  Future<void> _confirmDeleteVersion(
    BuildContext context,
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  ) async {
    if (!widget.viewModel.canDeleteVersion(script, version)) return;
    final confirmed = await _showDeleteDialog(
      context: context,
      title: '删除版本',
      message:
          '只会移除“${script.title}”里的“${version.label}”版本；不会删除整条剧本展览记录或原始剧本目录。',
      confirmKey: const ValueKey('script-exhibition-confirm-delete-version'),
      confirmLabel: '删除版本',
    );
    if (!confirmed || !mounted) return;
    await widget.viewModel.deleteVersion(script, version);
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
      categories: widget.viewModel.categories,
      title: '归入分类',
    );
    if (categoryName == null || !mounted) return;
    await widget.viewModel.assignScriptToCategory(script, categoryName);
  }

  Future<void> _createCategory(BuildContext context) async {
    final categoryName = await _showCategoryDialog(
      context: context,
      categories: widget.viewModel.categories,
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
    await widget.viewModel.assignScriptsToCategory(scripts, category.title);
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
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback? onImport;

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
            onPressed: onImport,
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
  final List<ScriptExhibitionScript> scripts;
  final Set<String> selectedScriptIds;
  final ValueChanged<String> onSelect;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<ScriptExhibitionFocus> onSend;
  final ValueChanged<ScriptExhibitionScript>? onDelete;
  final bool Function(ScriptExhibitionScript script) canDeleteScript;
  final String Function(ScriptExhibitionScript script) deleteTooltipForScript;
  final IconData Function(ScriptExhibitionScript script) deleteIconForScript;
  final ValueChanged<ScriptExhibitionScript>? onRename;
  final ValueChanged<ScriptExhibitionScript>? onAssignCategory;

  const _ScriptShelf({
    required this.scripts,
    required this.selectedScriptIds,
    required this.onSelect,
    required this.onSelectionChanged,
    required this.onSend,
    required this.onDelete,
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
  Offset? _marqueeStartLocal;
  Offset? _marqueeCurrentLocal;
  Offset? _marqueeStartGlobal;
  Offset? _marqueeCurrentGlobal;
  Set<String> _lastMarqueeSelection = const {};

  @override
  void didUpdateWidget(_ScriptShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = widget.scripts.map((script) => script.scriptId).toSet();
    _cardRects.removeWhere((scriptId, rect) => !liveIds.contains(scriptId));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scripts.isEmpty) {
      return const _StatusPanel(
        icon: Icons.search_off_outlined,
        title: '当前分类没有剧本',
        subtitle: '切换到全部馆区可以查看完整收纳结果。',
      );
    }

    return Listener(
      key: _shelfKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          Column(
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
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = max(1, constraints.maxWidth ~/ 220);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.scripts.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemBuilder: (context, index) {
                      final script = widget.scripts[index];
                      final selected =
                          widget.selectedScriptIds.contains(script.scriptId);
                      final canDelete = widget.onDelete != null &&
                          widget.canDeleteScript(script);
                      return _ScriptShelfCardRectReporter(
                        scriptId: script.scriptId,
                        onRectChanged: _recordCardRect,
                        child: _DraggableScriptShelfCard(
                          key: ValueKey(
                            'script-exhibition-draggable-${script.scriptId}',
                          ),
                          script: script,
                          selected: selected,
                          dragScripts: _dragScriptsFor(script),
                          onDragStarted: () {
                            if (!selected) {
                              widget.onSelectionChanged({script.scriptId});
                            }
                          },
                          onTap: () => widget.onSelect(script.scriptId),
                          onSend: () => widget.onSend(script.focus),
                          onDelete:
                              canDelete ? () => widget.onDelete!(script) : null,
                          deleteTooltip: widget.deleteTooltipForScript(script),
                          deleteIcon: widget.deleteIconForScript(script),
                          onRename: widget.onRename == null
                              ? null
                              : () => widget.onRename!(script),
                          onAssignCategory: widget.onAssignCategory == null
                              ? null
                              : () => widget.onAssignCategory!(script),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
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

  void _recordCardRect(String scriptId, Rect? rect) {
    if (rect == null) {
      _cardRects.remove(scriptId);
      return;
    }
    _cardRects[scriptId] = rect;
  }

  Rect? get _marqueeRect {
    final start = _marqueeStartLocal;
    final current = _marqueeCurrentLocal;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kPrimaryMouseButton == 0 ||
        _isInsideScriptCard(event.position)) {
      return;
    }
    setState(() {
      _marqueeStartGlobal = event.position;
      _marqueeCurrentGlobal = event.position;
      _marqueeStartLocal = _localPosition(event.position);
      _marqueeCurrentLocal = _marqueeStartLocal;
      _lastMarqueeSelection = const {};
    });
    widget.onSelectionChanged(const {});
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_marqueeStartGlobal == null) return;
    setState(() {
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
      _lastMarqueeSelection = const {};
    });
  }

  void _updateMarqueeSelection() {
    final start = _marqueeStartGlobal;
    final current = _marqueeCurrentGlobal;
    if (start == null || current == null) return;
    final marquee = Rect.fromPoints(start, current);
    final selected = <String>{};
    for (final script in widget.scripts) {
      final rect = _cardRect(script.scriptId);
      if (rect != null && rect.overlaps(marquee)) {
        selected.add(script.scriptId);
      }
    }
    if (setEquals(selected, _lastMarqueeSelection)) return;
    _lastMarqueeSelection = selected;
    widget.onSelectionChanged(selected);
  }

  Offset _localPosition(Offset globalPosition) {
    final renderObject = _shelfKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return globalPosition;
    return renderObject.globalToLocal(globalPosition);
  }

  bool _isInsideScriptCard(Offset globalPosition) {
    for (final script in widget.scripts) {
      if (_cardRect(script.scriptId)?.contains(globalPosition) ?? false) {
        return true;
      }
    }
    return false;
  }

  Rect? _cardRect(String scriptId) {
    return _cardRects[scriptId];
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

class _ScriptShelfCardRectReporter extends StatefulWidget {
  final String scriptId;
  final void Function(String scriptId, Rect? rect) onRectChanged;
  final Widget child;

  const _ScriptShelfCardRectReporter({
    required this.scriptId,
    required this.onRectChanged,
    required this.child,
  });

  @override
  State<_ScriptShelfCardRectReporter> createState() =>
      _ScriptShelfCardRectReporterState();
}

class _ScriptShelfCardRectReporterState
    extends State<_ScriptShelfCardRectReporter> {
  @override
  void didUpdateWidget(_ScriptShelfCardRectReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptId != widget.scriptId) {
      widget.onRectChanged(oldWidget.scriptId, null);
    }
  }

  @override
  void dispose() {
    widget.onRectChanged(widget.scriptId, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportRect());
    return widget.child;
  }

  void _reportRect() {
    if (!mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      widget.onRectChanged(widget.scriptId, null);
      return;
    }
    widget.onRectChanged(
      widget.scriptId,
      renderObject.localToGlobal(Offset.zero) & renderObject.size,
    );
  }
}

class _DraggableScriptShelfCard extends StatelessWidget {
  final ScriptExhibitionScript script;
  final bool selected;
  final List<ScriptExhibitionScript> dragScripts;
  final VoidCallback onDragStarted;
  final VoidCallback onTap;
  final VoidCallback onSend;
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
    required this.onDragStarted,
    required this.onTap,
    required this.onSend,
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
      onDragStarted: onDragStarted,
      feedback: _ScriptDragFeedback(count: dragScripts.length),
      childWhenDragging: Opacity(
        opacity: 0.48,
        child: _ScriptShelfCard(
          script: script,
          selected: selected,
          onTap: onTap,
          onSend: onSend,
          onDelete: onDelete,
          deleteTooltip: deleteTooltip,
          deleteIcon: deleteIcon,
          onRename: onRename,
          onAssignCategory: onAssignCategory,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('script-exhibition-script-card-${script.scriptId}'),
        child: _ScriptShelfCard(
          script: script,
          selected: selected,
          onTap: onTap,
          onSend: onSend,
          onDelete: onDelete,
          deleteTooltip: deleteTooltip,
          deleteIcon: deleteIcon,
          onRename: onRename,
          onAssignCategory: onAssignCategory,
        ),
      ),
    );
  }
}

class _ScriptDragFeedback extends StatelessWidget {
  final int count;

  const _ScriptDragFeedback({required this.count});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          border: Border.all(color: StudioTokens.primary, width: 1.4),
          borderRadius: StudioTokens.radiusCard,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 18,
                color: StudioTokens.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '$count 个剧本',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
  final VoidCallback onSend;
  final VoidCallback? onDelete;
  final String deleteTooltip;
  final IconData deleteIcon;
  final VoidCallback? onRename;
  final VoidCallback? onAssignCategory;

  const _ScriptShelfCard({
    required this.script,
    required this.selected,
    required this.onTap,
    required this.onSend,
    required this.onDelete,
    required this.deleteTooltip,
    required this.deleteIcon,
    required this.onRename,
    required this.onAssignCategory,
  });

  @override
  Widget build(BuildContext context) {
    final coverItem = script.coverItem;
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
                    _ScriptCoverActionButton(
                      key: ValueKey(
                        'script-exhibition-send-script-${script.scriptId}',
                      ),
                      tooltip: '发送到剧本工作台',
                      onPressed: script.focus.canOpenWorkbench ? onSend : null,
                      icon: Icons.send_outlined,
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
    return Image.file(
      File(imagePath),
      key: imageKey,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _ScriptCoverFallback(item: item),
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

  const _ScriptCoverActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
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
        icon: Icon(icon),
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
  final List<ScriptExhibitionDetailFilter> detailFilters;
  final String selectedDetailFilterId;
  final VoidCallback onBack;
  final ValueChanged<String> onVersionSelected;
  final ValueChanged<String> onDetailFilterSelected;
  final ValueChanged<ScriptExhibitionFocus> onSend;
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
  final ValueChanged<ScriptExhibitionScript>? onImportImages;

  const _ScriptDetailHeader({
    required this.script,
    required this.selectedVersion,
    required this.detailFilters,
    required this.selectedDetailFilterId,
    required this.onBack,
    required this.onVersionSelected,
    required this.onDetailFilterSelected,
    required this.onSend,
    required this.onDeleteScript,
    required this.deleteTooltip,
    required this.deleteIcon,
    required this.onRenameScript,
    required this.onRenameVersion,
    required this.canDeleteVersion,
    required this.onDeleteVersion,
    required this.onImportImages,
  });

  @override
  Widget build(BuildContext context) {
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
                onPressed: _sendCallback(script.focus, onSend),
                icon: const Icon(Icons.send_outlined),
                label: const Text('发送到剧本工作台'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('script-exhibition-import-script-images'),
                onPressed: onImportImages == null
                    ? null
                    : () => onImportImages!(script),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('导入图片'),
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
      child: ChoiceChip(
        key: ValueKey('script-exhibition-version-${version.id}'),
        label: Text('${version.label} ${version.items.length}'),
        selected: version.id == selectedVersion.id,
        onSelected: (_) => onVersionSelected(version.id),
      ),
    );
  }
}

class _SliverWaterfallBoard extends StatelessWidget {
  final List<ScriptExhibitionItem> items;
  final String? focusedItemId;
  final GlobalKey? focusedItemKey;
  final ValueChanged<ScriptExhibitionFocus> onSend;
  final ValueChanged<ScriptExhibitionItem>? onDelete;
  final ValueChanged<ScriptExhibitionItem>? onRename;
  final ValueChanged<ScriptExhibitionItem>? onSetCover;

  const _SliverWaterfallBoard({
    required this.items,
    required this.focusedItemId,
    required this.focusedItemKey,
    required this.onSend,
    required this.onDelete,
    required this.onRename,
    required this.onSetCover,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: _StatusPanel(
          icon: Icons.photo_library_outlined,
          title: '该版本还没有图片',
          subtitle: '批量产线完成后会自动收纳到这里。',
        ),
      );
    }
    final galleryItems = items.map(_scriptGeneratedImageItem).toList();
    return StudioGeneratedImageSliverGallery(
      key: const ValueKey('script-exhibition-waterfall-board'),
      items: galleryItems,
      selectedId: focusedItemId,
      columnWidth: 320,
      cardKeyPrefix: 'script-exhibition-item',
      imageKeyPrefix: 'script-exhibition-image',
      itemKeys: focusedItemId == null || focusedItemKey == null
          ? const {}
          : {focusedItemId!: focusedItemKey!},
      onOpen: (context, generatedItem) {
        final item = generatedItem.source as ScriptExhibitionItem;
        _showPreview(
          context: context,
          items: items,
          initialIndex: items.indexOf(item),
          onSend: onSend,
          onDelete: onDelete,
          onRename: onRename,
        );
      },
      trailingBuilder: (context, generatedItem) {
        final item = generatedItem.source as ScriptExhibitionItem;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSetCover != null)
              _ScriptSetCoverAction(
                item: item,
                onSetCover: onSetCover!,
              ),
            IconButton(
              key: ValueKey('script-exhibition-send-workbench-${item.id}'),
              tooltip: '发送到工作台',
              onPressed: item.focus.canOpenSingleWorkbench
                  ? () => onSend(item.focus)
                  : null,
              icon: const Icon(Icons.send_outlined, size: 18),
            ),
            IconButton(
              key: ValueKey('script-exhibition-delete-item-${item.id}'),
              tooltip: '删除展览图片',
              onPressed: item.canDelete && onDelete != null
                  ? () => onDelete?.call(item)
                  : null,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
            if (item.canRename)
              IconButton(
                key: ValueKey('script-exhibition-rename-item-${item.id}'),
                tooltip: '重命名',
                onPressed: onRename == null ? null : () => onRename?.call(item),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
          ],
        );
      },
    );
  }
}

StudioGeneratedImageItem _scriptGeneratedImageItem(ScriptExhibitionItem item) {
  final imagePath = item.imagePath.trim();
  if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
    return StudioGeneratedImageItem.file(
      id: item.id,
      name: item.title,
      imagePath: imagePath,
      source: item,
    );
  }
  return StudioGeneratedImageItem(
    id: item.id,
    name: item.title,
    source: item,
    placeholder: item.statusLabel,
  );
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
  required ValueChanged<ScriptExhibitionFocus> onSend,
  required ValueChanged<ScriptExhibitionItem>? onDelete,
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
          key: const ValueKey('script-exhibition-preview-send'),
          onPressed: _sendSingleWorkbenchCallback(item.focus, (_) {}) == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onSend(item.focus);
                },
          icon: const Icon(Icons.send_outlined),
          label: const Text('发送'),
        ),
        IconButton(
          key: const ValueKey('script-exhibition-preview-delete'),
          tooltip: '删除展览图片',
          onPressed: item.canDelete && onDelete != null
              ? () {
                  Navigator.of(context).pop();
                  onDelete(item);
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
      );
    },
    dialogKey: const ValueKey('script-exhibition-fullscreen-preview'),
    windowedKey: const ValueKey('script-exhibition-image-viewer-windowed'),
    fullscreenKey: const ValueKey('script-exhibition-image-viewer-fullscreen'),
    zoomableKey: const ValueKey('script-exhibition-zoomable-image-viewer'),
    fullscreenButtonKey:
        const ValueKey('script-exhibition-preview-fullscreen-toggle'),
    showFooterInFullscreen: false,
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

  @override
  void didUpdateWidget(covariant _ZoomableImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
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
        return Listener(
          key: const ValueKey('script-exhibition-zoomable-image-viewer'),
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
                  child: _ImagePreview(item: widget.item, fit: BoxFit.contain),
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

class _PreviewPromptPanel extends StatelessWidget {
  final ScriptExhibitionItem item;
  final bool fullscreen;
  final StudioAssetCaptureHostState? assetCaptureHost;

  const _PreviewPromptPanel({
    required this.item,
    required this.fullscreen,
    required this.assetCaptureHost,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = item.prompt.trim();
    final promptGroups = _exhibitionPromptGroups(item);
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
            defaultTranslated:
                item.sourceKind != ScriptExhibitionItemSourceKind.original,
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
            defaultTranslated:
                item.sourceKind != ScriptExhibitionItemSourceKind.original,
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
}) async {
  var deleteLocalFiles = false;
  final result = await showDialog<_DeleteDialogResult>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: StudioTokens.surface2,
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey(
                    'script-exhibition-delete-local-files',
                  ),
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
                label: const Text('删除'),
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
  ValueChanged<ScriptExhibitionFocus> onSend,
) {
  if (focus == null || !focus.canOpenWorkbench) {
    return null;
  }
  return () => onSend(focus);
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
