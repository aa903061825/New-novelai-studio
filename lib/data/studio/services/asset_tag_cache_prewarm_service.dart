import 'dart:collection';

import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/services/prompt_workshop_bridge.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

typedef AssetTagCachePrewarmProgressCallback = void Function(
  AssetTagCachePrewarmProgress progress,
);

class AssetTagCachePrewarmProgress {
  final String phase;
  final int processed;
  final int total;
  final String message;

  const AssetTagCachePrewarmProgress({
    required this.phase,
    required this.processed,
    required this.total,
    required this.message,
  });
}

class AssetTagCachePrewarmResult {
  final int scannedTextCount;
  final int uniqueTagCount;
  final int translationCacheHits;
  final int translatedCount;
  final int translationFailures;
  final int classifiedCount;

  const AssetTagCachePrewarmResult({
    required this.scannedTextCount,
    required this.uniqueTagCount,
    required this.translationCacheHits,
    required this.translatedCount,
    required this.translationFailures,
    required this.classifiedCount,
  });
}

class AssetTagCandidate {
  final String text;
  final bool negative;
  final String source;
  final String? seedTranslation;

  const AssetTagCandidate({
    required this.text,
    required this.negative,
    required this.source,
    this.seedTranslation,
  });

  AssetTagCandidate copyWith({bool? negative, String? seedTranslation}) {
    return AssetTagCandidate(
      text: text,
      negative: negative ?? this.negative,
      source: source,
      seedTranslation: seedTranslation ?? this.seedTranslation,
    );
  }
}

class AssetTagCollection {
  final List<AssetTagCandidate> candidates;
  final int scannedTextCount;

  const AssetTagCollection({
    required this.candidates,
    required this.scannedTextCount,
  });
}

class AssetTagCachePrewarmService {
  static const int fullCodexLimit = 0x3fffffff;

  final StudioAssetCatalogService catalogService;
  final PromptTranslationService translationService;
  final TranslationCache translationCache;
  final PromptTagClassificationCache classificationCache;
  final Future<void> Function(TranslationCache cache) saveTranslationCache;
  final Future<void> Function(PromptTagClassificationCache cache)
      saveClassificationCache;

  AssetTagCachePrewarmService({
    required this.catalogService,
    required this.translationService,
    required this.translationCache,
    required this.classificationCache,
    Future<void> Function(TranslationCache cache)? saveTranslationCache,
    Future<void> Function(PromptTagClassificationCache cache)?
        saveClassificationCache,
  })  : saveTranslationCache =
            saveTranslationCache ?? PromptWorkshopBridge.saveTranslationCache,
        saveClassificationCache = saveClassificationCache ??
            PromptWorkshopBridge.saveTagClassificationCache;

  Future<AssetTagCachePrewarmResult> prewarm({
    bool includeCodex = true,
    int legacyCodexLimit = fullCodexLimit,
    AssetTagCachePrewarmProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const AssetTagCachePrewarmProgress(
        phase: 'loading',
        processed: 0,
        total: 0,
        message: 'Loading asset catalog...',
      ),
    );
    final snapshot = await catalogService.loadSnapshot(
      includeLegacyCodex: includeCodex,
      legacyCodexLimit: legacyCodexLimit,
    );
    return warmSnapshot(snapshot, onProgress: onProgress);
  }

  Future<AssetTagCachePrewarmResult> warmSnapshot(
    StudioAssetCatalogSnapshot snapshot, {
    AssetTagCachePrewarmProgressCallback? onProgress,
  }) async {
    final collection = collectAssetTagCandidates(snapshot);
    final candidates = collection.candidates;
    onProgress?.call(
      AssetTagCachePrewarmProgress(
        phase: 'scanned',
        processed: 0,
        total: candidates.length,
        message: 'Scanned ${candidates.length} unique tags.',
      ),
    );

    var translationCacheHits = 0;
    var translatedCount = 0;
    var translationFailures = 0;
    var translationDirty = false;

    for (final (index, candidate) in candidates.indexed) {
      final seeded = candidate.seedTranslation?.trim();
      if (seeded != null && seeded.isNotEmpty) {
        final directEntry = translationCache.entryFor(candidate.text);
        if (directEntry == null) {
          translationCache.setCached(
            candidate.text,
            seeded,
            source: candidate.source,
          );
          translationDirty = true;
        }
        translationCacheHits += 1;
        _reportProgress(
          onProgress,
          processed: index + 1,
          total: candidates.length,
        );
        continue;
      }

      final cached = translationCache.translate(candidate.text);
      if (cached.text.trim().isNotEmpty) {
        translationCacheHits += 1;
        if (cached.source == TranslationSource.localDictionary ||
            cached.source == TranslationSource.cleanedCache) {
          translationCache.setCached(
            candidate.text,
            cached.text,
            source: cached.source.name,
          );
          translationDirty = true;
        }
      } else {
        try {
          final result = await translationService.translate(
            OnlineTranslationRequest(
              text: candidate.text,
              sourceLanguage: 'en',
              targetLanguage: 'zh',
            ),
            preferCache: false,
          );
          final translated = result.text.trim();
          if (translated.isEmpty ||
              result.source == OnlineAiResultSource.emptyFallback) {
            translationFailures += 1;
          } else {
            translationCache.setCached(
              candidate.text,
              translated,
              source: result.providerName ?? result.source.name,
            );
            translatedCount += 1;
            translationDirty = true;
          }
        } catch (_) {
          translationFailures += 1;
        }
      }

      _reportProgress(
        onProgress,
        processed: index + 1,
        total: candidates.length,
      );
    }

    if (translationDirty) {
      await saveTranslationCache(translationCache);
    }

    return AssetTagCachePrewarmResult(
      scannedTextCount: collection.scannedTextCount,
      uniqueTagCount: candidates.length,
      translationCacheHits: translationCacheHits,
      translatedCount: translatedCount,
      translationFailures: translationFailures,
      classifiedCount: 0,
    );
  }
}

AssetTagCollection collectAssetTagCandidates(
  StudioAssetCatalogSnapshot snapshot, {
  bool includeWorkflowPayloads = true,
  bool includeBatchPayloads = true,
  bool includeAssemblyPayloads = true,
}) {
  final collector = _AssetTagCandidateCollector();

  for (final character in snapshot.characters) {
    collector.addViewTexts(character.traits, 'character.traits');
    collector.addList(character.anchorTags, 'character.anchorTags');
    collector.addList(character.identityTags, 'character.identityTags');
    collector.addList(
      character.conflictTags,
      'character.conflictTags',
      negative: true,
    );
    for (final outfit in character.outfits) {
      collector.addViewTexts(outfit.tags, 'character.outfit.tags');
      collector.addList(
        outfit.partTags.upperBodyTags,
        'character.outfit.upperBodyTags',
      );
      collector.addList(
        outfit.partTags.upperClothingTags,
        'character.outfit.upperClothingTags',
      );
      collector.addList(
        outfit.partTags.lowerBodyTags,
        'character.outfit.lowerBodyTags',
      );
      collector.addList(
        outfit.partTags.lowerClothingTags,
        'character.outfit.lowerClothingTags',
      );
      collector.addList(
        outfit.partTags.weaponTags,
        'character.outfit.weaponTags',
      );
    }
  }

  for (final artistChain in snapshot.artistChains) {
    collector.addText(artistChain.prompt, 'artist.prompt');
    collector.addList(artistChain.tags, 'artist.tags');
    collector.addList(artistChain.styleTags, 'artist.styleTags');
    for (final artist in artistChain.artists) {
      collector.addText(
        '${artist.prefix}${artist.name}',
        'artist.artists',
      );
    }
    for (final entry in artistChain.translations.entries) {
      final key = entry.key.trim();
      final translation = entry.value.trim();
      if (key.isNotEmpty && translation.isNotEmpty) {
        collector.seedTranslation(key, translation);
      }
    }
    collector.addList(
      artistChain.globalNegatives.map((tag) => tag.tag),
      'artist.globalNegatives',
      negative: true,
    );
    collector.addList(
      artistChain.styleHintsWeighted.map((tag) => tag.tag),
      'artist.styleHintsWeighted',
    );
  }

  for (final recipe in snapshot.recipes) {
    collector.addText(recipe.tags, 'recipe.tags');
    collector.addList(recipe.variants.values, 'recipe.variants');
  }

  for (final tag in snapshot.tags) {
    if (tag.tag.trim().isNotEmpty && tag.zh.trim().isNotEmpty) {
      collector.seedTranslation(tag.tag, tag.zh);
    }
    collector.addText(tag.tag, 'tag.tag');
    collector.addList(tag.aliases, 'tag.aliases');
  }

  for (final inspiration in snapshot.inspirations) {
    collector.addText(inspiration.prompt, 'inspiration.prompt');
    collector.addText(
      inspiration.negativePrompt,
      'inspiration.negativePrompt',
      negative: true,
    );
    collector.addList(inspiration.tags, 'inspiration.tags');
  }

  for (final lora in snapshot.loras) {
    collector.addList(lora.triggerWords, 'lora.triggerWords');
  }

  if (includeWorkflowPayloads) {
    for (final workflow in snapshot.workflows) {
      collector.addPayload(workflow.payload, 'workflow.payload');
    }
  }
  if (includeBatchPayloads) {
    for (final batchPlan in snapshot.batchPlans) {
      collector.addPayload(batchPlan.items, 'batchPlan.items');
      collector.addPayload(batchPlan.statusSnapshot, 'batchPlan.status');
    }
  }
  if (includeAssemblyPayloads) {
    for (final preset in snapshot.assemblyPresets) {
      collector.addPayload(preset.payload, 'assembly.payload');
    }
  }

  return AssetTagCollection(
    candidates: collector.candidates,
    scannedTextCount: collector.scannedTextCount,
  );
}

class _AssetTagCandidateCollector {
  final LinkedHashMap<String, AssetTagCandidate> _candidates =
      LinkedHashMap<String, AssetTagCandidate>();
  int scannedTextCount = 0;

  List<AssetTagCandidate> get candidates =>
      List.unmodifiable(_candidates.values);

  void seedTranslation(String tag, String translation) {
    final cleaned = _cleanTag(tag);
    if (cleaned.isEmpty || translation.trim().isEmpty) {
      return;
    }
    final key = PromptTagProcessor.normalizeMatchKey(cleaned);
    final existing = _candidates[key];
    if (existing == null) {
      _candidates[key] = AssetTagCandidate(
        text: cleaned,
        negative: false,
        source: 'asset-library',
        seedTranslation: translation.trim(),
      );
    } else {
      _candidates[key] = existing.copyWith(
        seedTranslation: translation.trim(),
      );
    }
  }

  void addViewTexts(ViewVariantTexts texts, String source) {
    addText(texts.frontFull, '$source.frontFull');
    addText(texts.frontCowboy ?? '', '$source.frontCowboy');
    addText(texts.frontUpper ?? '', '$source.frontUpper');
    addText(texts.frontLower ?? '', '$source.frontLower');
    addText(texts.backFull ?? '', '$source.backFull');
    addText(texts.backCowboy ?? '', '$source.backCowboy');
    addText(texts.backUpper ?? '', '$source.backUpper');
    addText(texts.backLower ?? '', '$source.backLower');
  }

  void addList(
    Iterable<String> values,
    String source, {
    bool negative = false,
  }) {
    for (final value in values) {
      addText(value, source, negative: negative);
    }
  }

  void addText(
    String text,
    String source, {
    bool negative = false,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    for (final part in PromptTagProcessor.splitWorkshopTags(trimmed)) {
      final cleaned = _cleanTag(part);
      if (cleaned.isEmpty) {
        continue;
      }
      scannedTextCount += 1;
      final key = PromptTagProcessor.normalizeMatchKey(cleaned);
      final existing = _candidates[key];
      if (existing == null) {
        _candidates[key] = AssetTagCandidate(
          text: cleaned,
          negative: negative,
          source: source,
        );
      } else if (!existing.negative && negative) {
        _candidates[key] = existing.copyWith(negative: true);
      }
    }
  }

  void addPayload(
    Object? value,
    String source, {
    String key = '',
    bool negative = false,
  }) {
    final keyIsPromptLike = _isPromptLikeKey(key);
    final nextNegative = negative || _isNegativeKey(key);
    if (value is String) {
      if (keyIsPromptLike) {
        addText(value, source, negative: nextNegative);
      }
      return;
    }
    if (value is Iterable) {
      for (final item in value) {
        addPayload(item, source, key: key, negative: nextNegative);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        addPayload(
          entry.value,
          source,
          key: entry.key.toString(),
          negative: nextNegative,
        );
      }
    }
  }

  bool _isPromptLikeKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('prompt') ||
        normalized.contains('tag') ||
        normalized.contains('tags') ||
        normalized.contains('trigger') ||
        normalized.contains('caption');
  }

  bool _isNegativeKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('negative') || normalized.contains('exclude');
  }
}

String _cleanTag(String text) {
  return PromptTagProcessor.cleanTagDisplay(text)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void _reportProgress(
  AssetTagCachePrewarmProgressCallback? onProgress, {
  required int processed,
  required int total,
}) {
  if (processed != total && processed % 25 != 0) {
    return;
  }
  onProgress?.call(
    AssetTagCachePrewarmProgress(
      phase: 'warming',
      processed: processed,
      total: total,
      message: 'Warmed $processed/$total tags.',
    ),
  );
}
