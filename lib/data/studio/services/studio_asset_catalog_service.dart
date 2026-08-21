import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:novel_studio/data/studio/studio_data_service.dart';
import 'package:novel_studio/data/studio/studio_codex_source.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

part 'studio_codex_index.dart';

dynamic _decodeAssetCatalogCacheFile(String path) {
  return jsonDecode(File(path).readAsStringSync());
}

class _AssetCatalogPersistentCacheReadRequest {
  final String path;
  final Map<String, dynamic> request;

  const _AssetCatalogPersistentCacheReadRequest({
    required this.path,
    required this.request,
  });
}

class _AssetCatalogPersistentCacheWriteRequest {
  final String path;
  final Map<String, dynamic> request;
  final StudioAssetCatalogSnapshot snapshot;
  final Map<String, String> sourceFingerprint;

  const _AssetCatalogPersistentCacheWriteRequest({
    required this.path,
    required this.request,
    required this.snapshot,
    required this.sourceFingerprint,
  });
}

_PersistentCatalogCache? _readAssetCatalogPersistentCacheFromFile(
  _AssetCatalogPersistentCacheReadRequest request,
) {
  try {
    final decoded = _decodeAssetCatalogCacheFile(request.path);
    final map = StudioAssetCatalogService._jsonMap(
      decoded,
      'asset catalog cache',
    );
    if (map['schemaVersion'] == StudioAssetCatalogService._cacheSchemaVersion) {
      final entries = StudioAssetCatalogService._jsonMap(
        map['entries'],
        'cache.entries',
      );
      if (request.request['includeLegacyCodex'] == true) {
        return StudioAssetCatalogService._readCompatibleCodexCacheEntry(
          request: request.request,
          entries: entries,
          readEntry: (key, entry) =>
              StudioAssetCatalogService._cacheEntryFromJson(
            entry,
            'cache.entry.$key',
          ),
        );
      }
      final entry =
          entries[StudioAssetCatalogService._cacheEntryKey(request.request)];
      if (entry == null) return null;
      return StudioAssetCatalogService._cacheEntryFromJson(
        entry,
        'cache.entry',
      );
    }
    if (map['schemaVersion'] ==
        StudioAssetCatalogService._singleEntryCacheSchemaVersion) {
      final cachedRequest = StudioAssetCatalogService._jsonMap(
        map['request'],
        'cache.request',
      );
      if (!StudioAssetCatalogService._sameJsonMap(
        cachedRequest,
        request.request,
      )) {
        return null;
      }
      return StudioAssetCatalogService._cacheEntryFromJson(map, 'cache');
    }
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, dynamic> _readAssetCatalogPersistentCacheEntriesFromFile(
  String path,
) {
  try {
    final file = File(path);
    if (!file.existsSync()) return <String, dynamic>{};
    final decoded = _decodeAssetCatalogCacheFile(path);
    final map = StudioAssetCatalogService._jsonMap(
      decoded,
      'asset catalog cache',
    );
    if (map['schemaVersion'] == StudioAssetCatalogService._cacheSchemaVersion) {
      return StudioAssetCatalogService._jsonMap(
        map['entries'],
        'cache.entries',
      );
    }
    if (map['schemaVersion'] ==
        StudioAssetCatalogService._singleEntryCacheSchemaVersion) {
      final request = StudioAssetCatalogService._jsonMap(
        map['request'],
        'cache.request',
      );
      return <String, dynamic>{
        StudioAssetCatalogService._cacheEntryKey(request):
            StudioAssetCatalogService._cacheEntryToJson(
          _PersistentCatalogCache(
            snapshot: StudioAssetCatalogService._snapshotFromJson(
              map['snapshot'],
            ),
            sourceFingerprint: StudioAssetCatalogService._stringMap(
              map['sourceFingerprint'],
              'cache.sourceFingerprint',
            ),
          ),
        ),
      };
    }
  } catch (_) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{};
}

void _writeAssetCatalogPersistentCacheFile(
  _AssetCatalogPersistentCacheWriteRequest request,
) {
  final file = File(request.path);
  final cacheEntry = _PersistentCatalogCache(
    snapshot: request.snapshot,
    sourceFingerprint: request.sourceFingerprint,
  );
  final cacheKey = StudioAssetCatalogService._cacheEntryKey(request.request);
  file.parent.createSync(recursive: true);
  final entries = _readAssetCatalogPersistentCacheEntriesFromFile(file.path);
  if (request.request['includeLegacyCodex'] == true &&
      StudioAssetCatalogService._hasPersistentEntryCoveringSnapshot(
        entries,
        request.request,
        request.snapshot,
      )) {
    return;
  }
  if (request.request['includeLegacyCodex'] == true) {
    StudioAssetCatalogService._removeCoveredCodexCacheEntries(
      entries,
      request.request,
      request.snapshot,
    );
  } else {
    StudioAssetCatalogService._removeRedundantDefaultCacheEntries(
      entries,
      cacheKey,
    );
  }
  entries[cacheKey] = StudioAssetCatalogService._cacheEntryToJson(cacheEntry);
  StudioAssetCatalogService._prunePersistentCacheEntries(entries);
  file.writeAsStringSync(
    jsonEncode({
      'schemaVersion': StudioAssetCatalogService._cacheSchemaVersion,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries,
    }),
  );
}

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
  static const sourceAllKey = 'all';
  static const sourceRegularKey = 'regular';
  static const sourceAdultKey = 'adult';
  static const sourceCategoryPrefix = 'source:';
  static const _requestSeparator = '::';
  static const _sourceCategorySeparator = ' / ';

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

  static const adultBody = StudioLegacyCodexCategory(
    key: 'adult-body',
    label: '身体/部位',
  );
  static const adultInteraction = StudioLegacyCodexCategory(
    key: 'adult-interaction',
    label: '互动/姿势',
  );
  static const adultClothingState = StudioLegacyCodexCategory(
    key: 'adult-clothing-state',
    label: '服装/状态',
  );
  static const adultView = StudioLegacyCodexCategory(
    key: 'adult-view',
    label: '视角/构图',
  );
  static const adultExpression = StudioLegacyCodexCategory(
    key: 'adult-expression',
    label: '表情/动作',
  );
  static const adultSceneProp = StudioLegacyCodexCategory(
    key: 'adult-scene-prop',
    label: '场景/道具',
  );
  static const adultQualityFix = StudioLegacyCodexCategory(
    key: 'adult-quality-fix',
    label: '质量/修正',
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

  static const adultFilters = [
    all,
    adultBody,
    adultInteraction,
    adultClothingState,
    adultView,
    adultExpression,
    adultSceneProp,
    adultQualityFix,
    general,
  ];

  static const _adultSpecificFilters = [
    adultBody,
    adultInteraction,
    adultClothingState,
    adultView,
    adultExpression,
    adultSceneProp,
    adultQualityFix,
  ];

  static List<StudioLegacyCodexCategory> filtersForSource(
    String sourceScopeKey,
  ) {
    final normalized = normalizedSourceScopeKey(sourceScopeKey);
    return normalized == sourceAdultKey ? adultFilters : filters;
  }

  static String defaultCategoryKeyForSource(String sourceScopeKey) {
    return allKey;
  }

  static String normalizedKey(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) return allKey;
    if (isSourceCategoryKey(normalized)) return normalized;
    return filters.any((category) => category.key == normalized)
        ? normalized
        : allKey;
  }

  static String normalizedKeyForSource(String key, String sourceScopeKey) {
    final normalized = key.trim();
    if (normalized.isEmpty) return allKey;
    if (isSourceCategoryKey(normalized)) return normalized;
    final categories = filtersForSource(sourceScopeKey);
    return categories.any((category) => category.key == normalized)
        ? normalized
        : defaultCategoryKeyForSource(sourceScopeKey);
  }

  static String normalizedSourceScopeKey(String key) {
    final normalized = key.trim();
    return switch (normalized) {
      sourceRegularKey => sourceRegularKey,
      sourceAdultKey => sourceAdultKey,
      sourceAllKey => sourceAllKey,
      _ => sourceAllKey,
    };
  }

  static String requestKey({
    required String sourceScopeKey,
    required String categoryKey,
  }) {
    final normalizedSource = normalizedSourceScopeKey(sourceScopeKey);
    return [
      normalizedSource,
      normalizedKeyForSource(categoryKey, normalizedSource),
    ].join(_requestSeparator);
  }

  static String normalizedRequestKey(String key) {
    final request = requestFilterFor(key);
    return requestKey(
      sourceScopeKey: request.sourceScopeKey,
      categoryKey: request.categoryKey,
    );
  }

  static StudioLegacyCodexRequestFilter requestFilterFor(String key) {
    final raw = key.trim();
    if (raw.contains(_requestSeparator)) {
      final parts = raw.split(_requestSeparator);
      final sourceScopeKey = normalizedSourceScopeKey(parts.first);
      return StudioLegacyCodexRequestFilter(
        sourceScopeKey: sourceScopeKey,
        categoryKey: normalizedKeyForSource(
          parts.length > 1 ? parts[1] : allKey,
          sourceScopeKey,
        ),
      );
    }
    return StudioLegacyCodexRequestFilter(
      sourceScopeKey: sourceAllKey,
      categoryKey: normalizedKey(raw),
    );
  }

  static StudioLegacyCodexCategory byKey(String key) {
    final normalized = normalizedKey(key);
    if (isSourceCategoryKey(normalized)) {
      return StudioLegacyCodexCategory(
        key: normalized,
        label: labelForKey(normalized),
      );
    }
    return filters.firstWhere((category) => category.key == normalized);
  }

  static bool matches(InspirationEntry entry, String categoryKey) {
    final request = requestFilterFor(categoryKey);
    final normalized = request.categoryKey;
    if (normalized == allKey) return true;
    if (isSourceCategoryKey(normalized)) {
      return keysForSource(entry, request.sourceScopeKey).contains(normalized);
    }
    return _semanticKeysForSource(entry, request.sourceScopeKey)
        .contains(normalized);
  }

  static List<String> keysFor(InspirationEntry entry) {
    return keysForSource(entry, sourceRegularKey);
  }

  static List<String> keysForSource(
    InspirationEntry entry,
    String sourceScopeKey,
  ) {
    final sourceCategoryKey = sourceCategoryKeyForPath(
      entry.sourceCategoryPath,
    );
    if (sourceCategoryKey != null) return [sourceCategoryKey];
    return _semanticKeysForSource(entry, sourceScopeKey);
  }

  static List<String> _semanticKeysForSource(
    InspirationEntry entry,
    String sourceScopeKey,
  ) {
    final normalizedSource = normalizedSourceScopeKey(sourceScopeKey);
    if (normalizedSource == sourceAdultKey) {
      return _adultKeysFor(entry);
    }
    return _regularKeysFor(entry);
  }

  static String? sourceCategoryKeyForPath(List<String> path) {
    final normalized = path
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return null;
    return '$sourceCategoryPrefix${normalized.join(_sourceCategorySeparator)}';
  }

  static bool isSourceCategoryKey(String key) {
    return key.trim().startsWith(sourceCategoryPrefix);
  }

  static String labelForKey(String key) {
    final normalized = key.trim();
    if (!isSourceCategoryKey(normalized)) {
      return byKey(normalized).label;
    }
    final path = normalized.substring(sourceCategoryPrefix.length);
    final parts = path
        .split(_sourceCategorySeparator)
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? path : parts.last;
  }

  static List<String> _regularKeysFor(InspirationEntry entry) {
    final text = _searchText(entry);
    final keys = <String>[];
    for (final category in _specificFilters) {
      if (_termsFor(category.key).any((term) => _matchesTerm(text, term))) {
        keys.add(category.key);
      }
    }
    return keys.isEmpty ? [general.key] : List.unmodifiable(keys);
  }

  static List<String> _adultKeysFor(InspirationEntry entry) {
    final text = _searchText(entry);
    final keys = <String>[];
    for (final category in _adultSpecificFilters) {
      if (_adultTermsFor(category.key)
          .any((term) => _matchesTerm(text, term))) {
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
    return countByCategoryForSource(entries, sourceRegularKey);
  }

  static Map<String, int> countByCategoryForSource(
    List<InspirationEntry> entries,
    String sourceScopeKey,
  ) {
    final filters = filtersForSource(sourceScopeKey);
    final counts = <String, int>{allKey: entries.length};
    for (final category in filters.skip(1)) {
      counts[category.key] = 0;
    }
    for (final entry in entries) {
      for (final key in keysForSource(entry, sourceScopeKey)) {
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

  static List<String> _adultTermsFor(String key) {
    return switch (key) {
      'adult-body' => const [
          'nude',
          'naked',
          'breasts',
          'nipples',
          'pussy',
          'penis',
          'ass',
          'feet',
          'labia',
          'thighs',
          'bare shoulder',
          'skin',
          'body',
        ],
      'adult-interaction' => const [
          'sex',
          'kiss',
          'oral',
          'handjob',
          'footjob',
          'missionary',
          'doggystyle',
          'penetration',
          'cum',
          'grabbing',
          'kneeling',
          'lying',
          'spread legs',
          'leg grab',
          'hands on',
        ],
      'adult-clothing-state' => const [
          'see-through',
          'shirt lift',
          'shirt lifted',
          'skirt lift',
          'collar',
          'no collar',
          'panties',
          'bra',
          'stockings',
          'socks',
          'white ankle socks',
          'bare shoulder',
        ],
      'adult-view' => const [
          'pov',
          'first-person',
          'from above',
          'from below',
          'close-up',
          'front view',
          'side view',
          'looking down',
          'looking at viewer',
          'upside-down',
        ],
      'adult-expression' => const [
          'blush',
          'sweat',
          'crying',
          'tears',
          'closed eyes',
          'open mouth',
          'looking',
          'smile',
        ],
      'adult-scene-prop' => const [
          'bed',
          'on bed',
          'indoors',
          'bath',
          'chair',
          'floor',
          'couch',
          'game console',
          'nintendo',
          'mirror',
        ],
      'adult-quality-fix' => const [
          'lowres',
          'bad anatomy',
          'extra fingers',
          'missing fingers',
          'censored',
          'uncensored',
          'negative',
          'bad hands',
        ],
      _ => const <String>[],
    };
  }
}

class StudioLegacyCodexRequestFilter {
  final String sourceScopeKey;
  final String categoryKey;

  const StudioLegacyCodexRequestFilter({
    required this.sourceScopeKey,
    required this.categoryKey,
  });
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
  final List<PromptAssetCategory> promptAssetCategories;
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
    this.promptAssetCategories = const [],
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
  static const _cacheSchemaVersion = 10;
  static const _singleEntryCacheSchemaVersion = 2;
  static const _maxPersistentCodexEntries = 8;
  static const _maxPersistentCodexLimit = 64;
  static final _cacheSchemaVersionPattern = RegExp(
    r'"schemaVersion"\s*:\s*(\d+)',
  );
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
  late final StudioCodexIndex _codexIndex;
  final Map<String, _PersistentCatalogCache> _catalogCacheEntries = {};
  Future<void>? _pendingPersistentCacheWrite;

  StudioAssetCatalogService({
    required this.workspaceService,
    this.legacyCodexLoader,
  }) {
    _codexIndex = StudioCodexIndex(
      workspaceService: workspaceService,
      legacyCodexLoader: legacyCodexLoader,
    );
  }

  static bool isCodexSourceType(String sourceType) {
    return isStudioCodexSourceType(sourceType);
  }

  static bool isAdultCodexSourceType(String sourceType) {
    return isAdultStudioCodexSourceType(sourceType);
  }

  Future<StudioAssetCatalogCacheLoadResult> loadSnapshotWithCache({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool checkStaleness = true,
    bool persistCacheBeforeReturn = true,
  }) async {
    final request = _cacheRequest(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
    final cached =
        _readMemoryCache(request) ?? await _readPersistentCache(request);
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
        persistCacheBeforeReturn: persistCacheBeforeReturn,
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
    bool persistCacheBeforeReturn = true,
  }) {
    return loadSnapshot(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
      persistCacheBeforeReturn: persistCacheBeforeReturn,
    );
  }

  Future<StudioAssetCatalogSummary> loadSummary() async {
    final characters = await _loadCatalogCharacters();
    final recipeCountsByBlock = <String, int>{};
    final tagCountsByBlock = <String, int>{};

    for (final block in await workspaceService.listRecipeBlocks()) {
      recipeCountsByBlock[block] =
          (await workspaceService.loadRecipes(block)).length;
    }
    for (final block in await workspaceService.listTagBlocks()) {
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

  Future<StudioAssetCatalogSummary?> loadCachedSummary() async {
    final request = _cacheRequest(
      includeLegacyCodex: false,
      legacyCodexLimit: 160,
      legacyCodexQuery: '',
      legacyCodexCategoryKey: StudioLegacyCodexCategories.allKey,
    );
    final cached =
        _readMemoryCache(request) ?? await _readPersistentCache(request);
    return cached?.snapshot.summary;
  }

  Future<Set<String>> loadAssetFavoriteKeys() {
    return workspaceService.loadAssetFavorites();
  }

  Future<void> setAssetFavorite(String key, bool isFavorite) {
    return workspaceService.setAssetFavorite(key, isFavorite);
  }

  String? resolveImagePath(List<String> refs) {
    final paths = resolveImagePaths(refs, limit: 1);
    return paths.isEmpty ? null : paths.first;
  }

  List<String> resolveImagePaths(List<String> refs, {int? limit}) {
    final workspaceRoot = workspaceService.root;
    final paths = <String>[];
    final seen = <String>{};
    for (final ref in refs) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty) continue;
      final direct = File(trimmed);
      if (direct.isAbsolute && direct.existsSync()) {
        if (seen.add(direct.path)) {
          paths.add(direct.path);
          if (limit != null && paths.length >= limit) return paths;
        }
        continue;
      }
      if (workspaceRoot == null) continue;
      for (final candidate in [
        File(_join(workspaceRoot.path, trimmed)),
        File(_join(workspaceRoot.path, 'assets/references/$trimmed')),
        File(_join(workspaceRoot.path, 'imports/artist_studio/$trimmed')),
        File(_join(workspaceRoot.path, 'imports/external/$trimmed')),
      ]) {
        if (candidate.existsSync() && seen.add(candidate.path)) {
          paths.add(candidate.path);
          if (limit != null && paths.length >= limit) return paths;
          break;
        }
      }
    }
    return List.unmodifiable(paths);
  }

  Future<List<String>> resolveImagePathsAsync(List<String> refs) async {
    final workspaceRoot = workspaceService.root;
    if (workspaceRoot == null) {
      final paths = <String>[];
      final seen = <String>{};
      for (final ref in refs) {
        final resolved = resolveImagePath([ref]);
        if (resolved != null && seen.add(resolved)) {
          paths.add(resolved);
        }
      }
      return List.unmodifiable(paths);
    }
    final paths = <String>[];
    final seen = <String>{};
    for (final ref in refs) {
      final trimmed = ref.trim();
      if (trimmed.isEmpty) continue;
      final direct = File(trimmed);
      if (direct.isAbsolute && await direct.exists()) {
        if (seen.add(direct.path)) paths.add(direct.path);
        continue;
      }
      for (final candidate in [
        File(_join(workspaceRoot.path, trimmed)),
        File(_join(workspaceRoot.path, 'assets/references/$trimmed')),
        File(_join(workspaceRoot.path, 'imports/artist_studio/$trimmed')),
        File(_join(workspaceRoot.path, 'imports/external/$trimmed')),
      ]) {
        if (await candidate.exists() && seen.add(candidate.path)) {
          paths.add(candidate.path);
          break;
        }
      }
    }
    return List.unmodifiable(paths);
  }

  Future<List<CharacterEntry>> loadWorkbenchCharacters() {
    return _loadCatalogCharacters();
  }

  Future<List<StudioOutfitAsset>> loadWorkbenchOutfits() async {
    final characters = await _loadCatalogCharacters();
    return List.unmodifiable(_outfitsFromCharacters(characters));
  }

  static List<StudioOutfitAsset> _outfitsFromCharacters(
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
    for (final block in await workspaceService.listRecipeBlocks()) {
      recipes.addAll(await workspaceService.loadRecipes(block));
    }
    return List.unmodifiable(recipes);
  }

  Future<List<TagEntry>> loadWorkbenchTags() async {
    final tags = <TagEntry>[];
    for (final block in await workspaceService.listTagBlocks()) {
      tags.addAll(await workspaceService.loadTags(block));
    }
    return List.unmodifiable(tags);
  }

  Future<List<PromptAssetCategory>> loadPromptAssetCategories() {
    return workspaceService.loadPromptAssetCategories();
  }

  Future<Map<String, dynamic>> loadWorkbenchFilterRules() {
    return workspaceService.loadFilterRules();
  }

  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    final snapshot = await _buildSnapshot(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
    final request = _cacheRequest(
      includeLegacyCodex: includeLegacyCodex,
      legacyCodexLimit: legacyCodexLimit,
      legacyCodexQuery: legacyCodexQuery,
      legacyCodexCategoryKey: legacyCodexCategoryKey,
    );
    if (persistCacheBeforeReturn) {
      await _writePersistentCache(
        request: request,
        snapshot: snapshot,
        sourceFingerprint: await _sourceFingerprint(),
      );
    } else {
      _rememberMemoryCache(
        request: request,
        snapshot: snapshot,
        sourceFingerprint: const {},
      );
      final pendingWrite = _writePersistentCacheWithFreshFingerprint(
        request: request,
        snapshot: snapshot,
      );
      _pendingPersistentCacheWrite = pendingWrite;
      unawaited(pendingWrite.whenComplete(() {
        if (identical(_pendingPersistentCacheWrite, pendingWrite)) {
          _pendingPersistentCacheWrite = null;
        }
      }));
    }
    return snapshot;
  }

  Future<void> waitForPendingPersistentCacheWrite() {
    return _pendingPersistentCacheWrite ?? Future<void>.value();
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
    final legacyWorkspaceCodexInspirations = workspaceInspirations
        .where((entry) => isCodexSourceType(entry.source.type))
        .toList(growable: false);
    final separatedCodexInspirations = includeLegacyCodex
        ? await workspaceService.loadCodexEntries()
        : const <InspirationEntry>[];
    final workspaceCodexInspirations = [
      ...separatedCodexInspirations,
      ...legacyWorkspaceCodexInspirations,
    ];
    final legacyCodex = includeLegacyCodex
        ? await _loadLegacyCodexInspirations(
            limit: legacyCodexLimit,
            query: legacyCodexQuery,
            categoryKey: legacyCodexCategoryKey,
            workspaceCodexEntries: workspaceCodexInspirations,
          )
        : const StudioCodexSlice.empty();
    final legacyCodexAvailable = workspaceCodexInspirations.isNotEmpty ||
        legacyWorkspaceCodexInspirations.isNotEmpty ||
        await workspaceService.hasCodexEntries() ||
        await _hasLegacyCodexSource();
    final inspirations = [
      ...catalogInspirations,
      ...legacyCodex.entries,
    ];
    final loras = await workspaceService.loadLoras();
    final workflows = await workspaceService.loadWorkflows();
    final batchPlans = await workspaceService.loadBatchPlans();
    final assemblyPresets = await workspaceService.loadAssemblyPresets();
    final promptAssetCategories =
        await workspaceService.loadPromptAssetCategories();
    final recipeCountsByBlock = <String, int>{};
    final tagCountsByBlock = <String, int>{};
    final outfits = _outfitsFromCharacters(characters);
    final recipes = <Recipe>[];
    final tags = <TagEntry>[];

    for (final block in await workspaceService.listRecipeBlocks()) {
      final blockRecipes = await workspaceService.loadRecipes(block);
      recipes.addAll(blockRecipes);
      recipeCountsByBlock[block] = blockRecipes.length;
    }
    for (final block in await workspaceService.listTagBlocks()) {
      final blockTags = await workspaceService.loadTags(block);
      tags.addAll(blockTags);
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
      promptAssetCategories: List.unmodifiable(promptAssetCategories),
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
          StudioLegacyCodexCategories.normalizedRequestKey(
        legacyCodexCategoryKey,
      ),
    };
  }

  Future<_PersistentCatalogCache?> _readPersistentCache(
    Map<String, dynamic> request,
  ) async {
    final file = _workspaceFile(WorkspacePaths.assetCatalogCache);
    if (file == null || !await file.exists()) return null;
    try {
      final schemaVersion = await _readPersistentCacheSchemaVersion(file);
      if (schemaVersion != _cacheSchemaVersion &&
          schemaVersion != _singleEntryCacheSchemaVersion) {
        return null;
      }
      final cacheEntry = await Isolate.run(
        () => _readAssetCatalogPersistentCacheFromFile(
          _AssetCatalogPersistentCacheReadRequest(
            path: file.path,
            request: request,
          ),
        ),
      );
      if (cacheEntry != null) {
        _catalogCacheEntries[_cacheEntryKey(request)] = cacheEntry;
        return cacheEntry;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  _PersistentCatalogCache? _readMemoryCache(Map<String, dynamic> request) {
    if (request['includeLegacyCodex'] == true) {
      final compatible = _readCompatibleCodexCacheEntry(
        request: request,
        entries: _catalogCacheEntries,
        readEntry: (_, entry) => entry as _PersistentCatalogCache,
      );
      if (compatible != null) return compatible;
    }
    return _catalogCacheEntries[_cacheEntryKey(request)];
  }

  void _rememberMemoryCache({
    required Map<String, dynamic> request,
    required StudioAssetCatalogSnapshot snapshot,
    required Map<String, String> sourceFingerprint,
  }) {
    _catalogCacheEntries[_cacheEntryKey(request)] = _PersistentCatalogCache(
      snapshot: snapshot,
      sourceFingerprint: sourceFingerprint,
    );
  }

  Future<void> _writePersistentCacheWithFreshFingerprint({
    required Map<String, dynamic> request,
    required StudioAssetCatalogSnapshot snapshot,
  }) async {
    try {
      await _writePersistentCache(
        request: request,
        snapshot: snapshot,
        sourceFingerprint: await _sourceFingerprint(),
      );
    } catch (_) {
      // Cache persistence is a read optimization; foreground data is already
      // available from the rebuilt in-memory snapshot.
    }
  }

  Future<void> _writePersistentCache({
    required Map<String, dynamic> request,
    required StudioAssetCatalogSnapshot snapshot,
    required Map<String, String> sourceFingerprint,
  }) async {
    final cacheEntry = _PersistentCatalogCache(
      snapshot: snapshot,
      sourceFingerprint: sourceFingerprint,
    );
    _rememberMemoryCache(
      request: request,
      snapshot: snapshot,
      sourceFingerprint: sourceFingerprint,
    );
    if (!_shouldPersistCacheEntry(request, snapshot)) {
      return;
    }
    final file = _workspaceFile(WorkspacePaths.assetCatalogCache);
    if (file == null) return;
    await Isolate.run(
      () => _writeAssetCatalogPersistentCacheFile(
        _AssetCatalogPersistentCacheWriteRequest(
          path: file.path,
          request: request,
          snapshot: cacheEntry.snapshot,
          sourceFingerprint: cacheEntry.sourceFingerprint,
        ),
      ),
    );
  }

  Future<int?> _readPersistentCacheSchemaVersion(File file) async {
    try {
      final length = await file.length();
      if (length <= 0) return null;
      final end = length < 512 ? length : 512;
      final prefix = await file.openRead(0, end).transform(utf8.decoder).join();
      final match = _cacheSchemaVersionPattern.firstMatch(prefix);
      if (match == null) return null;
      return int.tryParse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  static bool _shouldPersistCacheEntry(
    Map<String, dynamic> request,
    StudioAssetCatalogSnapshot snapshot,
  ) {
    if (request['includeLegacyCodex'] != true) return true;
    final loadedCount = snapshot.legacyCodexLoadedCount;
    final totalCount = snapshot.legacyCodexTotalCount;
    return loadedCount <= _maxPersistentCodexLimit ||
        totalCount <= _maxPersistentCodexLimit;
  }

  static bool _hasPersistentEntryCoveringSnapshot(
    Map<String, dynamic> entries,
    Map<String, dynamic> request,
    StudioAssetCatalogSnapshot snapshot,
  ) {
    final compatible = _readCompatibleCodexCacheEntry(
      request: request,
      entries: entries,
      readEntry: (key, entry) => _cacheEntryFromJson(entry, 'cache.entry.$key'),
    );
    return compatible != null &&
        compatible.snapshot.legacyCodexLoadedCount >=
            snapshot.legacyCodexLoadedCount;
  }

  static void _removeCoveredCodexCacheEntries(
    Map<String, dynamic> entries,
    Map<String, dynamic> request,
    StudioAssetCatalogSnapshot snapshot,
  ) {
    final requestedQuery = (request['legacyCodexQuery'] ?? '').toString();
    final requestedCategoryKey =
        StudioLegacyCodexCategories.normalizedRequestKey(
      (request['legacyCodexCategoryKey'] ?? '').toString(),
    );
    entries.removeWhere((key, _) {
      final parts = _cacheEntryKeyParts(key);
      if (parts == null ||
          !parts.includeLegacyCodex ||
          parts.legacyCodexQuery != requestedQuery ||
          parts.legacyCodexCategoryKey != requestedCategoryKey) {
        return false;
      }
      return parts.legacyCodexLimit <= snapshot.legacyCodexLoadedCount;
    });
  }

  static void _removeRedundantDefaultCacheEntries(
    Map<String, dynamic> entries,
    String currentKey,
  ) {
    entries.removeWhere((key, _) {
      if (key == currentKey) return false;
      final parts = _cacheEntryKeyParts(key);
      return parts != null && !parts.includeLegacyCodex;
    });
  }

  static void _prunePersistentCacheEntries(Map<String, dynamic> entries) {
    final codexKeys = [
      for (final key in entries.keys)
        if (_cacheEntryKeyParts(key)?.includeLegacyCodex == true) key,
    ];
    if (codexKeys.length <= _maxPersistentCodexEntries) return;
    codexKeys.sort((a, b) {
      final generatedCompare = _cacheEntryGeneratedAt(
        entries[b],
      ).compareTo(_cacheEntryGeneratedAt(entries[a]));
      if (generatedCompare != 0) return generatedCompare;
      final aLimit = _cacheEntryKeyParts(a)?.legacyCodexLimit ?? 0;
      final bLimit = _cacheEntryKeyParts(b)?.legacyCodexLimit ?? 0;
      return bLimit.compareTo(aLimit);
    });
    for (final key in codexKeys.skip(_maxPersistentCodexEntries)) {
      entries.remove(key);
    }
  }

  static DateTime _cacheEntryGeneratedAt(dynamic entry) {
    if (entry is! Map) return DateTime.fromMillisecondsSinceEpoch(0);
    final generatedAt = entry['generatedAt'];
    if (generatedAt is! String) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.tryParse(generatedAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Map<String, dynamic> _cacheEntryToJson(
    _PersistentCatalogCache cacheEntry,
  ) {
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceFingerprint': cacheEntry.sourceFingerprint,
      'snapshot': _snapshotToJson(cacheEntry.snapshot),
    };
  }

  static _PersistentCatalogCache _cacheEntryFromJson(
    dynamic json,
    String label,
  ) {
    final map = _jsonMap(json, label);
    return _PersistentCatalogCache(
      snapshot: _snapshotFromJson(map['snapshot']),
      sourceFingerprint:
          _stringMap(map['sourceFingerprint'], '$label.sourceFingerprint'),
    );
  }

  static _PersistentCatalogCache? _readCompatibleCodexCacheEntry({
    required Map<String, dynamic> request,
    required Map<String, dynamic> entries,
    required _PersistentCatalogCache Function(String key, dynamic entry)
        readEntry,
  }) {
    final requestedLimit = _intValue(request['legacyCodexLimit']);
    final requestedQuery = (request['legacyCodexQuery'] ?? '').toString();
    final requestedCategoryKey =
        StudioLegacyCodexCategories.normalizedRequestKey(
      (request['legacyCodexCategoryKey'] ?? '').toString(),
    );
    _PersistentCatalogCache? best;
    var bestLoadedCount = -1;
    for (final entry in entries.entries) {
      final key = _cacheEntryKeyParts(entry.key);
      if (key == null ||
          key.includeLegacyCodex != true ||
          key.legacyCodexQuery != requestedQuery ||
          key.legacyCodexCategoryKey != requestedCategoryKey) {
        continue;
      }
      try {
        final candidate = readEntry(entry.key, entry.value);
        final loadedCount = candidate.snapshot.legacyCodexLoadedCount;
        final totalCount = candidate.snapshot.legacyCodexTotalCount;
        final coversRequest =
            loadedCount >= requestedLimit || loadedCount >= totalCount;
        if (!coversRequest || loadedCount <= bestLoadedCount) continue;
        best = candidate;
        bestLoadedCount = loadedCount;
      } catch (_) {
        continue;
      }
    }
    return best;
  }

  static String _cacheEntryKey(Map<String, dynamic> request) {
    final includeLegacyCodex = request['includeLegacyCodex'] == true ? 1 : 0;
    final limit = _intValue(request['legacyCodexLimit']);
    final query = (request['legacyCodexQuery'] ?? '').toString();
    final categoryKey = StudioLegacyCodexCategories.normalizedRequestKey(
      (request['legacyCodexCategoryKey'] ?? '').toString(),
    );
    return [
      'codex=$includeLegacyCodex',
      'limit=$limit',
      'query=$query',
      'codexRequest=$categoryKey',
    ].join('|');
  }

  static ({
    bool includeLegacyCodex,
    int legacyCodexLimit,
    String legacyCodexQuery,
    String legacyCodexCategoryKey,
  })? _cacheEntryKeyParts(String key) {
    const codexPrefix = 'codex=';
    const limitMarker = '|limit=';
    const queryMarker = '|query=';
    const categoryMarker = '|codexRequest=';
    if (!key.startsWith(codexPrefix)) return null;
    final limitMarkerIndex = key.indexOf(limitMarker);
    final queryMarkerIndex = key.indexOf(queryMarker, limitMarkerIndex + 1);
    final categoryMarkerIndex = key.lastIndexOf(categoryMarker);
    if (limitMarkerIndex < 0 ||
        queryMarkerIndex < 0 ||
        categoryMarkerIndex < 0 ||
        queryMarkerIndex <= limitMarkerIndex ||
        categoryMarkerIndex <= queryMarkerIndex) {
      return null;
    }
    final codexText = key.substring(codexPrefix.length, limitMarkerIndex);
    final limitText = key.substring(
      limitMarkerIndex + limitMarker.length,
      queryMarkerIndex,
    );
    final limit = int.tryParse(limitText);
    if (limit == null) return null;
    final query = key.substring(
      queryMarkerIndex + queryMarker.length,
      categoryMarkerIndex,
    );
    final categoryKey = key.substring(
      categoryMarkerIndex + categoryMarker.length,
    );
    return (
      includeLegacyCodex: codexText == '1',
      legacyCodexLimit: limit,
      legacyCodexQuery: query,
      legacyCodexCategoryKey:
          StudioLegacyCodexCategories.normalizedRequestKey(categoryKey),
    );
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
      WorkspacePaths.codexEntries,
      WorkspacePaths.loras,
      WorkspacePaths.promptAssetCategories,
    ]) {
      await _addFileFingerprint(root, relativePath, fingerprint);
    }
    for (final relativeDir in [
      'library/recipes',
      'library/tags',
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

  static bool _sameJsonMap(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  static Map<String, dynamic> _summaryToJson(
    StudioAssetCatalogSummary summary,
  ) {
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

  static StudioAssetCatalogSummary _summaryFromJson(dynamic json) {
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

  static Map<String, dynamic> _snapshotToJson(
    StudioAssetCatalogSnapshot snapshot,
  ) {
    return {
      'summary': _summaryToJson(snapshot.summary),
      'promptAssetCategories': snapshot.promptAssetCategories
          .map((entry) => entry.toJson())
          .toList(),
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

  static StudioAssetCatalogSnapshot _snapshotFromJson(dynamic json) {
    final map = _jsonMap(json, 'catalog.snapshot');
    final characters = _list(map['characters'])
        .map(CharacterEntry.fromJson)
        .toList(growable: false);
    return StudioAssetCatalogSnapshot(
      summary: _summaryFromJson(map['summary']),
      promptAssetCategories: _list(map['promptAssetCategories'])
          .map(PromptAssetCategory.fromJson)
          .toList(growable: false),
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

  static Map<String, dynamic> _jsonMap(dynamic value, String label) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw FormatException('$label must be a JSON object.');
  }

  static List<dynamic> _list(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  static Map<String, String> _stringMap(dynamic value, String label) {
    return _jsonMap(value, label).map(
      (key, value) => MapEntry(key, value.toString()),
    );
  }

  static Map<String, int> _intMap(dynamic value, String label) {
    return _jsonMap(value, label).map(
      (key, value) => MapEntry(key, _intValue(value)),
    );
  }

  static int _intValue(dynamic value) {
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

  Future<StudioCodexSlice> _loadLegacyCodexInspirations({
    required int limit,
    required String query,
    required String categoryKey,
    List<InspirationEntry> workspaceCodexEntries = const [],
  }) async {
    return _codexIndex.loadSlice(
      workspaceCodexEntries: workspaceCodexEntries,
      limit: limit,
      query: query,
      categoryKey: categoryKey,
    );
  }

  Future<bool> _hasLegacyCodexSource() async {
    return _codexIndex.hasBundledCodexSource();
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

class _PersistentCatalogCache {
  final StudioAssetCatalogSnapshot snapshot;
  final Map<String, String> sourceFingerprint;

  const _PersistentCatalogCache({
    required this.snapshot,
    required this.sourceFingerprint,
  });
}
