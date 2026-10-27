import 'dart:math' as math;

import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/script_role_replacement_layer_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

class ScriptRoleMappingProfileService {
  static const Set<String> _genericTargetTagKeys = {
    '1boy',
    '1girl',
    'boy',
    'female',
    'girl',
    'male',
    'one person only',
    'single character',
    'solo',
  };

  final ScriptRoleReplacementLayerService layerService;

  const ScriptRoleMappingProfileService({
    this.layerService = const ScriptRoleReplacementLayerService(),
  });

  RoleMappingProfile createProfile({
    required String id,
    required String name,
    required ScriptRolePromptReplacement replacement,
    required DateTime now,
    String targetCharacterNameSnapshot = '',
    RoleAssembly? assembly,
  }) {
    final timestamp = now.toUtc();
    return RoleMappingProfile(
      id: id,
      name: name.trim(),
      targetCharacterId: replacement.targetCharacterId,
      targetCharacterNameSnapshot: targetCharacterNameSnapshot.trim(),
      targetIdentityPrompt: replacement.targetIdentityPrompt,
      layers: _profileLayersFromReplacement(
        replacement: replacement,
        assembly: assembly,
      ),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// Removes target terms that belong to another character when a profile was
  /// retargeted without rebuilding its old target rules.
  ///
  /// Profile blocks intentionally may contain terms that are not present in
  /// the current source prompt, so source matching alone cannot protect the
  /// output. The character library is the authoritative boundary for
  /// character/outfit terms; unknown custom terms remain untouched.
  RoleMappingProfile reconcileTargetCharacter({
    required RoleMappingProfile profile,
    required CharacterEntry targetCharacter,
    required Iterable<CharacterEntry> characterCatalog,
    String fallbackIdentityPrompt = '',
  }) {
    final catalog = [
      for (final character in characterCatalog)
        if (character.id.trim().isNotEmpty) character,
    ];
    if (!catalog.any((character) => character.id == targetCharacter.id)) {
      catalog.add(targetCharacter);
    }
    final targetKeys = _characterTargetTagKeys(targetCharacter);
    final knownKeys = <String>{
      for (final character in catalog) ..._characterTargetTagKeys(character),
    };
    final foreignKeys = knownKeys.difference(targetKeys)
      ..removeAll(_genericTargetTagKeys);

    String filterPrompt(String prompt) {
      final filtered = [
        for (final tag in _splitTargetPromptTags(prompt))
          if (!_isForeignTargetTag(
            PromptTagProcessor.normalizeMatchKey(tag),
            targetKeys,
            foreignKeys,
          ))
            tag,
      ];
      return _joinTargetPromptTags(filtered);
    }

    final identityPrompt = filterPrompt(profile.targetIdentityPrompt);
    final identityChanged =
        identityPrompt != profile.targetIdentityPrompt.trim();
    final fallback = fallbackIdentityPrompt.trim();
    final repairedIdentity =
        (identityChanged || identityPrompt.isEmpty) && fallback.isNotEmpty
            ? _joinTargetPromptTags([fallback, identityPrompt])
            : identityPrompt;
    final layers = [
      for (final layer in profile.effectiveLayers)
        layer.copyWith(
          blocks: List.unmodifiable([
            for (final block in layer.blocks)
              block.copyWith(
                targetPrompt: filterPrompt(block.targetPrompt),
                targetWeightMultiplier:
                    filterPrompt(block.targetPrompt).trim().isEmpty
                        ? null
                        : block.targetWeightMultiplier,
              ),
          ]),
        ),
    ];

    return profile.copyWith(
      targetIdentityPrompt: repairedIdentity,
      layers: List.unmodifiable(layers),
    );
  }

  RoleMappingApplyPreview buildPreview({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement replacement,
    RoleAssembly? assembly,
  }) {
    final currentTerms = _includedTermsById(replacement.rules);
    final presentKeys = {
      for (final term in currentTerms.values)
        normalizeRoleMappingProfileTerm(term.text),
    };
    final availableTermIds = List<String>.unmodifiable(currentTerms.keys);
    final layerEntries = _layerPreviews(
      profile: profile,
      replacement: replacement,
      assembly: assembly,
    );

    // A profile block is a reusable target-side mapping.  Its source terms
    // can be heterogeneous because older profiles were recorded before the
    // upper/lower split was enforced.  First collect every raw candidate, then
    // remove fallback candidates for a term whenever a same-part candidate
    // exists elsewhere in the profile.
    final candidateTermIdsByBlockKey = <String, List<String>>{};
    final strictOwnersByTermId = <String, Set<String>>{};
    for (final layer in profile.effectiveLayers) {
      for (final block in layer.blocks) {
        final blockKey = _profileBlockKey(layer.id, block.id);
        final candidates = [
          for (final entry in currentTerms.entries)
            if (block.normalizedTermKeys.contains(
              normalizeRoleMappingProfileTerm(entry.value.text),
            ))
              entry.key,
        ];
        candidateTermIdsByBlockKey[blockKey] = candidates;
        for (final termId in candidates) {
          final term = currentTerms[termId];
          if (term == null || !_hasStrictCategoryMatch(block, term.category)) {
            continue;
          }
          strictOwnersByTermId.putIfAbsent(termId, () => <String>{}).add(
                blockKey,
              );
        }
      }
    }
    final blockedGenericClothingTermIds = <String>{
      for (final entry in currentTerms.entries)
        if (entry.value.category == PromptTagCategory.clothing &&
            !strictOwnersByTermId.containsKey(entry.key))
          entry.key,
    };
    var entries = [
      for (final layer in profile.effectiveLayers)
        for (final block in layer.blocks)
          _previewEntry(
            block: block,
            profileLayerId: layer.id,
            replacement: replacement,
            currentTerms: currentTerms,
            presentKeys: presentKeys,
            availableTermIds: availableTermIds,
            candidateTermIds: [
              for (final termId in candidateTermIdsByBlockKey[
                      _profileBlockKey(layer.id, block.id)] ??
                  const <String>[])
                if (!blockedGenericClothingTermIds.contains(termId) &&
                    ((strictOwnersByTermId[termId]?.isEmpty ?? true) ||
                        strictOwnersByTermId[termId]!
                            .contains(_profileBlockKey(layer.id, block.id))))
                  termId,
            ],
          ),
    ];

    final claimsByTermId = <String, int>{};
    for (final entry in entries) {
      if (entry.status == RoleMappingApplyPreviewStatus.unmatched) continue;
      for (final termId in entry.selectedTermIds) {
        claimsByTermId.update(termId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    entries = [
      for (final entry in entries)
        if (entry.selectedTermIds.any(
          (termId) => (claimsByTermId[termId] ?? 0) > 1,
        ))
          entry.copyWith(
            status: RoleMappingApplyPreviewStatus.ambiguous,
            selectedByDefault: false,
          )
        else
          entry,
    ];

    return RoleMappingApplyPreview(
      profileId: profile.id,
      sourceRoleId: replacement.sourceRoleId,
      entries: List.unmodifiable(entries),
      layerEntries: layerEntries,
    );
  }

  ScriptRolePromptReplacement applySelections({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement replacement,
    required Iterable<RoleMappingProfileApplySelection> selections,
    bool applyIdentity = true,
    bool linkProfile = false,
    Iterable<RoleMappingProfileLayerApplySelection> layerSelections = const [],
    RoleAssembly? assembly,
  }) {
    final selected = selections.toList(growable: false);
    final hasSelectedTerms = selected.any(
      (selection) => selection.termIds.isNotEmpty,
    );
    final effectiveApplyIdentity = applyIdentity && hasSelectedTerms;
    final claimedTermIds = <String>{};
    for (final selection in selected) {
      for (final termId in selection.termIds) {
        if (!claimedTermIds.add(termId)) {
          throw ArgumentError.value(
            termId,
            'selections',
            'A source term cannot be merged into multiple cached blocks.',
          );
        }
      }
    }

    final blockOwnerById = <String, RoleMappingProfileLayer>{
      for (final layer in profile.effectiveLayers)
        for (final block in layer.blocks) block.id: layer,
    };
    final explicitLayerSelections = {
      for (final selection in layerSelections)
        selection.profileLayerId: selection,
    };
    final layerPreviewById = {
      for (final preview in _layerPreviews(
        profile: profile,
        replacement: replacement,
        assembly: assembly,
      ))
        preview.layer.id: preview,
    };
    final targetChanged = effectiveApplyIdentity &&
        profile.targetCharacterId != replacement.targetCharacterId;
    var rules = targetChanged
        ? _rulesWithoutTargetOutputs(replacement.rules)
        : replacement.rules;
    final appliedLayerByRuleId =
        <String, ScriptRoleReplacementRuleLayerOverride>{};
    for (final selection in selected) {
      final block = profile.blocks
          .where((entry) => entry.id == selection.blockId)
          .firstOrNull;
      if (block == null || selection.termIds.isEmpty) continue;
      final owner = blockOwnerById[block.id];
      if (owner == null) continue;
      final targetLayer = explicitLayerSelections[owner.id] ??
          _automaticLayerSelection(layerPreviewById[owner.id]);
      if (targetLayer == null || targetLayer.skipped) {
        continue;
      }
      rules = _rulesWithAppliedBlock(
        rules: rules,
        block: block,
        selectedTermIds: selection.termIds.toSet(),
        requestedAnchorTermId: selection.anchorTermId,
      );
      final appliedRule = rules
          .where(
            (rule) => _sameStringSet(
              _includedTermIds(rule),
              selection.termIds.toSet(),
            ),
          )
          .firstOrNull;
      if (appliedRule != null && targetLayer.targetKind != null) {
        appliedLayerByRuleId[appliedRule.id] =
            ScriptRoleReplacementRuleLayerOverride(
          ruleId: appliedRule.id,
          kind: targetLayer.targetKind!,
          stageId: targetLayer.targetStageId,
        );
      }
    }

    final identityPromptToken = profile.targetIdentityPromptToken.trim();
    if (effectiveApplyIdentity && identityPromptToken.isNotEmpty) {
      // A custom identity token belongs only on character-identity source
      // rules. Appearance terms such as hair, eyes, ears, and headwear must
      // remain in their own upper-body/accessory rules instead of being
      // attached to the source character name.
      rules = _rulesWithIdentityPromptToken(
        rules: rules,
        token: identityPromptToken,
      );
    }

    final survivingRuleIds = {for (final rule in rules) rule.id};
    return replacement.copyWith(
      targetCharacterId: effectiveApplyIdentity
          ? profile.targetCharacterId
          : replacement.targetCharacterId,
      targetIdentityPrompt: effectiveApplyIdentity
          ? _targetIdentityPromptWithToken(
              profile.targetIdentityPrompt,
              identityPromptToken,
            )
          : replacement.targetIdentityPrompt,
      // Applying a global profile is a one-time copy by default. Linking the
      // current role back to the global profile is a separate, explicit
      // action so a normal apply cannot silently enable write-back sync.
      activeMappingProfileId:
          linkProfile && hasSelectedTerms ? profile.id : null,
      rules: List.unmodifiable(rules),
      layerOverrides: List.unmodifiable([
        for (final override in replacement.layerOverrides)
          if (survivingRuleIds.contains(override.ruleId) &&
              !appliedLayerByRuleId.containsKey(override.ruleId))
            override,
        ...appliedLayerByRuleId.values,
      ]),
    );
  }

  /// Converts character-identity cleanup into a real replacement when a
  /// fully materialized cache is being produced.
  ///
  /// `targetIdentityPrompt` is intentionally a candidate in the interactive
  /// editor.  Offline script variants, however, must be executable without a
  /// second manual "sync to selected rules" action. Older profiles can leave
  /// the source identity as delete-only, no-op, or mixed character rules;
  /// merge those identity terms into one replacement and keep accessory/body
  /// cleanup terms as their own rules.
  ScriptRolePromptReplacement materializeTargetIdentityReplacement(
    ScriptRolePromptReplacement replacement,
  ) {
    final targetPrompt = replacement.targetIdentityPrompt.trim();
    if (targetPrompt.isEmpty) return replacement;

    final rules = replacement.rules;
    final identityRuleIndexes = <int>[];
    final mixedIdentityRuleIndexes = <int>[];
    final movedTermIdsByIndex = <int, Set<String>>{};
    for (var index = 0; index < rules.length; index += 1) {
      final rule = rules[index];
      final includedTerms = [
        for (final term in rule.sourceTerms)
          if (!rule.excludedTermIds.contains(term.id)) term,
      ];
      final characterTerms = includedTerms
          .where((term) => term.category == PromptTagCategory.character)
          .toList(growable: false);
      if (_isCharacterIdentityRule(rule)) {
        identityRuleIndexes.add(index);
      } else if (characterTerms.isNotEmpty &&
          includedTerms.any(
            (term) =>
                term.category != PromptTagCategory.character &&
                term.category != PromptTagCategory.other,
          )) {
        // A profile block can be a mixed rule even when its current action is
        // replace.  Its target may only be a partial identity output, so the
        // character terms still need to be separated and merged into the
        // canonical full identity replacement below.
        mixedIdentityRuleIndexes.add(index);
      }
      if (characterTerms.isNotEmpty &&
          (identityRuleIndexes.contains(index) ||
              mixedIdentityRuleIndexes.contains(index))) {
        movedTermIdsByIndex[index] = {
          for (final term in includedTerms)
            if (term.category == PromptTagCategory.character ||
                (term.category == PromptTagCategory.other &&
                    characterTerms.isNotEmpty))
              term.id,
        };
      }
    }
    final candidateIndexes = {
      ...identityRuleIndexes,
      ...mixedIdentityRuleIndexes,
    }.toList()
      ..sort();
    if (candidateIndexes.isEmpty) return replacement;

    final mergedTerms = <ScriptPromptReplacementTerm>[];
    final seenTermKeys = <String>{};
    for (final index in candidateIndexes) {
      final rule = rules[index];
      final movedTermIds = movedTermIdsByIndex[index] ?? const <String>{};
      for (final term in rule.sourceTerms) {
        if (!movedTermIds.contains(term.id)) continue;
        final key = PromptTagProcessor.normalizeMatchKey(term.text);
        if (key.isNotEmpty && seenTermKeys.add(key)) {
          mergedTerms.add(term);
        }
      }
    }
    if (mergedTerms.isEmpty) return replacement;

    final firstIndex = candidateIndexes.reduce(
      (left, right) => left < right ? left : right,
    );
    final firstRule = rules[firstIndex];
    final materializedRule = firstRule.copyWith(
      sourceTerms: List.unmodifiable(mergedTerms),
      excludedTermIds: const [],
      action: ScriptPromptReplacementAction.replace,
      matchMode: ScriptPromptReplacementMatchMode.any,
      targetPrompt: targetPrompt,
      targetWeightMultiplier: null,
      manualPhrase: '',
      anchorTermId: '',
    );
    final nextRules = <ScriptPromptReplacementRule>[];
    for (var index = 0; index < rules.length; index += 1) {
      if (index == firstIndex) {
        nextRules.add(materializedRule);
      }
      if (identityRuleIndexes.contains(index)) continue;
      if (mixedIdentityRuleIndexes.contains(index)) {
        final movedTermIds = movedTermIdsByIndex[index] ?? const <String>{};
        final remainingTerms = [
          for (final term in rules[index].sourceTerms)
            if (!movedTermIds.contains(term.id)) term,
        ];
        if (remainingTerms.isNotEmpty) {
          final remainingRule = rules[index].copyWith(
            id: index == firstIndex
                ? '${rules[index].id}-non-identity'
                : rules[index].id,
            sourceTerms: List.unmodifiable(remainingTerms),
            excludedTermIds: [
              for (final termId in rules[index].excludedTermIds)
                if (remainingTerms.any((term) => term.id == termId)) termId,
            ],
          );
          nextRules.add(remainingRule);
        }
        continue;
      }
      nextRules.add(rules[index]);
    }

    return replacement.copyWith(
      rules: List.unmodifiable(nextRules),
      layerOverrides: List.unmodifiable([
        for (final override in replacement.layerOverrides)
          if ({for (final rule in nextRules) rule.id}.contains(override.ruleId))
            override,
      ]),
    );
  }

  /// Removes exact duplicate target tags across a materialized role mapping.
  /// Character identity rules are authoritative, so their stable appearance
  /// tags are reserved before accessory/body/clothing rules are processed.
  ScriptRolePromptReplacement deduplicateTargetOutputs(
    ScriptRolePromptReplacement replacement, {
    String forbiddenTarget = '',
  }) {
    final emittedKeys = <String>{};
    final forbiddenTargetKey = PromptTagProcessor.normalizeMatchKey(
      forbiddenTarget,
    );
    final identityRuleIds = {
      for (final rule in replacement.rules)
        if (_isCharacterIdentityRule(rule) &&
            rule.effectiveAction == ScriptPromptReplacementAction.replace &&
            rule.targetPrompt.trim().isNotEmpty)
          rule.id,
    };
    for (final rule in replacement.rules) {
      if (!identityRuleIds.contains(rule.id)) continue;
      for (final tag in _splitTargetPromptTags(rule.targetPrompt)) {
        final key = PromptTagProcessor.normalizeMatchKey(tag);
        if (key.isNotEmpty) emittedKeys.add(key);
      }
    }

    final rules = <ScriptPromptReplacementRule>[];
    for (final rule in replacement.rules) {
      if (identityRuleIds.contains(rule.id)) {
        rules.add(rule);
        continue;
      }
      if (rule.effectiveAction != ScriptPromptReplacementAction.replace ||
          rule.targetPrompt.trim().isEmpty) {
        rules.add(rule);
        continue;
      }
      final keptTags = <String>[];
      for (final tag in _splitTargetPromptTags(rule.targetPrompt)) {
        final key = PromptTagProcessor.normalizeMatchKey(tag);
        if (key.isEmpty ||
            (forbiddenTargetKey.isNotEmpty && key == forbiddenTargetKey) ||
            !emittedKeys.add(key)) {
          continue;
        }
        keptTags.add(tag);
      }
      if (keptTags.isEmpty) {
        rules.add(
          rule.copyWith(
            action: ScriptPromptReplacementAction.delete,
            targetPrompt: '',
            targetWeightMultiplier: null,
            manualPhrase: '',
          ),
        );
      } else {
        rules.add(rule.copyWith(targetPrompt: keptTags.join(', ')));
      }
    }
    return replacement.copyWith(rules: List.unmodifiable(rules));
  }

  RoleMappingProfile withAppliedCompanionTerms({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement sourceReplacement,
    required Iterable<RoleMappingProfileApplySelection> selections,
    required DateTime now,
  }) {
    final sourceTerms = _includedTermsById(sourceReplacement.rules);
    var changed = false;
    final blocks = [
      for (final block in profile.blocks)
        _blockWithAppliedCompanionTerms(
          block,
          selections.where((selection) => selection.blockId == block.id),
          sourceTerms,
          () => changed = true,
        ),
    ];
    if (!changed) return profile;
    final updatedById = {for (final block in blocks) block.id: block};
    return profile.copyWith(
      layers: List.unmodifiable([
        for (final layer in profile.effectiveLayers)
          layer.copyWith(
            blocks: List.unmodifiable([
              for (final block in layer.blocks) updatedById[block.id] ?? block,
            ]),
            recognitionSignature: _recognitionSignatureForProfileBlocks([
              for (final block in layer.blocks) updatedById[block.id] ?? block,
            ]),
          ),
      ]),
      updatedAt: now.toUtc(),
    );
  }

  RoleMappingProfile learnReplacement({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement before,
    required ScriptRolePromptReplacement after,
    required DateTime now,
    String targetCharacterNameSnapshot = '',
    RoleAssembly? assembly,
  }) {
    final nextBlocks = profile.blocks.toList();
    final beforeRuleById = {
      for (final rule in before.rules) rule.id: rule,
    };
    final claimedBlockIds = <String>{};

    for (final rule in after.rules.where((rule) => rule.hasEffect)) {
      final exactIndex = _blockIndexWithSignature(nextBlocks, rule);
      final beforeRule = beforeRuleById[rule.id];
      final previousIndex = beforeRule == null
          ? -1
          : _blockIndexWithSignature(nextBlocks, beforeRule);
      final index = exactIndex >= 0 ? exactIndex : previousIndex;
      if (index >= 0) {
        final current = nextBlocks[index];
        nextBlocks[index] = _blockFromRulePreservingDetection(
          rule,
          current,
        ).copyWith(id: current.id);
        claimedBlockIds.add(current.id);
      } else {
        final added = _blockFromRuleWithStableIds(
          rule,
          existingIds: {
            for (final block in nextBlocks) block.id,
          },
        );
        nextBlocks.add(added);
        claimedBlockIds.add(added.id);
      }
    }

    final afterRuleIds = {for (final rule in after.rules) rule.id};
    final afterKeys = {
      for (final rule in after.rules.where((rule) => rule.hasEffect))
        ..._signatureForRule(rule),
    };
    nextBlocks.removeWhere((block) {
      if (claimedBlockIds.contains(block.id)) return false;
      final matchingBeforeRule = before.rules
          .where(
            (rule) =>
                !afterRuleIds.contains(rule.id) &&
                _sameSignature(
                    block.normalizedTermKeys, _signatureForRule(rule)),
          )
          .firstOrNull;
      if (matchingBeforeRule == null) return false;
      return block.normalizedTermKeys.isNotEmpty &&
          afterKeys.containsAll(block.normalizedTermKeys);
    });

    return profile.copyWith(
      targetCharacterId: after.targetCharacterId,
      targetCharacterNameSnapshot: targetCharacterNameSnapshot.trim().isEmpty
          ? profile.targetCharacterNameSnapshot
          : targetCharacterNameSnapshot.trim(),
      targetIdentityPrompt: after.targetIdentityPrompt.trim().isEmpty
          ? profile.targetIdentityPrompt
          : after.targetIdentityPrompt,
      layers: _profileLayersWithLearnedBlocks(
        profile: profile,
        replacement: after,
        assembly: assembly,
        blocks: List.unmodifiable(nextBlocks),
      ),
      updatedAt: now.toUtc(),
    );
  }

  List<RoleMappingProfileDeletionPrompt> deletionPrompts({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement before,
    required ScriptRolePromptReplacement after,
    RoleAssembly? beforeAssembly,
    RoleAssembly? afterAssembly,
  }) {
    final prompts = <RoleMappingProfileDeletionPrompt>[];
    if (before.targetIdentityPrompt.trim().isNotEmpty &&
        after.targetIdentityPrompt.trim().isEmpty &&
        profile.targetIdentityPrompt.trim().isNotEmpty) {
      prompts.add(
        RoleMappingProfileDeletionPrompt(
          profileId: profile.id,
          profileName: profile.name,
          sourceRoleId: after.sourceRoleId,
          kind: RoleMappingProfileDeletionKind.identity,
          label: '角色身份',
        ),
      );
    }
    final afterById = {for (final rule in after.rules) rule.id: rule};
    for (final beforeRule in before.rules.where((rule) => rule.hasEffect)) {
      final afterRule = afterById[beforeRule.id];
      if (afterRule != null && afterRule.hasEffect) continue;
      final blockIndex = _blockIndexWithSignature(profile.blocks, beforeRule);
      if (blockIndex < 0) continue;
      final block = profile.blocks[blockIndex];
      prompts.add(
        RoleMappingProfileDeletionPrompt(
          profileId: profile.id,
          profileName: profile.name,
          sourceRoleId: after.sourceRoleId,
          kind: RoleMappingProfileDeletionKind.block,
          blockId: block.id,
          label: block.terms.map((term) => term.text).join(', '),
        ),
      );
    }
    final beforeAssignments = layerService
        .resolve(
          replacement: before,
          assembly: beforeAssembly ?? afterAssembly,
        )
        .assignmentsByRuleId;
    final afterAssignments = layerService
        .resolve(
          replacement: after,
          assembly: afterAssembly ?? beforeAssembly,
        )
        .assignmentsByRuleId;
    for (final beforeRule in before.rules.where((rule) => rule.hasEffect)) {
      final afterRule = afterById[beforeRule.id];
      if (afterRule == null || !afterRule.hasEffect) {
        continue;
      }
      final beforeLayerId = beforeAssignments[beforeRule.id]?.layerId;
      final afterLayerId = afterAssignments[afterRule.id]?.layerId;
      if (beforeLayerId == null ||
          afterLayerId == null ||
          beforeLayerId == afterLayerId) {
        continue;
      }
      final blockIndex = _blockIndexWithSignature(profile.blocks, beforeRule);
      if (blockIndex < 0) {
        continue;
      }
      final block = profile.blocks[blockIndex];
      if (prompts.any((prompt) => prompt.blockId == block.id)) {
        continue;
      }
      prompts.add(
        RoleMappingProfileDeletionPrompt(
          profileId: profile.id,
          profileName: profile.name,
          sourceRoleId: after.sourceRoleId,
          kind: RoleMappingProfileDeletionKind.layerMove,
          blockId: block.id,
          label: block.terms.map((term) => term.text).join(', '),
        ),
      );
    }
    return List.unmodifiable(prompts);
  }

  RoleMappingProfile resolveDeletion({
    required RoleMappingProfile profile,
    required RoleMappingProfileDeletionPrompt prompt,
    required DateTime now,
  }) {
    if (prompt.kind == RoleMappingProfileDeletionKind.identity) {
      return profile.copyWith(
        targetIdentityPrompt: '',
        updatedAt: now.toUtc(),
      );
    }
    return profile.copyWith(
      layers: List.unmodifiable([
        for (final layer in profile.effectiveLayers)
          layer.copyWith(
            blocks: List.unmodifiable([
              for (final block in layer.blocks)
                if (block.id != prompt.blockId) block,
            ]),
            recognitionSignature: _recognitionSignatureForProfileBlocks([
              for (final block in layer.blocks)
                if (block.id != prompt.blockId) block,
            ]),
          ),
      ]),
      updatedAt: now.toUtc(),
    );
  }

  List<RoleMappingProfileLayerApplyPreview> _layerPreviews({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement replacement,
    RoleAssembly? assembly,
  }) {
    final current = layerService.resolve(
      replacement: replacement,
      assembly: assembly,
    );
    final ruleById = {for (final rule in replacement.rules) rule.id: rule};
    final signatureByCurrentLayerId = <String, Set<String>>{
      for (final layer in current.layers)
        layer.id: _signatureForRules([
          for (final ruleId in layer.ruleIds)
            if (ruleById[ruleId] != null) ruleById[ruleId]!,
        ]),
    };
    final preliminary = <RoleMappingProfileLayerApplyPreview>[];
    for (final layer in profile.effectiveLayers) {
      if (layer.kind == RoleMappingProfileLayerKind.shared) {
        preliminary.add(
          RoleMappingProfileLayerApplyPreview(
            layer: layer,
            status: RoleMappingProfileLayerMatchStatus.matched,
            matchedCurrentLayerId: scriptRoleReplacementSharedLayerId,
            candidateCurrentLayerIds: const [
              scriptRoleReplacementSharedLayerId,
            ],
            selectedByDefault: true,
          ),
        );
        continue;
      }
      if (layer.kind == RoleMappingProfileLayerKind.pending) {
        preliminary.add(
          RoleMappingProfileLayerApplyPreview(
            layer: layer,
            status: RoleMappingProfileLayerMatchStatus.matched,
            matchedCurrentLayerId: scriptRoleReplacementPendingLayerId,
            candidateCurrentLayerIds: const [
              scriptRoleReplacementPendingLayerId,
            ],
            selectedByDefault: true,
          ),
        );
        continue;
      }

      final scores = <String, int>{};
      for (final currentLayer in current.layers.where(
        (entry) => entry.kind == ScriptRoleReplacementRuleLayerKind.stage,
      )) {
        scores[currentLayer.id] = layer.recognitionSignature
            .toSet()
            .intersection(
              signatureByCurrentLayerId[currentLayer.id] ?? const {},
            )
            .length;
      }
      final highestScore = scores.values.fold<int>(
        0,
        (highest, score) => math.max(highest, score),
      );
      final candidates = [
        for (final entry in scores.entries)
          if (entry.value == highestScore && highestScore > 0) entry.key,
      ];
      preliminary.add(
        RoleMappingProfileLayerApplyPreview(
          layer: layer,
          status: candidates.length == 1
              ? RoleMappingProfileLayerMatchStatus.matched
              : candidates.isEmpty
                  ? RoleMappingProfileLayerMatchStatus.unmatched
                  : RoleMappingProfileLayerMatchStatus.ambiguous,
          matchedCurrentLayerId:
              candidates.length == 1 ? candidates.single : '',
          candidateCurrentLayerIds: List.unmodifiable(candidates),
          selectedByDefault: candidates.length == 1,
        ),
      );
    }

    final claimsByCurrentLayerId = <String, int>{};
    for (final preview in preliminary.where(
      (entry) =>
          entry.layer.kind == RoleMappingProfileLayerKind.stage &&
          entry.status == RoleMappingProfileLayerMatchStatus.matched,
    )) {
      claimsByCurrentLayerId.update(
        preview.matchedCurrentLayerId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return List.unmodifiable([
      for (final preview in preliminary)
        if (preview.layer.kind == RoleMappingProfileLayerKind.stage &&
            (claimsByCurrentLayerId[preview.matchedCurrentLayerId] ?? 0) > 1)
          RoleMappingProfileLayerApplyPreview(
            layer: preview.layer,
            status: RoleMappingProfileLayerMatchStatus.conflict,
            matchedCurrentLayerId: preview.matchedCurrentLayerId,
            candidateCurrentLayerIds: preview.candidateCurrentLayerIds,
          )
        else
          preview,
    ]);
  }

  RoleMappingProfileLayerApplySelection? _automaticLayerSelection(
    RoleMappingProfileLayerApplyPreview? preview,
  ) {
    if (preview == null ||
        preview.status != RoleMappingProfileLayerMatchStatus.matched ||
        preview.matchedCurrentLayerId.isEmpty) {
      return null;
    }
    if (preview.matchedCurrentLayerId == scriptRoleReplacementSharedLayerId) {
      return RoleMappingProfileLayerApplySelection(
        profileLayerId: preview.layer.id,
        targetKind: ScriptRoleReplacementRuleLayerKind.shared,
      );
    }
    if (preview.matchedCurrentLayerId == scriptRoleReplacementPendingLayerId) {
      return RoleMappingProfileLayerApplySelection(
        profileLayerId: preview.layer.id,
        targetKind: ScriptRoleReplacementRuleLayerKind.pending,
      );
    }
    const stagePrefix = 'stage:';
    if (preview.matchedCurrentLayerId.startsWith(stagePrefix)) {
      return RoleMappingProfileLayerApplySelection(
        profileLayerId: preview.layer.id,
        targetKind: ScriptRoleReplacementRuleLayerKind.stage,
        targetStageId:
            preview.matchedCurrentLayerId.substring(stagePrefix.length),
      );
    }
    return null;
  }

  List<RoleMappingProfileLayer> _profileLayersFromReplacement({
    required ScriptRolePromptReplacement replacement,
    RoleAssembly? assembly,
  }) {
    final resolved = layerService.resolve(
      replacement: replacement,
      assembly: assembly,
    );
    final ruleById = {for (final rule in replacement.rules) rule.id: rule};
    final existingBlockIds = <String>{};
    return List.unmodifiable([
      for (final layer in resolved.layers)
        () {
          final rules = [
            for (final ruleId in layer.ruleIds)
              if (ruleById[ruleId] != null) ruleById[ruleId]!,
          ];
          return RoleMappingProfileLayer(
            id: layer.id,
            kind: _profileLayerKind(layer.kind),
            displayName: layer.label,
            recognitionSignature:
                List.unmodifiable(_signatureForRules(rules).toList()..sort()),
            blocks: _blocksFromRules(
              rules,
              existingIds: existingBlockIds,
            ),
          );
        }(),
    ]);
  }

  List<RoleMappingProfileLayer> _profileLayersWithLearnedBlocks({
    required RoleMappingProfile profile,
    required ScriptRolePromptReplacement replacement,
    required List<RoleMappingProfileBlock> blocks,
    RoleAssembly? assembly,
  }) {
    final resolved = layerService.resolve(
      replacement: replacement,
      assembly: assembly,
    );
    final ruleById = {for (final rule in replacement.rules) rule.id: rule};
    final claimedBlockIds = <String>{};
    final nextLayers = <RoleMappingProfileLayer>[];
    for (final layer in resolved.layers) {
      final rules = [
        for (final ruleId in layer.ruleIds)
          if (ruleById[ruleId] != null) ruleById[ruleId]!,
      ];
      final layerBlocks = <RoleMappingProfileBlock>[];
      for (final rule in rules.where((rule) => rule.hasEffect)) {
        final block = blocks
            .where(
              (candidate) =>
                  !claimedBlockIds.contains(candidate.id) &&
                  _sameSignature(
                    candidate.normalizedTermKeys,
                    _signatureForRule(rule),
                  ),
            )
            .firstOrNull;
        if (block != null) {
          claimedBlockIds.add(block.id);
          layerBlocks.add(block);
        }
      }
      nextLayers.add(
        RoleMappingProfileLayer(
          id: layer.id,
          kind: _profileLayerKind(layer.kind),
          displayName: layer.label,
          recognitionSignature:
              List.unmodifiable(_signatureForRules(rules).toList()..sort()),
          blocks: List.unmodifiable(layerBlocks),
        ),
      );
    }

    final nextLayerIndexById = <String, int>{
      for (var index = 0; index < nextLayers.length; index += 1)
        nextLayers[index].id: index,
    };
    for (final oldLayer in profile.effectiveLayers) {
      final rememberedBlocks = [
        for (final block in oldLayer.blocks)
          if (blocks.any((candidate) => candidate.id == block.id) &&
              !claimedBlockIds.contains(block.id))
            blocks.firstWhere((candidate) => candidate.id == block.id),
      ];
      if (rememberedBlocks.isEmpty) {
        continue;
      }
      final existingIndex = nextLayerIndexById[oldLayer.id];
      if (existingIndex == null) {
        nextLayerIndexById[oldLayer.id] = nextLayers.length;
        nextLayers.add(
          oldLayer.copyWith(
            blocks: List.unmodifiable(rememberedBlocks),
            recognitionSignature:
                _recognitionSignatureForProfileBlocks(rememberedBlocks),
          ),
        );
        continue;
      }
      final existing = nextLayers[existingIndex];
      final combinedBlocks = [
        ...existing.blocks,
        ...rememberedBlocks,
      ];
      nextLayers[existingIndex] = existing.copyWith(
        blocks: List.unmodifiable(combinedBlocks),
        recognitionSignature:
            _recognitionSignatureForProfileBlocks(combinedBlocks),
      );
    }
    return List.unmodifiable(nextLayers);
  }

  RoleMappingProfileLayerKind _profileLayerKind(
    ScriptRoleReplacementRuleLayerKind kind,
  ) {
    return switch (kind) {
      ScriptRoleReplacementRuleLayerKind.shared =>
        RoleMappingProfileLayerKind.shared,
      ScriptRoleReplacementRuleLayerKind.stage =>
        RoleMappingProfileLayerKind.stage,
      ScriptRoleReplacementRuleLayerKind.pending =>
        RoleMappingProfileLayerKind.pending,
    };
  }

  RoleMappingApplyPreviewEntry _previewEntry({
    required RoleMappingProfileBlock block,
    required String profileLayerId,
    required ScriptRolePromptReplacement replacement,
    required Map<String, ScriptPromptReplacementTerm> currentTerms,
    required Set<String> presentKeys,
    required List<String> availableTermIds,
    required List<String> candidateTermIds,
  }) {
    final detectionKeys = block.detectionKeys;
    final triggered = switch (block.matchMode) {
      ScriptPromptReplacementMatchMode.any =>
        detectionKeys.isNotEmpty && detectionKeys.any(presentKeys.contains),
      ScriptPromptReplacementMatchMode.all =>
        detectionKeys.isNotEmpty && presentKeys.containsAll(detectionKeys),
      ScriptPromptReplacementMatchMode.anchor =>
        block.anchorTermKey.isNotEmpty &&
            detectionKeys.contains(block.anchorTermKey) &&
            presentKeys.contains(block.anchorTermKey),
    };
    if (!triggered) {
      return RoleMappingApplyPreviewEntry(
        block: block,
        profileLayerId: profileLayerId,
        status: RoleMappingApplyPreviewStatus.unmatched,
        availableTermIds: availableTermIds,
      );
    }

    final selectedTermIds = candidateTermIds
        .where(currentTerms.containsKey)
        .toList(growable: false);
    if (selectedTermIds.isEmpty) {
      return RoleMappingApplyPreviewEntry(
        block: block,
        profileLayerId: profileLayerId,
        status: RoleMappingApplyPreviewStatus.unmatched,
        availableTermIds: availableTermIds,
      );
    }
    final affectedRules = [
      for (final rule in replacement.rules)
        if (rule.sourceTerms.any(
          (term) => selectedTermIds.contains(term.id),
        ))
          rule,
    ];
    final pendingSplitRuleIds = [
      for (final rule in affectedRules)
        if (_includedTermIds(rule).any(selectedTermIds.contains) &&
            _includedTermIds(rule).any(
              (termId) => !selectedTermIds.contains(termId),
            ))
          rule.id,
    ];
    final pendingMergeRuleIds = affectedRules.length > 1
        ? affectedRules.map((rule) => rule.id).toList(growable: false)
        : const <String>[];
    final same = affectedRules.length == 1 &&
        _sameStringSet(
          _includedTermIds(affectedRules.single),
          selectedTermIds.toSet(),
        ) &&
        affectedRules.single.matchMode == block.matchMode &&
        _sameAnchor(affectedRules.single, block) &&
        _sameEffect(affectedRules.single, block);
    final conflict = affectedRules.any(
      (rule) => rule.hasEffect && !_sameEffect(rule, block),
    );
    final status = same
        ? RoleMappingApplyPreviewStatus.same
        : conflict
            ? RoleMappingApplyPreviewStatus.conflict
            : RoleMappingApplyPreviewStatus.matched;
    return RoleMappingApplyPreviewEntry(
      block: block,
      profileLayerId: profileLayerId,
      status: status,
      selectedTermIds: List.unmodifiable(selectedTermIds),
      availableTermIds: availableTermIds,
      affectedRuleIds:
          List.unmodifiable(affectedRules.map((rule) => rule.id).toList()),
      pendingSplitRuleIds: List.unmodifiable(pendingSplitRuleIds),
      pendingMergeRuleIds: List.unmodifiable(pendingMergeRuleIds),
      // Choosing a profile is an explicit request to replace the current
      // target. A different existing target is therefore a deterministic
      // overwrite, not an unresolved match. Only genuinely ambiguous source
      // ownership should require manual confirmation.
      selectedByDefault: status == RoleMappingApplyPreviewStatus.matched ||
          status == RoleMappingApplyPreviewStatus.conflict,
    );
  }

  String _profileBlockKey(String layerId, String blockId) {
    return '$layerId\u001f$blockId';
  }

  bool _hasStrictCategoryMatch(
    RoleMappingProfileBlock block,
    PromptTagCategory sourceCategory,
  ) {
    final targetCategories = _targetCategoriesForBlock(block);
    if (targetCategories.isEmpty) return false;
    if (sourceCategory == PromptTagCategory.character) {
      return targetCategories.contains(PromptTagCategory.character);
    }
    if (sourceCategory == PromptTagCategory.upperBody ||
        sourceCategory == PromptTagCategory.upperClothing) {
      return targetCategories.any(
        (category) =>
            category == PromptTagCategory.upperBody ||
            category == PromptTagCategory.upperClothing,
      );
    }
    if (sourceCategory == PromptTagCategory.lowerBody ||
        sourceCategory == PromptTagCategory.lowerClothing) {
      return targetCategories.any(
        (category) =>
            category == PromptTagCategory.lowerBody ||
            category == PromptTagCategory.lowerClothing,
      );
    }
    if (sourceCategory == PromptTagCategory.accessory) {
      return targetCategories.contains(PromptTagCategory.accessory);
    }
    if (sourceCategory == PromptTagCategory.clothingState) {
      return targetCategories.any(
        (category) =>
            category == PromptTagCategory.clothingState ||
            category == PromptTagCategory.clothing,
      );
    }
    if (sourceCategory == PromptTagCategory.clothing) {
      return targetCategories.contains(PromptTagCategory.clothing);
    }
    return targetCategories.contains(sourceCategory);
  }

  Set<PromptTagCategory> _targetCategoriesForBlock(
    RoleMappingProfileBlock block,
  ) {
    if (block.targetCategories.isNotEmpty) {
      return block.targetCategories.toSet();
    }
    final inferred = <PromptTagCategory>{};
    for (final tag in _splitTargetPromptTags(block.targetPrompt)) {
      inferred.add(PromptTagClassifier.classify(tag).category);
    }
    return inferred;
  }

  List<ScriptPromptReplacementRule> _rulesWithAppliedBlock({
    required List<ScriptPromptReplacementRule> rules,
    required RoleMappingProfileBlock block,
    required Set<String> selectedTermIds,
    required String requestedAnchorTermId,
  }) {
    final selectedTerms = <ScriptPromptReplacementTerm>[];
    var insertionIndex = -1;
    final next = <ScriptPromptReplacementRule>[];
    final existingRuleIds = {for (final rule in rules) rule.id};

    for (final rule in rules) {
      final moving = [
        for (final term in rule.sourceTerms)
          if (selectedTermIds.contains(term.id) &&
              !rule.excludedTermIds.contains(term.id))
            term,
      ];
      if (moving.isEmpty) {
        next.add(rule);
        continue;
      }
      insertionIndex = insertionIndex < 0 ? next.length : insertionIndex;
      selectedTerms.addAll(moving);
      final remaining = [
        for (final term in rule.sourceTerms)
          if (!selectedTermIds.contains(term.id)) term,
      ];
      if (remaining.isEmpty) continue;
      next.add(
        rule.copyWith(
          sourceTerms: List.unmodifiable(remaining),
          excludedTermIds: [
            for (final id in rule.excludedTermIds)
              if (remaining.any((term) => term.id == id)) id,
          ],
          anchorTermId: remaining.any((term) => term.id == rule.anchorTermId)
              ? rule.anchorTermId
              : '',
        ),
      );
    }
    if (selectedTerms.isEmpty) return rules;

    final deduplicated = <ScriptPromptReplacementTerm>[];
    final seenIds = <String>{};
    for (final term in selectedTerms) {
      if (seenIds.add(term.id)) deduplicated.add(term);
    }
    var anchorTermId = '';
    if (block.matchMode == ScriptPromptReplacementMatchMode.anchor) {
      anchorTermId = requestedAnchorTermId.trim();
      if (anchorTermId.isEmpty) {
        anchorTermId = deduplicated
                .where(
                  (term) =>
                      normalizeRoleMappingProfileTerm(term.text) ==
                      block.anchorTermKey,
                )
                .firstOrNull
                ?.id ??
            '';
      }
      if (!deduplicated.any((term) => term.id == anchorTermId)) {
        throw ArgumentError(
          'Anchor mapping blocks require an anchor from the selected terms.',
        );
      }
    }
    final mergedRule = ScriptPromptReplacementRule(
      id: _uniqueRuleId(block.id, existingRuleIds),
      sourceTerms: List.unmodifiable(deduplicated),
      action: block.effectiveAction,
      matchMode: block.matchMode,
      targetPrompt: block.targetPrompt,
      targetWeightMultiplier: block.targetWeightMultiplier,
      anchorTermId: anchorTermId,
    );
    next.insert(
      insertionIndex < 0 ? next.length : insertionIndex,
      mergedRule,
    );
    return List.unmodifiable(next);
  }

  bool _isCharacterIdentityRule(ScriptPromptReplacementRule rule) {
    final excluded = rule.excludedTermIds.toSet();
    final terms = [
      for (final term in rule.sourceTerms)
        if (!excluded.contains(term.id)) term,
    ];
    return terms.isNotEmpty &&
        terms.any((term) => term.category == PromptTagCategory.character) &&
        terms.every(
          (term) =>
              term.category == PromptTagCategory.character ||
              term.category == PromptTagCategory.other,
        );
  }

  List<ScriptPromptReplacementRule> _rulesWithIdentityPromptToken({
    required Iterable<ScriptPromptReplacementRule> rules,
    required String token,
  }) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return List.unmodifiable(rules);
    return List.unmodifiable([
      for (final rule in rules)
        if (rule.sourceTerms.isNotEmpty &&
            rule.sourceTerms.every(
              (term) => term.category == PromptTagCategory.character,
            ) &&
            rule.action != ScriptPromptReplacementAction.delete)
          rule.copyWith(
            action: ScriptPromptReplacementAction.replace,
            targetPrompt: normalizedToken,
            targetWeightMultiplier: null,
            manualPhrase: '',
          )
        else
          rule,
    ]);
  }

  String _targetIdentityPromptWithToken(String prompt, String token) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return prompt;
    return _joinTargetPromptTags([normalizedToken, prompt]);
  }

  List<ScriptPromptReplacementRule> _rulesWithoutTargetOutputs(
    Iterable<ScriptPromptReplacementRule> rules,
  ) {
    return List.unmodifiable([
      for (final rule in rules)
        rule.copyWith(
          action: rule.action == ScriptPromptReplacementAction.delete
              ? ScriptPromptReplacementAction.delete
              : ScriptPromptReplacementAction.none,
          targetPrompt: '',
          targetWeightMultiplier: null,
          manualPhrase: '',
        ),
    ]);
  }

  RoleMappingProfileBlock _blockWithAppliedCompanionTerms(
    RoleMappingProfileBlock block,
    Iterable<RoleMappingProfileApplySelection> selections,
    Map<String, ScriptPromptReplacementTerm> sourceTerms,
    void Function() markChanged,
  ) {
    final incoming = <String, ScriptPromptReplacementTerm>{};
    for (final selection in selections) {
      for (final termId in selection.termIds) {
        final term = sourceTerms[termId];
        if (term == null) continue;
        incoming[normalizeRoleMappingProfileTerm(term.text)] = term;
      }
    }
    if (incoming.isEmpty) return block;
    final existingKeys = block.normalizedTermKeys;
    final termIds = {for (final term in block.terms) term.id};
    final additions = [
      for (final entry in incoming.entries)
        if (!existingKeys.contains(entry.key))
          RoleMappingProfileTerm(
            id: _stableId('term', entry.key, termIds),
            text: entry.value.text,
            normalizedKey: entry.key,
            autoDetect: true,
          ),
    ];
    if (additions.isEmpty) return block;
    markChanged();
    return block.copyWith(
      terms: List.unmodifiable([...block.terms, ...additions]),
    );
  }

  List<RoleMappingProfileBlock> _blocksFromRules(
    List<ScriptPromptReplacementRule> rules, {
    Set<String>? existingIds,
  }) {
    final blocks = <RoleMappingProfileBlock>[];
    final ids = existingIds ?? <String>{};
    for (final rule in rules.where((rule) => rule.hasEffect)) {
      final block = _blockFromRuleWithStableIds(rule, existingIds: ids);
      blocks.add(block);
      ids.add(block.id);
    }
    return List.unmodifiable(blocks);
  }

  RoleMappingProfileBlock _blockFromRuleWithStableIds(
    ScriptPromptReplacementRule rule, {
    required Set<String> existingIds,
  }) {
    final signature = _signatureForRule(rule).toList()..sort();
    final blockId = _stableId('block', signature.join('|'), existingIds);
    final termIds = <String>{};
    return RoleMappingProfileBlock(
      id: blockId,
      terms: [
        for (final term in rule.sourceTerms)
          RoleMappingProfileTerm(
            id: _stableId(
              'term',
              normalizeRoleMappingProfileTerm(term.text),
              termIds,
            ),
            text: term.text,
            normalizedKey: normalizeRoleMappingProfileTerm(term.text),
            autoDetect: true,
          ),
      ],
      matchMode: rule.matchMode,
      anchorTermKey: _anchorKey(rule),
      action: rule.effectiveAction,
      targetPrompt: rule.targetPrompt,
      targetWeightMultiplier: rule.targetWeightMultiplier,
    );
  }

  RoleMappingProfileBlock _blockFromRulePreservingDetection(
    ScriptPromptReplacementRule rule,
    RoleMappingProfileBlock current,
  ) {
    final detectionByKey = {
      for (final term in current.terms) term.matchKey: term.autoDetect,
    };
    final existingTermIds = <String>{};
    return RoleMappingProfileBlock(
      id: current.id,
      terms: [
        for (final term in rule.sourceTerms)
          RoleMappingProfileTerm(
            id: _stableId(
              'term',
              normalizeRoleMappingProfileTerm(term.text),
              existingTermIds,
            ),
            text: term.text,
            normalizedKey: normalizeRoleMappingProfileTerm(term.text),
            autoDetect:
                detectionByKey[normalizeRoleMappingProfileTerm(term.text)] ??
                    true,
          ),
      ],
      matchMode: rule.matchMode,
      anchorTermKey: _anchorKey(rule),
      action: rule.effectiveAction,
      targetPrompt: rule.targetPrompt,
      targetWeightMultiplier: rule.targetWeightMultiplier,
    );
  }

  int _blockIndexWithSignature(
    List<RoleMappingProfileBlock> blocks,
    ScriptPromptReplacementRule rule,
  ) {
    final signature = _signatureForRule(rule);
    return blocks.indexWhere(
      (block) => _sameSignature(block.normalizedTermKeys, signature),
    );
  }

  Set<String> _characterTargetTagKeys(CharacterEntry character) {
    final tags = <String>[
      ...character.anchorTags,
      ...character.identityTags,
      ..._viewVariantTexts(character.traits),
      for (final outfit in character.outfits) ...[
        ..._viewVariantTexts(outfit.tags),
        ...outfit.partTags.upperBodyTags,
        ...outfit.partTags.upperClothingTags,
        ...outfit.partTags.lowerBodyTags,
        ...outfit.partTags.lowerClothingTags,
        ...outfit.partTags.weaponTags,
        outfit.negativePrompt,
      ],
    ];
    return {
      for (final tag in tags)
        for (final fragment in _splitTargetPromptTags(tag))
          PromptTagProcessor.normalizeMatchKey(fragment),
    }..remove('');
  }

  Iterable<String> _viewVariantTexts(ViewVariantTexts texts) sync* {
    yield texts.frontFull;
    if (texts.frontCowboy != null) yield texts.frontCowboy!;
    if (texts.frontUpper != null) yield texts.frontUpper!;
    if (texts.frontLower != null) yield texts.frontLower!;
    if (texts.backFull != null) yield texts.backFull!;
    if (texts.backCowboy != null) yield texts.backCowboy!;
    if (texts.backUpper != null) yield texts.backUpper!;
    if (texts.backLower != null) yield texts.backLower!;
  }

  bool _isForeignTargetTag(
    String key,
    Set<String> targetKeys,
    Set<String> foreignKeys,
  ) {
    if (key.isEmpty) return false;
    if (targetKeys.contains(key)) return false;
    if (key.contains('hood') &&
        targetKeys.any((targetKey) => targetKey.contains('hood'))) {
      return false;
    }
    if (foreignKeys.contains(key)) return true;
    // Some old mapping profiles used a shortened display alias such as
    // "animal hood" while the character card stored "animal ear hood".
    return key.contains('hood') &&
        foreignKeys.any((foreignKey) => foreignKey.contains('hood'));
  }

  List<String> _splitTargetPromptTags(String text) {
    return PromptTagProcessor.splitWorkshopTags(text)
        .map(
          (tag) => PromptTagProcessor.cleanTagDisplay(
            tag,
            removeWeights: false,
          ).trim(),
        )
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  String _joinTargetPromptTags(Iterable<String> prompts) {
    final seen = <String>{};
    final result = <String>[];
    for (final prompt in prompts) {
      for (final tag in _splitTargetPromptTags(prompt)) {
        final key = PromptTagProcessor.normalizeMatchKey(tag);
        if (key.isNotEmpty && seen.add(key)) result.add(tag);
      }
    }
    return result.join(', ');
  }
}

Map<String, ScriptPromptReplacementTerm> _includedTermsById(
  List<ScriptPromptReplacementRule> rules,
) {
  return {
    for (final rule in rules)
      for (final term in rule.sourceTerms)
        if (!rule.excludedTermIds.contains(term.id)) term.id: term,
  };
}

Set<String> _signatureForRule(ScriptPromptReplacementRule rule) {
  return {
    for (final term in rule.sourceTerms)
      if (!rule.excludedTermIds.contains(term.id))
        normalizeRoleMappingProfileTerm(term.text),
  };
}

Set<String> _signatureForRules(
  Iterable<ScriptPromptReplacementRule> rules,
) {
  return {
    for (final rule in rules) ..._signatureForRule(rule),
  };
}

List<String> _recognitionSignatureForProfileBlocks(
  Iterable<RoleMappingProfileBlock> blocks,
) {
  final signature = <String>{
    for (final block in blocks) ...block.detectionKeys,
  };
  final result = signature.toList()..sort();
  return List.unmodifiable(result);
}

bool _sameSignature(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

Set<String> _includedTermIds(ScriptPromptReplacementRule rule) {
  return {
    for (final term in rule.sourceTerms)
      if (!rule.excludedTermIds.contains(term.id)) term.id,
  };
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

bool _sameAnchor(
  ScriptPromptReplacementRule rule,
  RoleMappingProfileBlock block,
) {
  if (block.matchMode != ScriptPromptReplacementMatchMode.anchor) return true;
  return _anchorKey(rule) == block.anchorTermKey;
}

bool _sameEffect(
  ScriptPromptReplacementRule rule,
  RoleMappingProfileBlock block,
) {
  return rule.effectiveAction == block.effectiveAction &&
      rule.targetPrompt.trim() == block.targetPrompt.trim() &&
      _sameNullableDouble(
        rule.targetWeightMultiplier,
        block.targetWeightMultiplier,
      );
}

bool _sameNullableDouble(double? left, double? right) {
  if (left == null || right == null) return left == right;
  return (left - right).abs() < 0.000001;
}

String _anchorKey(ScriptPromptReplacementRule rule) {
  if (rule.anchorTermId.isEmpty) return '';
  return normalizeRoleMappingProfileTerm(
    rule.sourceTerms
            .where((term) => term.id == rule.anchorTermId)
            .firstOrNull
            ?.text ??
        '',
  );
}

String _uniqueRuleId(String blockId, Set<String> existingIds) {
  final base = 'profile-$blockId';
  if (!existingIds.contains(base)) return base;
  for (var index = 2;; index += 1) {
    final candidate = '$base-$index';
    if (!existingIds.contains(candidate)) return candidate;
  }
}

String _stableId(String prefix, String value, Set<String> existingIds) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final base = '$prefix-${hash.toRadixString(16).padLeft(8, '0')}';
  if (!existingIds.contains(base)) {
    existingIds.add(base);
    return base;
  }
  for (var index = 2; index < math.max(1000, existingIds.length + 2); index++) {
    final candidate = '$base-$index';
    if (existingIds.add(candidate)) return candidate;
  }
  throw StateError('Unable to allocate a stable role mapping profile id.');
}
