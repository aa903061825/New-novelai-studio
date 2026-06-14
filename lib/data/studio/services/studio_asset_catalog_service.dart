import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
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
  final Map<String, String> sourceFingerprint;

  const StudioAssetCatalogCacheLoadResult({
    required this.snapshot,
    required this.fromCache,
    required this.isStale,
    this.sourceFingerprint = const {},
  });
}

class StudioAssetCatalogService {
  static const _cacheSchemaVersion = 5;
  static const _singleEntryCacheSchemaVersion = 2;
  static final _genericLegacyOutfitNamePattern = RegExp(
    r'^(变体\s*\d+|服装|outfit|variant\s*\d+|imported outfit|preset\s*\d+)$',
    caseSensitive: false,
  );
  static final _catalogClothingTagPattern = RegExp(
    r'(^|_)(apron|armor|belt|bikini|blouse|bodystocking|bodysuit|boot|boots|cape|capelet|china_dress|chinese_clothes|clothes|clothing|coat|detached_sleeves|dress|glove|gloves|hood|hoodie|jacket|japanese_clothes|kimono|kneehighs|leggings|pants|pantyhose|pelvic_curtain|robe|sandal|sandals|shirt|shoe|shoes|shorts|skirt|sock|socks|stocking|stockings|sweater|swimsuit|thigh_boots|thighhighs|thigh_highs|uniform|vest)($|_)',
  );
  static final _catalogBodyTagPattern = RegExp(
    r'(^|_)(ahoge|animal|animal_ear|animal_ears|bangs|bare_shoulders|bell|blonde_hair|blue_eyes|blue_hair|bow|braid|brown_eyes|brown_hair|cat_ears|cat_girl|cat_tail|cherry_blossoms|choker|collar|collarbone|dog_ears|dog_girl|ear|ears|eye|eyes|fang|fluffy_tail|fox_ears|girl|green_eyes|green_hair|hair|hair_between_eyes|hair_ornament|hair_ribbon|head|headpiece|horn|horns|infection_monitor|leg|legs|loli|long_hair|necklace|ornament|pink_eyes|pink_hair|pointy_ears|purple_eyes|red_eyes|red_hair|ribbon|sheep_ears|sheep_horns|short_hair|skin|solo|tail|thigh|thighs|very_long_hair|white_hair|yellow_eyes)($|_)',
  );

  final WorkspaceService workspaceService;
  final Future<List<InspirationEntry>> Function()? legacyCodexLoader;
  List<InspirationEntry>? _legacyCodexCache;
  bool? _legacyCodexAvailabilityCache;
  final Map<String, List<String>> _legacyCodexCategoryKeyCache = {};

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
        sourceFingerprint: cached.sourceFingerprint,
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

  Future<bool> isSourceFingerprintStale(
    Map<String, String> sourceFingerprint,
  ) async {
    return !_sameFingerprint(sourceFingerprint, await _sourceFingerprint());
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
    final legacyArtistWorkbook =
        character.source.type == 'legacy_artist_workbook';
    final normalizedCharacter = legacyArtistWorkbook
        ? _normalizeLegacyCharacterIdentityFields(character)
        : character;
    var changed = !identical(normalizedCharacter, character);
    if (normalizedCharacter.outfits.isEmpty) return normalizedCharacter;

    final preparedOutfits = legacyArtistWorkbook
        ? _mergeIdentityOnlyGenericLegacyOutfitsIntoDefault(normalizedCharacter)
        : (outfits: normalizedCharacter.outfits, changed: false);
    final outfits = <WorkspaceOutfit>[];
    final byName = <String, int>{};
    final bySignature = <String, int>{};
    changed = changed || preparedOutfits.changed;

    for (final rawOutfit in preparedOutfits.outfits) {
      var outfit = rawOutfit;
      if (legacyArtistWorkbook && _isLowConfidenceLegacyOutfit(outfit)) {
        changed = true;
        continue;
      }
      if (legacyArtistWorkbook) {
        final normalizedIdentityOutfit =
            _normalizeLegacyOutfitIdentityFields(outfit);
        if (!identical(normalizedIdentityOutfit, outfit)) changed = true;
        outfit = normalizedIdentityOutfit;
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

      final normalizedSignature =
          legacyArtistWorkbook ? _normalizedOutfitSignature(outfit) : '';
      final existingSignatureIndex =
          normalizedSignature.isEmpty ? null : bySignature[normalizedSignature];
      if (existingSignatureIndex != null) {
        final existing = outfits[existingSignatureIndex];
        final preferred = _prefersLegacyOutfit(
          outfit,
          existing,
          normalizedCharacter.defaultOutfitId,
        )
            ? _mergeOutfitImageRefs(outfit, existing.imageRefs)
            : _mergeOutfitImageRefs(existing, outfit.imageRefs);
        outfits[existingSignatureIndex] = preferred;
        if (legacyArtistWorkbook) {
          byName[_normalizedOutfitName(preferred.name)] =
              existingSignatureIndex;
          bySignature[normalizedSignature] = existingSignatureIndex;
        }
        changed = true;
        continue;
      }

      final normalizedOutfit = outfit.imageRefs.isEmpty &&
              normalizedCharacter.imageRefs.isNotEmpty &&
              legacyArtistWorkbook
          ? _mergeOutfitImageRefs(outfit, normalizedCharacter.imageRefs)
          : outfit;
      if (!identical(normalizedOutfit, outfit)) changed = true;
      outfits.add(normalizedOutfit);
      if (legacyArtistWorkbook) {
        final index = outfits.length - 1;
        byName[normalizedName] = index;
        if (normalizedSignature.isNotEmpty) {
          bySignature[normalizedSignature] = index;
        }
      }
    }

    final defaultOutfitId = _catalogDefaultOutfitId(
      normalizedCharacter.defaultOutfitId,
      outfits,
    );
    if (defaultOutfitId != normalizedCharacter.defaultOutfitId) changed = true;

    if (!changed) return normalizedCharacter;
    return normalizedCharacter.copyWith(
      outfits: List.unmodifiable(outfits),
      defaultOutfitId: defaultOutfitId,
    );
  }

  CharacterEntry _normalizeLegacyCharacterIdentityFields(
    CharacterEntry character,
  ) {
    final traits = character.traits;
    final normalizedTraits = ViewVariantTexts(
      frontFull: _normalizeLegacyCharacterIdentityPrompt(traits.frontFull),
      frontCowboy:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.frontCowboy),
      frontUpper:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.frontUpper),
      frontLower:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.frontLower),
      backFull:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.backFull),
      backCowboy:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.backCowboy),
      backUpper:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.backUpper),
      backLower:
          _normalizeLegacyCharacterOptionalIdentityPrompt(traits.backLower),
    );
    final normalizedAnchorTags =
        _normalizeLegacyCharacterIdentityTagList(character.anchorTags);
    final normalizedIdentityTags =
        _normalizeLegacyCharacterIdentityTagList(character.identityTags);

    if (normalizedTraits.frontFull == traits.frontFull &&
        normalizedTraits.frontCowboy == traits.frontCowboy &&
        normalizedTraits.frontUpper == traits.frontUpper &&
        normalizedTraits.frontLower == traits.frontLower &&
        normalizedTraits.backFull == traits.backFull &&
        normalizedTraits.backCowboy == traits.backCowboy &&
        normalizedTraits.backUpper == traits.backUpper &&
        normalizedTraits.backLower == traits.backLower &&
        _sameStringList(normalizedAnchorTags, character.anchorTags) &&
        _sameStringList(normalizedIdentityTags, character.identityTags)) {
      return character;
    }

    return character.copyWith(
      traits: normalizedTraits,
      anchorTags: normalizedAnchorTags,
      identityTags: normalizedIdentityTags,
    );
  }

  WorkspaceOutfit _normalizeLegacyOutfitIdentityFields(
    WorkspaceOutfit outfit,
  ) {
    final frontFull =
        _normalizeLegacyOutfitIdentityPrompt(outfit.tags.frontFull);
    if (frontFull == outfit.tags.frontFull) return outfit;
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: ViewVariantTexts(
        frontFull: frontFull,
        frontCowboy: outfit.tags.frontCowboy,
        frontUpper: outfit.tags.frontUpper,
        frontLower: outfit.tags.frontLower,
        backFull: outfit.tags.backFull,
        backCowboy: outfit.tags.backCowboy,
        backUpper: outfit.tags.backUpper,
        backLower: outfit.tags.backLower,
      ),
      partTags: outfit.partTags,
      imageRefs: outfit.imageRefs,
      negativePrompt: outfit.negativePrompt,
      note: outfit.note,
    );
  }

  String _normalizeLegacyOutfitIdentityPrompt(String prompt) {
    final tags = PromptTagProcessor.splitWorkshopTags(prompt)
        .map((tag) => PromptTagProcessor.cleanTagDisplay(
              tag,
              removeWeights: false,
            ).trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (tags.isEmpty) return prompt;

    final originalByKey = <String, String>{};
    for (final tag in tags) {
      final key = _catalogPromptKey(tag);
      if (key.isNotEmpty) {
        originalByKey.putIfAbsent(key, () => tag);
      }
    }

    final normalized = <String>[];
    final written = <String>{};
    for (final tag in tags) {
      final baseTag = _legacySkinVariantBaseIdentityDisplay(tag);
      if (baseTag != null) {
        final baseKey = _catalogPromptKey(baseTag);
        final baseDisplay = originalByKey[baseKey] ?? baseTag;
        if (baseKey.isNotEmpty && written.add(baseKey)) {
          normalized.add(baseDisplay);
        }
      }
      final tagKey = _catalogPromptKey(tag);
      if (tagKey.isNotEmpty && written.add(tagKey)) {
        normalized.add(tag);
      }
    }

    final normalizedPrompt = normalized.join(', ');
    return normalizedPrompt == prompt ? prompt : normalizedPrompt;
  }

  String? _normalizeLegacyCharacterOptionalIdentityPrompt(String? prompt) {
    if (prompt == null) return null;
    return _normalizeLegacyCharacterIdentityPrompt(prompt);
  }

  String _normalizeLegacyCharacterIdentityPrompt(String prompt) {
    final tags = PromptTagProcessor.splitWorkshopTags(prompt);
    var changed = false;
    final normalized = [
      for (final tag in tags)
        _normalizeLegacyCharacterIdentityTag(
          tag,
          onChanged: () => changed = true,
        ),
    ];
    if (!changed) return prompt;
    return _mergePromptTagLists(normalized).join(', ');
  }

  List<String> _normalizeLegacyCharacterIdentityTagList(List<String> tags) {
    var changed = false;
    final normalized = <String>[];
    for (final tag in tags) {
      for (final splitTag in PromptTagProcessor.splitWorkshopTags(tag)) {
        normalized.add(
          _normalizeLegacyCharacterIdentityTag(
            splitTag,
            onChanged: () => changed = true,
          ),
        );
      }
    }
    if (!changed) return tags;
    return _mergePromptTagLists(normalized);
  }

  String _normalizeLegacyCharacterIdentityTag(
    String tag, {
    required void Function() onChanged,
  }) {
    final descriptor = PromptTagProcessor.describeWorkshopTag(tag);
    final baseTag =
        _legacySkinVariantBaseIdentityTag(descriptor.displayText.trim());
    if (baseTag == null) return tag;
    onChanged();
    final weight = descriptor.weight;
    if (weight == null) return baseTag;
    return PromptTagProcessor.formatInlineWeightTag(baseTag, weight);
  }

  String? _legacySkinVariantBaseIdentityDisplay(String tag) {
    final descriptor = PromptTagProcessor.describeWorkshopTag(tag);
    final baseTag =
        _legacySkinVariantBaseIdentityTag(descriptor.displayText.trim());
    if (baseTag == null) return null;
    final weight = descriptor.weight;
    if (weight == null) return baseTag;
    return PromptTagProcessor.formatInlineWeightTag(baseTag, weight);
  }

  String? _legacySkinVariantBaseIdentityTag(String tag) {
    final value = tag.trim();
    if (value.isEmpty || value.contains(':')) return null;
    final match = RegExp(r'^(.+?)([_\s])(?:\([^()]+\)[_\s])+\(([^()]+)\)$')
        .firstMatch(value);
    if (match == null) return null;
    final baseName = match.group(1)?.trim();
    final series = match.group(3)?.trim();
    if (baseName == null ||
        baseName.isEmpty ||
        series == null ||
        series.isEmpty) {
      return null;
    }
    final separator = match.group(2) == '_' ? '_' : ' ';
    return '$baseName$separator($series)';
  }

  bool _sameStringList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  ({List<WorkspaceOutfit> outfits, bool changed})
      _mergeIdentityOnlyGenericLegacyOutfitsIntoDefault(
    CharacterEntry character,
  ) {
    final defaultIndex = _legacyDefaultOutfitIndex(character);
    if (defaultIndex < 0) {
      return (outfits: character.outfits, changed: false);
    }

    var defaultOutfit = character.outfits[defaultIndex];
    final kept = <WorkspaceOutfit>[];
    var changed = false;

    for (var index = 0; index < character.outfits.length; index += 1) {
      final outfit = character.outfits[index];
      if (index != defaultIndex &&
          _shouldMergeGenericLegacyOutfitIntoDefault(outfit)) {
        defaultOutfit = _mergeLegacyOutfitIntoDefault(defaultOutfit, outfit);
        changed = true;
        continue;
      }
      kept.add(outfit);
    }

    if (!changed) return (outfits: character.outfits, changed: false);
    final keptDefaultIndex =
        kept.indexWhere((outfit) => outfit.id == defaultOutfit.id);
    if (keptDefaultIndex >= 0) {
      kept[keptDefaultIndex] = defaultOutfit;
    }
    return (outfits: List.unmodifiable(kept), changed: true);
  }

  int _legacyDefaultOutfitIndex(CharacterEntry character) {
    if (character.defaultOutfitId != null) {
      final explicitIndex = character.outfits.indexWhere(
        (outfit) => outfit.id == character.defaultOutfitId,
      );
      if (explicitIndex >= 0) return explicitIndex;
    }
    return character.outfits.indexWhere(
      (outfit) => outfit.id == 'default-outfit',
    );
  }

  bool _shouldMergeGenericLegacyOutfitIntoDefault(WorkspaceOutfit outfit) {
    return _isGenericLegacyOutfitName(outfit.name) &&
        _hasStructuredClothingPrompt(outfit) &&
        _hasIdentityOnlyFrontFullPrompt(outfit);
  }

  WorkspaceOutfit _mergeLegacyOutfitIntoDefault(
    WorkspaceOutfit defaultOutfit,
    WorkspaceOutfit supplement,
  ) {
    return WorkspaceOutfit(
      id: defaultOutfit.id,
      name: defaultOutfit.name,
      tags: ViewVariantTexts(
        frontFull: defaultOutfit.tags.frontFull,
        frontCowboy: defaultOutfit.tags.frontCowboy,
        frontUpper: _mergeOptionalPromptValues(
          defaultOutfit.tags.frontUpper,
          supplement.tags.frontUpper,
        ),
        frontLower: _mergeOptionalPromptValues(
          defaultOutfit.tags.frontLower,
          supplement.tags.frontLower,
        ),
        backFull: defaultOutfit.tags.backFull,
        backCowboy: defaultOutfit.tags.backCowboy,
        backUpper: defaultOutfit.tags.backUpper,
        backLower: defaultOutfit.tags.backLower,
      ),
      partTags: WorkspaceOutfitPartTags(
        upperBodyTags: _mergePromptTagLists([
          ...defaultOutfit.partTags.upperBodyTags,
          ...supplement.partTags.upperBodyTags,
        ]),
        upperClothingTags: _mergePromptTagLists([
          ...defaultOutfit.partTags.upperClothingTags,
          ...supplement.partTags.upperClothingTags,
        ]),
        lowerBodyTags: _mergePromptTagLists([
          ...defaultOutfit.partTags.lowerBodyTags,
          ...supplement.partTags.lowerBodyTags,
        ]),
        lowerClothingTags: _mergePromptTagLists([
          ...defaultOutfit.partTags.lowerClothingTags,
          ...supplement.partTags.lowerClothingTags,
        ]),
        weaponTags: _mergePromptTagLists([
          ...defaultOutfit.partTags.weaponTags,
          ...supplement.partTags.weaponTags,
        ]),
      ),
      imageRefs: _mergeImageRefLists(
        defaultOutfit.imageRefs,
        supplement.imageRefs,
      ),
      negativePrompt: defaultOutfit.negativePrompt,
      note: defaultOutfit.note,
    );
  }

  bool _isLowConfidenceLegacyOutfit(WorkspaceOutfit outfit) {
    final name = outfit.name.trim();
    if (name.isEmpty) return true;
    final hasGenericLegacyName = _isGenericLegacyOutfitName(name);
    return hasGenericLegacyName && !_hasStructuredOutfitPrompt(outfit);
  }

  bool _isGenericLegacyOutfitName(String name) {
    return _genericLegacyOutfitNamePattern.hasMatch(name.trim());
  }

  bool _hasStructuredOutfitPrompt(WorkspaceOutfit outfit) {
    return (outfit.tags.frontUpper?.trim().isNotEmpty ?? false) ||
        (outfit.tags.frontLower?.trim().isNotEmpty ?? false) ||
        outfit.partTags.upperBodyTags.isNotEmpty ||
        outfit.partTags.upperClothingTags.isNotEmpty ||
        outfit.partTags.lowerBodyTags.isNotEmpty ||
        outfit.partTags.lowerClothingTags.isNotEmpty;
  }

  bool _hasStructuredClothingPrompt(WorkspaceOutfit outfit) {
    return (outfit.tags.frontUpper?.trim().isNotEmpty ?? false) ||
        (outfit.tags.frontLower?.trim().isNotEmpty ?? false) ||
        outfit.partTags.upperClothingTags.isNotEmpty ||
        outfit.partTags.lowerClothingTags.isNotEmpty ||
        outfit.partTags.weaponTags.isNotEmpty;
  }

  bool _hasIdentityOnlyFrontFullPrompt(WorkspaceOutfit outfit) {
    final tags = _promptTagsFromValue(outfit.tags.frontFull);
    if (tags.isEmpty) return false;
    final bodyKeys = {
      ...outfit.partTags.upperBodyTags.map(_catalogPromptKey),
      ...outfit.partTags.lowerBodyTags.map(_catalogPromptKey),
    };
    var identityCount = 0;
    for (final tag in tags) {
      final key = _catalogPromptKey(tag);
      if (key.isEmpty) continue;
      if (_isCatalogClothingKey(key)) return false;
      if (bodyKeys.contains(key) || _isCatalogBodyKey(key)) {
        identityCount += 1;
      }
    }
    return identityCount == tags.length || identityCount / tags.length >= 0.75;
  }

  String _normalizedOutfitSignature(WorkspaceOutfit outfit) {
    final tags = [
      ...outfit.partTags.upperClothingTags,
      ...outfit.partTags.lowerClothingTags,
      ...outfit.partTags.weaponTags,
    ];
    if (tags.isEmpty) {
      tags.addAll(_promptTagsFromValue(outfit.tags.frontUpper ?? ''));
      tags.addAll(_promptTagsFromValue(outfit.tags.frontLower ?? ''));
    }
    if (tags.isEmpty) {
      tags.addAll(
        _promptTagsFromValue(outfit.tags.frontFull).where(
          (tag) => _isCatalogClothingKey(_catalogPromptKey(tag)),
        ),
      );
    }
    final keys = {
      for (final tag in tags)
        if (_catalogPromptKey(tag).isNotEmpty) _catalogPromptKey(tag),
    }.toList()
      ..sort();
    return keys.join('|');
  }

  bool _prefersLegacyOutfit(
    WorkspaceOutfit candidate,
    WorkspaceOutfit existing,
    String? defaultOutfitId,
  ) {
    return _legacyOutfitQualityScore(candidate, defaultOutfitId) >
        _legacyOutfitQualityScore(existing, defaultOutfitId);
  }

  double _legacyOutfitQualityScore(
    WorkspaceOutfit outfit,
    String? defaultOutfitId,
  ) {
    var score = 0.0;
    if (!_isGenericLegacyOutfitName(outfit.name)) score += 10;
    if (outfit.id == defaultOutfitId || outfit.id == 'default-outfit') {
      score -= 2;
    }
    if (_promptTagsFromValue(outfit.tags.frontFull).any(
      (tag) => _isCatalogClothingKey(_catalogPromptKey(tag)),
    )) {
      score += 1;
    }
    if (outfit.imageRefs.isNotEmpty) score += 0.1;
    return score;
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

  List<String> _promptTagsFromValue(String value) {
    return PromptTagProcessor.splitWorkshopTags(value)
        .map(PromptTagProcessor.cleanTagDisplay)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  String _catalogPromptKey(String tag) {
    return PromptTagProcessor.normalizeMatchKey(tag)
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  bool _isCatalogClothingKey(String key) {
    return _catalogClothingTagPattern.hasMatch(key);
  }

  bool _isCatalogBodyKey(String key) {
    return _catalogBodyTagPattern.hasMatch(key) ||
        key == '1girl' ||
        key == 'girl' ||
        key == 'solo';
  }

  String? _mergeOptionalPromptValues(String? first, String? second) {
    final merged = _mergePromptTagLists([
      ..._promptTagsFromValue(first ?? ''),
      ..._promptTagsFromValue(second ?? ''),
    ]);
    if (merged.isEmpty) return null;
    return merged.join(', ');
  }

  List<String> _mergePromptTagLists(Iterable<String> values) {
    final seen = <String>{};
    final merged = <String>[];
    for (final raw in values) {
      final tag = PromptTagProcessor.cleanTagDisplay(raw).trim();
      final key = _catalogPromptKey(tag);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      merged.add(tag);
    }
    return List.unmodifiable(merged);
  }

  List<String> _mergeImageRefLists(
    List<String> first,
    List<String> second,
  ) {
    final refs = <String>[...first];
    for (final ref in second) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty || refs.contains(trimmed)) continue;
      refs.add(trimmed);
    }
    return List.unmodifiable(refs);
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
    final normalizedCategory =
        StudioLegacyCodexCategories.normalizedKey(categoryKey);
    final filtered = <InspirationEntry>[];
    final categoryCounts = _emptyLegacyCodexCategoryCounts(
      allCount: queryFiltered.length,
    );
    if (normalizedCategory == StudioLegacyCodexCategories.allKey) {
      filtered.addAll(queryFiltered);
    } else {
      for (final entry in queryFiltered) {
        final categoryKeys = _legacyCodexCategoryKeysFor(entry);
        for (final key in categoryKeys) {
          categoryCounts[key] = (categoryCounts[key] ?? 0) + 1;
        }
        if (categoryKeys.contains(normalizedCategory)) {
          filtered.add(entry);
        }
      }
    }
    final safeLimit = limit < 1 ? 1 : limit;
    return _LegacyCodexSlice(
      entries: filtered.take(safeLimit).toList(growable: false),
      totalCount: filtered.length,
      categoryCounts: Map.unmodifiable(categoryCounts),
    );
  }

  Map<String, int> _emptyLegacyCodexCategoryCounts({
    required int allCount,
  }) {
    return {
      StudioLegacyCodexCategories.allKey: allCount,
      for (final category in StudioLegacyCodexCategories.filters.skip(1))
        category.key: 0,
    };
  }

  List<String> _legacyCodexCategoryKeysFor(InspirationEntry entry) {
    final cacheKey = _legacyCodexCategoryCacheKey(entry);
    return _legacyCodexCategoryKeyCache.putIfAbsent(
      cacheKey,
      () => StudioLegacyCodexCategories.keysFor(entry),
    );
  }

  String _legacyCodexCategoryCacheKey(InspirationEntry entry) {
    return [
      entry.id,
      entry.name,
      entry.prompt,
      entry.negativePrompt,
      entry.tags.join('\u0001'),
      entry.note,
      entry.source.type,
      entry.source.id ?? '',
      entry.source.path ?? '',
    ].join('\u0002');
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
