import 'dart:convert';
import 'dart:io';

typedef TranslationClock = int Function();

enum TranslationSource { empty, cache, cleanedCache, miss }

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
        source: value['source'] as String? ?? 'legacy',
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
  final TranslationClock _clock;
  final Map<String, TranslationCacheEntry> _entries;

  TranslationCache({
    TranslationClock? clock,
    Map<String, TranslationCacheEntry>? entries,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000),
        _entries = {...?entries};

  factory TranslationCache.fromJson(Map<String, dynamic> json) {
    final entries = <String, TranslationCacheEntry>{};
    for (final entry in json.entries) {
      final cacheEntry = TranslationCacheEntry.fromValue(entry.value);
      if (cacheEntry.translation.isNotEmpty) {
        entries[entry.key] = cacheEntry;
      }
    }
    return TranslationCache(entries: entries);
  }

  String? getCached(String text, {String mode = 'en2zh'}) {
    return entryFor(text, mode: mode)?.translation;
  }

  TranslationCacheEntry? entryFor(String text, {String mode = 'en2zh'}) {
    final key = cacheKey(text, mode: mode);
    return _entries[key];
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
    _entries[cacheKey(trimmedText, mode: mode)] = TranslationCacheEntry(
      translation: trimmedTranslation,
      source: source,
      ts: _clock(),
    );
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

  static String cleanForTranslation(String text) {
    var cleaned = text.replaceAll(RegExp(r'[-+]?\d+(?:\.\d+)?::|::'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[{}\[\]()]'), '');
    return cleaned.trim();
  }
}

class TranslationCacheRepository {
  final File file;

  const TranslationCacheRepository(this.file);

  Future<TranslationCache> load() async {
    if (!await file.exists()) {
      return TranslationCache();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return TranslationCache();
    }
    return TranslationCache.fromJson(decoded.cast<String, dynamic>());
  }

  Future<void> save(TranslationCache cache) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(cache.toJson())}\n');
  }
}
