import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/prompt_workshop_bridge.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';

void main() {
  test('default prompt workshop cache candidates include the live cache folder',
      () {
    final translationPaths =
        PromptWorkshopBridge.defaultTranslationCacheCandidates()
            .map((file) => file.path)
            .toList(growable: false);
    final classificationPaths =
        PromptWorkshopBridge.defaultTagClassificationCacheCandidates()
            .map((file) => file.path)
            .toList(growable: false);

    expect(
      translationPaths,
      contains('E:\\NAI\u7684\u811a\u672c\u7fa4\\trans_cache.json'),
    );
    expect(
      classificationPaths,
      contains(
        'E:\\NAI\u7684\u811a\u672c\u7fa4\\tag_classification_cache.json',
      ),
    );

    expect(translationPaths, contains(r'E:\NAI的脚本群\trans_cache.json'));
    expect(
      classificationPaths,
      contains(r'E:\NAI的脚本群\tag_classification_cache.json'),
    );
  });

  test('default prompt workshop cache candidates include legacy app identity',
      () {
    final translationPaths =
        PromptWorkshopBridge.defaultTranslationCacheCandidates()
            .map((file) => file.path)
            .toList(growable: false);
    final classificationPaths =
        PromptWorkshopBridge.defaultTagClassificationCacheCandidates()
            .map((file) => file.path)
            .toList(growable: false);

    expect(
      translationPaths,
      contains(
        contains(
          '${Platform.pathSeparator}org.exception0x0194'
          '${Platform.pathSeparator}nai3_autodraw'
          '${Platform.pathSeparator}novel_studio'
          '${Platform.pathSeparator}configs'
          '${Platform.pathSeparator}trans_cache.json',
        ),
      ),
    );
    expect(
      classificationPaths,
      contains(
        contains(
          '${Platform.pathSeparator}org.exception0x0194'
          '${Platform.pathSeparator}nai3_autodraw'
          '${Platform.pathSeparator}novel_studio'
          '${Platform.pathSeparator}configs'
          '${Platform.pathSeparator}tag_classification_cache.json',
        ),
      ),
    );
  });

  test('loads translation cache from the first existing prompt workshop file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('prompt_workshop_bridge_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final missing = File('${directory.path}/missing.json');
    final cacheFile = File('${directory.path}/trans_cache.json');
    await cacheFile.writeAsString(
      jsonEncode({
        'depth of field_en2zh': {'text': 'depth translated', 'source': 1},
      }),
    );

    final cache = await PromptWorkshopBridge.loadTranslationCache(
      candidates: [missing, cacheFile],
    );

    expect(cache.getCached('depth of field'), 'depth translated');
  });

  test('falls back to empty translation cache for malformed files', () async {
    final directory =
        await Directory.systemTemp.createTemp('prompt_workshop_bridge_bad_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final malformed = File('${directory.path}/trans_cache.json');
    await malformed.writeAsString('not-json');

    final cache = await PromptWorkshopBridge.loadTranslationCache(
      candidates: [malformed],
    );

    expect(cache.isEmpty, isTrue);
  });

  test('merges smaller translation cache saves into larger existing file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('prompt_workshop_bridge_save_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final cacheFile = File('${directory.path}/trans_cache.json');
    await cacheFile.writeAsString(
      jsonEncode({
        'blue eyes_en2zh': {
          'translation': 'old blue',
          'source': 'bulk',
          'ts': 1,
        },
        'silver hair_en2zh': {
          'translation': 'silver',
          'source': 'bulk',
          'ts': 1,
        },
      }),
    );

    await PromptWorkshopBridge.saveTranslationCache(
      TranslationCache(
        entries: {
          'blue eyes_en2zh': const TranslationCacheEntry(
            translation: 'new blue',
            source: 'ai-refresh',
            ts: 2,
          ),
        },
      ),
      candidates: [cacheFile],
    );

    final saved = await PromptWorkshopBridge.loadTranslationCache(
      candidates: [cacheFile],
    );
    expect(saved.length, 2);
    expect(saved.getCached('blue eyes'), 'new blue');
    expect(saved.entryFor('blue eyes')?.source, 'ai-refresh');
    expect(saved.getCached('silver hair'), 'silver');
  });

  test('falls back to empty tag cache for malformed files', () async {
    final directory = await Directory.systemTemp
        .createTemp('prompt_workshop_bridge_bad_tags_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final malformed = File('${directory.path}/tag_classification_cache.json');
    await malformed.writeAsString('not-json');

    final cache = await PromptWorkshopBridge.loadTagClassificationCache(
      candidates: [malformed],
    );

    expect(cache.isEmpty, isTrue);
  });

  test('merges smaller classification cache saves into larger existing file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('prompt_workshop_bridge_tags_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final cacheFile = File('${directory.path}/tag_classification_cache.json');
    await cacheFile.writeAsString(
      jsonEncode({
        'positive:blue eyes': {
          'category': PromptTagCategory.character.name,
          'source': 'bulk',
          'updatedAt': 1,
        },
        'positive:silver hair': {
          'category': PromptTagCategory.upperBody.name,
          'source': 'bulk',
          'updatedAt': 1,
        },
      }),
    );

    await PromptWorkshopBridge.saveTagClassificationCache(
      PromptTagClassificationCache(
        entries: {
          'positive:blue eyes': const PromptTagClassificationCacheEntry(
            category: PromptTagCategory.style,
            source: 'manual',
            updatedAt: 2,
          ),
        },
      ),
      candidates: [cacheFile],
    );

    final saved = await PromptWorkshopBridge.loadTagClassificationCache(
      candidates: [cacheFile],
    );
    expect(saved.length, 2);
    expect(saved.entryFor('blue eyes')?.category, PromptTagCategory.style);
    expect(saved.entryFor('blue eyes')?.source, 'manual');
    expect(
        saved.entryFor('silver hair')?.category, PromptTagCategory.upperBody);
  });
}
