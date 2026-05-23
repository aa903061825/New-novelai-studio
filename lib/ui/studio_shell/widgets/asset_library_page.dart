import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

enum _AssetFilter {
  all,
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

class AssetLibraryPage extends StatefulWidget {
  final StudioAssetCatalogService catalogService;
  final StudioWorkbenchAssetService workbenchAssetService;

  const AssetLibraryPage({
    super.key,
    required this.catalogService,
    required this.workbenchAssetService,
  });

  @override
  State<AssetLibraryPage> createState() => _AssetLibraryPageState();
}

class _AssetLibraryPageState extends State<AssetLibraryPage> {
  late Future<StudioAssetCatalogSnapshot> _snapshotFuture;
  String _query = '';
  _AssetFilter _filter = _AssetFilter.all;
  String? _selectedBlock;
  _AssetDisplayItem? _selectedAsset;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.catalogService.loadSnapshot();
  }

  @override
  void didUpdateWidget(covariant AssetLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService) {
      _snapshotFuture = widget.catalogService.loadSnapshot();
      _selectedAsset = null;
    }
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

          final catalog = snapshot.data!;
          final allItems = _buildDisplayItems(catalog);
          final filteredItems = _filterItems(allItems);

          return _LibraryFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LibraryHeader(summary: catalog.summary),
                const SizedBox(height: 14),
                _AssetLibraryControls(
                  selectedFilter: _filter,
                  selectedBlock: _selectedBlock,
                  blocks: _availableBlocks(catalog),
                  resultCount: filteredItems.length,
                  onQueryChanged: (value) => setState(() {
                    _query = value;
                    _selectedAsset = null;
                  }),
                  onFilterChanged: (value) => setState(() {
                    _filter = value;
                    _selectedBlock = null;
                    _selectedAsset = null;
                  }),
                  onBlockChanged: (value) => setState(() {
                    _selectedBlock = _selectedBlock == value ? null : value;
                    _selectedAsset = null;
                  }),
                  onReload: _reload,
                ),
                const SizedBox(height: 14),
                _AssetLibraryBody(
                  items: filteredItems,
                  selectedAsset: _selectedAsset,
                  onSelect: (item) => setState(() {
                    _selectedAsset = item;
                  }),
                ),
              ],
            ),
          );
        },
      ),
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
          meta: _compactMeta([
            'ID ${character.id}',
            _sourceLabel(character.source),
          ]),
          referencePaths: character.imageRefs,
          details: _details([
            const _AssetDetailLine('类型', '角色'),
            _AssetDetailLine('ID', character.id),
            _AssetDetailLine('Prompt', character.traits.frontFull),
            _AssetDetailLine('来源类型', character.source.type),
            if (character.source.id != null)
              _AssetDetailLine('来源 ID', character.source.id!),
            if (character.source.path != null)
              _AssetDetailLine('来源路径', character.source.path!),
            if (character.note.isNotEmpty)
              _AssetDetailLine('备注', character.note),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendCharacter(character),
          ),
        ),
      for (final outfitAsset in catalog.outfits)
        _AssetDisplayItem(
          key: 'outfit-${outfitAsset.character.id}-${outfitAsset.outfit.id}',
          kind: _AssetKind.outfit,
          icon: Icons.checkroom_outlined,
          typeLabel: 'Outfit',
          title: outfitAsset.outfit.name,
          summary: outfitAsset.outfit.tags.frontFull,
          meta: '角色 ${outfitAsset.character.name}',
          referencePaths: outfitAsset.outfit.imageRefs,
          details: _details([
            const _AssetDetailLine('类型', 'Outfit'),
            _AssetDetailLine('ID', outfitAsset.outfit.id),
            _AssetDetailLine('所属角色', outfitAsset.character.name),
            _AssetDetailLine('Prompt', outfitAsset.outfit.tags.frontFull),
            if (outfitAsset.outfit.note.isNotEmpty)
              _AssetDetailLine('备注', outfitAsset.outfit.note),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendOutfit(
              outfitAsset.character,
              outfitAsset.outfit,
            ),
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
          meta: _compactMeta([
            'ID ${artistChain.id}',
            _sourceLabel(artistChain.source),
          ]),
          referencePaths: artistChain.imageRefs,
          details: _details([
            const _AssetDetailLine('类型', '画师串'),
            _AssetDetailLine('ID', artistChain.id),
            _AssetDetailLine('Prompt', _artistChainPrompt(artistChain)),
            if (artistChain.tags.isNotEmpty)
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
        ),
      for (final recipe in catalog.recipes)
        _AssetDisplayItem(
          key: 'recipe-${recipe.block}-${recipe.id}',
          kind: _AssetKind.recipe,
          icon: Icons.auto_awesome_mosaic_outlined,
          typeLabel: '配方',
          title: recipe.name,
          summary: _recipePrompt(recipe),
          meta: _compactMeta([recipe.block, recipe.category, recipe.group]),
          block: recipe.block,
          referencePaths: recipe.imageRefs,
          details: _details([
            const _AssetDetailLine('类型', '配方'),
            _AssetDetailLine('ID', recipe.id),
            _AssetDetailLine('Block', recipe.block),
            if (recipe.category.isNotEmpty)
              _AssetDetailLine('分类', recipe.category),
            if (recipe.group.isNotEmpty) _AssetDetailLine('分组', recipe.group),
            _AssetDetailLine('Prompt', _recipePrompt(recipe)),
            if (recipe.variants.isNotEmpty)
              _AssetDetailLine(
                '变体',
                recipe.variants.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
              ),
            if (recipe.note.isNotEmpty) _AssetDetailLine('备注', recipe.note),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendRecipe(recipe),
          ),
        ),
      for (final tag in catalog.tags)
        _AssetDisplayItem(
          key: 'tag-${tag.block}-${tag.id}',
          kind: _AssetKind.tag,
          icon: Icons.local_offer_outlined,
          typeLabel: 'Tag',
          title: tag.zh.isEmpty ? tag.tag : tag.zh,
          summary: tag.tag,
          meta: _compactMeta([tag.block, tag.category]),
          block: tag.block,
          referencePaths: tag.imageRefs,
          details: _details([
            const _AssetDetailLine('类型', 'Tag'),
            _AssetDetailLine('ID', tag.id),
            _AssetDetailLine('Tag', tag.tag),
            if (tag.zh.isNotEmpty) _AssetDetailLine('中文', tag.zh),
            _AssetDetailLine('Block', tag.block),
            if (tag.category.isNotEmpty) _AssetDetailLine('分类', tag.category),
            if (tag.aliases.isNotEmpty)
              _AssetDetailLine('别名', tag.aliases.join(', ')),
            if (tag.note.isNotEmpty) _AssetDetailLine('备注', tag.note),
          ]),
          onSend: () => _sendAsset(
            context,
            () => widget.workbenchAssetService.appendTag(tag),
          ),
        ),
      for (final inspiration in catalog.inspirations)
        _AssetDisplayItem(
          key: 'inspiration-${inspiration.id}',
          kind: _AssetKind.inspiration,
          icon: Icons.auto_awesome_outlined,
          typeLabel: 'Inspiration',
          title: inspiration.name,
          summary: _inspirationSummary(inspiration),
          meta: _compactMeta([
            'ID ${inspiration.id}',
            _sourceLabel(inspiration.source),
          ]),
          referencePaths: inspiration.imageRefs,
          details: _details([
            const _AssetDetailLine('Type', 'Inspiration'),
            _AssetDetailLine('ID', inspiration.id),
            if (inspiration.prompt.isNotEmpty)
              _AssetDetailLine('Prompt', inspiration.prompt),
            if (inspiration.negativePrompt.isNotEmpty)
              _AssetDetailLine('Negative Prompt', inspiration.negativePrompt),
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
          details: _details([
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
          details: _details([
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
          details: _details([
            const _AssetDetailLine('Type', 'Batch Plan'),
            _AssetDetailLine('ID', batchPlan.id),
            _AssetDetailLine('Items', batchPlan.items.length.toString()),
            if (batchPlan.statusSnapshot.isNotEmpty)
              _AssetDetailLine('Status', _mapPreview(batchPlan.statusSnapshot)),
            _AssetDetailLine('Created At', batchPlan.createdAt.toIso8601String()),
            _AssetDetailLine('Updated At', batchPlan.updatedAt.toIso8601String()),
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
          details: _details([
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

  List<_AssetDisplayItem> _filterItems(List<_AssetDisplayItem> items) {
    final normalizedQuery = _query.trim().toLowerCase();
    return items.where((item) {
      final typeMatches =
          _filter == _AssetFilter.all || _assetFilterFor(item.kind) == _filter;
      final blockMatches =
          _selectedBlock == null || item.block == _selectedBlock;
      final queryMatches =
          normalizedQuery.isEmpty || item.matches(normalizedQuery);
      return typeMatches && blockMatches && queryMatches;
    }).toList(growable: false);
  }

  _AssetFilter _assetFilterFor(_AssetKind kind) {
    return switch (kind) {
      _AssetKind.character => _AssetFilter.character,
      _AssetKind.outfit => _AssetFilter.outfit,
      _AssetKind.artistChain => _AssetFilter.artistChain,
      _AssetKind.recipe => _AssetFilter.recipe,
      _AssetKind.tag => _AssetFilter.tag,
      _AssetKind.inspiration => _AssetFilter.inspiration,
      _AssetKind.lora => _AssetFilter.lora,
      _AssetKind.workflow => _AssetFilter.workflow,
      _AssetKind.batchPlan => _AssetFilter.batchPlan,
      _AssetKind.assemblyPreset => _AssetFilter.assemblyPreset,
    };
  }

  List<String> _availableBlocks(StudioAssetCatalogSnapshot catalog) {
    return {
      ...catalog.recipes.map((recipe) => recipe.block),
      ...catalog.tags.map((tag) => tag.block),
    }.where((block) => block.trim().isNotEmpty).toList(growable: false)
      ..sort();
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
      _snapshotFuture = widget.catalogService.loadSnapshot();
      _selectedAsset = null;
    });
  }

  void _sendAsset(BuildContext context, VoidCallback send) {
    send();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已发送到工作台')),
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

  String _recipePrompt(Recipe recipe) {
    if (recipe.tags.trim().isNotEmpty) {
      return recipe.tags.trim();
    }
    return recipe.variants.values.join(', ');
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
    return values.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');
  }
}

class _LibraryFrame extends StatelessWidget {
  final Widget child;

  const _LibraryFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(StudioTokens.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: child,
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  final StudioAssetCatalogSummary summary;

  const _LibraryHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    final description = summary.isEmpty
        ? '素材库还是空的，新建第一条素材，或把工作台结果沉淀进来。'
        : '已整理 ${summary.totalAssetCount} 条可复用素材，可直接送入工作台。';
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
  final String? selectedBlock;
  final List<String> blocks;
  final int resultCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_AssetFilter> onFilterChanged;
  final ValueChanged<String> onBlockChanged;
  final VoidCallback onReload;

  const _AssetLibraryControls({
    required this.selectedFilter,
    required this.selectedBlock,
    required this.blocks,
    required this.resultCount,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onBlockChanged,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      (_AssetFilter.all, '全部', 'asset-filter-all'),
      (_AssetFilter.character, '角色', 'asset-filter-character'),
      (_AssetFilter.outfit, 'Outfit', 'asset-filter-outfit'),
      (_AssetFilter.artistChain, '画师串', 'asset-filter-artist-chain'),
      (_AssetFilter.recipe, '配方', 'asset-filter-recipe'),
      (_AssetFilter.tag, 'Tag', 'asset-filter-tag'),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in filters)
                KeyedSubtree(
                  key: ValueKey(filter.$3),
                  child: StudioChip(
                    label: filter.$2,
                    selected: selectedFilter == filter.$1,
                    onTap: () => onFilterChanged(filter.$1),
                  ),
                ),
            ],
          ),
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
            ],
          ),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final block in blocks)
                  KeyedSubtree(
                    key: ValueKey('asset-block-filter-$block'),
                    child: StudioChip(
                      label: block,
                      icon: Icons.folder_outlined,
                      selected: selectedBlock == block,
                      onTap: () => onBlockChanged(block),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetLibraryBody extends StatelessWidget {
  final List<_AssetDisplayItem> items;
  final _AssetDisplayItem? selectedAsset;
  final ValueChanged<_AssetDisplayItem> onSelect;

  const _AssetLibraryBody({
    required this.items,
    required this.selectedAsset,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final board = _AssetWaterfallBoard(
          items: items,
          selectedAsset: selectedAsset,
          onSelect: onSelect,
        );
        final drawer = _AssetDetailDrawer(asset: selectedAsset);

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
            Expanded(child: board),
            const SizedBox(width: 14),
            SizedBox(width: 340, child: drawer),
          ],
        );
      },
    );
  }
}

class _AssetWaterfallBoard extends StatelessWidget {
  final List<_AssetDisplayItem> items;
  final _AssetDisplayItem? selectedAsset;
  final ValueChanged<_AssetDisplayItem> onSelect;

  const _AssetWaterfallBoard({
    required this.items,
    required this.selectedAsset,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyRow(message: '没有匹配的素材');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 680
                ? 2
                : 1;
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
            return _WaterfallAssetCard(
              item: item,
              selected: selectedAsset?.key == item.key,
              onSelect: () => onSelect(item),
            );
          },
        );
      },
    );
  }
}

class _WaterfallAssetCard extends StatelessWidget {
  final _AssetDisplayItem item;
  final bool selected;
  final VoidCallback onSelect;

  const _WaterfallAssetCard({
    required this.item,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('asset-card-${item.key}'),
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
                  StudioChip(label: item.typeLabel, icon: item.icon),
                  const Spacer(),
                  StudioIconButton(
                    key: ValueKey('asset-card-send-${item.key}'),
                    tooltip: '发送到工作台',
                    icon: Icons.keyboard_return,
                    onPressed: item.onSend,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (item.meta.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  item.meta,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: StudioTokens.textMuted,
                      ),
                ),
              ],
              if (item.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  item.summary,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (item.hasReferenceWarning) ...[
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: StudioChip(
                    label: '引用待检查',
                    icon: Icons.warning_amber_outlined,
                    selected: true,
                    accentColor: StudioTokens.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetDetailDrawer extends StatelessWidget {
  final _AssetDisplayItem? asset;

  const _AssetDetailDrawer({required this.asset});

  @override
  Widget build(BuildContext context) {
    final item = asset;
    if (item == null) {
      return const StudioPanel(
        key: ValueKey('asset-library-detail-drawer'),
        color: StudioTokens.surface2,
        child: _EmptyRow(message: '选择一张素材卡片查看详情'),
      );
    }

    return StudioPanel(
      key: const ValueKey('asset-library-detail-drawer'),
      color: StudioTokens.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(item.icon, color: StudioTokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '素材详情',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StudioIconButton(
                key: const ValueKey('asset-detail-send'),
                tooltip: '发送到工作台',
                icon: Icons.keyboard_return,
                onPressed: item.onSend,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          for (final detail in item.details) ...[
            Text(
              detail.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
            const SizedBox(height: 4),
            Text(detail.value),
            const SizedBox(height: 10),
          ],
          if (item.referencePaths.isNotEmpty) ...[
            Text(
              '参考引用',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StudioTokens.textMuted,
                  ),
            ),
            const SizedBox(height: 4),
            for (final path in item.referencePaths) Text(path),
          ],
        ],
      ),
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

class _AssetDisplayItem {
  final String key;
  final _AssetKind kind;
  final IconData icon;
  final String typeLabel;
  final String title;
  final String summary;
  final String meta;
  final String? block;
  final List<_AssetDetailLine> details;
  final List<String> referencePaths;
  final VoidCallback? onSend;

  const _AssetDisplayItem({
    required this.key,
    required this.kind,
    required this.icon,
    required this.typeLabel,
    required this.title,
    required this.summary,
    required this.meta,
    required this.details,
    required this.referencePaths,
    required this.onSend,
    this.block,
  });

  bool get hasReferenceWarning => referencePaths.isNotEmpty;

  bool matches(String normalizedQuery) {
    final haystack = [
      typeLabel,
      title,
      summary,
      meta,
      if (block != null) block!,
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
