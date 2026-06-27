import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

void main() {
  group('RecastMapping', () {
    test('round trips role and artist swaps without policy metadata', () {
      final mapping = RecastMapping(
        id: 'mapping-1',
        scriptId: 'script-1',
        roleSwaps: const [
          RoleSwap(sourceRoleId: 'slot-0', targetCharacterId: 'char-x'),
        ],
        artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
        manualVibeRefs: const [
          WorkspaceVibeReference(
            id: 'manual-vibe',
            name: 'Manual Vibe',
            vibeB64: 'encoded-manual-vibe',
            referenceStrength: 0.5,
          ),
        ],
      );

      final restored = RecastMapping.fromJson(mapping.toJson());

      expect(restored.toJson(), mapping.toJson());
      expect(restored.roleSwaps.single.targetCharacterId, 'char-x');
      expect(restored.artistSwap!.targetArtistChainId, 'artist-chain-x');
      expect(restored.manualVibeRefs.single.vibeB64, 'encoded-manual-vibe');
      expect(restored.toJson().keys, isNot(contains('segmentPolicies')));
      expect(restored.toJson().keys, isNot(contains('paramPolicies')));
      expect(restored.toJson().keys, isNot(contains('frameOverrides')));
      expect(restored.toJson().keys, isNot(contains('filterOverrides')));
    });

    test('round trips manual artist prompt swaps', () {
      const mapping = RecastMapping(
        id: 'mapping-manual-artist',
        scriptId: 'script-1',
        artistSwap: ArtistSwap(
          targetArtistChainId: '',
          manualPrompt: 'artist:manual_style, soft watercolor lighting',
          sourceArtistPrompt: 'artist:source_style',
          deleteSource: true,
        ),
        promptBlockSwaps: [
          PromptBlockSwap(
            block: 'style',
            sourcePrompt: 'official style',
            manualPrompt: 'watercolor',
          ),
          PromptBlockSwap(
            block: 'quality',
            sourcePrompt: 'best quality',
            deleteSource: true,
          ),
        ],
      );

      final restored = RecastMapping.fromJson(mapping.toJson());

      expect(restored.toJson(), mapping.toJson());
      expect(restored.artistSwap!.targetArtistChainId, isEmpty);
      expect(
        restored.artistSwap!.manualPrompt,
        'artist:manual_style, soft watercolor lighting',
      );
      expect(restored.artistSwap!.sourceArtistPrompt, 'artist:source_style');
      expect(restored.artistSwap!.deleteSource, isTrue);
      expect(restored.promptBlockSwaps, hasLength(2));
      expect(restored.promptBlockSwaps.first.block, 'style');
      expect(restored.promptBlockSwaps.last.deleteSource, isTrue);
    });

    test('defaults keep mapping metadata minimal', () {
      final defaults = RecastMapping.defaults('script-1');

      expect(defaults.scriptId, 'script-1');
      expect(defaults.toJson(),
          RecastMapping.fromJson(defaults.toJson()).toJson());
      expect(defaults.toJson().keys, containsAll(['id', 'scriptId']));
      expect(defaults.toJson().keys, isNot(contains('segmentPolicies')));
      expect(defaults.toJson().keys, isNot(contains('paramPolicies')));
    });

    test('round trips suppressed prompt tag warning keys', () {
      final mapping = RecastMapping.defaults('script-1').copyWith(
        suppressedPromptTagWarningKeys: const {'male smile'},
      );

      final restored = RecastMapping.fromJson(mapping.toJson());

      expect(restored.suppressedPromptTagWarningKeys, {'male smile'});
      expect(restored.toJson(), mapping.toJson());
    });

    test('copyWith updates selected fields while preserving defaults', () {
      final mapping = RecastMapping.defaults('script-1').copyWith(
        roleSwaps: const [
          RoleSwap(sourceRoleId: 'slot-0', targetCharacterId: 'char-x'),
        ],
      );

      expect(mapping.roleSwaps.single.targetCharacterId, 'char-x');
      expect(mapping.toJson().keys, isNot(contains('paramPolicies')));
    });

    test('round trips role assemblies with prompt parts and stages', () {
      final mapping = RecastMapping(
        id: 'mapping-assembly',
        scriptId: 'script-1',
        roleAssemblies: const [
          RoleAssembly(
            sourceRoleId: 'slot-0',
            displayLabel: '角色 1',
            sourceName: 'source heroine',
            stages: [
              RoleAssemblyStage(
                id: 'slot-0-stage-1',
                label: '服装 1',
                frameIndexes: [1, 2],
                sourceSummary: 'school uniform',
                targetCharacterId: 'char-hero',
                targetUpperOutfitId: 'school',
                targetLowerOutfitId: 'casual',
                omittedParts: {RecastPromptPart.lowerBody},
                preservedParts: {RecastPromptPart.upperBody},
                manualParts: RecastPromptParts(
                  identity: 'edited heroine',
                  upperBody: 'animal ears',
                  lowerBody: 'tail',
                  upperClothing: 'white shirt',
                  lowerClothing: 'black skirt',
                ),
              ),
            ],
          ),
        ],
      );

      final restored = RecastMapping.fromJson(mapping.toJson());

      expect(restored.toJson(), mapping.toJson());
      expect(restored.roleAssemblies.single.displayLabel, '角色 1');
      expect(restored.roleAssemblies.single.stages.single.label, '服装 1');
      expect(
        restored.roleAssemblies.single.stages.single.manualParts.upperClothing,
        'white shirt',
      );
      expect(
        restored.roleAssemblies.single.stages.single.preservedParts,
        contains(RecastPromptPart.upperBody),
      );
    });

    test('round trips role and scene prompt replacement rules', () {
      const mapping = RecastMapping(
        id: 'mapping-replacements',
        scriptId: 'script-1',
        rolePromptReplacements: [
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-0',
            displayLabel: '角色 1',
            targetCharacterId: 'lily',
            targetIdentityPrompt: 'lily, silver hair, blue eyes',
            rules: [
              ScriptPromptReplacementRule(
                id: 'rule-jacket-skirt',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'term-red-jacket',
                    text: 'red jacket',
                    category: PromptTagCategory.clothing,
                    frameIndexes: [1, 2, 3],
                  ),
                  ScriptPromptReplacementTerm(
                    id: 'term-black-skirt',
                    text: 'black skirt',
                    category: PromptTagCategory.clothing,
                    frameIndexes: [1, 2, 3],
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                matchMode: ScriptPromptReplacementMatchMode.any,
                targetPrompt: 'white dress, lace trim',
              ),
            ],
          ),
        ],
        scenePromptReplacements: [
          ScriptScenePromptReplacement(
            id: 'scene-base',
            label: 'base prompt',
            rules: [
              ScriptPromptReplacementRule(
                id: 'rule-night',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'term-night',
                    text: 'night',
                    category: PromptTagCategory.scene,
                    sourceLocation: 'base prompt',
                    frameIndexes: [1, 2],
                  ),
                ],
                action: ScriptPromptReplacementAction.delete,
                matchMode: ScriptPromptReplacementMatchMode.anchor,
                anchorTermId: 'term-night',
              ),
            ],
          ),
        ],
      );

      final restored = RecastMapping.fromJson(mapping.toJson());

      expect(restored.toJson(), mapping.toJson());
      expect(restored.rolePromptReplacements.single.sourceRoleId, 'slot-0');
      expect(restored.rolePromptReplacements.single.displayLabel, '角色 1');
      expect(
        restored.rolePromptReplacements.single.targetCharacterId,
        'lily',
      );
      expect(
        restored.rolePromptReplacements.single.targetIdentityPrompt,
        'lily, silver hair, blue eyes',
      );
      expect(
        restored.rolePromptReplacements.single.rules.single.targetPrompt,
        'white dress, lace trim',
      );
      expect(
        restored.rolePromptReplacements.single.rules.single.sourceTerms
            .map((term) => term.text),
        ['red jacket', 'black skirt'],
      );
      expect(
        restored.scenePromptReplacements.single.rules.single.sourceTerms.single
            .sourceLocation,
        'base prompt',
      );
      expect(
        restored.scenePromptReplacements.single.rules.single.matchMode,
        ScriptPromptReplacementMatchMode.anchor,
      );
    });

    test('blank target prompt keeps a replacement rule inactive', () {
      const rule = ScriptPromptReplacementRule(
        id: 'rule-glasses',
        sourceTerms: [
          ScriptPromptReplacementTerm(
            id: 'term-round-glasses',
            text: 'round glasses',
            category: PromptTagCategory.clothing,
          ),
        ],
      );

      expect(rule.hasEffect, isFalse);
      expect(rule.action, ScriptPromptReplacementAction.none);
    });

    test('target prompt with default action is an effective replacement', () {
      const rule = ScriptPromptReplacementRule(
        id: 'rule-target-only',
        targetPrompt: 'white dress, lace trim',
      );

      expect(rule.action, ScriptPromptReplacementAction.none);
      expect(rule.effectiveAction, ScriptPromptReplacementAction.replace);
      expect(rule.hasEffect, isTrue);
    });

    test('round trips replacement rule target block weight multiplier', () {
      final rule = ScriptPromptReplacementRule.fromJson(const {
        'id': 'rule-weighted-block',
        'targetPrompt': 'white dress, lace trim',
        'targetWeightMultiplier': 1.2,
      });

      expect(rule.toJson()['targetWeightMultiplier'], 1.2);
    });

    test('target weight multiplier without target prompt is effective', () {
      const rule = ScriptPromptReplacementRule(
        id: 'rule-source-weight',
        targetWeightMultiplier: 1.2,
      );

      expect(rule.effectiveAction, ScriptPromptReplacementAction.replace);
      expect(rule.hasEffect, isTrue);
    });

    test('replace action with blank target and manual prompt is inactive', () {
      const rule = ScriptPromptReplacementRule(
        id: 'rule-blank-replace',
        action: ScriptPromptReplacementAction.replace,
        manualPhrase: 'hidden manual output',
      );

      expect(rule.effectiveAction, ScriptPromptReplacementAction.none);
      expect(rule.hasEffect, isFalse);
    });

    test('delete action stays an effective delete', () {
      const rule = ScriptPromptReplacementRule(
        id: 'rule-delete',
        action: ScriptPromptReplacementAction.delete,
      );

      expect(rule.effectiveAction, ScriptPromptReplacementAction.delete);
      expect(rule.hasEffect, isTrue);
    });

    test('replacement term categories preserve accessory and clothingState',
        () {
      final mapping = RecastMapping.fromJson({
        'id': 'mapping-a',
        'scriptId': 'script-a',
        'roleSwaps': [],
        'artistSwap': null,
        'rolePromptReplacements': [
          {
            'sourceRoleId': 'slot-0',
            'displayLabel': 'Role',
            'rules': [
              {
                'id': 'rule-accessory',
                'sourceTerms': [
                  {
                    'id': 'term-collar',
                    'text': 'black collar',
                    'category': 'accessory',
                  },
                ],
              },
              {
                'id': 'rule-state',
                'sourceTerms': [
                  {
                    'id': 'term-strap-slip',
                    'text': 'strap slip',
                    'category': 'clothing_state',
                  },
                ],
              },
            ],
          },
        ],
      });

      final terms = mapping.rolePromptReplacements.single.rules
          .expand((rule) => rule.sourceTerms)
          .toList();
      final json = mapping.toJson();
      final replacements =
          (json['rolePromptReplacements'] as List).cast<Map<String, dynamic>>();
      final rules =
          (replacements.first['rules'] as List).cast<Map<String, dynamic>>();
      final accessoryTerm = (rules.first['sourceTerms'] as List)
          .cast<Map<String, dynamic>>()
          .first;
      final stateTerm = (rules.last['sourceTerms'] as List)
          .cast<Map<String, dynamic>>()
          .first;

      expect(terms[0].category, PromptTagCategory.accessory);
      expect(terms[1].category, PromptTagCategory.clothingState);
      expect(accessoryTerm['category'], 'accessory');
      expect(stateTerm['category'], 'clothingState');
    });
  });

  group('RecastRun', () {
    test('round trips frame results and config fingerprint', () {
      final run = RecastRun(
        id: 'run-1',
        scriptId: 'script-1',
        mappingId: 'mapping-1',
        productionPlanId: 'plan-1',
        status: RecastRunStatus.queued,
        configFingerprint: 'abc123',
        frameResults: const [
          FrameResult(
            frameIndex: 1,
            sourceFileName: 'nai_1.json',
            taskId: 'task-1',
            status: FrameResultStatus.queued,
            payloadFingerprint: 'payload-1',
            attempts: 2,
          ),
        ],
      );

      final restored = RecastRun.fromJson(run.toJson());

      expect(restored.toJson(), run.toJson());
      expect(restored.frameResults.single.payloadFingerprint, 'payload-1');
      expect(restored.configFingerprint, 'abc123');
    });
  });
}
