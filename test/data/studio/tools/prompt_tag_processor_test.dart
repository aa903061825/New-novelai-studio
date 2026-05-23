import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/filter_rule_config.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';

void main() {
  group('PromptTagProcessor', () {
    test('parses replace rules and ignores malformed lines', () {
      expect(
        PromptTagProcessor.parseReplaceRulesText(
          'jacket -> coat\nmissing arrow\nkousaka kirino -> kirino\n -> skip',
        ),
        const [
          ReplaceRule('jacket', 'coat'),
          ReplaceRule('kousaka kirino', 'kirino'),
        ],
      );
    });

    test('filters quantity, replacements, delete rules, and artist prompts',
        () {
      const config = FilterRuleConfig(
        deleteKeywords: 'masterpiece, low quality',
        replaceRules: 'jacket -> coat',
        deleteArtistTags: true,
      );

      final result = PromptTagProcessor.filterTags(
        'solo, masterpiece, red jacket, artist:sample, low quality',
        config: config,
      );

      expect(result.quantity, ['solo']);
      expect(result.clean, ['red coat']);
      expect(result.deleted, [
        'masterpiece',
        'artist:sample (artist)',
        'low quality',
      ]);
    });

    test('strong filters remove partial matches before normal matching', () {
      const config = FilterRuleConfig(strongFilterKeywords: 'bad hands');

      final result = PromptTagProcessor.filterTags(
        'good pose, bad hands on face',
        config: config,
      );

      expect(result.clean, ['good pose']);
      expect(result.deleted, ['bad hands on face']);
    });

    test('preserves weighted groups after filtering inner tags', () {
      const config = FilterRuleConfig(
        deleteKeywords: 'masterpiece',
        replaceRules: 'blue dress -> blue coat',
        removeWeights: false,
      );

      final result = PromptTagProcessor.filterTags(
        '1.2::masterpiece, blue dress::, city street',
        config: config,
      );

      expect(result.clean, ['1.2::blue coat::', 'city street']);
      expect(result.deleted, ['1.2::masterpiece']);
    });

    test('splits clean prompt tags into heuristic buckets', () {
      final buckets = PromptTagProcessor.heuristicSplit(
        'solo, artist:abc, watercolor, masterpiece, (hero focus), city street',
      );

      expect(buckets.scene, ['solo', 'city street']);
      expect(buckets.artist, ['artist:abc']);
      expect(buckets.style, ['watercolor']);
      expect(buckets.quality, ['masterpiece']);
      expect(buckets.character, ['(hero focus)']);
      expect(buckets.deleted, isEmpty);
    });
  });
}
