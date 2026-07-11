import 'dart:io';

import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';

class PromptWorkshopBridge {
  const PromptWorkshopBridge._();

  static List<File> defaultTranslationCacheCandidates() {
    return [
      ..._workspaceCacheCandidates('trans_cache.json'),
      File(r'E:\NAI的脚本群\trans_cache.json'),
    ];
  }

  static List<File> defaultTagClassificationCacheCandidates() {
    return [
      ..._workspaceCacheCandidates('tag_classification_cache.json'),
      File(r'E:\NAI的脚本群\tag_classification_cache.json'),
    ];
  }

  static List<File> _workspaceCacheCandidates(String fileName) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      return const [];
    }
    return [
      File(
        '$appData${Platform.pathSeparator}Novel Studio'
        '${Platform.pathSeparator}Novel Studio'
        '${Platform.pathSeparator}novel_studio'
        '${Platform.pathSeparator}configs'
        '${Platform.pathSeparator}$fileName',
      ),
      File(
        '$appData${Platform.pathSeparator}org.exception0x0194'
        '${Platform.pathSeparator}nai3_autodraw'
        '${Platform.pathSeparator}novel_studio'
        '${Platform.pathSeparator}configs'
        '${Platform.pathSeparator}$fileName',
      ),
      File(
        '$appData${Platform.pathSeparator}novel_studio'
        '${Platform.pathSeparator}configs'
        '${Platform.pathSeparator}$fileName',
      ),
    ];
  }

  static Future<TranslationCache> loadTranslationCache({
    List<File>? candidates,
  }) async {
    for (final file in candidates ?? defaultTranslationCacheCandidates()) {
      if (!await file.exists()) continue;
      try {
        return await TranslationCacheRepository(file).load();
      } on FormatException {
        continue;
      }
    }
    return TranslationCache();
  }

  static Future<void> saveTranslationCache(
    TranslationCache cache, {
    List<File>? candidates,
  }) async {
    final files = candidates ?? defaultTranslationCacheCandidates();
    final target = files.firstWhere(
      (file) => file.existsSync(),
      orElse: () => files.first,
    );
    var cacheToSave = cache;
    if (target.existsSync()) {
      final existing = await TranslationCacheRepository(target).load();
      if (existing.length > cache.length) {
        cacheToSave = TranslationCache(
          entries: {
            ...existing.entries,
            ...cache.entries,
          },
        );
      }
    }
    await TranslationCacheRepository(target).save(cacheToSave);
  }

  static Future<PromptTagClassificationCache> loadTagClassificationCache({
    List<File>? candidates,
  }) async {
    for (final file
        in candidates ?? defaultTagClassificationCacheCandidates()) {
      if (!await file.exists()) continue;
      try {
        return await PromptTagClassificationCacheRepository(file).load();
      } on FormatException {
        continue;
      }
    }
    return PromptTagClassificationCache();
  }

  static Future<void> saveTagClassificationCache(
    PromptTagClassificationCache cache, {
    List<File>? candidates,
  }) async {
    final files = candidates ?? defaultTagClassificationCacheCandidates();
    final target = files.firstWhere(
      (file) => file.existsSync(),
      orElse: () => files.first,
    );
    var cacheToSave = cache;
    if (target.existsSync()) {
      final existing = await PromptTagClassificationCacheRepository(
        target,
      ).load();
      cacheToSave = PromptTagClassificationCache(
        entries: {
          ...existing.entries,
          ...cache.entries,
        },
        validCompoundTagKeys: {
          ...existing.validCompoundTagKeys,
          ...cache.validCompoundTagKeys,
        },
      );
    }
    await PromptTagClassificationCacheRepository(target).save(cacheToSave);
  }
}
