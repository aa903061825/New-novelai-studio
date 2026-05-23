# Novel Studio Waterfall Asset Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `NAI_NEW-c8d` into a Studio-style waterfall asset library with searchable/filterable material cards, a read-only detail drawer, reference warning markers, and the existing real send-to-workbench flow.

**Architecture:** Keep `StudioAssetCatalogService.loadSnapshot()` and `StudioWorkbenchAssetService` as the data/action boundaries. Flatten catalog entities into private UI display assets inside `AssetLibraryPage`, then render those assets through `WaterfallFlow` and a selected-asset detail drawer without changing workspace schema or generation behavior.

**Tech Stack:** Flutter, Dart, existing Studio widgets/tokens, `waterfall_flow`, Flutter widget tests.

---

## Execution Note

`C:\Users\admin\Downloads\NAI_NEW` is not a Git repository, so this plan uses verification checkpoints instead of commit commands. If the workspace is put under Git before execution, commit after each green task.

## File Map

- Modify `lib/ui/studio_shell/widgets/asset_library_page.dart`
  - Replace the sectioned card layout with a waterfall board.
  - Add private display models for flattened catalog assets.
  - Add selected-asset state and a read-only detail drawer.
  - Add block filter chips for recipe/tag blocks.
  - Keep existing load, retry, search, type filter, and send-to-workbench behavior.
- Modify `test/ui/studio_shell/asset_library_page_test.dart`
  - Update existing tests from grouped cards to waterfall cards.
  - Add detail drawer, drawer send, block filter, and reference warning coverage.
- Review `test/data/studio/studio_asset_catalog_service_test.dart`
  - Keep service tests unchanged unless a regression reveals catalog behavior drift.

## Task 1: Add Failing Widget Coverage For Waterfall Cards And Detail Drawer

**Files:**
- Modify: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Expand the fake snapshot so tests can prove reference warnings and richer details**

Update the constant `snapshot` in `test/ui/studio_shell/asset_library_page_test.dart` so at least one asset has `imageRefs`, category, aliases, variants, note, and source metadata:

```dart
const snapshot = StudioAssetCatalogSnapshot(
  summary: StudioAssetCatalogSummary(
    characterCount: 1,
    outfitCount: 1,
    artistChainCount: 1,
    recipeCount: 1,
    tagCount: 1,
    recipeCountsByBlock: {'style': 1},
    tagCountsByBlock: {'scene': 1},
  ),
  characters: [
    CharacterEntry(
      id: 'char-1',
      name: '璃夏',
      traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
      imageRefs: ['refs/lixia.png'],
      source: SourceRef(type: 'kamia', id: 'k-char-1', path: 'characters/lixia.json'),
      note: '主角素材',
      outfits: [
        WorkspaceOutfit(
          id: 'outfit-1',
          name: '雨披',
          tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
          note: '雨天外套',
        ),
      ],
    ),
  ],
  outfits: [
    StudioOutfitAsset(
      character: CharacterEntry(
        id: 'char-1',
        name: '璃夏',
        traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
      ),
      outfit: WorkspaceOutfit(
        id: 'outfit-1',
        name: '雨披',
        tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
        note: '雨天外套',
      ),
    ),
  ],
  artistChains: [
    ArtistChain(
      id: 'artist-1',
      name: '水彩柔光',
      prompt: 'watercolor wash, soft light',
      tags: ['transparent color'],
      styleTags: ['soft rim'],
      translations: {'watercolor': '水彩'},
    ),
  ],
  recipes: [
    Recipe(
      id: 'recipe-1',
      name: '雨夜街道',
      block: 'style',
      category: 'city',
      group: 'night',
      tags: 'wet asphalt, neon reflection',
      variants: {'close': 'wet asphalt close-up'},
    ),
  ],
  tags: [
    TagEntry(
      id: 'tag-1',
      tag: 'rainy street',
      zh: '雨街',
      block: 'scene',
      category: 'weather',
      aliases: ['rain road'],
    ),
  ],
);
```

- [ ] **Step 2: Replace the render test expectations with waterfall-specific keys**

In `asset library page renders concrete reusable assets`, keep the existing text assertions and add waterfall assertions:

```dart
expect(find.byKey(const ValueKey('asset-library-waterfall-board')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-character-char-1')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-artist-artist-1')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-recipe-style-recipe-1')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-tag-scene-tag-1')), findsOneWidget);
expect(find.text('引用待检查'), findsOneWidget);
```

- [ ] **Step 3: Add a failing detail drawer test**

Append this widget test:

```dart
testWidgets('asset library opens a detail drawer for the selected waterfall card', (tester) async {
  final config = payload();

  await tester.pumpWidget(page(config: config));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('asset-library-detail-drawer')), findsOneWidget);
  expect(find.text('素材详情'), findsOneWidget);
  expect(find.text('char-1'), findsOneWidget);
  expect(find.text('kamia'), findsOneWidget);
  expect(find.text('characters/lixia.json'), findsOneWidget);
  expect(find.text('主角素材'), findsOneWidget);
  expect(find.text('refs/lixia.png'), findsOneWidget);
});
```

- [ ] **Step 4: Add a failing drawer-send test**

Append this widget test:

```dart
testWidgets('asset library detail drawer can send the selected asset to workbench', (tester) async {
  final config = payload();
  final service = StudioWorkbenchAssetService(payloadConfig: config);

  await tester.pumpWidget(page(config: config, service: service));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('asset-card-tag-scene-tag-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('asset-detail-send')));
  await tester.pump();

  expect(config.useOverridePrompt, isTrue);
  expect(config.overridePrompt, 'rainy street');
  expect(service.fragments.single.typeLabel, 'Tag');
  expect(find.text('已发送到工作台'), findsOneWidget);
});
```

- [ ] **Step 5: Add a failing block-filter test**

Append this widget test:

```dart
testWidgets('asset library filters recipes and tags by block chip', (tester) async {
  final config = payload();

  await tester.pumpWidget(page(config: config));
  await tester.pumpAndSettle();

  final styleFilter = find.byKey(const ValueKey('asset-block-filter-style'));
  await tester.ensureVisible(styleFilter);
  await tester.tap(styleFilter);
  await tester.pumpAndSettle();

  expect(find.text('雨夜街道'), findsOneWidget);
  expect(find.text('雨街'), findsNothing);
  expect(find.text('璃夏'), findsNothing);
});
```

- [ ] **Step 6: Run the asset library widget tests and verify they fail for missing waterfall/detail behavior**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: FAIL because `asset-library-waterfall-board`, `asset-card-*`, detail drawer, drawer send key, and block filter chips do not exist yet.

## Task 2: Flatten Catalog Assets Into Searchable Display Assets

**Files:**
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`

- [ ] **Step 1: Add private asset type and display model classes near the bottom of the file**

Add these private types after `_AssetItemData` or replace `_AssetItemData` if it becomes unused:

```dart
enum _AssetKind { character, outfit, artistChain, recipe, tag }

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
  final VoidCallback onSend;

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
```

- [ ] **Step 2: Replace grouped item construction with `_buildDisplayItems`**

Inside `_AssetLibraryPageState`, add a method that flattens the snapshot:

```dart
List<_AssetDisplayItem> _buildDisplayItems(StudioAssetCatalogSnapshot catalog) {
  return [
    for (final character in catalog.characters)
      _AssetDisplayItem(
        key: 'character-${character.id}',
        kind: _AssetKind.character,
        icon: Icons.person_outline,
        typeLabel: '角色',
        title: character.name,
        summary: character.traits.frontFull,
        meta: _compactMeta(['ID ${character.id}', _sourceLabel(character.source)]),
        referencePaths: character.imageRefs,
        details: _details([
          _AssetDetailLine('类型', '角色'),
          _AssetDetailLine('ID', character.id),
          _AssetDetailLine('Prompt', character.traits.frontFull),
          _AssetDetailLine('来源类型', character.source.type),
          if (character.source.id != null) _AssetDetailLine('来源 ID', character.source.id!),
          if (character.source.path != null) _AssetDetailLine('来源路径', character.source.path!),
          if (character.note.isNotEmpty) _AssetDetailLine('备注', character.note),
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
        meta: _compactMeta(['ID ${artistChain.id}', _sourceLabel(artistChain.source)]),
        referencePaths: artistChain.imageRefs,
        details: _details([
          const _AssetDetailLine('类型', '画师串'),
          _AssetDetailLine('ID', artistChain.id),
          _AssetDetailLine('Prompt', _artistChainPrompt(artistChain)),
          if (artistChain.tags.isNotEmpty) _AssetDetailLine('Tags', artistChain.tags.join(', ')),
          if (artistChain.styleTags.isNotEmpty)
            _AssetDetailLine('Style Tags', artistChain.styleTags.join(', ')),
          if (artistChain.translations.isNotEmpty)
            _AssetDetailLine(
              '翻译',
              artistChain.translations.entries.map((entry) => '${entry.key}: ${entry.value}').join(', '),
            ),
          if (artistChain.note.isNotEmpty) _AssetDetailLine('备注', artistChain.note),
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
          if (recipe.category.isNotEmpty) _AssetDetailLine('分类', recipe.category),
          if (recipe.group.isNotEmpty) _AssetDetailLine('分组', recipe.group),
          _AssetDetailLine('Prompt', _recipePrompt(recipe)),
          if (recipe.variants.isNotEmpty)
            _AssetDetailLine(
              '变体',
              recipe.variants.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n'),
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
          if (tag.aliases.isNotEmpty) _AssetDetailLine('别名', tag.aliases.join(', ')),
          if (tag.note.isNotEmpty) _AssetDetailLine('备注', tag.note),
        ]),
        onSend: () => _sendAsset(
          context,
          () => widget.workbenchAssetService.appendTag(tag),
        ),
      ),
  ];
}
```

Add helper methods used above:

```dart
List<_AssetDetailLine> _details(List<_AssetDetailLine> lines) {
  return lines.where((line) => line.value.trim().isNotEmpty).toList(growable: false);
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
```

- [ ] **Step 3: Add filter state for blocks**

In `_AssetLibraryPageState`, add:

```dart
String? _selectedBlock;
_AssetDisplayItem? _selectedAsset;
```

Then add filter helpers:

```dart
List<_AssetDisplayItem> _filterItems(List<_AssetDisplayItem> items) {
  final normalizedQuery = _query.trim().toLowerCase();
  return items.where((item) {
    final typeMatches = _filter == _AssetFilter.all || _assetFilterFor(item.kind) == _filter;
    final blockMatches = _selectedBlock == null || item.block == _selectedBlock;
    final queryMatches = normalizedQuery.isEmpty || item.matches(normalizedQuery);
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
  };
}
```

- [ ] **Step 4: Run analyzer to catch private type/signature mistakes**

Run:

```powershell
flutter analyze --no-pub
```

Expected before Task 3 UI wiring: analyzer may fail if old build code still references removed group classes. Either keep old group code temporarily or continue directly to Task 3 before re-running.

## Task 3: Render The Waterfall Board And Detail Drawer

**Files:**
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`

- [ ] **Step 1: Import `waterfall_flow`**

Add:

```dart
import 'package:waterfall_flow/waterfall_flow.dart';
```

- [ ] **Step 2: Replace the main loaded body with command band, board, and drawer**

Inside the `FutureBuilder` loaded branch, replace the old metric grid and section loop with:

```dart
final catalog = snapshot.data!;
final summary = catalog.summary;
final allItems = _buildDisplayItems(catalog);
final filteredItems = _filterItems(allItems);
final blocks = _availableBlocks(catalog);

return _LibraryFrame(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _LibraryHeader(summary: summary),
      const SizedBox(height: 14),
      _AssetLibraryControls(
        selectedFilter: _filter,
        selectedBlock: _selectedBlock,
        blocks: blocks,
        resultCount: filteredItems.length,
        onQueryChanged: (value) => setState(() {
          _query = value;
        }),
        onFilterChanged: (value) => setState(() {
          _filter = value;
          _selectedBlock = null;
        }),
        onBlockChanged: (value) => setState(() {
          _selectedBlock = _selectedBlock == value ? null : value;
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
```

Add block derivation:

```dart
List<String> _availableBlocks(StudioAssetCatalogSnapshot catalog) {
  return {
    ...catalog.recipes.map((recipe) => recipe.block),
    ...catalog.tags.map((tag) => tag.block),
  }.where((block) => block.trim().isNotEmpty).toList(growable: false)
    ..sort();
}
```

- [ ] **Step 3: Update `_AssetLibraryControls` to include counts, block chips, and refresh**

Change the constructor to accept:

```dart
final String? selectedBlock;
final List<String> blocks;
final int resultCount;
final ValueChanged<String> onBlockChanged;
final VoidCallback onReload;
```

In `build`, keep the search field and type chips, then add:

```dart
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
```

- [ ] **Step 4: Add `_AssetLibraryBody` with wide and compact layouts**

Add:

```dart
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
```

- [ ] **Step 5: Add `_AssetWaterfallBoard`**

Add:

```dart
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
```

- [ ] **Step 6: Add `_WaterfallAssetCard`**

Add:

```dart
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
      color: selected ? StudioTokens.primary.withAlpha(20) : StudioTokens.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioTokens.radiusMedium),
        side: BorderSide(
          color: selected ? StudioTokens.primary : StudioTokens.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(StudioTokens.radiusMedium),
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
                const StudioChip(
                  label: '引用待检查',
                  icon: Icons.warning_amber_outlined,
                  accentColor: StudioTokens.warning,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Add `_AssetDetailDrawer`**

Add:

```dart
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
            SelectableText(detail.value),
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
            for (final path in item.referencePaths) SelectableText(path),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: Remove obsolete section/grid widgets once no longer referenced**

Delete private widgets/classes that are no longer used by the new body:

- `_MetricGrid`
- `_BlockBreakdown`
- `_AssetSection`
- `_AssetTile`
- `_AssetGroupData`
- `_AssetItemData`

Keep `_EmptyRow`, `_StatePanel`, `_LibraryHeader`, and `_LibraryFrame`.

- [ ] **Step 9: Run the asset library widget tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: PASS.

## Task 4: Preserve Existing Search/Type Send Behavior And Fix Regressions

**Files:**
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Modify: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Update the existing card send test to tap a stable card send key**

Replace:

```dart
final firstSendButton = find.byTooltip('发送到工作台').first;
await tester.ensureVisible(firstSendButton);
await tester.tap(firstSendButton);
```

with:

```dart
final sendButton = find.byKey(const ValueKey('asset-card-send-character-char-1'));
await tester.ensureVisible(sendButton);
await tester.tap(sendButton);
```

- [ ] **Step 2: Update the search/type filter test to assert waterfall cards**

After searching `雨披`, assert:

```dart
expect(find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-artist-artist-1')), findsNothing);
```

After tapping `asset-filter-tag`, assert:

```dart
expect(find.byKey(const ValueKey('asset-card-tag-scene-tag-1')), findsOneWidget);
expect(find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')), findsNothing);
expect(find.byKey(const ValueKey('asset-card-artist-artist-1')), findsNothing);
```

- [ ] **Step 3: Make type filter clear block filter and keep selected detail coherent**

In the `_AssetLibraryControls.onFilterChanged` callback in `AssetLibraryPage`, use:

```dart
onFilterChanged: (value) => setState(() {
  _filter = value;
  _selectedBlock = null;
  _selectedAsset = null;
}),
```

In search and block filter callbacks, also clear `_selectedAsset` if the selected item will no longer match:

```dart
onQueryChanged: (value) => setState(() {
  _query = value;
  _selectedAsset = null;
}),
onBlockChanged: (value) => setState(() {
  _selectedBlock = _selectedBlock == value ? null : value;
  _selectedAsset = null;
}),
```

- [ ] **Step 4: Run focused asset library tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: PASS.

## Task 5: Verify Related Regression Surface

**Files:**
- Review: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Review: `lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart`
- Review: `test/ui/navigation/novel_studio_navigation_test.dart`
- Review: `test/ui/studio_workbench/workbench_asset_drawer_test.dart`

- [ ] **Step 1: Run asset catalog and related UI tests**

Run:

```powershell
flutter test --no-pub test/data/studio/studio_asset_catalog_service_test.dart test/ui/studio_shell/asset_library_page_test.dart test/ui/studio_workbench/workbench_asset_drawer_test.dart test/ui/navigation/novel_studio_navigation_test.dart -r expanded
```

Expected: PASS. If navigation tests fail because expected text count changed, update only assertions that depend on the old asset library internals; do not change navigation behavior.

- [ ] **Step 2: Run analyzer**

Run:

```powershell
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 3: Run focused Studio UI tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell test/ui/studio_workbench -r expanded
```

Expected: PASS.

- [ ] **Step 4: Run full Flutter test suite**

Run:

```powershell
flutter test --no-pub -r expanded
```

Expected: PASS.

## Task 6: Close The Beads Issue

**Files:**
- No code files.

- [ ] **Step 1: Show the issue to confirm status**

Run:

```powershell
bd show NAI_NEW-c8d
```

Expected: issue is `IN_PROGRESS`.

- [ ] **Step 2: Close the issue with verification evidence**

Run:

```powershell
bd close NAI_NEW-c8d --reason "完成瀑布流素材库：AssetLibraryPage 保留 StudioAssetCatalogService 真实索引，改为 Studio 风格 waterfall board、搜索/类型/block 筛选、详情抽屉、引用待检查提示，并保留卡片和详情发送到工作台。验证：flutter analyze --no-pub 通过；flutter test --no-pub -r expanded 通过。"
```

Expected: `NAI_NEW-c8d` closed.

## Plan Self-Review

- Spec coverage:
  - Waterfall board is covered by Tasks 1 and 3.
  - Search, type filter, and block filter are covered by Tasks 1, 2, and 4.
  - Detail drawer is covered by Tasks 1 and 3.
  - Send-to-workbench from card and drawer is covered by Tasks 1, 3, and 4.
  - Reference warning markers are covered by Tasks 1 and 3.
  - Real catalog service remains unchanged and is covered by Task 5.
- Placeholder scan:
  - No `TBD`, `TODO`, or open-ended placeholders remain.
- Type consistency:
  - `_AssetDisplayItem`, `_AssetDetailLine`, `_AssetKind`, `_AssetLibraryBody`, `_AssetWaterfallBoard`, `_WaterfallAssetCard`, and `_AssetDetailDrawer` use consistent names across the plan.
