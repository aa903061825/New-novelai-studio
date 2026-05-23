import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioAssetCatalogSummary {
  final int characterCount;
  final int outfitCount;
  final int artistChainCount;
  final int recipeCount;
  final int tagCount;
  final int inspirationCount;
  final int loraCount;
  final int workflowCount;
  final int batchPlanCount;
  final int assemblyPresetCount;
  final Map<String, int> recipeCountsByBlock;
  final Map<String, int> tagCountsByBlock;

  const StudioAssetCatalogSummary({
    required this.characterCount,
    this.outfitCount = 0,
    required this.artistChainCount,
    required this.recipeCount,
    required this.tagCount,
    this.inspirationCount = 0,
    this.loraCount = 0,
    this.workflowCount = 0,
    this.batchPlanCount = 0,
    this.assemblyPresetCount = 0,
    required this.recipeCountsByBlock,
    required this.tagCountsByBlock,
  });

  int get totalAssetCount =>
      characterCount +
      outfitCount +
      artistChainCount +
      recipeCount +
      tagCount +
      inspirationCount +
      loraCount +
      workflowCount +
      batchPlanCount +
      assemblyPresetCount;

  bool get isEmpty => totalAssetCount == 0;
}

class StudioOutfitAsset {
  final CharacterEntry character;
  final WorkspaceOutfit outfit;

  const StudioOutfitAsset({
    required this.character,
    required this.outfit,
  });
}

class StudioAssetCatalogSnapshot {
  final StudioAssetCatalogSummary summary;
  final List<CharacterEntry> characters;
  final List<StudioOutfitAsset> outfits;
  final List<ArtistChain> artistChains;
  final List<Recipe> recipes;
  final List<TagEntry> tags;
  final List<InspirationEntry> inspirations;
  final List<LoraEntry> loras;
  final List<WorkflowEntry> workflows;
  final List<BatchPlan> batchPlans;
  final List<AssemblyPresetEntry> assemblyPresets;

  const StudioAssetCatalogSnapshot({
    required this.summary,
    required this.characters,
    this.outfits = const [],
    required this.artistChains,
    required this.recipes,
    required this.tags,
    this.inspirations = const [],
    this.loras = const [],
    this.workflows = const [],
    this.batchPlans = const [],
    this.assemblyPresets = const [],
  });
}

class StudioAssetCatalogService {
  final WorkspaceService workspaceService;

  StudioAssetCatalogService({required this.workspaceService});

  Future<StudioAssetCatalogSummary> loadSummary() async {
    return (await loadSnapshot()).summary;
  }

  Future<StudioAssetCatalogSnapshot> loadSnapshot() async {
    final characters = await workspaceService.loadCharacters();
    final artistChains = await workspaceService.loadArtistChains();
    final inspirations = await workspaceService.loadInspirations();
    final loras = await workspaceService.loadLoras();
    final workflows = await workspaceService.loadWorkflows();
    final batchPlans = await workspaceService.loadBatchPlans();
    final assemblyPresets = await workspaceService.loadAssemblyPresets();
    final outfits = <StudioOutfitAsset>[];
    final recipeCountsByBlock = <String, int>{};
    final tagCountsByBlock = <String, int>{};
    final recipes = <Recipe>[];
    final tags = <TagEntry>[];

    for (final character in characters) {
      for (final outfit in character.outfits) {
        outfits.add(StudioOutfitAsset(character: character, outfit: outfit));
      }
    }

    for (final block in WorkspacePaths.blocks) {
      final blockRecipes = await workspaceService.loadRecipes(block);
      final blockTags = await workspaceService.loadTags(block);
      recipes.addAll(blockRecipes);
      tags.addAll(blockTags);
      recipeCountsByBlock[block] = blockRecipes.length;
      tagCountsByBlock[block] = blockTags.length;
    }

    final summary = StudioAssetCatalogSummary(
      characterCount: characters.length,
      outfitCount: outfits.length,
      artistChainCount: artistChains.length,
      recipeCount: recipeCountsByBlock.values.fold(0, (a, b) => a + b),
      tagCount: tagCountsByBlock.values.fold(0, (a, b) => a + b),
      inspirationCount: inspirations.length,
      loraCount: loras.length,
      workflowCount: workflows.length,
      batchPlanCount: batchPlans.length,
      assemblyPresetCount: assemblyPresets.length,
      recipeCountsByBlock: Map.unmodifiable(recipeCountsByBlock),
      tagCountsByBlock: Map.unmodifiable(tagCountsByBlock),
    );

    return StudioAssetCatalogSnapshot(
      summary: summary,
      characters: List.unmodifiable(characters),
      outfits: List.unmodifiable(outfits),
      artistChains: List.unmodifiable(artistChains),
      recipes: List.unmodifiable(recipes),
      tags: List.unmodifiable(tags),
      inspirations: List.unmodifiable(inspirations),
      loras: List.unmodifiable(loras),
      workflows: List.unmodifiable(workflows),
      batchPlans: List.unmodifiable(batchPlans),
      assemblyPresets: List.unmodifiable(assemblyPresets),
    );
  }
}
