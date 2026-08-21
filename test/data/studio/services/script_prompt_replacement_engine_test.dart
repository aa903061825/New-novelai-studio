import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_prompt_replacement_engine.dart';

void main() {
  group('ScriptPromptReplacementEngine', () {
    const engine = ScriptPromptReplacementEngine();

    test('returns original prompt exactly when there are no rules', () {
      const prompt = '  1girl,girl ,  solo';

      final result = engine.applyRules(
        prompt: prompt,
        frameIndex: 1,
        rules: const [],
      );

      expect(result, prompt);
    });

    test('returns original prompt exactly when rules have no effect', () {
      const prompt = '  round glasses,brown hair ,  solo';

      final result = engine.applyRules(
        prompt: prompt,
        frameIndex: 1,
        rules: [
          _rule(
            'rule-blank-default',
            sourceTerms: [_term('term-glasses', 'round glasses')],
          ),
        ],
      );

      expect(result, prompt);
    });

    test('replaces exact comma token without touching 1girl', () {
      final result = engine.applyRules(
        prompt: '1girl, girl, solo',
        frameIndex: 1,
        rules: [
          _rule(
            'rule-girl',
            sourceTerms: [_term('term-girl', 'girl')],
            targetPrompt: 'lily',
          ),
        ],
      );

      expect(result, '1girl, lily, solo');
    });

    test('directly replaces a delimiter-equivalent source token', () {
      final result = engine.applyRules(
        prompt: 'xuelin（black survival）, solo',
        frameIndex: 2,
        rules: [
          _rule(
            'rule-xuelin',
            sourceTerms: [
              _term(
                'term-xuelin',
                'xuelin (black survival)',
                frameIndexes: [2],
              ),
            ],
            targetPrompt: 'pepe_(arknights)',
          ),
        ],
      );

      expect(result, 'pepe_(arknights), solo');
    });

    test('blank target keeps prompt unchanged and explicit delete removes term',
        () {
      final blankDefault = _rule(
        'rule-blank-default',
        sourceTerms: [_term('term-glasses', 'round glasses')],
      );
      final blankReplace = _rule(
        'rule-blank-replace',
        sourceTerms: [_term('term-glasses', 'round glasses')],
        action: ScriptPromptReplacementAction.replace,
      );
      final delete = _rule(
        'rule-delete',
        sourceTerms: [_term('term-glasses', 'round glasses')],
        action: ScriptPromptReplacementAction.delete,
      );

      expect(
        engine.applyRules(
          prompt: 'round glasses, brown hair',
          frameIndex: 1,
          rules: [blankDefault],
        ),
        'round glasses, brown hair',
      );
      expect(
        engine.applyRules(
          prompt: 'round glasses, brown hair',
          frameIndex: 1,
          rules: [blankReplace],
        ),
        'round glasses, brown hair',
      );
      expect(
        engine.applyRules(
          prompt: 'brown hair, round glasses, solo',
          frameIndex: 1,
          rules: [delete],
        ),
        'brown hair, solo',
      );
    });

    test('all requires every included source term', () {
      final rule = _rule(
        'rule-all',
        sourceTerms: [
          _term('term-dress', 'red dress'),
          _term('term-ribbon', 'ribbon'),
        ],
        matchMode: ScriptPromptReplacementMatchMode.all,
        targetPrompt: 'formal outfit',
      );

      expect(
        engine.applyRules(
          prompt: 'red dress, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'red dress, solo',
      );
      expect(
        engine.applyRules(
          prompt: 'red dress, ribbon, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'formal outfit, solo',
      );
    });

    test('any replaces only present matching source terms', () {
      final rule = _rule(
        'rule-any',
        sourceTerms: [
          _term('term-dress', 'red dress'),
          _term('term-ribbon', 'ribbon'),
        ],
        targetPrompt: 'formal outfit',
      );

      expect(
        engine.applyRules(
          prompt: 'red dress, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'formal outfit, solo',
      );
      expect(
        engine.applyRules(
          prompt: 'red dress, ribbon, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'formal outfit, solo',
      );
    });

    test(
        'anchor uses anchor term and ignores missing non-anchor terms without substring matching',
        () {
      final rule = _rule(
        'rule-anchor',
        sourceTerms: [
          _term('term-hero', 'hero'),
          _term('term-girl', 'girl'),
          _term('term-hair', 'long hair'),
        ],
        matchMode: ScriptPromptReplacementMatchMode.anchor,
        anchorTermId: 'term-hero',
        targetPrompt: 'main character',
      );

      expect(
        engine.applyRules(
          prompt: 'girl, long hair, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'girl, long hair, solo',
      );
      expect(
        engine.applyRules(
          prompt: 'hero, 1girl, long hair, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'main character, 1girl, solo',
      );
    });

    test('explicit anchor id excluded prevents anchor rule from applying', () {
      final result = engine.applyRules(
        prompt: 'hero, girl, solo',
        frameIndex: 1,
        rules: [
          _rule(
            'rule-anchor-excluded',
            sourceTerms: [
              _term('term-hero', 'hero'),
              _term('term-girl', 'girl'),
            ],
            excludedTermIds: ['term-hero'],
            matchMode: ScriptPromptReplacementMatchMode.anchor,
            anchorTermId: 'term-hero',
            targetPrompt: 'main character',
          ),
        ],
      );

      expect(result, 'hero, girl, solo');
    });

    test('explicit anchor id out of frame prevents anchor rule from applying',
        () {
      final result = engine.applyRules(
        prompt: 'hero, girl, solo',
        frameIndex: 1,
        rules: [
          _rule(
            'rule-anchor-frame-filtered',
            sourceTerms: [
              _term('term-hero', 'hero', frameIndexes: [2]),
              _term('term-girl', 'girl', frameIndexes: [1]),
            ],
            matchMode: ScriptPromptReplacementMatchMode.anchor,
            anchorTermId: 'term-hero',
            targetPrompt: 'main character',
          ),
        ],
      );

      expect(result, 'hero, girl, solo');
    });

    test('frame indexes restrict rule application and per-term removal', () {
      final rule = _rule(
        'rule-frame',
        sourceTerms: [
          _term('term-hat', 'hat'),
          _term('term-cape', 'cape', frameIndexes: [2]),
          _term('term-boots', 'boots', frameIndexes: [3]),
        ],
        targetPrompt: 'armor',
      );

      expect(
        engine.applyRules(
          prompt: 'hat, cape, boots, solo',
          frameIndex: 1,
          rules: [rule],
        ),
        'hat, cape, boots, solo',
      );
      expect(
        engine.applyRules(
          prompt: 'hat, cape, boots, solo',
          frameIndex: 2,
          rules: [rule],
        ),
        'armor, boots, solo',
      );
    });

    test('manual phrase overrides target prompt as replacement output', () {
      final result = engine.applyRules(
        prompt: 'cloak, solo',
        frameIndex: 1,
        rules: [
          _rule(
            'rule-manual',
            sourceTerms: [_term('term-cloak', 'cloak')],
            targetPrompt: 'blue dress',
            manualPhrase: 'silver cloak, moon pin',
          ),
        ],
      );

      expect(result, 'silver cloak, moon pin, solo');
    });

    test('blank target with manual phrase keeps prompt unchanged', () {
      const prompt = 'cloak, solo';

      final result = engine.applyRules(
        prompt: prompt,
        frameIndex: 1,
        rules: [
          _rule(
            'rule-hidden-manual',
            sourceTerms: [_term('term-cloak', 'cloak')],
            action: ScriptPromptReplacementAction.replace,
            manualPhrase: 'silver cloak, moon pin',
          ),
        ],
      );

      expect(result, prompt);
    });

    test('excluded term ids prevent terms from participating', () {
      final result = engine.applyRules(
        prompt: 'hat, cape, solo',
        frameIndex: 1,
        rules: [
          _rule(
            'rule-excluded',
            sourceTerms: [
              _term('term-hat', 'hat'),
              _term('term-cape', 'cape'),
            ],
            excludedTermIds: ['term-hat'],
            matchMode: ScriptPromptReplacementMatchMode.all,
            targetPrompt: 'armor',
          ),
        ],
      );

      expect(result, 'hat, armor, solo');
    });

    test('does not duplicate target tags that already remain in the prompt',
        () {
      final result = engine.applyRules(
        prompt: 'girl, lily, solo',
        frameIndex: 1,
        rules: [
          _rule(
            'rule-duplicate',
            sourceTerms: [_term('term-girl', 'girl')],
            targetPrompt: 'lily',
          ),
        ],
      );

      expect(result, 'lily, solo');
    });

    test('applies target weight multiplier as one weighted replacement block',
        () {
      final result = engine.applyRules(
        prompt: 'cat ears, fox ears, solo',
        frameIndex: 1,
        rules: [
          ScriptPromptReplacementRule.fromJson(const {
            'id': 'rule-weighted-block',
            'sourceTerms': [
              {
                'id': 'term-cat-ears',
                'text': 'cat ears',
                'category': 'upperBody',
              },
              {
                'id': 'term-fox-ears',
                'text': 'fox ears',
                'category': 'upperBody',
              },
            ],
            'targetPrompt': 'no cap, no hat',
            'targetWeightMultiplier': 1.2,
          }),
        ],
      );

      expect(result, '1.2:: no cap, no hat ::, solo');
    });

    test('block multiplier multiplies existing target tag weights', () {
      final result = engine.applyRules(
        prompt: 'cat ears, fox ears, solo',
        frameIndex: 1,
        rules: [
          ScriptPromptReplacementRule.fromJson(const {
            'id': 'rule-weighted-block',
            'sourceTerms': [
              {
                'id': 'term-cat-ears',
                'text': 'cat ears',
                'category': 'upperBody',
              },
              {
                'id': 'term-fox-ears',
                'text': 'fox ears',
                'category': 'upperBody',
              },
            ],
            'targetPrompt': '1.5:: no cap ::, no hat',
            'targetWeightMultiplier': 2,
          }),
        ],
      );

      expect(result, '3:: no cap ::, 2:: no hat ::, solo');
    });

    test('empty target multiplier weights only present source tags', () {
      final result = engine.applyRules(
        prompt: '1.5:: cat ears ::, solo',
        frameIndex: 1,
        rules: [
          ScriptPromptReplacementRule.fromJson(const {
            'id': 'rule-source-weight',
            'sourceTerms': [
              {
                'id': 'term-cat-ears',
                'text': 'cat ears',
                'category': 'upperBody',
              },
              {
                'id': 'term-fox-ears',
                'text': 'fox ears',
                'category': 'upperBody',
              },
              {
                'id': 'term-no-cap',
                'text': 'no cap',
                'category': 'upperBody',
              },
              {
                'id': 'term-no-hat',
                'text': 'no hat',
                'category': 'upperBody',
              },
            ],
            'targetWeightMultiplier': 2,
          }),
        ],
      );

      expect(result, '3:: cat ears ::, solo');
    });
  });
}

ScriptPromptReplacementRule _rule(
  String id, {
  List<ScriptPromptReplacementTerm> sourceTerms = const [],
  List<String> excludedTermIds = const [],
  ScriptPromptReplacementAction action = ScriptPromptReplacementAction.none,
  ScriptPromptReplacementMatchMode matchMode =
      ScriptPromptReplacementMatchMode.any,
  String targetPrompt = '',
  String manualPhrase = '',
  String anchorTermId = '',
}) {
  return ScriptPromptReplacementRule(
    id: id,
    sourceTerms: sourceTerms,
    excludedTermIds: excludedTermIds,
    action: action,
    matchMode: matchMode,
    targetPrompt: targetPrompt,
    manualPhrase: manualPhrase,
    anchorTermId: anchorTermId,
  );
}

ScriptPromptReplacementTerm _term(
  String id,
  String text, {
  List<int> frameIndexes = const [],
}) {
  return ScriptPromptReplacementTerm(
    id: id,
    text: text,
    category: PromptTagCategory.character,
    frameIndexes: frameIndexes,
  );
}
