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
    expect(roleReplacement.rules.single.id, 'role-slot-0-clothing-red-jacket');
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

  test('passes source occurrence pairs through AI replacement application', () {
    final result = application.apply(
      mapping: RecastMapping.defaults('script-1'),
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'red-jacket',
                text: 'red jacket',
                category: PromptTagCategory.clothing,
                sourceOccurrences: [
                  ScriptPromptSourceOccurrence(
                    frameIndex: 1,
                    sourceLocation: 'slot-0 prompt',
                  ),
                  ScriptPromptSourceOccurrence(
                    frameIndex: 2,
                    sourceLocation: 'slot-1 prompt',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    final term = result
        .mapping.rolePromptReplacements.single.rules.single.sourceTerms.single;
    expect(term.sourceOccurrences, const [
      ScriptPromptSourceOccurrence(
        frameIndex: 1,
        sourceLocation: 'slot-0 prompt',
      ),
      ScriptPromptSourceOccurrence(
        frameIndex: 2,
        sourceLocation: 'slot-1 prompt',
      ),
    ]);
    expect(term.toJson()['sourceOccurrences'], [
      {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
      {'frameIndex': 2, 'sourceLocation': 'slot-1 prompt'},
    ]);
  });

  test('replacement equality notices changed source occurrence pairs', () {
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
                  sourceOccurrences: [
                    ScriptPromptSourceOccurrence(
                      frameIndex: 1,
                      sourceLocation: 'slot-0 prompt',
                    ),
                  ],
                ),
              ],
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
                sourceOccurrences: [
                  ScriptPromptSourceOccurrence(
                    frameIndex: 2,
                    sourceLocation: 'slot-1 prompt',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      stageLabelFor: labelFor,
    );

    expect(result.changed, isTrue);
    expect(
      result.mapping.rolePromptReplacements.single.rules.single.sourceTerms
          .single.sourceOccurrences,
      const [
        ScriptPromptSourceOccurrence(
          frameIndex: 2,
          sourceLocation: 'slot-1 prompt',
        ),
      ],
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
    'prefers refined upper and lower clothing prompt terms over polluted legacy duplicates',
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
                  id: 'legacy-shirt-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-white-shirt',
                      text: 'white shirt',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  action: ScriptPromptReplacementAction.replace,
                  matchMode: ScriptPromptReplacementMatchMode.anchor,
                  targetPrompt: 'black blouse',
                  anchorTermId: 'legacy-white-shirt',
                ),
                ScriptPromptReplacementRule(
                  id: 'legacy-skirt-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-black-skirt',
                      text: 'black skirt',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  action: ScriptPromptReplacementAction.delete,
                  matchMode: ScriptPromptReplacementMatchMode.all,
                  targetPrompt: 'pleated skirt',
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
                  id: 'legacy-white-shirt',
                  text: 'white shirt',
                  category: PromptTagCategory.clothing,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-white-shirt',
                  text: 'white shirt',
                  category: PromptTagCategory.upperClothing,
                  frameIndexes: [2],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'legacy-black-skirt',
                  text: 'black skirt',
                  category: PromptTagCategory.clothing,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-black-skirt',
                  text: 'black skirt',
                  category: PromptTagCategory.lowerClothing,
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
      expect(rules.map((rule) => rule.id), [
        'legacy-shirt-rule',
        'legacy-skirt-rule',
      ]);
      expect(rules.first.targetPrompt, 'black blouse');
      expect(rules.first.action, ScriptPromptReplacementAction.replace);
      expect(rules.first.matchMode, ScriptPromptReplacementMatchMode.anchor);
      expect(rules.first.anchorTermId, 'term-white-shirt');
      expect(rules.first.sourceTerms.single.id, 'term-white-shirt');
      expect(
        rules.first.sourceTerms.single.category,
        PromptTagCategory.upperClothing,
      );
      expect(rules.last.targetPrompt, 'pleated skirt');
      expect(rules.last.action, ScriptPromptReplacementAction.delete);
      expect(rules.last.matchMode, ScriptPromptReplacementMatchMode.all);
      expect(rules.last.sourceTerms.single.id, 'term-black-skirt');
      expect(
        rules.last.sourceTerms.single.category,
        PromptTagCategory.lowerClothing,
      );
    },
  );

  test(
    'rewrites replacement anchors and exclusions when source term ids refresh',
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
                  id: 'legacy-shirt-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-white-shirt',
                      text: 'white shirt',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  excludedTermIds: ['legacy-black-skirt', 'unmapped-term'],
                  action: ScriptPromptReplacementAction.replace,
                  matchMode: ScriptPromptReplacementMatchMode.anchor,
                  targetPrompt: 'black blouse',
                  anchorTermId: 'legacy-white-shirt',
                ),
                ScriptPromptReplacementRule(
                  id: 'legacy-skirt-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-black-skirt',
                      text: 'black skirt',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  action: ScriptPromptReplacementAction.delete,
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
                  id: 'term-white-shirt',
                  text: 'white shirt',
                  category: PromptTagCategory.upperClothing,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-black-skirt',
                  text: 'black skirt',
                  category: PromptTagCategory.lowerClothing,
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      final rules = result.mapping.rolePromptReplacements.single.rules;
      final shirtRule = rules.singleWhere(
        (rule) => rule.id == 'legacy-shirt-rule',
      );
      expect(shirtRule.sourceTerms.single.id, 'term-white-shirt');
      expect(shirtRule.anchorTermId, 'term-white-shirt');
      expect(shirtRule.excludedTermIds, ['term-black-skirt', 'unmapped-term']);
      expect(shirtRule.action, ScriptPromptReplacementAction.replace);
      expect(shirtRule.matchMode, ScriptPromptReplacementMatchMode.anchor);
      expect(shirtRule.targetPrompt, 'black blouse');
    },
  );

  test(
    'keeps refined upper and lower clothing prompt terms distinct when text matches',
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
                  id: 'term-upper-wrap',
                  text: 'wrap',
                  category: PromptTagCategory.upperClothing,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-lower-wrap',
                  text: 'wrap',
                  category: PromptTagCategory.lowerClothing,
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
          PromptTagCategory.upperClothing,
          PromptTagCategory.lowerClothing,
        ],
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
    'keeps refined accessory and clothing state prompt terms distinct when id and text match',
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
                  id: 'term-collar',
                  text: 'collar',
                  category: PromptTagCategory.accessory,
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-collar',
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
        rules.map((rule) => rule.id),
        [
          'role-slot-0-accessory-term-collar',
          'role-slot-0-clothingstate-term-collar',
        ],
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
    'does not reuse existing refined rule when incoming term has same id and text but different refined category',
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
                      id: 'term-collar',
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
                  id: 'term-collar',
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
      expect(rules.first.id, 'role-slot-0-clothingstate-term-collar');
      expect(rules.first.sourceTerms.single.category,
          PromptTagCategory.clothingState);
      expect(rules.last.id, 'existing-accessory-collar-rule');
      expect(rules.last.targetPrompt, 'silver collar');
      expect(
          rules.last.sourceTerms.single.category, PromptTagCategory.accessory);
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
    'keeps stale role replacement rule that only changes target weight',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
        rolePromptReplacements: [
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-0',
            displayLabel: 'Heroine',
            sourcePreview: 'red jacket',
            rules: [
              ScriptPromptReplacementRule(
                id: 'role-slot-0-clothing-red-jacket',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'red-jacket',
                    text: 'red jacket',
                    category: PromptTagCategory.clothing,
                  ),
                ],
              ),
              ScriptPromptReplacementRule(
                id: 'role-slot-0-clothing-old-hat',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'old-hat',
                    text: 'old hat',
                    category: PromptTagCategory.clothing,
                  ),
                ],
                targetWeightMultiplier: 1.35,
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
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      expect(result.changed, isFalse);
      expect(identical(result.mapping, mapping), isTrue);
      final rules = result.mapping.rolePromptReplacements.single.rules;
      expect(rules.map((rule) => rule.id), [
        'role-slot-0-clothing-red-jacket',
        'role-slot-0-clothing-old-hat',
      ]);
      expect(rules.last.targetPrompt, isEmpty);
      expect(rules.last.targetWeightMultiplier, 1.35);
      expect(rules.last.effectiveAction, ScriptPromptReplacementAction.replace);
    },
  );

  test(
    'keeps stale scene replacement rule that only changes target weight',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
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
                targetWeightMultiplier: 0.8,
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
              text: 'night',
              category: PromptTagCategory.scene,
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      expect(result.changed, isFalse);
      expect(identical(result.mapping, mapping), isTrue);
      final rules = result.mapping.scenePromptReplacements.single.rules;
      expect(rules.map((rule) => rule.id), [
        'scene-night',
        'scene-old-rain',
      ]);
      expect(rules.last.targetPrompt, isEmpty);
      expect(rules.last.targetWeightMultiplier, 0.8);
      expect(rules.last.effectiveAction, ScriptPromptReplacementAction.replace);
    },
  );

  test(
    'reports mapping changed when refreshed rule only changes target weight',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-1',
        scriptId: 'script-1',
        rolePromptReplacements: [
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-0',
            displayLabel: 'Heroine',
            sourcePreview: 'red jacket',
            rules: [
              _WeightRefreshingPromptReplacementRule(
                id: 'role-slot-0-clothing-red-jacket',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'red-jacket',
                    text: 'red jacket',
                    category: PromptTagCategory.clothing,
                  ),
                ],
                targetWeightMultiplier: 1.2,
                refreshedWeightMultiplier: 1.8,
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
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      expect(result.changed, isTrue);
      expect(identical(result.mapping, mapping), isFalse);
      expect(
        result.mapping.rolePromptReplacements.single.rules.single
            .targetWeightMultiplier,
        1.8,
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

  test(
    'rebases stale same-character variant groups onto the surviving AI role',
    () {
      const mapping = RecastMapping(
        id: 'mapping-script-mash',
        scriptId: 'script-mash',
        roleAssemblies: [
          RoleAssembly(
            sourceRoleId: 'role-mash-kyrielight-demi-servant',
            displayLabel: 'Mash demi-servant',
            stages: [
              RoleAssemblyStage(
                id: 'mash-default',
                label: '默认',
                targetCharacterId: 'target-main',
              ),
            ],
          ),
          RoleAssembly(
            sourceRoleId: 'role-mash-kyrielight',
            displayLabel: 'Mash',
            stages: [
              RoleAssemblyStage(
                id: 'mash-base',
                label: '裸体',
                targetCharacterId: 'target-stale-base',
              ),
            ],
          ),
          RoleAssembly(
            sourceRoleId: 'role-mash-kyrielight-dangerous-beast',
            displayLabel: 'Mash dangerous beast',
            stages: [
              RoleAssemblyStage(
                id: 'mash-dangerous-beast',
                label: '危险野兽',
                targetCharacterId: 'target-stale-variant',
              ),
            ],
          ),
        ],
        rolePromptReplacements: [
          ScriptRolePromptReplacement(
            sourceRoleId: 'role-mash-kyrielight-demi-servant',
            displayLabel: 'Mash demi-servant',
            targetCharacterId: 'target-main',
            rules: [
              ScriptPromptReplacementRule(
                id: 'rule-mash-demi',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'mash-demi',
                    text: 'mash_kyrielight_(demi-servant)',
                    category: PromptTagCategory.character,
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                targetPrompt: 'target main prompt',
              ),
            ],
          ),
          ScriptRolePromptReplacement(
            sourceRoleId: 'role-mash-kyrielight',
            displayLabel: 'Mash',
            targetCharacterId: 'target-stale-base',
            rules: [
              ScriptPromptReplacementRule(
                id: 'rule-mash-base',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'mash-base',
                    text: 'mash_kyrielight',
                    category: PromptTagCategory.character,
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                targetPrompt: 'stale base prompt',
              ),
            ],
          ),
          ScriptRolePromptReplacement(
            sourceRoleId: 'role-mash-kyrielight-dangerous-beast',
            displayLabel: 'Mash dangerous beast',
            targetCharacterId: 'target-stale-variant',
            rules: [
              ScriptPromptReplacementRule(
                id: 'rule-mash-dangerous-beast',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'mash-dangerous-beast',
                    text: 'mash_kyrielight_(dangerous_beast)',
                    category: PromptTagCategory.character,
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                targetPrompt: 'stale variant prompt',
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
              sourceRoleId: 'role-mash-kyrielight-demi-servant',
              sourceKind: 'cross_slot',
              displayName: 'mash_kyrielight_(demi-servant) / 玛修·基列莱特（亚从者）',
              canonicalName: 'mash kyrielight',
              rawIdentityTags: [
                'mash_kyrielight_(demi-servant)',
                'mash_kyrielight',
                'mash_kyrielight_(dangerous_beast)',
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'mash-default',
                  label: '默认',
                  frameIndexes: [1, 2, 3],
                  identity: 'mash_kyrielight_(demi-servant)',
                ),
              ],
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'mash-demi',
                  text: 'mash_kyrielight_(demi-servant)',
                  category: PromptTagCategory.character,
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'mash-base',
                  text: 'mash_kyrielight',
                  category: PromptTagCategory.character,
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'mash-dangerous-beast',
                  text: 'mash_kyrielight_(dangerous_beast)',
                  category: PromptTagCategory.character,
                ),
              ],
            ),
          ],
        ),
        stageLabelFor: labelFor,
      );

      expect(result.changed, isTrue);
      expect(result.mapping.roleAssemblies, hasLength(1));
      expect(
        result.mapping.roleAssemblies.single.sourceRoleId,
        'role-mash-kyrielight-demi-servant',
      );
      expect(
        result.mapping.roleAssemblies.single.stages.single.targetCharacterId,
        'target-main',
      );
      expect(result.mapping.rolePromptReplacements, hasLength(1));
      final replacement = result.mapping.rolePromptReplacements.single;
      expect(replacement.sourceRoleId, 'role-mash-kyrielight-demi-servant');
      expect(replacement.targetCharacterId, 'target-main');
      expect(
        replacement.rules
            .expand((rule) => rule.sourceTerms)
            .map((term) => term.text),
        containsAll([
          'mash_kyrielight_(demi-servant)',
          'mash_kyrielight',
          'mash_kyrielight_(dangerous_beast)',
        ]),
      );
    },
  );
}

class _WeightRefreshingPromptReplacementRule
    extends ScriptPromptReplacementRule {
  final double refreshedWeightMultiplier;

  const _WeightRefreshingPromptReplacementRule({
    required String id,
    List<ScriptPromptReplacementTerm> sourceTerms = const [],
    List<String> excludedTermIds = const [],
    ScriptPromptReplacementAction action = ScriptPromptReplacementAction.none,
    ScriptPromptReplacementMatchMode matchMode =
        ScriptPromptReplacementMatchMode.any,
    String targetPrompt = '',
    double? targetWeightMultiplier,
    String manualPhrase = '',
    String anchorTermId = '',
    required this.refreshedWeightMultiplier,
  }) : super(
          id: id,
          sourceTerms: sourceTerms,
          excludedTermIds: excludedTermIds,
          action: action,
          matchMode: matchMode,
          targetPrompt: targetPrompt,
          targetWeightMultiplier: targetWeightMultiplier,
          manualPhrase: manualPhrase,
          anchorTermId: anchorTermId,
        );

  @override
  ScriptPromptReplacementRule copyWith({
    String? id,
    List<ScriptPromptReplacementTerm>? sourceTerms,
    List<String>? excludedTermIds,
    ScriptPromptReplacementAction? action,
    ScriptPromptReplacementMatchMode? matchMode,
    String? targetPrompt,
    Object? targetWeightMultiplier,
    String? manualPhrase,
    String? anchorTermId,
  }) {
    return ScriptPromptReplacementRule(
      id: id ?? this.id,
      sourceTerms: sourceTerms ?? this.sourceTerms,
      excludedTermIds: excludedTermIds ?? this.excludedTermIds,
      action: action ?? this.action,
      matchMode: matchMode ?? this.matchMode,
      targetPrompt: targetPrompt ?? this.targetPrompt,
      targetWeightMultiplier: refreshedWeightMultiplier,
      manualPhrase: manualPhrase ?? this.manualPhrase,
      anchorTermId: anchorTermId ?? this.anchorTermId,
    );
  }
}
