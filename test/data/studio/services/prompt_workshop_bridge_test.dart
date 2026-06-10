import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/prompt_workshop_bridge.dart';

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

  test('falls back to empty tag cache for malformed files', () async {
    final directory =
        await Directory.systemTemp.createTemp('prompt_workshop_bridge_bad_tags_');
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
