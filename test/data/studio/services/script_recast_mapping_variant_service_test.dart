import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_mapping_variant_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

void main() {
  const service = ScriptRecastMappingVariantService();

  group('RecastScriptCache mapping variants', () {
    test('round trips complete snapshots and active variant metadata', () {
      final first = RecastMappingVariant(
        id: 'variant-r14',
        name: 'r14',
        scriptId: 'script-a',
        sourceFingerprint: 'source-a',
        sourceContentFingerprint: 'content-a',
        capturedAt: DateTime.utc(2026, 8, 20, 1),
        mapping: _fullMapping('script-a', 'r14'),
        targetCharacterNamesByRoleId: const {'slot-r14': '巫恋'},
      );
      final second = RecastMappingVariant(
        id: 'variant-r15',
        name: 'r15 Mari',
        scriptId: 'script-a',
        sourceFingerprint: 'source-a',
        sourceContentFingerprint: 'content-a',
        capturedAt: DateTime.utc(2026, 8, 20, 2),
        mapping: _fullMapping('script-a', 'r15'),
        targetCharacterNamesByRoleId: const {'slot-r15': '迷迭香'},
      );
      final cache = _cache(
        mapping: second.mapping,
        variants: [first, second],
        activeVariantId: second.id,
      );

      final restored = RecastScriptCache.fromJson(cache.toJson());

      expect(restored.mappingVariants, hasLength(2));
      expect(restored.activeMappingVariantId, second.id);
      expect(restored.mapping.toJson(), second.mapping.toJson());
      expect(restored.mappingVariants[0].toJson(), first.toJson());
      expect(restored.mappingVariants[1].toJson(), second.toJson());
      expect(
        restored.mappingVariants[1].targetCharacterNamesByRoleId,
        const {'slot-r15': '迷迭香'},
      );
      expect(
        restored.mappingVariants[1].mapping.rolePromptReplacements.single
            .activeMappingProfileId,
        'global-profile-r15',
      );
    });

    test('loads legacy JSON without mapping variants', () {
      final legacyJson =
          _cache(mapping: _fullMapping('script-a', 'legacy')).toJson()
            ..remove('mappingVariants')
            ..remove('activeMappingVariantId');

      final restored = RecastScriptCache.fromJson(legacyJson);

      expect(restored.mappingVariants, isEmpty);
      expect(restored.activeMappingVariantId, isNull);
      expect(restored.mapping.toJson(), legacyJson['mapping']);
    });

    test('legacy cache writers cannot erase existing mapping variants', () {
      final variant = RecastMappingVariant(
        id: 'variant-r15',
        name: 'r15 Mari',
        scriptId: 'script-a',
        sourceFingerprint: 'source-a',
        capturedAt: DateTime.utc(2026, 8, 20, 2),
        mapping: _fullMapping('script-a', 'r15'),
      );
      final existing = _cache(
        mapping: variant.mapping,
        variants: [variant],
        activeVariantId: variant.id,
      );
      final legacyDraft = _cache(mapping: variant.mapping);

      final preserved = const ScriptRecastCacheRestoreService()
          .cachePreservingExistingAiDraft(legacyDraft, existing);

      expect(preserved.mappingVariants, [variant]);
      expect(preserved.activeMappingVariantId, variant.id);
      expect(preserved.mapping.toJson(), legacyDraft.mapping.toJson());
    });
  });

  group('ScriptRecastMappingVariantService', () {
    test('captures an immutable complete snapshot', () {
      final mapping = _fullMapping('script-a', 'r15');
      final cache = _cache(mapping: mapping);

      final captured = service.capture(
        cache: cache,
        id: 'variant-r15',
        name: 'r15 Mari',
        capturedAt: DateTime.utc(2026, 8, 20, 3),
        targetCharacterNamesByRoleId: const {'slot-r15': '迷迭香'},
      );

      expect(cache.mappingVariants, isEmpty);
      expect(captured.activeMappingVariantId, 'variant-r15');
      expect(captured.mappingVariants, hasLength(1));
      expect(
        captured.mappingVariants.single.targetCharacterNamesByRoleId,
        const {'slot-r15': '迷迭香'},
      );
      expect(
          captured.mappingVariants.single.mapping.toJson(), mapping.toJson());
      expect(
        identical(captured.mappingVariants.single.mapping, mapping),
        isFalse,
      );
    });

    test('atomically switches every mapping field and preserves profile id',
        () {
      final r14 = RecastMappingVariant(
        id: 'variant-r14',
        name: 'r14',
        scriptId: 'script-a',
        sourceFingerprint: 'source-a',
        sourceContentFingerprint: 'content-a',
        capturedAt: DateTime.utc(2026, 8, 20, 1),
        mapping: _fullMapping('script-a', 'r14'),
      );
      final r15 = RecastMappingVariant(
        id: 'variant-r15',
        name: 'r15 Mari',
        scriptId: 'script-a',
        sourceFingerprint: 'source-a',
        sourceContentFingerprint: 'content-a',
        capturedAt: DateTime.utc(2026, 8, 20, 2),
        mapping: _fullMapping('script-a', 'r15'),
      );
      final original = _cache(
        mapping: r14.mapping,
        variants: [r14, r15],
        activeVariantId: r14.id,
      );

      final switched = service.activate(
        cache: original,
        variantId: r15.id,
        expectedScriptId: 'script-a',
        expectedSourceFingerprint: 'source-a',
        expectedSourceContentFingerprint: 'content-a',
        activatedAt: DateTime.utc(2026, 8, 20, 4),
      );

      expect(original.activeMappingVariantId, r14.id);
      expect(original.mapping.toJson(), r14.mapping.toJson());
      expect(switched.activeMappingVariantId, r15.id);
      expect(switched.mapping.toJson(), r15.mapping.toJson());
      expect(
        switched.mapping.rolePromptReplacements.single.activeMappingProfileId,
        'global-profile-r15',
      );
      expect(
        switched.mapping.rolePromptReplacements.single.rules,
        isNotEmpty,
      );
    });

    test('rejects foreign script and source fingerprints', () {
      final foreign = RecastMappingVariant(
        id: 'foreign',
        name: 'foreign',
        scriptId: 'script-b',
        sourceFingerprint: 'source-b',
        capturedAt: DateTime.utc(2026, 8, 20),
        mapping: _fullMapping('script-b', 'foreign'),
      );
      final wrongSource = RecastMappingVariant(
        id: 'wrong-source',
        name: 'wrong source',
        scriptId: 'script-a',
        sourceFingerprint: 'source-b',
        capturedAt: DateTime.utc(2026, 8, 20),
        mapping: _fullMapping('script-a', 'wrong-source'),
      );
      final cache = _cache(
        mapping: _fullMapping('script-a', 'working'),
        variants: [foreign, wrongSource],
      );

      expect(
        () => service.activate(
          cache: cache,
          variantId: foreign.id,
          expectedScriptId: 'script-a',
          expectedSourceFingerprint: 'source-a',
          expectedSourceContentFingerprint: 'content-a',
          activatedAt: DateTime.utc(2026, 8, 20),
        ),
        throwsFormatException,
      );
      expect(
        () => service.activate(
          cache: cache,
          variantId: wrongSource.id,
          expectedScriptId: 'script-a',
          expectedSourceFingerprint: 'source-a',
          expectedSourceContentFingerprint: 'content-a',
          activatedAt: DateTime.utc(2026, 8, 20),
        ),
        throwsFormatException,
      );
    });

    test('distinguishes empty, no-rule, and effective mappings', () {
      final empty = service.summarize(RecastMapping.defaults('script-a'));
      final emptyGroup = service.summarize(
        RecastMapping.defaults('script-a').copyWith(
          rolePromptReplacements: const [
            ScriptRolePromptReplacement(
              sourceRoleId: 'shared-role',
              displayLabel: '共享角色',
              activeMappingProfileId: 'global-profile',
            ),
          ],
        ),
      );
      final noRules = service.summarize(
        RecastMapping.defaults('script-a').copyWith(
          roleSwaps: const [
            RoleSwap(
              sourceRoleId: 'slot-0',
              targetCharacterId: 'mari',
            ),
          ],
        ),
      );
      final mapped = service.summarize(_fullMapping('script-a', 'r15'));

      expect(empty.kind, RecastMappingVariantSummaryKind.empty);
      expect(emptyGroup.kind, RecastMappingVariantSummaryKind.empty);
      expect(emptyGroup.hasEffectiveMapping, isFalse);
      expect(noRules.kind, RecastMappingVariantSummaryKind.mappedWithoutRules);
      expect(noRules.ruleCount, 0);
      expect(mapped.kind, RecastMappingVariantSummaryKind.mappedWithRules);
      expect(mapped.mappingCount, greaterThan(0));
      expect(mapped.ruleCount, greaterThan(0));
    });
  });
}

RecastScriptCache _cache({
  required RecastMapping mapping,
  List<RecastMappingVariant> variants = const [],
  String? activeVariantId,
}) {
  return RecastScriptCache(
    scriptId: 'script-a',
    scriptName: 'Script A',
    sourceRootPath: r'C:\scripts\a',
    sourceFingerprint: 'source-a',
    sourceContentFingerprint: 'content-a',
    updatedAt: DateTime.utc(2026, 8, 20),
    mapping: mapping,
    mappingVariants: variants,
    activeMappingVariantId: activeVariantId,
  );
}

RecastMapping _fullMapping(String scriptId, String suffix) {
  final ruleId = 'rule-$suffix';
  return RecastMapping(
    id: 'mapping-$scriptId',
    scriptId: scriptId,
    roleSwaps: [
      RoleSwap(
        sourceRoleId: 'slot-$suffix',
        targetCharacterId: 'character-$suffix',
        targetOutfitId: 'outfit-$suffix',
      ),
    ],
    roleAssemblies: [
      RoleAssembly(
        sourceRoleId: 'slot-$suffix',
        displayLabel: 'Role $suffix',
        stages: [
          RoleAssemblyStage(
            id: 'stage-$suffix',
            label: 'Stage $suffix',
            targetCharacterId: 'character-$suffix',
            targetUpperOutfitId: 'upper-$suffix',
            omittedParts: const {RecastPromptPart.lowerClothing},
            manualParts: RecastPromptParts(identity: 'identity-$suffix'),
          ),
        ],
      ),
    ],
    rolePromptReplacements: [
      ScriptRolePromptReplacement(
        sourceRoleId: 'slot-$suffix',
        displayLabel: 'Role $suffix',
        targetCharacterId: 'character-$suffix',
        targetIdentityPrompt: 'target identity $suffix',
        activeMappingProfileId: 'global-profile-$suffix',
        layerOverrides: [
          ScriptRoleReplacementRuleLayerOverride(
            ruleId: ruleId,
            kind: ScriptRoleReplacementRuleLayerKind.stage,
            stageId: 'stage-$suffix',
          ),
        ],
        rules: [
          ScriptPromptReplacementRule(
            id: ruleId,
            sourceTerms: [
              ScriptPromptReplacementTerm(
                id: 'term-$suffix',
                text: 'source $suffix',
                category: PromptTagCategory.character,
              ),
            ],
            action: ScriptPromptReplacementAction.replace,
            targetPrompt: 'replacement $suffix',
          ),
        ],
      ),
    ],
    scenePromptReplacements: [
      ScriptScenePromptReplacement(
        id: 'scene-$suffix',
        label: 'Scene $suffix',
        rules: [
          ScriptPromptReplacementRule(
            id: 'scene-rule-$suffix',
            action: ScriptPromptReplacementAction.delete,
          ),
        ],
      ),
    ],
    artistSwap: ArtistSwap(
      targetArtistChainId: 'artist-$suffix',
      manualPrompt: 'artist prompt $suffix',
      sourceArtistPrompt: 'source artist $suffix',
    ),
    promptBlockSwaps: [
      PromptBlockSwap(
        block: 'style',
        sourcePrompt: 'source style $suffix',
        manualPrompt: 'style $suffix',
      ),
    ],
    manualVibeRefs: [
      WorkspaceVibeReference(
        id: 'vibe-$suffix',
        name: 'Vibe $suffix',
        vibeB64: 'encoding-$suffix',
      ),
    ],
    suppressedPromptTagWarningKeys: {'warning-$suffix'},
    preservePresetId: 'preset-$suffix',
    outputPolicy: 'output-$suffix',
  );
}
