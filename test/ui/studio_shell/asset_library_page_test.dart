import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:novel_studio/ui/studio_shell/widgets/asset_library_page.dart';

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService(
    this.snapshot, {
    this.resolvedRefs = const {},
    Set<String> favoriteKeys = const {},
  })  : favoriteKeys = {...favoriteKeys},
        super(workspaceService: WorkspaceService());

  StudioAssetCatalogSnapshot snapshot;
  final Map<String, String> resolvedRefs;
  final Set<String> favoriteKeys;
  final List<bool> includeLegacyCodexRequests = [];
  final List<int> legacyCodexLimitRequests = [];
  final List<String> legacyCodexCategoryKeyRequests = [];
  int resolveImagePathCallCount = 0;
  StudioAssetCatalogCacheLoadResult? cacheLoadResult;
  int loadSnapshotWithCacheCallCount = 0;
  int sourceFingerprintStaleCheckCount = 0;
  int refreshSnapshotCacheCallCount = 0;
  Map<String, String>? lastCheckedSourceFingerprint;
  bool sourceFingerprintIsStale = false;

  @override
  Future<StudioAssetCatalogCacheLoadResult> loadSnapshotWithCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool checkStaleness = true,
    bool persistCacheBeforeReturn = true,
  }) async {
    loadSnapshotWithCacheCallCount += 1;
    final cached = cacheLoadResult;
    if (cached != null) return cached;
    return StudioAssetCatalogCacheLoadResult(
      snapshot: await loadSnapshot(
        includeLegacyCodex: includeLegacyCodex,
        legacyCodexLimit: legacyCodexLimit,
        legacyCodexQuery: legacyCodexQuery,
        legacyCodexCategoryKey: legacyCodexCategoryKey,
      ),
      fromCache: false,
      isStale: false,
    );
  }

  @override
  Future<bool> isSourceFingerprintStale(
    Map<String, String> sourceFingerprint,
  ) async {
    sourceFingerprintStaleCheckCount += 1;
    lastCheckedSourceFingerprint = sourceFingerprint;
    return sourceFingerprintIsStale;
  }

  @override
  Future<StudioAssetCatalogSnapshot> refreshSnapshotCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    refreshSnapshotCacheCallCount += 1;
    return loadSnapshot(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
  }

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    includeLegacyCodexRequests.add(includeLegacyCodex);
    legacyCodexLimitRequests.add(legacyCodexLimit);
    legacyCodexCategoryKeyRequests.add(legacyCodexCategoryKey);
    if (includeLegacyCodex) {
      final requestFilter =
          StudioLegacyCodexCategories.requestFilterFor(legacyCodexCategoryKey);
      final normalizedQuery = legacyCodexQuery.trim().toLowerCase();
      final workspaceInspirations = snapshot.inspirations
          .where(
            (entry) => !StudioAssetCatalogService.isCodexSourceType(
              entry.source.type,
            ),
          )
          .toList(growable: false);
      final queryMatchedCodex = snapshot.inspirations
          .where(
        (entry) => StudioAssetCatalogService.isCodexSourceType(
          entry.source.type,
        ),
      )
          .where((entry) {
        final isAdult =
            StudioAssetCatalogService.isAdultCodexSourceType(entry.source.type);
        return switch (requestFilter.sourceScopeKey) {
          StudioLegacyCodexCategories.sourceAdultKey => isAdult,
          StudioLegacyCodexCategories.sourceRegularKey => !isAdult,
          _ => true,
        };
      }).where((entry) {
        if (normalizedQuery.isEmpty) return true;
        return [entry.name, entry.prompt, entry.tags.join(' ')]
            .join('\n')
            .toLowerCase()
            .contains(normalizedQuery);
      }).toList(growable: false);
      final categoryCounts =
          StudioLegacyCodexCategories.countByCategoryForSource(
        queryMatchedCodex,
        requestFilter.sourceScopeKey,
      );
      final normalizedCategory = requestFilter.categoryKey;
      final codex = normalizedCategory == StudioLegacyCodexCategories.allKey
          ? queryMatchedCodex
          : queryMatchedCodex
              .where(
                (entry) => StudioLegacyCodexCategories.matches(
                  entry,
                  StudioLegacyCodexCategories.requestKey(
                    sourceScopeKey: requestFilter.sourceScopeKey,
                    categoryKey: normalizedCategory,
                  ),
                ),
              )
              .toList(growable: false);
      return StudioAssetCatalogSnapshot(
        summary: snapshot.summary,
        characters: snapshot.characters,
        outfits: snapshot.outfits,
        artistChains: snapshot.artistChains,
        recipes: snapshot.recipes,
        tags: snapshot.tags,
        inspirations: [
          ...workspaceInspirations,
          ...codex.take(legacyCodexLimit),
        ],
        loras: snapshot.loras,
        workflows: snapshot.workflows,
        batchPlans: snapshot.batchPlans,
        assemblyPresets: snapshot.assemblyPresets,
        legacyCodexLoadedCount: codex.take(legacyCodexLimit).length,
        legacyCodexTotalCount: codex.length,
        legacyCodexCategoryCounts: categoryCounts,
        legacyCodexAvailable: snapshot.legacyCodexAvailable ||
            snapshot.inspirations.any(
              (entry) => StudioAssetCatalogService.isCodexSourceType(
                entry.source.type,
              ),
            ),
      );
    }
    return StudioAssetCatalogSnapshot(
      summary: snapshot.summary,
      characters: snapshot.characters,
      outfits: snapshot.outfits,
      artistChains: snapshot.artistChains,
      recipes: snapshot.recipes,
      tags: snapshot.tags,
      inspirations: snapshot.inspirations
          .where(
            (entry) => !StudioAssetCatalogService.isCodexSourceType(
              entry.source.type,
            ),
          )
          .toList(growable: false),
      loras: snapshot.loras,
      workflows: snapshot.workflows,
      batchPlans: snapshot.batchPlans,
      assemblyPresets: snapshot.assemblyPresets,
      legacyCodexAvailable: snapshot.legacyCodexAvailable ||
          snapshot.inspirations.any(
            (entry) => StudioAssetCatalogService.isCodexSourceType(
              entry.source.type,
            ),
          ),
    );
  }

  @override
  String? resolveImagePath(List<String> refs) {
    resolveImagePathCallCount += 1;
    for (final ref in refs) {
      final resolved = resolvedRefs[ref];
      if (resolved != null) return resolved;
    }
    if (refs.contains('refs/artist.png')) return 'refs/artist.png';
    if (refs.contains('refs/outfit.png')) {
      return '${Uri.base.toFilePath()}assets/appicon.png';
    }
    return null;
  }

  @override
  Future<Set<String>> loadAssetFavoriteKeys() async {
    return {...favoriteKeys};
  }

  @override
  Future<void> setAssetFavorite(String key, bool isFavorite) async {
    if (isFavorite) {
      favoriteKeys.add(key);
    } else {
      favoriteKeys.remove(key);
    }
  }
}

class _FakePreviewGenerationService
    extends StudioAssetPreviewGenerationService {
  _FakePreviewGenerationService({
    this.onGenerateCharacterPreview,
    this.onDiscardCharacterPreview,
    this.characterPreviewPath,
  }) : super(
          workspaceService: WorkspaceService(),
          requestImage: (_) async => Uint8List(0),
          saveImage: (_, __) async => 'preview.png',
        );

  final List<String> characterIds = [];
  final List<String> artistChainIds = [];
  final List<String> outfitIds = [];
  final List<StudioAssetPreviewGenerationOptions> characterOptions = [];
  final List<StudioAssetPreviewGenerationOptions> artistChainOptions = [];
  final List<String> discardedCharacterPreviews = [];
  final List<String> discardedArtistChainPreviews = [];
  final List<String> discardedOutfitPreviews = [];
  final void Function(String id)? onGenerateCharacterPreview;
  final void Function(String id, String path)? onDiscardCharacterPreview;
  final String Function(String id)? characterPreviewPath;
  int characterFailuresRemaining = 0;
  int artistChainFailuresRemaining = 0;

  @override
  Future<String> generateCharacterPreview(
    String id, {
    StudioAssetPreviewGenerationOptions options =
        const StudioAssetPreviewGenerationOptions(),
  }) async {
    characterIds.add(id);
    characterOptions.add(options);
    if (characterFailuresRemaining > 0) {
      characterFailuresRemaining -= 1;
      throw StateError('character preview failed');
    }
    onGenerateCharacterPreview?.call(id);
    return characterPreviewPath?.call(id) ?? 'generated-character-$id.png';
  }

  @override
  Future<String> generateArtistChainPreview(
    String id, {
    StudioAssetPreviewGenerationOptions options =
        const StudioAssetPreviewGenerationOptions(),
  }) async {
    artistChainIds.add(id);
    artistChainOptions.add(options);
    if (artistChainFailuresRemaining > 0) {
      artistChainFailuresRemaining -= 1;
      throw StateError('artist preview failed');
    }
    return 'generated-artist-$id.png';
  }

  @override
  Future<String> generateOutfitPreview(
    String characterId,
    String outfitId, {
    StudioAssetPreviewGenerationOptions options =
        const StudioAssetPreviewGenerationOptions(),
  }) async {
    outfitIds.add('$characterId:$outfitId');
    return 'generated-outfit-$characterId-$outfitId.png';
  }

  @override
  Future<void> discardCharacterPreview(String id, String previewPath) async {
    discardedCharacterPreviews.add('$id:$previewPath');
    onDiscardCharacterPreview?.call(id, previewPath);
  }

  @override
  Future<void> discardArtistChainPreview(String id, String previewPath) async {
    discardedArtistChainPreviews.add('$id:$previewPath');
  }

  @override
  Future<void> discardOutfitPreview(
    String characterId,
    String outfitId,
    String previewPath,
  ) async {
    discardedOutfitPreviews.add('$characterId:$outfitId:$previewPath');
  }
}

Future<void> _addPromptTags(
  WidgetTester tester,
  Finder editor,
  String text,
) async {
  await tester.ensureVisible(editor);
  await tester.tap(
    find.descendant(
      of: editor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: editor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
    ),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> _finishPreviewGenerationDialog(
  WidgetTester tester, {
  required bool keep,
}) async {
  await tester.pumpAndSettle();
  expect(find.text('预览生成完成'), findsOneWidget);
  expect(
    find.byKey(
      const ValueKey('asset-preview-generation-preview-image'),
    ),
    findsOneWidget,
  );
  await tester.tap(
    find.byKey(
      ValueKey(
        keep
            ? 'asset-preview-generation-keep'
            : 'asset-preview-generation-discard',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _startPreviewGenerationFromOptions(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('asset-preview-options-dialog')),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const ValueKey('asset-preview-options-start')));
  await tester.pump();
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('silver hair', '银发')
        ..setManual('blue eyes', '蓝眼睛')
        ..setManual('yellow rain coat', '黄色雨衣')
        ..setManual('yellow jacket', '黄色夹克')
        ..setManual('rain skirt', '雨裙')
        ..setManual('rainy street', '雨街'),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  PayloadConfig payload() {
    return PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({'welcome_message_version': '1.0.0'}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );
  }

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
        traits: ViewVariantTexts(
          frontFull: 'silver hair, blue eyes',
          frontUpper: 'blue eyes',
          frontLower: 'fox tail',
        ),
        imageRefs: ['refs/lixia.png'],
        source: SourceRef(
          type: 'external',
          id: 'k-char-1',
          path: 'characters/lixia.json',
        ),
        note: '主角素材',
        outfits: [
          WorkspaceOutfit(
            id: 'outfit-1',
            name: '雨披',
            tags: ViewVariantTexts(
              frontFull: 'yellow rain coat',
              frontUpper: 'yellow jacket',
              frontLower: 'rain skirt',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['yellow jacket'],
              lowerClothingTags: ['rain skirt'],
            ),
            imageRefs: ['refs/outfit.png'],
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
          traits: ViewVariantTexts(
            frontFull: 'silver hair, blue eyes',
            frontUpper: 'blue eyes',
            frontLower: 'fox tail',
          ),
        ),
        outfit: WorkspaceOutfit(
          id: 'outfit-1',
          name: '雨披',
          tags: ViewVariantTexts(
            frontFull: 'yellow rain coat',
            frontUpper: 'yellow jacket',
            frontLower: 'rain skirt',
          ),
          partTags: WorkspaceOutfitPartTags(
            upperClothingTags: ['yellow jacket'],
            lowerClothingTags: ['rain skirt'],
          ),
          imageRefs: ['refs/outfit.png'],
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
        imageRefs: ['refs/artist.png'],
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

  final nonBasicSnapshot = StudioAssetCatalogSnapshot(
    summary: StudioAssetCatalogSummary(
      characterCount: 0,
      artistChainCount: 0,
      recipeCount: 0,
      tagCount: 0,
      inspirationCount: 2,
      loraCount: 1,
      workflowCount: 1,
      batchPlanCount: 1,
      assemblyPresetCount: 1,
      recipeCountsByBlock: {},
      tagCountsByBlock: {},
    ),
    characters: [],
    artistChains: [],
    recipes: [],
    tags: [],
    inspirations: [
      InspirationEntry(
        id: 'night-alley',
        name: 'Night Alley',
        prompt: 'wet asphalt, neon reflections',
        negativePrompt: 'daylight, crowd',
        tags: ['city', 'rain'],
        imageRefs: ['refs/night_alley.png'],
        source: SourceRef(
          type: 'external',
          id: 'insp-1',
          path: 'data/inspirations.json',
        ),
        note: 'late-night urban mood board',
      ),
      InspirationEntry(
        id: 'legacy-codex-regular-0001',
        name: '西幻',
        prompt: 'artist:wlop, dnd, fantasy',
        tags: ['法典', '常规'],
        source: SourceRef(
          type: 'legacy_codex',
          id: 'regular.docx#p156',
        ),
      ),
      for (var index = 2; index <= 180; index++)
        InspirationEntry(
          id: 'legacy-codex-regular-${index.toString().padLeft(4, '0')}',
          name: '法典条目 $index',
          prompt: 'codex prompt $index',
          tags: const ['法典', '常规'],
          source: SourceRef(
            type: 'legacy_codex',
            id: 'regular.docx#p$index',
          ),
        ),
    ],
    loras: [
      LoraEntry(
        id: 'soft-rain',
        name: 'SoftRain',
        baseModel: 'nai-diffusion-4',
        triggerWords: ['soft-rain', 'mist-glow'],
        defaultStrength: 0.65,
        imageRefs: ['refs/soft_rain.png'],
        source: SourceRef(
          type: 'external',
          id: 'lora-1',
          path: 'data/loras.json',
        ),
        note: 'misty rain sheen',
      ),
    ],
    workflows: [
      WorkflowEntry(
        id: 'city-stack',
        name: 'City Stack',
        summary: 'character plus neon city pass',
        imageRefs: ['refs/city_stack.png'],
        payload: {
          'steps': 28,
          'sampler': 'k_euler',
        },
        source: SourceRef(
          type: 'external',
          id: 'workflow-1',
          path: 'data/workflows/city_stack.json',
        ),
        note: 'two-stage city assembly flow',
      ),
    ],
    batchPlans: [
      BatchPlan(
        id: 'night-queue',
        name: 'Night Queue',
        items: [
          {'shot': 'close'},
          {'shot': 'wide'},
        ],
        statusSnapshot: {
          'queued': 2,
        },
        createdAt: DateTime(2026, 5, 22, 12),
        updatedAt: DateTime(2026, 5, 23, 8),
      ),
    ],
    assemblyPresets: [
      AssemblyPresetEntry(
        id: 'city-assembly',
        name: 'City Assembly',
        summary: 'city overlays with reflection polish',
        imageRefs: ['refs/city_assembly.png'],
        payload: {
          'layers': ['fg', 'bg', 'reflection'],
        },
        source: SourceRef(
          type: 'external',
          id: 'assembly-1',
          path: 'data/assembly_presets/city_assembly.json',
        ),
        note: 'final composite preset',
      ),
    ],
  );

  Widget page({
    required PayloadConfig config,
    StudioWorkbenchAssetService? service,
    StudioAssetCatalogService? catalogService,
    StudioAssetPreviewGenerationService? previewGenerationService,
    StudioAssetCatalogSnapshot catalog = snapshot,
    Map<String, String> resolvedRefs = const {},
    ValueChanged<StudioScriptAssetFocus>? onSendToScript,
    Future<List<WorkspaceVibeReference>> Function()? loadVibes,
    Future<List<WorkspaceVibeReference>> Function()? importVibes,
    Future<void> Function(List<ArtistChain>)? saveArtistChains,
    Future<void> Function(List<CharacterEntry>)? saveCharacters,
    Future<void> Function(String, List<Recipe>)? saveRecipes,
    Future<void> Function(String, List<TagEntry>)? saveTags,
    Future<void> Function(List<PromptAssetCategory>)? savePromptAssetCategories,
    VoidCallback? onPromptAssetsChanged,
  }) {
    final resolvedCatalogService = catalogService ??
        _FakeCatalogService(
          catalog,
          resolvedRefs: resolvedRefs,
        );
    return MaterialApp(
      theme: StudioTheme.build(),
      home: AssetLibraryPage(
        catalogService: resolvedCatalogService,
        workbenchAssetService: service ??
            StudioWorkbenchAssetService(
              payloadConfig: config,
            ),
        previewGenerationService: previewGenerationService,
        onSendToScript: onSendToScript,
        loadVibes: loadVibes,
        importVibes: importVibes,
        saveArtistChains: saveArtistChains,
        saveCharacters: saveCharacters,
        saveRecipes: saveRecipes,
        saveTags: saveTags,
        savePromptAssetCategories: savePromptAssetCategories,
        onPromptAssetsChanged: onPromptAssetsChanged,
      ),
    );
  }

  testWidgets('asset library page renders concrete reusable assets',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    expect(find.text('素材库'), findsOneWidget);
    expect(find.text('角色'), findsWidgets);
    expect(find.text('匹配素材 5'), findsOneWidget);
    expect(find.text('璃夏'), findsWidgets);
    expect(find.text('雨披'), findsNothing);
    expect(find.text('水彩柔光'), findsOneWidget);
    expect(find.text('雨夜街道'), findsOneWidget);
    expect(find.text('雨街'), findsOneWidget);
    expect(find.textContaining('silver hair'), findsNothing);
    expect(find.byTooltip('发送到工作台'), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-filter-gallery')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('asset-filter-gallery')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-filter-lora')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-library-waterfall-board')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-character-char-1')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('asset-card-character-char-1')),
        matching: find.byType(StudioStaggeredReveal),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-filter-outfit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-preview-refs/artist.png')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-recipe-style-recipe-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-tag-scene-tag-1')),
      findsOneWidget,
    );
    expect(find.text('引用待检查'), findsNothing);
  });

  testWidgets('cached asset library does not auto-refresh on first display',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(snapshot)
      ..cacheLoadResult = const StudioAssetCatalogCacheLoadResult(
        snapshot: snapshot,
        fromCache: true,
        isStale: false,
        sourceFingerprint: {'library/characters.json': '1:2'},
      );

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('asset-card-character-char-1')),
      findsOneWidget,
    );
    expect(catalogService.loadSnapshotWithCacheCallCount, 1);
    expect(catalogService.sourceFingerprintStaleCheckCount, 0);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(catalogService.loadSnapshotWithCacheCallCount, 1);
    expect(catalogService.sourceFingerprintStaleCheckCount, 0);
    expect(catalogService.lastCheckedSourceFingerprint, isNull);
    expect(catalogService.refreshSnapshotCacheCallCount, 0);
  });

  testWidgets('refresh re-resolves preview refs after a stale empty preview',
      (tester) async {
    final config = payload();
    final tempDir = Directory.systemTemp.createTempSync(
      'asset-restored-preview-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final restoredPreview =
        File('${tempDir.path}${Platform.pathSeparator}restored.png');
    restoredPreview.writeAsBytesSync(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    const restoredRef = 'refs/restored.png';
    const initialCatalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-restored',
          name: 'Restored Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          imageRefs: [restoredRef],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final resolvedRefs = <String, String>{};
    final catalogService = _FakeCatalogService(
      initialCatalog,
      resolvedRefs: resolvedRefs,
    );

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byKey(
        const ValueKey('asset-card-preview-image-character-char-restored'),
      ),
      findsNothing,
    );

    resolvedRefs[restoredRef] = restoredPreview.path;
    await tester.tap(find.byIcon(Icons.refresh).first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('asset-card-preview-image-character-char-restored'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asset waterfall cards compact assets without previews',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    final characterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    expect(tester.getSize(characterCard).width, lessThan(320));
    expect(
      find.byKey(const ValueKey('asset-card-preview-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-tags-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-preview-artist-artist-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-tags-artist-artist-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-copy-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-send-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-send-script-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-summary-character-char-1')),
      findsNothing,
    );
  });

  testWidgets('preview generation buttons call character and artist services',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final previewService = _FakePreviewGenerationService();

    await tester.pumpWidget(
      page(
        config: config,
        previewGenerationService: previewService,
      ),
    );
    await tester.pumpAndSettle();

    final characterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    await tester.ensureVisible(characterCard);
    await tester.tap(characterCard);
    await tester.pumpAndSettle();
    final characterButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-character-char-1'),
    );
    await tester.ensureVisible(characterButton);
    await tester.tap(characterButton);
    await _startPreviewGenerationFromOptions(tester);
    expect(find.text('正在生成预览'), findsOneWidget);
    await _finishPreviewGenerationDialog(tester, keep: true);
    await tester.tap(find.byKey(const ValueKey('asset-detail-dialog-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();
    final artistButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-artistChain-artist-1'),
    );
    await tester.ensureVisible(artistButton);
    await tester.tap(artistButton);
    await _startPreviewGenerationFromOptions(tester);
    expect(find.text('正在生成预览'), findsOneWidget);
    await _finishPreviewGenerationDialog(tester, keep: true);

    expect(previewService.characterIds, ['char-1']);
    expect(previewService.artistChainIds, ['artist-1']);
    expect(
      previewService.artistChainOptions.single.model,
      'nai-diffusion-5-full',
    );
    expect(find.text('新增预览'), findsWidgets);
    expect(find.byTooltip('Generate preview'), findsNothing);
  });

  testWidgets('character preview options pass artist and custom prompt mode',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final previewService = _FakePreviewGenerationService();

    await tester.pumpWidget(
      page(
        config: config,
        previewGenerationService: previewService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    final characterButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-character-char-1'),
    );
    await tester.ensureVisible(characterButton);
    await tester.tap(characterButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-preview-options-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('asset-preview-options-artist-chain')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(snapshot.artistChains.single.name).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('asset-preview-options-mode-replace')),
    );
    final customPromptEditor =
        find.byKey(const ValueKey('asset-preview-options-custom-prompt-tags'));
    expect(
      find.descendant(
        of: customPromptEditor,
        matching: find.byType(PromptTagEditor),
      ),
      findsOneWidget,
    );
    await _addPromptTags(tester, customPromptEditor, 'only my prompt');
    await tester.tap(
      find.byKey(const ValueKey('asset-preview-options-size')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1472 x 704').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('asset-preview-options-start')),
    );
    await tester.pump();
    await _finishPreviewGenerationDialog(tester, keep: true);

    expect(previewService.characterIds, ['char-1']);
    expect(previewService.characterOptions.single.artistChainId, 'artist-1');
    expect(
        previewService.characterOptions.single.customPrompt, 'only my prompt');
    expect(
      previewService.characterOptions.single.customPromptMode,
      StudioPreviewCustomPromptMode.replace,
    );
    expect(previewService.characterOptions.single.size?.width, 1472);
    expect(previewService.characterOptions.single.size?.height, 704);
  });

  testWidgets('artist preview options pass custom append prompt',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final previewService = _FakePreviewGenerationService();

    await tester.pumpWidget(
      page(
        config: config,
        previewGenerationService: previewService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();
    final artistButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-artistChain-artist-1'),
    );
    await tester.ensureVisible(artistButton);
    await tester.tap(artistButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-preview-options-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-preview-options-model')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('asset-preview-options-model')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NAI V4.5 Full').last);
    await tester.pumpAndSettle();
    final customPromptEditor =
        find.byKey(const ValueKey('asset-preview-options-custom-prompt-tags'));
    expect(
      find.descendant(
        of: customPromptEditor,
        matching: find.byType(PromptTagEditor),
      ),
      findsOneWidget,
    );
    await _addPromptTags(
      tester,
      customPromptEditor,
      'misty park',
    );
    await tester.tap(
      find.byKey(const ValueKey('asset-preview-options-start')),
    );
    await tester.pump();
    await _finishPreviewGenerationDialog(tester, keep: true);

    expect(previewService.artistChainIds, ['artist-1']);
    expect(
      previewService.artistChainOptions.single.model,
      'nai-diffusion-4-5-full',
    );
    expect(previewService.artistChainOptions.single.customPrompt, 'misty park');
    expect(
      previewService.artistChainOptions.single.customPromptMode,
      StudioPreviewCustomPromptMode.append,
    );
  });

  testWidgets('preview generation buttons are only shown for supported assets',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(
      page(
        config: config,
        catalog: nonBasicSnapshot,
        previewGenerationService: _FakePreviewGenerationService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-generate-preview-lora-soft-rain')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-generate-preview-workflow-city-stack')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('asset-generate-preview-assemblyPreset-city-assembly'),
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      page(
        config: config,
        previewGenerationService: _FakePreviewGenerationService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-generate-preview-recipe-recipe-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-generate-preview-tag-tag-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-generate-preview-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('asset-generate-preview-artistChain-artist-1'),
      ),
      findsNothing,
    );

    final characterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    await tester.ensureVisible(characterCard);
    await tester.tap(characterCard);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
          const ValueKey('asset-detail-generate-preview-character-char-1')),
      findsOneWidget,
    );
  });

  testWidgets('preview generation error shows snackbar and allows retry',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final previewService = _FakePreviewGenerationService()
      ..characterFailuresRemaining = 1;

    await tester.pumpWidget(
      page(
        config: config,
        previewGenerationService: previewService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    final characterButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-character-char-1'),
    );
    await tester.ensureVisible(characterButton);
    await tester.tap(characterButton);
    await _startPreviewGenerationFromOptions(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-preview-generation-close')),
      findsOneWidget,
    );
    await tester
        .tap(find.byKey(const ValueKey('asset-preview-generation-close')));
    await tester.pumpAndSettle();

    await tester.tap(characterButton);
    await _startPreviewGenerationFromOptions(tester);
    await _finishPreviewGenerationDialog(tester, keep: true);

    expect(previewService.characterIds, ['char-1', 'char-1']);
  });

  testWidgets('preview generation refreshes the selected detail asset',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final tempDir =
        Directory.systemTemp.createTempSync('asset-generated-preview-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final generatedPreview =
        File('${tempDir.path}${Platform.pathSeparator}generated.png');
    generatedPreview.writeAsBytesSync(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    final resolvedRefs = <String, String>{};
    final refreshCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-refresh',
          name: 'Refresh Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final catalogService = _FakeCatalogService(
      refreshCatalog,
      resolvedRefs: resolvedRefs,
    );
    final previewService = _FakePreviewGenerationService(
      onGenerateCharacterPreview: (id) {
        resolvedRefs['refs/generated-character.png'] = generatedPreview.path;
        final characters = [
          for (final character in catalogService.snapshot.characters)
            character.id == id
                ? character.copyWith(
                    imageRefs: [
                      ...character.imageRefs,
                      'refs/generated-character.png',
                    ],
                  )
                : character,
        ];
        catalogService.snapshot = StudioAssetCatalogSnapshot(
          summary: catalogService.snapshot.summary,
          characters: characters,
          outfits: catalogService.snapshot.outfits,
          artistChains: catalogService.snapshot.artistChains,
          recipes: catalogService.snapshot.recipes,
          tags: catalogService.snapshot.tags,
          inspirations: catalogService.snapshot.inspirations,
          loras: catalogService.snapshot.loras,
          workflows: catalogService.snapshot.workflows,
          batchPlans: catalogService.snapshot.batchPlans,
          assemblyPresets: catalogService.snapshot.assemblyPresets,
          legacyCodexLoadedCount:
              catalogService.snapshot.legacyCodexLoadedCount,
          legacyCodexTotalCount: catalogService.snapshot.legacyCodexTotalCount,
          legacyCodexCategoryCounts:
              catalogService.snapshot.legacyCodexCategoryCounts,
          legacyCodexAvailable: catalogService.snapshot.legacyCodexAvailable,
        );
      },
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalogService: catalogService,
        previewGenerationService: previewService,
      ),
    );
    await tester.pumpAndSettle();

    final refreshCard =
        find.byKey(const ValueKey('asset-card-character-char-refresh'));
    await tester.tapAt(
      tester.getBottomLeft(refreshCard) + const Offset(24, -24),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('asset-detail-preview-image-character-char-refresh'),
      ),
      findsNothing,
    );

    final characterButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-character-char-refresh'),
    );
    await tester.ensureVisible(characterButton);
    await tester.tap(characterButton);
    await _startPreviewGenerationFromOptions(tester);
    await _finishPreviewGenerationDialog(tester, keep: true);

    expect(previewService.characterIds, ['char-refresh']);
    expect(
      find.byKey(
        const ValueKey('asset-detail-preview-image-character-char-refresh'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('discarding a generated preview removes it before refresh',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final tempDir =
        Directory.systemTemp.createTempSync('asset-discard-preview-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final generatedPath =
        '${tempDir.path}${Platform.pathSeparator}generated-discard.png';
    File(generatedPath).writeAsBytesSync(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    final resolvedRefs = <String, String>{generatedPath: generatedPath};
    final refreshCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-discard',
          name: 'Discard Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );
    final catalogService = _FakeCatalogService(
      refreshCatalog,
      resolvedRefs: resolvedRefs,
    );
    final previewService = _FakePreviewGenerationService(
      characterPreviewPath: (_) => generatedPath,
      onGenerateCharacterPreview: (id) {
        catalogService.snapshot = StudioAssetCatalogSnapshot(
          summary: catalogService.snapshot.summary,
          characters: [
            for (final character in catalogService.snapshot.characters)
              character.id == id
                  ? character.copyWith(imageRefs: [generatedPath])
                  : character,
          ],
          outfits: catalogService.snapshot.outfits,
          artistChains: catalogService.snapshot.artistChains,
          recipes: catalogService.snapshot.recipes,
          tags: catalogService.snapshot.tags,
        );
      },
      onDiscardCharacterPreview: (id, path) {
        catalogService.snapshot = StudioAssetCatalogSnapshot(
          summary: catalogService.snapshot.summary,
          characters: [
            for (final character in catalogService.snapshot.characters)
              character.id == id
                  ? character.copyWith(
                      imageRefs: [
                        for (final ref in character.imageRefs)
                          if (ref != path) ref,
                      ],
                    )
                  : character,
          ],
          outfits: catalogService.snapshot.outfits,
          artistChains: catalogService.snapshot.artistChains,
          recipes: catalogService.snapshot.recipes,
          tags: catalogService.snapshot.tags,
        );
      },
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalogService: catalogService,
        previewGenerationService: previewService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-discard')),
    );
    await tester.pumpAndSettle();
    final characterButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-character-char-discard'),
    );
    await tester.ensureVisible(characterButton);
    await tester.tap(characterButton);
    await _startPreviewGenerationFromOptions(tester);
    await _finishPreviewGenerationDialog(tester, keep: false);

    expect(previewService.characterIds, ['char-discard']);
    expect(
      previewService.discardedCharacterPreviews,
      ['char-discard:$generatedPath'],
    );
    expect(
      find.byKey(
        const ValueKey('asset-detail-preview-image-character-char-discard'),
      ),
      findsNothing,
    );
  });

  testWidgets('asset card copy writes the prompt to clipboard', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    final characterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    await tester.ensureVisible(characterCard);
    await tester.tap(characterCard);
    await tester.pumpAndSettle();
    final copyButton = find.byKey(const ValueKey('asset-detail-copy'));
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pump();

    expect(clipboardText, 'silver hair, blue eyes');
    expect(find.text('已复制提示词'), findsOneWidget);
  });

  testWidgets('detail header keeps actions clear of close and compact favorite',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();

    final favorite = find.byKey(const ValueKey('asset-detail-favorite'));
    final copy = find.byKey(const ValueKey('asset-detail-copy'));
    final close = find.byKey(const ValueKey('asset-detail-dialog-close'));
    expect(favorite, findsOneWidget);
    expect(copy, findsOneWidget);
    expect(close, findsOneWidget);
    expect(tester.getSize(favorite).width, lessThanOrEqualTo(36));
    expect(tester.getRect(copy).right, lessThan(tester.getRect(close).left));
  });

  testWidgets('asset library favorites pin cards and can be cleared',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    const artistCatalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 2,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [
        ArtistChain(id: 'artist-1', name: 'First Painter', prompt: 'ink wash'),
        ArtistChain(
            id: 'artist-2', name: 'Second Painter', prompt: 'rain glow'),
      ],
      recipes: [],
      tags: [],
    );
    final catalogService = _FakeCatalogService(artistCatalog);

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistCatalog,
        catalogService: catalogService,
      ),
    );
    await tester.pumpAndSettle();

    final firstCard = find.byKey(const ValueKey('asset-card-artist-artist-1'));
    final secondCard = find.byKey(const ValueKey('asset-card-artist-artist-2'));
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getTopLeft(secondCard).dy),
    );

    await tester.ensureVisible(secondCard);
    await tester.tap(secondCard);
    await tester.pumpAndSettle();
    final secondFavorite = find.byKey(const ValueKey('asset-detail-favorite'));
    await tester.ensureVisible(secondFavorite);
    await tester.tap(secondFavorite);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-dialog-close')));
    await tester.pumpAndSettle();
    expect(catalogService.favoriteKeys, contains('artist:artist-2'));
    expect(
      tester.getTopLeft(secondCard).dy,
      lessThan(tester.getTopLeft(firstCard).dy),
    );

    await tester.ensureVisible(secondCard);
    await tester.tap(secondCard);
    await tester.pumpAndSettle();
    final favoriteAgain = find.byKey(const ValueKey('asset-detail-favorite'));
    await tester.ensureVisible(favoriteAgain);
    await tester.tap(favoriteAgain);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-dialog-close')));
    await tester.pumpAndSettle();
    expect(catalogService.favoriteKeys, isNot(contains('artist:artist-2')));
  });

  testWidgets('character detail does not expose synthetic default outfit',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-default',
          name: 'Heroine',
          traits: ViewVariantTexts(
            frontFull: 'heroine identity',
            frontUpper: 'silver hair, white blouse',
            frontLower: 'fox tail, pleated skirt',
          ),
          imageRefs: ['refs/heroine.png'],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(config: config, service: service, catalog: catalog),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-default')),
    );
    await tester.pumpAndSettle();

    final defaultOutfitCard = find.byKey(
      const ValueKey(
        'asset-character-outfit-card-char-default-default-outfit',
      ),
    );
    expect(defaultOutfitCard, findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('asset-detail-send')),
    );
    await tester.pump();

    expect(service.fragments.single.kind, StudioWorkbenchAssetKind.character);
    expect(service.fragments.single.sourceId, 'char-default');
    expect(service.fragments.single.name, 'Heroine');
    expect(config.overridePrompt, 'heroine identity');
  });

  testWidgets('multi-outfit character send opens an outfit chooser',
      (tester) async {
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 2,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [
        CharacterEntry(
          id: 'char-multi',
          name: '多衣角色',
          traits: ViewVariantTexts(frontFull: 'green eyes'),
          outfits: [
            WorkspaceOutfit(
              id: 'uniform',
              name: '制服',
              tags: ViewVariantTexts(
                frontFull: 'navy uniform',
                frontUpper: 'navy jacket',
                frontLower: 'pleated skirt',
              ),
            ),
            WorkspaceOutfit(
              id: 'casual',
              name: '便服',
              tags: ViewVariantTexts(
                frontFull: 'white hoodie, denim shorts',
                frontUpper: 'white hoodie',
                frontLower: 'denim shorts',
              ),
            ),
          ],
        ),
      ],
      artistChains: const [],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(config: config, service: service, catalog: catalog),
    );
    await tester.pumpAndSettle();

    final multiCharacterCard =
        find.byKey(const ValueKey('asset-card-character-char-multi'));
    await tester.ensureVisible(multiCharacterCard);
    await tester.tap(multiCharacterCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-send')));
    await tester.pumpAndSettle();

    expect(find.text('选择服装'), findsOneWidget);
    expect(service.fragments, isEmpty);

    await tester.tap(
      find.byKey(
        const ValueKey('asset-card-outfit-choice-char-multi-casual'),
      ),
    );
    await tester.pump();

    expect(service.fragments.single.name, '多衣角色 / 便服');
    expect(config.overridePrompt, 'white hoodie, denim shorts');
  });

  testWidgets('multi-image previews open a wheel carousel', (tester) async {
    final config = payload();
    final tempDir = Directory.systemTemp.createTempSync('asset-preview-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final first = File('${tempDir.path}${Platform.pathSeparator}first.png');
    final second = File('${tempDir.path}${Platform.pathSeparator}second.png');
    File('${Uri.base.toFilePath()}assets/appicon.png').copySync(first.path);
    File('${Uri.base.toFilePath()}assets/appicon.png').copySync(second.path);
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'multi-preview',
          name: '多图画风',
          prompt: 'soft watercolor',
          imageRefs: ['multi/first.png', 'multi/second.png'],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        resolvedRefs: {
          'multi/first.png': first.path,
          'multi/second.png': second.path,
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('asset-card-preview-image-artist-multi-preview'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-card-preview-count-artist-multi-preview'),
      ),
      findsOneWidget,
    );
    expect(find.text('2 张'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('asset-card-artist-multi-preview')));
    await tester.pumpAndSettle();
    final preview =
        find.byKey(const ValueKey('asset-detail-preview-artist-multi-preview'));
    await tester.ensureVisible(preview);
    expect(
      find.ancestor(
        of: preview,
        matching: find.byType(StudioInteractiveSurface),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-detail-preview-count-artist-multi-preview'),
      ),
      findsOneWidget,
    );
    final detailImage = find.byKey(
      const ValueKey('asset-detail-preview-image-artist-multi-preview'),
    );
    _expectResizedFileImage(tester.widget<Image>(detailImage), first.path);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(preview),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    _expectResizedFileImage(tester.widget<Image>(detailImage), second.path);

    await tester.tap(preview);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('asset-preview-carousel-artist-multi-preview'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-preview-carousel-image-artist-multi-preview-0',
        ),
      ),
      findsOneWidget,
    );
    final revealButton = find.byKey(
      const ValueKey('asset-preview-carousel-reveal-file'),
    );
    expect(revealButton, findsOneWidget);
    expect(tester.widget<IconButton>(revealButton).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('asset-preview-carousel-dot-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('asset-preview-carousel-dot-1')),
        findsOneWidget);

    final counter =
        find.byKey(const ValueKey('asset-preview-carousel-counter'));
    final before = tester.widget<Text>(counter).data;
    final artistCarousel = find.byKey(
      const ValueKey('asset-preview-carousel-artist-multi-preview'),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(artistCarousel),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(counter).data, isNot(before));
    expect(
      find.byKey(
        const ValueKey(
          'asset-preview-carousel-image-artist-multi-preview-1',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asset card previews follow the resolved image aspect ratio',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final previewFile = File(
      '${Directory.current.path}${Platform.pathSeparator}'
      'assets${Platform.pathSeparator}appicon.png',
    );
    final previewImage = img.decodeImage(previewFile.readAsBytesSync())!;
    final expectedRatio = previewImage.width / previewImage.height;
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'tall-preview',
          name: '竖图预览',
          prompt: 'portrait card',
          imageRefs: ['preview/tall.png'],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        resolvedRefs: {'preview/tall.png': previewFile.path},
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final preview = find.byKey(
      const ValueKey('asset-card-preview-artist-tall-preview'),
    );
    final previewSize = tester.getSize(preview);

    expect(
        previewSize.width / previewSize.height, closeTo(expectedRatio, 0.03));
    expect(
      find.byKey(
        const ValueKey('asset-card-preview-image-artist-tall-preview'),
      ),
      findsOneWidget,
    );
    _expectResizedFileImage(
      tester.widget<Image>(
        find.byKey(
          const ValueKey('asset-card-preview-image-artist-tall-preview'),
        ),
      ),
      previewFile.path,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('asset card can request navigation to the script asset drawer',
      (tester) async {
    final config = payload();
    StudioScriptAssetFocus? focus;

    await tester.pumpWidget(
      page(
        config: config,
        onSendToScript: (value) => focus = value,
      ),
    );
    await tester.pumpAndSettle();

    final scriptCharacterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    await tester.ensureVisible(scriptCharacterCard);
    await tester.tap(scriptCharacterCard);
    await tester.pumpAndSettle();
    final sendScriptButton =
        find.byKey(const ValueKey('asset-detail-send-script'));
    await tester.ensureVisible(sendScriptButton);
    await tester.tap(sendScriptButton);
    await tester.pump();

    expect(focus?.kind, StudioScriptAssetFocusKind.character);
    expect(focus?.characterId, 'char-1');
    expect(find.text('已发送到剧本素材抽屉'), findsOneWidget);
  });

  testWidgets('asset library top filters render full exhibition cards',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    final gallery = find.byKey(const ValueKey('asset-filter-gallery'));
    final allFilter = find.byKey(const ValueKey('asset-filter-all'));
    final characterFilter =
        find.byKey(const ValueKey('asset-filter-character'));
    final artistFilter =
        find.byKey(const ValueKey('asset-filter-artist-chain'));
    final outfitFilter = find.byKey(const ValueKey('asset-filter-outfit'));
    final secondaryRow =
        find.byKey(const ValueKey('asset-filter-secondary-row'));

    expect(gallery, findsOneWidget);
    expect(
        find.byKey(const ValueKey('asset-filter-primary-row')), findsNothing);
    expect(allFilter, findsOneWidget);
    expect(characterFilter, findsOneWidget);
    expect(artistFilter, findsOneWidget);
    expect(tester.getSize(allFilter).height, greaterThanOrEqualTo(72));
    expect(outfitFilter, findsOneWidget);
    expect(
      find.descendant(of: gallery, matching: outfitFilter),
      findsNothing,
    );
    expect(
      find.descendant(of: secondaryRow, matching: outfitFilter),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('asset-filter-recipe')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-filter-tag')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-library-add-custom-category')),
      findsNothing,
    );
  });

  testWidgets('codex filter is promoted to the primary gallery cards',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final catalog = StudioAssetCatalogSnapshot(
      summary: snapshot.summary,
      characters: snapshot.characters,
      outfits: snapshot.outfits,
      artistChains: snapshot.artistChains,
      recipes: snapshot.recipes,
      tags: snapshot.tags,
      inspirations: [
        ...snapshot.inspirations,
        const InspirationEntry(
          id: 'legacy-codex-layout',
          name: 'Layout Codex',
          prompt: 'artist:wlop, dnd, fantasy',
          source: SourceRef(type: 'legacy_codex'),
        ),
      ],
      legacyCodexAvailable: true,
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    final gallery = find.byKey(const ValueKey('asset-filter-gallery'));
    final secondaryRow =
        find.byKey(const ValueKey('asset-filter-secondary-row'));
    final allFilter = find.byKey(const ValueKey('asset-filter-all'));
    final characterFilter =
        find.byKey(const ValueKey('asset-filter-character'));
    final artistFilter =
        find.byKey(const ValueKey('asset-filter-artist-chain'));
    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    final outfitFilter = find.byKey(const ValueKey('asset-filter-outfit'));

    expect(gallery, findsOneWidget);
    expect(
      find.descendant(of: gallery, matching: allFilter),
      findsOneWidget,
    );
    expect(
      find.descendant(of: gallery, matching: characterFilter),
      findsOneWidget,
    );
    expect(
      find.descendant(of: gallery, matching: artistFilter),
      findsOneWidget,
    );
    expect(codexFilter, findsOneWidget);
    expect(
      find.descendant(of: gallery, matching: codexFilter),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(codexFilter).dx,
      greaterThan(tester.getTopLeft(artistFilter).dx),
    );
    expect(
      find.descendant(of: secondaryRow, matching: codexFilter),
      findsNothing,
    );
    expect(
      find.descendant(of: gallery, matching: outfitFilter),
      findsNothing,
    );
    expect(
      find.descendant(of: secondaryRow, matching: outfitFilter),
      findsOneWidget,
    );
  });

  testWidgets('codex source tabs render source-specific categories',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(
      StudioAssetCatalogSnapshot(
        summary: const StudioAssetCatalogSummary(
          characterCount: 0,
          artistChainCount: 0,
          recipeCount: 0,
          tagCount: 0,
          inspirationCount: 2,
          recipeCountsByBlock: {},
          tagCountsByBlock: {},
        ),
        characters: const [],
        artistChains: const [],
        recipes: const [],
        tags: const [],
        inspirations: const [
          InspirationEntry(
            id: 'regular-codex-style',
            name: 'Regular Style',
            prompt: 'artist:wlop, painterly, official art',
            source: SourceRef(type: 'legacy_codex'),
          ),
          InspirationEntry(
            id: 'adult-codex-view',
            name: 'Adult View',
            prompt: 'pov, from above, on bed, blush',
            source: SourceRef(type: 'novalai_codex_adult_docx'),
          ),
        ],
        legacyCodexAvailable: true,
      ),
    );

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    final regularCategory =
        find.byKey(const ValueKey('asset-codex-category-artist-style'));
    final adultCategory =
        find.byKey(const ValueKey('asset-codex-category-adult-interaction'));
    expect(regularCategory, findsOneWidget);
    expect(adultCategory, findsNothing);

    await tester.tap(regularCategory);
    await tester.pumpAndSettle();
    expect(
      catalogService.legacyCodexCategoryKeyRequests.last,
      StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceRegularKey,
        categoryKey: StudioLegacyCodexCategories.artistStyle.key,
      ),
    );

    final adultSource = find.byKey(const ValueKey('asset-codex-source-adult'));
    await tester.ensureVisible(adultSource);
    await tester.tap(adultSource);
    await tester.pumpAndSettle();

    expect(regularCategory, findsNothing);
    expect(adultCategory, findsOneWidget);
    expect(
      catalogService.legacyCodexCategoryKeyRequests.last,
      StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceAdultKey,
        categoryKey: StudioLegacyCodexCategories.allKey,
      ),
    );

    final regularSource =
        find.byKey(const ValueKey('asset-codex-source-regular'));
    await tester.tap(regularSource);
    await tester.pumpAndSettle();

    expect(regularCategory, findsOneWidget);
    expect(adultCategory, findsNothing);
    expect(
      catalogService.legacyCodexCategoryKeyRequests.last,
      StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceRegularKey,
        categoryKey: StudioLegacyCodexCategories.allKey,
      ),
    );
  });

  testWidgets('codex category chips use source category paths', (tester) async {
    final config = payload();
    final regularSourceCategoryKey =
        StudioLegacyCodexCategories.sourceCategoryKeyForPath(
      const ['各种风格'],
    )!;
    final adultSourceCategoryKey =
        StudioLegacyCodexCategories.sourceCategoryKeyForPath(
      const ['基础涩涩', '各种体位', '正身位'],
    )!;
    final catalogService = _FakeCatalogService(
      StudioAssetCatalogSnapshot(
        summary: const StudioAssetCatalogSummary(
          characterCount: 0,
          artistChainCount: 0,
          recipeCount: 0,
          tagCount: 0,
          inspirationCount: 2,
          recipeCountsByBlock: {},
          tagCountsByBlock: {},
        ),
        characters: const [],
        artistChains: const [],
        recipes: const [],
        tags: const [],
        inspirations: const [
          InspirationEntry(
            id: 'regular-codex-style',
            name: 'Regular Style',
            prompt: 'artist:wlop, painterly',
            sourceCategoryPath: ['各种风格'],
            source: SourceRef(type: 'legacy_codex'),
          ),
          InspirationEntry(
            id: 'adult-codex-position',
            name: 'Adult Position',
            prompt: 'front view, leg grab',
            sourceCategoryPath: ['基础涩涩', '各种体位', '正身位'],
            source: SourceRef(type: 'novalai_codex_adult_docx'),
          ),
        ],
        legacyCodexAvailable: true,
      ),
    );

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    final regularCategory = find.byKey(
      ValueKey('asset-codex-category-$regularSourceCategoryKey'),
    );
    final adultCategory = find.byKey(
      ValueKey('asset-codex-category-$adultSourceCategoryKey'),
    );
    expect(regularCategory, findsOneWidget);
    expect(find.text('各种风格'), findsOneWidget);
    expect(adultCategory, findsNothing);

    await tester.tap(regularCategory);
    await tester.pumpAndSettle();
    expect(
      catalogService.legacyCodexCategoryKeyRequests.last,
      StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceRegularKey,
        categoryKey: regularSourceCategoryKey,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('asset-codex-source-adult')));
    await tester.pumpAndSettle();

    expect(regularCategory, findsNothing);
    expect(adultCategory, findsOneWidget);
    expect(find.text('正身位'), findsOneWidget);
  });

  testWidgets('codex detail shows source variants under the parent card',
      (tester) async {
    final config = payload();
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        inspirationCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
      inspirations: [
        InspirationEntry(
          id: 'legacy-codex-parent',
          name: '脸部视角抬腿正身位',
          prompt: 'front view, leg grab',
          sourceCategoryPath: ['基础涩涩', '各种体位', '正身位'],
          variants: [
            InspirationEntry(
              id: 'legacy-codex-variant',
              name: '另一版本',
              prompt: 'alternate front view, leg grab',
              sourceParentId: 'legacy-codex-parent',
              sourceParentName: '脸部视角抬腿正身位',
              sourceVariantLabel: '另一版本',
              source: SourceRef(type: 'legacy_codex'),
            ),
          ],
          source: SourceRef(type: 'legacy_codex'),
        ),
      ],
      legacyCodexAvailable: true,
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    final codexCard = find
        .byKey(const ValueKey('asset-card-inspiration-legacy-codex-parent'));
    await tester.ensureVisible(codexCard);
    await tester.tap(codexCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-codex-variants')),
      findsOneWidget,
    );
    expect(find.text('另一版本'), findsWidgets);
    expect(
      find.byKey(
        const ValueKey('asset-detail-codex-variant-legacy-codex-variant'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asset library page can send a selected asset to workbench',
      (tester) async {
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);

    await tester.pumpWidget(page(config: config, service: service));
    await tester.pumpAndSettle();

    final sendCharacterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    await tester.ensureVisible(sendCharacterCard);
    await tester.tap(sendCharacterCard);
    await tester.pumpAndSettle();
    final sendButton = find.byKey(const ValueKey('asset-detail-send'));
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();

    expect(config.useOverridePrompt, isTrue);
    expect(config.overridePrompt, 'silver hair, blue eyes');
    expect(service.fragments.single.typeLabel, '角色');
    expect(service.fragments.single.name, '璃夏');
    expect(find.text('已发送到工作台'), findsOneWidget);
  });

  testWidgets('asset library page filters assets by search and type',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('asset-library-search')),
      '雨披',
    );
    await tester.pumpAndSettle();

    expect(find.text('匹配素材 2'), findsOneWidget);
    expect(find.text('璃夏'), findsWidgets);
    expect(find.text('水彩柔光'), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-card-character-char-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('asset-library-search')),
      '',
    );
    expect(find.byKey(const ValueKey('asset-filter-tag')), findsOneWidget);

    final artistFilter =
        find.byKey(const ValueKey('asset-filter-artist-chain'));
    await tester.ensureVisible(artistFilter);
    await tester.tap(artistFilter);
    await tester.pumpAndSettle();

    expect(find.text('雨街'), findsNothing);
    expect(find.text('雨披'), findsNothing);
    expect(find.text('水彩柔光'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-card-tag-scene-tag-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsOneWidget,
    );
  });

  testWidgets('copied manual outfits appear as standalone outfit assets',
      (tester) async {
    final config = payload();
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 3,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'legacy-character-sheet-r14',
          name: '佩佩',
          traits: ViewVariantTexts(frontFull: 'pepe_(arknights)'),
          source: SourceRef(type: 'manual'),
          outfits: [
            WorkspaceOutfit(
              id: 'default-outfit',
              name: '默认服装',
              tags: ViewVariantTexts(frontFull: 'hood, black jacket'),
            ),
            WorkspaceOutfit(
              id: 'legacy-character-sheet-r14-outfit-4',
              name: '星移',
              tags: ViewVariantTexts(frontFull: 'white dress'),
            ),
            WorkspaceOutfit(
              id: 'default-outfit-copy',
              name: '默认服装 Copy',
              tags: ViewVariantTexts(
                frontFull:
                    '6:: cat_ears ::, -6:: hood ::, black_jacket, shorts',
                frontUpper: 'black_jacket',
                frontLower: 'shorts',
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    final outfitFilter = find.byKey(const ValueKey('asset-filter-outfit'));
    await tester.ensureVisible(outfitFilter);
    await tester.tap(outfitFilter);
    await tester.pumpAndSettle();

    final copiedOutfitCard = find.byKey(
      const ValueKey(
        'asset-card-outfit-legacy-character-sheet-r14-default-outfit-copy',
      ),
    );
    expect(copiedOutfitCard, findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('asset-library-search')),
      'default-outfit-copy',
    );
    await tester.pumpAndSettle();

    expect(copiedOutfitCard, findsOneWidget);

    await tester.tap(copiedOutfitCard);
    await tester.pumpAndSettle();

    expect(find.text('black_jacket'), findsWidgets);
  });

  testWidgets('asset library filter switches reuse resolved display items',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(snapshot);

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    final initialResolveCount = catalogService.resolveImagePathCallCount;
    expect(initialResolveCount, greaterThan(0));

    final characterFilter =
        find.byKey(const ValueKey('asset-filter-character'));
    await tester.ensureVisible(characterFilter);
    await tester.tap(characterFilter);
    await tester.pumpAndSettle();
    expect(catalogService.resolveImagePathCallCount, initialResolveCount);

    final artistFilter =
        find.byKey(const ValueKey('asset-filter-artist-chain'));
    await tester.ensureVisible(artistFilter);
    await tester.tap(artistFilter);
    await tester.pumpAndSettle();
    expect(catalogService.resolveImagePathCallCount, initialResolveCount);

    final allFilter = find.byKey(const ValueKey('asset-filter-all'));
    await tester.ensureVisible(allFilter);
    await tester.tap(allFilter);
    await tester.pumpAndSettle();
    expect(catalogService.resolveImagePathCallCount, initialResolveCount);
  });

  testWidgets('large tag catalogs resolve preview references lazily',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const tagCount = 600;
    final config = payload();
    final largeTagCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: tagCount,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'scene': tagCount},
      ),
      characters: const [],
      artistChains: const [],
      recipes: const [],
      tags: [
        for (var index = 0; index < tagCount; index++)
          TagEntry(
            id: 'tag-$index',
            tag: 'tag $index',
            block: 'scene',
            imageRefs: ['refs/tag-$index.png'],
          ),
      ],
    );
    final catalogService = _FakeCatalogService(largeTagCatalog);

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-filter-tag')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-card-tag-scene-tag-0')),
      findsOneWidget,
    );
    expect(catalogService.resolveImagePathCallCount, lessThan(tagCount ~/ 2));
  });

  testWidgets(
      'asset library opens a detail dialog for the selected waterfall card',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-library-detail-content')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-dialog-character-char-1')),
      findsOneWidget,
    );
    expect(find.text('璃夏'), findsWidgets);
    expect(find.textContaining('external'), findsNothing);
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-grouped')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-layered')),
      findsNothing,
    );
    expect(find.text('characters/lixia.json'), findsNothing);
    expect(find.text('主角素材'), findsNothing);
    expect(find.text('refs/lixia.png'), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-detail-info-strip-character-char-1')),
      findsOneWidget,
    );
    expect(find.text('char-1'), findsWidgets);
    expect(find.text('1 套'), findsOneWidget);
    expect(find.text('1 张'), findsWidgets);
    expect(
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-character-char-1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-character-outfit-icon-char-1-outfit-1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-character-outfit-selector-char-1-outfit-1'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-character-preview-dot-char-1-0')),
      findsOneWidget,
    );
    expect(find.text('雨披'), findsWidgets);
    expect(find.text('蓝眼睛'), findsWidgets);
    expect(find.text('fox tail'), findsNothing);
    expect(find.text('黄色雨衣'), findsNothing);
    expect(find.text('黄色夹克'), findsWidgets);
    expect(find.text('雨裙'), findsWidgets);
    expect(
      find.byKey(
        const ValueKey(
            'asset-detail-prompt-editor-character-char-1-upper-body'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
            'asset-detail-prompt-editor-character-char-1-lower-body'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-1-outfit-0-upper-clothing',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-1-outfit-0-lower-clothing',
        ),
      ),
      findsOneWidget,
    );
    final outfitPreview = find.byKey(
      const ValueKey('asset-character-outfit-preview-image-char-1-outfit-1'),
    );
    expect(outfitPreview, findsOneWidget);
    final previewSize = tester.getSize(outfitPreview);
    expect(previewSize.height, greaterThan(0));

    final detailSend = tester.widget<StudioButton>(
      find.byKey(const ValueKey('asset-detail-send')),
    );
    expect(detailSend.label, '发送到工作台');
  });

  testWidgets('asset detail dialog keeps usable proportions on wide screens',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(
      const ValueKey('asset-detail-dialog-character-char-1'),
    );
    final content = find.byKey(
      const ValueKey('asset-library-detail-content'),
    );
    final editorPane = find.byKey(
      const ValueKey('asset-detail-editor-pane-character-char-1'),
    );
    final close = find.byKey(const ValueKey('asset-detail-dialog-close'));

    expect(tester.getSize(dialog).width, lessThanOrEqualTo(1220));
    expect(tester.getSize(editorPane).width, inInclusiveRange(420, 640));
    expect(
      tester.getRect(content).right,
      closeTo(tester.getRect(dialog).right, 0.1),
    );
    expect(
      tester.getRect(close).right,
      lessThan(tester.getRect(content).right),
    );
  });

  testWidgets('asset detail dialog stays visible after selecting a low card',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final longCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 48,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: [
        for (var index = 0; index < 48; index++)
          ArtistChain(
            id: 'artist-$index',
            name: 'Artist $index',
            prompt: 'style prompt $index',
            tags: ['tag $index'],
          ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(page(config: config, catalog: longCatalog));
    await tester.pumpAndSettle();

    final waterfallScrollable = find.descendant(
      of: find.byKey(const ValueKey('asset-library-waterfall-board')),
      matching: find.byType(Scrollable),
    );
    final lastCard = find.byKey(const ValueKey('asset-card-artist-artist-47'));
    await tester.scrollUntilVisible(
      lastCard,
      500,
      scrollable: waterfallScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(lastCard);
    await tester.pumpAndSettle();

    final detailDialog =
        find.byKey(const ValueKey('asset-detail-dialog-artist-artist-47'));
    expect(detailDialog, findsOneWidget);
    expect(
      tester.getTopLeft(detailDialog).dy,
      greaterThanOrEqualTo(0),
    );
  });

  testWidgets('artist chain detail dialog also hides prompt layout controls',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: '水彩柔光',
          prompt: 'watercolor wash, soft light',
          tags: ['transparent color'],
          styleTags: ['soft rim'],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(page(config: config, catalog: artistOnlyCatalog));
    await tester.pumpAndSettle();

    final artistCard = find.byKey(const ValueKey('asset-card-artist-artist-1'));
    await tester.ensureVisible(artistCard);
    await tester.tap(artistCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-dialog-artist-artist-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('asset-detail-send')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-grouped')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-layered')),
      findsNothing,
    );
  });

  testWidgets('artist chain detail toggles default vibe binding',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter With Default Vibe',
          prompt: 'artist:replacement',
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        loadVibes: () async => const [
          WorkspaceVibeReference(
            id: 'v4-vibe-0-qaq-2',
            name: 'QAQ 2',
            vibeB64: 'encoded-qaq-2',
            referenceStrength: 0.42,
          ),
        ],
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final artistCard = find.byKey(const ValueKey('asset-card-artist-artist-1'));
    await tester.ensureVisible(artistCard);
    await tester.tap(artistCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final chooseExistingButton =
        find.byKey(const ValueKey('asset-artist-vibe-options-toggle'));
    expect(chooseExistingButton, findsOneWidget);
    await tester.tap(chooseExistingButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final vibeToggle = find.byKey(
      const ValueKey('asset-artist-vibe-binding-v4-vibe-0-qaq-2'),
    );
    expect(vibeToggle, findsOneWidget);
    expect(find.text('QAQ 2'), findsOneWidget);

    await tester.tap(vibeToggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedArtistChains.single.vibeRefs.single.name, 'QAQ 2');
    expect(savedArtistChains.single.vibeRefs.single.vibeB64, 'encoded-qaq-2');
    expect(savedArtistChains.single.vibeRefs.single.referenceStrength, 0.42);

    final strengthSlider = find.byKey(
      const ValueKey('asset-artist-vibe-strength-v4-vibe-0-qaq-2'),
    );
    expect(strengthSlider, findsOneWidget);
    tester.widget<Slider>(strengthSlider).onChangeEnd?.call(0.73);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedArtistChains.single.vibeRefs.single.referenceStrength, 0.73);
  });

  testWidgets('artist chain detail imports and binds a default vibe',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter With Imported Vibe',
          prompt: 'artist:replacement',
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        loadVibes: () async => const [],
        importVibes: () async => const [
          WorkspaceVibeReference(
            id: 'imported-vibe',
            name: 'Imported Vibe',
            vibeB64: 'encoded-imported-vibe',
            referenceStrength: 0.61,
          ),
        ],
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final artistCard = find.byKey(const ValueKey('asset-card-artist-artist-1'));
    await tester.ensureVisible(artistCard);
    await tester.tap(artistCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final addButton = find.byKey(const ValueKey('asset-artist-vibe-import'));
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedArtistChains.single.vibeRefs.single.name, 'Imported Vibe');
    expect(
      savedArtistChains.single.vibeRefs.single.vibeB64,
      'encoded-imported-vibe',
    );
    expect(
      find.byKey(const ValueKey('asset-artist-vibe-binding-imported-vibe')),
      findsOneWidget,
    );
    expect(find.text('Imported Vibe'), findsOneWidget);
  });

  testWidgets('imported artist chain vibe stays scoped to selected chain',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 2,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter With Scoped Vibe',
          prompt: 'artist:scoped',
        ),
        ArtistChain(
          id: 'artist-2',
          name: 'Painter Without Scoped Vibe',
          prompt: 'artist:plain',
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        loadVibes: () async => const [],
        importVibes: () async => const [
          WorkspaceVibeReference(
            id: 'scoped-imported-vibe',
            name: 'Scoped Imported Vibe',
            vibeB64: 'encoded-scoped-imported-vibe',
            referenceStrength: 0.61,
          ),
        ],
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final firstArtistCard =
        find.byKey(const ValueKey('asset-card-artist-artist-1'));
    await tester.ensureVisible(firstArtistCard);
    await tester.tap(firstArtistCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('asset-artist-vibe-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedArtistChains, hasLength(2));
    expect(savedArtistChains[0].vibeRefs.single.name, 'Scoped Imported Vibe');
    expect(savedArtistChains[1].vibeRefs, isEmpty);
    expect(find.text('Scoped Imported Vibe'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('asset-detail-dialog-close')));
    await tester.pumpAndSettle();

    final secondArtistCard =
        find.byKey(const ValueKey('asset-card-artist-artist-2'));
    await tester.ensureVisible(secondArtistCard);
    await tester.tap(secondArtistCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Painter Without Scoped Vibe'), findsWidgets);
    expect(find.text('Scoped Imported Vibe'), findsNothing);
  });

  testWidgets('artist chain detail can duplicate the chain as a new asset',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'artist:source, watercolor wash',
          tags: ['artist:source'],
          styleTags: ['watercolor wash'],
          vibeRefs: [
            WorkspaceVibeReference(
              id: 'bound-vibe',
              name: 'Bound Vibe',
              vibeB64: 'encoded-bound-vibe',
            ),
          ],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pumpAndSettle();

    final artistCard = find.byKey(const ValueKey('asset-card-artist-artist-1'));
    await tester.ensureVisible(artistCard);
    await tester.tap(artistCard);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-detail-duplicate-artist-chain')),
    );
    await tester.pumpAndSettle();

    expect(savedArtistChains, hasLength(2));
    expect(savedArtistChains.last.id, 'artist-1-copy');
    expect(savedArtistChains.last.name, 'Painter Copy');
    expect(savedArtistChains.last.prompt, 'artist:source, watercolor wash');
    expect(savedArtistChains.last.tags, ['artist:source']);
    expect(savedArtistChains.last.styleTags, ['watercolor wash']);
    expect(savedArtistChains.last.vibeRefs.single.id, 'bound-vibe');
    expect(savedArtistChains.last.source.type, 'manual');
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1-copy')),
      findsOneWidget,
    );
    expect(find.text('Painter Copy'), findsWidgets);
  });

  testWidgets('artist chain detail can rename the chain', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'artist:source, watercolor wash',
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('asset-detail-rename-artist-chain')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-artist-chain-name-field')),
      'Painter Renamed',
    );
    await tester.tap(
      find.byKey(const ValueKey('asset-artist-chain-rename-confirm')),
    );
    await tester.pumpAndSettle();

    expect(savedArtistChains.single.name, 'Painter Renamed');
    expect(find.text('Painter Renamed'), findsWidgets);
    expect(find.text('Painter'), findsNothing);
  });

  testWidgets('asset detail edits artist chain prompt tags inline',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'artist:source, watercolor wash',
          tags: ['artist:source', 'watercolor wash'],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();

    final editor = find.byKey(
      const ValueKey('asset-detail-prompt-editor-artist-artist-1'),
    );
    expect(editor, findsOneWidget);
    await _addPromptTags(tester, editor, 'ink lines');

    expect(savedArtistChains.single.prompt,
        'artist:source, watercolor wash, ink lines');
    expect(savedArtistChains.single.tags,
        ['artist:source', 'watercolor wash', 'ink lines']);
  });

  testWidgets('artist chain detail hides duplicate prompt tag sections',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = payload();
    const artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'artist:source, watercolor wash',
          tags: ['artist:source', 'watercolor wash'],
        ),
      ],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(config: config, catalog: artistOnlyCatalog),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-prompt-editor-artist-artist-1')),
      findsOneWidget,
    );
    expect(find.text('Prompt'), findsNothing);
    expect(find.text('Tags'), findsNothing);
  });

  testWidgets(
      'artist chain detail does not expose old metadata or vibe sliders',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = payload();
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-real',
          name: 'OAQ1号',
          prompt: '0.9:: kedama_milk ::, 1.2::ciloranko ::',
          tags: ['kedama_milk', 'ciloranko'],
          imageRefs: [
            'assets/references/strict-artist-chain-previews/raw.png',
          ],
          vibeRefs: [
            WorkspaceVibeReference(
              id: 'legacy-vibe',
              name: '2d0e77-8b0dd8',
              vibeB64: 'encoded',
              referenceStrength: 0.72,
            ),
          ],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(config: config, catalog: artistOnlyCatalog),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-artist-artist-real')),
    );
    await tester.pumpAndSettle();

    expect(find.text('OAQ1号'), findsWidgets);
    expect(
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-artist-artist-real'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-detail-translation-toggle')),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Prompt'), findsNothing);
    expect(find.text('Tags'), findsNothing);
    expect(
      find.text('assets/references/strict-artist-chain-previews/raw.png'),
      findsNothing,
    );
  });

  testWidgets('asset library can create edit and delete manual artist chains',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final emptyCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: emptyCatalog,
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-library-add-character')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('asset-library-add-artist-chain')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('asset-library-add-asset')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('asset-editor-kind-artist-chain')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Manual Painter',
    );
    final createPromptEditor =
        find.byKey(const ValueKey('asset-editor-prompt-field'));
    expect(
      find.descendant(
        of: createPromptEditor,
        matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
      ),
      findsOneWidget,
    );
    await _addPromptTags(
      tester,
      createPromptEditor,
      'artist:manual, bright rim light',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedArtistChains, hasLength(1));
    expect(savedArtistChains.single.name, 'Manual Painter');
    expect(savedArtistChains.single.prompt, 'artist:manual, bright rim light');
    expect(
        savedArtistChains.single.tags, ['artist:manual', 'bright rim light']);

    await tester.tap(
      find.byKey(
        ValueKey('asset-card-artist-${savedArtistChains.single.id}'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-edit-asset')));
    await tester.pumpAndSettle();
    final editPromptEditor =
        find.byKey(const ValueKey('asset-editor-prompt-field'));
    expect(
      find.descendant(
        of: editPromptEditor,
        matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
      ),
      findsOneWidget,
    );
    await _addPromptTags(
      tester,
      editPromptEditor,
      'sunset palette',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(
      savedArtistChains.single.prompt,
      'artist:manual, bright rim light, sunset palette',
    );
    expect(savedArtistChains.single.tags, [
      'artist:manual',
      'bright rim light',
      'sunset palette',
    ]);

    final deleteAsset = find.byKey(const ValueKey('asset-detail-delete-asset'));
    await tester.ensureVisible(deleteAsset);
    await tester.pumpAndSettle();
    tester.widget<StudioIconButton>(deleteAsset).onPressed?.call();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-delete-confirm')));
    await tester.pumpAndSettle();

    expect(savedArtistChains, isEmpty);
    expect(find.text('Manual Painter'), findsNothing);
  });

  testWidgets('new manual artist chain is shown after a crowded all view',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final characters = [
      for (var index = 0; index < 49; index += 1)
        CharacterEntry(
          id: 'crowded-character-$index',
          name: 'Crowded Character $index',
          traits: ViewVariantTexts(frontFull: 'crowded character $index'),
        ),
    ];
    final crowdedCatalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: characters.length,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: const {},
        tagCountsByBlock: const {},
      ),
      characters: characters,
      artistChains: const [],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: crowdedCatalog,
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-library-add-asset')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('asset-editor-kind-artist-chain')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Visible Painter',
    );
    await _addPromptTags(
      tester,
      find.byKey(const ValueKey('asset-editor-prompt-field')),
      'artist:visible',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedArtistChains, hasLength(1));
    expect(
      find.byKey(ValueKey('asset-card-artist-${savedArtistChains.single.id}')),
      findsOneWidget,
    );
    expect(find.text('匹配素材 1'), findsOneWidget);
  });

  testWidgets('asset library can create manual characters', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();
    final emptyCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: emptyCatalog,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-library-add-character')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('asset-library-add-artist-chain')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('asset-library-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-editor-kind-character')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('asset-editor-prompt-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-character-editor-front-upper-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-character-editor-front-lower-field')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Manual Hero',
    );
    await _addPromptTags(
      tester,
      find.byKey(const ValueKey('asset-character-editor-identity-tags-editor')),
      '1girl, girl, loli, silver hair',
    );
    await _addPromptTags(
      tester,
      find.byKey(
          const ValueKey('asset-character-editor-upper-body-tags-editor')),
      'blue eyes',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-character-editor-upper-clothing-tags-editor'),
      ),
      'blue cape',
    );
    await _addPromptTags(
      tester,
      find.byKey(
          const ValueKey('asset-character-editor-lower-body-tags-editor')),
      'fox tail',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-character-editor-lower-clothing-tags-editor'),
      ),
      'pleated skirt',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters, hasLength(1));
    final character = savedCharacters.single;
    expect(character.name, 'Manual Hero');
    expect(
      character.traits.frontFull,
      'girl, loli, silver hair, blue eyes, fox tail',
    );
    expect(character.traits.frontUpper, 'blue eyes');
    expect(character.traits.frontLower, 'fox tail');
    expect(character.identityTags, ['girl', 'loli', 'silver hair']);
    expect(character.identityTags, isNot(contains('1girl')));
    expect(character.anchorTags, isEmpty);
    expect(character.defaultOutfitId, 'default-outfit');
    expect(character.outfits, hasLength(1));
    expect(character.outfits.single.partTags.upperBodyTags, ['blue eyes']);
    expect(character.outfits.single.partTags.upperClothingTags, ['blue cape']);
    expect(character.outfits.single.partTags.lowerBodyTags, ['fox tail']);
    expect(
        character.outfits.single.partTags.lowerClothingTags, ['pleated skirt']);
    expect(character.outfits.single.tags.frontUpper, 'blue cape');
    expect(character.outfits.single.tags.frontLower, 'pleated skirt');
    expect(find.byKey(const ValueKey('asset-library-add-tag')), findsNothing);
  });

  testWidgets('asset library can create sectioned recipes and tags',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedRecipesByBlock = <String, List<Recipe>>{};
    final savedTagsByBlock = <String, List<TagEntry>>{};
    var savedPromptCategories = <PromptAssetCategory>[];
    var promptAssetChangeCount = 0;
    final config = payload();
    const emptyCatalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: emptyCatalog,
        saveRecipes: (block, recipes) async {
          savedRecipesByBlock[block] = recipes;
        },
        saveTags: (block, tags) async {
          savedTagsByBlock[block] = tags;
        },
        savePromptAssetCategories: (categories) async {
          savedPromptCategories = categories;
        },
        onPromptAssetsChanged: () {
          promptAssetChangeCount += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-filter-recipe')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-filter-tag')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('asset-library-manage-categories')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-asset-category-name-field')),
      '战斗素材',
    );
    await tester.enterText(
      find.byKey(const ValueKey('prompt-asset-category-id-field')),
      'combat',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-asset-category-add')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-asset-category-drawer-combat')),
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-asset-category-save')),
    );
    await tester.pumpAndSettle();

    expect(savedPromptCategories, hasLength(1));
    expect(savedPromptCategories.single.id, 'combat');
    expect(savedPromptCategories.single.name, '战斗素材');
    expect(savedPromptCategories.single.showInScriptDrawer, isTrue);

    await tester.tap(find.byKey(const ValueKey('asset-library-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-editor-kind-recipe')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Battle Recipe',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-block-field')),
      'combat',
    );
    final recipePromptEditor =
        find.byKey(const ValueKey('asset-editor-prompt-field'));
    expect(
      find.descendant(
        of: recipePromptEditor,
        matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
      ),
      findsOneWidget,
    );
    await _addPromptTags(
      tester,
      recipePromptEditor,
      'battle stance',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-add-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-section-prompt-0-label')),
      '穿甲',
    );
    await _addPromptTags(
      tester,
      find.byKey(const ValueKey('asset-editor-section-prompt-0')),
      'armored plates, shoulder armor',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedRecipesByBlock['combat'], hasLength(1));
    expect(savedRecipesByBlock['combat']!.single.tags, 'battle stance');
    expect(
      savedRecipesByBlock['combat']!.single.variants,
      {'穿甲': 'armored plates, shoulder armor'},
    );

    await tester.tap(find.byKey(const ValueKey('asset-library-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-editor-kind-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Camera Mood',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-block-field')),
      'camera',
    );
    final tagPromptEditor =
        find.byKey(const ValueKey('asset-editor-prompt-field'));
    expect(
      find.descendant(
        of: tagPromptEditor,
        matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
      ),
      findsOneWidget,
    );
    await _addPromptTags(
      tester,
      tagPromptEditor,
      'low angle',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-add-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-section-prompt-0-label')),
      '俯拍',
    );
    await _addPromptTags(
      tester,
      find.byKey(const ValueKey('asset-editor-section-prompt-0')),
      'from above, wide shot',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedTagsByBlock['camera'], hasLength(1));
    expect(savedTagsByBlock['camera']!.single.tag, 'low angle');
    expect(savedTagsByBlock['camera']!.single.zh, 'Camera Mood');
    expect(
      savedTagsByBlock['camera']!.single.sections,
      {'俯拍': 'from above, wide shot'},
    );
    expect(promptAssetChangeCount, 3);
  });

  testWidgets('asset library can duplicate character cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();

    await tester.pumpWidget(
      page(
        config: config,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('asset-detail-duplicate-character')),
    );
    await tester.pumpAndSettle();

    expect(savedCharacters, hasLength(2));
    expect(savedCharacters.last.id, 'char-1-copy');
    expect(
        savedCharacters.last.name, '${snapshot.characters.single.name} Copy');
    expect(savedCharacters.last.traits.frontFull, 'silver hair, blue eyes');
    expect(savedCharacters.last.outfits.single.id, 'outfit-1');
    expect(savedCharacters.last.source.type, 'manual');
    expect(
      find.byKey(const ValueKey('asset-card-character-char-1-copy')),
      findsOneWidget,
    );
  });

  testWidgets('asset library edits richer manual character card fields',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();

    await tester.pumpWidget(
      page(
        config: config,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-edit-asset')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Edited Hero',
    );
    expect(
        find.byKey(const ValueKey('asset-editor-prompt-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-character-editor-front-upper-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-character-editor-front-lower-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-character-editor-anchor-tags-editor')),
      findsNothing,
    );
    await _addPromptTags(
      tester,
      find.byKey(const ValueKey('asset-character-editor-identity-tags-editor')),
      'manual identity',
    );
    await _addPromptTags(
      tester,
      find.byKey(
          const ValueKey('asset-character-editor-upper-body-tags-editor')),
      'edited upper',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-character-editor-upper-clothing-tags-editor'),
      ),
      'blue cape',
    );
    await _addPromptTags(
      tester,
      find.byKey(
          const ValueKey('asset-character-editor-lower-body-tags-editor')),
      'edited lower',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-character-editor-lower-clothing-tags-editor'),
      ),
      'pleated skirt',
    );
    expect(
      find.byKey(const ValueKey('asset-character-editor-aliases-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-character-editor-image-refs-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-character-editor-note-field')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters, hasLength(1));
    final character = savedCharacters.single;
    expect(character.name, 'Edited Hero');
    expect(character.traits.frontFull, contains('manual identity'));
    expect(character.traits.frontFull, contains('edited upper'));
    expect(character.traits.frontFull, contains('edited lower'));
    expect(character.traits.frontUpper, contains('edited upper'));
    expect(character.traits.frontLower, contains('edited lower'));
    expect(character.anchorTags, isEmpty);
    expect(character.identityTags, contains('manual identity'));
    expect(character.defaultOutfitId, isNotNull);
    expect(character.outfits, isNotEmpty);
    final defaultOutfit = character.outfits.firstWhere(
      (outfit) => outfit.id == character.defaultOutfitId,
      orElse: () => character.outfits.first,
    );
    expect(defaultOutfit.partTags.upperClothingTags, contains('blue cape'));
    expect(defaultOutfit.partTags.lowerClothingTags, contains('pleated skirt'));
    expect(character.aliases, isEmpty);
    expect(character.imageRefs, ['refs/lixia.png']);
    expect(character.note, '主角素材');
    expect(character.source.type, 'manual');
  });

  testWidgets('asset detail edits character prompt tags inline',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();

    await tester.pumpWidget(
      page(
        config: config,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    final editor = find.byKey(
      const ValueKey('asset-detail-prompt-editor-character-char-1'),
    );
    expect(editor, findsOneWidget);
    await _addPromptTags(tester, editor, 'new ribbon');

    expect(savedCharacters, hasLength(1));
    expect(
      savedCharacters.single.traits.frontFull,
      'silver hair, blue eyes, new ribbon',
    );
    expect(savedCharacters.single.identityTags, contains('new ribbon'));
  });

  testWidgets('asset detail edits structured outfit tag fields',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();

    await tester.pumpWidget(
      page(
        config: config,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    final outfitUpperEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-char-1-outfit-0-upper-clothing',
      ),
    );
    expect(outfitUpperEditor, findsOneWidget);
    await _addPromptTags(tester, outfitUpperEditor, 'blue trim');

    expect(
      savedCharacters.single.outfits.single.partTags.upperClothingTags,
      ['yellow jacket', 'blue trim'],
    );
    expect(
      savedCharacters.single.outfits.single.tags.frontUpper,
      'yellow jacket, blue trim',
    );
  });

  testWidgets('asset detail serializes prompt edits against the latest catalog',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstSaveStarted = Completer<void>();
    final releaseSaves = Completer<void>();
    List<CharacterEntry> persistedCharacters = const [];
    var savesInFlight = 0;
    var maxSavesInFlight = 0;

    await tester.pumpWidget(
      page(
        config: payload(),
        saveCharacters: (characters) async {
          savesInFlight += 1;
          if (savesInFlight > maxSavesInFlight) {
            maxSavesInFlight = savesInFlight;
          }
          if (!firstSaveStarted.isCompleted) {
            firstSaveStarted.complete();
          }
          await releaseSaves.future;
          persistedCharacters = characters;
          savesInFlight -= 1;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-character-char-1'),
      ),
      'new ribbon',
    );
    await firstSaveStarted.future;
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-1-outfit-0-upper-clothing',
        ),
      ),
      'blue trim',
    );

    releaseSaves.complete();
    await tester.pumpAndSettle();

    expect(maxSavesInFlight, 1);
    expect(persistedCharacters.single.identityTags, contains('new ribbon'));
    expect(
      persistedCharacters.single.outfits.single.partTags.upperClothingTags,
      contains('blue trim'),
    );
  });

  testWidgets('character deletion waits for a pending prompt mutation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstSaveStarted = Completer<void>();
    final releaseSaves = Completer<void>();
    List<CharacterEntry> persistedCharacters = const [];
    var savesInFlight = 0;
    var maxSavesInFlight = 0;

    await tester.pumpWidget(
      page(
        config: payload(),
        saveCharacters: (characters) async {
          savesInFlight += 1;
          if (savesInFlight > maxSavesInFlight) {
            maxSavesInFlight = savesInFlight;
          }
          if (!firstSaveStarted.isCompleted) {
            firstSaveStarted.complete();
          }
          await releaseSaves.future;
          persistedCharacters = characters;
          savesInFlight -= 1;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-character-char-1'),
      ),
      'pending prompt',
    );
    await firstSaveStarted.future;

    final deleteAsset = find.byKey(const ValueKey('asset-detail-delete-asset'));
    tester.widget<StudioIconButton>(deleteAsset).onPressed?.call();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-delete-confirm')));
    await tester.pump();

    releaseSaves.complete();
    await tester.pumpAndSettle();

    expect(maxSavesInFlight, 1);
    expect(persistedCharacters, isEmpty);
  });

  testWidgets('queued prompt edits keep their working catalog after dispose',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstSaveStarted = Completer<void>();
    final releaseFirstSave = Completer<void>();
    List<CharacterEntry> persistedCharacters = const [];
    var saveCount = 0;

    await tester.pumpWidget(
      page(
        config: payload(),
        saveCharacters: (characters) async {
          saveCount += 1;
          if (saveCount == 1) {
            firstSaveStarted.complete();
            await releaseFirstSave.future;
          }
          persistedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-character-char-1'),
      ),
      'new ribbon',
    );
    await firstSaveStarted.future;
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-1-outfit-0-upper-clothing',
        ),
      ),
      'blue trim',
    );

    await tester.pumpWidget(const SizedBox());
    releaseFirstSave.complete();
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }

    expect(saveCount, 2);
    expect(persistedCharacters.single.identityTags, contains('new ribbon'));
    expect(
      persistedCharacters.single.outfits.single.partTags.upperClothingTags,
      contains('blue trim'),
    );
  });

  testWidgets('asset detail matches drawer outfit prompt and part rows',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = payload();
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-outfit-fields',
          name: 'Outfit Fields',
          traits: ViewVariantTexts(
            frontFull: 'base identity',
            frontUpper: 'hidden character upper',
            frontLower: 'hidden character lower',
          ),
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-fields',
              name: 'Fielded Outfit',
              tags: ViewVariantTexts(
                frontFull: 'outfit identity',
                frontUpper: 'white blouse',
                frontLower: 'black skirt',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperBodyTags: ['cat ears'],
                upperClothingTags: ['white blouse'],
                lowerBodyTags: ['cat tail'],
                lowerClothingTags: ['black skirt'],
                weaponTags: ['sword'],
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('asset-card-character-char-outfit-fields'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-outfit-fields-outfit-0',
        ),
      ),
      findsNothing,
    );
    expect(find.text('outfit identity'), findsNothing);
    expect(find.text('hidden character upper'), findsNothing);
    expect(find.text('hidden character lower'), findsNothing);
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-outfit-fields-outfit-0-upper-body',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-outfit-fields-outfit-0-lower-body',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-outfit-fields-outfit-0-upper-clothing',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-outfit-fields-outfit-0-lower-clothing',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-char-outfit-fields-outfit-0-weapon',
        ),
      ),
      findsNothing,
    );
    expect(find.text('sword'), findsNothing);
  });

  testWidgets('asset detail keeps skin identity out of outfit tag slots',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = payload();
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-suzuran',
          name: 'Suzuran',
          traits: ViewVariantTexts(frontFull: 'suzuran (arknights)'),
          identityTags: ['suzuran (arknights)'],
          outfits: [
            WorkspaceOutfit(
              id: 'yukibare',
              name: 'Yukibare',
              tags: ViewVariantTexts(
                frontFull: 'suzuran (yukibare) (arknights), kimono',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['kimono'],
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('asset-card-character-char-suzuran')));
    await tester.pumpAndSettle();

    final outfitEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-char-suzuran-outfit-0',
      ),
    );
    expect(outfitEditor, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('asset-detail-prompt-editor-character-char-suzuran'),
        ),
        matching: find.text('suzuran (arknights)'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('suzuran (yukibare) (arknights)'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'asset-detail-prompt-editor-character-char-suzuran-outfit-0-upper-clothing',
          ),
        ),
        matching: find.text('kimono'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'asset detail shows structured character outfit fields without duplicate raw tags',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    GetIt.I<TranslationCache>()
      ..setManual('pepe_(arknights)', '佩佩')
      ..setManual('girl', '少女')
      ..setManual('loli', '萝莉')
      ..setManual('cat_ears', '猫耳')
      ..setManual('cat_tail', '猫尾')
      ..setManual('animal_ear_fluff', '兽耳绒毛')
      ..setManual('animal_ears', '兽耳')
      ..setManual('lotus_flower_headdress', '莲花头饰')
      ..setManual('animal_ear_hood', '兽耳兜帽')
      ..setManual('black_jacket', '黑色夹克')
      ..setManual('black_shorts', '黑色短裤');

    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'legacy-character-sheet-r14',
          name: '佩佩',
          traits: ViewVariantTexts(
            frontFull:
                'pepe_(arknights), girl, 2::loli::, cat_girl, 1.5::cat_ears, cat_tail, animal_ear_fluff, animal_ears, cat_ears, cat_tail::, Lotus flower headdress',
            frontUpper:
                'cat_ears, animal_ear_fluff, animal_ears, lotus_flower_headdress',
            frontLower: 'cat_tail',
          ),
          identityTags: [
            'pepe_(arknights)',
            'girl',
            'loli',
          ],
          outfits: [
            WorkspaceOutfit(
              id: 'default-outfit',
              name: '默认服装',
              tags: ViewVariantTexts(
                frontFull:
                    'animal_ear_hood, black_jacket, black_shorts, cat_ears, cat_tail',
                frontUpper: 'animal_ear_hood, black_jacket',
                frontLower: 'black_shorts',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperBodyTags: [
                  'cat_ears',
                  'animal_ear_fluff',
                  'animal_ears',
                  'lotus_flower_headdress',
                ],
                upperClothingTags: [
                  'animal_ear_hood',
                  'black_jacket',
                ],
                lowerBodyTags: ['cat_tail'],
                lowerClothingTags: ['black_shorts'],
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(page(config: payload(), catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('asset-card-character-legacy-character-sheet-r14'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-prompt-editor-character-legacy-character-sheet-r14-outfit-0',
        ),
      ),
      findsNothing,
    );

    final roleEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-character-sheet-r14',
      ),
    );
    final upperBodyEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-character-sheet-r14-outfit-0-upper-body',
      ),
    );
    final upperClothingEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-character-sheet-r14-outfit-0-upper-clothing',
      ),
    );
    final lowerBodyEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-character-sheet-r14-outfit-0-lower-body',
      ),
    );
    final lowerClothingEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-character-sheet-r14-outfit-0-lower-clothing',
      ),
    );

    expect(roleEditor, findsOneWidget);
    expect(upperBodyEditor, findsOneWidget);
    expect(upperClothingEditor, findsOneWidget);
    expect(lowerBodyEditor, findsOneWidget);
    expect(lowerClothingEditor, findsOneWidget);
    expect(
      find.descendant(of: roleEditor, matching: find.text('佩佩')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: roleEditor, matching: find.text('少女')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: roleEditor, matching: find.text('猫耳')),
      findsNothing,
    );
    expect(
      find.descendant(of: upperBodyEditor, matching: find.text('猫耳')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lowerBodyEditor, matching: find.text('猫尾')),
      findsOneWidget,
    );

    expect(
      find.descendant(of: upperBodyEditor, matching: find.text('cat_ears')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lowerBodyEditor, matching: find.text('cat_tail')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: upperClothingEditor,
        matching: find.text('animal_ear_hood'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lowerClothingEditor,
        matching: find.text('black_shorts'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asset detail keeps character outfit editing to five tag slots',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'legacy-outfit-character',
          name: 'Legacy Outfit Character',
          traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
          outfits: [
            WorkspaceOutfit(
              id: 'legacy-outfit',
              name: 'Legacy Outfit',
              tags: ViewVariantTexts(
                frontFull: 'yellow rain coat',
                frontUpper: 'legacy upper fallback',
                frontLower: 'legacy lower fallback',
              ),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('asset-card-character-legacy-outfit-character'),
      ),
    );
    await tester.pumpAndSettle();

    final outfitEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-outfit-character-outfit-0',
      ),
    );
    expect(outfitEditor, findsNothing);
    final upperClothingEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-outfit-character-outfit-0-upper-clothing',
      ),
    );
    final lowerClothingEditor = find.byKey(
      const ValueKey(
        'asset-detail-prompt-editor-character-legacy-outfit-character-outfit-0-lower-clothing',
      ),
    );
    expect(upperClothingEditor, findsOneWidget);
    expect(lowerClothingEditor, findsOneWidget);
    expect(
      find.descendant(
          of: upperClothingEditor, matching: find.text('yellow rain coat')),
      findsOneWidget,
    );
    expect(find.text('legacy upper fallback'), findsNothing);
    expect(find.text('legacy lower fallback'), findsNothing);
    await _addPromptTags(tester, lowerClothingEditor, 'muddy boots');

    expect(savedCharacters, hasLength(1));
    expect(savedCharacters.single.traits.frontFull, 'silver hair, blue eyes');
    expect(
      savedCharacters.single.outfits.single.tags.frontFull,
      'yellow rain coat, muddy boots',
    );
  });

  testWidgets('asset library adds edits and duplicates character outfits',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();

    await tester.pumpWidget(
      page(
        config: config,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-add-outfit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('asset-outfit-editor-name-field')),
      'Travel Cloak',
    );
    expect(
      find.byKey(const ValueKey('asset-outfit-editor-prompt-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-outfit-editor-image-refs-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-outfit-editor-negative-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-outfit-editor-weapon-tags-field')),
      findsNothing,
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-outfit-editor-upper-clothing-tags-editor'),
      ),
      'black cloak',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-outfit-editor-lower-clothing-tags-editor'),
      ),
      'boots',
    );
    await tester.tap(find.byKey(const ValueKey('asset-outfit-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters.single.outfits.map((outfit) => outfit.id), [
      'outfit-1',
      'outfit-travel-cloak',
    ]);
    expect(
      savedCharacters.single.outfits.last.tags.frontFull,
      'black cloak, boots',
    );
    expect(savedCharacters.single.outfits.last.tags.frontUpper, 'black cloak');
    expect(
      savedCharacters.single.outfits.last.partTags.upperClothingTags,
      ['black cloak'],
    );

    final editTravelCloak = find.byKey(
      const ValueKey(
        'asset-character-outfit-edit-char-1-outfit-travel-cloak',
      ),
    );
    await tester.ensureVisible(editTravelCloak);
    await tester.pumpAndSettle();
    await tester.tap(editTravelCloak);
    await tester.pumpAndSettle();
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-outfit-editor-lower-clothing-tags-editor'),
      ),
      'leather boots',
    );
    await tester.tap(find.byKey(const ValueKey('asset-outfit-editor-save')));
    await tester.pumpAndSettle();

    expect(
      savedCharacters.single.outfits.last.tags.frontFull,
      'black cloak, boots, leather boots',
    );

    final duplicateTravelCloak = find.byKey(
      const ValueKey(
        'asset-character-outfit-duplicate-char-1-outfit-travel-cloak',
      ),
    );
    await tester.ensureVisible(duplicateTravelCloak);
    await tester.pumpAndSettle();
    await tester.tap(duplicateTravelCloak);
    await tester.pumpAndSettle();

    expect(savedCharacters.single.outfits.map((outfit) => outfit.id), [
      'outfit-1',
      'outfit-travel-cloak',
      'outfit-travel-cloak-copy',
    ]);
    expect(savedCharacters.single.outfits.last.name, 'Travel Cloak Copy');
  });

  testWidgets('adding an outfit manualizes a legacy imported character',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();
    const catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'legacy-character',
          name: 'Legacy Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          source: SourceRef(type: 'legacy_artist_workbook'),
          outfits: [
            WorkspaceOutfit(
              id: 'default-outfit',
              name: 'Default Outfit',
              tags: ViewVariantTexts(frontFull: 'school uniform'),
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-legacy-character')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-add-outfit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('asset-outfit-editor-name-field')),
      'Travel Cloak',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-outfit-editor-upper-clothing-tags-editor'),
      ),
      'black cloak',
    );
    await _addPromptTags(
      tester,
      find.byKey(
        const ValueKey('asset-outfit-editor-lower-clothing-tags-editor'),
      ),
      'boots',
    );
    await tester.tap(find.byKey(const ValueKey('asset-outfit-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters.single.source.type, 'manual');
    expect(
      savedCharacters.single.outfits.map((outfit) => outfit.id),
      ['default-outfit', 'outfit-travel-cloak'],
    );
  });

  testWidgets('artist chain preview carousel can remove a preview ref',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ArtistChain> savedArtistChains = const [];
    final config = payload();
    final tempDir = Directory.systemTemp.createTempSync(
      'asset-preview-delete-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final previewFile = File(
      '${tempDir.path}${Platform.pathSeparator}artist-preview.png',
    );
    File('${Uri.base.toFilePath()}assets/appicon.png')
        .copySync(previewFile.path);
    final artistOnlyCatalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [
        ArtistChain(
          id: 'artist-1',
          name: 'Painter',
          prompt: 'artist:source, watercolor wash',
          imageRefs: ['refs/artist.png'],
        ),
      ],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        resolvedRefs: {
          'refs/artist.png': previewFile.path,
        },
        saveArtistChains: (artistChains) async {
          savedArtistChains = artistChains;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(previewFile.existsSync(), isTrue);

    final preview = find.byKey(
      const ValueKey('asset-card-preview-artist-artist-1'),
    );
    expect(preview, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-detail-delete-preview-artist-artist-1')),
    );
    await tester.pumpAndSettle();

    expect(savedArtistChains.single.imageRefs, isEmpty);
    expect(previewFile.existsSync(), isFalse);
    expect(
      find.byKey(const ValueKey('asset-card-preview-image-artist-artist-1')),
      findsNothing,
    );
  });

  testWidgets('artist chain preview delete removes the file after saving refs',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = payload();
    final tempDir = Directory.systemTemp.createTempSync(
      'asset-preview-delete-save-failure-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    bool? fileExistedDuringSave;
    final previewFile = File(
      '${tempDir.path}${Platform.pathSeparator}artist-preview.png',
    );
    File('${Uri.base.toFilePath()}assets/appicon.png')
        .copySync(previewFile.path);
    final artistOnlyCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 1,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [
        ArtistChain(
          id: 'artist-save-fails',
          name: 'Painter',
          prompt: 'artist:source, watercolor wash',
          imageRefs: ['refs/artist-save-fails.png'],
        ),
      ],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: artistOnlyCatalog,
        resolvedRefs: {
          'refs/artist-save-fails.png': previewFile.path,
        },
        saveArtistChains: (_) async {
          fileExistedDuringSave = previewFile.existsSync();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(previewFile.existsSync(), isTrue);

    await tester.tap(
      find.byKey(
        const ValueKey('asset-card-artist-artist-save-fails'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'asset-detail-delete-preview-artist-artist-save-fails',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fileExistedDuringSave, isTrue);
    expect(previewFile.existsSync(), isFalse);
  });

  testWidgets('character preview delete removes the local preview file',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();
    final tempDir = Directory.systemTemp.createTempSync(
      'asset-character-preview-delete-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final previewFile = File(
      '${tempDir.path}${Platform.pathSeparator}character-preview.png',
    );
    File('${Uri.base.toFilePath()}assets/appicon.png')
        .copySync(previewFile.path);
    final characterOnlyCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-delete',
          name: 'Preview Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          imageRefs: ['refs/character-delete.png'],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: characterOnlyCatalog,
        resolvedRefs: {
          'refs/character-delete.png': previewFile.path,
        },
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(previewFile.existsSync(), isTrue);

    await tester
        .tap(find.byKey(const ValueKey('asset-card-character-char-delete')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('asset-detail-delete-preview-character-char-delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(savedCharacters.single.imageRefs, isEmpty);
    expect(previewFile.existsSync(), isFalse);
    expect(
      find.byKey(
        const ValueKey('asset-detail-preview-image-character-char-delete'),
      ),
      findsNothing,
    );
  });

  testWidgets('outfit preview delete removes the local preview file',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    final config = payload();
    final tempDir = Directory.systemTemp.createTempSync(
      'asset-outfit-preview-delete-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final previewFile = File(
      '${tempDir.path}${Platform.pathSeparator}outfit-preview.png',
    );
    File('${Uri.base.toFilePath()}assets/appicon.png')
        .copySync(previewFile.path);
    final outfitCatalog = const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [
        CharacterEntry(
          id: 'char-outfit-delete',
          name: 'Outfit Character',
          traits: ViewVariantTexts(frontFull: 'silver hair'),
          outfits: [
            WorkspaceOutfit(
              id: 'outfit-delete',
              name: 'Preview Outfit',
              tags: ViewVariantTexts(frontFull: 'yellow coat'),
              imageRefs: ['refs/outfit-delete.png'],
            ),
          ],
        ),
      ],
      artistChains: [],
      recipes: [],
      tags: [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: outfitCatalog,
        resolvedRefs: {
          'refs/outfit-delete.png': previewFile.path,
        },
        saveCharacters: (characters) async {
          savedCharacters = characters;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(previewFile.existsSync(), isTrue);

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-outfit-delete')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'asset-character-outfit-delete-preview-char-outfit-delete-outfit-delete',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(savedCharacters.single.outfits.single.imageRefs, isEmpty);
    expect(previewFile.existsSync(), isFalse);
    expect(
      find.byKey(
        const ValueKey(
          'asset-character-outfit-preview-image-char-outfit-delete-outfit-delete',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('asset detail content uses inline editable character tags',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-prompt-editor-character-char-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-detail-translation-toggle')),
      findsOneWidget,
    );
    expect(find.text('银发'), findsWidgets);
    expect(find.text('蓝眼睛'), findsWidgets);
    expect(find.text('黄色雨衣'), findsNothing);
    expect(find.text('黄色夹克'), findsWidgets);
    expect(find.text('雨裙'), findsWidgets);

    await tester
        .tap(find.byKey(const ValueKey('asset-detail-translation-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('silver hair'), findsWidgets);
  });

  testWidgets('character detail outfit cards switch the viewed outfit',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final tempDir =
        Directory.systemTemp.createTempSync('asset-outfit-switch-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final uniformPreview =
        File('${tempDir.path}${Platform.pathSeparator}uniform.png');
    final casualPreviewFile =
        File('${tempDir.path}${Platform.pathSeparator}casual.png');
    final casualAltPreviewFile =
        File('${tempDir.path}${Platform.pathSeparator}casual-alt.png');
    final portraitPreviewA =
        File('${tempDir.path}${Platform.pathSeparator}portrait-a.png');
    final portraitPreviewB =
        File('${tempDir.path}${Platform.pathSeparator}portrait-b.png');
    uniformPreview.writeAsBytesSync(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    casualPreviewFile.writeAsBytesSync(
      img.encodePng(img.Image(width: 480, height: 320)),
    );
    casualAltPreviewFile.writeAsBytesSync(
      img.encodePng(img.Image(width: 480, height: 320)),
    );
    portraitPreviewA.writeAsBytesSync(
      img.encodePng(img.Image(width: 360, height: 480)),
    );
    portraitPreviewB.writeAsBytesSync(
      img.encodePng(img.Image(width: 360, height: 480)),
    );
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 2,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [
        CharacterEntry(
          id: 'char-multi',
          name: '多衣角色',
          traits: ViewVariantTexts(frontFull: 'green eyes'),
          imageRefs: ['refs/portrait-a.png', 'refs/portrait-b.png'],
          outfits: [
            WorkspaceOutfit(
              id: 'uniform',
              name: '制服',
              tags: ViewVariantTexts(
                frontFull: 'navy uniform',
                frontUpper: 'navy jacket',
                frontLower: 'pleated skirt',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['navy jacket'],
                lowerClothingTags: ['pleated skirt'],
              ),
              imageRefs: ['refs/uniform.png'],
            ),
            WorkspaceOutfit(
              id: 'casual',
              name: '便服',
              tags: ViewVariantTexts(
                frontFull: 'white hoodie, denim shorts',
                frontUpper: 'white hoodie',
                frontLower: 'denim shorts',
              ),
              partTags: WorkspaceOutfitPartTags(
                upperClothingTags: ['white hoodie'],
                lowerClothingTags: ['denim shorts'],
              ),
              imageRefs: ['refs/casual.png', 'refs/casual-alt.png'],
            ),
          ],
        ),
      ],
      artistChains: const [],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        resolvedRefs: {
          'refs/portrait-a.png': portraitPreviewA.path,
          'refs/portrait-b.png': portraitPreviewB.path,
          'refs/uniform.png': uniformPreview.path,
          'refs/casual.png': casualPreviewFile.path,
          'refs/casual-alt.png': casualAltPreviewFile.path,
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-multi')),
    );
    await tester.pumpAndSettle();

    expect(find.text('制服'), findsOneWidget);
    expect(find.text('white hoodie, denim shorts'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('asset-character-outfit-icon-char-multi-casual'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('asset-character-outfit-icon-char-multi-casual'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('navy uniform'), findsNothing);
    expect(find.text('white hoodie'), findsWidgets);
    expect(find.text('denim shorts'), findsWidgets);
    expect(find.text('便服'), findsOneWidget);

    final casualImage = tester.widget<Image>(
      find.byKey(
        const ValueKey(
          'asset-character-outfit-preview-image-char-multi-casual',
        ),
      ),
    );
    _expectResizedFileImage(casualImage, casualPreviewFile.path);
    final infoStrip = find.byKey(
      const ValueKey('asset-detail-info-strip-character-char-multi'),
    );
    expect(
      find.descendant(of: infoStrip, matching: find.text('2 张')),
      findsWidgets,
    );
    expect(
      find.descendant(of: infoStrip, matching: find.text('5 张')),
      findsNothing,
    );
    for (var index = 0; index < 2; index += 1) {
      expect(
        find.byKey(ValueKey('asset-character-preview-dot-char-multi-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('asset-character-preview-dot-char-multi-2')),
      findsNothing,
    );

    final casualPreview = find.byKey(
      const ValueKey('asset-character-outfit-preview-char-multi-casual'),
    );
    await tester.ensureVisible(casualPreview);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(casualPreview),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    final scrolledCasualImage = tester.widget<Image>(
      find.byKey(
        const ValueKey(
          'asset-character-outfit-preview-image-char-multi-casual',
        ),
      ),
    );
    _expectResizedFileImage(scrolledCasualImage, casualAltPreviewFile.path);

    await tester.tap(casualPreview);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('asset-preview-carousel-outfit-char-multi-casual'),
      ),
      findsOneWidget,
    );
    final counter =
        find.byKey(const ValueKey('asset-preview-carousel-counter'));
    expect(tester.widget<Text>(counter).data, '1/2');

    final carousel = find.byKey(
      const ValueKey('asset-preview-carousel-outfit-char-multi-casual'),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(carousel),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(counter).data, '2/2');
    expect(
      find.byKey(
        const ValueKey(
          'asset-preview-carousel-image-outfit-char-multi-casual-1',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('character detail switches duplicate-id outfits by slot index',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 2,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [
        CharacterEntry(
          id: 'char-duplicate-outfits',
          name: 'Duplicate Outfit IDs',
          traits: ViewVariantTexts(frontFull: 'green eyes'),
          defaultOutfitId: 'default-outfit',
          outfits: [
            WorkspaceOutfit(
              id: 'default-outfit',
              name: 'Default',
              tags: ViewVariantTexts(frontFull: 'blue coat'),
            ),
            WorkspaceOutfit(
              id: 'default-outfit',
              name: 'Variant',
              tags: ViewVariantTexts(frontFull: 'white dress'),
            ),
          ],
        ),
      ],
      artistChains: const [],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('asset-card-character-char-duplicate-outfits'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('blue coat'), findsWidgets);
    expect(find.text('white dress'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'asset-character-outfit-icon-char-duplicate-outfits-default-outfit-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Variant'), findsOneWidget);
    expect(find.text('blue coat'), findsNothing);
    expect(find.text('white dress'), findsWidgets);
  });

  testWidgets('expanded asset detail click targets expose hover feedback',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final tempDir =
        Directory.systemTemp.createTempSync('asset-detail-hover-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final uniformPreview =
        File('${tempDir.path}${Platform.pathSeparator}uniform.png');
    final casualPreview =
        File('${tempDir.path}${Platform.pathSeparator}casual.png');
    File('${Uri.base.toFilePath()}assets/appicon.png')
        .copySync(uniformPreview.path);
    File('${Uri.base.toFilePath()}assets/appicon.png')
        .copySync(casualPreview.path);
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 2,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [
        CharacterEntry(
          id: 'char-hover',
          name: 'Hover Heroine',
          traits: ViewVariantTexts(frontFull: 'green eyes'),
          outfits: [
            WorkspaceOutfit(
              id: 'uniform',
              name: 'Uniform',
              tags: ViewVariantTexts(frontFull: 'navy uniform'),
              imageRefs: ['refs/uniform-hover.png'],
            ),
            WorkspaceOutfit(
              id: 'casual',
              name: 'Casual',
              tags: ViewVariantTexts(frontFull: 'white hoodie'),
              imageRefs: ['refs/casual-hover.png'],
            ),
          ],
        ),
      ],
      artistChains: const [],
      recipes: const [],
      tags: const [],
    );
    Color borderColor(Finder finder) {
      final decoration =
          tester.widget<AnimatedContainer>(finder).decoration! as BoxDecoration;
      return (decoration.border! as Border).top.color;
    }

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        resolvedRefs: {
          'refs/uniform-hover.png': uniformPreview.path,
          'refs/casual-hover.png': casualPreview.path,
        },
        saveCharacters: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-hover')),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final preview = find.byKey(
      const ValueKey('asset-character-outfit-preview-char-hover-uniform'),
    );
    final previewFrame = find.descendant(
      of: preview,
      matching: find.byType(AnimatedContainer),
    );
    final previewBorder = borderColor(previewFrame);
    await mouse.moveTo(tester.getCenter(preview));
    await tester.pumpAndSettle();
    expect(borderColor(previewFrame), isNot(previewBorder));

    final outfitIcon = find.byKey(
      const ValueKey('asset-character-outfit-icon-char-hover-casual'),
    );
    final outfitIconFrame = find.descendant(
      of: outfitIcon,
      matching: find.byType(AnimatedContainer),
    );
    final outfitIconBorder = borderColor(outfitIconFrame);
    await mouse.moveTo(tester.getCenter(outfitIcon));
    await tester.pumpAndSettle();
    expect(borderColor(outfitIconFrame), isNot(outfitIconBorder));

    final addOutfit = find.byKey(const ValueKey('asset-detail-add-outfit'));
    final addOutfitFrame = find.descendant(
      of: addOutfit,
      matching: find.byType(AnimatedContainer),
    );
    final addOutfitBorder = borderColor(addOutfitFrame);
    await mouse.moveTo(tester.getCenter(addOutfit));
    await tester.pumpAndSettle();
    expect(borderColor(addOutfitFrame), isNot(addOutfitBorder));
  });

  testWidgets('character detail outfit preview uses the outfit image refs',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    final tempDir =
        Directory.systemTemp.createTempSync('asset-outfit-preview-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final outfitPreview =
        File('${tempDir.path}${Platform.pathSeparator}outfit-preview.png');
    outfitPreview.writeAsBytesSync(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    final catalog = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 1,
        outfitCount: 1,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [
        CharacterEntry(
          id: 'char-preview',
          name: '棰勮瑙掕壊',
          traits: ViewVariantTexts(frontFull: 'green eyes'),
          outfits: [
            WorkspaceOutfit(
              id: 'uniform',
              name: '制服',
              tags: ViewVariantTexts(frontFull: 'navy uniform'),
              imageRefs: ['refs/outfit-detail.png'],
            ),
          ],
        ),
      ],
      artistChains: const [],
      recipes: const [],
      tags: const [],
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalog: catalog,
        resolvedRefs: {'refs/outfit-detail.png': outfitPreview.path},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-preview')),
    );
    await tester.pumpAndSettle();

    final previewImage = tester.widget<Image>(
      find.byKey(
        const ValueKey(
          'asset-character-outfit-preview-image-char-preview-uniform',
        ),
      ),
    );

    _expectResizedFileImage(previewImage, outfitPreview.path);
  });

  testWidgets(
      'asset library detail dialog can send the selected asset to workbench',
      (tester) async {
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);

    await tester.pumpWidget(page(config: config, service: service));
    await tester.pumpAndSettle();

    final characterCard =
        find.byKey(const ValueKey('asset-card-character-char-1'));
    await tester.ensureVisible(characterCard);
    await tester.tap(characterCard);
    await tester.pumpAndSettle();
    final detailSend = find.byKey(const ValueKey('asset-detail-send'));
    await tester.ensureVisible(detailSend);
    await tester.tap(detailSend);
    await tester.pump();

    expect(config.useOverridePrompt, isTrue);
    expect(config.overridePrompt, 'silver hair, blue eyes');
    expect(service.fragments.single.typeLabel, '角色');
    expect(find.text('已发送到工作台'), findsOneWidget);
  });

  testWidgets('asset waterfall cards use ZZZ card shape and outline',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    final card = tester.widget<Material>(
      find.byKey(const ValueKey('asset-card-character-char-1')),
    );
    final shape = card.shape as RoundedRectangleBorder;

    expect(shape.borderRadius, StudioTokens.radiusCard);
    expect(shape.side.color, StudioTokens.cardOutline);
  });

  testWidgets('asset library surfaces recipe and tag without block chips',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('asset-block-filter-style')), findsNothing);
    expect(
        find.byKey(const ValueKey('asset-block-filter-scene')), findsNothing);
    expect(find.text('雨夜街道'), findsOneWidget);
    expect(find.text('雨街'), findsOneWidget);
  });

  testWidgets('asset library surfaces non-basic assets for browsing',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config, catalog: nonBasicSnapshot));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-filter-inspiration')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('asset-filter-codex')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-filter-lora')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-filter-workflow')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-filter-batch-plan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-filter-assembly-preset')),
      findsOneWidget,
    );

    expect(find.text('Night Alley'), findsOneWidget);
    expect(find.text('西幻'), findsNothing);
    expect(find.text('SoftRain'), findsOneWidget);
    expect(find.text('City Stack'), findsOneWidget);
    expect(find.text('Night Queue'), findsNothing);
    expect(find.text('City Assembly'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-card-inspiration-night-alley')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0001'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-lora-soft-rain')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-workflow-city-stack')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-batch-plan-night-queue')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-assembly-preset-city-assembly')),
      findsOneWidget,
    );

    final workflowCard =
        find.byKey(const ValueKey('asset-card-workflow-city-stack'));
    await tester.ensureVisible(workflowCard);
    await tester.tap(workflowCard);
    await tester.pumpAndSettle();

    expect(find.text('character plus neon city pass'), findsWidgets);
    expect(find.text('data/workflows/city_stack.json'), findsNothing);

    final detailSend = tester.widget<StudioButton>(
      find.byKey(const ValueKey('asset-detail-send')),
    );
    expect(detailSend.onPressed, isNull);
  });

  testWidgets('asset library filters non-basic assets by new type chip',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config, catalog: nonBasicSnapshot));
    await tester.pumpAndSettle();

    final loraFilter = find.byKey(const ValueKey('asset-filter-lora'));
    await tester.ensureVisible(loraFilter);
    await tester.tap(loraFilter);
    await tester.pumpAndSettle();

    expect(find.text('SoftRain'), findsOneWidget);
    expect(find.text('Night Alley'), findsNothing);
    expect(find.text('City Stack'), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-card-lora-soft-rain')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-workflow-city-stack')),
      findsNothing,
    );
  });

  testWidgets('asset library exposes legacy codex as a dedicated 法典 filter',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config, catalog: nonBasicSnapshot));
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    expect(find.text('西幻'), findsOneWidget);
    expect(find.text('法典'), findsWidgets);
    expect(find.text('Night Alley'), findsNothing);
    expect(find.text('SoftRain'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0001'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-inspiration-night-alley')),
      findsNothing,
    );
  });

  testWidgets('asset library renders no-preview codex as compact cards',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config, catalog: nonBasicSnapshot));
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'asset-card-preview-inspiration-legacy-codex-regular-0001',
        ),
      ),
      findsNothing,
    );
    final codexCard = find.byKey(
      const ValueKey('asset-card-inspiration-legacy-codex-regular-0001'),
    );
    expect(
      find.descendant(of: codexCard, matching: find.byType(PromptTagDisplay)),
      findsNothing,
    );
    await tester.ensureVisible(codexCard);
    await tester.tap(codexCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-prompt-tag-display')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'asset-detail-preview-empty-inspiration-legacy-codex-regular-0001',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('asset library defers codex loading until the codex filter',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(nonBasicSnapshot);

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    expect(catalogService.includeLegacyCodexRequests, [false]);
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0001'),
      ),
      findsNothing,
    );

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    expect(catalogService.includeLegacyCodexRequests.first, isFalse);
    expect(
      catalogService.includeLegacyCodexRequests.skip(1),
      everyElement(isTrue),
    );
    expect(catalogService.legacyCodexLimitRequests[1], 48);
    expect(
      catalogService.legacyCodexCategoryKeyRequests[1],
      StudioLegacyCodexCategories.requestKey(
        sourceScopeKey: StudioLegacyCodexCategories.sourceRegularKey,
        categoryKey: StudioLegacyCodexCategories.allKey,
      ),
    );
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0001'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asset library treats imported NovelAI codex as codex assets',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(
      StudioAssetCatalogSnapshot(
        summary: const StudioAssetCatalogSummary(
          characterCount: 0,
          artistChainCount: 0,
          recipeCount: 0,
          tagCount: 0,
          inspirationCount: 2,
          recipeCountsByBlock: {},
          tagCountsByBlock: {},
        ),
        characters: const [],
        artistChains: const [],
        recipes: const [],
        tags: const [],
        inspirations: const [
          InspirationEntry(
            id: 'mood-board',
            name: 'Mood Board',
            prompt: 'quiet interior, window light',
          ),
          InspirationEntry(
            id: 'adult-codex-0001',
            name: 'Imported Codex',
            prompt: 'cinematic lighting, solo',
            source: SourceRef(type: 'novalai_codex_adult_docx'),
          ),
        ],
        legacyCodexAvailable: true,
      ),
    );

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mood Board'), findsOneWidget);
    expect(find.text('Imported Codex'), findsNothing);

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    expect(find.text('Mood Board'), findsNothing);
    expect(find.text('Imported Codex'), findsNothing);

    final adultSource = find.byKey(const ValueKey('asset-codex-source-adult'));
    await tester.ensureVisible(adultSource);
    await tester.tap(adultSource);
    await tester.pumpAndSettle();

    expect(find.text('Mood Board'), findsNothing);
    expect(find.text('Imported Codex'), findsOneWidget);
  });

  testWidgets('asset library shows codex filter before codex entries load',
      (tester) async {
    final config = payload();
    final catalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        batchPlanCount: 1,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
      batchPlans: [
        BatchPlan(
          id: 'tokenizer-queue-1',
          name: '分词任务',
          items: const [
            {'shot': 'close'},
          ],
          statusSnapshot: const {
            'queued': 1,
          },
          createdAt: DateTime(2026, 6, 3),
          updatedAt: DateTime(2026, 6, 3),
        ),
      ],
      legacyCodexAvailable: true,
    );

    await tester.pumpWidget(page(config: config, catalog: catalog));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-filter-codex')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-filter-batch-plan')),
      findsOneWidget,
    );
    expect(find.text('分词任务'), findsNothing);

    final batchPlanFilter =
        find.byKey(const ValueKey('asset-filter-batch-plan'));
    await tester.ensureVisible(batchPlanFilter);
    await tester.tap(batchPlanFilter);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('asset-card-batch-plan-tokenizer-queue-1')),
        findsOneWidget);
    expect(find.text('分词任务'), findsOneWidget);
  });

  testWidgets('asset library filters legacy codex by finer category chips',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config, catalog: nonBasicSnapshot));
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    final styleCategory =
        find.byKey(const ValueKey('asset-codex-category-artist-style'));
    expect(styleCategory, findsOneWidget);
    expect(find.byKey(const ValueKey('asset-codex-category-general')),
        findsOneWidget);

    await tester.tap(styleCategory);
    await tester.pumpAndSettle();

    expect(find.text('西幻'), findsOneWidget);
    expect(find.text('法典条目 2'), findsNothing);
    expect(find.text('匹配素材 1'), findsOneWidget);
  });

  testWidgets('asset library progressively fills large codex after opening',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = payload();
    final largeCodexSnapshot = StudioAssetCatalogSnapshot(
      summary: const StudioAssetCatalogSummary(
        characterCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        inspirationCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: const [],
      artistChains: const [],
      recipes: const [],
      tags: const [],
      inspirations: [
        for (var index = 1; index <= 500; index++)
          InspirationEntry(
            id: 'legacy-codex-regular-${index.toString().padLeft(4, '0')}',
            name: '法典条目 $index',
            prompt: 'codex prompt $index',
            tags: const ['法典', '常规'],
            source: SourceRef(
              type: 'legacy_codex',
              id: 'regular.docx#p$index',
            ),
          ),
      ],
      legacyCodexAvailable: true,
    );
    final catalogService = _FakeCatalogService(largeCodexSnapshot);

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    final codexFilter = find.byKey(const ValueKey('asset-filter-codex'));
    await tester.ensureVisible(codexFilter);
    await tester.tap(codexFilter);
    await tester.pumpAndSettle();

    expect(catalogService.includeLegacyCodexRequests,
        [false, true, true, true, true]);
    expect(catalogService.legacyCodexLimitRequests, [48, 48, 208, 368, 500]);
    expect(find.textContaining('48/500'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0001'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0500'),
      ),
      findsNothing,
    );
  });
}

void _expectResizedFileImage(Image image, String expectedPath) {
  expect(image.image, isA<ResizeImage>());
  final resizeImage = image.image as ResizeImage;
  expect(resizeImage.width, isNotNull);
  expect(resizeImage.height, isNotNull);
  expect(resizeImage.width, lessThanOrEqualTo(1024));
  expect(resizeImage.height, lessThanOrEqualTo(1024));
  expect(
    resizeImage.imageProvider,
    isA<FileImage>().having(
      (provider) => provider.file.path,
      'file path',
      expectedPath,
    ),
  );
}
