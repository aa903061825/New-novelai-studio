import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/asset_tag_cache_prewarm_service.dart';
import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/asset_library_page.dart';

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
  int resolveImagePathCallCount = 0;

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
  }) async {
    includeLegacyCodexRequests.add(includeLegacyCodex);
    legacyCodexLimitRequests.add(legacyCodexLimit);
    if (includeLegacyCodex) {
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
        if (normalizedQuery.isEmpty) return true;
        return [entry.name, entry.prompt, entry.tags.join(' ')]
            .join('\n')
            .toLowerCase()
            .contains(normalizedQuery);
      }).toList(growable: false);
      final categoryCounts =
          StudioLegacyCodexCategories.countByCategory(queryMatchedCodex);
      final normalizedCategory =
          StudioLegacyCodexCategories.normalizedKey(legacyCodexCategoryKey);
      final codex = normalizedCategory == StudioLegacyCodexCategories.allKey
          ? queryMatchedCodex
          : queryMatchedCodex
              .where(
                (entry) => StudioLegacyCodexCategories.matches(
                    entry, normalizedCategory),
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
  }) : super(
          workspaceService: WorkspaceService(),
          requestImage: (_) async => Uint8List(0),
          saveImage: (_, __) async => 'preview.png',
        );

  final List<String> characterIds = [];
  final List<String> artistChainIds = [];
  final void Function(String id)? onGenerateCharacterPreview;
  int characterFailuresRemaining = 0;
  int artistChainFailuresRemaining = 0;

  @override
  Future<String> generateCharacterPreview(String id) async {
    characterIds.add(id);
    if (characterFailuresRemaining > 0) {
      characterFailuresRemaining -= 1;
      throw StateError('character preview failed');
    }
    onGenerateCharacterPreview?.call(id);
    return 'generated-character-$id.png';
  }

  @override
  Future<String> generateArtistChainPreview(String id) async {
    artistChainIds.add(id);
    if (artistChainFailuresRemaining > 0) {
      artistChainFailuresRemaining -= 1;
      throw StateError('artist preview failed');
    }
    return 'generated-artist-$id.png';
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
          type: 'kamia',
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
          type: 'kamia',
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
          type: 'kamia',
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
          type: 'kamia',
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
          type: 'kamia',
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
    AssetTagCachePrewarmService? tagCachePrewarmService,
    StudioAssetPreviewGenerationService? previewGenerationService,
    StudioAssetCatalogSnapshot catalog = snapshot,
    Map<String, String> resolvedRefs = const {},
    ValueChanged<StudioScriptAssetFocus>? onSendToScript,
    Future<List<WorkspaceVibeReference>> Function()? loadVibes,
    Future<List<WorkspaceVibeReference>> Function()? importVibes,
    Future<void> Function(List<ArtistChain>)? saveArtistChains,
    Future<void> Function(List<CharacterEntry>)? saveCharacters,
    Future<void> Function(String, List<TagEntry>)? saveTags,
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
        tagCachePrewarmService: tagCachePrewarmService,
        previewGenerationService: previewGenerationService,
        onSendToScript: onSendToScript,
        loadVibes: loadVibes,
        importVibes: importVibes,
        saveArtistChains: saveArtistChains,
        saveCharacters: saveCharacters,
        saveTags: saveTags,
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
    expect(find.text('匹配素材 4'), findsOneWidget);
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
      find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-filter-outfit')),
      findsNothing,
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

  testWidgets('asset waterfall cards only show preview and name before opening',
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
      find.byKey(const ValueKey('asset-card-preview-artist-artist-1')),
      findsOneWidget,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('asset-detail-dialog-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-artist-artist-1')));
    await tester.pumpAndSettle();
    final artistButton = find.byKey(
      const ValueKey('asset-detail-generate-preview-artistChain-artist-1'),
    );
    await tester.ensureVisible(artistButton);
    await tester.tap(artistButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(previewService.characterIds, ['char-1']);
    expect(previewService.artistChainIds, ['artist-1']);
    expect(find.text('新增预览'), findsWidgets);
    expect(find.byTooltip('Generate preview'), findsNothing);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('预览图生成失败'), findsOneWidget);

    await tester.tap(characterButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(previewService.characterIds, ['char-refresh']);
    expect(
      find.byKey(
        const ValueKey('asset-detail-preview-image-character-char-refresh'),
      ),
      findsOneWidget,
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

  testWidgets('asset library favorites pin cards and can be cleared',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = payload();
    const tagCatalog = StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 2,
        recipeCountsByBlock: {},
        tagCountsByBlock: {'scene': 2},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [
        TagEntry(id: 'tag-1', tag: 'rainy street', block: 'scene'),
        TagEntry(id: 'tag-2', tag: 'moonlit roof', block: 'scene'),
      ],
    );
    final catalogService = _FakeCatalogService(tagCatalog);

    await tester.pumpWidget(
      page(
        config: config,
        catalog: tagCatalog,
        catalogService: catalogService,
      ),
    );
    await tester.pumpAndSettle();

    final firstCard = find.byKey(const ValueKey('asset-card-tag-scene-tag-1'));
    final secondCard = find.byKey(const ValueKey('asset-card-tag-scene-tag-2'));
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
    expect(catalogService.favoriteKeys, contains('tag:scene/tag-2'));
    expect(
      tester.getTopLeft(secondCard).dy,
      lessThan(tester.getTopLeft(firstCard).dy),
    );

    await tester.ensureVisible(secondCard);
    await tester.tap(secondCard);
    await tester.pumpAndSettle();
    await tester.tap(secondFavorite);
    await tester.pumpAndSettle();

    expect(catalogService.favoriteKeys, isNot(contains('tag:scene/tag-2')));
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getTopLeft(secondCard).dy),
    );
  });

  testWidgets('favorite cards stay scoped to the selected asset filter',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(
      snapshot,
      favoriteKeys: {
        StudioAssetFavoriteKeys.character('char-1'),
      },
    );

    await tester.pumpWidget(
      page(config: config, catalogService: catalogService),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-card-character-char-1')),
      findsOneWidget,
    );

    final artistFilter =
        find.byKey(const ValueKey('asset-filter-artist-chain'));
    await tester.ensureVisible(artistFilter);
    await tester.tap(artistFilter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-card-character-char-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsOneWidget,
    );
  });

  testWidgets('asset waterfall prompt cards do not translate by default',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    expect(find.textContaining('silver hair, blue eyes'), findsNothing);
    expect(find.text('silver hair'), findsNothing);
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('银发'), findsNothing);
    expect(find.text('蓝眼睛'), findsNothing);
  });

  testWidgets('asset prompt previews skip redundant single grouped blocks',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-group-character')),
      findsNothing,
    );
    expect(find.textContaining('silver hair, blue eyes'), findsNothing);
    expect(find.text('silver hair'), findsNothing);
    expect(find.text('blue eyes'), findsNothing);
  });

  testWidgets('asset library prewarms tag translation and grouping caches',
      (tester) async {
    final config = payload();
    final catalogService = _FakeCatalogService(snapshot);
    final translationCache = TranslationCache(clock: () => 1710000000)
      ..setManual('blue eyes', 'cached-blue-eyes');
    final classificationCache = PromptTagClassificationCache(
      clock: () => 1710000000,
    );
    final service = AssetTagCachePrewarmService(
      catalogService: catalogService,
      translationService: _FakePromptTranslationService((request) async {
        return OnlineTranslationResult(
          text: 'zh:${request.text}',
          source: OnlineAiResultSource.online,
          providerName: 'fake-ai',
        );
      }),
      translationCache: translationCache,
      classificationCache: classificationCache,
      saveTranslationCache: (_) async {},
      saveClassificationCache: (_) async {},
    );

    await tester.pumpWidget(
      page(
        config: config,
        catalogService: catalogService,
        tagCachePrewarmService: service,
      ),
    );
    await tester.pumpAndSettle();

    final button =
        find.byKey(const ValueKey('asset-library-prewarm-tag-cache'));
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(translationCache.getCached('silver hair'), 'zh:silver hair');
    expect(translationCache.getCached('blue eyes'), 'cached-blue-eyes');
    expect(classificationCache.entryFor('silver hair'), isNull);
    expect(
      find.byKey(const ValueKey('asset-library-tag-cache-prewarm-status')),
      findsOneWidget,
    );
    expect(find.textContaining('缓存预热完成'), findsOneWidget);
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

    await tester.tap(
      find.byKey(const ValueKey('asset-card-character-char-multi')),
    );
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

    await tester
        .tap(find.byKey(const ValueKey('asset-card-artist-multi-preview')));
    await tester.pumpAndSettle();
    final preview =
        find.byKey(const ValueKey('asset-detail-preview-artist-multi-preview'));
    await tester.ensureVisible(preview);
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
    expect(find.byKey(const ValueKey('asset-preview-carousel-dot-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('asset-preview-carousel-dot-1')),
        findsOneWidget);

    final counter =
        find.byKey(const ValueKey('asset-preview-carousel-counter'));
    final before = tester.widget<Text>(counter).data;
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(300, 300),
        scrollDelta: Offset(0, 120),
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
    final tempDir = Directory.systemTemp.createTempSync('asset-ratio-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final portrait = File('${tempDir.path}${Platform.pathSeparator}tall.png');
    portrait
        .writeAsBytesSync(img.encodePng(img.Image(width: 600, height: 1200)));
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
        resolvedRefs: {'preview/tall.png': portrait.path},
      ),
    );
    await tester.pumpAndSettle();

    final preview = find.byKey(
      const ValueKey('asset-card-preview-artist-tall-preview'),
    );
    final previewSize = tester.getSize(preview);

    expect(previewSize.width / previewSize.height, closeTo(0.5, 0.03));
    expect(
      find.byKey(
        const ValueKey('asset-card-preview-image-artist-tall-preview'),
      ),
      findsOneWidget,
    );
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
    final addCategoryButton =
        find.byKey(const ValueKey('asset-library-add-custom-category'));
    final artistFilter =
        find.byKey(const ValueKey('asset-filter-artist-chain'));

    expect(gallery, findsOneWidget);
    expect(
        find.byKey(const ValueKey('asset-filter-primary-row')), findsNothing);
    expect(allFilter, findsOneWidget);
    expect(characterFilter, findsOneWidget);
    expect(artistFilter, findsOneWidget);
    expect(addCategoryButton, findsOneWidget);
    expect(tester.getSize(allFilter).height, greaterThanOrEqualTo(72));
    expect(
      tester.getTopLeft(addCategoryButton).dx,
      greaterThan(tester.getTopLeft(artistFilter).dx),
    );
    expect(find.byKey(const ValueKey('asset-filter-outfit')), findsNothing);
    expect(find.byKey(const ValueKey('asset-filter-tag')), findsOneWidget);
  });

  testWidgets('asset library can add a custom category filter name',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-custom-category-weather')),
        findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('asset-library-add-custom-category')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('asset-library-custom-category-input')),
      'weather',
    );
    await tester.tap(
      find.byKey(const ValueKey('asset-library-save-custom-category')),
    );
    await tester.pumpAndSettle();

    final customFilter =
        find.byKey(const ValueKey('asset-custom-category-weather'));
    expect(customFilter, findsOneWidget);

    await tester.tap(customFilter);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-card-tag-scene-tag-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-character-char-1')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('asset-card-artist-artist-1')), findsNothing);
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

    expect(find.text('匹配素材 1'), findsOneWidget);
    expect(find.text('璃夏'), findsWidgets);
    expect(find.text('水彩柔光'), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-card-character-char-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('asset-library-search')),
      '',
    );
    final tagFilter = find.byKey(const ValueKey('asset-filter-tag'));
    await tester.ensureVisible(tagFilter);
    await tester.tap(tagFilter);
    await tester.pumpAndSettle();

    expect(find.text('雨街'), findsOneWidget);
    expect(find.text('雨披'), findsNothing);
    expect(find.text('水彩柔光'), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-card-tag-scene-tag-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-outfit-char-1-outfit-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsNothing,
    );
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

    expect(
      find.byKey(const ValueKey('asset-card-tag-scene-tag-0')),
      findsOneWidget,
    );
    expect(
      catalogService.resolveImagePathCallCount,
      lessThan(tagCount ~/ 2),
    );
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
    expect(find.textContaining('kamia'), findsNothing);
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
    expect(find.text('1 张'), findsOneWidget);
    expect(find.text('2 条'), findsOneWidget);
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
    expect(find.text('blue eyes'), findsWidgets);
    expect(find.text('fox tail'), findsWidgets);
    expect(find.text('yellow rain coat'), findsWidgets);
    expect(find.text('yellow jacket'), findsWidgets);
    expect(find.text('rain skirt'), findsWidgets);
    expect(
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-character-char-1-upper-body'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-detail-prompt-editor-character-char-1-lower-body'),
      ),
      findsOneWidget,
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
    final editorPane = find.byKey(
      const ValueKey('asset-detail-editor-pane-character-char-1'),
    );

    expect(tester.getSize(dialog).width, lessThanOrEqualTo(1220));
    expect(tester.getSize(editorPane).width, inInclusiveRange(420, 640));
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

    await tester.tap(
      find.byKey(const ValueKey('asset-library-add-artist-chain')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Manual Painter',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-prompt-field')),
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
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-prompt-field')),
      'artist:manual, sunset palette',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedArtistChains.single.prompt, 'artist:manual, sunset palette');
    expect(savedArtistChains.single.tags, ['artist:manual', 'sunset palette']);

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

  testWidgets('asset library can create manual characters and prompt tags',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<CharacterEntry> savedCharacters = const [];
    List<TagEntry> savedTags = const [];
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
        saveTags: (block, tags) async {
          savedTags = tags;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-library-add-character')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-name-field')),
      'Manual Hero',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-prompt-field')),
      '1girl, girl, loli, silver hair, blue cape',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters, hasLength(1));
    expect(savedCharacters.single.name, 'Manual Hero');
    expect(
      savedCharacters.single.traits.frontFull,
      '1girl, girl, loli, silver hair, blue cape',
    );
    expect(
      savedCharacters.single.identityTags,
      ['girl', 'loli', 'silver hair', 'blue cape'],
    );
    expect(savedCharacters.single.identityTags, isNot(contains('1girl')));
    expect(savedCharacters.single.identityTags, containsAll(['girl', 'loli']));
    expect(savedCharacters.single.anchorTags, isEmpty);

    await tester.tap(find.byKey(const ValueKey('asset-library-add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-tag-field')),
      'floating lanterns',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedTags, hasLength(1));
    expect(savedTags.single.tag, 'floating lanterns');
    expect(savedTags.single.block, 'style');
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
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-prompt-field')),
      'edited full, silver hair, blue cape',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-front-upper-field')),
      'edited upper',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-front-lower-field')),
      'edited lower',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-anchor-tags-field')),
      'hero anchor, explicit anchor',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-identity-tags-field')),
      'manual identity, silver hair',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-aliases-field')),
      'Hero, Li Xia',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-image-refs-field')),
      'refs/new.png\nrefs/second.png',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-character-editor-note-field')),
      'manual note',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters, hasLength(1));
    final character = savedCharacters.single;
    expect(character.name, 'Edited Hero');
    expect(character.traits.frontFull, 'edited full, silver hair, blue cape');
    expect(character.traits.frontUpper, 'edited upper');
    expect(character.traits.frontLower, 'edited lower');
    expect(character.anchorTags, ['hero anchor', 'explicit anchor']);
    expect(character.identityTags, ['manual identity', 'silver hair']);
    expect(character.aliases, ['Hero', 'Li Xia']);
    expect(character.imageRefs, ['refs/new.png', 'refs/second.png']);
    expect(character.note, 'manual note');
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

  testWidgets('asset detail edits structured character and outfit tag fields',
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

    final characterUpperEditor = find.byKey(
      const ValueKey('asset-detail-prompt-editor-character-char-1-upper-body'),
    );
    expect(characterUpperEditor, findsOneWidget);
    await _addPromptTags(tester, characterUpperEditor, 'white ribbon');

    expect(savedCharacters, hasLength(1));
    expect(savedCharacters.single.traits.frontUpper, 'blue eyes, white ribbon');

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

  testWidgets('asset detail shows each outfit as five fixed tag fields only',
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
          traits: ViewVariantTexts(frontFull: 'base identity'),
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
      findsOneWidget,
    );
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

  testWidgets('asset detail edits selected outfit prompt tags inline',
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

    final outfitEditor = find.byKey(
      const ValueKey('asset-detail-prompt-editor-character-char-1-outfit-0'),
    );
    expect(outfitEditor, findsOneWidget);
    await _addPromptTags(tester, outfitEditor, 'muddy boots');

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
    await tester.enterText(
      find.byKey(const ValueKey('asset-outfit-editor-prompt-field')),
      'black cloak, boots',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-outfit-editor-front-upper-field')),
      'black cloak',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-outfit-editor-front-lower-field')),
      'boots',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('asset-outfit-editor-upper-clothing-tags-field'),
      ),
      'black cloak',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('asset-outfit-editor-lower-clothing-tags-field'),
      ),
      'boots',
    );
    await tester.tap(find.byKey(const ValueKey('asset-outfit-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters.single.outfits.map((outfit) => outfit.id), [
      'outfit-1',
      'outfit-travel-cloak',
    ]);
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
    await tester.enterText(
      find.byKey(const ValueKey('asset-outfit-editor-prompt-field')),
      'white cloak, leather boots',
    );
    await tester.tap(find.byKey(const ValueKey('asset-outfit-editor-save')));
    await tester.pumpAndSettle();

    expect(savedCharacters.single.outfits.last.tags.frontFull,
        'white cloak, leather boots');

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
      findsNothing,
    );
    expect(find.text('silver hair'), findsWidgets);
    expect(find.text('blue eyes'), findsWidgets);
    expect(find.text('yellow rain coat'), findsWidgets);
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
    uniformPreview.writeAsBytesSync(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    casualPreviewFile.writeAsBytesSync(
      img.encodePng(img.Image(width: 480, height: 320)),
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
              imageRefs: ['refs/casual.png'],
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
          'refs/uniform.png': uniformPreview.path,
          'refs/casual.png': casualPreviewFile.path,
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
    expect(
      casualImage.image,
      isA<FileImage>().having(
        (provider) => provider.file.path,
        'file path',
        casualPreviewFile.path,
      ),
    );

    final casualPreview = find.byKey(
      const ValueKey('asset-character-outfit-preview-char-multi-casual'),
    );
    await tester.ensureVisible(casualPreview);
    await tester.tap(casualPreview);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('asset-preview-carousel-outfit-char-multi-casual'),
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
              name: '鍒舵湇',
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

    expect(
      previewImage.image,
      isA<FileImage>().having(
        (provider) => provider.file.path,
        'file path',
        outfitPreview.path,
      ),
    );
  });

  testWidgets(
      'asset library detail dialog can send the selected asset to workbench',
      (tester) async {
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);

    await tester.pumpWidget(page(config: config, service: service));
    await tester.pumpAndSettle();

    final tagCard = find.byKey(const ValueKey('asset-card-tag-scene-tag-1'));
    await tester.ensureVisible(tagCard);
    await tester.tapAt(tester.getTopLeft(tagCard) + const Offset(24, 96));
    await tester.pumpAndSettle();
    final detailSend = find.byKey(const ValueKey('asset-detail-send'));
    await tester.ensureVisible(detailSend);
    await tester.tap(detailSend);
    await tester.pump();

    expect(config.useOverridePrompt, isTrue);
    expect(config.overridePrompt, 'rainy street');
    expect(service.fragments.single.typeLabel, 'Tag');
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

  testWidgets('asset library filters recipes and tags by block chip',
      (tester) async {
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

  testWidgets('asset library surfaces non-basic KAMIA assets for browsing',
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
      findsNothing,
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
    expect(catalogService.legacyCodexLimitRequests[1], 160);
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
      findsNothing,
    );
    expect(find.text('分词任务'), findsNothing);
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

  testWidgets('asset library keeps legacy codex paged until the user scrolls',
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

    expect(catalogService.includeLegacyCodexRequests, [false, true]);
    expect(catalogService.legacyCodexLimitRequests, [160, 160]);

    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0160'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0161'),
      ),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey('asset-library-scroll')),
      const Offset(0, -50000),
    );
    await tester.pumpAndSettle();

    expect(catalogService.includeLegacyCodexRequests, [false, true, true]);
    expect(catalogService.legacyCodexLimitRequests, [160, 160, 320]);
    expect(
      find.byKey(
        const ValueKey('asset-card-inspiration-legacy-codex-regular-0320'),
      ),
      findsOneWidget,
    );
  });
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
    return handler(request);
  }
}
