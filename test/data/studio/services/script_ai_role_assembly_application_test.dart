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
}

