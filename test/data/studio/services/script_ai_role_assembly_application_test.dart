import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_assembly_application.dart';

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

  test('keeps user-authored targets and manual fields when refreshing stage', () {
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
