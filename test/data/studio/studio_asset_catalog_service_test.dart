import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WorkspaceService workspaceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('asset-catalog-test-');
    workspaceService = WorkspaceService();
    await workspaceService.createWorkspace(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'loadSummary counts internal character, outfit, artist, recipe, and tag assets',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
        outfits: [
          WorkspaceOutfit(
            id: 'outfit-1',
            name: 'Rain Coat',
            tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
          ),
        ],
      ),
    ]);
    await workspaceService.saveArtistChains([
      const ArtistChain(id: 'artist-1', name: 'Painter', tags: ['soft light']),
    ]);
    await workspaceService.saveRecipes('style', [
      const Recipe(id: 'recipe-1', name: 'Watercolor', block: 'style'),
      const Recipe(id: 'recipe-2', name: 'Ink', block: 'style'),
    ]);
    await workspaceService.saveTags('scene', [
      const TagEntry(id: 'tag-1', tag: 'rainy street', block: 'scene'),
    ]);
    await workspaceService.saveInspirations([
      const InspirationEntry(
        id: 'insp-1',
        name: 'Night Alley',
        prompt: 'rainy alley',
      ),
    ]);
    await workspaceService.saveLoras([
      const LoraEntry(
        id: 'lora-1',
        name: 'SoftRain',
        triggerWords: ['softrain'],
      ),
    ]);
    await workspaceService.saveWorkflows([
      const WorkflowEntry(
        id: 'workflow-1',
        name: 'City Stack',
      ),
    ]);
    await workspaceService.saveBatchPlans([
      BatchPlan(
        id: 'batch-1',
        name: 'Night Queue',
        createdAt: DateTime.parse('2026-05-23T00:00:00Z'),
        updatedAt: DateTime.parse('2026-05-23T00:00:00Z'),
      ),
    ]);
    await workspaceService.saveAssemblyPresets([
      const AssemblyPresetEntry(
        id: 'assembly-1',
        name: 'City Assembly',
      ),
    ]);

    final summary = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSummary();

    expect(summary.characterCount, 1);
    expect(summary.outfitCount, 1);
    expect(summary.artistChainCount, 1);
    expect(summary.recipeCount, 2);
    expect(summary.tagCount, 1);
    expect(summary.inspirationCount, 1);
    expect(summary.loraCount, 1);
    expect(summary.workflowCount, 1);
    expect(summary.batchPlanCount, 1);
    expect(summary.assemblyPresetCount, 1);
    expect(summary.totalAssetCount, 10);
    expect(summary.recipeCountsByBlock['style'], 2);
    expect(summary.tagCountsByBlock['scene'], 1);
  });

  test('character prompts without explicit outfits do not create outfit assets',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-default',
        name: 'Heroine',
        traits: ViewVariantTexts(
          frontFull: 'heroine identity',
          frontUpper: 'silver hair, white blouse',
          frontLower: 'fox tail, pleated skirt',
        ),
        imageRefs: ['refs/heroine.png'],
      ),
    ]);

    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
    );
    final summary = await service.loadSummary();
    final snapshot = await service.loadSnapshot();
    final outfits = await service.loadWorkbenchOutfits();

    expect(summary.outfitCount, 0);
    expect(snapshot.summary.outfitCount, 0);
    expect(outfits, isEmpty);
  });

  test('loadSnapshot returns concrete assets for library browsing', () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
        outfits: [
          WorkspaceOutfit(
            id: 'outfit-1',
            name: 'Rain Coat',
            tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
          ),
        ],
      ),
    ]);
    await workspaceService.saveArtistChains([
      const ArtistChain(
        id: 'artist-1',
        name: 'Painter',
        prompt: 'watercolor wash',
      ),
    ]);
    await workspaceService.saveRecipes('style', [
      const Recipe(
        id: 'recipe-1',
        name: 'Watercolor',
        block: 'style',
        tags: 'soft wash',
      ),
    ]);
    await workspaceService.saveTags('scene', [
      const TagEntry(id: 'tag-1', tag: 'rainy street', block: 'scene'),
    ]);
    await workspaceService.saveInspirations([
      const InspirationEntry(
        id: 'insp-1',
        name: 'Night Alley',
        prompt: 'rainy alley',
      ),
    ]);
    await workspaceService.saveLoras([
      const LoraEntry(
        id: 'lora-1',
        name: 'SoftRain',
        triggerWords: ['softrain'],
      ),
    ]);
    await workspaceService.saveWorkflows([
      const WorkflowEntry(
        id: 'workflow-1',
        name: 'City Stack',
      ),
    ]);
    await workspaceService.saveBatchPlans([
      BatchPlan(
        id: 'batch-1',
        name: 'Night Queue',
        createdAt: DateTime.parse('2026-05-23T00:00:00Z'),
        updatedAt: DateTime.parse('2026-05-23T00:00:00Z'),
      ),
    ]);
    await workspaceService.saveAssemblyPresets([
      const AssemblyPresetEntry(
        id: 'assembly-1',
        name: 'City Assembly',
      ),
    ]);

    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    expect(snapshot.summary.outfitCount, 1);
    expect(snapshot.summary.totalAssetCount, 9);
    expect(snapshot.characters.single.name, 'Heroine');
    expect(snapshot.outfits.single.character.name, 'Heroine');
    expect(snapshot.outfits.single.outfit.name, 'Rain Coat');
    expect(snapshot.artistChains.single.prompt, 'watercolor wash');
    expect(snapshot.recipes.single.tags, 'soft wash');
    expect(snapshot.tags.single.tag, 'rainy street');
    expect(snapshot.inspirations.single.prompt, 'rainy alley');
    expect(snapshot.loras.single.name, 'SoftRain');
    expect(snapshot.workflows.single.name, 'City Stack');
    expect(snapshot.batchPlans.single.name, 'Night Queue');
    expect(snapshot.assemblyPresets.single.name, 'City Assembly');
  });

  test(
      'loadSnapshot prunes legacy generic outfit variants and dedupes repeated outfit names',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r5',
        name: 'Ceobe',
        traits: ViewVariantTexts(frontFull: 'ceobe_(arknights)'),
        imageRefs: ['assets/references/ceobe.png'],
        source: SourceRef(type: 'legacy_artist_workbook'),
        outfits: [
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r5-outfit-3',
            name: '变体 1',
            tags: ViewVariantTexts(frontFull: 'dog ears, brown hair'),
          ),
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r5-outfit-4',
            name: '变体 2',
            tags: ViewVariantTexts(frontFull: 'brown dress'),
          ),
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r5-outfit-5',
            name: 'Cozy Coat',
            tags: ViewVariantTexts(frontFull: 'warm coat'),
            imageRefs: ['assets/references/cozy-a.png'],
          ),
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r5-outfit-6',
            name: 'Cozy Coat',
            tags: ViewVariantTexts(frontFull: 'warm coat, scarf'),
            imageRefs: ['assets/references/cozy-b.png'],
          ),
        ],
      ),
    ]);

    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    expect(snapshot.summary.characterCount, 1);
    expect(snapshot.summary.outfitCount, 1);
    expect(snapshot.characters.single.outfits, hasLength(1));
    expect(snapshot.characters.single.outfits.single.name, 'Cozy Coat');
    expect(snapshot.characters.single.outfits.single.imageRefs, [
      'assets/references/cozy-a.png',
      'assets/references/cozy-b.png',
    ]);
    expect(snapshot.outfits.single.outfit.name, 'Cozy Coat');
  });

  test('loadSnapshot keeps structured legacy generic outfit prompts', () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r14',
        name: 'Pepe',
        traits: ViewVariantTexts(frontFull: 'pepe_(arknights)'),
        source: SourceRef(type: 'legacy_artist_workbook'),
        outfits: [
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r14-outfit-4',
            name: '服装',
            tags: ViewVariantTexts(
              frontFull: 'ancient egyptian clothes, white dress, skirt',
              frontUpper: 'ancient egyptian clothes, white dress',
              frontLower: 'purple skirt',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['ancient egyptian clothes', 'white dress'],
              lowerClothingTags: ['purple skirt'],
            ),
          ),
        ],
      ),
    ]);

    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    expect(snapshot.summary.outfitCount, 1);
    expect(snapshot.characters.single.outfits.single.id,
        'legacy-character-sheet-r14-outfit-4');
    expect(snapshot.characters.single.outfits.single.name, '服装');
    expect(snapshot.outfits.single.outfit.name, '服装');
  });

  test('loadSnapshot keeps skin identities on outfits, not legacy characters',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r13',
        name: 'Suzuran',
        traits: ViewVariantTexts(
          frontFull:
              'suzuran (spring praise) (arknights), fox girl, fox ears, fox tail',
        ),
        anchorTags: [
          'suzuran_(spring_praise)_(arknights)',
          'fox_ears',
        ],
        identityTags: [
          'suzuran (spring praise) (arknights)',
          'girl',
        ],
        source: SourceRef(type: 'legacy_artist_workbook'),
        defaultOutfitId: 'legacy-character-sheet-r13-outfit-3',
        outfits: [
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r13-outfit-3',
            name: 'Yukibare',
            tags: ViewVariantTexts(
              frontFull: 'suzuran (yukibare) (arknights)',
              frontUpper: 'japanese_clothes, kimono',
              frontLower: 'hakama_skirt, sandals',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['japanese_clothes', 'kimono'],
              lowerClothingTags: ['hakama_skirt', 'sandals'],
            ),
          ),
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r13-outfit-4',
            name: 'Spring Praise',
            tags: ViewVariantTexts(
              frontFull:
                  'suzuran (spring praise) (arknights), long_sleeves, blue_skirt',
              frontUpper: 'long_sleeves',
              frontLower: 'blue_skirt',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['long_sleeves'],
              lowerClothingTags: ['blue_skirt'],
            ),
          ),
        ],
      ),
    ]);

    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    final character = snapshot.characters.single;
    expect(
      character.traits.frontFull,
      'suzuran (arknights), fox girl, fox ears, fox tail',
    );
    expect(character.anchorTags, ['suzuran_(arknights)', 'fox_ears']);
    expect(character.identityTags, ['suzuran (arknights)', 'girl']);
    expect(character.defaultOutfitId, 'legacy-character-sheet-r13-outfit-3');
    expect(
      character.outfits[0].tags.frontFull,
      'suzuran (arknights), suzuran (yukibare) (arknights)',
    );
    expect(
      character.outfits[1].tags.frontFull,
      'suzuran (arknights), suzuran (spring praise) (arknights), '
      'long_sleeves, blue_skirt',
    );
    expect(snapshot.outfits, hasLength(2));
  });

  test(
      'loadSnapshot folds identity-only legacy generic outfits into the default outfit',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r5',
        name: 'Ceobe',
        traits: ViewVariantTexts(frontFull: 'ceobe_(arknights)'),
        source: SourceRef(type: 'legacy_artist_workbook'),
        defaultOutfitId: 'default-outfit',
        outfits: [
          WorkspaceOutfit(
            id: 'default-outfit',
            name: '默认服装',
            tags: ViewVariantTexts(
              frontFull: 'dress, long_sleeves',
              frontUpper: 'dress, long_sleeves',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['dress', 'long_sleeves'],
            ),
            imageRefs: ['assets/references/ceobe-default.png'],
          ),
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r5-outfit-3',
            name: '变体 1',
            tags: ViewVariantTexts(
              frontFull:
                  'dog_girl, animal_ears, brown_hair, dog_ears, long_hair',
              frontUpper: 'jacket, black_jacket, gloves, dress, long_sleeves',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperBodyTags: [
                'animal_ears',
                'brown_hair',
                'dog_ears',
                'long_hair',
              ],
              upperClothingTags: [
                'jacket',
                'black_jacket',
                'gloves',
                'dress',
                'long_sleeves',
              ],
            ),
            imageRefs: ['assets/references/ceobe-variant.png'],
          ),
        ],
      ),
    ]);

    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    final character = snapshot.characters.single;
    expect(snapshot.summary.outfitCount, 1);
    expect(character.outfits, hasLength(1));
    expect(character.defaultOutfitId, 'default-outfit');
    final outfit = character.outfits.single;
    expect(outfit.id, 'default-outfit');
    expect(outfit.tags.frontFull, 'dress, long_sleeves');
    expect(outfit.tags.frontUpper,
        'dress, long_sleeves, jacket, black_jacket, gloves');
    expect(outfit.partTags.upperBodyTags, [
      'animal_ears',
      'brown_hair',
      'dog_ears',
      'long_hair',
    ]);
    expect(outfit.partTags.upperClothingTags, [
      'dress',
      'long_sleeves',
      'jacket',
      'black_jacket',
      'gloves',
    ]);
    expect(outfit.imageRefs, [
      'assets/references/ceobe-default.png',
      'assets/references/ceobe-variant.png',
    ]);
  });

  test('loadSnapshot dedupes legacy outfits by structured clothing signature',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'legacy-character-sheet-r21',
        name: 'Yuel',
        traits: ViewVariantTexts(frontFull: 'yuel_(granblue_fantasy)'),
        source: SourceRef(type: 'legacy_artist_workbook'),
        defaultOutfitId: 'default-outfit',
        outfits: [
          WorkspaceOutfit(
            id: 'default-outfit',
            name: '默认服装',
            tags: ViewVariantTexts(
              frontFull: 'bikini, swimsuit, white_robe',
              frontUpper: 'bikini, swimsuit, white_robe',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['bikini', 'swimsuit', 'white_robe'],
            ),
            imageRefs: ['assets/references/yuel-default.png'],
          ),
          WorkspaceOutfit(
            id: 'legacy-character-sheet-r21-outfit-3',
            name: '夏日装',
            tags: ViewVariantTexts(
              frontFull: 'yuel (summer) (granblue fantasy), bikini, swimsuit',
              frontUpper: 'bikini, swimsuit, white_robe',
            ),
            partTags: WorkspaceOutfitPartTags(
              upperClothingTags: ['bikini', 'swimsuit', 'white_robe'],
            ),
            imageRefs: ['assets/references/yuel-summer.png'],
          ),
        ],
      ),
    ]);

    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    final character = snapshot.characters.single;
    expect(snapshot.summary.outfitCount, 1);
    expect(character.outfits, hasLength(1));
    expect(character.defaultOutfitId, 'legacy-character-sheet-r21-outfit-3');
    expect(character.outfits.single.id, 'legacy-character-sheet-r21-outfit-3');
    expect(character.outfits.single.name, '夏日装');
    expect(character.outfits.single.imageRefs, [
      'assets/references/yuel-summer.png',
      'assets/references/yuel-default.png',
    ]);
  });

  test('loadSnapshot excludes legacy codex unless explicitly requested',
      () async {
    await workspaceService.saveInspirations([
      const InspirationEntry(
        id: 'insp-1',
        name: 'Night Alley',
        prompt: 'rainy alley',
      ),
      const InspirationEntry(
        id: 'legacy-codex-regular-0001',
        name: 'Fantasy',
        prompt: 'artist:wlop, dnd, fantasy',
        source: SourceRef(type: 'legacy_codex'),
      ),
      const InspirationEntry(
        id: 'adult-codex-0001',
        name: 'Imported Codex',
        prompt: 'cinematic lighting, solo',
        source: SourceRef(type: 'novalai_codex_adult_docx'),
      ),
    ]);
    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
      legacyCodexLoader: () async => const [
        InspirationEntry(
          id: 'legacy-codex-regular-0001',
          name: 'Fantasy',
          prompt: 'artist:wlop, dnd, fantasy',
          source: SourceRef(type: 'legacy_codex'),
        ),
      ],
    );

    final defaultSnapshot = await service.loadSnapshot();
    final codexSnapshot = await service.loadSnapshot(includeLegacyCodex: true);
    final summary = await service.loadSummary();

    expect(defaultSnapshot.inspirations.map((entry) => entry.id), ['insp-1']);
    expect(defaultSnapshot.summary.inspirationCount, 1);
    expect(summary.inspirationCount, 1);
    expect(codexSnapshot.inspirations.map((entry) => entry.id), [
      'insp-1',
      'legacy-codex-regular-0001',
      'adult-codex-0001',
    ]);
  });

  test('loadSnapshot exposes bundled legacy codex before entries load',
      () async {
    final snapshot = await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    expect(snapshot.legacyCodexAvailable, isTrue);
    expect(snapshot.legacyCodexLoadedCount, 0);
    expect(snapshot.legacyCodexTotalCount, 0);
  });

  test('loadSnapshot limits and searches legacy codex entries', () async {
    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
      legacyCodexLoader: () async => [
        for (var index = 1; index <= 5; index++)
          InspirationEntry(
            id: 'legacy-codex-$index',
            name: 'Codex $index',
            prompt: index == 5 ? 'dragon shrine' : 'forest path $index',
            source: const SourceRef(type: 'legacy_codex'),
          ),
      ],
    );

    final limited = await service.loadSnapshot(
      includeLegacyCodex: true,
      legacyCodexLimit: 2,
    );
    final searched = await service.loadSnapshot(
      includeLegacyCodex: true,
      legacyCodexLimit: 2,
      legacyCodexQuery: 'dragon',
    );

    expect(limited.legacyCodexLoadedCount, 2);
    expect(limited.legacyCodexTotalCount, 5);
    expect(limited.inspirations.map((entry) => entry.id), [
      'legacy-codex-1',
      'legacy-codex-2',
    ]);
    expect(searched.legacyCodexLoadedCount, 1);
    expect(searched.legacyCodexTotalCount, 1);
    expect(searched.inspirations.single.id, 'legacy-codex-5');
  });

  test('loadSnapshot avoids legacy codex subcategory counts for all view',
      () async {
    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
      legacyCodexLoader: () async => const [
        InspirationEntry(
          id: 'legacy-codex-style',
          name: 'Painter Style',
          prompt: 'artist:wlop, painterly, official art',
          source: SourceRef(type: 'legacy_codex'),
        ),
        InspirationEntry(
          id: 'legacy-codex-dress',
          name: 'Dress Notes',
          prompt: 'red dress, white gloves, leather boots',
          source: SourceRef(type: 'legacy_codex'),
        ),
      ],
    );

    final snapshot = await service.loadSnapshot(
      includeLegacyCodex: true,
      legacyCodexLimit: 2,
    );

    expect(
      snapshot.legacyCodexCategoryCounts[StudioLegacyCodexCategories.allKey],
      2,
    );
    expect(
      snapshot.legacyCodexCategoryCounts[
          StudioLegacyCodexCategories.artistStyle.key],
      0,
    );
    expect(
      snapshot
          .legacyCodexCategoryCounts[StudioLegacyCodexCategories.clothing.key],
      0,
    );
  });

  test('loadSnapshot filters legacy codex category before paging', () async {
    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
      legacyCodexLoader: () async => const [
        InspirationEntry(
          id: 'legacy-codex-style',
          name: 'Painter Style',
          prompt: 'artist:wlop, painterly, official art',
          source: SourceRef(type: 'legacy_codex'),
        ),
        InspirationEntry(
          id: 'legacy-codex-dress',
          name: 'Dress Notes',
          prompt: 'red dress, white gloves, leather boots',
          source: SourceRef(type: 'legacy_codex'),
        ),
        InspirationEntry(
          id: 'legacy-codex-coat',
          name: 'Coat Notes',
          prompt: 'long coat, uniform jacket, black skirt',
          source: SourceRef(type: 'legacy_codex'),
        ),
      ],
    );

    final snapshot = await service.loadSnapshot(
      includeLegacyCodex: true,
      legacyCodexLimit: 1,
      legacyCodexCategoryKey: StudioLegacyCodexCategories.clothing.key,
    );

    expect(snapshot.legacyCodexLoadedCount, 1);
    expect(snapshot.legacyCodexTotalCount, 2);
    expect(snapshot.inspirations.single.id, 'legacy-codex-dress');
    expect(
      snapshot.legacyCodexCategoryCounts[
          StudioLegacyCodexCategories.artistStyle.key],
      1,
    );
    expect(
      snapshot
          .legacyCodexCategoryCounts[StudioLegacyCodexCategories.clothing.key],
      2,
    );
  });

  test('legacy codex categories avoid broad token false positives', () {
    List<String> keysFor(String prompt) {
      return StudioLegacyCodexCategories.keysFor(
        InspirationEntry(
          id: 'sample',
          name: 'Sample',
          prompt: prompt,
          source: const SourceRef(type: 'legacy_codex'),
        ),
      );
    }

    expect(keysFor('1girl, solo, slight smile'), [
      StudioLegacyCodexCategories.poseExpression.key,
    ]);
    expect(keysFor('1girl, solo, looking at viewer, from side'), [
      StudioLegacyCodexCategories.composition.key,
    ]);
    expect(
        keysFor('dragon claw, flame wings, magic circle'),
        containsAll([
          StudioLegacyCodexCategories.fantasyCreature.key,
          StudioLegacyCodexCategories.magicEffects.key,
        ]));
    expect(keysFor('mechanical arms, cyberpunk city, robot joints'),
        contains(StudioLegacyCodexCategories.mechanicalSciFi.key));
    expect(keysFor('red dress, white gloves, leather boots'), [
      StudioLegacyCodexCategories.clothing.key,
    ]);
  });

  test('legacy codex category terms avoid substring-only matches', () {
    final keys = StudioLegacyCodexCategories.keysFor(
      const InspirationEntry(
        id: 'sample',
        name: 'Sample',
        prompt: 'eyeshadow, negative space, multiple views, highlight',
        source: SourceRef(type: 'legacy_codex'),
      ),
    );

    expect(keys, [StudioLegacyCodexCategories.general.key]);
  });

  test('legacy codex categories cover common accessory and subject clusters',
      () {
    List<String> keysFor(String prompt) {
      return StudioLegacyCodexCategories.keysFor(
        InspirationEntry(
          id: 'sample',
          name: 'Sample',
          prompt: prompt,
          source: const SourceRef(type: 'legacy_codex'),
        ),
      );
    }

    expect(keysFor('black thighhighs, toeless legwear'), [
      StudioLegacyCodexCategories.clothing.key,
    ]);
    expect(keysFor('black fur, doberman, furry, bird boy'), [
      StudioLegacyCodexCategories.fantasyCreature.key,
    ]);
    expect(
        keysFor('abstract art, cubism, greyscale'),
        containsAll([
          StudioLegacyCodexCategories.artistStyle.key,
          StudioLegacyCodexCategories.lightingColor.key,
        ]));
    expect(keysFor('pink bikini, swimsuit, mittens, fur shawl'), [
      StudioLegacyCodexCategories.clothing.key,
    ]);
    expect(
        keysFor('transparent wing, crystal wing, pink slime'),
        contains(
          StudioLegacyCodexCategories.fantasyCreature.key,
        ));
    expect(keysFor('white tank top, striped underwear, side slit'), [
      StudioLegacyCodexCategories.clothing.key,
    ]);
    expect(
        keysFor('space helmet, spacesuit, underwater, heroic stance'),
        containsAll([
          StudioLegacyCodexCategories.poseExpression.key,
          StudioLegacyCodexCategories.scene.key,
          StudioLegacyCodexCategories.mechanicalSciFi.key,
        ]));
  });

  test('loadSnapshot writes a durable catalog cache file', () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-cache',
        name: 'Cached Hero',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);
    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
    );

    final snapshot = await service.loadSnapshot();

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${WorkspacePaths.assetCatalogCache}',
    );
    expect(await cacheFile.exists(), isTrue);
    final cacheJson = jsonDecode(await cacheFile.readAsString());
    expect(cacheJson['schemaVersion'], 5);
    final entries = Map<String, dynamic>.from(cacheJson['entries'] as Map);
    expect(entries, hasLength(1));
    final cacheEntry = Map<String, dynamic>.from(entries.values.single as Map);
    expect(cacheEntry['snapshot']['characters'].single['id'], 'char-cache');
    expect(snapshot.characters.single.name, 'Cached Hero');
  });

  test('loadSnapshotWithCache restores a persisted snapshot after restart',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-before-restart',
        name: 'Before Restart',
        traits: ViewVariantTexts(frontFull: 'silver hair'),
      ),
    ]);
    await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();

    final reopenedWorkspace = WorkspaceService();
    await reopenedWorkspace.openWorkspace(tempDir.path);
    final reopenedService = StudioAssetCatalogService(
      workspaceService: reopenedWorkspace,
    );

    final result = await reopenedService.loadSnapshotWithCache();

    expect(result.fromCache, isTrue);
    expect(result.isStale, isFalse);
    expect(result.snapshot.characters.single.id, 'char-before-restart');
  });

  test('loadSnapshot cache keeps default and codex requests side by side',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-default-cache',
        name: 'Default Cache Hero',
        traits: ViewVariantTexts(frontFull: 'silver hair'),
      ),
    ]);
    await workspaceService.saveInspirations([
      const InspirationEntry(
        id: 'legacy-codex-cache',
        name: 'Codex Cache',
        prompt: 'artist:wlop, fantasy',
        source: SourceRef(type: 'legacy_codex'),
      ),
    ]);
    final service = StudioAssetCatalogService(
      workspaceService: workspaceService,
    );

    await service.loadSnapshot();
    await service.loadSnapshot(
      includeLegacyCodex: true,
      legacyCodexLimit: 1,
    );

    final reopenedWorkspace = WorkspaceService();
    await reopenedWorkspace.openWorkspace(tempDir.path);
    final reopenedService = StudioAssetCatalogService(
      workspaceService: reopenedWorkspace,
    );

    final defaultResult = await reopenedService.loadSnapshotWithCache();
    final codexResult = await reopenedService.loadSnapshotWithCache(
      includeLegacyCodex: true,
      legacyCodexLimit: 1,
    );

    expect(defaultResult.fromCache, isTrue);
    expect(defaultResult.snapshot.characters.single.id, 'char-default-cache');
    expect(defaultResult.snapshot.inspirations, isEmpty);
    expect(codexResult.fromCache, isTrue);
    expect(codexResult.snapshot.legacyCodexLoadedCount, 1);
    expect(codexResult.snapshot.inspirations.single.id, 'legacy-codex-cache');
  });

  test('loadSnapshotWithCache marks persisted cache stale after external edit',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-old',
        name: 'Old Hero',
        traits: ViewVariantTexts(frontFull: 'green eyes'),
      ),
    ]);
    await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-new',
        name: 'New Hero',
        traits: ViewVariantTexts(frontFull: 'gold eyes, long braid'),
      ),
    ]);
    final reopenedWorkspace = WorkspaceService();
    await reopenedWorkspace.openWorkspace(tempDir.path);
    final reopenedService = StudioAssetCatalogService(
      workspaceService: reopenedWorkspace,
    );

    final cached = await reopenedService.loadSnapshotWithCache();
    final rebuilt = await reopenedService.refreshSnapshotCache();

    expect(cached.fromCache, isTrue);
    expect(cached.isStale, isTrue);
    expect(cached.snapshot.characters.single.id, 'char-old');
    expect(rebuilt.characters.single.id, 'char-new');
  });

  test('loadSnapshotWithCache can skip stale check for fast cache display',
      () async {
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-old',
        name: 'Old Hero',
        traits: ViewVariantTexts(frontFull: 'green eyes'),
      ),
    ]);
    await StudioAssetCatalogService(
      workspaceService: workspaceService,
    ).loadSnapshot();
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-new',
        name: 'New Hero',
        traits: ViewVariantTexts(frontFull: 'gold eyes, long braid'),
      ),
    ]);
    final reopenedWorkspace = WorkspaceService();
    await reopenedWorkspace.openWorkspace(tempDir.path);
    final reopenedService = StudioAssetCatalogService(
      workspaceService: reopenedWorkspace,
    );

    final unchecked = await reopenedService.loadSnapshotWithCache(
      checkStaleness: false,
    );
    final checked = await reopenedService.loadSnapshotWithCache();

    expect(unchecked.fromCache, isTrue);
    expect(unchecked.isStale, isFalse);
    expect(unchecked.snapshot.characters.single.id, 'char-old');
    expect(checked.fromCache, isTrue);
    expect(checked.isStale, isTrue);
  });
}
