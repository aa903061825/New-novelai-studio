import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/services/filter_rule_document.dart';

void main() {
  String resolveBlock(String text) {
    final classification = PromptTagClassifier.classify(text);
    return filterRuleBlockFromCategory(classification.category);
  }

  test('batch auto add preserves existing words then typed order', () {
    final document = FilterRuleDocument.fromText(
      'lowres',
      resolveBlock: resolveBlock,
    ).addAuto(parseFilterRuleWords('city lights\nnight rain, train platform'));

    expect(
      document.toRuleText(),
      'lowres, city lights, night rain, train platform',
    );
  });

  test('append operations dedupe by normalized tag key', () {
    final document = FilterRuleDocument.fromText(
      'lowres, city lights',
      resolveBlock: resolveBlock,
    ).addAuto(const [' lowres ', 'City Lights', 'night rain']);

    expect(document.toRuleText(), 'lowres, city lights, night rain');
  });

  test('known tag blocks override classifier blocks', () {
    final knownBlocks = buildKnownFilterRuleBlocks([
      const TagEntry(
        id: 'dramatic-light',
        tag: 'dramatic light',
        block: 'camera',
        aliases: ['cinematic light'],
      ),
    ]);

    final document = FilterRuleDocument.fromText(
      'dramatic light, cinematic light',
      resolveBlock: (text) =>
          knownBlocks[filterRuleMatchKey(text)] ?? resolveBlock(text),
    );

    expect(document.tagsByBlock['camera'], [
      'dramatic light',
      'cinematic light',
    ]);
    expect(document.toRuleText(), 'dramatic light, cinematic light');
  });

  test('source order exposes non-empty blocks before empty canonical blocks', () {
    final document = FilterRuleDocument.fromText(
      'street, lowres',
      resolveBlock: resolveBlock,
    );

    expect(document.sourceOrderBlocks.take(3), ['scene', 'style', 'sub_style']);
  });
}
