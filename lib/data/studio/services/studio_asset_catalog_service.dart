import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioLegacyCodexCategory {
  final String key;
  final String label;

  const StudioLegacyCodexCategory({
    required this.key,
    required this.label,
  });
}

class StudioLegacyCodexCategories {
  static const allKey = 'all';

  static const all = StudioLegacyCodexCategory(
    key: allKey,
    label: '全部法典',
  );
  static const artistStyle = StudioLegacyCodexCategory(
    key: 'artist-style',
    label: '画师风格',
  );
  static const character = StudioLegacyCodexCategory(
    key: 'character',
    label: '角色体貌',
  );
  static const poseExpression = StudioLegacyCodexCategory(
    key: 'pose-expression',
    label: '动作/表情',
  );
  static const clothing = StudioLegacyCodexCategory(
    key: 'clothing',
    label: '服装穿搭',
  );
  static const scene = StudioLegacyCodexCategory(
    key: 'scene',
    label: '场景空间',
  );
  static const composition = StudioLegacyCodexCategory(
    key: 'composition',
    label: '构图镜头',
  );
  static const lightingColor = StudioLegacyCodexCategory(
    key: 'lighting-color',
    label: '光影/色调',
  );
  static const qualityRender = StudioLegacyCodexCategory(
    key: 'quality-render',
    label: '质量/渲染',
  );
  static const negativeFix = StudioLegacyCodexCategory(
    key: 'negative-fix',
    label: '负面/修正',
  );
  static const fantasyCreature = StudioLegacyCodexCategory(
    key: 'fantasy-creature',
    label: '奇幻题材/生物',
  );
  static const mechanicalSciFi = StudioLegacyCodexCategory(
    key: 'mechanical-sci-fi',
    label: '机械/赛博科幻',
  );
  static const magicEffects = StudioLegacyCodexCategory(
    key: 'magic-effects',
    label: '魔法/特效',
  );
  static const general = StudioLegacyCodexCategory(
    key: 'general',
    label: '其他/通用',
  );

  static const filters = [
    all,
    artistStyle,
    character,
    poseExpression,
    clothing,
    scene,
    composition,
    lightingColor,
    qualityRender,
    negativeFix,
    fantasyCreature,
    mechanicalSciFi,
    magicEffects,
    general,
  ];

  static const _specificFilters = [
    artistStyle,
    character,
    poseExpression,
    clothing,
    scene,
    composition,
    lightingColor,
    qualityRender,
    negativeFix,
    fantasyCreature,
    mechanicalSciFi,
    magicEffects,
  ];

  static String normalizedKey(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) return allKey;
    return filters.any((category) => category.key == normalized)
        ? normalized
        : allKey;
  }

  static StudioLegacyCodexCategory byKey(String key) {
    final normalized = normalizedKey(key);
    return filters.firstWhere((category) => category.key == normalized);
  }

  static bool matches(InspirationEntry entry, String categoryKey) {
    final normalized = normalizedKey(categoryKey);
    return normalized == allKey || keysFor(entry).contains(normalized);
  }

  static List<String> keysFor(InspirationEntry entry) {
    final text = _searchText(entry);
    final keys = <String>[];
    for (final category in _specificFilters) {
      if (_termsFor(category.key).any((term) => _matchesTerm(text, term))) {
        keys.add(category.key);
      }
    }
    return keys.isEmpty ? [general.key] : List.unmodifiable(keys);
  }

  static List<String> labelsFor(InspirationEntry entry) {
    return keysFor(entry)
        .map((key) => byKey(key).label)
        .toList(growable: false);
  }

  static Map<String, int> countByCategory(List<InspirationEntry> entries) {
    final counts = <String, int>{allKey: entries.length};
    for (final category in filters.skip(1)) {
      counts[category.key] = 0;
    }
    for (final entry in entries) {
      for (final key in keysFor(entry)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return Map.unmodifiable(counts);
  }

  static String _searchText(InspirationEntry entry) {
    return [
      entry.name,
      entry.prompt,
      entry.negativePrompt,
      entry.tags.join(' '),
      entry.note,
    ].join('\n').toLowerCase();
  }

  static bool _matchesTerm(String text, String term) {
    final normalizedTerm = term.trim().toLowerCase();
    if (normalizedTerm.isEmpty) return false;
    if (!_shouldUseAsciiBoundary(normalizedTerm)) {
      return text.contains(normalizedTerm);
    }
    final escaped = RegExp.escape(normalizedTerm);
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(text);
  }

  static bool _shouldUseAsciiBoundary(String term) {
    return RegExp(r'^[a-z0-9][a-z0-9 -]*[a-z0-9]$').hasMatch(term);
  }

  static List<String> _termsFor(String key) {
    return switch (key) {
      'artist-style' => const [
          'artist:',
          'style of',
          'galgame',
          'game cg',
          'official art',
          'project moon',
          'blue archive',
          'arknights',
          'chibi',
          'pixel art',
          'lineart',
          'sketch',
          'sketching',
          'painterly',
          'watercolor',
          'crayon',
          'abstract art',
          'cubism',
          'surrealism',
          'greyscale',
          '画风',
          '风格',
          '插画',
          '手绘',
          'q版',
        ],
      'character' => const [
          'hair',
          'eyes',
          'eyelashes',
          'eyebrows',
          'face',
          'body markings',
          'body writing',
          'bodypaint',
          'skin',
          'freckles',
          'collarbone',
          'navel',
          'tattoo',
          'muscular',
          'pointy ears',
          'horns',
          'tail',
          'wings',
          '角色',
          '体貌',
        ],
      'pose-expression' => const [
          'smile',
          'slight smile',
          'open mouth',
          'closed mouth',
          'expressionless',
          'closed eyes',
          'half-closed eyes',
          'pose',
          'dynamic pose',
          'standing',
          'sitting',
          'lying',
          'leaning forward',
          'hand up',
          'head tilt',
          'arms up',
          'holding',
          'grabbing',
          'hand in pocket',
          'stance',
          '动作',
          '表情',
        ],
      'clothing' => const [
          'dress',
          'skirt',
          'shirt',
          'coat',
          'uniform',
          'hoodie',
          'jacket',
          'pants',
          'boot',
          'boots',
          'sock',
          'socks',
          'glove',
          'gloves',
          'hat',
          'cap',
          'headwear',
          'kimono',
          'armor',
          'outfit',
          'clothes',
          'bikini',
          'swimsuit',
          'mittens',
          'bodystocking',
          'tank top',
          'underwear',
          'panties',
          'side slit',
          'cross-laced',
          'double-breasted',
          'helmet',
          'space helmet',
          'spacesuit',
          'bodysuit',
          'sweater',
          'shorts',
          'thighhighs',
          'pantyhose',
          'legwear',
          'sleeves',
          'heels',
          'shoes',
          'sneakers',
          'scarf',
          'shawl',
          'fur shawl',
          'fur trim',
          'cloak',
          'cape',
          'blouse',
          'corset',
          'lapels',
          'eyewear',
          'sunglasses',
          '服装',
          '穿搭',
          '制服',
          '裙',
        ],
      'scene' => const [
          'background',
          'room',
          'street',
          'city',
          'forest',
          'school',
          'indoors',
          'outdoors',
          'sky',
          'cloud',
          'night',
          'daytime',
          'landscape',
          'castle',
          'beach',
          'window',
          'store',
          'grocery store',
          'underwater',
          'pool',
          'blurry background',
          '场景',
          '背景',
          '空间',
        ],
      'composition' => const [
          'close-up',
          'cowboy shot',
          'upper body',
          'full body',
          'from side',
          'from above',
          'from below',
          'from behind',
          'angle',
          'portrait',
          'composition',
          'looking at viewer',
          'looking away',
          'looking back',
          'dynamic angle',
          'perspective',
          '构图',
          '镜头',
          '视角',
        ],
      'lighting-color' => const [
          'soft light',
          'sunlight',
          'light particles',
          'light rays',
          'lighting',
          'shadow',
          'color palette',
          'colorful',
          'flat color',
          'gradient',
          'monochrome',
          'greyscale',
          'black and white',
          'glow',
          'glowing',
          'sunset',
          'neon',
          'backlight',
          'rim light',
          'palette',
          '光',
          '色彩',
        ],
      'quality-render' => const [
          'masterpiece',
          'best quality',
          'absurdres',
          'highres',
          'detailed',
          'render',
          'illustration',
          'anime screencap',
          'very aesthetic',
          '质量',
          '渲染',
        ],
      'negative-fix' => const [
          'negative prompt',
          'worst quality',
          'low quality',
          'lowres',
          'bad anatomy',
          'extra fingers',
          'jpeg artifacts',
          'bad hands',
          'watermark',
          'signature',
          'cropped',
          '负面',
          '修正',
        ],
      'fantasy-creature' => const [
          'dragon',
          'elf',
          'fairy',
          'demon',
          'angel',
          'monster',
          'beast',
          'beast ears',
          'animal ears',
          'kemonomimi',
          'furry',
          'centaur',
          'wing',
          'tentacle',
          'tentacles',
          'slime',
          'snowman',
          'xenomorph',
          'harvin',
          'lalafell',
          'doberman',
          'bird boy',
          'insect',
          'enderman',
          'tail',
          'wings',
          'horns',
          'claws',
          'fantasy',
          'medieval',
          'dnd',
          '精灵',
          '龙',
          '兽',
          '怪',
        ],
      'mechanical-sci-fi' => const [
          'mechanical',
          'robot',
          'android',
          'cyborg',
          'mecha',
          'cyberpunk',
          'sci-fi',
          'science fiction',
          'spacesuit',
          'space helmet',
          'power armor',
          'mechanical arms',
          'robot joints',
          'circuit',
          'bio-chip',
          'hologram',
          '机娘',
          '机械',
          '赛博',
          '科幻',
        ],
      'magic-effects' => const [
          'magic',
          'magic circle',
          'spell',
          'aura',
          'flame',
          'fire',
          'ice',
          'lightning',
          'electricity',
          'spark',
          'radiant',
          'solar',
          'trailing light',
          'particles',
          'magic particles',
          'glitch',
          'energy',
          'portal',
          'rune',
          '魔法',
          '特效',
          '火焰',
        ],
      _ => const <String>[],
    };
  }
}

class StudioAssetFavoriteKeys {
  const StudioAssetFavoriteKeys._();

  static String character(String id) => 'character:${_segment(id)}';

  static String outfit(String characterId, String outfitId) =>
      'outfit:${_segment(characterId)}/${_segment(outfitId)}';

  static String artistChain(String id) => 'artist:${_segment(id)}';

  static String recipe(String block, String id) =>
      'recipe:${_segment(block)}/${_segment(id)}';

  static String tag(String block, String id) =>
      'tag:${_segment(block)}/${_segment(id)}';

  static String inspiration(String id) => 'inspiration:${_segment(id)}';

  static String lora(String id) => 'lora:${_segment(id)}';

  static String workflow(String id) => 'workflow:${_segment(id)}';

  static String assemblyPreset(String id) => 'assembly-preset:${_segment(id)}';

  static String _segment(String value) => value.trim();
}

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
  final int legacyCodexTotalCount;
  final int legacyCodexLoadedCount;
  final Map<String, int> legacyCodexCategoryCounts;
  final bool legacyCodexAvailable;

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
    this.legacyCodexTotalCount = 0,
    this.legacyCodexLoadedCount = 0,
    this.legacyCodexCategoryCounts = const {},
    this.legacyCodexAvailable = false,
  });
}

class StudioAssetCatalogCacheLoadResult {
  final StudioAssetCatalogSnapshot snapshot;
  final bool fromCache;
  final bool isStale;

  const StudioAssetCatalogCacheLoadResult({
    required this.snapshot,
    required this.fromCache,
    required this.isStale,
  });
}

class StudioAssetCatalogService {
  static const _cacheSchemaVersion = 3;
  static const _singleEntryCacheSchemaVersion = 2;

  final WorkspaceService workspaceService;
  final Future<List<InspirationEntry>> Function()? legacyCodexLoader;
  List<InspirationEntry>? _legacyCodexCache;
  bool? _legacyCodexAvailabilityCache;

  StudioAssetCatalogService({
    required this.workspaceService,
    this.legacyCodexLoader,
  });

  static bool isCodexSourceType(String sourceType) {
    final normalized = sourceType.trim().toLowerCase().replaceAll('-', '_');
    if (normalized.isEmpty) return false;
    return normalized == 'codex' ||
        normalized == 'legacy_codex' ||
        normalized.startsWith('novalai_codex') ||
        normalized.contains('_codex') ||
        normalized.contains('codex_');
  }

  Future<StudioAssetCatalogCacheLoadResult> loadSnapshotWithCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool checkStaleness = true,
  }) async {
    final request = _cacheRequest(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
    final cached = await _readPersistentCache(request);
    if (cached != null) {
      final isStale = checkStaleness
          ? !_sameFingerprint(
              cached.sourceFingerprint,
              await _sourceFingerprint(),
            )
          : false;
      return StudioAssetCatalogCacheLoadResult(
        snapshot: cached.snapshot,
        fromCache: true,
        isStale: isStale,
      );
    }

    return StudioAssetCatalogCacheLoadResult(
      snapshot: await refreshSnapshotCache(
        includeLegacyCodex: includeLegacyCodex,
        legacyCodexLimit: legacyCodexLimit,
        legacyCodexQuery: legacyCodexQuery,
        legacyCodexCategoryKey: legacyCodexCategoryKey,
      ),
      fromCache: false,
      isStale: false,
    );
  }

  Future<StudioAssetCatalogSnapshot> refreshSnapshotCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
  }) {
    return loadSnapshot(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
  }

  Future<StudioAssetCatalogSummary> loadSummary() async {
    final characters = await _loadCatalogCharacters();
    final recipeCountsByBlock = <String, int>{};
    final tagCountsByBlock = <String, int>{};

    for (final block in WorkspacePaths.blocks) {
      recipeCountsByBlock[block] =
          (await workspaceService.loadRecipes(block)).length;
      tagCountsByBlock[block] = (await workspaceService.loadTags(block)).length;
    }

    return StudioAssetCatalogSummary(
      characterCount: characters.length,
      outfitCount: _outfitsFromCharacters(characters).length,
      artistChainCount: (await workspaceService.loadArtistChains()).length,
      recipeCount: recipeCountsByBlock.values.fold(0, (a, b) => a + b),
      tagCount: tagCountsByBlock.values.fold(0, (a, b) => a + b),
      inspirationCount: (await workspaceService.loadInspirations())
          .where((entry) => !isCodexSourceType(entry.source.type))
          .length,
      loraCount: (await workspaceService.loadLoras()).length,
      workflowCount: (await workspaceService.loadWorkflows()).length,
      batchPlanCount: (await workspaceService.loadBatchPlans()).length,
      assemblyPresetCount:
          (await workspaceService.loadAssemblyPresets()).length,
      recipeCountsByBlock: Map.unmodifiable(recipeCountsByBlock),
      tagCountsByBlock: Map.unmodifiable(tagCountsByBlock),
    );
  }

  Future<Set<String>> loadAssetFavoriteKeys() {
    return workspaceService.loadAssetFavorites();
  }

  Future<void> setAssetFavorite(String key, bool isFavorite) {
    return workspaceService.setAssetFavorite(key, isFavorite);
  }

  String? resolveImagePath(List<String> refs) {
    final workspaceRoot = workspaceService.root;
    for (final ref in refs) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty) continue;
      final direct = File(trimmed);
      if (direct.isAbsolute && direct.existsSync()) {
        return direct.path;
      }
      if (workspaceRoot == null) continue;
      for (final candidate in [
        File(_join(workspaceRoot.path, trimmed)),
        File(_join(workspaceRoot.path, 'assets/references/$trimmed')),
        File(_join(workspaceRoot.path, 'imports/artist_studio/$trimmed')),
        File(_join(workspaceRoot.path, 'imports/kamia/$trimmed')),
      ]) {
        if (candidate.existsSync()) return candidate.path;
      }
    }
    return null;
  }

  Future<List<CharacterEntry>> loadWorkbenchCharacters() {
    return _loadCatalogCharacters();
  }

  Future<List<StudioOutfitAsset>> loadWorkbenchOutfits() async {
    final characters = await _loadCatalogCharacters();
    return List.unmodifiable(_outfitsFromCharacters(characters));
  }

  List<StudioOutfitAsset> _outfitsFromCharacters(
    List<CharacterEntry> characters,
  ) {
    final outfits = <StudioOutfitAsset>[];
    for (final character in characters) {
      for (final outfit in character.outfits) {
        outfits.add(StudioOutfitAsset(character: character, outfit: outfit));
      }
    }
    return outfits;
  }

  Future<List<ArtistChain>> loadWorkbenchArtistChains() {
    return workspaceService.loadArtistChains();
  }

  Future<List<Recipe>> loadWorkbenchRecipes() async {
    final recipes = <Recipe>[];
    for (final block in WorkspacePaths.blocks) {
      recipes.addAll(await workspaceService.loadRecipes(block));
    }
    return List.unmodifiable(recipes);
  }

  Future<List<TagEntry>> loadWorkbenchTags() async {
    final tags = <TagEntry>[];
    for (final block in WorkspacePaths.blocks) {
      tags.addAll(await workspaceService.loadTags(block));
    }
    return List.unmodifiable(tags);
  }

  Future<Map<String, dynamic>> loadWorkbenchFilterRules() {
    return workspaceService.loadFilterRules();
  }

  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
  }) async {
    final snapshot = await _buildSnapshot(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
    await _writePersistentCache(
      request: _cacheRequest(
        includeLegacyCodex: includeLegacyCodex,
        legacyCodexLimit: legacyCodexLimit,
        legacyCodexQuery: legacyCodexQuery,
        legacyCodexCategoryKey: legacyCodexCategoryKey,
      ),
      snapshot: snapshot,
      sourceFingerprint: await _sourceFingerprint(),
    );
    return snapshot;
  }

  Future<StudioAssetCatalogSnapshot> _buildSnapshot({
    required bool includeLegacyCodex,
    required int legacyCodexLimit,
    required String legacyCodexQuery,
    required String legacyCodexCategoryKey,
  }) async {
    final characters = await _loadCatalogCharacters();
    final artistChains = await loadWorkbenchArtistChains();
    final workspaceInspirations = await workspaceService.loadInspirations();
    final catalogInspirations = workspaceInspirations
        .where((entry) => !isCodexSourceType(entry.source.type))
        .toList(growable: false);
    final workspaceCodexInspirations = workspaceInspirations
        .where((entry) => isCodexSourceType(entry.source.type))
        .toList(growable: false);
    final legacyCodex = includeLegacyCodex
        ? await _loadLegacyCodexInspirations(
            limit: legacyCodexLimit,
            query: legacyCodexQuery,
            categoryKey: legacyCodexCategoryKey,
            workspaceCodexEntries: workspaceCodexInspirations,
          )
        : const _LegacyCodexSlice.empty();
    final legacyCodexAvailable =
        workspaceCodexInspirations.isNotEmpty || await _hasLegacyCodexSource();
    final inspirations = [
      ...catalogInspirations,
      ...legacyCodex.entries,
    ];
    final loras = await workspaceService.loadLoras();
    final workflows = await workspaceService.loadWorkflows();
    final batchPlans = await workspaceService.loadBatchPlans();
    final assemblyPresets = await workspaceService.loadAssemblyPresets();
    final recipeCountsByBlock = <String, int>{};
    final tagCountsByBlock = <String, int>{};
    final outfits = _outfitsFromCharacters(characters);
    final recipes = <Recipe>[];
    final tags = <TagEntry>[];

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
      inspirationCount: catalogInspirations.length,
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
      legacyCodexTotalCount: legacyCodex.totalCount,
      legacyCodexLoadedCount: legacyCodex.entries.length,
      legacyCodexCategoryCounts: legacyCodex.categoryCounts,
      legacyCodexAvailable: legacyCodexAvailable,
    );
  }

  Map<String, dynamic> _cacheRequest({
    required bool includeLegacyCodex,
    required int legacyCodexLimit,
    required String legacyCodexQuery,
    required String legacyCodexCategoryKey,
  }) {
    return {
      'includeLegacyCodex': includeLegacyCodex,
      'legacyCodexLimit': legacyCodexLimit < 1 ? 1 : legacyCodexLimit,
      'legacyCodexQuery': legacyCodexQuery.trim(),
      'legacyCodexCategoryKey':
          StudioLegacyCodexCategories.normalizedKey(legacyCodexCategoryKey),
    };
  }

  Future<_PersistentCatalogCache?> _readPersistentCache(
    Map<String, dynamic> request,
  ) async {
    final file = _workspaceFile(WorkspacePaths.assetCatalogCache);
    if (file == null || !await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      final map = _jsonMap(decoded, 'asset catalog cache');
      if (map['schemaVersion'] == _cacheSchemaVersion) {
        final entries = _jsonMap(map['entries'], 'cache.entries');
        final entry = entries[_cacheEntryKey(request)];
        if (entry == null) return null;
        return _cacheEntryFromJson(entry, 'cache.entry');
      }
      if (map['schemaVersion'] == _singleEntryCacheSchemaVersion) {
        final cachedRequest = _jsonMap(map['request'], 'cache.request');
        if (!_sameJsonMap(cachedRequest, request)) return null;
        return _cacheEntryFromJson(map, 'cache');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePersistentCache({
    required Map<String, dynamic> request,
    required StudioAssetCatalogSnapshot snapshot,
    required Map<String, String> sourceFingerprint,
  }) async {
    final file = _workspaceFile(WorkspacePaths.assetCatalogCache);
    if (file == null) return;
    await file.parent.create(recursive: true);
    final entries = await _readPersistentCacheEntries(file);
    entries[_cacheEntryKey(request)] = _cacheEntryToJson(
      snapshot: snapshot,
      sourceFingerprint: sourceFingerprint,
    );
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': _cacheSchemaVersion,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': entries,
      }),
    );
  }

  Future<Map<String, dynamic>> _readPersistentCacheEntries(File file) async {
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      final map = _jsonMap(decoded, 'asset catalog cache');
      if (map['schemaVersion'] == _cacheSchemaVersion) {
        return _jsonMap(map['entries'], 'cache.entries');
      }
      if (map['schemaVersion'] == _singleEntryCacheSchemaVersion) {
        final request = _jsonMap(map['request'], 'cache.request');
        return <String, dynamic>{
          _cacheEntryKey(request): _cacheEntryToJson(
            snapshot: _snapshotFromJson(map['snapshot']),
            sourceFingerprint:
                _stringMap(map['sourceFingerprint'], 'cache.sourceFingerprint'),
          ),
        };
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _cacheEntryToJson({
    required StudioAssetCatalogSnapshot snapshot,
    required Map<String, String> sourceFingerprint,
  }) {
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceFingerprint': sourceFingerprint,
      'snapshot': _snapshotToJson(snapshot),
    };
  }

  _PersistentCatalogCache _cacheEntryFromJson(dynamic json, String label) {
    final map = _jsonMap(json, label);
    return _PersistentCatalogCache(
      snapshot: _snapshotFromJson(map['snapshot']),
      sourceFingerprint:
          _stringMap(map['sourceFingerprint'], '$label.sourceFingerprint'),
    );
  }

  String _cacheEntryKey(Map<String, dynamic> request) {
    final includeLegacyCodex = request['includeLegacyCodex'] == true ? 1 : 0;
    final limit = _intValue(request['legacyCodexLimit']);
    final query = (request['legacyCodexQuery'] ?? '').toString();
    final categoryKey = StudioLegacyCodexCategories.normalizedKey(
      (request['legacyCodexCategoryKey'] ?? '').toString(),
    );
    return [
      'codex=$includeLegacyCodex',
      'limit=$limit',
      'query=$query',
      'category=$categoryKey',
    ].join('|');
  }

  File? _workspaceFile(String relativePath) {
    final root = workspaceService.root;
    if (root == null) return null;
    return File(_join(root.path, relativePath));
  }

  Future<Map<String, String>> _sourceFingerprint() async {
    final root = workspaceService.root;
    if (root == null) return const {};
    final fingerprint = <String, String>{};
    for (final relativePath in [
      WorkspacePaths.characters,
      WorkspacePaths.artistChains,
      WorkspacePaths.inspirations,
      WorkspacePaths.loras,
      for (final block in WorkspacePaths.blocks)
        WorkspacePaths.recipeFile(block),
      for (final block in WorkspacePaths.blocks) WorkspacePaths.tagFile(block),
    ]) {
      await _addFileFingerprint(root, relativePath, fingerprint);
    }
    for (final relativeDir in [
      WorkspacePaths.batchPlansDir,
      WorkspacePaths.workflowsDir,
      WorkspacePaths.assemblyPresetsDir,
    ]) {
      await _addDirectoryFingerprint(root, relativeDir, fingerprint);
    }
    return Map.unmodifiable(fingerprint);
  }

  Future<void> _addFileFingerprint(
    Directory root,
    String relativePath,
    Map<String, String> fingerprint,
  ) async {
    final file = File(_join(root.path, relativePath));
    if (!await file.exists()) {
      fingerprint[relativePath] = 'missing';
      return;
    }
    final stat = await file.stat();
    fingerprint[relativePath] =
        '${stat.size}:${stat.modified.toUtc().microsecondsSinceEpoch}';
  }

  Future<void> _addDirectoryFingerprint(
    Directory root,
    String relativeDir,
    Map<String, String> fingerprint,
  ) async {
    final dir = Directory(_join(root.path, relativeDir));
    if (!await dir.exists()) {
      fingerprint['$relativeDir/'] = 'missing';
      return;
    }
    final files = await dir
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final normalizedRoot = root.path.replaceAll('\\', '/');
      final relativePath = normalizedPath
          .substring(normalizedRoot.length)
          .replaceFirst(RegExp(r'^/+'), '');
      final stat = await file.stat();
      fingerprint[relativePath] =
          '${stat.size}:${stat.modified.toUtc().microsecondsSinceEpoch}';
    }
  }

  bool _sameFingerprint(
    Map<String, String> left,
    Map<String, String> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _sameJsonMap(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  Map<String, dynamic> _summaryToJson(StudioAssetCatalogSummary summary) {
    return {
      'characterCount': summary.characterCount,
      'outfitCount': summary.outfitCount,
      'artistChainCount': summary.artistChainCount,
      'recipeCount': summary.recipeCount,
      'tagCount': summary.tagCount,
      'inspirationCount': summary.inspirationCount,
      'loraCount': summary.loraCount,
      'workflowCount': summary.workflowCount,
      'batchPlanCount': summary.batchPlanCount,
      'assemblyPresetCount': summary.assemblyPresetCount,
      'recipeCountsByBlock': summary.recipeCountsByBlock,
      'tagCountsByBlock': summary.tagCountsByBlock,
    };
  }

  StudioAssetCatalogSummary _summaryFromJson(dynamic json) {
    final map = _jsonMap(json, 'catalog.summary');
    return StudioAssetCatalogSummary(
      characterCount: _intValue(map['characterCount']),
      outfitCount: _intValue(map['outfitCount']),
      artistChainCount: _intValue(map['artistChainCount']),
      recipeCount: _intValue(map['recipeCount']),
      tagCount: _intValue(map['tagCount']),
      inspirationCount: _intValue(map['inspirationCount']),
      loraCount: _intValue(map['loraCount']),
      workflowCount: _intValue(map['workflowCount']),
      batchPlanCount: _intValue(map['batchPlanCount']),
      assemblyPresetCount: _intValue(map['assemblyPresetCount']),
      recipeCountsByBlock:
          _intMap(map['recipeCountsByBlock'], 'summary.recipeCountsByBlock'),
      tagCountsByBlock:
          _intMap(map['tagCountsByBlock'], 'summary.tagCountsByBlock'),
    );
  }

  Map<String, dynamic> _snapshotToJson(StudioAssetCatalogSnapshot snapshot) {
    return {
      'summary': _summaryToJson(snapshot.summary),
      'characters': snapshot.characters.map((entry) => entry.toJson()).toList(),
      'artistChains':
          snapshot.artistChains.map((entry) => entry.toJson()).toList(),
      'recipes': snapshot.recipes.map((entry) => entry.toJson()).toList(),
      'tags': snapshot.tags.map((entry) => entry.toJson()).toList(),
      'inspirations':
          snapshot.inspirations.map((entry) => entry.toJson()).toList(),
      'loras': snapshot.loras.map((entry) => entry.toJson()).toList(),
      'workflows': snapshot.workflows.map((entry) => entry.toJson()).toList(),
      'batchPlans': snapshot.batchPlans.map((entry) => entry.toJson()).toList(),
      'assemblyPresets':
          snapshot.assemblyPresets.map((entry) => entry.toJson()).toList(),
      'legacyCodexTotalCount': snapshot.legacyCodexTotalCount,
      'legacyCodexLoadedCount': snapshot.legacyCodexLoadedCount,
      'legacyCodexCategoryCounts': snapshot.legacyCodexCategoryCounts,
      'legacyCodexAvailable': snapshot.legacyCodexAvailable,
    };
  }

  StudioAssetCatalogSnapshot _snapshotFromJson(dynamic json) {
    final map = _jsonMap(json, 'catalog.snapshot');
    final characters = _list(map['characters'])
        .map(CharacterEntry.fromJson)
        .toList(growable: false);
    return StudioAssetCatalogSnapshot(
      summary: _summaryFromJson(map['summary']),
      characters: List.unmodifiable(characters),
      outfits: List.unmodifiable(_outfitsFromCharacters(characters)),
      artistChains: _list(map['artistChains'])
          .map(ArtistChain.fromJson)
          .toList(growable: false),
      recipes:
          _list(map['recipes']).map(Recipe.fromJson).toList(growable: false),
      tags: _list(map['tags']).map(TagEntry.fromJson).toList(growable: false),
      inspirations: _list(map['inspirations'])
          .map(InspirationEntry.fromJson)
          .toList(growable: false),
      loras:
          _list(map['loras']).map(LoraEntry.fromJson).toList(growable: false),
      workflows: _list(map['workflows'])
          .map(WorkflowEntry.fromJson)
          .toList(growable: false),
      batchPlans: _list(map['batchPlans'])
          .map(BatchPlan.fromJson)
          .toList(growable: false),
      assemblyPresets: _list(map['assemblyPresets'])
          .map(AssemblyPresetEntry.fromJson)
          .toList(growable: false),
      legacyCodexTotalCount: _intValue(map['legacyCodexTotalCount']),
      legacyCodexLoadedCount: _intValue(map['legacyCodexLoadedCount']),
      legacyCodexCategoryCounts: _intMap(
        map['legacyCodexCategoryCounts'],
        'snapshot.legacyCodexCategoryCounts',
      ),
      legacyCodexAvailable: map['legacyCodexAvailable'] == true,
    );
  }

  Map<String, dynamic> _jsonMap(dynamic value, String label) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw FormatException('$label must be a JSON object.');
  }

  List<dynamic> _list(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  Map<String, String> _stringMap(dynamic value, String label) {
    return _jsonMap(value, label).map(
      (key, value) => MapEntry(key, value.toString()),
    );
  }

  Map<String, int> _intMap(dynamic value, String label) {
    return _jsonMap(value, label).map(
      (key, value) => MapEntry(key, _intValue(value)),
    );
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  Future<List<CharacterEntry>> _loadCatalogCharacters() async {
    final characters = await workspaceService.loadCharacters();
    return List.unmodifiable(
      characters.map(_sanitizeCharacterForCatalog).toList(growable: false),
    );
  }

  CharacterEntry _sanitizeCharacterForCatalog(CharacterEntry character) {
    if (character.outfits.isEmpty) return character;

    final legacyArtistWorkbook =
        character.source.type == 'legacy_artist_workbook';
    final outfits = <WorkspaceOutfit>[];
    final byName = <String, int>{};
    var changed = false;

    for (final outfit in character.outfits) {
      if (legacyArtistWorkbook && _isLowConfidenceLegacyOutfit(outfit)) {
        changed = true;
        continue;
      }

      final normalizedName = _normalizedOutfitName(outfit.name);
      final existingIndex =
          legacyArtistWorkbook ? byName[normalizedName] : null;
      if (existingIndex != null) {
        outfits[existingIndex] = _mergeOutfitImageRefs(
          outfits[existingIndex],
          outfit.imageRefs,
        );
        changed = true;
        continue;
      }

      final normalizedOutfit = outfit.imageRefs.isEmpty &&
              character.imageRefs.isNotEmpty &&
              legacyArtistWorkbook
          ? _mergeOutfitImageRefs(outfit, character.imageRefs)
          : outfit;
      if (!identical(normalizedOutfit, outfit)) changed = true;
      outfits.add(normalizedOutfit);
      if (legacyArtistWorkbook) {
        byName[normalizedName] = outfits.length - 1;
      }
    }

    final defaultOutfitId = _catalogDefaultOutfitId(
      character.defaultOutfitId,
      outfits,
    );
    if (defaultOutfitId != character.defaultOutfitId) changed = true;

    if (!changed) return character;
    return character.copyWith(
      outfits: List.unmodifiable(outfits),
      defaultOutfitId: defaultOutfitId,
    );
  }

  bool _isLowConfidenceLegacyOutfit(WorkspaceOutfit outfit) {
    final name = outfit.name.trim();
    if (name.isEmpty) return true;
    final hasGenericLegacyName = RegExp(
      r'^(变体\s*\d+|服装|outfit|variant\s*\d+|imported outfit|preset\s*\d+)$',
      caseSensitive: false,
    ).hasMatch(name);
    return hasGenericLegacyName && !_hasStructuredOutfitPrompt(outfit);
  }

  bool _hasStructuredOutfitPrompt(WorkspaceOutfit outfit) {
    return (outfit.tags.frontUpper?.trim().isNotEmpty ?? false) ||
        (outfit.tags.frontLower?.trim().isNotEmpty ?? false) ||
        outfit.partTags.upperBodyTags.isNotEmpty ||
        outfit.partTags.upperClothingTags.isNotEmpty ||
        outfit.partTags.lowerBodyTags.isNotEmpty ||
        outfit.partTags.lowerClothingTags.isNotEmpty;
  }

  String _normalizedOutfitName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  WorkspaceOutfit _mergeOutfitImageRefs(
    WorkspaceOutfit outfit,
    List<String> imageRefs,
  ) {
    final refs = <String>[...outfit.imageRefs];
    var changed = false;
    for (final ref in imageRefs) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty || refs.contains(trimmed)) continue;
      refs.add(trimmed);
      changed = true;
    }
    if (!changed) return outfit;
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: outfit.tags,
      partTags: outfit.partTags,
      imageRefs: List.unmodifiable(refs),
      note: outfit.note,
    );
  }

  String? _catalogDefaultOutfitId(
    String? defaultOutfitId,
    List<WorkspaceOutfit> outfits,
  ) {
    if (defaultOutfitId != null &&
        outfits.any((outfit) => outfit.id == defaultOutfitId)) {
      return defaultOutfitId;
    }
    return outfits.isEmpty ? null : outfits.first.id;
  }

  Future<_LegacyCodexSlice> _loadLegacyCodexInspirations({
    required int limit,
    required String query,
    required String categoryKey,
    List<InspirationEntry> workspaceCodexEntries = const [],
  }) async {
    final allEntries = _mergedCodexEntries(
      workspaceCodexEntries,
      await _loadAllLegacyCodexInspirations(),
    );
    final normalizedQuery = query.trim().toLowerCase();
    final queryFiltered = normalizedQuery.isEmpty
        ? allEntries
        : allEntries
            .where((entry) => _matchesCodexQuery(entry, normalizedQuery))
            .toList(growable: false);
    final categoryCounts =
        StudioLegacyCodexCategories.countByCategory(queryFiltered);
    final normalizedCategory =
        StudioLegacyCodexCategories.normalizedKey(categoryKey);
    final filtered = normalizedCategory == StudioLegacyCodexCategories.allKey
        ? queryFiltered
        : queryFiltered
            .where(
              (entry) => StudioLegacyCodexCategories.matches(
                  entry, normalizedCategory),
            )
            .toList(growable: false);
    final safeLimit = limit < 1 ? 1 : limit;
    return _LegacyCodexSlice(
      entries: filtered.take(safeLimit).toList(growable: false),
      totalCount: filtered.length,
      categoryCounts: categoryCounts,
    );
  }

  List<InspirationEntry> _mergedCodexEntries(
    List<InspirationEntry> workspaceEntries,
    List<InspirationEntry> bundledEntries,
  ) {
    if (workspaceEntries.isEmpty) return bundledEntries;
    if (bundledEntries.isEmpty) return workspaceEntries;

    final byKey = <String, InspirationEntry>{};
    void addEntry(InspirationEntry entry) {
      final id = entry.id.trim();
      final key = id.isNotEmpty
          ? id
          : [
              entry.source.type,
              entry.source.id ?? '',
              entry.name,
              entry.prompt,
            ].join('\n');
      byKey.putIfAbsent(key, () => entry);
    }

    for (final entry in workspaceEntries) {
      addEntry(entry);
    }
    for (final entry in bundledEntries) {
      addEntry(entry);
    }
    return List.unmodifiable(byKey.values);
  }

  Future<List<InspirationEntry>> _loadAllLegacyCodexInspirations() async {
    final cached = _legacyCodexCache;
    if (cached != null) return cached;
    if (legacyCodexLoader != null) {
      final entries = await legacyCodexLoader!.call();
      _legacyCodexCache = entries;
      return entries;
    }
    try {
      final raw = await rootBundle.loadString(
        'assets/json/legacy_codex_seed.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final entries = await StudioDataService(
        workspaceService: workspaceService,
        legacyCodexSeedLoader: () async => decoded,
      ).loadLegacyCodexSeedEntries();
      _legacyCodexCache = entries;
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> _hasLegacyCodexSource() async {
    if (legacyCodexLoader != null) return true;
    final cached = _legacyCodexCache;
    if (cached != null) return cached.isNotEmpty;
    final cachedAvailability = _legacyCodexAvailabilityCache;
    if (cachedAvailability != null) return cachedAvailability;
    try {
      final raw = await rootBundle.loadString(
        'assets/json/legacy_codex_seed.json',
      );
      final available = raw.trim().isNotEmpty;
      _legacyCodexAvailabilityCache = available;
      return available;
    } catch (_) {
      _legacyCodexAvailabilityCache = false;
      return false;
    }
  }

  bool _matchesCodexQuery(InspirationEntry entry, String normalizedQuery) {
    return [
      entry.name,
      entry.prompt,
      entry.negativePrompt,
      entry.tags.join(' '),
      entry.note,
    ].join('\n').toLowerCase().contains(normalizedQuery);
  }

  String _join(String root, String path) {
    final normalized = path.replaceAll('\\', '/');
    return [
      root,
      ...normalized
          .split('/')
          .where((segment) => segment.isNotEmpty && segment != '.'),
    ].join(Platform.pathSeparator);
  }
}

class _LegacyCodexSlice {
  final List<InspirationEntry> entries;
  final int totalCount;
  final Map<String, int> categoryCounts;

  const _LegacyCodexSlice({
    required this.entries,
    required this.totalCount,
    required this.categoryCounts,
  });

  const _LegacyCodexSlice.empty()
      : entries = const [],
        totalCount = 0,
        categoryCounts = const {};
}

class _PersistentCatalogCache {
  final StudioAssetCatalogSnapshot snapshot;
  final Map<String, String> sourceFingerprint;

  const _PersistentCatalogCache({
    required this.snapshot,
    required this.sourceFingerprint,
  });
}
