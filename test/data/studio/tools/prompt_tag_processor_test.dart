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

    test(
      'filters quantity, replacements, delete rules, and artist prompts',
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
      },
    );

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

      expect(result.clean, ['1.2:: blue coat ::', 'city street']);
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

      final weightedBuckets = PromptTagProcessor.heuristicSplit(
        '1.5::blue eyes, long hair::, masterpiece',
        config: const FilterRuleConfig(removeWeights: false),
      );

      expect(weightedBuckets.scene, [
        '1.5:: blue eyes ::',
        '1.5:: long hair ::',
      ]);
      expect(weightedBuckets.quality, ['masterpiece']);
    });

    test('does not classify action text as style by substring match', () {
      final buckets = PromptTagProcessor.heuristicSplit(
        'fingers sinking into soft breasts, ink, soft shading, best quality',
      );

      expect(buckets.scene, ['fingers sinking into soft breasts']);
      expect(buckets.style, ['ink', 'soft shading']);
      expect(buckets.quality, ['best quality']);
    });

    test('splits prompt workshop tags in smart and force modes', () {
      expect(PromptTagProcessor.splitWorkshopTags('1.5::A,B,C,D::'), [
        '1.5:: A ::',
        '1.5:: B ::',
        '1.5:: C ::',
        '1.5:: D ::',
      ]);

      expect(
        PromptTagProcessor.splitWorkshopTags(
          '1.2::blue eyes, long hair::, {{best quality}}, [lowres]',
        ),
        [
          '1.2:: blue eyes ::',
          '1.2:: long hair ::',
          '{{best quality}}',
          '[lowres]',
        ],
      );

      expect(
        PromptTagProcessor.splitWorkshopTags(
          '1girl, blue eyes，long hair\nsimple background',
        ),
        ['1girl', 'blue eyes', 'long hair', 'simple background'],
      );

      expect(
        PromptTagProcessor.splitWorkshopTags(
          '1girl blue eyes, simple background',
          splitSpace: true,
        ),
        ['1girl', 'blue', 'eyes', 'simple', 'background'],
      );
    });

    test('repairs safe prompt workshop missing comma cases', () {
      expect(
        PromptTagProcessor.splitWorkshopTags(
          '1::nose blush:: 2::close-up, separated screens:: standing',
        ),
        [
          '1:: nose blush ::',
          '2:: close-up ::',
          'separated screens',
          'standing',
        ],
      );
    });

    test('marks suspicious two-word tags without flagging known phrases', () {
      final analysis = PromptTagProcessor.analyzeWorkshopTags(
        'male blush, blue eyes, depth of field',
      );

      expect(analysis.map((tag) => tag.text), [
        'male blush',
        'blue eyes',
        'depth of field',
      ]);
      expect(analysis.first.warning, WorkshopTagWarning.suspectedMissingComma);
      expect(analysis.first.suggestedParts, ['male', 'blush']);
      expect(analysis[1].warning, WorkshopTagWarning.none);
      expect(analysis[2].warning, WorkshopTagWarning.none);
    });

    test('analyzes prompt tag weights while keeping clean display text', () {
      final analysis = PromptTagProcessor.analyzeWorkshopTags(
        '1.2::blue eyes, long hair::, {{best quality}}, [lowres]',
      );

      expect(analysis.map((tag) => tag.displayText), [
        'blue eyes',
        'long hair',
        'best quality',
        'lowres',
      ]);
      expect(analysis.map((tag) => tag.weightLabel), [
        'x1.20',
        'x1.20',
        'x1.10',
        'x0.95',
      ]);
    });

    test('formats inline weights with spaces around digit-ending tags', () {
      expect(
        PromptTagProcessor.formatInlineWeightTag('makoron117117', 1.5),
        '1.5:: makoron117117 ::',
      );
      expect(PromptTagProcessor.splitWorkshopTags('1.5::makoron117117::'), [
        '1.5:: makoron117117 ::',
      ]);
      expect(PromptTagProcessor.splitWorkshopTags('1.5:: makoron117117 ::'), [
        '1.5:: makoron117117 ::',
      ]);
    });
  });
}
