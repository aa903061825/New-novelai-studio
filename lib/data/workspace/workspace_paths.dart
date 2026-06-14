class WorkspacePaths {
  static const manifest = 'studio_manifest.json';
  static const characters = 'library/characters.json';
  static const artistChains = 'library/artist_chains.json';
  static const inspirations = 'library/inspirations.json';
  static const promptChunks = 'library/prompt_chunks.json';
  static const loras = 'library/loras.json';
  static const assetFavorites = 'library/favorites.json';
  static const assetCatalogCache = 'library/asset_catalog_cache.json';
  static const promptReplaceRules = 'configs/prompt_replace_rules.json';
  static const filterRules = 'configs/filter_rules.json';
  static const galleryRecords = 'gallery/records.json';
  static const batchPlansDir = 'production/batch_plans';
  static const deterministicPlansDir = 'production/deterministic_plans';
  static const productionExecutionSettings =
      'production/execution_settings.json';
  static const assemblyPresetsDir = 'production/assembly_presets';
  static const workflowsDir = 'production/workflows';
  static const scriptRecastKnowledge = 'script_recast/knowledge.json';
  static const scriptRecastCacheDir = 'script_recast/cache';
  static const tokenizerScriptsDir = 'tokenizer_scripts/scripts';

  static const blocks = [
    'style',
    'sub_style',
    'character',
    'clothing',
    'action',
    'expression',
    'scene',
    'camera',
  ];

  static const directories = [
    'library/recipes',
    'library/tags',
    'configs/prompt_configs',
    'configs/generation_profiles',
    batchPlansDir,
    deterministicPlansDir,
    assemblyPresetsDir,
    workflowsDir,
    scriptRecastCacheDir,
    tokenizerScriptsDir,
    'assets/images',
    'assets/thumbnails',
    'assets/references',
    'gallery',
    'imports/kamia',
    'imports/casrand',
    'imports/artist_studio',
    'output/nai',
    'output/comfyui',
  ];

  static List<String> get emptyArrayFiles => [
        characters,
        artistChains,
        inspirations,
        promptChunks,
        loras,
        assetFavorites,
        promptReplaceRules,
        galleryRecords,
        for (final block in blocks) recipeFile(block),
        for (final block in blocks) tagFile(block),
      ];

  static List<String> get emptyObjectFiles => [
        filterRules,
        productionExecutionSettings,
        scriptRecastKnowledge,
      ];

  static String recipeFile(String block) => 'library/recipes/$block.json';

  static String tagFile(String block) => 'library/tags/$block.json';

  static String promptConfigFile(String id) =>
      'configs/prompt_configs/$id.json';

  static String generationProfileFile(String id) {
    return 'configs/generation_profiles/$id.json';
  }

  static String batchPlanFile(String id) => '$batchPlansDir/$id.json';

  static String productionPlanFile(String id) =>
      '$deterministicPlansDir/$id.json';

  static String assemblyPresetFile(String id) => '$assemblyPresetsDir/$id.json';

  static String workflowFile(String id) => '$workflowsDir/$id.json';

  static String scriptRecastCacheFile(String id) =>
      '$scriptRecastCacheDir/$id.json';

  static String tokenizerScriptFile(String id) =>
      '$tokenizerScriptsDir/$id.json';
}
