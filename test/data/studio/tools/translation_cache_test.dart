import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';

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

    test('reads prompt workshop text entries with numeric source', () {
      final cache = TranslationCache.fromJson({
        'depth of field_en2zh': {
          'text': '景深',
          'source': 1,
        },
      });

      expect(cache.getCached('depth of field'), '景深');
      expect(cache.entryFor('depth of field')!.source, '1');
    });

    test('zh2en lookup reuses reverse en2zh cache hits', () {
      final cache = TranslationCache()
        ..setManual('blue eyes', '\u84dd\u773c\u775b');

      final result = cache.translate(
        '\u84dd\u773c\u775b',
        mode: 'zh2en',
      );

      expect(result.text, 'blue eyes');
      expect(result.source, TranslationSource.cache);
    });

    test('reverse lookup updates after manual cache overwrite', () {
      final cache = TranslationCache()
        ..setManual('blue eyes', '\u84dd\u773c\u775b');

      expect(
        cache.translate('\u84dd\u773c\u775b', mode: 'zh2en').text,
        'blue eyes',
      );

      cache.setManual('blue eyes', '\u78a7\u8272\u773c\u775b');

      expect(
        cache.translate('\u84dd\u773c\u775b', mode: 'zh2en').text,
        isEmpty,
      );
      expect(
        cache.translate('\u78a7\u8272\u773c\u775b', mode: 'zh2en').text,
        'blue eyes',
      );
    });

    test('manual overrides are stored with source and timestamp', () {
      final cache = TranslationCache(clock: () => 1710000000);

      cache.setManual('jacket', '外套');

      expect(cache.getCached('jacket'), '外套');
      expect(cache.entryFor('jacket')!.source, 'manual');
      expect(cache.length, 1);
      expect(cache.isEmpty, isFalse);
      expect(cache.entries.keys, ['jacket_en2zh']);
      expect(TranslationCache.textFromCacheKey('jacket_en2zh'), 'jacket');
      expect(cache.toJson(), {
        'jacket_en2zh': {
          'translation': '外套',
          'source': 'manual',
          'ts': 1710000000,
        },
      });
    });

    test('mergeMissingFrom imports usable misses without overwriting entries',
        () {
      final cache = TranslationCache(clock: () => 1710000000)
        ..setManual('blue eyes', 'manual-blue');
      final refreshed = TranslationCache.fromJson({
        'blue eyes_en2zh': {
          'translation': 'disk-blue',
          'source': 'ai',
          'ts': 1710000001,
        },
        'green_eyes_en2zh': {
          'translation': 'cached-green',
          'source': 'ai',
          'ts': 1710000002,
        },
        'bad_en2zh': {
          'translation': "I'm sorry, I cannot assist with that.",
          'source': 'ai',
          'ts': 1710000003,
        },
      });

      expect(cache.mergeMissingFrom(refreshed), 1);
      expect(cache.getCached('blue eyes'), 'manual-blue');
      expect(cache.getCached('green_eyes'), 'cached-green');
      expect(cache.getCached('bad'), isNull);
    });

    test('translation lookup falls back to cleaned weighted tags', () {
      final cache = TranslationCache();
      cache.setCached('masterpiece', '杰作', source: 'manual');

      final result = cache.translate('1.2::(masterpiece)::');

      expect(result.text, '杰作');
      expect(result.source, TranslationSource.cleanedCache);
    });

    test('translation lookup falls back to prompt workshop local dictionary',
        () {
      final cache = TranslationCache();

      final result = cache.translate('blue eyes');

      expect(result.text, '蓝眼睛');
      expect(result.source, TranslationSource.localDictionary);
    });

    test('local dictionary returns readable Simplified Chinese prompt labels',
        () {
      final cache = TranslationCache();

      expect(cache.translate('blue eyes').text, '蓝眼睛');
      expect(cache.translate('cat ears').text, '猫耳');
      expect(cache.translate('best quality').text, '最佳画质');
      expect(cache.translate('year_2023').text, '2023年');
    });

    test('underscore year tags normalize into local translation lookup', () {
      final cache = TranslationCache();

      expect(TranslationCache.cleanForTranslation('year_2023'), 'year 2023');

      final result = cache.translate('year_2023');

      expect(result.text, '2023年');
      expect(result.source, TranslationSource.localDictionary);
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

    test('AI refusal-style translations are ignored as cache misses', () {
      final cache = TranslationCache();
      cache.setCached(
        '(sincos)(year 2025)',
        '抱歉，我无法回答这个问题，请提出其他合规的问题',
        source: 'ai',
      );

      expect(cache.getCached('(sincos)(year 2025)'), isNull);

      final result = cache.translate('(sincos)(year 2025)');
      expect(result.text, isEmpty);
      expect(result.source, TranslationSource.miss);
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
