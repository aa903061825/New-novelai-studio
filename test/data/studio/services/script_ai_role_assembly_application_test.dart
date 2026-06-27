import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_assembly_application.dart';

void main() {
  const application = ScriptAiRoleAssemblyApplication();

  String labelFor(ScriptAiExtractedStage stage, int index) {
    final label = stage.label.trim();
    return label.isEmpty ? 'AI stage ${index + 1}' : label;
  }

  test('creates role assemblies from ready AI extraction', () {
    final result = application.apply(
      mapping: RecastMapping.defaults('script-1'),
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-heroine',
            displayName: 'Heroine',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'char-heroine',
                sourceKind: 'character',
                frameIndexes: [1, 2],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-casual',
                frameIndexes: [1],
                upperClothing: 'white hoodie',
                lowerClothing: 'denim shorts',
                missingFields: ['missing_upper_body'],
              ),
            ],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.changed, isTrue);
    final assembly = result.mapping.roleAssemblies.single;
    expect(assembly.sourceRoleId, 'role-heroine');
    expect(assembly.displayLabel, 'Heroine');
    expect(assembly.sourceAppearances.single.sourceId, 'char-heroine');

    final stage = assembly.stages.single;
    expect(stage.id, 'stage-casual');
    expect(stage.sourceParts.upperClothing, 'white hoodie');
    expect(stage.sourceParts.lowerClothing, 'denim shorts');
    expect(stage.omittedParts, contains(RecastPromptPart.upperBody));
  });

  test('applies AI role and scene terms as replacement groups', () {
    final result = application.apply(
      mapping: RecastMapping.defaults('script-1'),
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'Heroine',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'red-jacket',
                text: 'red jacket',
                category: PromptTagCategory.clothing,
                sourcePhrase: 'wearing a red jacket',
                sourceLocation: 'slot-0 prompt',
                frameIndexes: [1, 2],
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'night',
            text: 'night',
            category: PromptTagCategory.scene,
            sourcePhrase: 'city street at night',
            sourceLocation: 'base prompt',
            frameIndexes: [1],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.changed, isTrue);
    expect(result.mapping.roleAssemblies, isEmpty);

    final roleReplacement = result.mapping.rolePromptReplacements.single;
    expect(roleReplacement.sourceRoleId, 'slot-0');
    expect(roleReplacement.displayLabel, 'Heroine');
    expect(roleReplacement.sourcePreview, 'red jacket');
    expect(roleReplacement.rules.single.id, 'role-slot-0-red-jacket');
    expect(
      roleReplacement.rules.single.sourceTerms.single.text,
      'red jacket',
    );
    expect(
      roleReplacement.rules.single.sourceTerms.single.frameIndexes,
      [1, 2],
    );

    final sceneReplacement = result.mapping.scenePromptReplacements.single;
    expect(sceneReplacement.rules.single.id, 'scene-night');
    expect(
      sceneReplacement.rules.single.sourceTerms.single.text,
      'night',
    );
    expect(
      sceneReplacement.rules.single.sourceTerms.single.sourceLocation,
      'base prompt',
    );
  });

  test('preserves user edits when refreshing replacement groups', () {
    const mapping = RecastMapping(
      id: 'mapping-script-1',
      scriptId: 'script-1',
      rolePromptReplacements: [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Old heroine',
          sourcePreview: 'old jacket evidence',
          targetCharacterId: 'target-character',
          targetIdentityPrompt: 'target identity prompt',
          rules: [
            ScriptPromptReplacementRule(
              id: 'role-slot-0-red-jacket',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'red-jacket',
                  text: 'old red jacket',
                  category: PromptTagCategory.clothing,
                  sourcePhrase: 'old evidence',
                  sourceLocation: 'old prompt',
                  frameIndexes: [1],
                ),
              ],
              excludedTermIds: ['excluded-term'],
              action: ScriptPromptReplacementAction.delete,
              matchMode: ScriptPromptReplacementMatchMode.anchor,
              targetPrompt: 'white dress',
              manualPhrase: 'manual jacket phrase',
              anchorTermId: 'red-jacket',
            ),
          ],
        ),
      ],
      scenePromptReplacements: [
        ScriptScenePromptReplacement(
          id: 'scene-ai',
          label: 'Old scene',
          rules: [
            ScriptPromptReplacementRule(
              id: 'scene-night',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'night',
                  text: 'old night',
                  category: PromptTagCategory.scene,
                  sourcePhrase: 'old scene evidence',
                  sourceLocation: 'old base prompt',
                  frameIndexes: [1],
                ),
              ],
              excludedTermIds: ['scene-exclusion'],
              action: ScriptPromptReplacementAction.delete,
              matchMode: ScriptPromptReplacementMatchMode.anchor,
              targetPrompt: 'sunny morning',
              manualPhrase: 'manual scene phrase',
              anchorTermId: 'night',
            ),
          ],
        ),
      ],
    );

    final result = application.apply(
      mapping: mapping,
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'Heroine',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'red-jacket',
                text: 'crimson jacket',
                category: PromptTagCategory.clothing,
                sourcePhrase: 'new jacket evidence',
                sourceLocation: 'slot-0 prompt',
                frameIndexes: [2, 3],
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'night',
            text: 'moonlit night',
            category: PromptTagCategory.scene,
            sourcePhrase: 'new scene evidence',
            sourceLocation: 'base prompt',
            frameIndexes: [2, 3],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.changed, isTrue);

    final roleReplacement = result.mapping.rolePromptReplacements.single;
    expect(roleReplacement.targetCharacterId, 'target-character');
    expect(roleReplacement.targetIdentityPrompt, 'target identity prompt');
    final roleRule = roleReplacement.rules.single;
    expect(roleRule.sourceTerms.single.text, 'crimson jacket');
    expect(roleRule.sourceTerms.single.sourcePhrase, 'new jacket evidence');
    expect(roleRule.sourceTerms.single.frameIndexes, [2, 3]);
    expect(roleRule.targetPrompt, 'white dress');
    expect(roleRule.manualPhrase, 'manual jacket phrase');
    expect(roleRule.action, ScriptPromptReplacementAction.delete);
    expect(roleRule.matchMode, ScriptPromptReplacementMatchMode.anchor);
    expect(roleRule.excludedTermIds, ['excluded-term']);
    expect(roleRule.anchorTermId, 'red-jacket');

    final sceneRule =
        result.mapping.scenePromptReplacements.single.rules.single;
    expect(sceneRule.sourceTerms.single.text, 'moonlit night');
    expect(sceneRule.sourceTerms.single.sourceLocation, 'base prompt');
    expect(sceneRule.sourceTerms.single.frameIndexes, [2, 3]);
    expect(sceneRule.targetPrompt, 'sunny morning');
    expect(sceneRule.manualPhrase, 'manual scene phrase');
    expect(sceneRule.action, ScriptPromptReplacementAction.delete);
    expect(sceneRule.matchMode, ScriptPromptReplacementMatchMode.anchor);
    expect(sceneRule.excludedTermIds, ['scene-exclusion']);
    expect(sceneRule.anchorTermId, 'night');
  });

  test('reuses confirmed replacement rules by source term when ids changed',
      () {
    const mapping = RecastMapping(
      id: 'mapping-script-1',
      scriptId: 'script-1',
      rolePromptReplacements: [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Old heroine',
          targetCharacterId: 'target-character',
          rules: [
            ScriptPromptReplacementRule(
              id: 'legacy-double-bun-rule',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'legacy-double-bun',
                  text: 'double bun',
                  category: PromptTagCategory.upperBody,
                  sourcePhrase: 'old double bun evidence',
                ),
              ],
              targetPrompt: 'single braid',
            ),
          ],
        ),
      ],
      scenePromptReplacements: [
        ScriptScenePromptReplacement(
          id: 'scene-ai',
          label: 'Scene',
          rules: [
            ScriptPromptReplacementRule(
              id: 'legacy-bedroom-rule',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'legacy-bedroom',
                  text: 'bedroom',
                  category: PromptTagCategory.scene,
                ),
              ],
              targetPrompt: 'classroom',
            ),
          ],
        ),
      ],
    );

    final result = application.apply(
      mapping: mapping,
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'Heroine',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'term-double-bun',
                text: 'double bun',
                category: PromptTagCategory.upperBody,
                sourcePhrase: 'new double bun evidence',
                frameIndexes: [2],
              ),
              ScriptAiExtractedPromptTerm(
                id: 'term-wings',
                text: 'wings',
                category: PromptTagCategory.upperBody,
                sourcePhrase: 'wings evidence',
                frameIndexes: [2],
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'scene-bedroom',
            text: 'bedroom',
            category: PromptTagCategory.scene,
            sourcePhrase: 'new bedroom evidence',
            frameIndexes: [2],
          ),
          ScriptAiExtractedPromptTerm(
            id: 'scene-sunset',
            text: 'sunset',
            category: PromptTagCategory.scene,
            sourcePhrase: 'sunset evidence',
            frameIndexes: [3],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    final roleReplacement = result.mapping.rolePromptReplacements.single;
    expect(roleReplacement.targetCharacterId, 'target-character');
    expect(roleReplacement.rules, hasLength(2));
    expect(roleReplacement.rules.first.id, 'legacy-double-bun-rule');
    expect(roleReplacement.rules.first.targetPrompt, 'single braid');
    expect(
        roleReplacement.rules.first.sourceTerms.single.id, 'term-double-bun');
    expect(roleReplacement.rules.first.sourceTerms.single.sourcePhrase,
        'new double bun evidence');
    expect(roleReplacement.rules.last.sourceTerms.single.text, 'wings');

    final sceneRules = result.mapping.scenePromptReplacements.single.rules;
    expect(sceneRules, hasLength(2));
    expect(sceneRules.first.id, 'legacy-bedroom-rule');
    expect(sceneRules.first.targetPrompt, 'classroom');
    expect(sceneRules.first.sourceTerms.single.id, 'scene-bedroom');
    expect(
      result.mapping.rolePromptReplacements.single.rules
          .expand((rule) => rule.sourceTerms)
          .map((term) => term.text),
      isNot(contains('bedroom')),
    );
  });

  test(
    'reuses confirmed replacement rule when AI refines legacy clothing category',
    () {
      final result = application.apply(
        mapping: const RecastMapping(
          id: 'mapping-a',
          scriptId: 'script-a',
          rolePromptReplacements: [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'legacy-state-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-no-panties',
                      text: 'no panties',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  targetPrompt: 'black panties',
                ),
              ],
            ),
          ],
        ),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'term-no-panties',
                  text: 'no panties',
                  category: PromptTagCategory.clothingState,
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rule = result.mapping.rolePromptReplacements.single.rules.single;
      expect(rule.id, 'legacy-state-rule');
      expect(rule.targetPrompt, 'black panties');
      expect(rule.sourceTerms.single.id, 'term-no-panties');
      expect(
        rule.sourceTerms.single.category,
        PromptTagCategory.clothingState,
      );
    },
  );

  test(
    'does not reuse legacy rule when non-migration categories only share text',
    () {
      final result = application.apply(
        mapping: const RecastMapping(
          id: 'mapping-a',
          scriptId: 'script-a',
          rolePromptReplacements: [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'legacy-standing-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-standing',
                      text: 'standing',
                      category: PromptTagCategory.character,
                    ),
                  ],
                  targetPrompt: 'hero pose',
                ),
              ],
            ),
          ],
        ),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'term-standing',
                  text: 'standing',
                  category: PromptTagCategory.action,
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rules = result.mapping.rolePromptReplacements.single.rules;
      expect(rules, hasLength(2));
      expect(rules.first.id, isNot('legacy-standing-rule'));
      expect(rules.first.sourceTerms.single.id, 'term-standing');
      expect(rules.first.targetPrompt, isEmpty);
      expect(rules.last.id, 'legacy-standing-rule');
      expect(rules.last.targetPrompt, 'hero pose');
    },
  );

  test(
    'prefers refined clothing-compatible prompt term when polluted legacy duplicate comes first',
    () {
      final result = application.apply(
        mapping: const RecastMapping(
          id: 'mapping-a',
          scriptId: 'script-a',
          rolePromptReplacements: [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'legacy-state-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-strap-slip',
                      text: 'strap slip',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  targetPrompt: 'secure straps',
                ),
              ],
            ),
          ],
        ),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'legacy-strap-slip',
                  text: 'strap slip',
                  category: PromptTagCategory.clothing,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-strap-slip',
                  text: 'strap slip',
                  category: PromptTagCategory.clothingState,
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rules = result.mapping.rolePromptReplacements.single.rules;
      expect(rules, hasLength(1));
      final rule = rules.single;
      expect(rule.id, 'legacy-state-rule');
      expect(rule.targetPrompt, 'secure straps');
      expect(rule.sourceTerms.single.id, 'term-strap-slip');
      expect(
        rule.sourceTerms.single.category,
        PromptTagCategory.clothingState,
      );
    },
  );

  test(
    'keeps refined accessory and clothing state prompt terms distinct when text matches',
    () {
      final result = application.apply(
        mapping: RecastMapping.defaults('script-a'),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'term-accessory-collar',
                  text: 'collar',
                  category: PromptTagCategory.accessory,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-state-collar',
                  text: 'collar',
                  category: PromptTagCategory.clothingState,
                  frameIndexes: [2],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rules = result.mapping.rolePromptReplacements.single.rules;
      expect(rules, hasLength(2));
      expect(
        rules.map((rule) => rule.sourceTerms.single.category),
        [
          PromptTagCategory.accessory,
          PromptTagCategory.clothingState,
        ],
      );
      expect(
        rules.map((rule) => rule.sourceTerms.single.id),
        ['term-accessory-collar', 'term-state-collar'],
      );
    },
  );

  test(
    'does not merge refined clothing-compatible rules through legacy alias',
    () {
      final result = application.apply(
        mapping: const RecastMapping(
          id: 'mapping-a',
          scriptId: 'script-a',
          rolePromptReplacements: [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'existing-accessory-collar-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'existing-accessory-collar',
                      text: 'collar',
                      category: PromptTagCategory.accessory,
                    ),
                  ],
                  targetPrompt: 'silver collar',
                ),
              ],
            ),
          ],
        ),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'term-accessory-collar',
                  text: 'collar',
                  category: PromptTagCategory.accessory,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-state-collar',
                  text: 'collar',
                  category: PromptTagCategory.clothingState,
                  frameIndexes: [2],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rules = result.mapping.rolePromptReplacements.single.rules;
      expect(rules, hasLength(2));
      expect(rules.first.id, 'existing-accessory-collar-rule');
      expect(rules.first.targetPrompt, 'silver collar');
      expect(rules.first.sourceTerms.single.id, 'term-accessory-collar');
      expect(
        rules.map((rule) => rule.sourceTerms.single.category),
        [
          PromptTagCategory.accessory,
          PromptTagCategory.clothingState,
        ],
      );
      expect(
        rules.map((rule) => rule.sourceTerms.single.id),
        ['term-accessory-collar', 'term-state-collar'],
      );
    },
  );

  test(
    'does not reuse refined clothing-compatible rule for different refined category',
    () {
      final result = application.apply(
        mapping: const RecastMapping(
          id: 'mapping-a',
          scriptId: 'script-a',
          rolePromptReplacements: [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'existing-accessory-collar-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'existing-accessory-collar',
                      text: 'collar',
                      category: PromptTagCategory.accessory,
                    ),
                  ],
                  targetPrompt: 'silver collar',
                ),
              ],
            ),
          ],
        ),
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'term-state-collar',
                  text: 'collar',
                  category: PromptTagCategory.clothingState,
                  frameIndexes: [2],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rules = result.mapping.rolePromptReplacements.single.rules;
      expect(rules, hasLength(2));
      expect(rules.first.sourceTerms.single.id, 'term-state-collar');
      expect(rules.last.id, 'existing-accessory-collar-rule');
      expect(rules.last.targetPrompt, 'silver collar');
      expect(
        rules.map((rule) => rule.sourceTerms.single.category),
        [
          PromptTagCategory.clothingState,
          PromptTagCategory.accessory,
        ],
      );
    },
  );

  test('preserves user-merged replacement source terms when refreshing from AI',
      () {
    const mapping = RecastMapping(
      id: 'mapping-script-1',
      scriptId: 'script-1',
      rolePromptReplacements: [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Heroine',
          rules: [
            ScriptPromptReplacementRule(
              id: 'role-slot-0-red-jacket',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'red-jacket',
                  text: 'old red jacket',
                  category: PromptTagCategory.clothing,
                  sourcePhrase: 'old red evidence',
                  frameIndexes: [1],
                ),
                ScriptPromptReplacementTerm(
                  id: 'blue-skirt',
                  text: 'old blue skirt',
                  category: PromptTagCategory.clothing,
                  sourcePhrase: 'old skirt evidence',
                  frameIndexes: [1],
                ),
              ],
              targetPrompt: 'white dress',
            ),
          ],
        ),
      ],
      scenePromptReplacements: [
        ScriptScenePromptReplacement(
          id: 'scene-ai',
          label: 'Scene',
          rules: [
            ScriptPromptReplacementRule(
              id: 'scene-night',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'night',
                  text: 'old night',
                  category: PromptTagCategory.scene,
                ),
                ScriptPromptReplacementTerm(
                  id: 'rain',
                  text: 'old rain',
                  category: PromptTagCategory.scene,
                ),
              ],
              targetPrompt: 'sunny morning',
            ),
          ],
        ),
      ],
    );

    final result = application.apply(
      mapping: mapping,
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'Heroine',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'red-jacket',
                text: 'red jacket',
                category: PromptTagCategory.clothing,
                sourcePhrase: 'new red evidence',
                frameIndexes: [2],
              ),
              ScriptAiExtractedPromptTerm(
                id: 'blue-skirt',
                text: 'blue skirt',
                category: PromptTagCategory.clothing,
                sourcePhrase: 'new skirt evidence',
                frameIndexes: [3],
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'night',
            text: 'night',
            category: PromptTagCategory.scene,
            frameIndexes: [2],
          ),
          ScriptAiExtractedPromptTerm(
            id: 'rain',
            text: 'rain',
            category: PromptTagCategory.scene,
            frameIndexes: [3],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    final roleRules = result.mapping.rolePromptReplacements.single.rules;
    expect(roleRules, hasLength(1));
    expect(
      roleRules.single.sourceTerms.map((term) => term.text),
      ['red jacket', 'blue skirt'],
    );
    expect(
      roleRules.single.sourceTerms.map((term) => term.frameIndexes),
      [
        [2],
        [3],
      ],
    );
    expect(roleRules.single.targetPrompt, 'white dress');

    final sceneRules = result.mapping.scenePromptReplacements.single.rules;
    expect(sceneRules, hasLength(1));
    expect(
      sceneRules.single.sourceTerms.map((term) => term.text),
      ['night', 'rain'],
    );
    expect(sceneRules.single.targetPrompt, 'sunny morning');
  });

  test(
    'refreshes scene-ai even when a user-authored scene group appears first',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
        scenePromptReplacements: [
          ScriptScenePromptReplacement(
            id: 'custom-scene',
            label: 'Custom scene edits',
            rules: [
              ScriptPromptReplacementRule(
                id: 'scene-fog',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'fog',
                    text: 'fog',
                    category: PromptTagCategory.scene,
                  ),
                ],
                manualPhrase: 'soft haze',
              ),
            ],
          ),
          ScriptScenePromptReplacement(
            id: 'scene-ai',
            label: 'AI scene terms',
            rules: [
              ScriptPromptReplacementRule(
                id: 'scene-night',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'night',
                    text: 'old night evidence',
                    category: PromptTagCategory.scene,
                    sourcePhrase: 'old phrase',
                    sourceLocation: 'old base prompt',
                    frameIndexes: [1],
                  ),
                ],
                excludedTermIds: ['old-exclusion'],
                action: ScriptPromptReplacementAction.delete,
                matchMode: ScriptPromptReplacementMatchMode.anchor,
                targetPrompt: 'sunlit plaza',
                manualPhrase: 'manual night edit',
                anchorTermId: 'night',
              ),
            ],
          ),
        ],
      );

      final result = application.apply(
        mapping: mapping,
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          sceneTerms: [
            ScriptAiExtractedPromptTerm(
              id: 'night',
              text: 'moonlit night',
              category: PromptTagCategory.scene,
              sourcePhrase: 'moonlit street at night',
              sourceLocation: 'base prompt',
              frameIndexes: [2, 3],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      expect(
        result.mapping.scenePromptReplacements.map((group) => group.id),
        ['custom-scene', 'scene-ai'],
      );
      final customGroup = result.mapping.scenePromptReplacements.first;
      expect(customGroup.rules.single.id, 'scene-fog');
      expect(customGroup.rules.single.manualPhrase, 'soft haze');

      final aiGroup = result.mapping.scenePromptReplacements.last;
      expect(aiGroup.label, 'AI scene terms');
      final aiRule = aiGroup.rules.single;
      expect(aiRule.id, 'scene-night');
      expect(aiRule.sourceTerms.single.text, 'moonlit night');
      expect(aiRule.sourceTerms.single.sourcePhrase, 'moonlit street at night');
      expect(aiRule.sourceTerms.single.sourceLocation, 'base prompt');
      expect(aiRule.sourceTerms.single.frameIndexes, [2, 3]);
      expect(aiRule.targetPrompt, 'sunlit plaza');
      expect(aiRule.manualPhrase, 'manual night edit');
      expect(aiRule.action, ScriptPromptReplacementAction.delete);
      expect(aiRule.matchMode, ScriptPromptReplacementMatchMode.anchor);
      expect(aiRule.excludedTermIds, ['old-exclusion']);
      expect(aiRule.anchorTermId, 'night');
    },
  );

  test('preserves mapping exactly when extraction is not ready', () {
    const mapping = RecastMapping(
      id: 'mapping-script-1',
      scriptId: 'script-1',
      rolePromptReplacements: [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Heroine',
          targetCharacterId: 'target-character',
          rules: [
            ScriptPromptReplacementRule(
              id: 'role-slot-0-red-jacket',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'red-jacket',
                  text: 'red jacket',
                  category: PromptTagCategory.clothing,
                ),
              ],
              targetPrompt: 'white dress',
            ),
          ],
        ),
      ],
      scenePromptReplacements: [
        ScriptScenePromptReplacement(
          id: 'scene-ai',
          label: 'Scene',
          rules: [
            ScriptPromptReplacementRule(
              id: 'scene-night',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'night',
                  text: 'night',
                  category: PromptTagCategory.scene,
                ),
              ],
              manualPhrase: 'manual scene',
            ),
          ],
        ),
      ],
    );

    final result = application.apply(
      mapping: mapping,
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.needsMoreEvidence,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'blue-dress',
                text: 'blue dress',
                category: PromptTagCategory.clothing,
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'day',
            text: 'day',
            category: PromptTagCategory.scene,
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.changed, isFalse);
    expect(identical(result.mapping, mapping), isTrue);
  });

  test(
    'drops stale automatic replacement rules but keeps user-authored rules if source disappears',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
        rolePromptReplacements: [
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-0',
            displayLabel: 'Heroine',
            rules: [
              ScriptPromptReplacementRule(
                id: 'role-slot-0-red-jacket',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'red-jacket',
                    text: 'red jacket',
                    category: PromptTagCategory.clothing,
                  ),
                ],
              ),
              ScriptPromptReplacementRule(
                id: 'role-slot-0-old-hat',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'old-hat',
                    text: 'old hat',
                    category: PromptTagCategory.clothing,
                  ),
                ],
              ),
              ScriptPromptReplacementRule(
                id: 'role-slot-0-scarf',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'scarf',
                    text: 'scarf',
                    category: PromptTagCategory.clothing,
                  ),
                ],
                targetPrompt: 'blue ribbon',
              ),
            ],
          ),
        ],
        scenePromptReplacements: [
          ScriptScenePromptReplacement(
            id: 'scene-ai',
            label: 'Scene',
            rules: [
              ScriptPromptReplacementRule(
                id: 'scene-night',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'night',
                    text: 'night',
                    category: PromptTagCategory.scene,
                  ),
                ],
              ),
              ScriptPromptReplacementRule(
                id: 'scene-old-rain',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'old-rain',
                    text: 'old rain',
                    category: PromptTagCategory.scene,
                  ),
                ],
              ),
              ScriptPromptReplacementRule(
                id: 'scene-fog',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'fog',
                    text: 'fog',
                    category: PromptTagCategory.scene,
                  ),
                ],
                manualPhrase: 'soft sunrise haze',
              ),
            ],
          ),
        ],
      );

      final result = application.apply(
        mapping: mapping,
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Heroine',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'red-jacket',
                  text: 'bright red jacket',
                  category: PromptTagCategory.clothing,
                ),
              ],
            ),
          ],
          sceneTerms: [
            ScriptAiExtractedPromptTerm(
              id: 'night',
              text: 'deep night',
              category: PromptTagCategory.scene,
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      expect(result.changed, isTrue);
      expect(
        result.mapping.rolePromptReplacements.single.rules
            .map((rule) => rule.id),
        ['role-slot-0-red-jacket', 'role-slot-0-scarf'],
      );
      expect(
        result.mapping.rolePromptReplacements.single.rules.first.sourceTerms
            .single.text,
        'bright red jacket',
      );
      expect(
        result.mapping.rolePromptReplacements.single.rules.last.targetPrompt,
        'blue ribbon',
      );
      expect(
        result.mapping.scenePromptReplacements.single.rules
            .map((rule) => rule.id),
        ['scene-night', 'scene-fog'],
      );
      expect(
        result.mapping.scenePromptReplacements.single.rules.first.sourceTerms
            .single.text,
        'deep night',
      );
      expect(
        result.mapping.scenePromptReplacements.single.rules.last.manualPhrase,
        'soft sunrise haze',
      );
    },
  );

  test(
    'keeps AI stages whose ids look like local default stage ids',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
        roleAssemblies: [
          RoleAssembly(
            sourceRoleId: 'role-hoshino-blue-archive',
            displayLabel: 'hoshino (blue archive)',
            sourceName: 'hoshino (blue archive)',
            sourceAppearances: [
              RoleAssemblySourceAppearance(
                sourceId: 'slot-0',
                sourceKind: 'slot',
                frameIndexes: [1],
              ),
            ],
          ),
        ],
      );

      final result = application.apply(
        mapping: mapping,
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-hoshino-blue-archive',
              displayName: 'hoshino (blue archive)',
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'role-hoshino-blue-archive-stage-1',
                  label: 'School uniform',
                  frameIndexes: [1],
                  identity: 'hoshino (blue archive)',
                  upperClothing: 'white shirt',
                  lowerClothing: 'black skirt',
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final stage = result.mapping.roleAssemblies.single.stages.single;
      expect(stage.id, 'role-hoshino-blue-archive-stage-1');
      expect(stage.sourceParts.identity, 'hoshino (blue archive)');
      expect(stage.sourceParts.upperClothing, 'white shirt');
      expect(stage.sourceParts.lowerClothing, 'black skirt');
    },
  );

  test('keeps user-authored targets and manual fields when refreshing stage',
      () {
    const existingStage = RoleAssemblyStage(
      id: 'stage-casual',
      label: 'Old stage',
      targetCharacterId: 'target-character',
      manualParts: RecastPromptParts(upperClothing: 'manual jacket'),
    );
    const mapping = RecastMapping(
      id: 'mapping-script-1',
      scriptId: 'script-1',
      roleAssemblies: [
        RoleAssembly(
          sourceRoleId: 'role-heroine',
          displayLabel: 'Heroine',
          stages: [existingStage],
        ),
      ],
    );

    final result = application.apply(
      mapping: mapping,
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-heroine',
            displayName: 'Heroine',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-casual',
                label: 'Casual',
                frameIndexes: [2],
                upperClothing: 'white hoodie',
              ),
            ],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.changed, isTrue);
    final stage = result.mapping.roleAssemblies.single.stages.single;
    expect(stage.label, 'Casual');
    expect(stage.frameIndexes, [2]);
    expect(stage.sourceParts.upperClothing, 'white hoodie');
    expect(stage.targetCharacterId, 'target-character');
    expect(stage.manualParts.upperClothing, 'manual jacket');
  });

  test(
    'drops stale user-authored stages that are absent from refreshed AI stages',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
        roleAssemblies: [
          RoleAssembly(
            sourceRoleId: 'role-heroine',
            displayLabel: 'Heroine',
            stages: [
              RoleAssemblyStage(
                id: 'stage-casual',
                label: 'Old casual',
                targetCharacterId: 'target-character',
                manualParts: RecastPromptParts(upperClothing: 'manual jacket'),
              ),
              RoleAssemblyStage(
                id: 'stale-sweater',
                label: 'Grey sweater',
                targetCharacterId: 'stale-target',
                manualParts: RecastPromptParts(upperClothing: 'stale sweater'),
              ),
            ],
          ),
        ],
      );

      final result = application.apply(
        mapping: mapping,
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-heroine',
              displayName: 'Heroine',
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'stage-casual',
                  label: 'Casual',
                  frameIndexes: [2],
                  upperClothing: 'white hoodie',
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final stages = result.mapping.roleAssemblies.single.stages;
      expect(stages, hasLength(1));
      expect(stages.single.id, 'stage-casual');
      expect(stages.single.targetCharacterId, 'target-character');
      expect(stages.single.manualParts.upperClothing, 'manual jacket');
      expect(stages.single.sourceParts.upperClothing, 'white hoodie');
    },
  );

  test('drops local slot assemblies covered by cross-slot AI roles', () {
    const mapping = RecastMapping(
      id: 'mapping-script-1',
      scriptId: 'script-1',
      roleAssemblies: [
        RoleAssembly(
          sourceRoleId: 'slot-0',
          displayLabel: 'Slot 1',
          stages: [
            RoleAssemblyStage(
              id: 'slot-0-stage-1',
              label: 'Slot stage',
              targetCharacterId: 'target-character',
              manualParts: RecastPromptParts(upperClothing: 'manual jacket'),
            ),
          ],
        ),
      ],
    );

    final result = application.apply(
      mapping: mapping,
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'ai-role-0',
            sourceKind: 'cross_slot',
            displayName: 'Heroine',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'slot-0',
                sourceKind: 'slot',
                frameIndexes: [1],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-casual',
                label: 'Casual',
                frameIndexes: [1],
                upperClothing: 'white hoodie',
              ),
            ],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.mapping.roleAssemblies, hasLength(1));
    expect(result.mapping.roleAssemblies.single.sourceRoleId, 'ai-role-0');
  });
}
