import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';

void main() {
  group('TranslationCache', () {
    test('reads legacy string and structured cache entries', () {
      final cache = TranslationCache.fromJson({
        'blue eyes_en2zh': '蓝眼睛',
        'red dress_en2zh': {
          'translation': '红裙子',
          'source': 'manual',
          'ts': 1710000000,
        },
      });

      expect(cache.getCached('blue eyes'), '蓝眼睛');
      expect(cache.getCached('red dress'), '红裙子');
      expect(cache.entryFor('red dress')!.source, 'manual');
    });

    test('manual overrides are stored with source and timestamp', () {
      final cache = TranslationCache(clock: () => 1710000000);

      cache.setManual('jacket', '外套');

      expect(cache.getCached('jacket'), '外套');
      expect(cache.entryFor('jacket')!.source, 'manual');
      expect(cache.toJson(), {
        'jacket_en2zh': {
          'translation': '外套',
          'source': 'manual',
          'ts': 1710000000,
        },
      });
    });

    test('translation lookup falls back to cleaned weighted tags', () {
      final cache = TranslationCache();
      cache.setCached('masterpiece', '杰作', source: 'manual');

      final result = cache.translate('1.2::(masterpiece)::');

      expect(result.text, '杰作');
      expect(result.source, TranslationSource.cleanedCache);
    });

    test('batch translation preserves order and reports empty or miss', () {
      final cache = TranslationCache();
      cache.setCached('blue eyes', '蓝眼睛', source: 'manual');

      final result = cache.translateBatch(['blue eyes', ' ', 'unknown tag']);

      expect(result.map((entry) => entry.text), ['蓝眼睛', '', '']);
      expect(result.map((entry) => entry.source), [
        TranslationSource.cache,
        TranslationSource.empty,
        TranslationSource.miss,
      ]);
    });

    test('repository round trips cache files', () async {
      final directory = await Directory.systemTemp.createTemp('trans_cache_');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}${Platform.pathSeparator}cache.json');
      final repository = TranslationCacheRepository(file);
      final cache = TranslationCache(clock: () => 1710000000)
        ..setManual('soft light', '柔光');

      await repository.save(cache);
      final loaded = await repository.load();

      expect(jsonDecode(await file.readAsString()), {
        'soft light_en2zh': {
          'translation': '柔光',
          'source': 'manual',
          'ts': 1710000000,
        },
      });
      expect(loaded.getCached('soft light'), '柔光');
    });
  });
}
