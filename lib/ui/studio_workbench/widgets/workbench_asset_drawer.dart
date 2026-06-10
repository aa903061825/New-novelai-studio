import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_list_utils.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_hover_preview_thumbnail.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

const double _drawerPreviewWidth = 72;
const double _drawerPreviewHeight = 96;

class WorkbenchAssetDrawer extends StatefulWidget {
  final StudioAssetCatalogService catalogService;
  final StudioWorkbenchAssetService workbenchAssetService;

  const WorkbenchAssetDrawer({
    super.key,
    required this.catalogService,
    required this.workbenchAssetService,
  });

  @override
  State<WorkbenchAssetDrawer> createState() => _WorkbenchAssetDrawerState();
}

class _WorkbenchAssetDrawerState extends State<WorkbenchAssetDrawer> {
  late Future<StudioAssetCatalogSummary> _summaryFuture;
  final TextEditingController _searchController = TextEditingController();
  _AssetDrawerCategory? _selectedCategory;
  Future<List<_DrawerAssetItem>>? _detailFuture;
  String _searchQuery = '';
  Set<String> _favoriteKeys = const {};

  @override
  void initState() {
    super.initState();
    _summaryFuture = widget.catalogService.loadSummary();
    _searchController.addListener(_updateSearchQuery);
    _loadFavoriteKeys();
  }

  @override
  void didUpdateWidget(covariant WorkbenchAssetDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService) {
      _summaryFuture = widget.catalogService.loadSummary();
      _selectedCategory = null;
      _detailFuture = null;
      _searchQuery = '';
      _favoriteKeys = const {};
      _searchController.clear();
      _loadFavoriteKeys();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_updateSearchQuery);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<StudioAssetCatalogSummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _DrawerState(
              icon: Icons.error_outline,
              title: '素材抽屉不可用',
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const _DrawerState(
              icon: Icons.hourglass_empty,
              title: '素材抽屉',
              message: '正在整理可用素材',
            );
          }

          final summary = snapshot.data!;
          if (summary.isEmpty) {
            return const _DrawerState(
              icon: Icons.inventory_2_outlined,
              title: '素材抽屉',
              message: '还没有可加入工作台的素材',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrawerHeader(
                title: _selectedCategory?.title ?? '素材抽屉',
                count: _selectedCategory?.countFrom(summary) ??
                    summary.totalAssetCount,
                onBack: _selectedCategory == null ? null : _showCategories,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _selectedCategory == null
                    ? _CategoryCardList(
                        summary: summary,
                        onSelect: _selectCategory,
                      )
                    : _CategoryDetail(
                        future: _detailFuture!,
                        searchController: _searchController,
                        searchQuery: _searchQuery,
                        favoriteKeys: _favoriteKeys,
                        onFavoriteChanged: _setFavorite,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reload() {
    setState(() {
      _summaryFuture = widget.catalogService.loadSummary();
      _selectedCategory = null;
      _detailFuture = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadFavoriteKeys();
  }

  Future<void> _loadFavoriteKeys() async {
    try {
      final favoriteKeys = await widget.catalogService.loadAssetFavoriteKeys();
      if (!mounted) return;
      setState(() {
        _favoriteKeys = favoriteKeys;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteKeys = const {};
      });
    }
  }

  Future<void> _setFavorite(_DrawerAssetItem item, bool isFavorite) async {
    final previous = _favoriteKeys;
    setState(() {
      final next = {..._favoriteKeys};
      if (isFavorite) {
        next.add(item.favoriteKey);
      } else {
        next.remove(item.favoriteKey);
      }
      _favoriteKeys = next;
    });
    try {
      await widget.catalogService.setAssetFavorite(
        item.favoriteKey,
        isFavorite,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteKeys = previous;
      });
    }
  }

  void _selectCategory(_AssetDrawerCategory category) {
    setState(() {
      _selectedCategory = category;
      _detailFuture = _loadCategoryItems(category);
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _showCategories() {
    setState(() {
      _selectedCategory = null;
      _detailFuture = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _updateSearchQuery() {
    final nextQuery = _searchController.text.trim().toLowerCase();
    if (nextQuery == _searchQuery) return;
    setState(() {
      _searchQuery = nextQuery;
    });
  }

  Future<List<_DrawerAssetItem>> _loadCategoryItems(
    _AssetDrawerCategory category,
  ) async {
    switch (category) {
      case _AssetDrawerCategory.character:
        final characters =
            await widget.catalogService.loadWorkbenchCharacters();
        return [
          for (final character in characters)
            _DrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.character(character.id),
              favoriteButtonKey: ValueKey(
                'workbench-drawer-favorite-character-${character.id}',
              ),
              actionKey: ValueKey(
                'workbench-drawer-add-character-${character.id}',
              ),
              itemKey:
                  ValueKey('workbench-drawer-card-character-${character.id}'),
              previewKey: ValueKey(
                'workbench-drawer-preview-character-${character.id}',
              ),
              icon: Icons.person_outline,
              title: character.name,
              subtitle: character.traits.frontFull,
              previewPaths: _resolveImagePaths(character.imageRefs),
              searchableText: [
                character.name,
                character.traits.frontFull,
                character.traits.frontUpper ?? '',
                character.traits.frontLower ?? '',
                for (final outfit in character.outfits) ...[
                  outfit.name,
                  outfit.tags.frontFull,
                  outfit.partTags.upperBodyTags.join(', '),
                  outfit.partTags.upperClothingTags.join(', '),
                  outfit.partTags.lowerBodyTags.join(', '),
                  outfit.partTags.lowerClothingTags.join(', '),
                  outfit.tags.frontUpper ?? '',
                  outfit.tags.frontLower ?? '',
                ],
              ].join(' '),
              outfits: _drawerOutfitsForCharacter(character),
              onAdd: () =>
                  widget.workbenchAssetService.appendCharacter(character),
              onInsert: (index) => widget.workbenchAssetService
                  .insertCharacter(character, index),
              characterName: character.name,
              characterPrompt: character.traits.frontFull,
            ),
        ];
      case _AssetDrawerCategory.outfit:
        final outfits = await widget.catalogService.loadWorkbenchOutfits();
        return [
          for (final outfitAsset in outfits)
            _DrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.outfit(
                outfitAsset.character.id,
                outfitAsset.outfit.id,
              ),
              favoriteButtonKey: ValueKey(
                'workbench-drawer-favorite-outfit-${outfitAsset.outfit.id}',
              ),
              actionKey: ValueKey(
                'workbench-drawer-add-outfit-${outfitAsset.outfit.id}',
              ),
              itemKey: ValueKey(
                'workbench-drawer-card-outfit-${outfitAsset.outfit.id}',
              ),
              previewKey: ValueKey(
                'workbench-drawer-preview-outfit-${outfitAsset.outfit.id}',
              ),
              icon: Icons.checkroom_outlined,
              title: outfitAsset.outfit.name,
              subtitle: outfitAsset.character.name,
              previewPaths: _resolveImagePaths(outfitAsset.outfit.imageRefs),
              searchableText:
                  '${outfitAsset.outfit.name} ${outfitAsset.character.name}',
              onAdd: () => widget.workbenchAssetService.appendOutfit(
                outfitAsset.character,
                outfitAsset.outfit,
              ),
              onInsert: (index) => widget.workbenchAssetService.insertOutfit(
                outfitAsset.character,
                outfitAsset.outfit,
                index,
              ),
              characterName:
                  '${outfitAsset.character.name} / ${outfitAsset.outfit.name}',
              characterPrompt: _combinedPrompt([
                outfitAsset.character.traits.frontFull,
                outfitAsset.outfit.tags.frontFull,
              ]),
            ),
        ];
      case _AssetDrawerCategory.artist:
        final artistChains =
            await widget.catalogService.loadWorkbenchArtistChains();
        return [
          for (final artistChain in artistChains)
            _DrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.artistChain(artistChain.id),
              favoriteButtonKey: ValueKey(
                'workbench-drawer-favorite-artist-${artistChain.id}',
              ),
              actionKey: ValueKey(
                'workbench-drawer-add-artist-${artistChain.id}',
              ),
              itemKey: ValueKey(
                'workbench-drawer-card-artist-${artistChain.id}',
              ),
              previewKey: ValueKey(
                'workbench-drawer-preview-artist-${artistChain.id}',
              ),
              icon: Icons.brush_outlined,
              title: artistChain.name,
              subtitle: _artistChainPrompt(artistChain),
              previewPaths: _resolveImagePaths(artistChain.imageRefs),
              searchableText:
                  '${artistChain.name} ${_artistChainPrompt(artistChain)}',
              onAdd: () =>
                  widget.workbenchAssetService.appendArtistChain(artistChain),
              onInsert: (index) => widget.workbenchAssetService
                  .insertArtistChain(artistChain, index),
            ),
        ];
      case _AssetDrawerCategory.recipe:
        final recipes = await widget.catalogService.loadWorkbenchRecipes();
        return [
          for (final recipe in recipes)
            _DrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.recipe(
                recipe.block,
                recipe.id,
              ),
              favoriteButtonKey: ValueKey(
                'workbench-drawer-favorite-recipe-${recipe.id}',
              ),
              actionKey: ValueKey('workbench-drawer-add-recipe-${recipe.id}'),
              itemKey: ValueKey('workbench-drawer-card-recipe-${recipe.id}'),
              previewKey:
                  ValueKey('workbench-drawer-preview-recipe-${recipe.id}'),
              icon: Icons.auto_awesome_mosaic_outlined,
              title: recipe.name,
              subtitle: recipe.block,
              previewPaths: _resolveImagePaths(recipe.imageRefs),
              searchableText:
                  '${recipe.name} ${recipe.block} ${recipe.tags} ${recipe.category}',
              onAdd: () => widget.workbenchAssetService.appendRecipe(recipe),
              onInsert: (index) =>
                  widget.workbenchAssetService.insertRecipe(recipe, index),
            ),
        ];
      case _AssetDrawerCategory.tag:
        final tags = await widget.catalogService.loadWorkbenchTags();
        return [
          for (final tag in tags)
            _DrawerAssetItem(
              favoriteKey: StudioAssetFavoriteKeys.tag(tag.block, tag.id),
              favoriteButtonKey:
                  ValueKey('workbench-drawer-favorite-tag-${tag.id}'),
              actionKey: ValueKey('workbench-drawer-add-tag-${tag.id}'),
              itemKey: ValueKey('workbench-drawer-card-tag-${tag.id}'),
              previewKey: ValueKey('workbench-drawer-preview-tag-${tag.id}'),
              icon: Icons.local_offer_outlined,
              title: tag.zh.isEmpty ? tag.tag : tag.zh,
              subtitle: tag.tag,
              previewPaths: _resolveImagePaths(tag.imageRefs),
              searchableText: '${tag.zh} ${tag.tag} ${tag.block}',
              onAdd: () => widget.workbenchAssetService.appendTag(tag),
              onInsert: (index) =>
                  widget.workbenchAssetService.insertTag(tag, index),
            ),
        ];
    }
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

  List<_DrawerOutfitItem> _drawerOutfitsForCharacter(CharacterEntry character) {
    return [
      for (final outfit in _uniqueOutfitsById(character.outfits))
        _DrawerOutfitItem(
          actionKey: ValueKey(
            'workbench-drawer-add-character-${character.id}-outfit-${outfit.id}',
          ),
          itemKey: ValueKey(
            'workbench-drawer-card-character-${character.id}-outfit-${outfit.id}',
          ),
          previewKey: ValueKey(
            'workbench-drawer-preview-character-${character.id}-outfit-${outfit.id}',
          ),
          characterName: '${character.name} / ${outfit.name}',
          characterPrompt: _combinedPrompt([
            character.traits.frontFull,
            outfit.tags.frontFull,
          ]),
          title: outfit.name,
          fullPrompt: outfit.tags.frontFull,
          upperBodyPrompt: promptTagsToPrompt(outfit.partTags.upperBodyTags),
          upperClothingPrompt: promptTagsToPrompt(
            outfit.partTags.upperClothingTags,
          ),
          lowerBodyPrompt: promptTagsToPrompt(outfit.partTags.lowerBodyTags),
          lowerClothingPrompt: promptTagsToPrompt(
            outfit.partTags.lowerClothingTags,
          ),
          parts: _outfitParts(
            character: character,
            outfitId: outfit.id,
            outfitName: outfit.name,
            upperBodyPrompt: promptTagsToPrompt(outfit.partTags.upperBodyTags),
            upperClothingPrompt: promptTagsToPrompt(
              outfit.partTags.upperClothingTags,
            ),
            lowerBodyPrompt: promptTagsToPrompt(outfit.partTags.lowerBodyTags),
            lowerClothingPrompt: promptTagsToPrompt(
              outfit.partTags.lowerClothingTags,
            ),
            includeEmpty: true,
          ),
          previewPaths: _resolveImagePaths(outfit.imageRefs),
          onAdd: () => widget.workbenchAssetService.appendOutfit(
            character,
            outfit,
          ),
          onInsert: (index) => widget.workbenchAssetService.insertOutfit(
            character,
            outfit,
            index,
          ),
        ),
    ];
  }

  Iterable<WorkspaceOutfit> _uniqueOutfitsById(
    Iterable<WorkspaceOutfit> outfits,
  ) sync* {
    final seen = <String>{};
    for (final outfit in outfits) {
      if (seen.add(outfit.id)) {
        yield outfit;
      }
    }
  }

  List<_DrawerOutfitPartItem> _outfitParts({
    required CharacterEntry character,
    required String outfitId,
    required String outfitName,
    String upperBodyPrompt = '',
    String upperClothingPrompt = '',
    String lowerBodyPrompt = '',
    String lowerClothingPrompt = '',
    bool includeEmpty = false,
  }) {
    _DrawerOutfitPartItem part(
      String keySuffix,
      String label,
      String value,
    ) {
      return _DrawerOutfitPartItem(
        keySuffix: keySuffix,
        label: label,
        value: value,
        onAdd: () => widget.workbenchAssetService.appendOutfitPart(
          character: character,
          outfitId: outfitId,
          outfitName: outfitName,
          partLabel: label,
          fragment: value,
        ),
        onInsert: (index) => widget.workbenchAssetService.insertOutfitPart(
          character: character,
          outfitId: outfitId,
          outfitName: outfitName,
          partLabel: label,
          fragment: value,
          targetIndex: index,
        ),
      );
    }

    final parts = [
      part('upper-body', '上身', upperBodyPrompt),
      part('upper-clothing', '上装', upperClothingPrompt),
      part('lower-body', '下身', lowerBodyPrompt),
      part('lower-clothing', '下装', lowerClothingPrompt),
    ];
    if (includeEmpty) {
      return List.unmodifiable(parts);
    }
    return parts
        .where((part) => part.value.trim().isNotEmpty)
        .toList(growable: false);
  }

  String _combinedPrompt(List<String> prompts) {
    return prompts
        .map((prompt) => prompt.trim())
        .where((prompt) => prompt.isNotEmpty)
        .join(', ');
  }

  List<String> _resolveImagePaths(List<String> refs) {
    final paths = <String>[];
    final seen = <String>{};
    for (final ref in refs) {
      final path = widget.catalogService.resolveImagePath([ref]);
      if (path == null || !seen.add(path)) continue;
      paths.add(path);
    }
    return List.unmodifiable(paths);
  }
}

enum _AssetDrawerCategory {
  character(
    keySuffix: 'character',
    title: '角色',
    icon: Icons.person_outline,
  ),
  outfit(
    keySuffix: 'outfit',
    title: 'Outfit',
    icon: Icons.checkroom_outlined,
  ),
  artist(
    keySuffix: 'artist',
    title: '画师串',
    icon: Icons.brush_outlined,
  ),
  recipe(
    keySuffix: 'recipe',
    title: '配方',
    icon: Icons.auto_awesome_mosaic_outlined,
  ),
  tag(
    keySuffix: 'tag',
    title: 'Tag',
    icon: Icons.local_offer_outlined,
  );

  final String keySuffix;
  final String title;
  final IconData icon;

  const _AssetDrawerCategory({
    required this.keySuffix,
    required this.title,
    required this.icon,
  });

  int countFrom(StudioAssetCatalogSummary summary) {
    switch (this) {
      case _AssetDrawerCategory.character:
        return summary.characterCount;
      case _AssetDrawerCategory.outfit:
        return summary.outfitCount;
      case _AssetDrawerCategory.artist:
        return summary.artistChainCount;
      case _AssetDrawerCategory.recipe:
        return summary.recipeCount;
      case _AssetDrawerCategory.tag:
        return summary.tagCount;
    }
  }
}

class _DrawerHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback? onBack;

  const _DrawerHeader({
    required this.title,
    required this.count,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack == null)
          const Icon(
            Icons.inventory_2_outlined,
            color: StudioTokens.primary,
          )
        else
          StudioIconButton(
            key: const ValueKey('workbench-drawer-back'),
            tooltip: '返回分类',
            icon: Icons.arrow_back,
            onPressed: onBack,
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: StudioTokens.primary,
              ),
        ),
      ],
    );
  }
}

class _CategoryCardList extends StatelessWidget {
  final StudioAssetCatalogSummary summary;
  final ValueChanged<_AssetDrawerCategory> onSelect;

  const _CategoryCardList({
    required this.summary,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final category in _AssetDrawerCategory.values)
        if (category != _AssetDrawerCategory.outfit &&
            category.countFrom(summary) > 0)
          category,
    ];
    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryCard(
          category: category,
          count: category.countFrom(summary),
          onTap: () => onSelect(category),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _AssetDrawerCategory category;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('workbench-drawer-category-${category.keySuffix}'),
      onTap: onTap,
      borderRadius: StudioTokens.radiusSlot,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: StudioTokens.cardBorder,
        ),
        child: Row(
          children: [
            Icon(category.icon, size: 20, color: StudioTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: StudioTokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDetail extends StatelessWidget {
  final Future<List<_DrawerAssetItem>> future;
  final TextEditingController searchController;
  final String searchQuery;
  final Set<String> favoriteKeys;
  final void Function(_DrawerAssetItem item, bool isFavorite) onFavoriteChanged;

  const _CategoryDetail({
    required this.future,
    required this.searchController,
    required this.searchQuery,
    required this.favoriteKeys,
    required this.onFavoriteChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DrawerAssetItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DrawerState(
            icon: Icons.error_outline,
            title: '分类素材不可用',
            message: snapshot.error.toString(),
          );
        }
        if (!snapshot.hasData) {
          return const _DrawerState(
            icon: Icons.hourglass_empty,
            title: '正在打开分类',
            message: '正在整理这个分类的素材',
          );
        }

        final items = snapshot.data!;
        final pinnedItems = <_DrawerAssetItem>[];
        final regularItems = <_DrawerAssetItem>[];
        for (final item in items) {
          if (searchQuery.isNotEmpty &&
              !item.searchableText.toLowerCase().contains(searchQuery)) {
            continue;
          }
          if (favoriteKeys.contains(item.favoriteKey)) {
            pinnedItems.add(item);
          } else {
            regularItems.add(item);
          }
        }
        final filteredItems = [...pinnedItems, ...regularItems];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('workbench-drawer-category-search'),
              controller: searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索当前分类',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredItems.isEmpty
                  ? const _DrawerState(
                      icon: Icons.search_off,
                      title: '没有匹配素材',
                      message: '换个关键词试试',
                    )
                  : ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return _DrawerAssetRow(
                          key: _drawerStateKey('asset-row', item.itemKey),
                          itemKey: item.itemKey,
                          actionKey: item.actionKey,
                          favoriteButtonKey: item.favoriteButtonKey,
                          previewKey: item.previewKey,
                          icon: item.icon,
                          title: item.title,
                          subtitle: item.subtitle,
                          previewPaths: item.previewPaths,
                          outfits: item.outfits,
                          isFavorite: favoriteKeys.contains(item.favoriteKey),
                          onFavoriteChanged: (isFavorite) =>
                              onFavoriteChanged(item, isFavorite),
                          onAdd: item.onAdd,
                          onInsert: item.onInsert,
                          characterName: item.characterName,
                          characterPrompt: item.characterPrompt,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

Key _drawerStateKey(String prefix, Key sourceKey) {
  final value = sourceKey is ValueKey ? sourceKey.value : sourceKey.toString();
  return ValueKey('workbench-drawer-$prefix-state-$value');
}

String? _firstPreviewPath(List<String> paths) =>
    paths.isEmpty ? null : paths.first;

class _DrawerAssetItem {
  final String favoriteKey;
  final Key favoriteButtonKey;
  final Key itemKey;
  final Key actionKey;
  final Key previewKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> previewPaths;
  final String searchableText;
  final List<_DrawerOutfitItem> outfits;
  final VoidCallback onAdd;
  final ValueChanged<int> onInsert;
  final String? characterName;
  final String? characterPrompt;

  const _DrawerAssetItem({
    required this.favoriteKey,
    required this.favoriteButtonKey,
    required this.itemKey,
    required this.actionKey,
    required this.previewKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.previewPaths,
    required this.searchableText,
    required this.onAdd,
    required this.onInsert,
    this.outfits = const [],
    this.characterName,
    this.characterPrompt,
  });
}

class _DrawerOutfitItem {
  final Key itemKey;
  final Key actionKey;
  final Key previewKey;
  final String characterName;
  final String characterPrompt;
  final String title;
  final String fullPrompt;
  final List<_DrawerOutfitPartItem> parts;
  final String upperBodyPrompt;
  final String upperClothingPrompt;
  final String lowerBodyPrompt;
  final String lowerClothingPrompt;
  final List<String> previewPaths;
  final VoidCallback onAdd;
  final ValueChanged<int> onInsert;

  const _DrawerOutfitItem({
    required this.itemKey,
    required this.actionKey,
    required this.previewKey,
    required this.characterName,
    required this.characterPrompt,
    required this.title,
    required this.fullPrompt,
    required this.parts,
    this.upperBodyPrompt = '',
    this.upperClothingPrompt = '',
    this.lowerBodyPrompt = '',
    this.lowerClothingPrompt = '',
    required this.previewPaths,
    required this.onAdd,
    required this.onInsert,
  });
}

class _DrawerOutfitPartItem {
  final String keySuffix;
  final String label;
  final String value;
  final VoidCallback onAdd;
  final ValueChanged<int> onInsert;

  const _DrawerOutfitPartItem({
    required this.keySuffix,
    required this.label,
    required this.value,
    required this.onAdd,
    required this.onInsert,
  });
}

class _DrawerAssetDropData
    implements StudioWorkbenchPromptDropData, StudioWorkbenchCharacterDropData {
  @override
  final String label;
  final ValueChanged<int> onInsert;
  @override
  final String characterName;
  @override
  final String characterPrompt;

  const _DrawerAssetDropData({
    required this.label,
    required this.onInsert,
    this.characterName = '',
    this.characterPrompt = '',
  });

  @override
  void insertAt(int targetIndex) {
    onInsert(targetIndex);
  }
}

class _DrawerAssetRow extends StatefulWidget {
  final Key itemKey;
  final Key actionKey;
  final Key favoriteButtonKey;
  final Key previewKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> previewPaths;
  final List<_DrawerOutfitItem> outfits;
  final bool isFavorite;
  final ValueChanged<bool> onFavoriteChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onInsert;
  final String? characterName;
  final String? characterPrompt;

  const _DrawerAssetRow({
    super.key,
    required this.itemKey,
    required this.actionKey,
    required this.favoriteButtonKey,
    required this.previewKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.previewPaths,
    required this.outfits,
    required this.isFavorite,
    required this.onFavoriteChanged,
    required this.onAdd,
    required this.onInsert,
    this.characterName,
    this.characterPrompt,
  });

  @override
  State<_DrawerAssetRow> createState() => _DrawerAssetRowState();
}

class _DrawerAssetRowState extends State<_DrawerAssetRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final previewPath = _firstPreviewPath(widget.previewPaths);
    final card = InkWell(
      key: widget.itemKey,
      onTap: widget.outfits.isEmpty
          ? null
          : () => setState(() {
                _expanded = !_expanded;
              }),
      borderRadius: StudioTokens.radiusSlot,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: StudioTokens.cardBorder,
        ),
        child: Row(
          children: [
            StudioHoverPreviewThumbnail(
              previewPaths: widget.previewPaths,
              overlayKey: ValueKey(
                '${(widget.previewKey as ValueKey).value}-overlay',
              ),
              builder: (context, previewPath) => _DrawerAssetPreview(
                key: widget.previewKey,
                icon: widget.icon,
                previewPath: previewPath,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (widget.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (widget.outfits.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${widget.outfits.length} 套服装',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: StudioTokens.textMuted,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.outfits.isNotEmpty) ...[
              const SizedBox(width: 4),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: StudioTokens.textSecondary,
              ),
            ],
            const SizedBox(width: 8),
            StudioIconButton(
              key: widget.favoriteButtonKey,
              tooltip: widget.isFavorite ? '取消收藏' : '收藏',
              icon: widget.isFavorite ? Icons.star : Icons.star_border,
              onPressed: () => widget.onFavoriteChanged(!widget.isFavorite),
            ),
            const SizedBox(width: 4),
            StudioIconButton(
              key: widget.actionKey,
              tooltip: '加入工作台',
              icon: Icons.add,
              onPressed: widget.onAdd,
            ),
          ],
        ),
      ),
    );

    final draggable = Draggable<Object>(
      data: _DrawerAssetDropData(
        label: widget.title,
        onInsert: widget.onInsert,
        characterName: widget.characterName ?? widget.title,
        characterPrompt: widget.characterPrompt ?? '',
      ),
      feedback: _DrawerDragFeedback(
        label: widget.title,
        icon: widget.icon,
        previewPath: previewPath,
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        draggable,
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.only(left: 18, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final outfit in widget.outfits)
                  _DrawerOutfitRow(
                    key: _drawerStateKey('outfit-row', outfit.itemKey),
                    outfit: outfit,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DrawerOutfitRow extends StatefulWidget {
  final _DrawerOutfitItem outfit;

  const _DrawerOutfitRow({super.key, required this.outfit});

  @override
  State<_DrawerOutfitRow> createState() => _DrawerOutfitRowState();
}

class _DrawerOutfitRowState extends State<_DrawerOutfitRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final previewPath = _firstPreviewPath(widget.outfit.previewPaths);
    final header = InkWell(
      key: widget.outfit.itemKey,
      onTap: () => setState(() {
        _expanded = !_expanded;
      }),
      borderRadius: StudioTokens.radiusSlot,
      child: Row(
        children: [
          StudioHoverPreviewThumbnail(
            previewPaths: widget.outfit.previewPaths,
            overlayKey: ValueKey(
              '${(widget.outfit.previewKey as ValueKey).value}-overlay',
            ),
            builder: (context, previewPath) => _DrawerAssetPreview(
              key: widget.outfit.previewKey,
              icon: Icons.checkroom_outlined,
              previewPath: previewPath,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.outfit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (widget.outfit.fullPrompt.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.outfit.fullPrompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: StudioTokens.textSecondary,
          ),
          const SizedBox(width: 8),
          StudioIconButton(
            key: widget.outfit.actionKey,
            tooltip: '加入工作台',
            icon: Icons.add,
            onPressed: widget.outfit.onAdd,
          ),
        ],
      ),
    );

    final draggableHeader = Draggable<Object>(
      data: _DrawerAssetDropData(
        label: widget.outfit.title,
        onInsert: widget.outfit.onInsert,
        characterName: widget.outfit.characterName,
        characterPrompt: widget.outfit.characterPrompt,
      ),
      feedback: _DrawerDragFeedback(
        label: widget.outfit.title,
        icon: Icons.checkroom_outlined,
        previewPath: previewPath,
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: header),
      child: header,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          draggableHeader,
          if (_expanded) ...[
            const SizedBox(height: 10),
            for (final part in widget.outfit.parts) ...[
              _DrawerPromptPartCard(
                outfitKey: widget.outfit.itemKey,
                part: part,
              ),
              if (part != widget.outfit.parts.last) const SizedBox(height: 8),
            ],
            if (widget.outfit.parts.isNotEmpty) const SizedBox(height: 8),
            if (widget.outfit.parts.isEmpty) ...[
              if (widget.outfit.upperBodyPrompt.trim().isNotEmpty) ...[
                _DrawerPromptSplitLine(
                  label: '上身',
                  value: widget.outfit.upperBodyPrompt,
                ),
                const SizedBox(height: 8),
              ],
              _DrawerPromptSplitLine(
                label: '上装',
                value: widget.outfit.upperClothingPrompt,
              ),
              const SizedBox(height: 8),
              if (widget.outfit.lowerBodyPrompt.trim().isNotEmpty) ...[
                _DrawerPromptSplitLine(
                  label: '下身',
                  value: widget.outfit.lowerBodyPrompt,
                ),
                const SizedBox(height: 8),
              ],
              _DrawerPromptSplitLine(
                label: '下装',
                value: widget.outfit.lowerClothingPrompt,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DrawerPromptPartCard extends StatelessWidget {
  final Key outfitKey;
  final _DrawerOutfitPartItem part;

  const _DrawerPromptPartCard({
    required this.outfitKey,
    required this.part,
  });

  @override
  Widget build(BuildContext context) {
    final value = part.value.trim();
    final partKey = _partKey('part');
    final card = Container(
      key: ValueKey(partKey),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              part.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '未记录' : value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 6),
          StudioIconButton(
            key: ValueKey(_partKey('add-part')),
            tooltip: '加入工作台',
            icon: Icons.add,
            onPressed: value.isEmpty ? null : part.onAdd,
          ),
          const SizedBox(width: 4),
          StudioIconButton(
            key: ValueKey(_partKey('copy-part')),
            tooltip: '复制提示词',
            icon: Icons.copy_outlined,
            onPressed: value.isEmpty ? null : () => _copy(context, value),
          ),
        ],
      ),
    );

    if (value.isEmpty) {
      return card;
    }

    return Draggable<Object>(
      data: _DrawerAssetDropData(
        label: part.label,
        onInsert: part.onInsert,
        characterName: part.label,
        characterPrompt: value,
      ),
      feedback: _DrawerDragFeedback(
        label: part.label,
        icon: Icons.content_copy,
        previewPath: null,
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );
  }

  String _partKey(String prefix) {
    final rawKey = outfitKey is ValueKey
        ? (outfitKey as ValueKey).value.toString()
        : outfitKey.toString();
    final suffix = rawKey.replaceFirst('workbench-drawer-card-', '');
    return 'workbench-drawer-$prefix-$suffix-${part.keySuffix}';
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制提示词')),
    );
  }
}

class _DrawerPromptSplitLine extends StatelessWidget {
  final String label;
  final String value;

  const _DrawerPromptSplitLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '未记录' : value.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: StudioTokens.textMuted,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          displayValue,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DrawerAssetPreview extends StatelessWidget {
  final IconData icon;
  final String? previewPath;

  const _DrawerAssetPreview({
    super.key,
    required this.icon,
    required this.previewPath,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: StudioTokens.radiusSlot,
      child: Container(
        width: _drawerPreviewWidth,
        height: _drawerPreviewHeight,
        color: StudioTokens.surface2,
        child: previewPath == null
            ? Icon(icon, size: 24, color: StudioTokens.textSecondary)
            : Image.file(
                File(previewPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    icon,
                    size: 24,
                    color: StudioTokens.textSecondary,
                  );
                },
              ),
      ),
    );
  }
}

class _DrawerDragFeedback extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? previewPath;

  const _DrawerDragFeedback({
    required this.label,
    required this.icon,
    required this.previewPath,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: StudioTokens.surface3,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(color: StudioTokens.primary),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _DrawerAssetPreview(icon: icon, previewPath: previewPath),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _DrawerState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: StudioTokens.warning),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}
