import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_role_replacement_layer_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';

void main() {
  const service = ScriptRoleReplacementLayerService();
  const twoStageAssembly = RoleAssembly(
    sourceRoleId: 'slot-0',
    displayLabel: '女主',
    stages: [
      RoleAssemblyStage(
        id: 'stage-casual',
        label: '便服',
        frameIndexes: [0, 1],
      ),
      RoleAssemblyStage(
        id: 'stage-evening',
        label: '礼服',
        frameIndexes: [2, 3],
      ),
    ],
  );

  test('puts pure identity rules in shared', () {
    final result = service.resolve(
      replacement: _replacement([
        _rule(
          'identity',
          [_term('girl', PromptTagCategory.character)],
        ),
      ]),
      assembly: twoStageAssembly,
    );

    expect(
      result.assignmentForRule('identity')?.kind,
      ScriptRoleReplacementRuleLayerKind.shared,
    );
  });

  test('puts terms uniquely observed in one stage into that stage', () {
    final result = service.resolve(
      replacement: _replacement([
        _rule(
          'dress',
          [
            _term(
              'black dress',
              PromptTagCategory.upperClothing,
              frameIndexes: const [2, 3],
            ),
            _term(
              'lace trim',
              PromptTagCategory.accessory,
              frameIndexes: const [2],
            ),
          ],
        ),
      ]),
      assembly: twoStageAssembly,
    );

    final assignment = result.assignmentForRule('dress');
    expect(assignment?.kind, ScriptRoleReplacementRuleLayerKind.stage);
    expect(assignment?.stageId, 'stage-evening');
  });

  test('puts stable terms that each cover every stage in shared', () {
    final result = service.resolve(
      replacement: _replacement([
        _rule(
          'stable',
          [
            _term(
              'long hair',
              PromptTagCategory.upperBody,
              frameIndexes: const [0, 2],
            ),
            _term(
              'blue eyes',
              PromptTagCategory.upperBody,
              frameIndexes: const [1, 3],
            ),
          ],
        ),
      ]),
      assembly: twoStageAssembly,
    );

    expect(
      result.assignmentForRule('stable')?.kind,
      ScriptRoleReplacementRuleLayerKind.shared,
    );
  });

  test('puts mixed-stage rules and missing evidence in pending', () {
    final result = service.resolve(
      replacement: _replacement([
        _rule(
          'mixed',
          [
            _term(
              'hoodie',
              PromptTagCategory.upperClothing,
              frameIndexes: const [0],
            ),
            _term(
              'dress',
              PromptTagCategory.upperClothing,
              frameIndexes: const [2],
            ),
          ],
        ),
        _rule(
          'missing',
          [_term('shoes', PromptTagCategory.lowerClothing)],
        ),
        _rule(
          'outside',
          [
            _term(
              'hat',
              PromptTagCategory.accessory,
              frameIndexes: const [99],
            ),
          ],
        ),
      ]),
      assembly: twoStageAssembly,
    );

    for (final ruleId in ['mixed', 'missing', 'outside']) {
      expect(
        result.assignmentForRule(ruleId)?.kind,
        ScriptRoleReplacementRuleLayerKind.pending,
      );
    }
  });

  test('puts evidence-free non-identity rules in the only stage', () {
    const oneStageAssembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '女主',
      stages: [
        RoleAssemblyStage(id: 'only', label: '默认服装'),
      ],
    );
    final result = service.resolve(
      replacement: _replacement([
        _rule(
          'dress',
          [_term('dress', PromptTagCategory.upperClothing)],
        ),
      ]),
      assembly: oneStageAssembly,
    );

    expect(result.assignmentForRule('dress')?.stageId, 'only');
  });

  test('structured occurrences take precedence over legacy frame indexes', () {
    final result = service.resolve(
      replacement: _replacement([
        _rule(
          'dress',
          [
            _term(
              'dress',
              PromptTagCategory.upperClothing,
              frameIndexes: const [0],
              sourceOccurrences: const [
                ScriptPromptSourceOccurrence(
                  frameIndex: 2,
                  sourceLocation: 'slot-0 prompt',
                ),
              ],
            ),
          ],
        ),
      ]),
      assembly: twoStageAssembly,
    );

    expect(result.assignmentForRule('dress')?.stageId, 'stage-evening');
  });

  test('manual overrides win and stale stage overrides become pending', () {
    final result = service.resolve(
      replacement: _replacement(
        [
          _rule(
            'dress',
            [
              _term(
                'dress',
                PromptTagCategory.upperClothing,
                frameIndexes: const [2],
              ),
            ],
          ),
          _rule(
            'stale',
            [
              _term(
                'hoodie',
                PromptTagCategory.upperClothing,
                frameIndexes: const [0],
              ),
            ],
          ),
        ],
        overrides: const [
          ScriptRoleReplacementRuleLayerOverride(
            ruleId: 'dress',
            kind: ScriptRoleReplacementRuleLayerKind.shared,
          ),
          ScriptRoleReplacementRuleLayerOverride(
            ruleId: 'stale',
            kind: ScriptRoleReplacementRuleLayerKind.stage,
            stageId: 'removed-stage',
          ),
        ],
      ),
      assembly: twoStageAssembly,
    );

    final dress = result.assignmentForRule('dress');
    expect(dress?.kind, ScriptRoleReplacementRuleLayerKind.shared);
    expect(dress?.isManual, isTrue);

    final stale = result.assignmentForRule('stale');
    expect(stale?.kind, ScriptRoleReplacementRuleLayerKind.pending);
    expect(stale?.isManual, isTrue);
    expect(stale?.hasStaleOverride, isTrue);
  });

  test('excluded source terms do not affect grouping', () {
    final result = service.resolve(
      replacement: _replacement([
        ScriptPromptReplacementRule(
          id: 'dress',
          sourceTerms: [
            _term(
              'dress',
              PromptTagCategory.upperClothing,
              frameIndexes: const [2],
            ),
            _term(
              'hoodie',
              PromptTagCategory.upperClothing,
              frameIndexes: const [0],
            ),
          ],
          excludedTermIds: const ['term-hoodie'],
        ),
      ]),
      assembly: twoStageAssembly,
    );

    expect(result.assignmentForRule('dress')?.stageId, 'stage-evening');
  });
}

ScriptRolePromptReplacement _replacement(
  List<ScriptPromptReplacementRule> rules, {
  List<ScriptRoleReplacementRuleLayerOverride> overrides = const [],
}) {
  return ScriptRolePromptReplacement(
    sourceRoleId: 'slot-0',
    displayLabel: '女主',
    rules: rules,
    layerOverrides: overrides,
  );
}

ScriptPromptReplacementRule _rule(
  String id,
  List<ScriptPromptReplacementTerm> terms,
) {
  return ScriptPromptReplacementRule(id: id, sourceTerms: terms);
}

ScriptPromptReplacementTerm _term(
  String text,
  PromptTagCategory category, {
  List<int> frameIndexes = const [],
  List<ScriptPromptSourceOccurrence> sourceOccurrences = const [],
}) {
  return ScriptPromptReplacementTerm(
    id: 'term-${text.replaceAll(' ', '-')}',
    text: text,
    category: category,
    frameIndexes: frameIndexes,
    sourceOccurrences: sourceOccurrences,
  );
}
