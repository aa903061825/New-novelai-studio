import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/asset_tag_cache_prewarm_service.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

void main() {
  test('prewarms deduped asset and codex tags into caches', () async {
    final catalog = _FakeCatalogService(_snapshot);
    final translationCache = TranslationCache(clock: () => 1710000000)
      ..setCached('blue eyes', 'cached blue eyes', source: 'manual');
    final classificationCache = PromptTagClassificationCache(
      clock: () => 1710000000,
    );
    final translated = <String>[];
    var translationSaved = false;
    var classificationSaved = false;
    final service = AssetTagCachePrewarmService(
      catalogService: catalog,
      translationService: _FakePromptTranslationService((request) async {
        translated.add(request.text);
        return OnlineTranslationResult(
          text: 'zh:${request.text}',
          source: OnlineAiResultSource.online,
          providerName: 'fake-ai',
        );
      }),
      translationCache: translationCache,
      classificationCache: classificationCache,
      saveTranslationCache: (_) async => translationSaved = true,
      saveClassificationCache: (_) async => classificationSaved = true,
    );

    final result = await service.prewarm(includeCodex: true);

    expect(catalog.lastIncludeLegacyCodex, isTrue);
    expect(catalog.lastLegacyCodexLimit, greaterThan(1000000));
    expect(translated, containsAll(['silver hair', 'lowres', 'bad hands']));
    expect(translated, isNot(contains('blue eyes')));
    expect(translationCache.getCached('blue eyes'), 'cached blue eyes');
    expect(translationCache.getCached('silver hair'), 'zh:silver hair');
    expect(translationCache.getCached('lowres'), 'zh:lowres');
    expect(translationCache.getCached('rainy street'), 'cached-rainy-street');
    expect(translationCache.getCached('year_2023'), isNotNull);
    expect(translationCache.getCached('year_2023'), '2023年');
    expect(classificationCache.isEmpty, isTrue);
    expect(result.uniqueTagCount, greaterThanOrEqualTo(8));
    expect(result.translationCacheHits, greaterThanOrEqualTo(2));
    expect(result.translatedCount, greaterThanOrEqualTo(3));
    expect(result.classifiedCount, 0);
    expect(translationSaved, isTrue);
    expect(classificationSaved, isFalse);
  });
}

const _snapshot = StudioAssetCatalogSnapshot(
  summary: StudioAssetCatalogSummary(
    characterCount: 1,
    outfitCount: 1,
    artistChainCount: 1,
    recipeCount: 1,
    tagCount: 1,
    inspirationCount: 2,
    loraCount: 1,
    recipeCountsByBlock: {'style': 1},
    tagCountsByBlock: {'scene': 1},
  ),
  characters: [
    CharacterEntry(
      id: 'char-1',
      name: 'Lixia',
      traits: ViewVariantTexts(
        frontFull: 'silver hair, blue eyes',
        frontUpper: 'blue eyes',
      ),
      anchorTags: ['solo focus'],
      conflictTags: ['wrong hair color'],
      outfits: [
        WorkspaceOutfit(
          id: 'rain',
          name: 'Rain',
          tags: ViewVariantTexts(
            frontFull: 'yellow jacket, rain skirt',
          ),
          partTags: WorkspaceOutfitPartTags(
            upperClothingTags: ['yellow jacket'],
            lowerClothingTags: ['rain skirt'],
          ),
        ),
      ],
    ),
  ],
  artistChains: [
    ArtistChain(
      id: 'artist-1',
      name: 'Watercolor',
      prompt: 'artist:wlop, watercolor wash',
      tags: ['transparent color'],
      globalNegatives: [
        WorkspaceWeightedTag(tag: 'bad hands', weight: 1),
      ],
      translations: {'transparent color': '透明色'},
    ),
  ],
  recipes: [
    Recipe(
      id: 'recipe-1',
      name: 'Rainy street',
      block: 'scene',
      tags: 'wet asphalt, blue eyes',
      variants: {'close': 'neon reflection'},
    ),
  ],
  tags: [
    TagEntry(
      id: 'tag-1',
      tag: 'rainy street',
      zh: 'cached-rainy-street',
      block: 'scene',
      aliases: ['rain road'],
    ),
  ],
  inspirations: [
    InspirationEntry(
      id: 'insp-1',
      name: 'Night Alley',
      prompt: 'city lights, blue eyes, year_2023, year_2024',
      negativePrompt: 'lowres, bad hands',
      tags: ['rainy street'],
    ),
    InspirationEntry(
      id: 'legacy-1',
      name: 'Codex Entry',
      prompt: 'masterpiece, silver hair',
      negativePrompt: 'lowres',
      tags: ['codex'],
      source: SourceRef(type: 'legacy_codex'),
    ),
  ],
  loras: [
    LoraEntry(
      id: 'lora-1',
      name: 'Soft Rain',
      triggerWords: ['soft-rain', 'mist glow'],
    ),
  ],
);

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService(this.snapshot)
      : super(workspaceService: WorkspaceService());

  final StudioAssetCatalogSnapshot snapshot;
  bool? lastIncludeLegacyCodex;
  int? lastLegacyCodexLimit;

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    lastIncludeLegacyCodex = includeLegacyCodex;
    lastLegacyCodexLimit = legacyCodexLimit;
    if (includeLegacyCodex) {
      return snapshot;
    }
    return StudioAssetCatalogSnapshot(
      summary: snapshot.summary,
      characters: snapshot.characters,
      outfits: snapshot.outfits,
      artistChains: snapshot.artistChains,
      recipes: snapshot.recipes,
      tags: snapshot.tags,
      inspirations: snapshot.inspirations
          .where((entry) => entry.source.type != 'legacy_codex')
          .toList(growable: false),
      loras: snapshot.loras,
      workflows: snapshot.workflows,
      batchPlans: snapshot.batchPlans,
      assemblyPresets: snapshot.assemblyPresets,
    );
  }
}

class _FakePromptTranslationService implements PromptTranslationService {
  final Future<OnlineTranslationResult> Function(OnlineTranslationRequest)
      handler;

  const _FakePromptTranslationService(this.handler);

  @override
  OnlineAiMode get currentMode => OnlineAiMode.ai;

  @override
  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request, {
    bool preferCache = true,
  }) {
    expect(preferCache, isFalse);
    return handler(request);
  }
}
