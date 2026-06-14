import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_presentation.dart';

void main() {
  group('PromptTagPresentation', () {
    test('parses prompt tags into shared display and raw values', () {
      final items = promptTagPresentationItems(
        '1.5::makoron117117::, blue hair',
      );

      expect(items, hasLength(2));
      expect(items[0].index, 0);
      expect(items[0].displayLabel, 'makoron117117');
      expect(items[0].rawTag, '1.5:: makoron117117 ::');
      expect(items[0].weight, 1.5);
      expect(items[0].weightLabel, 'x1.50');
      expect(items[1].index, 1);
      expect(items[1].displayLabel, 'blue hair');
      expect(items[1].rawTag, 'blue hair');
      expect(items[1].weight, isNull);
    });

    test('classifies with manual cache before presentation overrides', () {
      final cache = PromptTagClassificationCache(clock: () => 42)
        ..setCategory(
          'blue hair',
          PromptTagCategory.upperBody,
          source: 'manual-role-field',
        );

      final classification = classifyPromptTagForPresentation(
        'blue hair',
        cache: cache,
        overrides: const {'blue_hair': PromptTagCategory.artist},
      );

      expect(classification.category, PromptTagCategory.upperBody);
      expect(classification.group.id, 'clothing');
    });

    test('uses presentation overrides before rule classification', () {
      final classification = classifyPromptTagForPresentation(
        'artist: makoron117117',
        overrides: const {'makoron117117': PromptTagCategory.character},
      );

      expect(classification.category, PromptTagCategory.character);
      expect(classification.group.id, 'character');
    });

    test('reads translation override before cache translation', () {
      final cache = TranslationCache(
        entries: const {
          'en2zh:blue hair': TranslationCacheEntry(
            translation: 'cache value',
            source: 'test',
            ts: 1,
          ),
        },
      );

      final translated = promptTagPresentationTranslation(
        'blue hair',
        cache: cache,
        overrides: const {'blue hair': 'manual value'},
      );

      expect(translated, 'manual value');
    });

    test('formats editable prompt tag weights consistently', () {
      expect(formatPromptTagWeightText(1), '1');
      expect(formatPromptTagWeightText(1.2), '1.2');
      expect(formatPromptTagWeightText(0.875), '0.875');
      expect(formatPromptTagWeightText(-2), '-2');
    });

    test('formats weighted prompt tag raw values consistently', () {
      expect(
        formatPromptTagWeightedValue('blue eyes', 1.2),
        '1.2:: blue eyes ::',
      );
      expect(
        formatPromptTagWeightedValue('animal ear hood', -2),
        '-2:: animal ear hood ::',
      );
    });
  });
}
