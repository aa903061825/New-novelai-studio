import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

enum PromptTagCategory {
  character,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
  accessory,
  clothingState,
  clothing,
  action,
  scene,
  camera,
  artist,
  style,
  quality,
  negativeQuality,
  negativeBody,
  negativeArtist,
  negativeContent,
  promptSyntax,
  other,
}

class PromptTagGroup {
  final String id;
  final String label;
  final List<PromptTagCategory> categories;

  const PromptTagGroup({
    required this.id,
    required this.label,
    required this.categories,
  });
}

class PromptTagClassification {
  final String source;
  final PromptTagCategory category;
  final PromptTagGroup group;

  const PromptTagClassification({
    required this.source,
    required this.category,
    required this.group,
  });
}

class PromptTagClassificationCacheEntry {
  final PromptTagCategory category;
  final String source;
  final int updatedAt;

  const PromptTagClassificationCacheEntry({
    required this.category,
    required this.source,
    required this.updatedAt,
  });

  factory PromptTagClassificationCacheEntry.fromJson(dynamic value) {
    if (value is String) {
      return PromptTagClassificationCacheEntry(
        category: _categoryFromName(value),
        source: 'legacy',
        updatedAt: 0,
      );
    }
    if (value is Map) {
      return PromptTagClassificationCacheEntry(
        category: _categoryFromName(value['category']?.toString()),
        source: value['source']?.toString() ?? 'legacy',
        updatedAt: value['updatedAt'] is int ? value['updatedAt'] as int : 0,
      );
    }
    return const PromptTagClassificationCacheEntry(
      category: PromptTagCategory.other,
      source: 'legacy',
      updatedAt: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category.name,
      'source': source,
      'updatedAt': updatedAt,
    };
  }
}

class PromptTagClassificationSuggestion {
  final String tag;
  final PromptTagCategory category;
  final String source;
  final bool negative;

  const PromptTagClassificationSuggestion({
    required this.tag,
    required this.category,
    this.source = 'ai_extraction',
    this.negative = false,
  });
}

class PromptTagClassificationCacheEvents {
  static final PromptTagClassificationRevisionNotifier revision =
      PromptTagClassificationRevisionNotifier();

  const PromptTagClassificationCacheEvents._();

  static void notifyChanged() {
    revision.notifyChanged();
  }
}

class PromptTagClassificationRevisionNotifier {
  final Set<void Function()> _listeners = <void Function()>{};

  int value = 0;

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void notifyChanged() {
    value += 1;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

class PromptTagClassificationCache {
  static const String _validCompoundTagsJsonKey = '__validCompoundTags';

  final int Function() clock;
  final Map<String, PromptTagClassificationCacheEntry> _entries;
  final Set<String> _validCompoundTagKeys;

  PromptTagClassificationCache({
    int Function()? clock,
    Map<String, PromptTagClassificationCacheEntry>? entries,
    Iterable<String>? validCompoundTagKeys,
  })  : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000),
        _entries = Map.of(entries ?? const {}),
        _validCompoundTagKeys = {
          for (final key in validCompoundTagKeys ?? const <String>[])
            if (key.trim().isNotEmpty)
              PromptTagProcessor.normalizeMatchKey(key),
        };

  factory PromptTagClassificationCache.fromJson(Map<String, dynamic> json) {
    return PromptTagClassificationCache(
      entries: {
        for (final entry in json.entries)
          if (entry.key != _validCompoundTagsJsonKey)
            entry.key: PromptTagClassificationCacheEntry.fromJson(entry.value),
      },
      validCompoundTagKeys: _stringList(json[_validCompoundTagsJsonKey]),
    );
  }

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  Map<String, PromptTagClassificationCacheEntry> get entries =>
      Map.unmodifiable(_entries);

  Set<String> get validCompoundTagKeys =>
      Set.unmodifiable(_validCompoundTagKeys);

  int mergeMissingFrom(PromptTagClassificationCache other) {
    var merged = 0;
    for (final entry in other._entries.entries) {
      final existing = _entries[entry.key];
      if (existing == null) {
        _entries[entry.key] = entry.value;
        merged += 1;
        continue;
      }
      if (_shouldReplaceMergedEntry(existing, entry.value)) {
        _entries[entry.key] = entry.value;
        merged += 1;
      }
    }
    final compoundCount = _validCompoundTagKeys.length;
    _validCompoundTagKeys.addAll(other._validCompoundTagKeys);
    final changed = merged + _validCompoundTagKeys.length - compoundCount;
    if (changed > 0) {
      PromptTagClassificationCacheEvents.notifyChanged();
    }
    return changed;
  }

  int mergeMissingSuggestions(
    Iterable<PromptTagClassificationSuggestion> suggestions, {
    bool refreshMachineEntries = false,
  }) {
    var merged = 0;
    for (final suggestion in suggestions) {
      final cleaned = _cleanTag(suggestion.tag);
      if (cleaned.isEmpty) continue;
      final key = _cacheKey(cleaned, negative: suggestion.negative);
      final existing = _entries[key];
      if (existing != null) {
        if (!refreshMachineEntries || _isUserConfirmedSource(existing.source)) {
          continue;
        }
      }

      _entries[key] = PromptTagClassificationCacheEntry(
        category: suggestion.category,
        source: suggestion.source.trim().isEmpty
            ? 'ai_extraction'
            : suggestion.source.trim(),
        updatedAt: clock(),
      );
      merged += 1;
    }
    if (merged > 0) {
      PromptTagClassificationCacheEvents.notifyChanged();
    }
    return merged;
  }

  bool isValidCompoundTag(String tag) {
    final key = _legacyCacheKey(tag);
    return key.isNotEmpty && _validCompoundTagKeys.contains(key);
  }

  void confirmValidCompoundTag(String tag) {
    final key = _legacyCacheKey(tag);
    if (key.isEmpty) return;
    if (_validCompoundTagKeys.add(key)) {
      PromptTagClassificationCacheEvents.notifyChanged();
    }
  }

  PromptTagClassificationCacheEntry? entryFor(
    String tag, {
    bool negative = false,
  }) {
    final cleaned = _cleanTag(tag);
    if (cleaned.isEmpty) return null;
    final contextualEntry = _entries[_cacheKey(cleaned, negative: negative)];
    if (contextualEntry != null) return contextualEntry;

    final legacyEntry = _entries[_legacyCacheKey(cleaned)];
    if (legacyEntry == null) return null;
    if (!_categoryMatchesPolarity(legacyEntry.category, negative: negative)) {
      return null;
    }
    return legacyEntry;
  }

  void setCategory(
    String tag,
    PromptTagCategory category, {
    String source = 'manual',
    bool negative = false,
  }) {
    final cleaned = _cleanTag(tag);
    if (cleaned.isEmpty) return;
    _entries[_cacheKey(cleaned, negative: negative)] =
        PromptTagClassificationCacheEntry(
      category: category,
      source: source,
      updatedAt: clock(),
    );
    if (source != 'rules') {
      PromptTagClassificationCacheEvents.notifyChanged();
    }
  }

  void clearCategory(
    String tag, {
    bool negative = false,
  }) {
    final cleaned = _cleanTag(tag);
    if (cleaned.isEmpty) return;
    var changed =
        _entries.remove(_cacheKey(cleaned, negative: negative)) != null;

    final legacyKey = _legacyCacheKey(cleaned);
    final legacyEntry = _entries[legacyKey];
    if (legacyEntry != null &&
        _categoryMatchesPolarity(legacyEntry.category, negative: negative)) {
      _entries.remove(legacyKey);
      changed = true;
    }
    if (changed) {
      PromptTagClassificationCacheEvents.notifyChanged();
    }
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      for (final entry in _entries.entries) entry.key: entry.value.toJson(),
    };
    if (_validCompoundTagKeys.isNotEmpty) {
      json[_validCompoundTagsJsonKey] =
          (_validCompoundTagKeys.toList()..sort());
    }
    return json;
  }

  static String _cacheKey(String tag, {required bool negative}) {
    return '${negative ? 'negative' : 'positive'}:${_legacyCacheKey(tag)}';
  }

  static String _legacyCacheKey(String tag) {
    return PromptTagProcessor.normalizeMatchKey(_cleanTag(tag));
  }

  static bool _shouldReplaceMergedEntry(
    PromptTagClassificationCacheEntry existing,
    PromptTagClassificationCacheEntry incoming,
  ) {
    if (_isManualSource(existing.source)) {
      return false;
    }
    if (_isManualSource(incoming.source)) {
      return true;
    }
    if (existing.source == 'rules' && incoming.source != 'rules') {
      return true;
    }
    return existing.source == 'legacy' && incoming.source != 'legacy';
  }

  static bool _isManualSource(String source) {
    return source == 'manual' || source.startsWith('manual-');
  }
}

List<String> _stringList(dynamic value) {
  if (value is! Iterable) {
    return const [];
  }
  return [
    for (final item in value)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

class PromptTagClassificationCacheRepository {
  final File file;

  const PromptTagClassificationCacheRepository(this.file);

  Future<PromptTagClassificationCache> load() async {
    if (!await file.exists()) {
      return PromptTagClassificationCache();
    }
    try {
      final path = file.path;
      return Isolate.run(() => _classificationCacheFromFile(path));
    } catch (_) {
      return PromptTagClassificationCache();
    }
  }

  Future<void> save(PromptTagClassificationCache cache) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(cache.toJson())}\n');
  }
}

PromptTagClassificationCache _classificationCacheFromFile(String path) {
  final source = File(path).readAsStringSync();
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    return PromptTagClassificationCache();
  }
  return PromptTagClassificationCache.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}

class PromptTagClassifier {
  static const groups = [
    PromptTagGroup(
      id: 'quality',
      label: '画质区',
      categories: [
        PromptTagCategory.quality,
        PromptTagCategory.negativeQuality,
      ],
    ),
    PromptTagGroup(
      id: 'artist',
      label: '画师区',
      categories: [
        PromptTagCategory.artist,
        PromptTagCategory.negativeArtist,
      ],
    ),
    PromptTagGroup(
      id: 'character',
      label: '角色区',
      categories: [
        PromptTagCategory.character,
      ],
    ),
    PromptTagGroup(
      id: 'clothing',
      label: '鏈嶈/韬綋',
      categories: [
        PromptTagCategory.upperBody,
        PromptTagCategory.lowerBody,
        PromptTagCategory.upperClothing,
        PromptTagCategory.lowerClothing,
        PromptTagCategory.accessory,
        PromptTagCategory.clothingState,
        PromptTagCategory.clothing,
        PromptTagCategory.negativeBody,
      ],
    ),
    PromptTagGroup(
      id: 'action',
      label: '动作区',
      categories: [
        PromptTagCategory.action,
      ],
    ),
    PromptTagGroup(
      id: 'scene',
      label: '鍦烘櫙/闀滃ご',
      categories: [
        PromptTagCategory.scene,
        PromptTagCategory.camera,
      ],
    ),
    PromptTagGroup(
      id: 'style',
      label: '风格区',
      categories: [
        PromptTagCategory.style,
      ],
    ),
    PromptTagGroup(
      id: 'negative',
      label: '璐熼潰鍐呭',
      categories: [
        PromptTagCategory.negativeContent,
      ],
    ),
    PromptTagGroup(
      id: 'syntax',
      label: '璇硶/鏉冮噸',
      categories: [
        PromptTagCategory.promptSyntax,
      ],
    ),
    PromptTagGroup(
      id: 'other',
      label: '鍏跺畠',
      categories: [
        PromptTagCategory.other,
      ],
    ),
  ];

  static const layeredGroups = [
    PromptTagGroup(
      id: 'quality',
      label: '画质区',
      categories: [
        PromptTagCategory.quality,
        PromptTagCategory.negativeQuality,
      ],
    ),
    PromptTagGroup(
      id: 'artist',
      label: '画师区',
      categories: [
        PromptTagCategory.artist,
        PromptTagCategory.negativeArtist,
      ],
    ),
    PromptTagGroup(
      id: 'character',
      label: '韬唤',
      categories: [
        PromptTagCategory.character,
      ],
    ),
    PromptTagGroup(
      id: 'upperBody',
      label: '涓婅韩',
      categories: [
        PromptTagCategory.upperBody,
      ],
    ),
    PromptTagGroup(
      id: 'upperClothing',
      label: '涓婅',
      categories: [
        PromptTagCategory.upperClothing,
      ],
    ),
    PromptTagGroup(
      id: 'lowerBody',
      label: '涓嬭韩',
      categories: [
        PromptTagCategory.lowerBody,
      ],
    ),
    PromptTagGroup(
      id: 'lowerClothing',
      label: '涓嬭',
      categories: [
        PromptTagCategory.lowerClothing,
      ],
    ),
    PromptTagGroup(
      id: 'accessory',
      label: '楗板搧',
      categories: [
        PromptTagCategory.accessory,
      ],
    ),
    PromptTagGroup(
      id: 'clothingState',
      label: '鏈嶈鐘舵€?鍔ㄤ綔',
      categories: [
        PromptTagCategory.clothingState,
      ],
    ),
    PromptTagGroup(
      id: 'clothing',
      label: '鍏跺畠鏈嶈',
      categories: [
        PromptTagCategory.clothing,
        PromptTagCategory.negativeBody,
      ],
    ),
    PromptTagGroup(
      id: 'action',
      label: '动作区',
      categories: [
        PromptTagCategory.action,
      ],
    ),
    PromptTagGroup(
      id: 'scene',
      label: '鍦烘櫙/闀滃ご',
      categories: [
        PromptTagCategory.scene,
        PromptTagCategory.camera,
      ],
    ),
    PromptTagGroup(
      id: 'style',
      label: '风格区',
      categories: [
        PromptTagCategory.style,
      ],
    ),
    PromptTagGroup(
      id: 'negative',
      label: '璐熼潰鍐呭',
      categories: [
        PromptTagCategory.negativeContent,
      ],
    ),
    PromptTagGroup(
      id: 'syntax',
      label: '璇硶/鏉冮噸',
      categories: [
        PromptTagCategory.promptSyntax,
      ],
    ),
    PromptTagGroup(
      id: 'other',
      label: '鍏跺畠',
      categories: [
        PromptTagCategory.other,
      ],
    ),
  ];

  static PromptTagClassification classify(
    String tag, {
    bool negative = false,
    PromptTagClassificationCache? cache,
  }) {
    final cleaned = _cleanTag(tag);
    final cached = cache?.entryFor(cleaned, negative: negative);
    if (cached != null && !_shouldRefreshCachedCategory(cached)) {
      return PromptTagClassification(
        source: cleaned,
        category: cached.category,
        group: groupFor(cached.category),
      );
    }

    final category = _classifyByRules(cleaned, negative: negative);
    return PromptTagClassification(
      source: cleaned,
      category: category,
      group: groupFor(category),
    );
  }

  static bool _shouldRefreshCachedCategory(
    PromptTagClassificationCacheEntry cached,
  ) {
    return cached.source == 'rules' ||
        (cached.source == 'legacy' &&
            cached.category == PromptTagCategory.other);
  }

  static PromptTagGroup groupFor(PromptTagCategory category) {
    for (final group in groups) {
      if (group.categories.contains(category)) {
        return group;
      }
    }
    return groups.last;
  }

  static PromptTagGroup layeredGroupFor(PromptTagCategory category) {
    for (final group in layeredGroups) {
      if (group.categories.contains(category)) {
        return group;
      }
    }
    return layeredGroups.last;
  }

  static Uri danbooruWikiUri(String tag) {
    final wikiName = danbooruWikiName(tag);
    return Uri.https('danbooru.donmai.us', '/wiki_pages/$wikiName');
  }

  static String danbooruWikiName(String tag) {
    var cleaned = _cleanTag(tag);
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(artist|character|copyright|general|meta)\s*:\s*'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'_+'), '_');
    return cleaned;
  }

  static PromptTagCategory _classifyByRules(
    String tag, {
    required bool negative,
  }) {
    final key = PromptTagProcessor.normalizeMatchKey(tag);
    if (negative) {
      if (_containsAny(key, _negativeQualityWords)) {
        return PromptTagCategory.negativeQuality;
      }
      if (_containsAny(key, _negativeBodyWords)) {
        return PromptTagCategory.negativeBody;
      }
      if (key.contains('artist:') || key.startsWith('artist ')) {
        return PromptTagCategory.negativeArtist;
      }
      return PromptTagCategory.negativeContent;
    }
    if (key.startsWith('artist:') || key.startsWith('artist ')) {
      return PromptTagCategory.artist;
    }
    if (_containsAny(key, _artistChainStyleWords)) {
      return PromptTagCategory.artist;
    }
    if (_isSeriesQualifiedCharacterTag(key)) {
      return PromptTagCategory.character;
    }
    if (_isPromptSyntaxTag(key)) {
      return PromptTagCategory.promptSyntax;
    }
    if (_containsAny(key, _qualityWords)) {
      return PromptTagCategory.quality;
    }
    if (_containsAny(key, _styleWords)) {
      return PromptTagCategory.style;
    }
    if (_containsAny(key, _upperBodyWords)) {
      return PromptTagCategory.upperBody;
    }
    if (_containsAny(key, _lowerBodyWords)) {
      return PromptTagCategory.lowerBody;
    }
    if (_containsAny(key, _accessoryWords)) {
      return PromptTagCategory.accessory;
    }
    if (_containsAny(key, _clothingStateWords)) {
      return PromptTagCategory.clothingState;
    }
    if (_containsAny(key, _upperClothingWords)) {
      return PromptTagCategory.upperClothing;
    }
    if (_containsAny(key, _lowerClothingWords)) {
      return PromptTagCategory.lowerClothing;
    }
    if (_containsAny(key, _clothingWords)) {
      return PromptTagCategory.clothing;
    }
    if (_containsAny(key, _cameraWords)) {
      return PromptTagCategory.camera;
    }
    if (_containsAny(key, _characterWords)) {
      return PromptTagCategory.character;
    }
    if (_containsAny(key, _actionWords)) {
      return PromptTagCategory.action;
    }
    if (_containsAny(key, _sceneWords)) {
      return PromptTagCategory.scene;
    }
    return PromptTagCategory.other;
  }

  static bool _containsAny(String key, Iterable<String> words) {
    return words.any(key.contains);
  }

  static bool _isPromptSyntaxTag(String key) {
    return RegExp(r'''^["'.!?銆傦紒锛熲€?;=\-+_^\s]+$''').hasMatch(key) ||
        RegExp(r'^[-+]?\d+(?:\.\d+)?(?:::)??$').hasMatch(key) ||
        RegExp(r'^"?\d+"?\s*:').hasMatch(key) ||
        RegExp(
          r'^"?(description|stealth pnginfo|base caption|prompt|v4 prompt|char caption|char captions|caption|comment|software|source|cfg|eta|sampler|seed|steps|height|width|scale|uncond scale|n samples|noise schedule|reference strength multiple|uc|hide debug overlay|negative momentum|centers|x|y|r|use coords|use order|controlnet strength|controlnet model|sm|sm dyn|skip cfg above sigma|skip cfg below sigma|lora unet weights|lora clip weights|generation time)"?$',
        ).hasMatch(key) ||
        key.startsWith('character#') ||
        key.startsWith('绀轰緥瑙掕壊') ||
        key.startsWith('鍐呭:') ||
        key.contains('unnamed config') ||
        key.contains('fur dataset') ||
        key.contains('inputs') ||
        key.contains('lora name') ||
        key.contains('safetensors') ||
        key.contains('stealth pnginfo');
  }

  static bool _isSeriesQualifiedCharacterTag(String key) {
    var normalized = key
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return false;
    }

    var hasSeries = false;
    for (final series in _characterSeriesWords) {
      final seriesPattern = RegExp(
        r'\b' + RegExp.escape(series).replaceAll(r'\ ', r'\s+') + r'\b',
      );
      if (seriesPattern.hasMatch(normalized)) {
        hasSeries = true;
        normalized = normalized.replaceAll(seriesPattern, ' ');
      }
    }
    if (!hasSeries) {
      return false;
    }

    final cleaned = normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(
          RegExp(
            r'\b(v1|v2|v3|ver|alt|summer|dress|swimsuit|art|work|style)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty && RegExp(r'[a-z0-9]').hasMatch(cleaned);
  }
}

bool _categoryMatchesPolarity(
  PromptTagCategory category, {
  required bool negative,
}) {
  final categoryIsNegative = switch (category) {
    PromptTagCategory.negativeQuality ||
    PromptTagCategory.negativeBody ||
    PromptTagCategory.negativeArtist ||
    PromptTagCategory.negativeContent =>
      true,
    _ => false,
  };
  return categoryIsNegative == negative;
}

const _qualityWords = [
  'masterpiece',
  'best quality',
  'high quality',
  'very aesthetic',
  'aesthetic',
  'highres',
  'absurdres',
  'detailed',
  'quality',
];

const _styleWords = [
  'realistic',
  'anime',
  'flat color',
  'monochrome',
  'muted color',
  'coloring',
  '3d',
  'style',
  'lighting',
  'shadow',
  'palette',
  'lineart',
  'sketch',
  'dithering',
  'halftone',
  'screentone',
  'gleaming',
  '100-layer',
];

const _artistChainStyleWords = [
  'official style',
  'official art',
  'official illustration',
];

const _upperBodyWords = [
  'breast',
  'breasts',
  'nipple',
  'nipples',
  'inverted nipples',
  'large breasts',
  'small breasts',
  'areola',
  'arm',
  'hand',
  'wrist',
  'torso',
  'shoulder',
  'choker',
  'necklace',
  'ribbon',
  'hair ornament',
  'hairclip',
  'hair clip',
  'headband',
  'navel',
  'stomach',
  'body',
  'cleft of venus',
  'cameltoe',
  'cleavage',
  'pubic tattoo',
  'pink tattoo',
  'steaming body',
  'white aura cover body',
];

const _lowerBodyWords = [
  'leg',
  'thigh',
  'feet',
  'foot',
  'barefoot',
  'tail',
  'pussy',
  'ass',
  'testicles',
  'penis',
  'erection',
  'vaginal',
  'anal',
  'hip',
  'hips',
  'stomach bulge',
];

const _accessoryWords = [
  'collar',
  'choker',
  'necklace',
  'earring',
  'earrings',
  'hair ornament',
  'hairclip',
  'hair clip',
  'headband',
  'hairband',
  'crown',
  'bracelet',
  'anklet',
  'glasses',
  'halo',
];
const _clothingStateWords = [
  'strap slip',
  'slipping strap',
  'no panties',
  'topless',
  'bottomless',
  'completely nude',
  'completly nude',
  'nude',
  'naked',
  'shirt lift',
  'clothes lift',
  'dress lift',
  'skirt lift',
  'open clothes',
  'open shirt',
  'open jacket',
  'panties aside',
  'bikini aside',
  'pulling down',
  'pulled down',
  'taking off',
  'take off',
  'undressing',
  'partially undressed',
];

const _upperClothingWords = [
  'shirt',
  'blouse',
  'jacket',
  'coat',
  'hoodie',
  'sweater',
  'sleeve',
  'glove',
  'bra',
  'bikini top',
  'top',
  'hood',
  'rope',
  'head wreath',
  'wreath',
  'sticker',
  'tattoo',
  'cage',
];

const _lowerClothingWords = [
  'skirt',
  'pants',
  'shorts',
  'panties',
  'thighhigh',
  'stocking',
  'sock',
  'shoe',
  'boots',
  'leggings',
];

const _clothingWords = [
  'dress',
  'belt',
  'armor',
  'uniform',
  'open shirt',
  'robe',
  'kimono',
  'swimsuit',
  'clothes',
  'outfit',
  'costume',
];

const _cameraWords = [
  'from above',
  'from below',
  'cowboy shot',
  'close-up',
  'close up',
  'solo focus',
  'looking at viewer',
  'looking up',
  'looking to the side',
  'pov',
  'view',
  'out of frame',
  'full body',
  'depth of field',
  'x-ray',
  'size difference',
  'look up',
];

const _actionWords = [
  'standing',
  'sitting',
  'walking',
  'running',
  'holding',
  'pose',
  'fighting',
  'grab',
  'sex',
  'fellatio',
  'trembling',
  'crying',
  'tears',
  'heavy breathing',
  'tearing up',
  'tongue out',
  'seductive',
  'disgust',
  'smile',
  'kiss',
  'hug',
  'spread',
  'kneeling',
  'motion lines',
  'notice lines',
  'sweat',
  'heart',
  'blood',
  'cum',
  'bukkake',
  'paizuri',
  'gangbang',
  'bondage',
  'mind control',
  'defeated',
  'shy',
  'horny',
  'tearing',
  'breathing',
  'steaming',
  'aura',
  'multiple expressions',
  'hit effect',
  ':d',
  ':o',
];

const _sceneWords = [
  'indoors',
  'outdoors',
  'background',
  'floor',
  'room',
  'street',
  'castle',
  'city',
  'sky',
  'forest',
  'water',
  'bed',
  'day',
  'night',
  'sun',
  'moon',
  'cloud',
  'snow',
  'rain',
  'flower',
  'grass',
  'tree',
  'text',
  'sound effects',
  'blank page',
  'negative space',
  'recording',
  'battery indicator',
  'liquid',
  'bacterie',
  'midden',
  'cup',
  'sake',
  'tokkuri',
  'pizza',
];

const _characterWords = [
  'hair',
  'eyes',
  'ears',
  'horns',
  'halo',
  'girl',
  'boy',
  'woman',
  'man',
  'loli',
  'hololive',
  'skin',
  'face',
  'mouth',
  'nose',
  'animal ears',
  'animal ear fluff',
  'pointy ears',
  'fang',
  'teeth',
  'pupil',
  'eyewear',
  'bald',
  'petite',
  'curvy',
  'muscular',
  'sidelocks',
  'mesugaki',
  'animalization',
  'slim',
];

const _characterSeriesWords = [
  'blue archive',
  'arknights',
  'honkai star rail',
  'honkai impact',
  'genshin impact',
  'granblue fantasy',
  'princess connect',
  'touhou',
  'azur lane',
  'date a live',
  'fate grand order',
  'hololive',
  'nijisanji',
  'idolmaster',
  'pokemon',
];

const _negativeQualityWords = [
  'lowres',
  'worst',
  'bad quality',
  'jpeg artifacts',
  'blurry',
  'error',
  'scan artifacts',
  'film grain',
];

const _negativeBodyWords = [
  'bad anatomy',
  'bad hands',
  'finger',
  'extra digits',
  'missing',
  'extra arms',
  'extra legs',
  'body',
  'hand',
];

PromptTagCategory _categoryFromName(String? name) {
  final normalized = name?.trim();
  if (normalized == null || normalized.isEmpty) {
    return PromptTagCategory.other;
  }
  final normalizedKey =
      normalized.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  return PromptTagCategory.values.firstWhere(
    (category) =>
        category.name == normalized ||
        category.name.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase() ==
            normalizedKey,
    orElse: () => PromptTagCategory.other,
  );
}

String _cleanTag(String tag) {
  var cleaned = PromptTagProcessor.cleanTagDisplay(tag)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  while (
      cleaned.length >= 2 && cleaned.startsWith('(') && cleaned.endsWith(')')) {
    cleaned = cleaned.substring(1, cleaned.length - 1).trim();
  }
  return cleaned;
}

bool _isUserConfirmedSource(String source) {
  final normalized = source.trim().toLowerCase();
  return normalized.startsWith('manual') || normalized.startsWith('user');
}
