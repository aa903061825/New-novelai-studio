import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
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
    expect(summary.totalAssetCount, 11);
    expect(summary.recipeCountsByBlock['style'], 2);
    expect(summary.tagCountsByBlock['scene'], 1);
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
    expect(snapshot.summary.totalAssetCount, 10);
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
}
