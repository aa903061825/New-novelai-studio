import 'dart:convert';
import 'dart:io';

typedef TranslationClock = int Function();

enum TranslationSource { empty, cache, cleanedCache, localDictionary, miss }

class TranslationResult {
  final String text;
  final TranslationSource source;

  const TranslationResult({
    required this.text,
    required this.source,
  });
}

class TranslationCacheEntry {
  final String translation;
  final String source;
  final int ts;

  const TranslationCacheEntry({
    required this.translation,
    required this.source,
    required this.ts,
  });

  factory TranslationCacheEntry.fromValue(dynamic value) {
    if (value is String) {
      return TranslationCacheEntry(
        translation: value,
        source: 'legacy',
        ts: 0,
      );
    }
    if (value is Map) {
      return TranslationCacheEntry(
        translation:
            value['translation'] as String? ?? value['text'] as String? ?? '',
        source: value['source']?.toString() ?? 'legacy',
        ts: value['ts'] as int? ?? 0,
      );
    }
    return const TranslationCacheEntry(
      translation: '',
      source: 'legacy',
      ts: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'translation': translation,
      'source': source,
      'ts': ts,
    };
  }
}

class TranslationCache {
  static const promptWorkshopLocalDictionary = {
    'idle': '待机',
    'run': '跑步',
    'walk': '走路',
    'attack': '攻击',
    'jump': '跳跃',
    'die': '死亡',
    'hit': '受击',
    'sword': '剑',
    'shield': '盾',
    'magic': '魔法',
    'masterpiece': '杰作',
    'best quality': '最佳画质',
    '1girl': '1个女孩',
    'solo': '单人',
    'blue eyes': '蓝眼睛',
    'cat ears': '猫耳',
    'simple background': '简单背景',
    'white background': '白色背景',
    'city lights': '城市灯光',
    'long hair': '长发',
    'short hair': '短发',
    'looking at viewer': '看向观众',
    'blush': '脸红',
    'smile': '微笑',
    'open mouth': '张嘴',
    'closed mouth': '闭嘴',
    'year 2024': '2024年',
    'absurdres': '超高分辨率',
    'highres': '高分辨率',
  };

  final TranslationClock _clock;
  final Map<String, TranslationCacheEntry> _entries;
  final Map<String, Map<String, String>> _reverseLookupBySourceMode =
      <String, Map<String, String>>{};

  TranslationCache({
    TranslationClock? clock,
    Map<String, TranslationCacheEntry>? entries,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000),
        _entries = {...?entries};

  factory TranslationCache.fromJson(Map<String, dynamic> json) {
    final entries = <String, TranslationCacheEntry>{};
    for (final entry in json.entries) {
      final cacheEntry = TranslationCacheEntry.fromValue(entry.value);
      if (cacheEntry.translation.isNotEmpty &&
          !looksLikeAiRefusal(cacheEntry.translation)) {
        entries[entry.key] = cacheEntry;
      }
    }
    return TranslationCache(entries: entries);
  }

  String? getCached(String text, {String mode = 'en2zh'}) {
    final direct = _usableTranslation(entryFor(text, mode: mode));
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    return _reverseCached(text, mode: mode);
  }

  Map<String, TranslationCacheEntry> get entries => Map.unmodifiable(_entries);

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  TranslationCacheEntry? entryFor(String text, {String mode = 'en2zh'}) {
    final key = cacheKey(text, mode: mode);
    return _entries[key];
  }

  String? _reverseCached(String text, {required String mode}) {
    final reverseMode = _reverseMode(mode);
    if (reverseMode == null) {
      return null;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final cleaned = cleanForTranslation(trimmed);
    final reverseLookup = _reverseLookupForSourceMode(reverseMode);
    final direct = reverseLookup[trimmed];
    if (direct != null) {
      return direct;
    }
    if (cleaned.isNotEmpty) {
      return reverseLookup[cleaned];
    }
    return null;
  }

  Map<String, String> _reverseLookupForSourceMode(String sourceMode) {
    final cached = _reverseLookupBySourceMode[sourceMode];
    if (cached != null) {
      return cached;
    }
    final suffix = '_$sourceMode';
    final lookup = <String, String>{};
    for (final entry in _entries.entries) {
      if (!entry.key.endsWith(suffix)) {
        continue;
      }
      final translation = _usableTranslation(entry.value);
      if (translation == null) {
        continue;
      }
      final sourceText = textFromCacheKey(entry.key, mode: sourceMode);
      _addReverseLookup(lookup, translation, sourceText);
      final cleanedTranslation = cleanForTranslation(translation);
      if (cleanedTranslation.isNotEmpty) {
        _addReverseLookup(lookup, cleanedTranslation, sourceText);
      }
    }
    _reverseLookupBySourceMode[sourceMode] = lookup;
    return lookup;
  }

  void _addReverseLookup(
    Map<String, String> lookup,
    String translation,
    String sourceText,
  ) {
    final key = translation.trim();
    if (key.isEmpty) {
      return;
    }
    lookup.putIfAbsent(key, () => sourceText);
  }

  void setManual(String text, String translation, {String mode = 'en2zh'}) {
    setCached(text, translation, mode: mode, source: 'manual');
  }

  void setCached(
    String text,
    String translation, {
    String mode = 'en2zh',
    String source = 'manual',
  }) {
    final trimmedText = text.trim();
    final trimmedTranslation = translation.trim();
    if (trimmedText.isEmpty || trimmedTranslation.isEmpty) {
      return;
    }
    if (source != 'manual' && looksLikeAiRefusal(trimmedTranslation)) {
      return;
    }
    _entries[cacheKey(trimmedText, mode: mode)] = TranslationCacheEntry(
      translation: trimmedTranslation,
      source: source,
      ts: _clock(),
    );
    _reverseLookupBySourceMode.remove(mode);
  }

  TranslationResult translate(String text, {String mode = 'en2zh'}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const TranslationResult(
        text: '',
        source: TranslationSource.empty,
      );
    }

    final direct = getCached(trimmed, mode: mode);
    if (direct != null) {
      return TranslationResult(text: direct, source: TranslationSource.cache);
    }

    final cleaned = cleanForTranslation(trimmed);
    if (cleaned.isNotEmpty && cleaned != trimmed) {
      final cleanedHit = getCached(cleaned, mode: mode);
      if (cleanedHit != null) {
        return TranslationResult(
          text: cleanedHit,
          source: TranslationSource.cleanedCache,
        );
      }
    }

    if (mode == 'en2zh') {
      final normalized = _normalizeForTranslationLookup(trimmed);
      final local = promptWorkshopLocalDictionary[normalized];
      if (local != null) {
        return TranslationResult(
          text: local,
          source: TranslationSource.localDictionary,
        );
      }

      final yearMatch = RegExp(r'^year\s*(\d{4})$').firstMatch(normalized);
      if (yearMatch != null) {
        return TranslationResult(
          text: '${yearMatch.group(1)}年',
          source: TranslationSource.localDictionary,
        );
      }
    }

    return const TranslationResult(text: '', source: TranslationSource.miss);
  }

  List<TranslationResult> translateBatch(
    List<String> texts, {
    String mode = 'en2zh',
  }) {
    return [
      for (final text in texts) translate(text, mode: mode),
    ];
  }

  Map<String, dynamic> toJson() {
    return {
      for (final entry in _entries.entries) entry.key: entry.value.toJson(),
    };
  }

  static String cacheKey(String text, {String mode = 'en2zh'}) {
    return '${text.trim()}_$mode';
  }

  static String textFromCacheKey(String key, {String mode = 'en2zh'}) {
    final suffix = '_$mode';
    if (!key.endsWith(suffix)) {
      return key.trim();
    }
    return key.substring(0, key.length - suffix.length).trim();
  }

  static String cleanForTranslation(String text) {
    var cleaned = text.replaceAll(RegExp(r'[-+]?\d+(?:\.\d+)?::|::'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[{}\[\]()]'), '');
    cleaned = cleaned.replaceAll('_', ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  static bool looksLikeAiRefusal(String text) {
    final normalized =
        text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return false;
    }
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    final chineseRefusal = (compact.contains('抱歉') ||
            compact.contains('对不起') ||
            compact.contains('很抱歉')) &&
        (compact.contains('无法') ||
            compact.contains('不能') ||
            compact.contains('不便') ||
            compact.contains('合规') ||
            compact.contains('政策'));
    if (chineseRefusal) {
      return true;
    }
    if (compact.contains('无法回答这个问题') ||
        compact.contains('不能回答这个问题') ||
        compact.contains('请提出其他合规的问题')) {
      return true;
    }
    return normalized.contains("i'm sorry") ||
        normalized.contains('i am sorry') ||
        normalized.contains('i cannot assist') ||
        normalized.contains("i can't assist") ||
        normalized.contains('cannot answer that') ||
        normalized.contains("can't answer that");
  }

  static String _normalizeForTranslationLookup(String text) {
    return cleanForTranslation(text).toLowerCase();
  }

  String? _usableTranslation(TranslationCacheEntry? entry) {
    final translation = entry?.translation.trim();
    if (translation == null || translation.isEmpty) {
      return null;
    }
    if (looksLikeAiRefusal(translation)) {
      return null;
    }
    return translation;
  }

  static String? _reverseMode(String mode) {
    return switch (mode) {
      'en2zh' => 'zh2en',
      'zh2en' => 'en2zh',
      _ => null,
    };
  }
}

class TranslationCacheRepository {
  final File file;

  const TranslationCacheRepository(this.file);

  Future<TranslationCache> load() async {
    if (!await file.exists()) {
      return TranslationCache();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return TranslationCache();
      }
      return TranslationCache.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return TranslationCache();
    }
  }

  Future<void> save(TranslationCache cache) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(cache.toJson())}\n');
  }
}
