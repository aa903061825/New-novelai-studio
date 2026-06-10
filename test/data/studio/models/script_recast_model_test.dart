import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

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
