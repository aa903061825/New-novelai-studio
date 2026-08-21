import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/ui/studio_shell/models/asset_library_query.dart'
    as asset_query;
import 'package:novel_studio/ui/studio_shell/services/asset_library_edit_document.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

enum _AssetFilter {
  all,
  character,
  outfit,
  artistChain,
  recipe,
  tag,
  codex,
  inspiration,
  lora,
  workflow,
  batchPlan,
  assemblyPreset,
}

enum _AssetKind {
  character,
  outfit,
  artistChain,
  recipe,
  tag,
  inspiration,
  lora,
  workflow,
  batchPlan,
  assemblyPreset,
}

enum _AssetEditorKind {
  character,
  artistChain,
  recipe,
  tag,
}

enum _CharacterPromptField {
  identity,
  upperBody,
  lowerBody,
}

enum _OutfitPromptField {
  full,
  upperBody,
  upperClothing,
  lowerBody,
  lowerClothing,
}

asset_query.AssetLibraryFilter _assetQueryFilterFor(_AssetFilter filter) {
  return switch (filter) {
    _AssetFilter.all => asset_query.AssetLibraryFilter.all,
    _AssetFilter.character => asset_query.AssetLibraryFilter.character,
    _AssetFilter.outfit => asset_query.AssetLibraryFilter.outfit,
    _AssetFilter.artistChain => asset_query.AssetLibraryFilter.artistChain,
    _AssetFilter.recipe => asset_query.AssetLibraryFilter.recipe,
    _AssetFilter.tag => asset_query.AssetLibraryFilter.tag,
    _AssetFilter.codex => asset_query.AssetLibraryFilter.codex,
    _AssetFilter.inspiration => asset_query.AssetLibraryFilter.inspiration,
    _AssetFilter.lora => asset_query.AssetLibraryFilter.lora,
    _AssetFilter.workflow => asset_query.AssetLibraryFilter.workflow,
    _AssetFilter.batchPlan => asset_query.AssetLibraryFilter.batchPlan,
    _AssetFilter.assemblyPreset =>
      asset_query.AssetLibraryFilter.assemblyPreset,
  };
}

asset_query.AssetLibraryKind _assetQueryKindFor(_AssetKind kind) {
  return switch (kind) {
    _AssetKind.character => asset_query.AssetLibraryKind.character,
    _AssetKind.outfit => asset_query.AssetLibraryKind.outfit,
    _AssetKind.artistChain => asset_query.AssetLibraryKind.artistChain,
    _AssetKind.recipe => asset_query.AssetLibraryKind.recipe,
    _AssetKind.tag => asset_query.AssetLibraryKind.tag,
    _AssetKind.inspiration => asset_query.AssetLibraryKind.inspiration,
    _AssetKind.lora => asset_query.AssetLibraryKind.lora,
    _AssetKind.workflow => asset_query.AssetLibraryKind.workflow,
    _AssetKind.batchPlan => asset_query.AssetLibraryKind.batchPlan,
    _AssetKind.assemblyPreset => asset_query.AssetLibraryKind.assemblyPreset,
  };
}

AssetLibraryCharacterPromptField _editCharacterPromptFieldFor(
  _CharacterPromptField field,
) {
  return switch (field) {
    _CharacterPromptField.identity => AssetLibraryCharacterPromptField.identity,
    _CharacterPromptField.upperBody =>
      AssetLibraryCharacterPromptField.upperBody,
    _CharacterPromptField.lowerBody =>
      AssetLibraryCharacterPromptField.lowerBody,
  };
}

AssetLibraryOutfitPromptField _editOutfitPromptFieldFor(
  _OutfitPromptField field,
) {
  return switch (field) {
    _OutfitPromptField.full => AssetLibraryOutfitPromptField.full,
    _OutfitPromptField.upperBody => AssetLibraryOutfitPromptField.upperBody,
    _OutfitPromptField.upperClothing =>
      AssetLibraryOutfitPromptField.upperClothing,
    _OutfitPromptField.lowerBody => AssetLibraryOutfitPromptField.lowerBody,
    _OutfitPromptField.lowerClothing =>
      AssetLibraryOutfitPromptField.lowerClothing,
  };
}

String _assetPromptTagKey(String tag) {
  return PromptTagProcessor.normalizeMatchKey(tag);
}

String _assetPromptAnalysisValue(WorkshopTagAnalysis tag) {
  final raw = tag.text.trim();
  final weight = tag.weight;
  if (weight == null ||
      PromptTagProcessor.hasCompleteNonInlineWeightSyntax(raw)) {
    return raw;
  }
  final display = tag.displayText.trim();
  if (display.isEmpty) return raw;
  return PromptTagProcessor.formatInlineWeightTag(display, weight);
}

String _assetPromptFromValue(
  String value, {
  Set<String>? seenKeys,
  Set<String> omitKeys = const {},
}) {
  final seen = seenKeys ?? <String>{};
  final result = <String>[];
  for (final tag in PromptTagProcessor.analyzeWorkshopTags(value)) {
    final display = tag.displayText.trim();
    final key = _assetPromptTagKey(display);
    if (key.isEmpty || omitKeys.contains(key) || seen.contains(key)) {
      continue;
    }
    seen.add(key);
    result.add(_assetPromptAnalysisValue(tag));
  }
  return result.join(', ');
}

String _assetPromptFromTags(
  Iterable<String> tags, {
  Set<String>? seenKeys,
  Set<String> omitKeys = const {},
}) {
  return _assetPromptFromValue(
    tags.join(', '),
    seenKeys: seenKeys,
    omitKeys: omitKeys,
  );
}

List<String> _assetPromptTagValuesFromValue(String value) {
  return PromptTagProcessor.analyzeWorkshopTags(value)
      .map(_assetPromptAnalysisValue)
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

Set<String> _assetPromptKeysFromValue(String value) {
  return {
    for (final tag in PromptTagProcessor.analyzeWorkshopTags(value))
      if (_assetPromptTagKey(tag.displayText).isNotEmpty)
        _assetPromptTagKey(tag.displayText),
  };
}

Set<String> _assetPromptKeysFromTags(Iterable<String> tags) {
  return _assetPromptKeysFromValue(tags.join(', '));
}

double? _readPreviewAspectRatio(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.height == 0) return null;
    return info.width / info.height;
  } catch (_) {
    return null;
  }
}

Map<String, double> _readPreviewAspectRatios(List<String> paths) {
  final ratios = <String, double>{};
  for (final path in paths.toSet()) {
    final ratio = _readPreviewAspectRatio(path);
    if (ratio != null) {
      ratios[path] = ratio;
    }
  }
  return ratios;
}

const double _assetDetailCloseButtonReserve = 52;

class AssetLibraryPage extends StatefulWidget {
  final StudioAssetCatalogService catalogService;
  final StudioWorkbenchAssetService workbenchAssetService;
  final StudioAssetPreviewGenerationService? previewGenerationService;
  final ValueChanged<StudioScriptAssetFocus>? onSendToScript;
  final Future<List<WorkspaceVibeReference>> Function()? loadVibes;
  final Future<List<WorkspaceVibeReference>> Function()? importVibes;
  final Future<void> Function(List<ArtistChain>)? saveArtistChains;
  final Future<void> Function(List<CharacterEntry>)? saveCharacters;
  final Future<void> Function(String, List<Recipe>)? saveRecipes;
  final Future<void> Function(String, List<TagEntry>)? saveTags;
  final Future<void> Function(List<PromptAssetCategory>)?
      savePromptAssetCategories;
  final VoidCallback? onPromptAssetsChanged;

  const AssetLibraryPage({
    super.key,
    required this.catalogService,
    required this.workbenchAssetService,
    this.previewGenerationService,
    this.onSendToScript,
    this.loadVibes,
    this.importVibes,
    this.saveArtistChains,
    this.saveCharacters,
    this.saveRecipes,
    this.saveTags,
    this.savePromptAssetCategories,
    this.onPromptAssetsChanged,
  });

  @override
  State<AssetLibraryPage> createState() => _AssetLibraryPageState();
}

class _AssetLibraryPageState extends State<AssetLibraryPage> {
  static const int _legacyCodexPageSize = 48;
  static const int _legacyCodexBackgroundBatchSize = 160;
  static const int _assetInitialRenderLimit = 12;
  static const int _assetRenderBatchSize = 12;
  static const int _assetAutoRenderLimit = 48;
  static const int _previewResolveBatchSize = 3;
  static const Duration _legacyCodexBackgroundLoadDelay =
      Duration(milliseconds: 120);

  late Future<StudioAssetCatalogSnapshot> _snapshotFuture;
  String _query = '';
  _AssetFilter _filter = _AssetFilter.all;
  _AssetDisplayItem? _selectedAsset;
  StudioAssetCatalogSnapshot? _localCatalog;
  Future<void> _characterMutationTail = Future<void>.value();
  StudioAssetCatalogSnapshot? _characterMutationCatalog;
  int _pendingCharacterMutations = 0;
  Set<String> _favoriteKeys = const {};
  String? _catalogRefreshStatus;
  bool _loadingMoreLegacyCodex = false;
  bool _legacyCodexAutoLoadQueued = false;
  int _legacyCodexLoadToken = 0;
  int _previewResolveToken = 0;
  final Map<String, List<String>> _resolvedPreviewPathsCache = {};
  final Set<String> _previewResolveQueuedKeys = {};
  final Map<String, double> _previewAspectRatioCache = {};
  final Set<String> _previewAspectRatioQueuedPaths = {};
  StudioAssetCatalogSnapshot? _displayItemsCatalog;
  List<_AssetDisplayItem>? _displayItemsCache;
  bool _assetRenderExpansionQueued = false;
  int _legacyCodexLimit = _legacyCodexPageSize;
  int _visibleAssetLimit = _assetInitialRenderLimit;
  String _legacyCodexSourceScopeKey =
      StudioLegacyCodexCategories.sourceRegularKey;
  String _legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
    _loadFavorites();
  }

  @override
  void didUpdateWidget(covariant AssetLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService) {
      _cancelLegacyCodexBackgroundLoad();
      _snapshotFuture = _loadSnapshot();
      _selectedAsset = null;
      _localCatalog = null;
      _clearPreviewResolutionState();
      _clearDisplayItemsCache();
      _loadFavorites();
    }
  }

  @override
  void dispose() {
    _legacyCodexLoadToken += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioTokens.surface1,
      body: FutureBuilder<StudioAssetCatalogSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LibraryFrame(
              child: _StatePanel(
                icon: Icons.error_outline,
                title: '素材库暂时不可用',
                message: snapshot.error.toString(),
                actionLabel: '重试',
                onAction: _reload,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const _LibraryFrame(
              child: _StatePanel(
                icon: Icons.hourglass_empty,
                title: '正在整理素材索引',
                message: '角色、Outfit、画师串、配方和 Tag 会在这里汇总。',
              ),
            );
          }

          final catalog = _localCatalog ?? snapshot.data!;
          final displaySlice = _displaySliceFor(catalog);
          final visibleItems = displaySlice.items
              .map(_withCachedPreviewData)
              .toList(growable: false);
          _scheduleVisiblePreviewResolution(visibleItems);
          _scheduleVisiblePreviewAspectRatioLoad(visibleItems);
          _scheduleVisibleAssetExpansion(displaySlice.totalCount);
          _scheduleLegacyCodexBackgroundLoad(catalog);

          return _LibraryFrame(
            onScrolledNearEnd: () {
              _expandVisibleAssetLimit(displaySlice.totalCount);
              _loadMoreLegacyCodex(catalog);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LibraryHeader(assetCount: _visibleAssetTotal(catalog)),
                const SizedBox(height: 14),
                _AssetLibraryControls(
                  selectedFilter: _filter,
                  availableFilters: _availableFilters(catalog),
                  selectedCodexSourceScopeKey: _legacyCodexSourceScopeKey,
                  selectedCodexCategoryKey: _legacyCodexCategoryKey,
                  codexCategoryCounts: catalog.legacyCodexCategoryCounts,
                  codexLoadedCount: catalog.legacyCodexLoadedCount,
                  codexTotalCount: catalog.legacyCodexTotalCount,
                  resultCount: displaySlice.totalCount,
                  onQueryChanged: _setQuery,
                  onFilterChanged: _selectAssetFilter,
                  onCodexSourceScopeChanged: _selectLegacyCodexSourceScope,
                  onCodexCategoryChanged: _selectLegacyCodexCategory,
                  onReload: _reload,
                  catalogRefreshStatus: _catalogRefreshStatus,
                  onAddAsset: widget.saveCharacters == null &&
                          widget.saveArtistChains == null &&
                          widget.saveRecipes == null &&
                          widget.saveTags == null
                      ? null
                      : () => _showAssetCreator(catalog),
                  onManagePromptCategories:
                      widget.savePromptAssetCategories == null
                          ? null
                          : () => _showPromptCategoryManager(catalog),
                ),
                const SizedBox(height: 14),
                _AssetLibraryBody(
                  items: visibleItems,
                  selectedAsset: _selectedAsset,
                  onSelect: _openAssetDetail,
                  onToggleFavorite: _toggleFavorite,
                  favoriteKeys: _favoriteKeys,
                  onCopy: _copyAssetPrompt,
                  onGeneratePreview: _generatePreview,
                  onSendToScript:
                      widget.onSendToScript == null ? null : _sendAssetToScript,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAssetDetail(_AssetDisplayItem item) async {
    final sourceItem = _resolveCurrentDisplayItem(item.key) ?? item;
    final detailItem = _withResolvedDetailPreviewData(sourceItem);
    setState(() {
      _selectedAsset = detailItem;
    });
    await showDialog<void>(
      context: context,
      builder: (context) => _AssetDetailDialog(
        initialAsset: detailItem,
        resolveAsset: () {
          final resolved = _resolveCurrentDisplayItem(item.key);
          return resolved == null
              ? null
              : _withResolvedDetailPreviewData(resolved);
        },
        onGeneratePreview: _generatePreview,
        isFavorite: () => _favoriteKeys.contains(item.favoriteKey),
        onToggleFavorite: () => _toggleFavorite(item),
        onSendToScript: widget.onSendToScript == null
            ? null
            : () => _sendAssetToScript(item),
      ),
    );
  }

  _AssetDisplayItem? _resolveCurrentDisplayItem(String key) {
    final catalog = _localCatalog ?? _displayItemsCatalog;
    if (catalog == null) {
      return _selectedAsset?.key == key ? _selectedAsset : null;
    }
    return _displayItemByKey(catalog, key) ??
        (_selectedAsset?.key == key ? _selectedAsset : null);
  }

  _AssetDisplayItem _withResolvedDetailPreviewData(_AssetDisplayItem item) {
    var resolvedItem = _withCachedPreviewData(item);
    if (resolvedItem.referencePaths.isNotEmpty &&
        resolvedItem.resolvedPreviewPaths.isEmpty) {
      resolvedItem = resolvedItem.withResolvedPreviewPaths(
        _resolvePreviewPaths(
          resolvedItem.kind,
          resolvedItem.key,
          resolvedItem.referencePaths,
        ),
      );
    }
    final character = resolvedItem.character;
    if (character == null ||
        character.outfits.isEmpty ||
        resolvedItem.outfitPreviewPathsById.isNotEmpty) {
      return resolvedItem;
    }
    return resolvedItem.withOutfitPreviewPathsById(
      _resolveCharacterOutfitPreviewPaths(character),
    );
  }

  _AssetDisplayItem _withCachedPreviewData(_AssetDisplayItem item) {
    var resolvedItem = item;
    if (item.resolvedPreviewPaths.isEmpty && item.referencePaths.isNotEmpty) {
      final paths = _resolvedPreviewPathsCache[
          _previewPathCacheKey(item.key, item.referencePaths)];
      if (paths != null) {
        resolvedItem = item.withResolvedPreviewPaths(paths);
      }
    }
    return _withCachedPreviewAspectRatio(resolvedItem);
  }

  _AssetDisplayItem _withCachedPreviewAspectRatio(_AssetDisplayItem item) {
    final path = item.resolvedPreviewPath;
    if (path == null) return item;
    final ratio = _previewAspectRatioCache[path];
    if (ratio == null) return item;
    return item.withPreviewAspectRatio(ratio);
  }

  void _scheduleVisiblePreviewResolution(List<_AssetDisplayItem> items) {
    final candidates = <_AssetDisplayItem>[];
    for (final item in items) {
      if (item.referencePaths.isEmpty) continue;
      final cacheKey = _previewPathCacheKey(item.key, item.referencePaths);
      if (_resolvedPreviewPathsCache.containsKey(cacheKey)) continue;
      if (!_previewResolveQueuedKeys.add(cacheKey)) continue;
      candidates.add(item);
    }
    if (candidates.isEmpty) return;
    final token = _previewResolveToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _previewResolveToken) return;
      unawaited(_resolveVisiblePreviewPaths(candidates, token));
    });
  }

  Future<void> _resolveVisiblePreviewPaths(
    List<_AssetDisplayItem> items,
    int token,
  ) async {
    var resolvedBatch = <String, List<String>>{};
    for (final item in items) {
      if (!mounted || token != _previewResolveToken) return;
      final cacheKey = _previewPathCacheKey(item.key, item.referencePaths);
      resolvedBatch[cacheKey] = await widget.catalogService
          .resolveImagePathsAsync(item.referencePaths);
      if (resolvedBatch.length < _previewResolveBatchSize) {
        continue;
      }
      if (!_commitResolvedPreviewPaths(resolvedBatch, token)) {
        return;
      }
      resolvedBatch = <String, List<String>>{};
      await SchedulerBinding.instance.endOfFrame;
    }
    _commitResolvedPreviewPaths(resolvedBatch, token);
  }

  bool _commitResolvedPreviewPaths(
    Map<String, List<String>> resolved,
    int token,
  ) {
    if (resolved.isEmpty) return true;
    if (!mounted || token != _previewResolveToken) return false;
    final previewPaths = <String>[
      for (final paths in resolved.values)
        if (paths.isNotEmpty) paths.first,
    ];
    setState(() {
      for (final entry in resolved.entries) {
        _resolvedPreviewPathsCache[entry.key] = entry.value;
        _previewResolveQueuedKeys.remove(entry.key);
      }
    });
    _schedulePreviewAspectRatioLoad(previewPaths, token);
    return true;
  }

  void _scheduleVisiblePreviewAspectRatioLoad(List<_AssetDisplayItem> items) {
    _schedulePreviewAspectRatioLoad(
      [
        for (final item in items)
          if (item.resolvedPreviewPath case final path?) path,
      ],
      _previewResolveToken,
    );
  }

  void _schedulePreviewAspectRatioLoad(List<String> paths, int token) {
    final candidates = <String>[];
    for (final path in paths) {
      if (path.isEmpty || _previewAspectRatioCache.containsKey(path)) continue;
      if (!_previewAspectRatioQueuedPaths.add(path)) continue;
      candidates.add(path);
    }
    if (candidates.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _previewResolveToken) {
        _previewAspectRatioQueuedPaths.removeAll(candidates);
        return;
      }
      unawaited(_loadPreviewAspectRatios(candidates, token));
    });
  }

  Future<void> _loadPreviewAspectRatios(List<String> paths, int token) async {
    try {
      final ratios = await compute(_readPreviewAspectRatios, paths);
      if (!mounted || token != _previewResolveToken) return;
      setState(() {
        _previewAspectRatioCache.addAll(ratios);
      });
    } finally {
      _previewAspectRatioQueuedPaths.removeAll(paths);
    }
  }

  List<_AssetDisplayItem> _displayItemsFor(
    StudioAssetCatalogSnapshot catalog,
  ) {
    final cached = _displayItemsCache;
    if (identical(_displayItemsCatalog, catalog) && cached != null) {
      return cached;
    }
    final items = _buildDisplayItems(catalog);
    _displayItemsCatalog = catalog;
    _displayItemsCache = items;
    return items;
  }

  void _clearDisplayItemsCache() {
    _displayItemsCatalog = null;
    _displayItemsCache = null;
  }

  void _clearPreviewResolutionState() {
    _previewResolveToken += 1;
    _previewResolveQueuedKeys.clear();
    _resolvedPreviewPathsCache.clear();
    _previewAspectRatioQueuedPaths.clear();
    _previewAspectRatioCache.clear();
  }

  void _resetVisibleAssetLimit() {
    _assetRenderExpansionQueued = false;
    _visibleAssetLimit = _assetInitialRenderLimit;
  }

  void _scheduleVisibleAssetExpansion(int totalCount) {
    final target = min(totalCount, _assetAutoRenderLimit);
    if (_visibleAssetLimit >= target || _assetRenderExpansionQueued) return;
    _assetRenderExpansionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _assetRenderExpansionQueued = false;
      if (!mounted) return;
      final nextTarget = min(totalCount, _assetAutoRenderLimit);
      if (_visibleAssetLimit >= nextTarget) return;
      setState(() {
        _visibleAssetLimit = min(
          nextTarget,
          _visibleAssetLimit + _assetRenderBatchSize,
        );
      });
    });
  }

  void _expandVisibleAssetLimit(int totalCount) {
    if (_visibleAssetLimit >= totalCount) return;
    setState(() {
      _visibleAssetLimit = min(
        totalCount,
        _visibleAssetLimit + _assetRenderBatchSize,
      );
    });
  }

  _AssetDisplaySlice _displaySliceFor(StudioAssetCatalogSnapshot catalog) {
    _displayItemsCatalog = catalog;
    if (_canUseLazyDisplaySlice) {
      return _lazyDisplaySliceFor(catalog);
    }

    final allItems = _displayItemsFor(catalog);
    final filteredItems = _filterItems(allItems);
    return _AssetDisplaySlice(
      items: filteredItems.take(_visibleAssetLimit).toList(growable: false),
      totalCount: filteredItems.length,
    );
  }

  bool get _canUseLazyDisplaySlice {
    return _query.trim().isEmpty;
  }

  _AssetDisplaySlice _lazyDisplaySliceFor(
    StudioAssetCatalogSnapshot catalog,
  ) {
    final items = <_AssetDisplayItem>[];
    final summaryTotalCount = _lazyTotalCountForSelection(catalog);
    var totalCount = 0;
    var stopVisiting = false;

    void addVisible(_AssetDisplayItem Function() buildItem) {
      if (summaryTotalCount == null) {
        totalCount += 1;
      }
      if (items.length < _visibleAssetLimit) {
        items.add(buildItem());
      }
      if (summaryTotalCount != null && items.length >= _visibleAssetLimit) {
        stopVisiting = true;
      }
    }

    void addCandidate({
      required _AssetKind kind,
      required String favoriteKey,
      required _AssetDisplayItem Function() buildItem,
      bool isLegacyCodex = false,
      bool? favoritesOnly,
    }) {
      if (stopVisiting) return;
      if (!_matchesLazyDisplaySelection(
        kind: kind,
        isLegacyCodex: isLegacyCodex,
      )) {
        return;
      }
      if (favoritesOnly != null &&
          _favoriteKeys.contains(favoriteKey) != favoritesOnly) {
        return;
      }
      addVisible(buildItem);
    }

    void visitCandidates({bool? favoritesOnly}) {
      for (final character in catalog.characters) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.character,
          favoriteKey: StudioAssetFavoriteKeys.character(character.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _characterCardItem(character),
        );
      }
      for (final character in catalog.characters) {
        if (stopVisiting) break;
        for (final entry in character.outfits.indexed) {
          if (stopVisiting) break;
          addCandidate(
            kind: _AssetKind.outfit,
            favoriteKey: StudioAssetFavoriteKeys.outfit(
              character.id,
              entry.$2.id,
            ),
            favoritesOnly: favoritesOnly,
            buildItem: () => _outfitCardItem(character, entry.$1, entry.$2),
          );
        }
      }
      for (final artistChain in catalog.artistChains) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.artistChain,
          favoriteKey: StudioAssetFavoriteKeys.artistChain(artistChain.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _artistChainCardItem(artistChain),
        );
      }
      for (final recipe in catalog.recipes) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.recipe,
          favoriteKey: StudioAssetFavoriteKeys.recipe(recipe.block, recipe.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _recipeCardItem(recipe),
        );
      }
      for (final tag in catalog.tags) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.tag,
          favoriteKey: StudioAssetFavoriteKeys.tag(tag.block, tag.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _tagCardItem(tag),
        );
      }
      for (final inspiration in catalog.inspirations) {
        if (stopVisiting) break;
        final isLegacyCodex = StudioAssetCatalogService.isCodexSourceType(
          inspiration.source.type,
        );
        addCandidate(
          kind: _AssetKind.inspiration,
          favoriteKey: StudioAssetFavoriteKeys.inspiration(inspiration.id),
          isLegacyCodex: isLegacyCodex,
          favoritesOnly: favoritesOnly,
          buildItem: () => _inspirationCardItem(inspiration),
        );
      }
      for (final lora in catalog.loras) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.lora,
          favoriteKey: StudioAssetFavoriteKeys.lora(lora.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _loraCardItem(lora),
        );
      }
      for (final workflow in catalog.workflows) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.workflow,
          favoriteKey: StudioAssetFavoriteKeys.workflow(workflow.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _workflowCardItem(workflow),
        );
      }
      for (final batchPlan in catalog.batchPlans) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.batchPlan,
          favoriteKey: 'batch-plan:${batchPlan.id}',
          favoritesOnly: favoritesOnly,
          buildItem: () => _batchPlanCardItem(batchPlan),
        );
      }
      for (final preset in catalog.assemblyPresets) {
        if (stopVisiting) break;
        addCandidate(
          kind: _AssetKind.assemblyPreset,
          favoriteKey: StudioAssetFavoriteKeys.assemblyPreset(preset.id),
          favoritesOnly: favoritesOnly,
          buildItem: () => _assemblyPresetCardItem(preset),
        );
      }
    }

    if (_favoriteKeys.isEmpty) {
      visitCandidates();
    } else {
      visitCandidates(favoritesOnly: true);
      if (!stopVisiting) {
        visitCandidates(favoritesOnly: false);
      }
    }

    return _AssetDisplaySlice(
      items: List.unmodifiable(items),
      totalCount: summaryTotalCount ?? totalCount,
    );
  }

  int _visibleAssetTotal(StudioAssetCatalogSnapshot catalog) {
    return catalog.summary.totalAssetCount;
  }

  int? _lazyTotalCountForSelection(StudioAssetCatalogSnapshot catalog) {
    final summary = catalog.summary;
    return switch (_filter) {
      _AssetFilter.all => _visibleAssetTotal(catalog) - summary.batchPlanCount,
      _AssetFilter.character => summary.characterCount,
      _AssetFilter.outfit => summary.outfitCount,
      _AssetFilter.artistChain => summary.artistChainCount,
      _AssetFilter.recipe => summary.recipeCount,
      _AssetFilter.tag => summary.tagCount,
      _AssetFilter.codex => catalog.legacyCodexLoadedCount,
      _AssetFilter.inspiration => summary.inspirationCount,
      _AssetFilter.lora => summary.loraCount,
      _AssetFilter.workflow => summary.workflowCount,
      _AssetFilter.batchPlan => summary.batchPlanCount,
      _AssetFilter.assemblyPreset => summary.assemblyPresetCount,
    };
  }

  bool _matchesLazyDisplaySelection({
    required _AssetKind kind,
    bool isLegacyCodex = false,
  }) {
    final typeMatches = switch (_filter) {
      _AssetFilter.all => !isLegacyCodex && kind != _AssetKind.batchPlan,
      _AssetFilter.character => kind == _AssetKind.character && !isLegacyCodex,
      _AssetFilter.outfit => kind == _AssetKind.outfit && !isLegacyCodex,
      _AssetFilter.artistChain =>
        kind == _AssetKind.artistChain && !isLegacyCodex,
      _AssetFilter.recipe => kind == _AssetKind.recipe && !isLegacyCodex,
      _AssetFilter.tag => kind == _AssetKind.tag && !isLegacyCodex,
      _AssetFilter.codex => isLegacyCodex,
      _AssetFilter.inspiration =>
        kind == _AssetKind.inspiration && !isLegacyCodex,
      _AssetFilter.lora => kind == _AssetKind.lora && !isLegacyCodex,
      _AssetFilter.workflow => kind == _AssetKind.workflow && !isLegacyCodex,
      _AssetFilter.batchPlan => kind == _AssetKind.batchPlan && !isLegacyCodex,
      _AssetFilter.assemblyPreset =>
        kind == _AssetKind.assemblyPreset && !isLegacyCodex,
    };
    return typeMatches;
  }

  _AssetDisplayItem _compactCardItem({
    required String key,
    String? assetId,
    required _AssetKind kind,
    required IconData icon,
    required String typeLabel,
    required String title,
    required String summary,
    String meta = '',
    List<String> referencePaths = const [],
    String sourceType = '',
    CharacterEntry? character,
    CharacterEntry? outfitCharacter,
    WorkspaceOutfit? outfit,
    int? outfitIndex,
    ArtistChain? artistChain,
    Recipe? recipe,
    TagEntry? tag,
    InspirationEntry? inspiration,
    StudioScriptAssetFocus? scriptFocus,
  }) {
    return _AssetDisplayItem(
      key: key,
      assetId: assetId,
      kind: kind,
      icon: icon,
      typeLabel: typeLabel,
      title: title,
      summary: summary,
      meta: meta,
      referencePaths: referencePaths,
      sourceType: sourceType,
      character: character,
      outfitCharacter: outfitCharacter,
      outfit: outfit,
      outfitIndex: outfitIndex,
      artistChain: artistChain,
      recipe: recipe,
      tag: tag,
      inspiration: inspiration,
      scriptFocus: scriptFocus,
      onSend: null,
    );
  }

  _AssetDisplayItem _characterCardItem(CharacterEntry character) {
    return _compactCardItem(
      key: 'character-${character.id}',
      kind: _AssetKind.character,
      icon: Icons.person_outline,
      typeLabel: 'Character',
      title: character.name,
      summary: character.traits.frontFull,
      character: character,
      scriptFocus: StudioScriptAssetFocus.character(
        characterId: character.id,
      ),
      meta: _compactMeta([
        'ID ${character.id}',
        _sourceLabel(character.source),
      ]),
      referencePaths: character.imageRefs,
    );
  }

  _AssetDisplayItem _outfitCardItem(
    CharacterEntry character,
    int outfitIndex,
    WorkspaceOutfit outfit,
  ) {
    return _compactCardItem(
      key: _outfitDisplayKey(character, outfitIndex, outfit),
      kind: _AssetKind.outfit,
      icon: Icons.checkroom_outlined,
      typeLabel: 'Outfit',
      title: '${character.name} / ${outfit.name}',
      summary: _outfitPrompt(outfit),
      outfitCharacter: character,
      outfit: outfit,
      outfitIndex: outfitIndex,
      scriptFocus: StudioScriptAssetFocus.outfit(
        characterId: character.id,
        outfitId: outfit.id,
      ),
      meta: _compactMeta([
        character.name,
        'ID ${outfit.id}',
      ]),
      referencePaths: outfit.imageRefs,
    );
  }

  _AssetDisplayItem _artistChainCardItem(ArtistChain artistChain) {
    return _compactCardItem(
      key: 'artist-${artistChain.id}',
      kind: _AssetKind.artistChain,
      icon: Icons.brush_outlined,
      typeLabel: 'Artist',
      title: artistChain.name,
      summary: _artistChainPrompt(artistChain),
      artistChain: artistChain,
      meta: _compactMeta([
        'ID ${artistChain.id}',
        _sourceLabel(artistChain.source),
      ]),
      referencePaths: artistChain.imageRefs,
      scriptFocus: StudioScriptAssetFocus.artistChain(
        artistChainId: artistChain.id,
      ),
    );
  }

  _AssetDisplayItem _recipeCardItem(Recipe recipe) {
    return _compactCardItem(
      key: 'recipe-${recipe.block}-${recipe.id}',
      kind: _AssetKind.recipe,
      icon: Icons.auto_awesome_mosaic_outlined,
      typeLabel: '配方',
      title: recipe.name,
      summary: recipe.tags.trim().isNotEmpty
          ? recipe.tags
          : _sectionPrompt(recipe.variants),
      recipe: recipe,
      meta: _compactMeta([
        recipe.block,
        if (recipe.category.isNotEmpty) recipe.category,
        if (recipe.variants.isNotEmpty) '${recipe.variants.length} 个分区',
        'ID ${recipe.id}',
      ]),
      referencePaths: recipe.imageRefs,
    );
  }

  _AssetDisplayItem _tagCardItem(TagEntry tag) {
    return _compactCardItem(
      key: 'tag-${tag.block}-${tag.id}',
      kind: _AssetKind.tag,
      icon: Icons.local_offer_outlined,
      typeLabel: 'Tag',
      title: tag.zh.isEmpty ? tag.tag : tag.zh,
      summary:
          tag.tag.trim().isNotEmpty ? tag.tag : _sectionPrompt(tag.sections),
      tag: tag,
      meta: _compactMeta([
        tag.block,
        if (tag.category.isNotEmpty) tag.category,
        if (tag.sections.isNotEmpty) '${tag.sections.length} 个分区',
        'ID ${tag.id}',
      ]),
      referencePaths: tag.imageRefs,
    );
  }

  _AssetDisplayItem _inspirationCardItem(InspirationEntry inspiration) {
    return _compactCardItem(
      key: 'inspiration-${inspiration.id}',
      kind: _AssetKind.inspiration,
      icon: Icons.auto_awesome_outlined,
      typeLabel: StudioAssetCatalogService.isCodexSourceType(
        inspiration.source.type,
      )
          ? 'Codex'
          : 'Inspiration',
      title: inspiration.name,
      summary: _inspirationSummary(inspiration),
      meta: _compactMeta([
        'ID ${inspiration.id}',
        if (inspiration.sourceCategoryPath.isNotEmpty)
          inspiration.sourceCategoryPath.last,
        if (inspiration.variants.isNotEmpty)
          '${inspiration.variants.length} variants',
        _sourceLabel(inspiration.source),
      ]),
      inspiration: inspiration,
      referencePaths: inspiration.imageRefs,
      sourceType: inspiration.source.type,
    );
  }

  _AssetDisplayItem _loraCardItem(LoraEntry lora) {
    return _compactCardItem(
      key: 'lora-${lora.id}',
      kind: _AssetKind.lora,
      icon: Icons.tune_outlined,
      typeLabel: 'LoRA',
      title: lora.name,
      summary: _loraSummary(lora),
      meta: _compactMeta([
        'ID ${lora.id}',
        _sourceLabel(lora.source),
      ]),
      referencePaths: lora.imageRefs,
    );
  }

  _AssetDisplayItem _workflowCardItem(WorkflowEntry workflow) {
    return _compactCardItem(
      key: 'workflow-${workflow.id}',
      kind: _AssetKind.workflow,
      icon: Icons.account_tree_outlined,
      typeLabel: 'Workflow',
      title: workflow.name,
      summary: _workflowSummary(workflow),
      meta: _compactMeta([
        'ID ${workflow.id}',
        '${workflow.payload.length} payload keys',
        _sourceLabel(workflow.source),
      ]),
      referencePaths: workflow.imageRefs,
    );
  }

  _AssetDisplayItem _batchPlanCardItem(BatchPlan batchPlan) {
    return _compactCardItem(
      key: 'batch-plan-${batchPlan.id}',
      kind: _AssetKind.batchPlan,
      icon: Icons.playlist_play_outlined,
      typeLabel: 'Batch Plan',
      title: batchPlan.name,
      summary: _batchPlanSummary(batchPlan),
      meta: _compactMeta([
        'ID ${batchPlan.id}',
        '${batchPlan.items.length} items',
      ]),
    );
  }

  _AssetDisplayItem _assemblyPresetCardItem(AssemblyPresetEntry preset) {
    return _compactCardItem(
      key: 'assembly-preset-${preset.id}',
      kind: _AssetKind.assemblyPreset,
      icon: Icons.layers_outlined,
      typeLabel: 'Assembly Preset',
      title: preset.name,
      summary: _assemblyPresetSummary(preset),
      meta: _compactMeta([
        'ID ${preset.id}',
        '${preset.payload.length} payload keys',
        _sourceLabel(preset.source),
      ]),
      referencePaths: preset.imageRefs,
    );
  }

  List<_AssetDisplayItem> _buildDisplayItems(
    StudioAssetCatalogSnapshot catalog,
  ) {
    return [
      for (final character in catalog.characters)
        _AssetDisplayItem(
          key: 'character-${character.id}',
          kind: _AssetKind.character,
          icon: Icons.person_outline,
          typeLabel: '角色',
          title: character.name,
          summary: character.traits.frontFull,
          character: character,
          scriptFocus: StudioScriptAssetFocus.character(
            characterId: character.id,
          ),
          meta: _compactMeta([
            'ID ${character.id}',
            _sourceLabel(character.source),
          ]),
          referencePaths: character.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('类型', '角色'),
            _AssetDetailLine('ID', character.id),
            _AssetDetailLine('Prompt', character.traits.frontFull),
            if ((character.traits.frontUpper ?? '').isNotEmpty)
              _AssetDetailLine('上身', character.traits.frontUpper!),
            if ((character.traits.frontLower ?? '').isNotEmpty)
              _AssetDetailLine('下身', character.traits.frontLower!),
            _AssetDetailLine('来源类型', character.source.type),
            if (character.source.id != null)
              _AssetDetailLine('来源 ID', character.source.id!),
            if (character.source.path != null)
              _AssetDetailLine('来源路径', character.source.path!),
            if (character.note.isNotEmpty)
              _AssetDetailLine('备注', character.note),
          ]),
          onSend: () => _sendCharacterAsset(character),
          onEdit: widget.saveCharacters == null
              ? null
              : () => _showCharacterEditor(
                    catalog,
                    initialExisting: character,
                  ),
          onDuplicateCharacter: widget.saveCharacters == null
              ? null
              : () => _duplicateCharacter(catalog, character),
          onAddOutfit: widget.saveCharacters == null
              ? null
              : () => _showOutfitEditor(catalog, character),
          onEditOutfit: widget.saveCharacters == null
              ? null
              : (outfit) => _showOutfitEditor(
                    catalog,
                    character,
                    initialExisting: outfit,
                  ),
          onDuplicateOutfit: widget.saveCharacters == null
              ? null
              : (outfit) => _duplicateOutfit(catalog, character, outfit),
          onDeleteOutfit: widget.saveCharacters == null
              ? null
              : (outfit) => _confirmDeleteAsset(
                    onConfirm: () => _deleteOutfit(catalog, character, outfit),
                  ),
          onDeleteOutfitPreview: widget.saveCharacters == null
              ? null
              : (outfitIndex, outfit) => _deleteOutfitPreview(
                    catalog,
                    character,
                    outfitIndex,
                    outfit,
                  ),
          onDelete: widget.saveCharacters == null
              ? null
              : () => _confirmDeleteAsset(
                    onConfirm: () => _deleteCharacter(catalog, character),
                  ),
          onDeletePreview: widget.saveCharacters == null
              ? null
              : () => _deleteCharacterPreview(catalog, character),
          onPromptChanged: widget.saveCharacters == null
              ? null
              : (prompt) => _saveCharacterPrompt(
                    catalog,
                    character,
                    prompt,
                  ),
          onCharacterPromptFieldChanged: widget.saveCharacters == null
              ? null
              : (field, prompt) => _saveCharacterPromptField(
                    catalog,
                    character,
                    field,
                    prompt,
                  ),
          onOutfitPromptChanged: widget.saveCharacters == null
              ? null
              : (outfitIndex, prompt) => _saveOutfitPrompt(
                    catalog,
                    character,
                    outfitIndex,
                    prompt,
                  ),
          onOutfitPromptFieldChanged: widget.saveCharacters == null
              ? null
              : (outfitIndex, field, prompt) => _saveOutfitPromptField(
                    catalog,
                    character,
                    outfitIndex,
                    field,
                    prompt,
                  ),
        ),
      for (final character in catalog.characters)
        for (final entry in character.outfits.indexed)
          _AssetDisplayItem(
            key: _outfitDisplayKey(character, entry.$1, entry.$2),
            kind: _AssetKind.outfit,
            icon: Icons.checkroom_outlined,
            typeLabel: 'Outfit',
            title: '${character.name} / ${entry.$2.name}',
            summary: _outfitPrompt(entry.$2),
            outfitCharacter: character,
            outfit: entry.$2,
            outfitIndex: entry.$1,
            scriptFocus: StudioScriptAssetFocus.outfit(
              characterId: character.id,
              outfitId: entry.$2.id,
            ),
            meta: _compactMeta([
              character.name,
              'ID ${entry.$2.id}',
            ]),
            referencePaths: entry.$2.imageRefs,
            detailsBuilder: () => _details([
              const _AssetDetailLine('类型', 'Outfit'),
              _AssetDetailLine('角色', character.name),
              _AssetDetailLine('角色 ID', character.id),
              _AssetDetailLine('Outfit ID', entry.$2.id),
              _AssetDetailLine('Prompt', _outfitPrompt(entry.$2)),
              if ((entry.$2.tags.frontUpper ?? '').isNotEmpty)
                _AssetDetailLine('上半身', entry.$2.tags.frontUpper!),
              if ((entry.$2.tags.frontLower ?? '').isNotEmpty)
                _AssetDetailLine('下半身', entry.$2.tags.frontLower!),
              if (entry.$2.negativePrompt.isNotEmpty)
                _AssetDetailLine('Negative', entry.$2.negativePrompt),
              if (entry.$2.note.isNotEmpty)
                _AssetDetailLine('备注', entry.$2.note),
            ]),
            onSend: () => _sendAsset(
              context,
              () => widget.workbenchAssetService.appendOutfit(
                character,
                entry.$2,
              ),
            ),
            onEdit: widget.saveCharacters == null
                ? null
                : () => _showOutfitEditor(
                      catalog,
                      character,
                      initialExisting: entry.$2,
                    ),
            onDelete: widget.saveCharacters == null
                ? null
                : () => _confirmDeleteAsset(
                      onConfirm: () =>
                          _deleteOutfit(catalog, character, entry.$2),
                    ),
            onDeletePreview: widget.saveCharacters == null
                ? null
                : () => _deleteOutfitPreview(
                      catalog,
                      character,
                      entry.$1,
                      entry.$2,
                    ),
            onOutfitPromptChanged: widget.saveCharacters == null
                ? null
                : (_, prompt) => _saveOutfitPrompt(
                      catalog,
                      character,
                      entry.$1,
                      prompt,
                    ),
            onOutfitPromptFieldChanged: widget.saveCharacters == null
                ? null
                : (_, field, prompt) => _saveOutfitPromptField(
                      catalog,
                      character,
                      entry.$1,
                      field,
                      prompt,
                    ),
          ),
      for (final artistChain in catalog.artistChains)
        _AssetDisplayItem(
          key: 'artist-${artistChain.id}',
          kind: _AssetKind.artistChain,
          icon: Icons.brush_outlined,
          typeLabel: '画师串',
          title: artistChain.name,
          summary: _artistChainPrompt(artistChain),
          artistChain: artistChain,
          meta: _compactMeta([
            'ID ${artistChain.id}',
            _sourceLabel(artistChain.source),
          ]),
          referencePaths: artistChain.imageRefs,
          scriptFocus: StudioScriptAssetFocus.artistChain(
            artistChainId: artistChain.id,
          ),
          detailsBuilder: () => _details([
            const _AssetDetailLine('类型', '画师串'),
            _AssetDetailLine('ID', artistChain.id),
            _AssetDetailLine('Prompt', _artistChainPrompt(artistChain)),
            if (_shouldShowArtistChainTags(artistChain))
              _AssetDetailLine('Tags', artistChain.tags.join(', ')),
            if (artistChain.styleTags.isNotEmpty)
              _AssetDetailLine(
                'Style Tags',
                artistChain.styleTags.join(', '),
              ),
            if (artistChain.translations.isNotEmpty)
              _AssetDetailLine(
                '翻译',
                artistChain.translations.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join(', '),
              ),
            if (artistChain.note.isNotEmpty)
              _AssetDetailLine('备注', artistChain.note),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendArtistChain(artistChain),
          ),
          onEdit: widget.saveArtistChains == null
              ? null
              : () => _showArtistChainEditor(catalog, existing: artistChain),
          onDelete: widget.saveArtistChains == null
              ? null
              : () => _confirmDeleteAsset(
                    onConfirm: () => _deleteArtistChain(catalog, artistChain),
                  ),
          onDeletePreview: widget.saveArtistChains == null
              ? null
              : () => _deleteArtistChainPreview(catalog, artistChain),
          onLoadVibes: widget.loadVibes,
          onImportVibes: widget.importVibes,
          onSaveArtistChain: widget.saveArtistChains == null
              ? null
              : (updated) => _saveArtistChain(catalog, updated),
          onDuplicateArtistChain: widget.saveArtistChains == null
              ? null
              : () => _duplicateArtistChain(catalog, artistChain),
          onRenameArtistChain: widget.saveArtistChains == null
              ? null
              : (name) => _renameArtistChain(catalog, artistChain, name),
          onPromptChanged: widget.saveArtistChains == null
              ? null
              : (prompt) => _saveArtistChainPrompt(
                    catalog,
                    artistChain,
                    prompt,
                  ),
        ),
      for (final recipe in catalog.recipes)
        _AssetDisplayItem(
          key: 'recipe-${recipe.block}-${recipe.id}',
          kind: _AssetKind.recipe,
          icon: Icons.auto_awesome_mosaic_outlined,
          typeLabel: '配方',
          title: recipe.name,
          summary: recipe.tags.trim().isNotEmpty
              ? recipe.tags
              : _sectionPrompt(recipe.variants),
          recipe: recipe,
          meta: _compactMeta([
            recipe.block,
            if (recipe.category.isNotEmpty) recipe.category,
            if (recipe.variants.isNotEmpty) '${recipe.variants.length} 个分区',
            'ID ${recipe.id}',
          ]),
          referencePaths: recipe.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('类型', '配方'),
            _AssetDetailLine('ID', recipe.id),
            _AssetDetailLine('分类', recipe.block),
            _AssetDetailLine('Prompt', recipe.tags),
            if (recipe.variants.isNotEmpty)
              _AssetDetailLine(
                '分区',
                recipe.variants.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
              ),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendRecipe(recipe),
          ),
          onEdit: widget.saveRecipes == null
              ? null
              : () => _showRecipeEditor(catalog, existing: recipe),
          onDelete: widget.saveRecipes == null
              ? null
              : () => _confirmDeleteAsset(
                    onConfirm: () => _deleteRecipe(catalog, recipe),
                  ),
        ),
      for (final tag in catalog.tags)
        _AssetDisplayItem(
          key: 'tag-${tag.block}-${tag.id}',
          kind: _AssetKind.tag,
          icon: Icons.local_offer_outlined,
          typeLabel: 'Tag',
          title: tag.zh.isEmpty ? tag.tag : tag.zh,
          summary: tag.tag.trim().isNotEmpty
              ? tag.tag
              : _sectionPrompt(tag.sections),
          tag: tag,
          meta: _compactMeta([
            tag.block,
            if (tag.category.isNotEmpty) tag.category,
            if (tag.sections.isNotEmpty) '${tag.sections.length} 个分区',
            'ID ${tag.id}',
          ]),
          referencePaths: tag.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('类型', 'Tag'),
            _AssetDetailLine('ID', tag.id),
            _AssetDetailLine('分类', tag.block),
            _AssetDetailLine('Prompt', tag.tag),
            if (tag.sections.isNotEmpty)
              _AssetDetailLine(
                '分区',
                tag.sections.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
              ),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendTag(tag),
          ),
          onEdit: widget.saveTags == null
              ? null
              : () => _showTagEditor(catalog, existing: tag),
          onDelete: widget.saveTags == null
              ? null
              : () => _confirmDeleteAsset(
                    onConfirm: () => _deleteTag(catalog, tag),
                  ),
        ),
      for (final inspiration in catalog.inspirations)
        _AssetDisplayItem(
          key: 'inspiration-${inspiration.id}',
          kind: _AssetKind.inspiration,
          icon: Icons.auto_awesome_outlined,
          typeLabel: StudioAssetCatalogService.isCodexSourceType(
            inspiration.source.type,
          )
              ? '法典'
              : 'Inspiration',
          title: inspiration.name,
          summary: _inspirationSummary(inspiration),
          meta: _compactMeta([
            'ID ${inspiration.id}',
            if (inspiration.sourceCategoryPath.isNotEmpty)
              inspiration.sourceCategoryPath.last,
            if (inspiration.variants.isNotEmpty)
              '${inspiration.variants.length} 个版本',
            _sourceLabel(inspiration.source),
          ]),
          inspiration: inspiration,
          referencePaths: inspiration.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('Type', 'Inspiration'),
            _AssetDetailLine('ID', inspiration.id),
            if (inspiration.sourceCategoryPath.isNotEmpty)
              _AssetDetailLine(
                'Source Category',
                inspiration.sourceCategoryPath.join(' / '),
              ),
            if (inspiration.prompt.isNotEmpty)
              _AssetDetailLine('Prompt', inspiration.prompt),
            if (inspiration.negativePrompt.isNotEmpty)
              _AssetDetailLine('Negative Prompt', inspiration.negativePrompt),
            if (inspiration.variants.isNotEmpty)
              _AssetDetailLine(
                'Variants',
                inspiration.variants.map((variant) => variant.name).join(', '),
              ),
            if (inspiration.tags.isNotEmpty)
              _AssetDetailLine('Tags', inspiration.tags.join(', ')),
            _AssetDetailLine('Source Type', inspiration.source.type),
            if (inspiration.source.id != null)
              _AssetDetailLine('Source ID', inspiration.source.id!),
            if (inspiration.source.path != null)
              _AssetDetailLine('Source Path', inspiration.source.path!),
            if (inspiration.note.isNotEmpty)
              _AssetDetailLine('Note', inspiration.note),
          ]),
          sourceType: inspiration.source.type,
          onSend: null,
        ),
      for (final lora in catalog.loras)
        _AssetDisplayItem(
          key: 'lora-${lora.id}',
          kind: _AssetKind.lora,
          icon: Icons.tune_outlined,
          typeLabel: 'LoRA',
          title: lora.name,
          summary: _loraSummary(lora),
          meta: _compactMeta([
            'ID ${lora.id}',
            _sourceLabel(lora.source),
          ]),
          referencePaths: lora.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('Type', 'LoRA'),
            _AssetDetailLine('ID', lora.id),
            if (lora.baseModel.isNotEmpty)
              _AssetDetailLine('Base Model', lora.baseModel),
            if (lora.triggerWords.isNotEmpty)
              _AssetDetailLine('Trigger Words', lora.triggerWords.join(', ')),
            if (lora.defaultStrength != null)
              _AssetDetailLine(
                'Default Strength',
                lora.defaultStrength!.toStringAsFixed(2),
              ),
            _AssetDetailLine('Source Type', lora.source.type),
            if (lora.source.id != null)
              _AssetDetailLine('Source ID', lora.source.id!),
            if (lora.source.path != null)
              _AssetDetailLine('Source Path', lora.source.path!),
            if (lora.note.isNotEmpty) _AssetDetailLine('Note', lora.note),
          ]),
          onSend: null,
        ),
      for (final workflow in catalog.workflows)
        _AssetDisplayItem(
          key: 'workflow-${workflow.id}',
          kind: _AssetKind.workflow,
          icon: Icons.account_tree_outlined,
          typeLabel: 'Workflow',
          title: workflow.name,
          summary: _workflowSummary(workflow),
          meta: _compactMeta([
            'ID ${workflow.id}',
            '${workflow.payload.length} payload keys',
            _sourceLabel(workflow.source),
          ]),
          referencePaths: workflow.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('Type', 'Workflow'),
            _AssetDetailLine('ID', workflow.id),
            if (workflow.summary.isNotEmpty)
              _AssetDetailLine('Summary', workflow.summary),
            if (workflow.payload.isNotEmpty)
              _AssetDetailLine('Payload', _mapPreview(workflow.payload)),
            _AssetDetailLine('Source Type', workflow.source.type),
            if (workflow.source.id != null)
              _AssetDetailLine('Source ID', workflow.source.id!),
            if (workflow.source.path != null)
              _AssetDetailLine('Source Path', workflow.source.path!),
            if (workflow.note.isNotEmpty)
              _AssetDetailLine('Note', workflow.note),
          ]),
          onSend: null,
        ),
      for (final batchPlan in catalog.batchPlans)
        _AssetDisplayItem(
          key: 'batch-plan-${batchPlan.id}',
          kind: _AssetKind.batchPlan,
          icon: Icons.playlist_play_outlined,
          typeLabel: 'Batch Plan',
          title: batchPlan.name,
          summary: _batchPlanSummary(batchPlan),
          meta: _compactMeta([
            'ID ${batchPlan.id}',
            '${batchPlan.items.length} items',
          ]),
          detailsBuilder: () => _details([
            const _AssetDetailLine('Type', 'Batch Plan'),
            _AssetDetailLine('ID', batchPlan.id),
            _AssetDetailLine('Items', batchPlan.items.length.toString()),
            if (batchPlan.statusSnapshot.isNotEmpty)
              _AssetDetailLine('Status', _mapPreview(batchPlan.statusSnapshot)),
            _AssetDetailLine(
                'Created At', batchPlan.createdAt.toIso8601String()),
            _AssetDetailLine(
                'Updated At', batchPlan.updatedAt.toIso8601String()),
          ]),
          referencePaths: const [],
          onSend: null,
        ),
      for (final preset in catalog.assemblyPresets)
        _AssetDisplayItem(
          key: 'assembly-preset-${preset.id}',
          kind: _AssetKind.assemblyPreset,
          icon: Icons.layers_outlined,
          typeLabel: 'Assembly Preset',
          title: preset.name,
          summary: _assemblyPresetSummary(preset),
          meta: _compactMeta([
            'ID ${preset.id}',
            '${preset.payload.length} payload keys',
            _sourceLabel(preset.source),
          ]),
          referencePaths: preset.imageRefs,
          detailsBuilder: () => _details([
            const _AssetDetailLine('Type', 'Assembly Preset'),
            _AssetDetailLine('ID', preset.id),
            if (preset.summary.isNotEmpty)
              _AssetDetailLine('Summary', preset.summary),
            if (preset.payload.isNotEmpty)
              _AssetDetailLine('Payload', _mapPreview(preset.payload)),
            _AssetDetailLine('Source Type', preset.source.type),
            if (preset.source.id != null)
              _AssetDetailLine('Source ID', preset.source.id!),
            if (preset.source.path != null)
              _AssetDetailLine('Source Path', preset.source.path!),
            if (preset.note.isNotEmpty) _AssetDetailLine('Note', preset.note),
          ]),
          onSend: null,
        ),
    ];
  }

  Map<String, List<String>> _resolveCharacterOutfitPreviewPaths(
    CharacterEntry character,
  ) {
    return {
      for (final entry in character.outfits.indexed)
        _outfitSlotKey(character.id, entry.$1, entry.$2): _resolvePreviewPaths(
          _AssetKind.outfit,
          _outfitPreviewCacheKey(character.id, entry.$1, entry.$2),
          entry.$2.imageRefs,
        ),
    };
  }

  String? _resolvePreviewPath(
    _AssetKind kind,
    String key,
    List<String> refs,
  ) {
    final paths = _resolvePreviewPaths(kind, key, refs);
    return paths.isEmpty ? null : paths.first;
  }

  List<String> _resolvePreviewPaths(
    _AssetKind kind,
    String key,
    List<String> refs,
  ) {
    if (refs.isEmpty) return const [];
    final cacheKey = _previewPathCacheKey(key, refs);
    return _resolvedPreviewPathsCache.putIfAbsent(cacheKey, () {
      final paths = <String>[];
      final seen = <String>{};
      for (final ref in refs) {
        final resolved = widget.catalogService.resolveImagePath([ref]);
        if (resolved == null || !seen.add(resolved)) continue;
        paths.add(resolved);
      }
      return List.unmodifiable(paths);
    });
  }

  String _previewPathCacheKey(String key, List<String> refs) {
    return [
      key,
      for (final ref in refs) ref.trim(),
    ].join('\u001f');
  }

  void _removePreviewPathCacheFor(String key) {
    _resolvedPreviewPathsCache.removeWhere(
      (cacheKey, _) => cacheKey == key || cacheKey.startsWith('$key\u001f'),
    );
    _previewResolveQueuedKeys.removeWhere(
      (cacheKey) => cacheKey == key || cacheKey.startsWith('$key\u001f'),
    );
  }

  List<_AssetDisplayItem> _filterItems(List<_AssetDisplayItem> items) {
    final query = asset_query.AssetLibraryQuery(
      query: _query,
      filter: _assetQueryFilterFor(_filter),
      favoriteKeys: _favoriteKeys,
    );
    return query
        .filterItems([
          for (final item in items)
            asset_query.AssetLibraryQueryItem(
              value: item,
              kind: _assetQueryKindFor(item.kind),
              isLegacyCodex: item.isLegacyCodex,
              favoriteKey: item.favoriteKey,
              matchesQuery: item.matches,
            ),
        ])
        .map((item) => item.value)
        .toList(growable: false);
  }

  Future<void> _loadFavorites() async {
    final keys = await widget.catalogService.loadAssetFavoriteKeys();
    if (!mounted) return;
    setState(() => _favoriteKeys = keys);
  }

  Future<void> _toggleFavorite(_AssetDisplayItem item) async {
    final next = !_favoriteKeys.contains(item.favoriteKey);
    await widget.catalogService.setAssetFavorite(item.favoriteKey, next);
    if (!mounted) return;
    setState(() {
      final keys = {..._favoriteKeys};
      if (next) {
        keys.add(item.favoriteKey);
      } else {
        keys.remove(item.favoriteKey);
      }
      _favoriteKeys = keys;
    });
  }

  void _copyAssetPrompt(_AssetDisplayItem item) {
    Clipboard.setData(ClipboardData(text: item.copyText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制提示词')),
    );
  }

  Future<void> _generatePreview(_AssetDisplayItem item) async {
    final service = widget.previewGenerationService;
    if (service == null) return;
    try {
      final options = await _previewGenerationOptions(item);
      if (!mounted || options == null) return;
      final decision = await showDialog<_PreviewGenerationDecision>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _PreviewGenerationDialog(
          assetTitle: item.title,
          generate: () => _generatePreviewPath(service, item, options),
        ),
      );
      if (!mounted || decision == null) return;
      if (!decision.keep) {
        await _discardGeneratedPreview(service, item, decision.previewPath);
      }
      await _refreshPreviewAsset(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('预览图生成失败: $error')),
      );
    }
  }

  Future<StudioAssetPreviewGenerationOptions?> _previewGenerationOptions(
    _AssetDisplayItem item,
  ) {
    if (item.kind != _AssetKind.character &&
        item.kind != _AssetKind.artistChain &&
        item.kind != _AssetKind.outfit) {
      return Future.value(const StudioAssetPreviewGenerationOptions());
    }
    return showDialog<StudioAssetPreviewGenerationOptions>(
      context: context,
      builder: (context) => _PreviewGenerationOptionsDialog(
        assetTitle: item.title,
        showArtistSelector: item.kind == _AssetKind.character,
        showCustomPrompt: item.kind == _AssetKind.character ||
            item.kind == _AssetKind.artistChain,
        artistChains: _previewOptionArtistChains(),
      ),
    );
  }

  List<ArtistChain> _previewOptionArtistChains() {
    return _localCatalog?.artistChains ??
        _displayItemsCatalog?.artistChains ??
        const [];
  }

  Future<String> _generatePreviewPath(
    StudioAssetPreviewGenerationService service,
    _AssetDisplayItem item,
    StudioAssetPreviewGenerationOptions options,
  ) {
    if (item.kind == _AssetKind.outfit &&
        item.outfitCharacter != null &&
        item.outfit != null) {
      return service.generateOutfitPreview(
        item.outfitCharacter!.id,
        item.outfit!.id,
        options: options,
      );
    }
    return switch (item.kind) {
      _AssetKind.character => service.generateCharacterPreview(
          item.assetId,
          options: options,
        ),
      _AssetKind.artistChain => service.generateArtistChainPreview(
          item.assetId,
          options: options,
        ),
      _AssetKind.outfit ||
      _AssetKind.recipe ||
      _AssetKind.tag ||
      _AssetKind.inspiration ||
      _AssetKind.lora ||
      _AssetKind.workflow ||
      _AssetKind.batchPlan ||
      _AssetKind.assemblyPreset =>
        Future<String>.error(
          StateError('Unsupported asset preview kind: ${item.kind.name}'),
        ),
    };
  }

  Future<void> _discardGeneratedPreview(
    StudioAssetPreviewGenerationService service,
    _AssetDisplayItem item,
    String previewPath,
  ) {
    if (item.kind == _AssetKind.outfit &&
        item.outfitCharacter != null &&
        item.outfit != null) {
      return service.discardOutfitPreview(
        item.outfitCharacter!.id,
        item.outfit!.id,
        previewPath,
      );
    }
    return switch (item.kind) {
      _AssetKind.character =>
        service.discardCharacterPreview(item.assetId, previewPath),
      _AssetKind.artistChain =>
        service.discardArtistChainPreview(item.assetId, previewPath),
      _AssetKind.outfit ||
      _AssetKind.recipe ||
      _AssetKind.tag ||
      _AssetKind.inspiration ||
      _AssetKind.lora ||
      _AssetKind.workflow ||
      _AssetKind.batchPlan ||
      _AssetKind.assemblyPreset =>
        Future<void>.value(),
    };
  }

  Future<void> _refreshPreviewAsset(_AssetDisplayItem item) async {
    final refreshed = await widget.catalogService.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _clearPreviewResolutionState();
      _clearDisplayItemsCache();
      _localCatalog = refreshed;
      _snapshotFuture = Future.value(refreshed);
      _selectedAsset = _displayItemsFor(refreshed)
          .where((candidate) => candidate.key == item.key)
          .cast<_AssetDisplayItem?>()
          .firstWhere((candidate) => candidate != null, orElse: () => null);
    });
  }

  void _sendAssetToScript(_AssetDisplayItem item) {
    final focus = item.scriptFocus;
    if (focus == null) return;
    widget.onSendToScript?.call(focus);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已发送到剧本素材抽屉')),
    );
  }

  bool _shouldShowArtistChainTags(ArtistChain artistChain) {
    if (artistChain.tags.isEmpty) return false;
    final promptTags = _promptTags(_artistChainPrompt(artistChain))
        .map((tag) => tag.toLowerCase())
        .toList(growable: false);
    final explicitTags = artistChain.tags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (promptTags.length != explicitTags.length) return true;
    for (var index = 0; index < promptTags.length; index += 1) {
      if (promptTags[index] != explicitTags[index]) return true;
    }
    return false;
  }

  List<String> _promptTags(String prompt) {
    return prompt
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _identityPromptTags(String prompt) {
    return _promptTags(prompt)
        .where((tag) => !_isCharacterCountTag(tag))
        .toList(growable: false);
  }

  bool _isCharacterCountTag(String tag) {
    final value = tag
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\s]+'), '_')
        .replaceAll(RegExp(r'^-?\d+(?:\.\d+)?::\s*'), '')
        .replaceAll(RegExp(r'\s*::-?\d+(?:\.\d+)?$'), '');
    return RegExp(
      r'^(\d+(?:girls?|boys?|males?|females?)|solo|multiple_girls|multiple_boys)$',
    ).hasMatch(value);
  }

  String _manualId(String prefix, String text, Iterable<String> existingIds) {
    final slug = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base =
        '$prefix-${slug.isEmpty ? DateTime.now().millisecondsSinceEpoch : slug}';
    var id = base;
    var suffix = 2;
    final used = existingIds.toSet();
    while (used.contains(id)) {
      id = '$base-$suffix';
      suffix += 1;
    }
    return id;
  }

  String _promptCategoryId(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001f]+'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  }

  Future<void> _showPromptCategoryManager(
    StudioAssetCatalogSnapshot catalog,
  ) async {
    final saveCategories = widget.savePromptAssetCategories;
    if (saveCategories == null) return;
    final result = await showDialog<List<PromptAssetCategory>>(
      context: context,
      builder: (dialogContext) => _PromptCategoryManagerDialog(
        initialCategories: catalog.promptAssetCategories,
        normalizeId: _promptCategoryId,
      ),
    );
    if (result == null) return;
    await saveCategories(result);
    widget.onPromptAssetsChanged?.call();
    if (!mounted) return;
    setState(() {
      _localCatalog = _snapshotWith(
        catalog,
        promptAssetCategories: result,
      );
    });
  }

  StudioAssetCatalogSnapshot _snapshotWith(
    StudioAssetCatalogSnapshot catalog, {
    List<CharacterEntry>? characters,
    List<ArtistChain>? artistChains,
    List<Recipe>? recipes,
    List<TagEntry>? tags,
    List<PromptAssetCategory>? promptAssetCategories,
  }) {
    final nextCharacters = characters ?? catalog.characters;
    final nextOutfits =
        characters == null ? catalog.outfits : _outfitsFrom(nextCharacters);
    final nextArtistChains = artistChains ?? catalog.artistChains;
    final nextRecipes = recipes ?? catalog.recipes;
    final nextTags = tags ?? catalog.tags;
    return StudioAssetCatalogSnapshot(
      summary: _summaryWith(
        catalog,
        characters: nextCharacters,
        outfits: nextOutfits,
        artistChains: nextArtistChains,
        recipes: nextRecipes,
        tags: nextTags,
      ),
      promptAssetCategories:
          promptAssetCategories ?? catalog.promptAssetCategories,
      characters: nextCharacters,
      outfits: nextOutfits,
      artistChains: nextArtistChains,
      recipes: nextRecipes,
      tags: nextTags,
      inspirations: catalog.inspirations,
      loras: catalog.loras,
      workflows: catalog.workflows,
      batchPlans: catalog.batchPlans,
      assemblyPresets: catalog.assemblyPresets,
      legacyCodexTotalCount: catalog.legacyCodexTotalCount,
      legacyCodexLoadedCount: catalog.legacyCodexLoadedCount,
      legacyCodexCategoryCounts: catalog.legacyCodexCategoryCounts,
      legacyCodexAvailable: catalog.legacyCodexAvailable,
    );
  }

  StudioAssetCatalogSummary _summaryWith(
    StudioAssetCatalogSnapshot catalog, {
    required List<CharacterEntry> characters,
    required List<StudioOutfitAsset> outfits,
    required List<ArtistChain> artistChains,
    required List<Recipe> recipes,
    required List<TagEntry> tags,
  }) {
    return StudioAssetCatalogSummary(
      characterCount: characters.length,
      outfitCount: outfits.length,
      artistChainCount: artistChains.length,
      recipeCount: recipes.length,
      tagCount: tags.length,
      inspirationCount: catalog.summary.inspirationCount,
      loraCount: catalog.summary.loraCount,
      workflowCount: catalog.summary.workflowCount,
      batchPlanCount: catalog.summary.batchPlanCount,
      assemblyPresetCount: catalog.summary.assemblyPresetCount,
      recipeCountsByBlock: _countsByBlock(
        catalog.summary.recipeCountsByBlock.keys,
        recipes.map((entry) => entry.block),
      ),
      tagCountsByBlock: _countsByBlock(
        catalog.summary.tagCountsByBlock.keys,
        tags.map((entry) => entry.block),
      ),
    );
  }

  Map<String, int> _countsByBlock(
    Iterable<String> knownBlocks,
    Iterable<String> blocks,
  ) {
    final counts = {
      for (final block in knownBlocks) block: 0,
    };
    for (final block in blocks) {
      final normalized = block.trim();
      if (normalized.isEmpty) continue;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    return counts;
  }

  List<StudioOutfitAsset> _outfitsFrom(List<CharacterEntry> characters) {
    return [
      for (final character in characters)
        for (final outfit in character.outfits)
          StudioOutfitAsset(character: character, outfit: outfit),
    ];
  }

  String _copyId(String id, Iterable<String> existingIds) {
    final base = id.trim().isEmpty ? 'asset' : id.trim();
    final used = existingIds.toSet();
    var copyId = '$base-copy';
    var suffix = 2;
    while (used.contains(copyId)) {
      copyId = '$base-copy-$suffix';
      suffix += 1;
    }
    return copyId;
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  CharacterEntry _manualizedCharacter(CharacterEntry character) {
    if (character.source.type == 'manual') return character;
    return character.copyWith(source: const SourceRef(type: 'manual'));
  }

  _AssetDisplayItem? _displayItemByKey(
    StudioAssetCatalogSnapshot catalog,
    String key,
  ) {
    for (final item in _displayItemsFor(catalog)) {
      if (item.key == key) return item;
    }
    return null;
  }

  Future<void> _saveCharacters(
    StudioAssetCatalogSnapshot catalog,
    List<CharacterEntry> characters, {
    String? selectedCharacterId,
    bool clearSelection = false,
  }) async {
    await widget.saveCharacters?.call(characters);
    final snapshot = _snapshotWith(catalog, characters: characters);
    _characterMutationCatalog = snapshot;
    if (!mounted) return;
    setState(() {
      _localCatalog = snapshot;
      if (clearSelection) {
        _selectedAsset = null;
      } else if (selectedCharacterId != null) {
        _selectedAsset = _displayItemByKey(
          snapshot,
          'character-$selectedCharacterId',
        );
      }
    });
  }

  Future<void> _enqueueCharactersMutation(
    StudioAssetCatalogSnapshot fallbackCatalog,
    List<CharacterEntry>? Function(List<CharacterEntry> current) update, {
    String? Function()? selectedCharacterId,
    bool clearSelection = false,
  }) {
    final completed = Completer<void>();
    _pendingCharacterMutations += 1;
    _characterMutationTail = _characterMutationTail.then((_) async {
      try {
        final catalog =
            _characterMutationCatalog ?? _localCatalog ?? fallbackCatalog;
        final characters = update(catalog.characters);
        if (characters != null) {
          await _saveCharacters(
            catalog,
            characters,
            selectedCharacterId: selectedCharacterId?.call(),
            clearSelection: clearSelection,
          );
        }
        completed.complete();
      } catch (error, stackTrace) {
        completed.completeError(error, stackTrace);
      } finally {
        _pendingCharacterMutations -= 1;
        if (_pendingCharacterMutations == 0) {
          _characterMutationCatalog = null;
        }
      }
    });
    return completed.future;
  }

  Future<void> _enqueueCharacterMutation(
    StudioAssetCatalogSnapshot fallbackCatalog,
    String characterId,
    CharacterEntry? Function(CharacterEntry current) update,
  ) {
    return _enqueueCharactersMutation(
      fallbackCatalog,
      (characters) {
        CharacterEntry? current;
        for (final character in characters) {
          if (character.id == characterId) {
            current = character;
            break;
          }
        }
        if (current == null) return null;
        final updated = update(current);
        if (updated == null) return null;
        return [
          for (final character in characters)
            if (character.id == characterId) updated else character,
        ];
      },
      selectedCharacterId: () => characterId,
    );
  }

  Future<void> _saveCharacterPrompt(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    String prompt,
  ) async {
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (current) => AssetLibraryEditDocument.updateCharacterPrompt(
        current,
        prompt,
      ),
    );
  }

  Future<void> _saveCharacterPromptField(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    _CharacterPromptField field,
    String prompt,
  ) async {
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (current) => AssetLibraryEditDocument.updateCharacterPromptField(
        current,
        _editCharacterPromptFieldFor(field),
        prompt,
      ),
    );
  }

  Future<void> _saveOutfitPrompt(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    int outfitIndex,
    String prompt,
  ) async {
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (current) {
        if (outfitIndex < 0 || outfitIndex >= current.outfits.length) {
          return null;
        }
        final updatedOutfits = [...current.outfits]..[outfitIndex] =
              AssetLibraryEditDocument.updateOutfitPrompt(
            current.outfits[outfitIndex],
            prompt,
          );
        return _manualizedCharacter(
          current.copyWith(outfits: updatedOutfits),
        );
      },
    );
  }

  Future<void> _saveOutfitPromptField(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    int outfitIndex,
    _OutfitPromptField field,
    String prompt,
  ) async {
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (current) {
        if (outfitIndex < 0 || outfitIndex >= current.outfits.length) {
          return null;
        }
        final updatedOutfits = [...current.outfits]..[outfitIndex] =
              AssetLibraryEditDocument.updateOutfitPromptField(
            current.outfits[outfitIndex],
            _editOutfitPromptFieldFor(field),
            prompt,
          );
        return _manualizedCharacter(
          current.copyWith(outfits: updatedOutfits),
        );
      },
    );
  }

  Future<void> _showAssetCreator(StudioAssetCatalogSnapshot catalog) async {
    final kinds = _availableEditorKinds();
    if (kinds.isEmpty) return;

    final selected = await showDialog<_AssetEditorKind>(
      context: context,
      builder: (context) {
        Widget kindButton({
          required _AssetEditorKind kind,
          required IconData icon,
          required String label,
          required String description,
          required String key,
        }) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: ValueKey(key),
              icon: Icon(icon),
              label: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StudioTokens.textMuted,
                        ),
                  ),
                ],
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(kind),
            ),
          );
        }

        return AlertDialog(
          title: const Text('添加素材'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final kind in kinds) ...[
                  kindButton(
                    kind: kind,
                    icon: _assetEditorKindIcon(kind),
                    label: _assetEditorKindLabel(kind),
                    description: _assetEditorKindDescription(kind),
                    key: 'asset-editor-kind-${_assetEditorKindKey(kind)}',
                  ),
                  if (kind != kinds.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) return;

    switch (selected) {
      case _AssetEditorKind.character:
        await _showCharacterEditor(catalog);
        break;
      case _AssetEditorKind.artistChain:
        await _showArtistChainEditor(catalog);
        break;
      case _AssetEditorKind.recipe:
        await _showRecipeEditor(catalog);
        break;
      case _AssetEditorKind.tag:
        await _showTagEditor(catalog);
        break;
    }
  }

  List<_AssetEditorKind> _availableEditorKinds() {
    final kinds = <_AssetEditorKind>[
      if (widget.saveCharacters != null) _AssetEditorKind.character,
      if (widget.saveArtistChains != null) _AssetEditorKind.artistChain,
      if (widget.saveRecipes != null) _AssetEditorKind.recipe,
      if (widget.saveTags != null) _AssetEditorKind.tag,
    ];
    final preferred = switch (_filter) {
      _AssetFilter.character ||
      _AssetFilter.outfit =>
        _AssetEditorKind.character,
      _AssetFilter.artistChain => _AssetEditorKind.artistChain,
      _AssetFilter.recipe => _AssetEditorKind.recipe,
      _AssetFilter.tag => _AssetEditorKind.tag,
      _ => null,
    };
    if (preferred == null || !kinds.remove(preferred)) {
      return List.unmodifiable(kinds);
    }
    return List.unmodifiable([preferred, ...kinds]);
  }

  IconData _assetEditorKindIcon(_AssetEditorKind kind) {
    return switch (kind) {
      _AssetEditorKind.character => Icons.person_outline,
      _AssetEditorKind.artistChain => Icons.brush_outlined,
      _AssetEditorKind.recipe => Icons.auto_awesome_mosaic_outlined,
      _AssetEditorKind.tag => Icons.local_offer_outlined,
    };
  }

  String _assetEditorKindLabel(_AssetEditorKind kind) {
    return switch (kind) {
      _AssetEditorKind.character => '角色',
      _AssetEditorKind.artistChain => '画师串',
      _AssetEditorKind.recipe => '配方',
      _AssetEditorKind.tag => 'Tag',
    };
  }

  String _assetEditorKindDescription(_AssetEditorKind kind) {
    return switch (kind) {
      _AssetEditorKind.character => '身份、身体和默认服装按标签分区保存',
      _AssetEditorKind.artistChain => '保存画师串，可添加自定义分区',
      _AssetEditorKind.recipe => '保存到指定分类，可添加自定义分区',
      _AssetEditorKind.tag => '保存到指定分类，可添加自定义分区',
    };
  }

  String _assetEditorKindKey(_AssetEditorKind kind) {
    return switch (kind) {
      _AssetEditorKind.character => 'character',
      _AssetEditorKind.artistChain => 'artist-chain',
      _AssetEditorKind.recipe => 'recipe',
      _AssetEditorKind.tag => 'tag',
    };
  }

  Future<void> _showCharacterEditor(
    StudioAssetCatalogSnapshot initialCatalog, {
    CharacterEntry? initialExisting,
  }) async {
    await _characterMutationTail;
    if (!mounted) return;

    final catalog = _localCatalog ?? initialCatalog;
    CharacterEntry? existing;
    if (initialExisting != null) {
      for (final character in catalog.characters) {
        if (character.id == initialExisting.id) {
          existing = character;
          break;
        }
      }
      if (existing == null) return;
    }

    final nameController = TextEditingController(text: existing?.name ?? '');

    WorkspaceOutfit? defaultOutfitFor(CharacterEntry? character) {
      if (character == null || character.outfits.isEmpty) return null;
      final defaultId = character.defaultOutfitId?.trim();
      if (defaultId != null && defaultId.isNotEmpty) {
        for (final outfit in character.outfits) {
          if (outfit.id == defaultId) return outfit;
        }
      }
      for (final outfit in character.outfits) {
        if (outfit.id == 'default-outfit') return outfit;
      }
      return character.outfits.length == 1 ? character.outfits.single : null;
    }

    final existingDefaultOutfit = defaultOutfitFor(existing);
    final existingPartTags =
        existingDefaultOutfit?.partTags ?? const WorkspaceOutfitPartTags();
    var identityPrompt =
        _assetPromptFromTags(existing?.identityTags ?? const []);
    if (identityPrompt.trim().isEmpty) {
      identityPrompt = _assetPromptFromTags(
        _identityPromptTags(existing?.traits.frontFull ?? ''),
      );
    }
    var upperBodyPrompt = _assetPromptFromTags(existingPartTags.upperBodyTags);
    if (upperBodyPrompt.trim().isEmpty) {
      upperBodyPrompt = existing?.traits.frontUpper ?? '';
    }
    var lowerBodyPrompt = _assetPromptFromTags(existingPartTags.lowerBodyTags);
    if (lowerBodyPrompt.trim().isEmpty) {
      lowerBodyPrompt = existing?.traits.frontLower ?? '';
    }
    var upperClothingPrompt =
        _assetPromptFromTags(existingPartTags.upperClothingTags);
    if (upperClothingPrompt.trim().isEmpty) {
      upperClothingPrompt = existingDefaultOutfit?.tags.frontUpper ?? '';
    }
    var lowerClothingPrompt =
        _assetPromptFromTags(existingPartTags.lowerClothingTags);
    if (lowerClothingPrompt.trim().isEmpty) {
      lowerClothingPrompt = existingDefaultOutfit?.tags.frontLower ?? '';
    }

    final saved = await showDialog<CharacterEntry>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget tagEditor({
            required String key,
            required String label,
            required String value,
            required ValueChanged<String> onChanged,
          }) {
            return KeyedSubtree(
              key: ValueKey(key),
              child: PromptTagEditor(
                value: value,
                label: label,
                dense: true,
                showControls: false,
                inlineLabel: true,
                inlineLabelWidth: 58,
                initialGroupedLayout: false,
                emptyText: '暂无标签',
                onChanged: (nextValue) {
                  setDialogState(() {
                    onChanged(nextValue);
                  });
                },
              ),
            );
          }

          return AlertDialog(
            title: Text(existing == null ? '新建角色' : '编辑角色'),
            content: SizedBox(
              width: 660,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('asset-editor-name-field'),
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    tagEditor(
                      key: 'asset-character-editor-identity-tags-editor',
                      label: '身份',
                      value: identityPrompt,
                      onChanged: (value) => identityPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-character-editor-upper-body-tags-editor',
                      label: '上身',
                      value: upperBodyPrompt,
                      onChanged: (value) => upperBodyPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-character-editor-upper-clothing-tags-editor',
                      label: '上装',
                      value: upperClothingPrompt,
                      onChanged: (value) => upperClothingPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-character-editor-lower-body-tags-editor',
                      label: '下身',
                      value: lowerBodyPrompt,
                      onChanged: (value) => lowerBodyPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-character-editor-lower-clothing-tags-editor',
                      label: '下装',
                      value: lowerClothingPrompt,
                      onChanged: (value) => lowerClothingPrompt = value,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                key: const ValueKey('asset-editor-save'),
                onPressed: () {
                  final name = nameController.text.trim();
                  final anchorTags = existing?.anchorTags ?? const <String>[];
                  final identityTags = _identityPromptTags(
                    _assetPromptFromTags(
                      _assetPromptTagValuesFromValue(identityPrompt),
                    ),
                  );
                  final upperBodyTags =
                      _assetPromptTagValuesFromValue(upperBodyPrompt);
                  final upperClothingTags =
                      _assetPromptTagValuesFromValue(upperClothingPrompt);
                  final lowerBodyTags =
                      _assetPromptTagValuesFromValue(lowerBodyPrompt);
                  final lowerClothingTags =
                      _assetPromptTagValuesFromValue(lowerClothingPrompt);
                  final characterPrompt = _assetPromptFromTags([
                    ...identityTags,
                    ...upperBodyTags,
                    ...lowerBodyTags,
                  ]);
                  final completePrompt = _assetPromptFromTags([
                    ...identityTags,
                    ...upperBodyTags,
                    ...upperClothingTags,
                    ...lowerBodyTags,
                    ...lowerClothingTags,
                  ]);
                  if (name.isEmpty || completePrompt.isEmpty) return;

                  final base = existing ??
                      CharacterEntry(
                        id: _manualId(
                          'character',
                          name,
                          catalog.characters.map((entry) => entry.id),
                        ),
                        name: name,
                        traits: ViewVariantTexts(frontFull: characterPrompt),
                      );
                  final outfitPrompt = _assetPromptFromTags([
                    ...upperBodyTags,
                    ...upperClothingTags,
                    ...lowerBodyTags,
                    ...lowerClothingTags,
                  ]);
                  final outfits = [...base.outfits];
                  String? defaultOutfitId = base.defaultOutfitId;
                  if (outfitPrompt.isNotEmpty) {
                    defaultOutfitId =
                        (base.defaultOutfitId?.trim().isNotEmpty ?? false)
                            ? base.defaultOutfitId
                            : existingDefaultOutfit?.id ?? 'default-outfit';
                    final updatedDefaultOutfit = WorkspaceOutfit(
                      id: defaultOutfitId!,
                      name: existingDefaultOutfit?.name ?? '默认服装',
                      tags: ViewVariantTexts(
                        frontFull: outfitPrompt,
                        frontCowboy: existingDefaultOutfit?.tags.frontCowboy,
                        frontUpper: _blankToNull(
                          _assetPromptFromTags(upperClothingTags),
                        ),
                        frontLower: _blankToNull(
                          _assetPromptFromTags(lowerClothingTags),
                        ),
                        backFull: existingDefaultOutfit?.tags.backFull,
                        backCowboy: existingDefaultOutfit?.tags.backCowboy,
                        backUpper: existingDefaultOutfit?.tags.backUpper,
                        backLower: existingDefaultOutfit?.tags.backLower,
                      ),
                      partTags: WorkspaceOutfitPartTags(
                        upperBodyTags: upperBodyTags,
                        upperClothingTags: upperClothingTags,
                        lowerBodyTags: lowerBodyTags,
                        lowerClothingTags: lowerClothingTags,
                        weaponTags:
                            existingDefaultOutfit?.partTags.weaponTags ??
                                const [],
                      ),
                      imageRefs: existingDefaultOutfit?.imageRefs ?? const [],
                      negativePrompt:
                          existingDefaultOutfit?.negativePrompt ?? '',
                      note: existingDefaultOutfit?.note ?? '',
                    );
                    final outfitIndex = outfits.indexWhere(
                      (outfit) => outfit.id == defaultOutfitId,
                    );
                    if (outfitIndex < 0) {
                      outfits.insert(0, updatedDefaultOutfit);
                    } else {
                      outfits[outfitIndex] = updatedDefaultOutfit;
                    }
                  }

                  Navigator.of(context).pop(
                    base.copyWith(
                      name: name,
                      traits: ViewVariantTexts(
                        frontFull: characterPrompt.isEmpty
                            ? completePrompt
                            : characterPrompt,
                        frontCowboy: base.traits.frontCowboy,
                        frontUpper: _blankToNull(
                          _assetPromptFromTags(upperBodyTags),
                        ),
                        frontLower: _blankToNull(
                          _assetPromptFromTags(lowerBodyTags),
                        ),
                        backFull: base.traits.backFull,
                        backCowboy: base.traits.backCowboy,
                        backUpper: base.traits.backUpper,
                        backLower: base.traits.backLower,
                      ),
                      outfits: outfits,
                      defaultOutfitId: defaultOutfitId,
                      anchorTags: anchorTags,
                      identityTags: identityTags,
                      aliases: existing?.aliases ?? const [],
                      imageRefs: existing?.imageRefs ?? const [],
                      note: existing?.note ?? '',
                      source: const SourceRef(type: 'manual'),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == null) return;
    await _enqueueCharactersMutation(
      catalog,
      (characters) {
        final updated = [...characters];
        final index = updated.indexWhere((entry) => entry.id == saved.id);
        index < 0 ? updated.add(saved) : updated[index] = saved;
        return updated;
      },
      selectedCharacterId: existing == null ? null : () => saved.id,
      clearSelection: existing == null,
    );
  }

  Future<void> _showOutfitEditor(
    StudioAssetCatalogSnapshot initialCatalog,
    CharacterEntry initialCharacter, {
    WorkspaceOutfit? initialExisting,
  }) async {
    await _characterMutationTail;
    if (!mounted) return;

    final catalog = _localCatalog ?? initialCatalog;
    CharacterEntry? currentCharacter;
    for (final character in catalog.characters) {
      if (character.id == initialCharacter.id) {
        currentCharacter = character;
        break;
      }
    }
    if (currentCharacter == null) return;
    final character = currentCharacter;

    WorkspaceOutfit? existing;
    if (initialExisting != null) {
      for (final outfit in character.outfits) {
        if (outfit.id == initialExisting.id) {
          existing = outfit;
          break;
        }
      }
      if (existing == null) return;
    }

    final nameController = TextEditingController(text: existing?.name ?? '');
    final existingPartTags =
        existing?.partTags ?? const WorkspaceOutfitPartTags();
    var upperBodyPrompt = _assetPromptFromTags(existingPartTags.upperBodyTags);
    var upperClothingPrompt =
        _assetPromptFromTags(existingPartTags.upperClothingTags);
    var lowerBodyPrompt = _assetPromptFromTags(existingPartTags.lowerBodyTags);
    var lowerClothingPrompt =
        _assetPromptFromTags(existingPartTags.lowerClothingTags);

    if (upperClothingPrompt.trim().isEmpty) {
      upperClothingPrompt = existing?.tags.frontUpper ?? '';
    }
    if (lowerClothingPrompt.trim().isEmpty) {
      lowerClothingPrompt = existing?.tags.frontLower ?? '';
    }
    if (existing != null &&
        existingPartTags.isEmpty &&
        upperClothingPrompt.trim().isEmpty &&
        lowerClothingPrompt.trim().isEmpty) {
      upperClothingPrompt = existing.tags.frontFull;
    }

    final saved = await showDialog<WorkspaceOutfit>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget tagEditor({
            required String key,
            required String label,
            required String value,
            required ValueChanged<String> onChanged,
          }) {
            return KeyedSubtree(
              key: ValueKey(key),
              child: PromptTagEditor(
                value: value,
                label: label,
                dense: true,
                showControls: false,
                inlineLabel: true,
                inlineLabelWidth: 44,
                initialGroupedLayout: false,
                emptyText: '暂无标签',
                onChanged: (nextValue) {
                  setDialogState(() {
                    onChanged(nextValue);
                  });
                },
              ),
            );
          }

          return AlertDialog(
            title: Text(existing == null ? '新建服装' : '编辑服装'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('asset-outfit-editor-name-field'),
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '服装名称'),
                    ),
                    const SizedBox(height: 12),
                    tagEditor(
                      key: 'asset-outfit-editor-upper-body-tags-editor',
                      label: '上身',
                      value: upperBodyPrompt,
                      onChanged: (value) => upperBodyPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-outfit-editor-upper-clothing-tags-editor',
                      label: '上装',
                      value: upperClothingPrompt,
                      onChanged: (value) => upperClothingPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-outfit-editor-lower-body-tags-editor',
                      label: '下身',
                      value: lowerBodyPrompt,
                      onChanged: (value) => lowerBodyPrompt = value,
                    ),
                    const SizedBox(height: 10),
                    tagEditor(
                      key: 'asset-outfit-editor-lower-clothing-tags-editor',
                      label: '下装',
                      value: lowerClothingPrompt,
                      onChanged: (value) => lowerClothingPrompt = value,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                key: const ValueKey('asset-outfit-editor-save'),
                onPressed: () {
                  final name = nameController.text.trim();
                  final upperBodyTags =
                      _assetPromptTagValuesFromValue(upperBodyPrompt);
                  final upperClothingTags =
                      _assetPromptTagValuesFromValue(upperClothingPrompt);
                  final lowerBodyTags =
                      _assetPromptTagValuesFromValue(lowerBodyPrompt);
                  final lowerClothingTags =
                      _assetPromptTagValuesFromValue(lowerClothingPrompt);
                  final fullPrompt = _assetPromptFromTags([
                    ...upperBodyTags,
                    ...upperClothingTags,
                    ...lowerBodyTags,
                    ...lowerClothingTags,
                  ]);
                  if (name.isEmpty || fullPrompt.isEmpty) return;
                  Navigator.of(context).pop(
                    WorkspaceOutfit(
                      id: existing?.id ??
                          _manualId(
                            'outfit',
                            name,
                            character.outfits.map((entry) => entry.id),
                          ),
                      name: name,
                      tags: ViewVariantTexts(
                        frontFull: fullPrompt,
                        frontCowboy: existing?.tags.frontCowboy,
                        frontUpper: _blankToNull(
                          _assetPromptFromTags(upperClothingTags),
                        ),
                        frontLower: _blankToNull(
                          _assetPromptFromTags(lowerClothingTags),
                        ),
                        backFull: existing?.tags.backFull,
                        backCowboy: existing?.tags.backCowboy,
                        backUpper: existing?.tags.backUpper,
                        backLower: existing?.tags.backLower,
                      ),
                      partTags: WorkspaceOutfitPartTags(
                        upperBodyTags: upperBodyTags,
                        upperClothingTags: upperClothingTags,
                        lowerBodyTags: lowerBodyTags,
                        lowerClothingTags: lowerClothingTags,
                      ),
                      imageRefs: existing?.imageRefs ?? const [],
                      negativePrompt: existing?.negativePrompt ?? '',
                      note: existing?.note ?? '',
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == null) return;

    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (parent) {
        final outfits = [...parent.outfits];
        final outfitIndex = outfits.indexWhere((entry) => entry.id == saved.id);
        outfitIndex < 0 ? outfits.add(saved) : outfits[outfitIndex] = saved;
        return _manualizedCharacter(
          parent.copyWith(
            outfits: outfits,
            defaultOutfitId: parent.defaultOutfitId ?? saved.id,
          ),
        );
      },
    );
  }

  WorkspaceOutfit _copyOutfit(
    WorkspaceOutfit outfit, {
    String? id,
    String? name,
    List<String>? imageRefs,
  }) {
    return WorkspaceOutfit(
      id: id ?? outfit.id,
      name: name ?? outfit.name,
      tags: outfit.tags,
      partTags: outfit.partTags,
      imageRefs: imageRefs ?? outfit.imageRefs,
      negativePrompt: outfit.negativePrompt,
      note: outfit.note,
    );
  }

  Future<void> _duplicateCharacter(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
  ) async {
    String? copyId;
    await _enqueueCharactersMutation(
      catalog,
      (characters) {
        CharacterEntry source = character;
        for (final entry in characters) {
          if (entry.id == character.id) {
            source = entry;
            break;
          }
        }
        copyId = _copyId(source.id, characters.map((entry) => entry.id));
        final duplicate = source.copyWith(
          id: copyId!,
          name: '${source.name} Copy',
          source: const SourceRef(type: 'manual'),
        );
        return [...characters, duplicate];
      },
      selectedCharacterId: () => copyId,
    );
  }

  Future<void> _duplicateOutfit(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    WorkspaceOutfit outfit,
  ) async {
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (parent) {
        var source = outfit;
        for (final current in parent.outfits) {
          if (current.id == outfit.id) {
            source = current;
            break;
          }
        }
        final copyId =
            _copyId(source.id, parent.outfits.map((entry) => entry.id));
        final duplicate = _copyOutfit(
          source,
          id: copyId,
          name: '${source.name} Copy',
        );
        return _manualizedCharacter(
          parent.copyWith(outfits: [...parent.outfits, duplicate]),
        );
      },
    );
  }

  Future<void> _deleteOutfit(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    WorkspaceOutfit outfit,
  ) async {
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (parent) {
        final outfits = parent.outfits
            .where((entry) => entry.id != outfit.id)
            .toList(growable: false);
        final defaultOutfitId = parent.defaultOutfitId == outfit.id
            ? outfits.isEmpty
                ? null
                : outfits.first.id
            : parent.defaultOutfitId;
        return _manualizedCharacter(
          parent.copyWith(
            outfits: outfits,
            defaultOutfitId: defaultOutfitId,
          ),
        );
      },
    );
  }

  Future<void> _deleteOutfitPreview(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
    int outfitIndex,
    WorkspaceOutfit outfit,
  ) async {
    final cacheKey = _outfitPreviewCacheKey(character.id, outfitIndex, outfit);
    final resolvedPath = _resolvePreviewPath(
      _AssetKind.outfit,
      cacheKey,
      outfit.imageRefs,
    );
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (parent) {
        if (outfitIndex < 0 || outfitIndex >= parent.outfits.length) {
          return null;
        }
        final outfits = [...parent.outfits];
        outfits[outfitIndex] = _copyOutfit(
          outfits[outfitIndex],
          imageRefs: const [],
        );
        return parent.copyWith(outfits: outfits);
      },
    );
    _removePreviewPathCacheFor(cacheKey);
    _deleteLocalPreviewFile(resolvedPath);
  }

  Future<void> _showArtistChainEditor(
    StudioAssetCatalogSnapshot catalog, {
    ArtistChain? existing,
  }) async {
    final result = await _showSectionedPromptEditor(
      title: existing == null ? '新建画师串' : '编辑画师串',
      initialName: existing?.name ?? '',
      initialPrompt: existing == null ? '' : _artistChainPrompt(existing),
      initialSections: existing?.sections ?? const {},
    );
    if (result == null) return;
    final prompt = result.prompt.trim().isNotEmpty
        ? result.prompt.trim()
        : _sectionPrompt(result.sections);
    if (result.name.isEmpty || prompt.isEmpty) return;
    final base = existing ??
        ArtistChain(
          id: _manualId(
            'artist',
            result.name,
            catalog.artistChains.map((entry) => entry.id),
          ),
          name: result.name,
        );
    final saved = base.copyWith(
      name: result.name,
      prompt: prompt,
      tags: _promptTags(prompt),
      sections: result.sections,
      source: const SourceRef(type: 'manual'),
    );
    final artistChains = [...catalog.artistChains];
    final index = artistChains.indexWhere((entry) => entry.id == saved.id);
    index < 0 ? artistChains.add(saved) : artistChains[index] = saved;
    await widget.saveArtistChains?.call(artistChains);
    if (!mounted) return;
    final snapshot = _snapshotWith(catalog, artistChains: artistChains);
    setState(() {
      _localCatalog = snapshot;
      if (existing == null) {
        _filter = _AssetFilter.artistChain;
        _resetVisibleAssetLimit();
        _clearDisplayItemsCache();
      }
      _selectedAsset = _displayItemByKey(snapshot, 'artist-${saved.id}');
    });
  }

  Future<void> _showRecipeEditor(
    StudioAssetCatalogSnapshot catalog, {
    Recipe? existing,
  }) async {
    final result = await _showSectionedPromptEditor(
      title: existing == null ? '新建配方' : '编辑配方',
      initialName: existing?.name ?? '',
      initialPrompt: existing?.tags ?? '',
      initialBlock: existing?.block ?? _defaultPromptBlock(catalog),
      initialSections: existing?.variants ?? const {},
      showBlock: true,
    );
    if (result == null) return;
    final prompt = result.prompt.trim().isNotEmpty
        ? result.prompt.trim()
        : _sectionPrompt(result.sections);
    final block = result.block.trim();
    if (result.name.isEmpty || block.isEmpty || prompt.isEmpty) return;
    final saved = Recipe(
      id: existing?.id ??
          _manualId(
              'recipe', result.name, catalog.recipes.map((entry) => entry.id)),
      name: result.name,
      block: block,
      category: existing?.category ?? '',
      group: existing?.group ?? '',
      tags: prompt,
      variants: result.sections,
      imageRefs: existing?.imageRefs ?? const [],
      source: const SourceRef(type: 'manual'),
      note: existing?.note ?? '',
    );
    await _saveRecipe(catalog, saved, originalBlock: existing?.block);
  }

  Future<void> _showTagEditor(
    StudioAssetCatalogSnapshot catalog, {
    TagEntry? existing,
  }) async {
    final result = await _showSectionedPromptEditor(
      title: existing == null ? '新建 Tag' : '编辑 Tag',
      initialName: existing == null
          ? ''
          : (existing.zh.isEmpty ? existing.tag : existing.zh),
      initialPrompt: existing?.tag ?? '',
      initialBlock: existing?.block ?? _defaultPromptBlock(catalog),
      initialSections: existing?.sections ?? const {},
      showBlock: true,
    );
    if (result == null) return;
    final prompt = result.prompt.trim().isNotEmpty
        ? result.prompt.trim()
        : _sectionPrompt(result.sections);
    final block = result.block.trim();
    if (result.name.isEmpty || block.isEmpty || prompt.isEmpty) return;
    final saved = TagEntry(
      id: existing?.id ??
          _manualId('tag', result.name, catalog.tags.map((entry) => entry.id)),
      tag: prompt,
      zh: result.name == prompt ? existing?.zh ?? '' : result.name,
      block: block,
      category: existing?.category ?? '',
      sections: result.sections,
      aliases: existing?.aliases ?? const [],
      imageRefs: existing?.imageRefs ?? const [],
      source: const SourceRef(type: 'manual'),
      note: existing?.note ?? '',
    );
    await _saveTag(catalog, saved, originalBlock: existing?.block);
  }

  Future<_SectionedPromptEditorResult?> _showSectionedPromptEditor({
    required String title,
    required String initialName,
    required String initialPrompt,
    String initialBlock = '',
    Map<String, String> initialSections = const {},
    bool showBlock = false,
  }) {
    final nameController = TextEditingController(text: initialName);
    final blockController = TextEditingController(text: initialBlock);
    var prompt = initialPrompt;
    final sections = [
      for (final entry in initialSections.entries)
        _PromptAssetSectionDraft(
          label: entry.key,
          prompt: entry.value,
        ),
    ];

    return showDialog<_SectionedPromptEditorResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget promptEditor({
            required String key,
            required String label,
            required String value,
            required ValueChanged<String> onChanged,
          }) {
            return KeyedSubtree(
              key: ValueKey(key),
              child: PromptTagEditor(
                value: value,
                label: label,
                dense: true,
                showControls: false,
                inlineLabel: true,
                inlineLabelWidth: 74,
                initialGroupedLayout: false,
                emptyText: '暂无标签',
                onChanged: (nextValue) {
                  setDialogState(() => onChanged(nextValue));
                },
              ),
            );
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 660,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('asset-editor-name-field'),
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    if (showBlock) ...[
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('asset-editor-block-field'),
                        controller: blockController,
                        decoration: const InputDecoration(
                          labelText: '所属分类 ID',
                          helperText: '可在素材库的“管理素材分类”中新增和配置',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    promptEditor(
                      key: 'asset-editor-prompt-field',
                      label: '完整 Prompt',
                      value: prompt,
                      onChanged: (value) => prompt = value,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '自定义分区',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        StudioIconButton(
                          key: const ValueKey('asset-editor-add-section'),
                          tooltip: '新增分区',
                          icon: Icons.add,
                          onPressed: () {
                            setDialogState(() {
                              sections.add(
                                _PromptAssetSectionDraft(
                                  label: '分区 ${sections.length + 1}',
                                ),
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < sections.length; index += 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AssetSectionEditor(
                          key: ValueKey('asset-editor-section-$index'),
                          labelController: sections[index].labelController,
                          prompt: sections[index].prompt,
                          promptKey: 'asset-editor-section-prompt-$index',
                          onPromptChanged: (value) {
                            setDialogState(
                                () => sections[index].prompt = value);
                          },
                          onDelete: () {
                            setDialogState(() => sections.removeAt(index));
                          },
                          promptEditor: promptEditor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                key: const ValueKey('asset-editor-save'),
                onPressed: () {
                  final sectionMap = <String, String>{};
                  for (final section in sections) {
                    final label = section.labelController.text.trim();
                    final value = section.prompt.trim();
                    if (label.isEmpty || value.isEmpty) continue;
                    sectionMap[label] = value;
                  }
                  Navigator.of(context).pop(
                    _SectionedPromptEditorResult(
                      name: nameController.text.trim(),
                      block: blockController.text.trim(),
                      prompt: prompt.trim(),
                      sections: Map.unmodifiable(sectionMap),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _defaultPromptBlock(StudioAssetCatalogSnapshot catalog) {
    final configuredCategoryIds = catalog.promptAssetCategories
        .map((category) => category.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (configuredCategoryIds.isNotEmpty) {
      return configuredCategoryIds.first;
    }
    final blocks = {
      ...WorkspacePaths.blocks,
      ...configuredCategoryIds,
      ...catalog.summary.recipeCountsByBlock.keys,
      ...catalog.summary.tagCountsByBlock.keys,
      for (final recipe in catalog.recipes) recipe.block,
      for (final tag in catalog.tags) tag.block,
    }.where((block) => block.trim().isNotEmpty).toList()
      ..sort();
    if (blocks.contains('style')) return 'style';
    return blocks.isEmpty ? 'style' : blocks.first;
  }

  String _sectionPrompt(Map<String, String> sections) {
    return sections.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  Future<void> _saveRecipe(
    StudioAssetCatalogSnapshot catalog,
    Recipe recipe, {
    String? originalBlock,
  }) async {
    final saveRecipes = widget.saveRecipes;
    if (saveRecipes == null) return;
    final target = [
      for (final entry in catalog.recipes)
        if (entry.block == recipe.block && entry.id != recipe.id) entry,
      recipe,
    ];
    await saveRecipes(recipe.block, target);
    if (originalBlock != null && originalBlock != recipe.block) {
      await saveRecipes(originalBlock, [
        for (final entry in catalog.recipes)
          if (!(entry.block == originalBlock && entry.id == recipe.id)) entry,
      ]);
    }
    widget.onPromptAssetsChanged?.call();
    if (!mounted) return;
    final recipes = [
      for (final entry in catalog.recipes)
        if (entry.id != recipe.id) entry,
      recipe,
    ];
    setState(() {
      _localCatalog = _snapshotWith(catalog, recipes: recipes);
      _selectedAsset = null;
    });
  }

  Future<void> _saveTag(
    StudioAssetCatalogSnapshot catalog,
    TagEntry tag, {
    String? originalBlock,
  }) async {
    final saveTags = widget.saveTags;
    if (saveTags == null) return;
    final target = [
      for (final entry in catalog.tags)
        if (entry.block == tag.block && entry.id != tag.id) entry,
      tag,
    ];
    await saveTags(tag.block, target);
    if (originalBlock != null && originalBlock != tag.block) {
      await saveTags(originalBlock, [
        for (final entry in catalog.tags)
          if (!(entry.block == originalBlock && entry.id == tag.id)) entry,
      ]);
    }
    widget.onPromptAssetsChanged?.call();
    if (!mounted) return;
    final tags = [
      for (final entry in catalog.tags)
        if (entry.id != tag.id) entry,
      tag,
    ];
    setState(() {
      _localCatalog = _snapshotWith(catalog, tags: tags);
      _selectedAsset = null;
    });
  }

  Future<void> _deleteRecipe(
    StudioAssetCatalogSnapshot catalog,
    Recipe recipe,
  ) async {
    final saveRecipes = widget.saveRecipes;
    if (saveRecipes == null) return;
    final recipes = [
      for (final entry in catalog.recipes)
        if (entry.id != recipe.id) entry,
    ];
    await saveRecipes(recipe.block, [
      for (final entry in recipes)
        if (entry.block == recipe.block) entry,
    ]);
    widget.onPromptAssetsChanged?.call();
    if (!mounted) return;
    setState(() {
      _localCatalog = _snapshotWith(catalog, recipes: recipes);
      _selectedAsset = null;
    });
  }

  Future<void> _deleteTag(
    StudioAssetCatalogSnapshot catalog,
    TagEntry tag,
  ) async {
    final saveTags = widget.saveTags;
    if (saveTags == null) return;
    final tags = [
      for (final entry in catalog.tags)
        if (entry.id != tag.id) entry,
    ];
    await saveTags(tag.block, [
      for (final entry in tags)
        if (entry.block == tag.block) entry,
    ]);
    widget.onPromptAssetsChanged?.call();
    if (!mounted) return;
    setState(() {
      _localCatalog = _snapshotWith(catalog, tags: tags);
      _selectedAsset = null;
    });
  }

  Future<void> _confirmDeleteAsset(
      {required Future<void> Function() onConfirm}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('确定删除这个素材？'),
        actions: [
          FilledButton(
            key: const ValueKey('asset-delete-confirm'),
            onPressed: () async {
              await onConfirm();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCharacter(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
  ) async {
    await _enqueueCharactersMutation(
      catalog,
      (characters) => characters
          .where((entry) => entry.id != character.id)
          .toList(growable: false),
      clearSelection: true,
    );
  }

  Future<void> _deleteArtistChain(
    StudioAssetCatalogSnapshot catalog,
    ArtistChain artistChain,
  ) async {
    final artistChains = catalog.artistChains
        .where((entry) => entry.id != artistChain.id)
        .toList(growable: false);
    await widget.saveArtistChains?.call(artistChains);
    if (!mounted) return;
    setState(() {
      _localCatalog = _snapshotWith(catalog, artistChains: artistChains);
      _selectedAsset = null;
    });
  }

  Future<void> _deleteCharacterPreview(
    StudioAssetCatalogSnapshot catalog,
    CharacterEntry character,
  ) async {
    final resolvedPath = _resolvePreviewPath(
      _AssetKind.character,
      'character-${character.id}',
      character.imageRefs,
    );
    await _enqueueCharacterMutation(
      catalog,
      character.id,
      (current) => current.copyWith(imageRefs: const []),
    );
    _removePreviewPathCacheFor('character-${character.id}');
    _deleteLocalPreviewFile(resolvedPath);
  }

  Future<void> _deleteArtistChainPreview(
    StudioAssetCatalogSnapshot catalog,
    ArtistChain artistChain,
  ) async {
    final resolvedPath = _resolvePreviewPath(
      _AssetKind.artistChain,
      'artist-${artistChain.id}',
      artistChain.imageRefs,
    );
    final updated = [
      for (final chain in catalog.artistChains)
        if (chain.id == artistChain.id)
          chain.copyWith(imageRefs: const [])
        else
          chain,
    ];
    await widget.saveArtistChains?.call(updated);
    if (!mounted) return;
    setState(() {
      _removePreviewPathCacheFor('artist-${artistChain.id}');
      _localCatalog = _snapshotWith(catalog, artistChains: updated);
      _selectedAsset = null;
    });
    _deleteLocalPreviewFile(resolvedPath);
  }

  void _deleteLocalPreviewFile(String? resolvedPath) {
    if (resolvedPath == null) return;
    try {
      final file = File(resolvedPath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best effort cleanup; catalog state still removes the stale ref.
    }
  }

  Future<void> _saveArtistChain(
    StudioAssetCatalogSnapshot catalog,
    ArtistChain updatedChain,
  ) async {
    final updated = [
      for (final chain in catalog.artistChains)
        if (chain.id == updatedChain.id) updatedChain else chain,
    ];
    await widget.saveArtistChains?.call(updated);
    if (!mounted) return;
    setState(() {
      _localCatalog = _snapshotWith(catalog, artistChains: updated);
      _selectedAsset = _displayItemsFor(_localCatalog!)
          .where((item) => item.key == 'artist-${updatedChain.id}')
          .cast<_AssetDisplayItem?>()
          .firstWhere((item) => item != null, orElse: () => null);
    });
  }

  Future<void> _saveArtistChainPrompt(
    StudioAssetCatalogSnapshot catalog,
    ArtistChain artistChain,
    String prompt,
  ) {
    final trimmed = prompt.trim();
    return _saveArtistChain(
      catalog,
      artistChain.copyWith(
        prompt: trimmed,
        tags: _promptTags(trimmed),
      ),
    );
  }

  Future<void> _duplicateArtistChain(
    StudioAssetCatalogSnapshot catalog,
    ArtistChain artistChain,
  ) async {
    final existingIds = catalog.artistChains.map((chain) => chain.id);
    var copyId = '${artistChain.id}-copy';
    var suffix = 2;
    while (existingIds.contains(copyId)) {
      copyId = '${artistChain.id}-copy-$suffix';
      suffix += 1;
    }
    final duplicate = artistChain.copyWith(
      id: copyId,
      name: '${artistChain.name} Copy',
      source: const SourceRef(type: 'manual'),
    );
    final updated = [...catalog.artistChains, duplicate];
    await widget.saveArtistChains?.call(updated);
    if (!mounted) return;
    setState(() {
      _localCatalog = _snapshotWith(catalog, artistChains: updated);
      _selectedAsset = _displayItemsFor(_localCatalog!)
          .where((item) => item.key == 'artist-$copyId')
          .cast<_AssetDisplayItem?>()
          .firstWhere((item) => item != null, orElse: () => null);
    });
  }

  Future<void> _renameArtistChain(
    StudioAssetCatalogSnapshot catalog,
    ArtistChain artistChain,
    String name,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _saveArtistChain(catalog, artistChain.copyWith(name: trimmed));
  }

  Set<_AssetFilter> _availableFilters(StudioAssetCatalogSnapshot catalog) {
    return {
      _AssetFilter.all,
      if (catalog.characters.isNotEmpty || widget.saveCharacters != null)
        _AssetFilter.character,
      if (catalog.summary.outfitCount > 0 || catalog.outfits.isNotEmpty)
        _AssetFilter.outfit,
      if (catalog.artistChains.isNotEmpty || widget.saveArtistChains != null)
        _AssetFilter.artistChain,
      if (catalog.summary.recipeCount > 0 ||
          catalog.recipes.isNotEmpty ||
          widget.saveRecipes != null)
        _AssetFilter.recipe,
      if (catalog.summary.tagCount > 0 ||
          catalog.tags.isNotEmpty ||
          widget.saveTags != null)
        _AssetFilter.tag,
      if (catalog.legacyCodexAvailable || catalog.legacyCodexTotalCount > 0)
        _AssetFilter.codex,
      if (catalog.summary.inspirationCount > 0) _AssetFilter.inspiration,
      if (catalog.loras.isNotEmpty) _AssetFilter.lora,
      if (catalog.workflows.isNotEmpty) _AssetFilter.workflow,
      if (catalog.summary.batchPlanCount > 0 || catalog.batchPlans.isNotEmpty)
        _AssetFilter.batchPlan,
      if (catalog.assemblyPresets.isNotEmpty) _AssetFilter.assemblyPreset,
    };
  }

  List<_AssetDetailLine> _details(List<_AssetDetailLine> lines) {
    return lines
        .where((line) => line.value.trim().isNotEmpty)
        .toList(growable: false);
  }

  String _compactMeta(List<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
  }

  String _sourceLabel(SourceRef source) {
    return source.type == 'manual' ? '' : source.type;
  }

  void _reload() {
    setState(() {
      _catalogRefreshStatus = '正在更新素材索引...';
      _cancelLegacyCodexBackgroundLoad();
      _clearPreviewResolutionState();
      _clearDisplayItemsCache();
      _resetVisibleAssetLimit();
      _localCatalog = null;
      _snapshotFuture = _refreshSnapshotCache();
      _selectedAsset = null;
    });
  }

  Future<StudioAssetCatalogSnapshot> _loadSnapshot() async {
    final includeLegacyCodex = _filter == _AssetFilter.codex;
    final codexQuery = includeLegacyCodex ? _query : '';
    final codexCategoryKey = _legacyCodexRequestKey;
    final result = await widget.catalogService.loadSnapshotWithCache(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: _legacyCodexLimit,
      legacyCodexQuery: codexQuery,
      legacyCodexCategoryKey: codexCategoryKey,
      checkStaleness: false,
      persistCacheBeforeReturn: false,
    );
    return result.snapshot;
  }

  Future<StudioAssetCatalogSnapshot> _refreshSnapshotCache() async {
    final includeLegacyCodex = _filter == _AssetFilter.codex;
    final codexQuery = includeLegacyCodex ? _query : '';
    final codexCategoryKey = _legacyCodexRequestKey;
    final snapshot = await widget.catalogService.refreshSnapshotCache(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: _legacyCodexLimit,
      legacyCodexQuery: codexQuery,
      legacyCodexCategoryKey: codexCategoryKey,
    );
    if (mounted) {
      setState(() => _catalogRefreshStatus = '素材索引已更新');
    }
    return snapshot;
  }

  String get _legacyCodexRequestKey => StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: _legacyCodexSourceScopeKey,
        categoryKey: _legacyCodexCategoryKey,
      );

  void _selectLegacyCodexCategory(String categoryKey) {
    setState(() {
      _filter = _AssetFilter.codex;
      _legacyCodexCategoryKey =
          StudioLegacyCodexCategories.normalizedKeyForSource(
        categoryKey,
        _legacyCodexSourceScopeKey,
      );
      _legacyCodexLimit = _legacyCodexPageSize;
      _resetVisibleAssetLimit();
      _cancelLegacyCodexBackgroundLoad();
      _localCatalog = null;
      _selectedAsset = null;
      _snapshotFuture = _loadSnapshot();
    });
  }

  void _selectLegacyCodexSourceScope(String sourceScopeKey) {
    setState(() {
      _filter = _AssetFilter.codex;
      final normalizedSourceScopeKey =
          StudioLegacyCodexCategories.normalizedSourceScopeKey(sourceScopeKey);
      _legacyCodexSourceScopeKey = normalizedSourceScopeKey;
      _legacyCodexCategoryKey =
          StudioLegacyCodexCategories.defaultCategoryKeyForSource(
        normalizedSourceScopeKey,
      );
      _legacyCodexLimit = _legacyCodexPageSize;
      _resetVisibleAssetLimit();
      _cancelLegacyCodexBackgroundLoad();
      _localCatalog = null;
      _selectedAsset = null;
      _snapshotFuture = _loadSnapshot();
    });
  }

  void _loadMoreLegacyCodex(StudioAssetCatalogSnapshot catalog) {
    _startLegacyCodexBackgroundLoad(
      catalog,
      query: _query,
      categoryKey: _legacyCodexRequestKey,
    );
  }

  void _startLegacyCodexBackgroundLoad(
    StudioAssetCatalogSnapshot catalog, {
    required String query,
    required String categoryKey,
    Duration delay = Duration.zero,
  }) {
    if (_filter != _AssetFilter.codex) return;
    if (_loadingMoreLegacyCodex) return;
    if (catalog.legacyCodexLoadedCount >= catalog.legacyCodexTotalCount) {
      return;
    }
    final nextLimit =
        catalog.legacyCodexLoadedCount + _legacyCodexBackgroundBatchSize;
    final safeLimit = nextLimit > catalog.legacyCodexTotalCount
        ? catalog.legacyCodexTotalCount
        : nextLimit;
    final token = _legacyCodexLoadToken + 1;
    setState(() {
      _legacyCodexLoadToken = token;
      _loadingMoreLegacyCodex = true;
    });
    unawaited(
      _loadNextLegacyCodexPage(
        token: token,
        query: query,
        categoryKey: categoryKey,
        limit: safeLimit,
        delay: delay,
      ),
    );
  }

  void _scheduleLegacyCodexBackgroundLoad(
    StudioAssetCatalogSnapshot catalog,
  ) {
    if (_filter != _AssetFilter.codex) return;
    if (_loadingMoreLegacyCodex || _legacyCodexAutoLoadQueued) return;
    if (catalog.legacyCodexLoadedCount >= catalog.legacyCodexTotalCount) {
      return;
    }
    final query = _query;
    final categoryKey = _legacyCodexRequestKey;
    _legacyCodexAutoLoadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _legacyCodexAutoLoadQueued = false;
      if (!_isLegacyCodexRequestCurrent(
          query: query, categoryKey: categoryKey)) {
        return;
      }
      _startLegacyCodexBackgroundLoad(
        catalog,
        query: query,
        categoryKey: categoryKey,
        delay: _legacyCodexBackgroundLoadDelay,
      );
    });
  }

  Future<void> _loadNextLegacyCodexPage({
    required int token,
    required String query,
    required String categoryKey,
    required int limit,
    required Duration delay,
  }) async {
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
        if (!_isLegacyCodexBackgroundLoadCurrent(
          token: token,
          query: query,
          categoryKey: categoryKey,
        )) {
          return;
        }
      }
      final result = await widget.catalogService.loadSnapshotWithCache(
        includeLegacyCodex: true,
        legacyCodexLimit: limit,
        legacyCodexQuery: query,
        legacyCodexCategoryKey: categoryKey,
        checkStaleness: false,
        persistCacheBeforeReturn: false,
      );
      if (!_isLegacyCodexBackgroundLoadCurrent(
        token: token,
        query: query,
        categoryKey: categoryKey,
      )) {
        return;
      }
      final catalog = result.snapshot;
      if (!mounted) return;
      setState(() {
        _legacyCodexLimit = limit;
        _localCatalog = catalog;
        _snapshotFuture = Future.value(catalog);
        _selectedAsset = _selectedAsset == null
            ? null
            : _displayItemsFor(catalog)
                .where((candidate) => candidate.key == _selectedAsset!.key)
                .cast<_AssetDisplayItem?>()
                .firstWhere((candidate) => candidate != null,
                    orElse: () => null);
      });
    } finally {
      if (mounted && _legacyCodexLoadToken == token) {
        setState(() => _loadingMoreLegacyCodex = false);
      }
    }
  }

  bool _isLegacyCodexBackgroundLoadCurrent({
    required int token,
    required String query,
    required String categoryKey,
  }) {
    return mounted &&
        _legacyCodexLoadToken == token &&
        _isLegacyCodexRequestCurrent(query: query, categoryKey: categoryKey);
  }

  bool _isLegacyCodexRequestCurrent({
    required String query,
    required String categoryKey,
  }) {
    return mounted &&
        _filter == _AssetFilter.codex &&
        _query == query &&
        _legacyCodexRequestKey == categoryKey;
  }

  void _cancelLegacyCodexBackgroundLoad() {
    _legacyCodexLoadToken += 1;
    _loadingMoreLegacyCodex = false;
    _legacyCodexAutoLoadQueued = false;
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _selectedAsset = null;
      _resetVisibleAssetLimit();
      if (_filter == _AssetFilter.codex) {
        _legacyCodexLimit = _legacyCodexPageSize;
        _cancelLegacyCodexBackgroundLoad();
        _localCatalog = null;
        _snapshotFuture = _loadSnapshot();
      }
    });
  }

  void _selectAssetFilter(_AssetFilter value) {
    final shouldReloadCatalog =
        value == _AssetFilter.codex || _filter == _AssetFilter.codex;
    setState(() {
      _filter = value;
      _selectedAsset = null;
      _resetVisibleAssetLimit();
      _cancelLegacyCodexBackgroundLoad();
      if (value == _AssetFilter.codex) {
        _legacyCodexLimit = _legacyCodexPageSize;
      }
      if (shouldReloadCatalog) {
        _localCatalog = null;
        _snapshotFuture = _loadSnapshot();
      }
    });
  }

  void _sendAsset(BuildContext context, VoidCallback send) {
    send();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已发送到工作台')),
    );
  }

  Future<void> _sendCharacterAsset(CharacterEntry character) async {
    if (character.outfits.length > 1) {
      final outfit = await showDialog<WorkspaceOutfit>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择服装'),
          children: [
            for (final outfit in character.outfits)
              SimpleDialogOption(
                key: ValueKey(
                  'asset-card-outfit-choice-${character.id}-${outfit.id}',
                ),
                onPressed: () => Navigator.of(context).pop(outfit),
                child: Text(outfit.name),
              ),
          ],
        ),
      );
      if (outfit == null || !mounted) return;
      _sendAsset(
        context,
        () => widget.workbenchAssetService.appendOutfit(character, outfit),
      );
      return;
    }
    _sendAsset(
      context,
      () => widget.workbenchAssetService.appendCharacter(character),
    );
  }

  String _artistChainPrompt(ArtistChain artistChain) {
    if (artistChain.prompt.trim().isNotEmpty) {
      return artistChain.prompt.trim();
    }
    return [
      ...artistChain.tags,
      ...artistChain.styleTags,
    ].join(', ');
  }

  String _outfitPrompt(WorkspaceOutfit outfit) {
    final prompt = outfit.tags.frontFull.trim();
    if (prompt.isNotEmpty) return prompt;
    return _assetPromptFromTags([
      ...outfit.partTags.upperBodyTags,
      ...outfit.partTags.upperClothingTags,
      ...outfit.partTags.lowerBodyTags,
      ...outfit.partTags.lowerClothingTags,
      ...outfit.partTags.weaponTags,
    ]);
  }

  String _inspirationSummary(InspirationEntry inspiration) {
    if (inspiration.prompt.trim().isNotEmpty) {
      return inspiration.prompt.trim();
    }
    return inspiration.tags.join(', ');
  }

  String _loraSummary(LoraEntry lora) {
    return _compactMeta([
      if (lora.triggerWords.isNotEmpty) lora.triggerWords.join(', '),
      if (lora.defaultStrength != null)
        'Strength ${lora.defaultStrength!.toStringAsFixed(2)}',
      lora.baseModel,
    ]);
  }

  String _workflowSummary(WorkflowEntry workflow) {
    if (workflow.summary.trim().isNotEmpty) {
      return workflow.summary.trim();
    }
    return _mapPreview(workflow.payload);
  }

  String _batchPlanSummary(BatchPlan batchPlan) {
    return _compactMeta([
      '${batchPlan.items.length} items',
      if (batchPlan.statusSnapshot.isNotEmpty)
        _mapPreview(batchPlan.statusSnapshot),
    ]);
  }

  String _assemblyPresetSummary(AssemblyPresetEntry preset) {
    if (preset.summary.trim().isNotEmpty) {
      return preset.summary.trim();
    }
    return _mapPreview(preset.payload);
  }

  String _mapPreview(Map<String, dynamic> values) {
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
  }
}

class _PromptCategoryManagerDialog extends StatefulWidget {
  final List<PromptAssetCategory> initialCategories;
  final String Function(String value) normalizeId;

  const _PromptCategoryManagerDialog({
    required this.initialCategories,
    required this.normalizeId,
  });

  @override
  State<_PromptCategoryManagerDialog> createState() =>
      _PromptCategoryManagerDialogState();
}

class _PromptCategoryManagerDialogState
    extends State<_PromptCategoryManagerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  late final List<PromptAssetCategory> _categories = [
    ...widget.initialCategories,
  ];
  String? _validationMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  void _addCategory() {
    final name = _nameController.text.trim();
    final id = widget.normalizeId(
      _idController.text.trim().isEmpty ? name : _idController.text,
    );
    if (name.isEmpty || id.isEmpty) {
      setState(() {
        _validationMessage = '请输入分类名称；分类 ID 需包含有效字符。';
      });
      return;
    }
    if (_categories.any((category) => category.id == id)) {
      setState(() {
        _validationMessage = '分类 ID “$id” 已存在。';
      });
      return;
    }
    setState(() {
      _categories.add(PromptAssetCategory(id: id, name: name));
      _nameController.clear();
      _idController.clear();
      _validationMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理素材分类'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '分类 ID 对应配方和 Tag 的“所属分类”。删除这里只会移除分类配置，不会删除分类中的素材。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
              const SizedBox(height: 12),
              if (_categories.isEmpty) const _EmptyRow(message: '还没有自定义分类'),
              for (var index = 0; index < _categories.length; index += 1)
                Container(
                  key: ValueKey(
                    'prompt-asset-category-row-${_categories[index].id}',
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: StudioTokens.surface2,
                    borderRadius: StudioTokens.radiusSlot,
                    border: StudioTokens.cardBorder,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _categories[index].name,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID ${_categories[index].id}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: StudioTokens.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '素材抽屉',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Switch(
                        key: ValueKey(
                          'prompt-asset-category-drawer-${_categories[index].id}',
                        ),
                        value: _categories[index].showInScriptDrawer,
                        onChanged: (value) {
                          setState(() {
                            _categories[index] = _categories[index]
                                .copyWith(showInScriptDrawer: value);
                          });
                        },
                      ),
                      StudioIconButton(
                        key: ValueKey(
                          'prompt-asset-category-delete-${_categories[index].id}',
                        ),
                        tooltip: '删除分类配置',
                        icon: Icons.delete_outline,
                        onPressed: () {
                          setState(() => _categories.removeAt(index));
                        },
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey(
                        'prompt-asset-category-name-field',
                      ),
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: '分类名称'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('prompt-asset-category-id-field'),
                      controller: _idController,
                      decoration: const InputDecoration(
                        labelText: '分类 ID（可留空自动生成）',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: StudioIconButton(
                      key: const ValueKey('prompt-asset-category-add'),
                      tooltip: '新增分类',
                      icon: Icons.add_circle_outline,
                      onPressed: _addCategory,
                    ),
                  ),
                ],
              ),
              if (_validationMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _validationMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StudioTokens.danger,
                      ),
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
          key: const ValueKey('prompt-asset-category-save'),
          onPressed: () => Navigator.of(context).pop(
            List<PromptAssetCategory>.unmodifiable(_categories),
          ),
          child: const Text('保存分类'),
        ),
      ],
    );
  }
}

class _LibraryFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onScrolledNearEnd;

  const _LibraryFrame({required this.child, this.onScrolledNearEnd});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is! ScrollEndNotification) return false;
        final metrics = notification.metrics;
        if (metrics.maxScrollExtent - metrics.pixels <= 480) {
          onScrolledNearEnd?.call();
        }
        return false;
      },
      child: SingleChildScrollView(
        key: const ValueKey('asset-library-scroll'),
        padding: const EdgeInsets.all(StudioTokens.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1760),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  final int assetCount;

  const _LibraryHeader({required this.assetCount});

  @override
  Widget build(BuildContext context) {
    final description = assetCount == 0
        ? '素材库还是空的，新建第一条素材，或把工作台结果沉淀进来。'
        : '已整理 $assetCount 条可复用素材，可直接送入工作台。';
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
              Icons.inventory_2_outlined,
              color: StudioTokens.onPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '素材库',
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
        ],
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Row(
        children: [
          Icon(icon, size: 28, color: StudioTokens.warning),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _AssetLibraryControls extends StatelessWidget {
  final _AssetFilter selectedFilter;
  final Set<_AssetFilter> availableFilters;
  final String selectedCodexSourceScopeKey;
  final String selectedCodexCategoryKey;
  final Map<String, int> codexCategoryCounts;
  final int codexLoadedCount;
  final int codexTotalCount;
  final int resultCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_AssetFilter> onFilterChanged;
  final ValueChanged<String> onCodexSourceScopeChanged;
  final ValueChanged<String> onCodexCategoryChanged;
  final VoidCallback onReload;
  final String? catalogRefreshStatus;
  final VoidCallback? onAddAsset;
  final VoidCallback? onManagePromptCategories;

  const _AssetLibraryControls({
    required this.selectedFilter,
    required this.availableFilters,
    required this.selectedCodexSourceScopeKey,
    required this.selectedCodexCategoryKey,
    required this.codexCategoryCounts,
    required this.codexLoadedCount,
    required this.codexTotalCount,
    required this.resultCount,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onCodexSourceScopeChanged,
    required this.onCodexCategoryChanged,
    required this.onReload,
    this.catalogRefreshStatus,
    this.onAddAsset,
    this.onManagePromptCategories,
  });

  IconData _assetFilterIcon(_AssetFilter filter) {
    return switch (filter) {
      _AssetFilter.all => Icons.dashboard_customize_outlined,
      _AssetFilter.character => Icons.person_outline,
      _AssetFilter.outfit => Icons.checkroom_outlined,
      _AssetFilter.artistChain => Icons.brush_outlined,
      _AssetFilter.recipe => Icons.auto_awesome_mosaic_outlined,
      _AssetFilter.tag => Icons.local_offer_outlined,
      _AssetFilter.codex => Icons.menu_book_outlined,
      _AssetFilter.inspiration => Icons.auto_awesome_outlined,
      _AssetFilter.lora => Icons.tune_outlined,
      _AssetFilter.workflow => Icons.account_tree_outlined,
      _AssetFilter.batchPlan => Icons.playlist_add_check_outlined,
      _AssetFilter.assemblyPreset => Icons.view_module_outlined,
    };
  }

  List<StudioLegacyCodexCategory> _codexCategories() {
    final sourceCategoryKeys = [
      for (final entry in codexCategoryCounts.entries)
        if (entry.key != StudioLegacyCodexCategories.allKey &&
            entry.value > 0 &&
            StudioLegacyCodexCategories.isSourceCategoryKey(entry.key))
          entry.key,
    ];
    if (sourceCategoryKeys.isNotEmpty) {
      return [
        for (final key in sourceCategoryKeys)
          StudioLegacyCodexCategory(
            key: key,
            label: StudioLegacyCodexCategories.labelForKey(key),
          ),
      ];
    }
    return StudioLegacyCodexCategories.filtersForSource(
      selectedCodexSourceScopeKey,
    )
        .where((category) => category.key != StudioLegacyCodexCategories.allKey)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filters = [
      (_AssetFilter.all, '全部', 'asset-filter-all'),
      (_AssetFilter.character, '角色', 'asset-filter-character'),
      (_AssetFilter.artistChain, '画师串', 'asset-filter-artist-chain'),
      (_AssetFilter.codex, '法典', 'asset-filter-codex'),
      (_AssetFilter.recipe, '配方', 'asset-filter-recipe'),
      (_AssetFilter.tag, 'Tag', 'asset-filter-tag'),
      (_AssetFilter.outfit, 'Outfit', 'asset-filter-outfit'),
      (_AssetFilter.inspiration, 'Inspiration', 'asset-filter-inspiration'),
      (_AssetFilter.lora, 'LoRA', 'asset-filter-lora'),
      (_AssetFilter.workflow, 'Workflow', 'asset-filter-workflow'),
      (_AssetFilter.batchPlan, 'Batch Plan', 'asset-filter-batch-plan'),
      (
        _AssetFilter.assemblyPreset,
        'Assembly Preset',
        'asset-filter-assembly-preset',
      ),
    ];
    final primaryFilterValues = {
      _AssetFilter.codex,
      _AssetFilter.all,
      _AssetFilter.character,
      _AssetFilter.artistChain,
      _AssetFilter.recipe,
      _AssetFilter.tag,
    };
    final primaryFilters = [
      for (final filter in filters)
        if (primaryFilterValues.contains(filter.$1) &&
            availableFilters.contains(filter.$1))
          filter,
    ];
    final secondaryFilters = [
      for (final filter in filters)
        if (!primaryFilterValues.contains(filter.$1) &&
            availableFilters.contains(filter.$1))
          filter,
    ];

    return StudioPanel(
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('asset-library-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索素材',
              isDense: true,
            ),
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 620
                      ? 3
                      : constraints.maxWidth >= 420
                          ? 2
                          : 1;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                key: const ValueKey('asset-filter-gallery'),
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final filter in primaryFilters)
                    SizedBox(
                      key: ValueKey(filter.$3),
                      width: width,
                      child: _AssetFilterGalleryCard(
                        label: filter.$2,
                        icon: _assetFilterIcon(filter.$1),
                        selected: selectedFilter == filter.$1,
                        onTap: () => onFilterChanged(filter.$1),
                      ),
                    ),
                ],
              );
            },
          ),
          if (secondaryFilters.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              key: const ValueKey('asset-filter-secondary-row'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in secondaryFilters)
                  KeyedSubtree(
                    key: ValueKey(filter.$3),
                    child: StudioChip(
                      label: filter.$2,
                      icon: _assetFilterIcon(filter.$1),
                      selected: selectedFilter == filter.$1,
                      onTap: () => onFilterChanged(filter.$1),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '匹配素材 $resultCount',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              StudioIconButton(
                tooltip: '刷新素材索引',
                icon: Icons.refresh,
                onPressed: onReload,
              ),
              if (onAddAsset != null)
                StudioIconButton(
                  key: const ValueKey('asset-library-add-asset'),
                  tooltip: '添加素材',
                  icon: Icons.add_circle_outline,
                  onPressed: onAddAsset,
                ),
              if (onManagePromptCategories != null)
                StudioIconButton(
                  key: const ValueKey('asset-library-manage-categories'),
                  tooltip: '管理素材分类',
                  icon: Icons.category_outlined,
                  onPressed: onManagePromptCategories,
                ),
            ],
          ),
          if (catalogRefreshStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              catalogRefreshStatus!,
              key: const ValueKey('asset-catalog-refresh-status'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          ],
          if (selectedFilter == _AssetFilter.codex) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sourceScope in const [
                  (
                    StudioLegacyCodexCategories.sourceRegularKey,
                    '普通法典',
                    'asset-codex-source-regular',
                  ),
                  (
                    StudioLegacyCodexCategories.sourceAdultKey,
                    '涩涩法典',
                    'asset-codex-source-adult',
                  ),
                ])
                  KeyedSubtree(
                    key: ValueKey(sourceScope.$3),
                    child: StudioChip(
                      label: sourceScope.$2,
                      icon: Icons.library_books_outlined,
                      selected: selectedCodexSourceScopeKey == sourceScope.$1,
                      onTap: () => onCodexSourceScopeChanged(sourceScope.$1),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _codexCategories())
                  KeyedSubtree(
                    key: ValueKey('asset-codex-category-${category.key}'),
                    child: StudioChip(
                      label: category.label,
                      selected: selectedCodexCategoryKey == category.key,
                      onTap: () => onCodexCategoryChanged(category.key),
                    ),
                  ),
              ],
            ),
            if (codexTotalCount > codexLoadedCount) ...[
              const SizedBox(height: 8),
              Text('法典 $codexLoadedCount/$codexTotalCount'),
            ],
          ],
        ],
      ),
    );
  }
}

class _AssetFilterGalleryCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AssetFilterGalleryCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? StudioTokens.primary.withAlpha(18) : StudioTokens.surface3,
      shape: RoundedRectangleBorder(
        borderRadius: StudioTokens.radiusCard,
        side: BorderSide(
          color: selected ? StudioTokens.primary : StudioTokens.cardOutline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: StudioTokens.radiusCard,
        onTap: onTap,
        child: SizedBox(
          height: 82,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color:
                        selected ? StudioTokens.primary : StudioTokens.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? StudioTokens.surface1
                        : StudioTokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
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
        ),
      ),
    );
  }
}

class _AssetLibraryBody extends StatelessWidget {
  final List<_AssetDisplayItem> items;
  final _AssetDisplayItem? selectedAsset;
  final ValueChanged<_AssetDisplayItem> onSelect;
  final ValueChanged<_AssetDisplayItem> onToggleFavorite;
  final Set<String> favoriteKeys;
  final ValueChanged<_AssetDisplayItem> onCopy;
  final ValueChanged<_AssetDisplayItem> onGeneratePreview;
  final ValueChanged<_AssetDisplayItem>? onSendToScript;

  const _AssetLibraryBody({
    required this.items,
    required this.selectedAsset,
    required this.onSelect,
    required this.onToggleFavorite,
    required this.favoriteKeys,
    required this.onCopy,
    required this.onGeneratePreview,
    required this.onSendToScript,
  });

  @override
  Widget build(BuildContext context) {
    return _AssetWaterfallBoard(
      items: items,
      selectedAsset: selectedAsset,
      onSelect: onSelect,
      onToggleFavorite: onToggleFavorite,
      favoriteKeys: favoriteKeys,
      onCopy: onCopy,
      onGeneratePreview: onGeneratePreview,
      onSendToScript: onSendToScript,
    );
  }
}

class _AssetWaterfallBoard extends StatelessWidget {
  final List<_AssetDisplayItem> items;
  final _AssetDisplayItem? selectedAsset;
  final ValueChanged<_AssetDisplayItem> onSelect;
  final ValueChanged<_AssetDisplayItem> onToggleFavorite;
  final Set<String> favoriteKeys;
  final ValueChanged<_AssetDisplayItem> onCopy;
  final ValueChanged<_AssetDisplayItem> onGeneratePreview;
  final ValueChanged<_AssetDisplayItem>? onSendToScript;

  const _AssetWaterfallBoard({
    required this.items,
    required this.selectedAsset,
    required this.onSelect,
    required this.onToggleFavorite,
    required this.favoriteKeys,
    required this.onCopy,
    required this.onGeneratePreview,
    required this.onSendToScript,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyRow(message: 'No matching assets');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / 240).floor().clamp(1, 6).toInt();
        return WaterfallFlow.builder(
          key: const ValueKey('asset-library-waterfall-board'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _AssetCardStreamEntry(
              index: index,
              columns: columns,
              child: _WaterfallAssetCard(
                item: item,
                selected: selectedAsset?.key == item.key,
                onSelect: () => onSelect(item),
                onToggleFavorite: () => onToggleFavorite(item),
                isFavorite: favoriteKeys.contains(item.favoriteKey),
                onCopy: () => onCopy(item),
                onGeneratePreview: () => onGeneratePreview(item),
                onSendToScript:
                    onSendToScript == null ? null : () => onSendToScript!(item),
              ),
            );
          },
        );
      },
    );
  }
}

class _AssetCardStreamEntry extends StatelessWidget {
  final int index;
  final int columns;
  final Widget child;

  const _AssetCardStreamEntry({
    required this.index,
    required this.columns,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StudioStaggeredReveal(
      index: index,
      columns: columns,
      maxStaggeredItems: _AssetLibraryPageState._assetRenderBatchSize,
      duration: const Duration(milliseconds: 260),
      itemDelay: const Duration(milliseconds: 20),
      beginOffset: const Offset(0, 0.034),
      beginScale: 0.958,
      child: child,
    );
  }
}

class _WaterfallAssetCard extends StatelessWidget {
  final _AssetDisplayItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggleFavorite;
  final bool isFavorite;
  final VoidCallback onCopy;
  final VoidCallback onGeneratePreview;
  final VoidCallback? onSendToScript;

  const _WaterfallAssetCard({
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onToggleFavorite,
    required this.isFavorite,
    required this.onCopy,
    required this.onGeneratePreview,
    required this.onSendToScript,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('asset-card-${item.key}'),
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
        borderRadius: StudioTokens.radiusCard,
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (item.hasCardPreviewArea) ...[
                _AssetCardPreview(item: item),
                const SizedBox(height: 10),
              ],
              Text(
                item.title,
                key: ValueKey('asset-card-title-${item.key}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

class _AssetCardPreview extends StatelessWidget {
  final _AssetDisplayItem item;

  const _AssetCardPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final previewPath = item.previewPath;
    final previewCount = item.previewPaths.length;
    return AspectRatio(
      key: ValueKey('asset-card-preview-${item.key}'),
      aspectRatio: previewPath == null ? 3 / 4 : item.previewAspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (previewPath == null)
              const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: StudioTokens.textMuted,
                ),
              )
            else
              _ConstrainedAssetImage(
                path: previewPath,
                imageKey: ValueKey(
                  'asset-card-preview-image-${item.key}',
                ),
                fit: BoxFit.cover,
                maxDecodeExtent: _assetCardPreviewMaxDecodeExtent,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: StudioTokens.textMuted,
                    ),
                  );
                },
              ),
            if (previewCount > 1)
              Positioned(
                top: 8,
                right: 8,
                child: _PreviewCountBadge(
                  key: ValueKey(
                    'asset-card-preview-count-${item.key}',
                  ),
                  count: previewCount,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCountBadge extends StatelessWidget {
  final int count;

  const _PreviewCountBadge({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 13,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              '$count 张',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

int _nextPreviewIndex(int currentIndex, int count, double scrollDeltaY) {
  if (count <= 1 || scrollDeltaY == 0) return currentIndex;
  final next = currentIndex + (scrollDeltaY > 0 ? 1 : -1);
  if (next >= count) return 0;
  if (next < 0) return count - 1;
  return next;
}

class _PreviewCarouselDialog extends StatefulWidget {
  final String title;
  final String keySuffix;
  final List<String> previewPaths;
  final Future<void> Function()? onDeletePreview;

  _PreviewCarouselDialog({required _AssetDisplayItem item})
      : title = item.title,
        keySuffix = _previewCarouselKeySuffix(item),
        previewPaths = item.previewPaths,
        onDeletePreview = item.onDeletePreview;

  const _PreviewCarouselDialog.fromPaths({
    required this.title,
    required this.keySuffix,
    required this.previewPaths,
  }) : onDeletePreview = null;

  static String _previewCarouselKeySuffix(_AssetDisplayItem item) {
    return item.kind == _AssetKind.outfit
        ? 'outfit-${item.key.substring('outfit-'.length)}'
        : item.key;
  }

  @override
  State<_PreviewCarouselDialog> createState() => _PreviewCarouselDialogState();
}

class _PreviewCarouselDialogState extends State<_PreviewCarouselDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final previewPaths = widget.previewPaths;
    final count = previewPaths.length;
    final keySuffix = widget.keySuffix;

    return Dialog(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && count > 1) {
            setState(() {
              _index = _nextPreviewIndex(_index, count, event.scrollDelta.dy);
            });
          }
        },
        child: SizedBox(
          key: ValueKey('asset-preview-carousel-$keySuffix'),
          width: 520,
          height: 620,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${_index + 1}/$count',
                      key: const ValueKey('asset-preview-carousel-counter'),
                    ),
                    IconButton(
                      key: const ValueKey(
                        'asset-preview-carousel-reveal-file',
                      ),
                      tooltip: '在资源管理器中显示',
                      icon: const Icon(Icons.folder_open_outlined),
                      onPressed: _canRevealCurrentPreview
                          ? () => unawaited(_revealCurrentPreview())
                          : null,
                    ),
                    if (widget.onDeletePreview != null)
                      IconButton(
                        key: const ValueKey('asset-preview-carousel-delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _confirmDelete,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: StudioTokens.surface3,
                    borderRadius: StudioTokens.radiusSlot,
                  ),
                  child: ClipRRect(
                    borderRadius: StudioTokens.radiusSlot,
                    child: _ConstrainedAssetImage(
                      path: previewPaths[_index],
                      imageKey: ValueKey(
                        'asset-preview-carousel-image-$keySuffix-$_index',
                      ),
                      fit: BoxFit.contain,
                      maxDecodeExtent: _assetDialogPreviewMaxDecodeExtent,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: StudioTokens.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (var index = 0; index < count; index += 1)
                      Container(
                        key: ValueKey('asset-preview-carousel-dot-$index'),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _index
                              ? StudioTokens.primary
                              : StudioTokens.cardOutline,
                        ),
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('删除预览图？'),
        actions: [
          TextButton(
            key: const ValueKey('asset-preview-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onDeletePreview?.call();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  bool get _canRevealCurrentPreview {
    final path = _currentPreviewPath;
    return path != null && File(path).existsSync();
  }

  String? get _currentPreviewPath {
    if (widget.previewPaths.isEmpty) return null;
    final safeIndex = _index.clamp(0, widget.previewPaths.length - 1).toInt();
    return widget.previewPaths[safeIndex];
  }

  Future<void> _revealCurrentPreview() async {
    final path = _currentPreviewPath;
    if (path == null) return;
    try {
      await FileService().revealInFileManager(path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class _PreviewGenerationDecision {
  final bool keep;
  final String previewPath;

  const _PreviewGenerationDecision({
    required this.keep,
    required this.previewPath,
  });
}

class _PreviewGenerationOptionsDialog extends StatefulWidget {
  final String assetTitle;
  final bool showArtistSelector;
  final bool showCustomPrompt;
  final List<ArtistChain> artistChains;

  const _PreviewGenerationOptionsDialog({
    required this.assetTitle,
    required this.showArtistSelector,
    required this.showCustomPrompt,
    required this.artistChains,
  });

  @override
  State<_PreviewGenerationOptionsDialog> createState() =>
      _PreviewGenerationOptionsDialogState();
}

class _PreviewGenerationOptionsDialogState
    extends State<_PreviewGenerationOptionsDialog> {
  String _artistChainId = '';
  String _customPrompt = '';
  StudioPreviewCustomPromptMode _mode = StudioPreviewCustomPromptMode.append;
  GenerationSize? _selectedSize;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('asset-preview-options-dialog'),
      title: const Text('生成预览'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.assetTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StudioTokens.textMuted,
                    ),
              ),
              if (widget.showArtistSelector) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const ValueKey('asset-preview-options-artist-chain'),
                  initialValue: _artistChainId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '画师串',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('随机画师串'),
                    ),
                    for (final chain in widget.artistChains)
                      DropdownMenuItem<String>(
                        value: chain.id,
                        child: Text(
                          chain.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _artistChainId = value ?? '');
                  },
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<GenerationSize?>(
                key: const ValueKey('asset-preview-options-size'),
                initialValue: _selectedSize,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '分辨率',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<GenerationSize?>(
                    value: null,
                    child: Text('随机分辨率'),
                  ),
                  for (final size in defaultSizes)
                    DropdownMenuItem<GenerationSize?>(
                      value: size,
                      child: Text(_sizeLabel(size)),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _selectedSize = value);
                },
              ),
              if (widget.showCustomPrompt) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('asset-preview-options-mode-append'),
                      label: const Text('追加'),
                      selected: _mode == StudioPreviewCustomPromptMode.append,
                      onSelected: (_) {
                        setState(
                          () => _mode = StudioPreviewCustomPromptMode.append,
                        );
                      },
                    ),
                    ChoiceChip(
                      key: const ValueKey('asset-preview-options-mode-replace'),
                      label: const Text('替换'),
                      selected: _mode == StudioPreviewCustomPromptMode.replace,
                      onSelected: (_) {
                        setState(
                          () => _mode = StudioPreviewCustomPromptMode.replace,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: const ValueKey(
                    'asset-preview-options-custom-prompt-tags',
                  ),
                  child: PromptTagEditor(
                    value: _customPrompt,
                    label: '自填提示词',
                    dense: true,
                    initialGroupedLayout: false,
                    preferTranslatedLabels: true,
                    emptyText: '可添加标签或输入提示词',
                    onChanged: (nextValue) {
                      setState(() => _customPrompt = nextValue);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('asset-preview-options-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('asset-preview-options-start'),
          onPressed: () => Navigator.of(context).pop(
            StudioAssetPreviewGenerationOptions(
              artistChainId:
                  _artistChainId.trim().isEmpty ? null : _artistChainId,
              customPrompt: _customPrompt,
              customPromptMode: _mode,
              size: _selectedSize,
            ),
          ),
          child: const Text('开始生成'),
        ),
      ],
    );
  }

  static String _sizeLabel(GenerationSize size) {
    return '${size.width} x ${size.height}';
  }
}

class _PreviewGenerationDialog extends StatefulWidget {
  final String assetTitle;
  final Future<String> Function() generate;

  const _PreviewGenerationDialog({
    required this.assetTitle,
    required this.generate,
  });

  @override
  State<_PreviewGenerationDialog> createState() =>
      _PreviewGenerationDialogState();
}

class _PreviewGenerationDialogState extends State<_PreviewGenerationDialog> {
  late final Future<String> _generationFuture =
      Future<void>.delayed(Duration.zero).then((_) => widget.generate());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _generationFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AlertDialog(
            key: const ValueKey('asset-preview-generation-dialog'),
            title: const Text('预览图生成失败'),
            content: Text('${snapshot.error}'),
            actions: [
              TextButton(
                key: const ValueKey('asset-preview-generation-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return AlertDialog(
            key: const ValueKey('asset-preview-generation-dialog'),
            title: const Text('正在生成预览'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    widget.assetTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        final previewPath = snapshot.data!;
        return AlertDialog(
          key: const ValueKey('asset-preview-generation-dialog'),
          title: const Text('预览生成完成'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('要保留为这个素材的预览吗？'),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: StudioTokens.surface1,
                        border: StudioTokens.cardBorder,
                      ),
                      child: SizedBox(
                        height: 320,
                        child: _ConstrainedAssetImage(
                          path: previewPath,
                          imageKey: const ValueKey(
                            'asset-preview-generation-preview-image',
                          ),
                          fit: BoxFit.contain,
                          maxDecodeExtent: _assetDialogPreviewMaxDecodeExtent,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: StudioTokens.textMuted,
                                size: 42,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.assetTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StudioTokens.textMuted,
                        ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('asset-preview-generation-discard'),
              onPressed: () => Navigator.of(context).pop(
                _PreviewGenerationDecision(
                  keep: false,
                  previewPath: previewPath,
                ),
              ),
              child: const Text('不保留'),
            ),
            FilledButton(
              key: const ValueKey('asset-preview-generation-keep'),
              onPressed: () => Navigator.of(context).pop(
                _PreviewGenerationDecision(
                  keep: true,
                  previewPath: previewPath,
                ),
              ),
              child: const Text('保留为预览'),
            ),
          ],
        );
      },
    );
  }
}

class _AssetDetailDialog extends StatefulWidget {
  final _AssetDisplayItem initialAsset;
  final _AssetDisplayItem? Function() resolveAsset;
  final Future<void> Function(_AssetDisplayItem) onGeneratePreview;
  final bool Function() isFavorite;
  final Future<void> Function() onToggleFavorite;
  final VoidCallback? onSendToScript;

  const _AssetDetailDialog({
    required this.initialAsset,
    required this.resolveAsset,
    required this.onGeneratePreview,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onSendToScript,
  });

  @override
  State<_AssetDetailDialog> createState() => _AssetDetailDialogState();
}

class _AssetDetailDialogState extends State<_AssetDetailDialog> {
  Future<void> _generatePreview(_AssetDisplayItem item) async {
    await widget.onGeneratePreview(item);
    if (!mounted) return;
    setState(() {});
  }

  void _refreshAsset() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.resolveAsset() ?? widget.initialAsset;
    final size = MediaQuery.sizeOf(context);
    final maxDialogWidth = size.width >= 1400 ? 1180.0 : size.width * 0.92;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        key: ValueKey('asset-detail-dialog-${widget.initialAsset.key}'),
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: size.height * 0.9,
        ),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: _AssetDetailContent(
                  asset: item,
                  onGeneratePreview: _generatePreview,
                  onAssetChanged: _refreshAsset,
                  isFavorite: widget.isFavorite,
                  onToggleFavorite: () async {
                    await widget.onToggleFavorite();
                    _refreshAsset();
                  },
                  onSendToScript: widget.onSendToScript,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: StudioIconButton(
                  key: const ValueKey('asset-detail-dialog-close'),
                  tooltip: '关闭',
                  icon: Icons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetDetailContent extends StatefulWidget {
  final _AssetDisplayItem? asset;
  final Future<void> Function(_AssetDisplayItem) onGeneratePreview;
  final VoidCallback? onAssetChanged;
  final bool Function() isFavorite;
  final Future<void> Function() onToggleFavorite;
  final VoidCallback? onSendToScript;

  const _AssetDetailContent({
    required this.asset,
    required this.onGeneratePreview,
    this.onAssetChanged,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onSendToScript,
  });

  @override
  State<_AssetDetailContent> createState() => _AssetDetailContentState();
}

class _AssetDetailContentState extends State<_AssetDetailContent> {
  int? _selectedOutfitIndex;
  bool _showTranslatedTags = true;
  bool _vibesExpanded = false;
  List<WorkspaceVibeReference> _availableVibes = const [];
  List<WorkspaceVibeReference>? _boundVibes;

  @override
  void didUpdateWidget(covariant _AssetDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset?.key != widget.asset?.key) {
      _selectedOutfitIndex = null;
      _showTranslatedTags = true;
      _vibesExpanded = false;
      _availableVibes = const [];
      _boundVibes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.asset;
    if (item == null) {
      return const StudioPanel(
        key: ValueKey('asset-library-detail-content'),
        color: StudioTokens.surface2,
        child: _EmptyRow(message: '选择一张素材卡片查看详情'),
      );
    }
    final previewPane = _buildPreviewPane(item);
    final editorPane = _buildEditorPane(item);
    final compactNoPreview = item.hasCompactNoPreview;

    return StudioPanel(
      key: const ValueKey('asset-library-detail-content'),
      color: StudioTokens.surface2,
      padding: const EdgeInsets.fromLTRB(
        StudioTokens.panelPadding,
        StudioTokens.panelPadding,
        StudioTokens.panelPadding + _assetDetailCloseButtonReserve,
        StudioTokens.panelPadding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final previewWidth =
              (constraints.maxWidth * 0.46).clamp(420.0, 560.0).toDouble();
          final editorWidth = (constraints.maxWidth - previewWidth - 22)
              .clamp(420.0, 620.0)
              .toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(item),
              const SizedBox(height: 18),
              if (wide && !compactNoPreview)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: previewWidth, child: previewPane),
                    const SizedBox(width: 22),
                    SizedBox(width: editorWidth, child: editorPane),
                  ],
                )
              else ...[
                if (!compactNoPreview) ...[
                  previewPane,
                  const SizedBox(height: 16),
                ],
                editorPane,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(_AssetDisplayItem item) {
    final titleBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioChip(
          label: item.typeLabel,
          icon: item.icon,
          selected: true,
          accentColor: StudioTokens.primary,
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _DetailFavoriteButton(
          key: const ValueKey('asset-detail-favorite'),
          tooltip: widget.isFavorite() ? '取消收藏' : '收藏',
          selected: widget.isFavorite(),
          onPressed: () => unawaited(widget.onToggleFavorite()),
        ),
        StudioButton(
          key: const ValueKey('asset-detail-send'),
          label: '发送到工作台',
          icon: Icons.keyboard_return,
          onPressed: item.onSend,
          tone: StudioButtonTone.ghost,
        ),
        if (item.scriptFocus != null)
          StudioButton(
            key: const ValueKey('asset-detail-send-script'),
            label: '发送到剧本',
            icon: Icons.outbox_outlined,
            onPressed: widget.onSendToScript,
            tone: StudioButtonTone.ghost,
          ),
        StudioButton(
          key: const ValueKey('asset-detail-copy'),
          label: '复制串词',
          icon: Icons.copy_outlined,
          onPressed: () => _copyPrompt(item),
          tone: StudioButtonTone.ghost,
        ),
        if (item.character != null || item.artistChain != null)
          StudioButton(
            key: const ValueKey('asset-detail-translation-toggle'),
            label: _showTranslatedTags ? '译文优先' : '原文优先',
            icon: _showTranslatedTags
                ? Icons.translate_outlined
                : Icons.code_outlined,
            onPressed: () => setState(() {
              _showTranslatedTags = !_showTranslatedTags;
            }),
            tone: StudioButtonTone.ghost,
          ),
        if (item.onEdit != null)
          StudioIconButton(
            key: const ValueKey('asset-detail-edit-asset'),
            tooltip: '编辑素材',
            icon: Icons.edit_outlined,
            onPressed: item.onEdit,
          ),
        if (item.onDelete != null)
          StudioIconButton(
            key: const ValueKey('asset-detail-delete-asset'),
            tooltip: '删除素材',
            icon: Icons.delete_outline,
            onPressed: () => unawaited(_deleteAndClose(item)),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildPreviewPane(_AssetDisplayItem item) {
    if (item.character != null && item.character!.outfits.isNotEmpty) {
      return _CharacterOutfitDetailSection(
        character: item.character!,
        outfitPreviewPathsById: item.outfitPreviewPathsById,
        selectedOutfitIndex: _selectedOutfitIndex,
        onSelectOutfit: (outfitIndex) => setState(() {
          _selectedOutfitIndex = outfitIndex;
        }),
        onGeneratePreview: item.canGeneratePreview
            ? () => unawaited(_handleGeneratePreview(item))
            : null,
        onEditOutfit: item.onEditOutfit,
        onDuplicateOutfit: item.onDuplicateOutfit,
        onDeleteOutfit: item.onDeleteOutfit,
        onDeleteOutfitPreview: item.onDeleteOutfitPreview,
        onAssetChanged: widget.onAssetChanged,
      );
    }
    return _AssetPreviewStage(
      item: item,
      onGeneratePreview: item.canGeneratePreview
          ? () => unawaited(_handleGeneratePreview(item))
          : null,
      onDeletePreview: item.onDeletePreview == null || item.previewPaths.isEmpty
          ? null
          : () => unawaited(_deletePreview(item)),
    );
  }

  Widget _buildEditorPane(_AssetDisplayItem item) {
    final promptEditableSurface = item.kind == _AssetKind.character ||
        item.kind == _AssetKind.artistChain;
    final selectedOutfit = _selectedOutfitFor(item);
    final selectedOutfitPreviewPaths = selectedOutfit == null
        ? null
        : item.character == null
            ? item.previewPaths
            : _outfitPreviewPathsFor(
                item.character!,
                selectedOutfit.index,
                selectedOutfit.outfit,
                item.outfitPreviewPathsById,
              );
    return KeyedSubtree(
      key: ValueKey('asset-detail-editor-pane-${item.key}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AssetDetailInfoStrip(
            item: item,
            previewCountOverride: selectedOutfitPreviewPaths?.length,
            referenceCountOverride: selectedOutfit?.outfit.imageRefs.length,
          ),
          if (item.character != null) ...[
            const SizedBox(height: 12),
            _buildCharacterActions(item),
          ],
          if (item.artistChain != null) ...[
            const SizedBox(height: 12),
            _buildArtistChainActions(item),
          ],
          const SizedBox(height: 12),
          if (item.character != null)
            ..._buildCharacterPromptEditors(item, selectedOutfit)
          else if (item.summary.isNotEmpty && item.kind != _AssetKind.outfit)
            if (promptEditableSurface)
              _AssetDetailPromptEditor(
                item: item,
                preferTranslatedLabels: _showTranslatedTags,
                onChanged: (prompt) => unawaited(
                  _savePromptTags(item, prompt),
                ),
              )
            else
              _AssetReadOnlyPromptBlock(
                item: item,
                translated: _showTranslatedTags,
                onToggleTranslated: () => setState(() {
                  _showTranslatedTags = !_showTranslatedTags;
                }),
              ),
          if ((item.inspiration?.variants ?? const []).isNotEmpty) ...[
            const SizedBox(height: 12),
            _AssetCodexVariantSection(
              variants: item.inspiration!.variants,
              translated: _showTranslatedTags,
            ),
          ],
          if (selectedOutfit != null && item.character == null) ...[
            const SizedBox(height: 12),
            _AssetDetailPromptEditor(
              item: item,
              keySuffix: '${item.key}-outfit-${selectedOutfit.index}',
              labelOverride: '服装提示',
              valueOverride: selectedOutfit.outfit.tags.frontFull,
              onChanged: (prompt) => unawaited(
                _saveOutfitTags(item, selectedOutfit.index, prompt),
              ),
            ),
          ],
          if (!promptEditableSurface && item.details.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AssetCompactInfo(details: item.details),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildCharacterPromptEditors(
    _AssetDisplayItem item,
    ({int index, WorkspaceOutfit outfit})? selectedOutfit,
  ) {
    final character = item.character!;
    final editors = <Widget>[];

    void addEditor({
      required String keySuffix,
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      bool showWhenEmpty = false,
    }) {
      if (!showWhenEmpty && value.trim().isEmpty) return;
      if (editors.isNotEmpty) editors.add(const SizedBox(height: 12));
      editors.add(
        _AssetDetailPromptEditor(
          item: item,
          keySuffix: keySuffix,
          labelOverride: label,
          valueOverride: value,
          preferTranslatedLabels: _showTranslatedTags,
          initialGroupedLayout: false,
          onChanged: onChanged,
        ),
      );
    }

    final selectedPartTags = selectedOutfit?.outfit.partTags;
    final selectedHasStructuredPartTags =
        selectedPartTags != null && !selectedPartTags.isEmpty;
    final characterFieldKeys = <String>{
      if (selectedHasStructuredPartTags)
        ..._assetPromptKeysFromTags([
          ...selectedPartTags.upperBodyTags,
          ...selectedPartTags.lowerBodyTags,
        ]),
    };
    final seenPromptKeys = <String>{};
    final characterIdentityTags = [
      ...character.anchorTags,
      ...character.identityTags,
    ];
    final characterPrompt = characterIdentityTags.isNotEmpty
        ? _assetPromptFromTags(
            characterIdentityTags,
            seenKeys: seenPromptKeys,
            omitKeys: characterFieldKeys,
          )
        : _assetPromptFromValue(
            character.traits.frontFull,
            seenKeys: seenPromptKeys,
            omitKeys: characterFieldKeys,
          );

    addEditor(
      keySuffix: item.key,
      label: '角色',
      value: characterPrompt,
      showWhenEmpty: true,
      onChanged: (prompt) => unawaited(
        _saveCharacterFieldTags(
          item,
          _CharacterPromptField.identity,
          prompt,
        ),
      ),
    );

    if (selectedOutfit == null) return editors;
    final outfit = selectedOutfit.outfit;
    final partTags = outfit.partTags;
    final upperBodyPrompt = _assetPromptFromTags(
      partTags.upperBodyTags,
      seenKeys: seenPromptKeys,
    );
    addEditor(
      keySuffix: '${item.key}-outfit-${selectedOutfit.index}-upper-body',
      label: '上身',
      value: upperBodyPrompt,
      showWhenEmpty: true,
      onChanged: (prompt) => unawaited(
        _saveOutfitFieldTags(
          item,
          selectedOutfit.index,
          _OutfitPromptField.upperBody,
          prompt,
        ),
      ),
    );

    var upperClothingPrompt = _assetPromptFromTags(
      partTags.upperClothingTags,
      seenKeys: seenPromptKeys,
    );
    if (upperClothingPrompt.trim().isEmpty) {
      upperClothingPrompt = partTags.isEmpty
          ? _assetPromptFromValue(
              outfit.tags.frontFull,
              seenKeys: seenPromptKeys,
            )
          : _assetPromptFromValue(
              outfit.tags.frontUpper ?? '',
              seenKeys: seenPromptKeys,
            );
    }
    addEditor(
      keySuffix: '${item.key}-outfit-${selectedOutfit.index}-upper-clothing',
      label: '上装',
      value: upperClothingPrompt,
      showWhenEmpty: true,
      onChanged: (prompt) => unawaited(
        _saveOutfitFieldTags(
          item,
          selectedOutfit.index,
          _OutfitPromptField.upperClothing,
          prompt,
        ),
      ),
    );

    final lowerBodyPrompt = _assetPromptFromTags(
      partTags.lowerBodyTags,
      seenKeys: seenPromptKeys,
    );
    addEditor(
      keySuffix: '${item.key}-outfit-${selectedOutfit.index}-lower-body',
      label: '下身',
      value: lowerBodyPrompt,
      showWhenEmpty: true,
      onChanged: (prompt) => unawaited(
        _saveOutfitFieldTags(
          item,
          selectedOutfit.index,
          _OutfitPromptField.lowerBody,
          prompt,
        ),
      ),
    );

    var lowerClothingPrompt = _assetPromptFromTags(
      partTags.lowerClothingTags,
      seenKeys: seenPromptKeys,
    );
    if (lowerClothingPrompt.trim().isEmpty && !partTags.isEmpty) {
      lowerClothingPrompt = _assetPromptFromValue(
        outfit.tags.frontLower ?? '',
        seenKeys: seenPromptKeys,
      );
    }
    addEditor(
      keySuffix: '${item.key}-outfit-${selectedOutfit.index}-lower-clothing',
      label: '下装',
      value: lowerClothingPrompt,
      showWhenEmpty: true,
      onChanged: (prompt) => unawaited(
        _saveOutfitFieldTags(
          item,
          selectedOutfit.index,
          _OutfitPromptField.lowerClothing,
          prompt,
        ),
      ),
    );
    return editors;
  }

  ({int index, WorkspaceOutfit outfit})? _selectedOutfitFor(
    _AssetDisplayItem item,
  ) {
    if (item.outfit != null && item.outfitIndex != null) {
      return (index: item.outfitIndex!, outfit: item.outfit!);
    }
    final character = item.character;
    if (character == null || character.outfits.isEmpty) return null;
    return _outfitAtSelection(character, _selectedOutfitIndex);
  }

  Future<void> _saveOutfitTags(
    _AssetDisplayItem item,
    int outfitIndex,
    String prompt,
  ) async {
    await item.onOutfitPromptChanged?.call(outfitIndex, prompt);
    widget.onAssetChanged?.call();
  }

  Future<void> _saveCharacterFieldTags(
    _AssetDisplayItem item,
    _CharacterPromptField field,
    String prompt,
  ) async {
    await item.onCharacterPromptFieldChanged?.call(field, prompt);
    widget.onAssetChanged?.call();
  }

  Future<void> _saveOutfitFieldTags(
    _AssetDisplayItem item,
    int outfitIndex,
    _OutfitPromptField field,
    String prompt,
  ) async {
    await item.onOutfitPromptFieldChanged?.call(outfitIndex, field, prompt);
    widget.onAssetChanged?.call();
  }

  Widget _buildArtistChainActions(_AssetDisplayItem item) {
    final artistChain = item.artistChain!;
    final boundVibes = _boundVibes ?? artistChain.vibeRefs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '画师串操作',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (item.onLoadVibes != null)
              _DetailActionChip(
                key: const ValueKey('asset-artist-vibe-options-toggle'),
                label: 'Vibe',
                onTap: () => _toggleVibeOptions(item),
              ),
            if (item.onImportVibes != null)
              _DetailActionChip(
                key: const ValueKey('asset-artist-vibe-import'),
                label: '导入 Vibe',
                onTap: () => _importVibe(item),
              ),
            if (item.onDuplicateArtistChain != null)
              _DetailActionChip(
                key: const ValueKey('asset-detail-duplicate-artist-chain'),
                label: '复制',
                onTap: () => unawaited(
                  _runAndRefresh(item.onDuplicateArtistChain!),
                ),
              ),
            if (item.onRenameArtistChain != null)
              _DetailActionChip(
                key: const ValueKey('asset-detail-rename-artist-chain'),
                label: '重命名',
                onTap: () => _showRenameDialog(item),
              ),
          ],
        ),
        if (boundVibes.isNotEmpty && !_vibesExpanded) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final vibe in boundVibes)
                StudioChip(
                  key: ValueKey('asset-artist-vibe-binding-${vibe.id}'),
                  label: vibe.name,
                  icon: Icons.auto_awesome_outlined,
                ),
            ],
          ),
        ],
        if (_vibesExpanded) ...[
          const SizedBox(height: 10),
          for (final vibe in _availableVibes)
            SwitchListTile(
              key: ValueKey('asset-artist-vibe-binding-${vibe.id}'),
              value: boundVibes.any((bound) => bound.id == vibe.id),
              title: Text(vibe.name),
              onChanged: (_) => _bindVibe(item, vibe),
            ),
          for (final vibe in boundVibes)
            Slider(
              key: ValueKey('asset-artist-vibe-strength-${vibe.id}'),
              value: vibe.referenceStrength.clamp(0, 1),
              onChanged: (_) {},
              onChangeEnd: (value) => _bindVibe(
                item,
                vibe.copyWith(referenceStrength: value),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildCharacterActions(_AssetDisplayItem item) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (item.onAddOutfit != null)
          _DetailActionChip(
            key: const ValueKey('asset-detail-add-outfit'),
            label: '新增服装',
            onTap: () => unawaited(_runAndRefresh(item.onAddOutfit!)),
          ),
        if (item.onDuplicateCharacter != null)
          _DetailActionChip(
            key: const ValueKey('asset-detail-duplicate-character'),
            label: '复制',
            onTap: item.onDuplicateCharacter!,
          ),
      ],
    );
  }

  Future<void> _handleGeneratePreview(_AssetDisplayItem item) async {
    await widget.onGeneratePreview(item);
    widget.onAssetChanged?.call();
  }

  Future<void> _runAndRefresh(Future<void> Function() action) async {
    await action();
    widget.onAssetChanged?.call();
  }

  Future<void> _savePromptTags(_AssetDisplayItem item, String prompt) async {
    await item.onPromptChanged?.call(prompt);
    widget.onAssetChanged?.call();
  }

  Future<void> _copyPrompt(_AssetDisplayItem item) async {
    await Clipboard.setData(ClipboardData(text: item.copyText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制提示词')),
    );
  }

  Future<void> _deletePreview(_AssetDisplayItem item) async {
    await item.onDeletePreview?.call();
    widget.onAssetChanged?.call();
  }

  Future<void> _deleteAndClose(_AssetDisplayItem item) async {
    await item.onDelete?.call();
    widget.onAssetChanged?.call();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _toggleVibeOptions(_AssetDisplayItem item) async {
    if (_vibesExpanded) {
      setState(() => _vibesExpanded = false);
      return;
    }
    final vibes = await item.onLoadVibes?.call() ?? const [];
    if (!mounted) return;
    setState(() {
      _availableVibes = vibes;
      _vibesExpanded = true;
    });
  }

  Future<void> _importVibe(_AssetDisplayItem item) async {
    final imported = await item.onImportVibes?.call() ?? const [];
    if (imported.isEmpty) return;
    await _bindVibe(item, imported.first);
  }

  Future<void> _bindVibe(
    _AssetDisplayItem item,
    WorkspaceVibeReference vibe,
  ) async {
    final artistChain = item.artistChain;
    if (artistChain == null) return;
    final updatedVibes = [
      for (final bound in _boundVibes ?? artistChain.vibeRefs)
        if (bound.id != vibe.id) bound,
      vibe,
    ];
    await item.onSaveArtistChain?.call(
      artistChain.copyWith(vibeRefs: updatedVibes),
    );
    if (!mounted) return;
    setState(() => _boundVibes = updatedVibes);
    widget.onAssetChanged?.call();
  }

  Future<void> _showRenameDialog(_AssetDisplayItem item) async {
    final controller =
        TextEditingController(text: item.artistChain?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: TextField(
          key: const ValueKey('asset-artist-chain-name-field'),
          controller: controller,
        ),
        actions: [
          TextButton(
            key: const ValueKey('asset-artist-chain-rename-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await item.onRenameArtistChain?.call(name);
    widget.onAssetChanged?.call();
  }
}

class _DetailFavoriteButton extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;

  const _DetailFavoriteButton({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected ? StudioTokens.primary : StudioTokens.surface3;
    return SizedBox.square(
      dimension: 36,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          iconSize: 20,
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return StudioTokens.textMuted;
              }
              return selected
                  ? StudioTokens.onPrimary
                  : StudioTokens.textSecondary;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return StudioTokens.surface2;
              }
              if (states.contains(WidgetState.pressed)) {
                return Color.lerp(background, Colors.black, 0.08);
              }
              if (states.contains(WidgetState.hovered)) {
                return selected
                    ? StudioTokens.secondary
                    : StudioTokens.surface2;
              }
              return background;
            }),
            shape: WidgetStateProperty.all(const CircleBorder()),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(selected ? Icons.star : Icons.star_border),
        ),
      ),
    );
  }
}

class _AssetPreviewStage extends StatefulWidget {
  final _AssetDisplayItem item;
  final VoidCallback? onGeneratePreview;
  final VoidCallback? onDeletePreview;

  const _AssetPreviewStage({
    required this.item,
    this.onGeneratePreview,
    this.onDeletePreview,
  });

  @override
  State<_AssetPreviewStage> createState() => _AssetPreviewStageState();
}

class _AssetPreviewStageState extends State<_AssetPreviewStage> {
  int _previewIndex = 0;
  bool _previewHovered = false;

  @override
  void didUpdateWidget(covariant _AssetPreviewStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.key != widget.item.key) {
      _previewIndex = 0;
      _previewHovered = false;
    }
    _clampPreviewIndex(widget.item.previewPaths.length);
  }

  void _clampPreviewIndex(int count) {
    if (count <= 0) {
      _previewIndex = 0;
    } else if (_previewIndex >= count) {
      _previewIndex = count - 1;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final count = widget.item.previewPaths.length;
    if (event is! PointerScrollEvent || count <= 1) return;
    final currentIndex = _previewIndex.clamp(0, count - 1).toInt();
    final nextIndex =
        _nextPreviewIndex(currentIndex, count, event.scrollDelta.dy);
    if (nextIndex == currentIndex) return;
    setState(() {
      _previewIndex = nextIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final previewPaths = item.previewPaths;
    final activeIndex = previewPaths.isEmpty
        ? 0
        : _previewIndex.clamp(0, previewPaths.length - 1).toInt();
    final previewPath = previewPaths.isEmpty ? null : previewPaths[activeIndex];
    final hasPreview = previewPath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasPreview)
          StudioInteractiveSurface(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: _handlePointerSignal,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _previewHovered = true),
                onExit: (_) => setState(() => _previewHovered = false),
                child: GestureDetector(
                  key: ValueKey('asset-detail-preview-${item.key}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => _PreviewCarouselDialog(item: item),
                  ),
                  child: Stack(
                    children: [
                      _AssetPreviewFrame(
                        hovered: _previewHovered,
                        child: _ConstrainedAssetImage(
                          path: previewPath,
                          imageKey: ValueKey(
                              'asset-detail-preview-image-${item.key}'),
                          fit: BoxFit.contain,
                          maxDecodeExtent: _assetDetailPreviewMaxDecodeExtent,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: StudioTokens.textMuted,
                                size: 42,
                              ),
                            );
                          },
                        ),
                      ),
                      if (previewPaths.length > 1)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: _PreviewCountBadge(
                            key: ValueKey(
                                'asset-detail-preview-count-${item.key}'),
                            count: previewPaths.length,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          _AssetPreviewFrame(
            key: ValueKey('asset-detail-preview-empty-${item.key}'),
            child: const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: StudioTokens.textMuted,
                size: 42,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (previewPaths.isNotEmpty)
          _PreviewDots(
            count: previewPaths.length,
            activeIndex: activeIndex,
            keyBuilder: (index) => ValueKey(
              'asset-detail-preview-dot-${item.key}-$index',
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (widget.onDeletePreview != null)
              StudioButton(
                key: ValueKey('asset-detail-delete-preview-${item.key}'),
                label: '删除预览',
                icon: Icons.delete_outline,
                onPressed: widget.onDeletePreview,
                tone: StudioButtonTone.danger,
              ),
            if (widget.onGeneratePreview != null)
              StudioButton(
                key: ValueKey(
                  'asset-detail-generate-preview-${item.previewKind}-${item.assetId}',
                ),
                label: hasPreview ? '新增预览' : '立即生成',
                icon: Icons.add_photo_alternate_outlined,
                onPressed: widget.onGeneratePreview,
                tone: hasPreview
                    ? StudioButtonTone.ghost
                    : StudioButtonTone.primary,
              ),
          ],
        ),
      ],
    );
  }
}

class _AssetPreviewFrame extends StatelessWidget {
  final Widget child;
  final bool hovered;

  const _AssetPreviewFrame({
    super.key,
    required this.child,
    this.hovered = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 520.0;
        final height = (width * 1.08).clamp(360.0, 560.0).toDouble();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: height,
          decoration: BoxDecoration(
            color: hovered ? StudioTokens.surface2 : StudioTokens.surface1,
            borderRadius: StudioTokens.radiusSlot,
            border: hovered
                ? Border.all(color: StudioTokens.primary, width: 1.5)
                : StudioTokens.cardBorder,
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}

class _ConstrainedAssetImage extends StatelessWidget {
  final String path;
  final Key? imageKey;
  final BoxFit fit;
  final int maxDecodeExtent;
  final ImageErrorWidgetBuilder? errorBuilder;

  const _ConstrainedAssetImage({
    required this.path,
    this.imageKey,
    required this.fit,
    required this.maxDecodeExtent,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Image(
      key: imageKey,
      image: ResizeImage(
        FileImage(File(path)),
        width: maxDecodeExtent,
        height: maxDecodeExtent,
        policy: ResizeImagePolicy.fit,
      ),
      fit: fit,
      filterQuality: FilterQuality.low,
      errorBuilder: errorBuilder,
    );
  }
}

class _PreviewDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  final Key Function(int index) keyBuilder;

  const _PreviewDots({
    required this.count,
    required this.activeIndex,
    required this.keyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      children: [
        for (var index = 0; index < count; index++)
          Container(
            key: keyBuilder(index),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: index == activeIndex
                  ? StudioTokens.primary
                  : StudioTokens.cardOutline,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class _AssetReadOnlyPromptBlock extends StatelessWidget {
  final _AssetDisplayItem item;
  final bool translated;
  final VoidCallback onToggleTranslated;

  const _AssetReadOnlyPromptBlock({
    required this.item,
    required this.translated,
    required this.onToggleTranslated,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      padding: const EdgeInsets.all(12),
      color: StudioTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '提示词',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              StudioButton(
                key: const ValueKey('asset-detail-translation-toggle'),
                label: translated ? '译文优先' : '原文优先',
                onPressed: onToggleTranslated,
                tone: StudioButtonTone.ghost,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DetailPromptTagPreview(
            text: item.summary,
            translated: translated,
          ),
        ],
      ),
    );
  }
}

class _AssetDetailInfoStrip extends StatelessWidget {
  final _AssetDisplayItem item;
  final int? previewCountOverride;
  final int? referenceCountOverride;

  const _AssetDetailInfoStrip({
    required this.item,
    this.previewCountOverride,
    this.referenceCountOverride,
  });

  @override
  Widget build(BuildContext context) {
    final previewCount = previewCountOverride ??
        (item.character == null
            ? item.previewPaths.length
            : item.previewPaths.length);
    final referenceCount = referenceCountOverride ??
        (item.referencePaths.length +
            (item.character == null
                ? 0
                : item.character!.outfits.fold<int>(
                    0,
                    (total, outfit) => total + outfit.imageRefs.length,
                  )));
    final entries = <(String, String)>[
      ('ID', item.assetId),
      if (item.character != null) ('服装', '${item.character!.outfits.length} 套'),
      if (item.artistChain?.vibeRefs.isNotEmpty ?? false)
        ('Vibe', '${item.artistChain!.vibeRefs.length} 个'),
      ('预览', '$previewCount 张'),
      if (referenceCount > 0) ('引用', '$referenceCount 张'),
    ];

    return Container(
      key: ValueKey('asset-detail-info-strip-${item.key}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface1,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in entries)
            _AssetDetailInfoPill(label: entry.$1, value: entry.$2),
        ],
      ),
    );
  }
}

class _AssetDetailInfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _AssetDetailInfoPill({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTokens.cardOutline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StudioTokens.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetCompactInfo extends StatelessWidget {
  final List<_AssetDetailLine> details;

  const _AssetCompactInfo({required this.details});

  @override
  Widget build(BuildContext context) {
    final visibleDetails = details
        .where((detail) {
          final label = detail.label.toLowerCase();
          return label != 'prompt' && label != 'tags';
        })
        .take(4)
        .toList(growable: false);
    if (visibleDetails.isEmpty) return const SizedBox.shrink();
    return StudioPanel(
      padding: const EdgeInsets.all(12),
      color: StudioTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '基础信息',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          for (final detail in visibleDetails) ...[
            Text(
              detail.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              detail.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _AssetCodexVariantSection extends StatelessWidget {
  final List<InspirationEntry> variants;
  final bool translated;

  const _AssetCodexVariantSection({
    required this.variants,
    required this.translated,
  });

  @override
  Widget build(BuildContext context) {
    if (variants.isEmpty) return const SizedBox.shrink();
    return StudioPanel(
      key: const ValueKey('asset-detail-codex-variants'),
      padding: const EdgeInsets.all(12),
      color: StudioTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '其他版本',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          for (final variant in variants) ...[
            Text(
              variant.sourceVariantLabel?.trim().isNotEmpty == true
                  ? variant.sourceVariantLabel!
                  : variant.name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (variant.prompt.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              KeyedSubtree(
                key: ValueKey('asset-detail-codex-variant-${variant.id}'),
                child: _DetailPromptTagPreview(
                  text: variant.prompt,
                  translated: translated,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DetailPromptTagPreview extends StatelessWidget {
  final String text;
  final bool translated;

  const _DetailPromptTagPreview({
    required this.text,
    required this.translated,
  });

  @override
  Widget build(BuildContext context) {
    final translationCache = GetIt.I.isRegistered<TranslationCache>()
        ? GetIt.I<TranslationCache>()
        : null;
    final classificationCache =
        GetIt.I.isRegistered<PromptTagClassificationCache>()
            ? GetIt.I<PromptTagClassificationCache>()
            : null;
    return PromptTagDisplay(
      key: const ValueKey('asset-detail-prompt-tag-display'),
      text: text,
      defaultTranslated: translated,
      dense: true,
      enableHoverShortcut: true,
      enableTagActions: true,
      translationCache: translationCache,
      classificationCache: classificationCache,
      initialLayoutMode: PromptTagLayoutMode.sourceOrder,
      respectInitialLayoutMode: true,
      showSelectionToolbar: false,
      emptyText: '暂无标签',
    );
  }
}

class _DetailActionChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _DetailActionChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<_DetailActionChip> createState() => _DetailActionChipState();
}

class _DetailActionChipState extends State<_DetailActionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 88),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? StudioTokens.surface4 : StudioTokens.surface3,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? StudioTokens.primary : StudioTokens.cardOutline,
            ),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _hovered
                      ? StudioTokens.textPrimary
                      : StudioTokens.textSecondary,
                ),
          ),
        ),
      ),
    );
  }
}

class _AssetDetailPromptEditor extends StatelessWidget {
  final _AssetDisplayItem item;
  final ValueChanged<String> onChanged;
  final String? keySuffix;
  final String? labelOverride;
  final String? valueOverride;
  final bool initialGroupedLayout;
  final bool preferTranslatedLabels;

  const _AssetDetailPromptEditor({
    required this.item,
    required this.onChanged,
    this.keySuffix,
    this.labelOverride,
    this.valueOverride,
    this.initialGroupedLayout = false,
    this.preferTranslatedLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = item.kind == _AssetKind.artistChain ? '画师串词' : '角色词';
    return KeyedSubtree(
      key: ValueKey('asset-detail-prompt-editor-${keySuffix ?? item.key}'),
      child: PromptTagEditor(
        value: valueOverride ?? item.summary,
        label: labelOverride ?? label,
        dense: true,
        showControls: false,
        inlineLabel: true,
        inlineLabelWidth: 72,
        initialGroupedLayout: initialGroupedLayout,
        preferTranslatedLabels: preferTranslatedLabels,
        emptyText: '暂无标签',
        onChanged: onChanged,
      ),
    );
  }
}

class _OutfitIconTile extends StatefulWidget {
  final WorkspaceOutfit outfit;
  final String? previewPath;
  final bool selected;

  const _OutfitIconTile({
    required this.outfit,
    required this.previewPath,
    required this.selected,
  });

  @override
  State<_OutfitIconTile> createState() => _OutfitIconTileState();
}

class _OutfitIconTileState extends State<_OutfitIconTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.outfit.name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _hovered ? StudioTokens.surface4 : StudioTokens.surface3,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered || widget.selected
                  ? StudioTokens.primary
                  : StudioTokens.cardOutline,
              width: _hovered || widget.selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.previewPath == null
              ? Icon(
                  Icons.checkroom_outlined,
                  color: _hovered || widget.selected
                      ? StudioTokens.primary
                      : StudioTokens.textMuted,
                )
              : _ConstrainedAssetImage(
                  path: widget.previewPath!,
                  fit: BoxFit.cover,
                  maxDecodeExtent: _assetOutfitIconMaxDecodeExtent,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.checkroom_outlined,
                      color: _hovered || widget.selected
                          ? StudioTokens.primary
                          : StudioTokens.textMuted,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

({int index, WorkspaceOutfit outfit}) _outfitAtSelection(
  CharacterEntry character,
  int? selectedOutfitIndex,
) {
  if (selectedOutfitIndex != null &&
      selectedOutfitIndex >= 0 &&
      selectedOutfitIndex < character.outfits.length) {
    return (
      index: selectedOutfitIndex,
      outfit: character.outfits[selectedOutfitIndex],
    );
  }
  final defaultIndex = character.defaultOutfitId == null
      ? -1
      : character.outfits.indexWhere(
          (outfit) => outfit.id == character.defaultOutfitId,
        );
  final index = defaultIndex >= 0 ? defaultIndex : 0;
  return (index: index, outfit: character.outfits[index]);
}

String _outfitSlotKey(String characterId, int index, WorkspaceOutfit outfit) {
  return '$characterId:$index:${outfit.id}';
}

String _outfitPreviewCacheKey(
  String characterId,
  int index,
  WorkspaceOutfit outfit,
) {
  return 'outfit-$characterId-$index-${outfit.id}';
}

String _outfitDisplayKey(
  CharacterEntry character,
  int index,
  WorkspaceOutfit outfit,
) {
  return 'outfit-${character.id}-${_outfitWidgetKey(character, index, outfit)}';
}

List<String> _outfitPreviewPathsFor(
  CharacterEntry character,
  int index,
  WorkspaceOutfit outfit,
  Map<String, List<String>> outfitPreviewPathsById,
) {
  return outfitPreviewPathsById[_outfitSlotKey(character.id, index, outfit)] ??
      outfitPreviewPathsById[outfit.id] ??
      const [];
}

String _outfitWidgetKey(
  CharacterEntry character,
  int index,
  WorkspaceOutfit outfit,
) {
  final duplicateIdCount =
      character.outfits.where((entry) => entry.id == outfit.id).length;
  return duplicateIdCount > 1 ? '${outfit.id}-$index' : outfit.id;
}

class _CharacterOutfitDetailSection extends StatefulWidget {
  final CharacterEntry character;
  final Map<String, List<String>> outfitPreviewPathsById;
  final int? selectedOutfitIndex;
  final ValueChanged<int> onSelectOutfit;
  final VoidCallback? onGeneratePreview;
  final Future<void> Function(WorkspaceOutfit)? onEditOutfit;
  final Future<void> Function(WorkspaceOutfit)? onDuplicateOutfit;
  final Future<void> Function(WorkspaceOutfit)? onDeleteOutfit;
  final Future<void> Function(int, WorkspaceOutfit)? onDeleteOutfitPreview;
  final VoidCallback? onAssetChanged;

  const _CharacterOutfitDetailSection({
    required this.character,
    required this.outfitPreviewPathsById,
    required this.selectedOutfitIndex,
    required this.onSelectOutfit,
    this.onGeneratePreview,
    this.onEditOutfit,
    this.onDuplicateOutfit,
    this.onDeleteOutfit,
    this.onDeleteOutfitPreview,
    this.onAssetChanged,
  });

  @override
  State<_CharacterOutfitDetailSection> createState() =>
      _CharacterOutfitDetailSectionState();
}

class _CharacterOutfitDetailSectionState
    extends State<_CharacterOutfitDetailSection> {
  int _previewIndex = 0;
  bool _outfitPreviewHovered = false;

  @override
  void didUpdateWidget(covariant _CharacterOutfitDetailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedOutfitSlotKey(oldWidget) != _selectedOutfitSlotKey(widget)) {
      _previewIndex = 0;
      _outfitPreviewHovered = false;
    }
    _clampPreviewIndex(_selectedPreviewPaths(widget).length);
  }

  String _selectedOutfitSlotKey(_CharacterOutfitDetailSection section) {
    if (section.character.outfits.isEmpty) {
      return '${section.character.id}:none';
    }
    final selectedRecord = _outfitAtSelection(
      section.character,
      section.selectedOutfitIndex,
    );
    return _outfitSlotKey(
      section.character.id,
      selectedRecord.index,
      selectedRecord.outfit,
    );
  }

  List<String> _selectedPreviewPaths(_CharacterOutfitDetailSection section) {
    if (section.character.outfits.isEmpty) return const [];
    final selectedRecord = _outfitAtSelection(
      section.character,
      section.selectedOutfitIndex,
    );
    return _outfitPreviewPathsFor(
      section.character,
      selectedRecord.index,
      selectedRecord.outfit,
      section.outfitPreviewPathsById,
    );
  }

  void _clampPreviewIndex(int count) {
    if (count <= 0) {
      _previewIndex = 0;
    } else if (_previewIndex >= count) {
      _previewIndex = count - 1;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final count = _selectedPreviewPaths(widget).length;
    if (event is! PointerScrollEvent || count <= 1) return;
    final currentIndex = _previewIndex.clamp(0, count - 1).toInt();
    final nextIndex =
        _nextPreviewIndex(currentIndex, count, event.scrollDelta.dy);
    if (nextIndex == currentIndex) return;
    setState(() {
      _previewIndex = nextIndex;
    });
  }

  Future<void> _runOutfitAction(Future<void> Function() action) async {
    await action();
    widget.onAssetChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final character = widget.character;
    final outfitPreviewPathsById = widget.outfitPreviewPathsById;
    final selectedOutfitIndex = widget.selectedOutfitIndex;
    final onSelectOutfit = widget.onSelectOutfit;
    final onGeneratePreview = widget.onGeneratePreview;
    final onEditOutfit = widget.onEditOutfit;
    final onDuplicateOutfit = widget.onDuplicateOutfit;
    final onDeleteOutfit = widget.onDeleteOutfit;
    final onDeleteOutfitPreview = widget.onDeleteOutfitPreview;
    final selectedRecord = _outfitAtSelection(character, selectedOutfitIndex);
    final selectedIndex = selectedRecord.index;
    final selected = selectedRecord.outfit;
    final previewPaths = _outfitPreviewPathsFor(
      character,
      selectedIndex,
      selected,
      outfitPreviewPathsById,
    );
    final activeIndex = previewPaths.isEmpty
        ? 0
        : _previewIndex.clamp(0, previewPaths.length - 1).toInt();
    final previewPath = previewPaths.isEmpty ? null : previewPaths[activeIndex];
    String? firstOutfitPreviewPath(int index, WorkspaceOutfit outfit) {
      final paths = _outfitPreviewPathsFor(
          character, index, outfit, outfitPreviewPathsById);
      return paths.isEmpty ? null : paths.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in character.outfits.indexed)
                    GestureDetector(
                      key: ValueKey(
                        'asset-character-outfit-icon-${character.id}-${_outfitWidgetKey(character, entry.$1, entry.$2)}',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelectOutfit(entry.$1),
                      child: _OutfitIconTile(
                        outfit: entry.$2,
                        previewPath: firstOutfitPreviewPath(entry.$1, entry.$2),
                        selected: entry.$1 == selectedIndex,
                      ),
                    ),
                ],
              ),
            ),
            if (onEditOutfit != null ||
                onDuplicateOutfit != null ||
                onDeleteOutfit != null)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (onEditOutfit != null)
                    StudioIconButton(
                      key: ValueKey(
                        'asset-character-outfit-edit-${character.id}-${selected.id}',
                      ),
                      tooltip: '编辑服装',
                      icon: Icons.edit_outlined,
                      onPressed: () => unawaited(
                        _runOutfitAction(() => onEditOutfit(selected)),
                      ),
                    ),
                  if (onDuplicateOutfit != null)
                    StudioIconButton(
                      key: ValueKey(
                        'asset-character-outfit-duplicate-${character.id}-${selected.id}',
                      ),
                      tooltip: '复制服装',
                      icon: Icons.copy_outlined,
                      onPressed: () => unawaited(
                        _runOutfitAction(() => onDuplicateOutfit(selected)),
                      ),
                    ),
                  if (onDeleteOutfit != null)
                    StudioIconButton(
                      key: ValueKey(
                        'asset-character-outfit-delete-${character.id}-${selected.id}',
                      ),
                      tooltip: '删除服装',
                      icon: Icons.delete_outline,
                      onPressed: () => unawaited(
                        _runOutfitAction(() => onDeleteOutfit(selected)),
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          selected.name,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (previewPath != null)
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _handlePointerSignal,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _outfitPreviewHovered = true),
              onExit: (_) => setState(() => _outfitPreviewHovered = false),
              child: GestureDetector(
                key: ValueKey(
                  'asset-character-outfit-preview-${character.id}-${selected.id}',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => _PreviewCarouselDialog.fromPaths(
                    title: '${character.name} / ${selected.name}',
                    keySuffix: 'outfit-${character.id}-${selected.id}',
                    previewPaths: previewPaths,
                  ),
                ),
                child: _AssetPreviewFrame(
                  hovered: _outfitPreviewHovered,
                  child: _ConstrainedAssetImage(
                    path: previewPath,
                    imageKey: ValueKey(
                      'asset-character-outfit-preview-image-${character.id}-${selected.id}',
                    ),
                    fit: BoxFit.contain,
                    maxDecodeExtent: _assetDetailPreviewMaxDecodeExtent,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: StudioTokens.textMuted,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          )
        else
          _AssetPreviewFrame(
            key: ValueKey(
              'asset-character-outfit-preview-empty-${character.id}-${selected.id}',
            ),
            child: const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: StudioTokens.textMuted,
                size: 42,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (previewPaths.isNotEmpty)
          _PreviewDots(
            count: previewPaths.length,
            activeIndex: activeIndex,
            keyBuilder: (index) => ValueKey(
              'asset-character-preview-dot-${character.id}-$index',
            ),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (previewPaths.isNotEmpty && onDeleteOutfitPreview != null)
                StudioButton(
                  key: ValueKey(
                    'asset-character-outfit-delete-preview-${character.id}-${selected.id}',
                  ),
                  label: '删除预览',
                  icon: Icons.delete_outline,
                  onPressed: () => unawaited(
                    _runOutfitAction(
                      () => onDeleteOutfitPreview(selectedIndex, selected),
                    ),
                  ),
                  tone: StudioButtonTone.danger,
                ),
              StudioButton(
                key: ValueKey(
                  'asset-detail-generate-preview-character-${character.id}',
                ),
                label: previewPaths.isEmpty ? '立即生成' : '新增预览',
                icon: Icons.add_photo_alternate_outlined,
                onPressed: onGeneratePreview,
                tone: previewPaths.isEmpty
                    ? StudioButtonTone.primary
                    : StudioButtonTone.ghost,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String message;

  const _EmptyRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _PromptAssetSectionDraft {
  final TextEditingController labelController;
  String prompt;

  _PromptAssetSectionDraft({
    required String label,
    this.prompt = '',
  }) : labelController = TextEditingController(text: label);
}

class _SectionedPromptEditorResult {
  final String name;
  final String block;
  final String prompt;
  final Map<String, String> sections;

  const _SectionedPromptEditorResult({
    required this.name,
    required this.block,
    required this.prompt,
    required this.sections,
  });
}

class _AssetSectionEditor extends StatelessWidget {
  final TextEditingController labelController;
  final String prompt;
  final String promptKey;
  final ValueChanged<String> onPromptChanged;
  final VoidCallback onDelete;
  final Widget Function({
    required String key,
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) promptEditor;

  const _AssetSectionEditor({
    super.key,
    required this.labelController,
    required this.prompt,
    required this.promptKey,
    required this.onPromptChanged,
    required this.onDelete,
    required this.promptEditor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('$promptKey-label'),
                    controller: labelController,
                    decoration: const InputDecoration(labelText: '分区名称'),
                  ),
                ),
                const SizedBox(width: 8),
                StudioIconButton(
                  key: ValueKey('$promptKey-delete'),
                  tooltip: '删除分区',
                  icon: Icons.delete_outline,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            promptEditor(
              key: promptKey,
              label: '提示词',
              value: prompt,
              onChanged: onPromptChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetDisplaySlice {
  final List<_AssetDisplayItem> items;
  final int totalCount;

  const _AssetDisplaySlice({
    required this.items,
    required this.totalCount,
  });
}

class _AssetDisplayItem {
  final String key;
  final String? assetIdOverride;
  final _AssetKind kind;
  final IconData icon;
  final String typeLabel;
  final String title;
  final String summary;
  final String meta;
  final String? resolvedPreviewPath;
  final List<String> resolvedPreviewPaths;
  final Map<String, List<String>> outfitPreviewPathsById;
  final double previewAspectRatio;
  final List<_AssetDetailLine>? _details;
  final List<_AssetDetailLine> Function()? _detailsBuilder;
  List<_AssetDetailLine>? _resolvedDetails;
  final List<String> referencePaths;
  final String sourceType;
  final VoidCallback? onSend;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onDuplicateCharacter;
  final Future<void> Function()? onAddOutfit;
  final Future<void> Function(WorkspaceOutfit)? onEditOutfit;
  final Future<void> Function(WorkspaceOutfit)? onDuplicateOutfit;
  final Future<void> Function(WorkspaceOutfit)? onDeleteOutfit;
  final Future<void> Function(int, WorkspaceOutfit)? onDeleteOutfitPreview;
  final Future<void> Function()? onDeletePreview;
  final Future<List<WorkspaceVibeReference>> Function()? onLoadVibes;
  final Future<List<WorkspaceVibeReference>> Function()? onImportVibes;
  final Future<void> Function(ArtistChain)? onSaveArtistChain;
  final Future<void> Function()? onDuplicateArtistChain;
  final Future<void> Function(String)? onRenameArtistChain;
  final Future<void> Function(String)? onPromptChanged;
  final Future<void> Function(_CharacterPromptField, String)?
      onCharacterPromptFieldChanged;
  final Future<void> Function(int, String)? onOutfitPromptChanged;
  final Future<void> Function(int, _OutfitPromptField, String)?
      onOutfitPromptFieldChanged;
  final CharacterEntry? character;
  final CharacterEntry? outfitCharacter;
  final WorkspaceOutfit? outfit;
  final int? outfitIndex;
  final ArtistChain? artistChain;
  final Recipe? recipe;
  final TagEntry? tag;
  final InspirationEntry? inspiration;
  final StudioScriptAssetFocus? scriptFocus;

  _AssetDisplayItem({
    required this.key,
    String? assetId,
    required this.kind,
    required this.icon,
    required this.typeLabel,
    required this.title,
    required this.summary,
    required this.meta,
    this.resolvedPreviewPath,
    this.resolvedPreviewPaths = const [],
    this.outfitPreviewPathsById = const {},
    this.previewAspectRatio = 3 / 4,
    List<_AssetDetailLine>? details,
    List<_AssetDetailLine> Function()? detailsBuilder,
    required this.referencePaths,
    this.sourceType = '',
    required this.onSend,
    this.onEdit,
    this.onDelete,
    this.onDuplicateCharacter,
    this.onAddOutfit,
    this.onEditOutfit,
    this.onDuplicateOutfit,
    this.onDeleteOutfit,
    this.onDeleteOutfitPreview,
    this.onDeletePreview,
    this.onLoadVibes,
    this.onImportVibes,
    this.onSaveArtistChain,
    this.onDuplicateArtistChain,
    this.onRenameArtistChain,
    this.onPromptChanged,
    this.onCharacterPromptFieldChanged,
    this.onOutfitPromptChanged,
    this.onOutfitPromptFieldChanged,
    this.character,
    this.outfitCharacter,
    this.outfit,
    this.outfitIndex,
    this.artistChain,
    this.recipe,
    this.tag,
    this.inspiration,
    this.scriptFocus,
  })  : assetIdOverride = assetId,
        _details = details,
        _detailsBuilder = detailsBuilder;

  _AssetDisplayItem withResolvedPreviewPaths(List<String> value) {
    return _copyWith(
      resolvedPreviewPath: value.isEmpty ? null : value.first,
      resolvedPreviewPaths: value,
    );
  }

  _AssetDisplayItem withOutfitPreviewPathsById(
    Map<String, List<String>> value,
  ) {
    return _copyWith(outfitPreviewPathsById: value);
  }

  _AssetDisplayItem withPreviewAspectRatio(double value) {
    return _copyWith(previewAspectRatio: value);
  }

  _AssetDisplayItem _copyWith({
    String? resolvedPreviewPath,
    List<String>? resolvedPreviewPaths,
    Map<String, List<String>>? outfitPreviewPathsById,
    double? previewAspectRatio,
  }) {
    return _AssetDisplayItem(
      key: key,
      assetId: assetIdOverride,
      kind: kind,
      icon: icon,
      typeLabel: typeLabel,
      title: title,
      summary: summary,
      meta: meta,
      resolvedPreviewPath: resolvedPreviewPath ?? this.resolvedPreviewPath,
      resolvedPreviewPaths: resolvedPreviewPaths ?? this.resolvedPreviewPaths,
      outfitPreviewPathsById:
          outfitPreviewPathsById ?? this.outfitPreviewPathsById,
      previewAspectRatio: previewAspectRatio ?? this.previewAspectRatio,
      details: _details,
      detailsBuilder: _detailsBuilder,
      referencePaths: referencePaths,
      sourceType: sourceType,
      onSend: onSend,
      onEdit: onEdit,
      onDelete: onDelete,
      onDuplicateCharacter: onDuplicateCharacter,
      onAddOutfit: onAddOutfit,
      onEditOutfit: onEditOutfit,
      onDuplicateOutfit: onDuplicateOutfit,
      onDeleteOutfit: onDeleteOutfit,
      onDeleteOutfitPreview: onDeleteOutfitPreview,
      onDeletePreview: onDeletePreview,
      onLoadVibes: onLoadVibes,
      onImportVibes: onImportVibes,
      onSaveArtistChain: onSaveArtistChain,
      onDuplicateArtistChain: onDuplicateArtistChain,
      onRenameArtistChain: onRenameArtistChain,
      onPromptChanged: onPromptChanged,
      onCharacterPromptFieldChanged: onCharacterPromptFieldChanged,
      onOutfitPromptChanged: onOutfitPromptChanged,
      onOutfitPromptFieldChanged: onOutfitPromptFieldChanged,
      character: character,
      outfitCharacter: outfitCharacter,
      outfit: outfit,
      outfitIndex: outfitIndex,
      artistChain: artistChain,
      recipe: recipe,
      tag: tag,
      inspiration: inspiration,
      scriptFocus: scriptFocus,
    );
  }

  bool get hasReferenceWarning {
    if (referencePaths.isEmpty) return false;
    if (kind == _AssetKind.artistChain && previewPath != null) return false;
    return true;
  }

  bool get hasCardPreviewArea => previewPath != null;

  bool get hasCompactNoPreview => previewPath == null && isLegacyCodex;

  List<_AssetDetailLine> get details {
    final details = _details ?? _resolvedDetails;
    if (details != null) return details;
    final resolved = _detailsBuilder?.call() ?? const [];
    _resolvedDetails = resolved;
    return resolved;
  }

  bool get canGeneratePreview {
    return kind == _AssetKind.character ||
        kind == _AssetKind.artistChain ||
        (kind == _AssetKind.outfit &&
            outfitCharacter != null &&
            outfit != null);
  }

  String get previewKind {
    return switch (kind) {
      _AssetKind.artistChain => 'artistChain',
      _AssetKind.assemblyPreset => 'assemblyPreset',
      _ => kind.name,
    };
  }

  String? get previewPath {
    if (resolvedPreviewPath != null) return resolvedPreviewPath;
    return resolvedPreviewPaths.isEmpty ? null : resolvedPreviewPaths.first;
  }

  List<String> get previewPaths {
    if (resolvedPreviewPaths.isNotEmpty) return resolvedPreviewPaths;
    final path = previewPath;
    return path == null ? const [] : [path];
  }

  bool get isLegacyCodex {
    return kind == _AssetKind.inspiration &&
        StudioAssetCatalogService.isCodexSourceType(sourceType);
  }

  List<String> get promptPreviewTags {
    if (summary.trim().isEmpty) return const [];
    return summary
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  String get assetId {
    if (outfit != null) return outfit!.id;
    if (assetIdOverride != null) return assetIdOverride!;
    if (character != null) return character!.id;
    if (artistChain != null) return artistChain!.id;
    if (recipe != null) return recipe!.id;
    if (tag != null) return tag!.id;
    final prefix = switch (kind) {
      _AssetKind.character => 'character-',
      _AssetKind.outfit => 'outfit-',
      _AssetKind.artistChain => 'artist-',
      _AssetKind.recipe => 'recipe-',
      _AssetKind.tag => 'tag-',
      _AssetKind.inspiration => 'inspiration-',
      _AssetKind.lora => 'lora-',
      _AssetKind.workflow => 'workflow-',
      _AssetKind.batchPlan => 'batch-plan-',
      _AssetKind.assemblyPreset => 'assembly-preset-',
    };
    return key.startsWith(prefix) ? key.substring(prefix.length) : key;
  }

  String get copyText {
    final value = summary.trim();
    if (value.isNotEmpty) return value;
    return details
        .map((line) => line.value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => title);
  }

  String get favoriteKey {
    if (outfitCharacter != null && outfit != null) {
      return StudioAssetFavoriteKeys.outfit(
        outfitCharacter!.id,
        outfit!.id,
      );
    }
    if (character != null) {
      return StudioAssetFavoriteKeys.character(character!.id);
    }
    if (artistChain != null) {
      return StudioAssetFavoriteKeys.artistChain(artistChain!.id);
    }
    if (recipe != null) {
      return StudioAssetFavoriteKeys.recipe(recipe!.block, recipe!.id);
    }
    if (tag != null) {
      return StudioAssetFavoriteKeys.tag(tag!.block, tag!.id);
    }
    final parts = key.split('-');
    return switch (kind) {
      _AssetKind.character => StudioAssetFavoriteKeys.character(
          key.substring('character-'.length),
        ),
      _AssetKind.outfit => StudioAssetFavoriteKeys.outfit(
          parts.length > 1 ? parts[1] : key,
          parts.length > 3 ? parts.sublist(3).join('-') : key,
        ),
      _AssetKind.artistChain => StudioAssetFavoriteKeys.artistChain(
          key.substring('artist-'.length),
        ),
      _AssetKind.recipe => key.startsWith('recipe-')
          ? 'recipe:${key.substring('recipe-'.length)}'
          : key,
      _AssetKind.tag =>
        key.startsWith('tag-') ? 'tag:${key.substring('tag-'.length)}' : key,
      _AssetKind.inspiration => StudioAssetFavoriteKeys.inspiration(
          key.substring('inspiration-'.length),
        ),
      _AssetKind.lora => StudioAssetFavoriteKeys.lora(
          key.substring('lora-'.length),
        ),
      _AssetKind.workflow => StudioAssetFavoriteKeys.workflow(
          key.substring('workflow-'.length),
        ),
      _AssetKind.batchPlan =>
        'batch-plan:${key.substring('batch-plan-'.length)}',
      _AssetKind.assemblyPreset => StudioAssetFavoriteKeys.assemblyPreset(
          key.substring('assembly-preset-'.length),
        ),
    };
  }

  bool matches(String normalizedQuery) {
    final haystack = [
      typeLabel,
      title,
      summary,
      meta,
      if (character != null)
        for (final outfit in character!.outfits) ...[
          outfit.id,
          outfit.name,
          outfit.tags.frontFull,
          outfit.tags.frontUpper,
          outfit.tags.frontLower,
        ],
      if (outfitCharacter != null) ...[
        outfitCharacter!.id,
        outfitCharacter!.name,
      ],
      if (outfit != null) ...[
        outfit!.id,
        outfit!.name,
        outfit!.tags.frontFull,
        outfit!.tags.frontUpper,
        outfit!.tags.frontLower,
      ],
      if (recipe != null) ...[
        recipe!.id,
        recipe!.block,
        recipe!.category,
        recipe!.group,
        recipe!.tags,
        ...recipe!.variants.keys,
        ...recipe!.variants.values,
      ],
      if (tag != null) ...[
        tag!.id,
        tag!.block,
        tag!.category,
        tag!.tag,
        tag!.zh,
        ...tag!.sections.keys,
        ...tag!.sections.values,
        ...tag!.aliases,
      ],
      for (final detail in details) detail.value,
      ...referencePaths,
    ].join('\n').toLowerCase();
    return haystack.contains(normalizedQuery);
  }
}

class _AssetDetailLine {
  final String label;
  final String value;

  const _AssetDetailLine(this.label, this.value);
}

const _assetCardPreviewMaxDecodeExtent = 768;
const _assetDetailPreviewMaxDecodeExtent = 1024;
const _assetDialogPreviewMaxDecodeExtent = 1024;
const _assetOutfitIconMaxDecodeExtent = 128;
