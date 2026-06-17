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
        'pink hair ribbon': PromptTagCategory.upperBody,
        'black choker': PromptTagCategory.upperBody,
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
  });
}
