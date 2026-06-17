import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/prompt_workshop_bridge.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';

void main() {
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
        'depth of field_en2zh': {'text': '鏅繁', 'source': 1},
      }),
    );

    final cache = await PromptWorkshopBridge.loadTranslationCache(
      candidates: [missing, cacheFile],
    );

    expect(cache.getCached('depth of field'), '鏅繁');
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
          'translation': '旧蓝眼',
          'source': 'bulk',
          'ts': 1,
        },
        'silver hair_en2zh': {
          'translation': '银发',
          'source': 'bulk',
          'ts': 1,
        },
      }),
    );

    await PromptWorkshopBridge.saveTranslationCache(
      TranslationCache(
        entries: {
          'blue eyes_en2zh': const TranslationCacheEntry(
            translation: '新蓝眼',
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
    expect(saved.getCached('blue eyes'), '新蓝眼');
    expect(saved.entryFor('blue eyes')?.source, 'ai-refresh');
    expect(saved.getCached('silver hair'), '银发');
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
}
