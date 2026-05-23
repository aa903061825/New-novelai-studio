import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/asset_library_page.dart';

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService(this.snapshot)
      : super(workspaceService: WorkspaceService());

  final StudioAssetCatalogSnapshot snapshot;

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot() async => snapshot;
}

void main() {
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
        traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
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

  final nonBasicSnapshot = StudioAssetCatalogSnapshot(
    summary: StudioAssetCatalogSummary(
      characterCount: 0,
      artistChainCount: 0,
      recipeCount: 0,
      tagCount: 0,
      inspirationCount: 1,
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
    StudioAssetCatalogSnapshot catalog = snapshot,
  }) {
    return MaterialApp(
      theme: StudioTheme.build(),
      home: AssetLibraryPage(
        catalogService: _FakeCatalogService(catalog),
        workbenchAssetService: service ??
            StudioWorkbenchAssetService(
              payloadConfig: config,
            ),
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
    expect(find.text('雨披'), findsWidgets);
    expect(find.text('水彩柔光'), findsOneWidget);
    expect(find.text('雨夜街道'), findsOneWidget);
    expect(find.text('雨街'), findsOneWidget);
    expect(find.textContaining('silver hair'), findsOneWidget);
    expect(find.byTooltip('发送到工作台'), findsNWidgets(5));
    expect(find.textContaining('style'), findsWidgets);
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-artist-artist-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-recipe-style-recipe-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-tag-scene-tag-1')),
      findsOneWidget,
    );
    expect(find.text('引用待检查'), findsOneWidget);
  });

  testWidgets('asset library page can send a selected asset to workbench',
      (tester) async {
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);

    await tester.pumpWidget(page(config: config, service: service));
    await tester.pumpAndSettle();

    final sendButton =
        find.byKey(const ValueKey('asset-card-send-character-char-1'));
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

    expect(find.text('雨披'), findsWidgets);
    expect(find.text('水彩柔光'), findsNothing);
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

  testWidgets(
      'asset library opens a detail drawer for the selected waterfall card',
      (tester) async {
    final config = payload();

    await tester.pumpWidget(page(config: config));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-card-character-char-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-library-detail-drawer')),
      findsOneWidget,
    );
    expect(find.text('素材详情'), findsOneWidget);
    expect(find.text('char-1'), findsOneWidget);
    expect(find.text('kamia'), findsOneWidget);
    expect(find.text('characters/lixia.json'), findsOneWidget);
    expect(find.text('主角素材'), findsOneWidget);
    expect(find.text('refs/lixia.png'), findsOneWidget);
  });

  testWidgets(
      'asset library detail drawer can send the selected asset to workbench',
      (tester) async {
    final config = payload();
    final service = StudioWorkbenchAssetService(payloadConfig: config);

    await tester.pumpWidget(page(config: config, service: service));
    await tester.pumpAndSettle();

    final tagCard = find.byKey(const ValueKey('asset-card-tag-scene-tag-1'));
    await tester.ensureVisible(tagCard);
    await tester.tap(tagCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-send')));
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
    expect(find.text('SoftRain'), findsOneWidget);
    expect(find.text('City Stack'), findsOneWidget);
    expect(find.text('Night Queue'), findsOneWidget);
    expect(find.text('City Assembly'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('asset-card-inspiration-night-alley')),
      findsOneWidget,
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('asset-card-assembly-preset-city-assembly')),
      findsOneWidget,
    );

    final workflowSend = tester.widget<StudioIconButton>(
      find.byKey(const ValueKey('asset-card-send-workflow-city-stack')),
    );
    expect(workflowSend.onPressed, isNull);

    final workflowCard =
        find.byKey(const ValueKey('asset-card-workflow-city-stack'));
    await tester.ensureVisible(workflowCard);
    await tester.tap(workflowCard);
    await tester.pumpAndSettle();

    expect(find.text('character plus neon city pass'), findsWidgets);
    expect(find.text('data/workflows/city_stack.json'), findsOneWidget);

    final drawerSend = tester.widget<StudioIconButton>(
      find.byKey(const ValueKey('asset-detail-send')),
    );
    expect(drawerSend.onPressed, isNull);
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
}
