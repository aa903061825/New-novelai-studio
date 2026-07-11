import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/script_recast_asset_context_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

void main() {
  group('ScriptRecastAssetContextService', () {
    test('loads Recast asset options from a single catalog snapshot', () async {
      final catalog = _FakeCatalogService(
        snapshot: _snapshot(
          characters: const [
            CharacterEntry(
              id: 'char-hero',
              name: 'Heroine',
              traits: ViewVariantTexts(frontFull: 'green eyes'),
              imageRefs: ['characters/hero.png'],
              defaultOutfitId: 'dress',
              aliases: ['lead'],
              outfits: [
                WorkspaceOutfit(
                  id: 'dress',
                  name: 'Stage Dress',
                  tags: ViewVariantTexts(frontFull: 'black dress'),
                  imageRefs: ['outfits/dress.png'],
                ),
                WorkspaceOutfit(
                  id: 'coat',
                  name: 'Rain Coat',
                  tags: ViewVariantTexts(frontFull: 'yellow coat'),
                ),
              ],
            ),
            CharacterEntry(
              id: 'char-sidekick',
              name: 'Sidekick',
              traits: ViewVariantTexts(frontFull: 'short hair'),
            ),
          ],
          artistChains: const [
            ArtistChain(
              id: 'artist-watercolor',
              name: 'Watercolor',
              prompt: 'soft wash',
              imageRefs: ['artists/watercolor.png'],
            ),
          ],
        ),
        filterRules: const {
          'delete_keywords': 'bad hands, lowres',
          'strong_filter_keywords': 'artist:old_style',
          'replace_rules': 'city lights -> neon city',
          'delete_artist_tags': true,
        },
      );

      final context = await ScriptRecastAssetContextService(
        catalogService: catalog,
      ).loadContext();

      expect(catalog.snapshotLoadCount, 0);
      expect(catalog.cachedSnapshotLoadCount, 1);
      expect(context.characters.map((character) => character.id), [
        'char-hero',
        'char-sidekick',
      ]);
      expect(context.outfits.map((asset) => asset.outfit.id), [
        'dress',
        'coat',
      ]);
      expect(context.artistChains.single.id, 'artist-watercolor');
      expect(context.characterById['char-hero']?.name, 'Heroine');
      expect(context.artistChainById['artist-watercolor']?.prompt, 'soft wash');
      expect(
          context.outfitsByCharacterId['char-hero']?.map((asset) {
            return asset.outfit.name;
          }),
          ['Stage Dress', 'Rain Coat']);
      expect(context.defaultOutfitFor('char-hero')?.outfit.id, 'dress');
      expect(context.defaultOutfitFor('char-sidekick'), isNull);
      expect(
        context.characterPreviewPaths['char-hero'],
        'resolved:characters/hero.png',
      );
      expect(
        context.outfitPreviewPaths[
            ScriptRecastAssetContext.outfitKey('char-hero', 'dress')],
        'resolved:outfits/dress.png',
      );
      expect(
        context.artistChainPreviewPaths['artist-watercolor'],
        'resolved:artists/watercolor.png',
      );
      expect(context.filterMetadata.isConfigured, isTrue);
      expect(context.filterMetadata.isEnabled, isTrue);
      expect(context.filterMetadata.deleteKeywordCount, 2);
      expect(context.filterMetadata.strongFilterKeywordCount, 1);
      expect(context.filterMetadata.replaceRuleCount, 1);
      expect(context.filterMetadata.deleteArtistTags, isTrue);
    });

    test('loads Recast asset options through catalog cache fast path',
        () async {
      final catalog = _FakeCatalogService(
        snapshot: _snapshot(
          characters: const [
            CharacterEntry(
              id: 'char-cached',
              name: 'Cached Heroine',
              traits: ViewVariantTexts(frontFull: 'cached green eyes'),
            ),
          ],
        ),
      );
      catalog.throwOnDirectSnapshotLoad = true;

      final context = await ScriptRecastAssetContextService(
        catalogService: catalog,
      ).loadContext();

      expect(catalog.snapshotLoadCount, 0);
      expect(catalog.cachedSnapshotLoadCount, 1);
      expect(context.characters.single.id, 'char-cached');
    });

    test('exposes immutable empty metadata when filters are absent', () async {
      final context = await ScriptRecastAssetContextService(
        catalogService: _FakeCatalogService(snapshot: _snapshot()),
      ).loadContext();

      expect(context.characters, isEmpty);
      expect(context.outfits, isEmpty);
      expect(context.artistChains, isEmpty);
      expect(context.filterMetadata.isConfigured, isFalse);
      expect(context.filterMetadata.isEnabled, isFalse);
      expect(context.defaultOutfitFor('missing'), isNull);
      expect(
        () => context.characterById['new'] = const CharacterEntry(
          id: 'new',
          name: 'New',
          traits: ViewVariantTexts(frontFull: 'new'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}

StudioAssetCatalogSnapshot _snapshot({
  List<CharacterEntry> characters = const [],
  List<ArtistChain> artistChains = const [],
}) {
  final outfits = [
    for (final character in characters)
      for (final outfit in character.outfits)
        StudioOutfitAsset(character: character, outfit: outfit),
  ];

  return StudioAssetCatalogSnapshot(
    summary: StudioAssetCatalogSummary(
      characterCount: characters.length,
      outfitCount: outfits.length,
      artistChainCount: artistChains.length,
      recipeCount: 0,
      tagCount: 0,
      recipeCountsByBlock: const {},
      tagCountsByBlock: const {},
    ),
    characters: characters,
    outfits: outfits,
    artistChains: artistChains,
    recipes: const [],
    tags: const [],
  );
}

class _FakeCatalogService extends StudioAssetCatalogService {
  final StudioAssetCatalogSnapshot snapshot;
  final Map<String, dynamic>? filterRules;
  int snapshotLoadCount = 0;
  int cachedSnapshotLoadCount = 0;
  bool throwOnDirectSnapshotLoad = false;

  _FakeCatalogService({
    required this.snapshot,
    this.filterRules,
  }) : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    snapshotLoadCount += 1;
    if (throwOnDirectSnapshotLoad) {
      throw StateError('Direct catalog snapshot load should not be used.');
    }
    return snapshot;
  }

  @override
  Future<StudioAssetCatalogCacheLoadResult> loadSnapshotWithCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool checkStaleness = true,
    bool persistCacheBeforeReturn = true,
  }) async {
    cachedSnapshotLoadCount += 1;
    return StudioAssetCatalogCacheLoadResult(
      snapshot: snapshot,
      fromCache: true,
      isStale: false,
    );
  }

  @override
  Future<Map<String, dynamic>> loadWorkbenchFilterRules() async {
    final rules = filterRules;
    if (rules == null) {
      return const {};
    }
    return Map.unmodifiable(rules);
  }

  @override
  String? resolveImagePath(List<String> refs) {
    if (refs.isEmpty) return null;
    return 'resolved:${refs.first}';
  }
}
