import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';

void main() {
  group('PromptTagClassifier', () {
    test('normalizes prompt tags into Danbooru wiki URLs', () {
      expect(
        PromptTagClassifier.danbooruWikiUri('blue eyes').toString(),
        'https://danbooru.donmai.us/wiki_pages/blue_eyes',
      );
      expect(
        PromptTagClassifier.danbooruWikiUri('artist: jon_(pixiv31559095)')
            .toString(),
        'https://danbooru.donmai.us/wiki_pages/jon_(pixiv31559095)',
      );
      expect(
        PromptTagClassifier.danbooruWikiUri('1.2::(best quality)::').toString(),
        'https://danbooru.donmai.us/wiki_pages/best_quality',
      );
    });

    test('classifies tags without writing rule results into cache', () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000);

      final first = PromptTagClassifier.classify(
        'best quality',
        cache: cache,
      );
      expect(first.category, PromptTagCategory.quality);
      expect(cache.length, 0);
      expect(cache.entryFor('best quality'), isNull);

      cache.setCategory(
        'best quality',
        PromptTagCategory.artist,
        source: 'manual-test',
      );

      final second = PromptTagClassifier.classify(
        'best quality',
        cache: cache,
      );
      expect(second.category, PromptTagCategory.artist);
      expect(second.group.id, 'artist');
    });

    test('keeps positive and negative cached categories separate', () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000);

      final negative = PromptTagClassifier.classify(
        'jewelry',
        negative: true,
        cache: cache,
      );
      expect(negative.category, PromptTagCategory.negativeContent);
      expect(cache.entryFor('jewelry'), isNull);
      expect(cache.entryFor('jewelry', negative: true), isNull);

      final positive = PromptTagClassifier.classify(
        'jewelry',
        cache: cache,
      );
      expect(positive.category, PromptTagCategory.other);
      expect(cache.length, 0);
      expect(cache.entryFor('jewelry'), isNull);
      expect(cache.entryFor('jewelry', negative: true), isNull);
    });

    test('ignores stale rule-derived cache without rewriting it', () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000)
        ..setCategory(
          'blue silver hair',
          PromptTagCategory.other,
          source: 'rules',
        );

      final result = PromptTagClassifier.classify(
        'blue silver hair',
        cache: cache,
      );

      expect(result.category, PromptTagCategory.character);
      expect(
        cache.entryFor('blue silver hair')?.category,
        PromptTagCategory.other,
      );
      expect(cache.entryFor('blue silver hair')?.source, 'rules');
    });

    test('round trips globally valid compound tags', () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000)
        ..confirmValidCompoundTag('Male   Smile');

      final restored = PromptTagClassificationCache.fromJson(cache.toJson());

      expect(restored.isValidCompoundTag('male smile'), isTrue);
      expect(restored.toJson()['__validCompoundTags'], ['male smile']);
      expect(restored.entries, isEmpty);
    });

    test('merges missing classifications without replacing existing entries',
        () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000)
        ..setCategory(
          'blue eyes',
          PromptTagCategory.character,
          source: 'manual',
        )
        ..confirmValidCompoundTag('male smile');
      final loaded = PromptTagClassificationCache.fromJson({
        'blue eyes': {
          'category': PromptTagCategory.style.name,
          'source': 'loaded',
          'updatedAt': 1710000001,
        },
        'cat ears': {
          'category': PromptTagCategory.upperBody.name,
          'source': 'loaded',
          'updatedAt': 1710000001,
        },
        '__validCompoundTags': ['tail wagging'],
      });

      final merged = cache.mergeMissingFrom(loaded);

      expect(merged, 3);
      expect(
          cache.entryFor('blue eyes')?.category, PromptTagCategory.character);
      expect(cache.entryFor('cat ears')?.category, PromptTagCategory.upperBody);
      expect(cache.isValidCompoundTag('male smile'), isTrue);
      expect(cache.isValidCompoundTag('tail wagging'), isTrue);
    });

    test('merge replaces render-only rule entries with loaded classifications',
        () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000)
        ..setCategory(
          'standing',
          PromptTagCategory.action,
          source: 'rules',
        );
      final loaded = PromptTagClassificationCache.fromJson({
        'positive:standing': {
          'category': PromptTagCategory.artist.name,
          'source': 'manual',
          'updatedAt': 1710000001,
        },
      });

      final merged = cache.mergeMissingFrom(loaded);

      expect(merged, 1);
      expect(cache.entryFor('standing')?.category, PromptTagCategory.artist);
      expect(cache.entryFor('standing')?.source, 'manual');
    });

    test(
        'mergeMissingSuggestions inserts misses and preserves manual classifications',
        () {
      final cache = PromptTagClassificationCache(clock: () => 1710000000)
        ..setCategory(
          'blue eyes',
          PromptTagCategory.character,
          source: 'manual',
        )
        ..setCategory(
          'green eyes',
          PromptTagCategory.character,
          source: 'ai_extraction',
        );

      final merged = cache.mergeMissingSuggestions([
        const PromptTagClassificationSuggestion(
          tag: 'blue eyes',
          category: PromptTagCategory.upperBody,
          source: 'ai_extraction',
        ),
        const PromptTagClassificationSuggestion(
          tag: 'red dress',
          category: PromptTagCategory.upperClothing,
          source: 'ai_extraction',
        ),
        const PromptTagClassificationSuggestion(
          tag: 'green eyes',
          category: PromptTagCategory.upperBody,
          source: 'ai_extraction',
        ),
      ]);

      expect(merged, 1);
      expect(
        cache.entryFor('blue eyes')?.category,
        PromptTagCategory.character,
      );
      expect(
        cache.entryFor('red dress')?.category,
        PromptTagCategory.upperClothing,
      );
      expect(cache.entryFor('red dress')?.source, 'ai_extraction');
      expect(
        cache.entryFor('green eyes')?.category,
        PromptTagCategory.character,
      );

      final refreshed = cache.mergeMissingSuggestions(
        [
          const PromptTagClassificationSuggestion(
            tag: 'green eyes',
            category: PromptTagCategory.upperBody,
            source: 'ai_extraction',
          ),
          const PromptTagClassificationSuggestion(
            tag: 'blue eyes',
            category: PromptTagCategory.upperBody,
            source: 'ai_extraction',
          ),
        ],
        refreshMachineEntries: true,
      );

      expect(refreshed, 1);
      expect(
        cache.entryFor('green eyes')?.category,
        PromptTagCategory.upperBody,
      );
      expect(
        cache.entryFor('blue eyes')?.category,
        PromptTagCategory.character,
      );
    });

    test('ignores legacy negative cache entries in positive prompts', () {
      final cache = PromptTagClassificationCache.fromJson({
        'demon tail': {
          'category': PromptTagCategory.negativeContent.name,
          'source': 'legacy',
          'updatedAt': 1710000000,
        },
      });

      final positive = PromptTagClassifier.classify(
        'demon_tail',
        cache: cache,
      );

      expect(positive.category, PromptTagCategory.lowerBody);
      expect(cache.entryFor('demon_tail'), isNull);
      expect(
        cache.entryFor('demon_tail', negative: true)?.category,
        PromptTagCategory.negativeContent,
      );
    });

    test('classifies series-qualified character names as character tags', () {
      for (final tag in [
        'wakamo (blue archive)',
        'wakamo blue archive',
        'march_7th_(honkai:_star_rail)',
        'firefly (honkai: star rail)',
        'eyjafjalla_(arknights)',
        'himekawa yoshino (date a live)',
      ]) {
        final result = PromptTagClassifier.classify(tag);

        expect(
          result.category,
          PromptTagCategory.character,
          reason: '$tag should be a character tag',
        );
      }
    });

    test('classifies official style tags as artist-chain tags', () {
      for (final tag in [
        'official style',
        'official_art',
        '{{{{{official style}}}}}',
      ]) {
        final result = PromptTagClassifier.classify(tag);

        expect(
          result.category,
          PromptTagCategory.artist,
          reason: '$tag should stay with artist-chain tags',
        );
        expect(result.group.id, 'artist');
      }
    });

    test('classifies visible character traits and accessories outside other',
        () {
      final expectedCategories = {
        'blue silver hair': PromptTagCategory.character,
        'blue silver eyes': PromptTagCategory.character,
        'heart eyes': PromptTagCategory.character,
        'short double bun hair': PromptTagCategory.character,
        'white rabbit ears': PromptTagCategory.character,
        'pink hair ribbon': PromptTagCategory.accessory,
        'black choker': PromptTagCategory.accessory,
        'white rabbit tail': PromptTagCategory.lowerBody,
      };

      for (final entry in expectedCategories.entries) {
        final result = PromptTagClassifier.classify(entry.key);

        expect(
          result.category,
          entry.value,
          reason: '${entry.key} should not fall back to other',
        );
        expect(result.group.id, isNot('other'));
      }
    });

    test('classifies explicit upper body traits as upperBody', () {
      expect(
        PromptTagClassifier.classify('inverted nipples').category,
        PromptTagCategory.upperBody,
      );
      expect(
        PromptTagClassifier.classify('large breasts').category,
        PromptTagCategory.upperBody,
      );
      expect(
        PromptTagClassifier.classify('small breasts').category,
        PromptTagCategory.upperBody,
      );
      expect(
        PromptTagClassifier.classify('collarbone').category,
        PromptTagCategory.upperBody,
      );
    });

    test('classifies accessories separately from clothing state', () {
      expect(
        PromptTagClassifier.classify('black collar').category,
        PromptTagCategory.accessory,
      );
      expect(
        PromptTagClassifier.classify('animal collar').category,
        PromptTagCategory.accessory,
      );
      expect(
        PromptTagClassifier.classify('strap slip').category,
        PromptTagCategory.clothingState,
      );
      expect(
        PromptTagClassifier.classify('no panties').category,
        PromptTagCategory.clothingState,
      );
      expect(
        PromptTagClassifier.classify('completely nude').category,
        PromptTagCategory.clothingState,
      );
    });
  });
}
