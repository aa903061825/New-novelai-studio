import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

typedef ScriptAiRoleStageLabeler = String Function(
  ScriptAiExtractedStage stage,
  int index,
);

class ScriptAiRoleAssemblyApplicationResult {
  final RecastMapping mapping;
  final bool changed;

  const ScriptAiRoleAssemblyApplicationResult({
    required this.mapping,
    required this.changed,
  });
}

class ScriptAiRoleAssemblyApplication {
  const ScriptAiRoleAssemblyApplication();

  ScriptAiRoleAssemblyApplicationResult apply({
    required RecastMapping mapping,
    required ScriptAiRoleExtraction extraction,
    required ScriptAiRoleStageLabeler stageLabelFor,
  }) {
    if (!extraction.isReady) {
      return ScriptAiRoleAssemblyApplicationResult(
        mapping: mapping,
        changed: false,
      );
    }

    final normalizedExtraction = extraction.collapseEquivalentStages();
    var changed = false;
    var roleAssembliesChanged = false;
    var nextAssemblies = mapping.roleAssemblies;

    void markRoleAssembliesChanged() {
      changed = true;
      roleAssembliesChanged = true;
    }

    if (normalizedExtraction.roles.isNotEmpty) {
      final rolesBySourceId = <String, ScriptAiExtractedRole>{
        for (final role in normalizedExtraction.roles)
          if (role.sourceRoleId.trim().isNotEmpty) role.sourceRoleId: role,
      };
      final coveredSourceRoleIds = _coveredSourceRoleIds(
        normalizedExtraction.roles,
      );
      final usedStageIds = <String>{
        for (final assembly in mapping.roleAssemblies)
          for (final stage in assembly.stages)
            if (_isUserAuthoredStage(stage)) stage.id,
      };
      final refreshedAssemblies = <RoleAssembly>[];
      final appliedRoleIds = <String>{};

      for (final assembly in mapping.roleAssemblies) {
        final role = rolesBySourceId[assembly.sourceRoleId];
        if (role == null) {
          if (_shouldKeepUnmatchedExistingAssembly(
            assembly,
            coveredSourceRoleIds,
          )) {
            refreshedAssemblies.add(assembly);
          } else {
            markRoleAssembliesChanged();
          }
          continue;
        }
        appliedRoleIds.add(role.sourceRoleId);
        final nextAssembly = _assemblyWithAiRoleExtraction(
          assembly: assembly,
          role: role,
          usedStageIds: usedStageIds,
          stageLabelFor: stageLabelFor,
        );
        if (assembly.displayLabel != nextAssembly.displayLabel ||
            assembly.sourceName != nextAssembly.sourceName ||
            !_roleAssemblySourceAppearancesEqual(
              assembly.sourceAppearances,
              nextAssembly.sourceAppearances,
            ) ||
            !_roleAssemblyStagesEqual(assembly.stages, nextAssembly.stages)) {
          markRoleAssembliesChanged();
        }
        refreshedAssemblies.add(nextAssembly);
      }

      for (final role in normalizedExtraction.roles) {
        final sourceRoleId = role.sourceRoleId.trim();
        if (!_shouldCreateAiRoleAssembly(role) ||
            appliedRoleIds.contains(sourceRoleId)) {
          continue;
        }
        final stages = _aiRoleExtractionStages(
          role: role,
          usedStageIds: usedStageIds,
          stageLabelFor: stageLabelFor,
        );
        if (stages.isEmpty) {
          continue;
        }
        markRoleAssembliesChanged();
        refreshedAssemblies.add(
          RoleAssembly(
            sourceRoleId: sourceRoleId,
            displayLabel: role.displayName.trim().isEmpty
                ? sourceRoleId
                : role.displayName,
            sourceName: role.displayName,
            sourceAppearances: _roleAssemblySourceAppearancesFromAi(role),
            stages: List.unmodifiable(stages),
          ),
        );
        appliedRoleIds.add(sourceRoleId);
      }
      nextAssemblies = List.unmodifiable(refreshedAssemblies);
    }

    final nextRolePromptReplacements = _rolePromptReplacementsFromAi(
      existingReplacements: mapping.rolePromptReplacements,
      roles: normalizedExtraction.roles,
    );
    final nextScenePromptReplacements = _scenePromptReplacementsFromAi(
      existingReplacements: mapping.scenePromptReplacements,
      sceneTerms: normalizedExtraction.sceneTerms,
    );
    if (!_rolePromptReplacementsEqual(
      mapping.rolePromptReplacements,
      nextRolePromptReplacements,
    )) {
      changed = true;
    }
    if (!_scenePromptReplacementsEqual(
      mapping.scenePromptReplacements,
      nextScenePromptReplacements,
    )) {
      changed = true;
    }

    if (!changed) {
      return ScriptAiRoleAssemblyApplicationResult(
        mapping: mapping,
        changed: false,
      );
    }
    var nextMapping = mapping.copyWith(
      roleAssemblies: nextAssemblies,
      rolePromptReplacements: nextRolePromptReplacements,
      scenePromptReplacements: nextScenePromptReplacements,
    );
    if (roleAssembliesChanged) {
      nextMapping = _mappingWithoutStaleLocalDefaultStages(nextMapping);
    }
    return ScriptAiRoleAssemblyApplicationResult(
      mapping: nextMapping,
      changed: true,
    );
  }

  List<ScriptRolePromptReplacement> _rolePromptReplacementsFromAi({
    required List<ScriptRolePromptReplacement> existingReplacements,
    required List<ScriptAiExtractedRole> roles,
  }) {
    final existingBySourceRoleId = <String, ScriptRolePromptReplacement>{};
    for (final replacement in existingReplacements) {
      final sourceRoleId = replacement.sourceRoleId.trim();
      if (sourceRoleId.isNotEmpty &&
          !existingBySourceRoleId.containsKey(sourceRoleId)) {
        existingBySourceRoleId[sourceRoleId] = replacement;
      }
    }

    final next = <ScriptRolePromptReplacement>[];
    final appliedSourceRoleIds = <String>{};
    for (final role in roles) {
      final sourceRoleId = role.sourceRoleId.trim();
      if (sourceRoleId.isEmpty) {
        continue;
      }
      final promptTerms = _nonEmptyPromptTerms(role.promptTerms);
      if (promptTerms.isEmpty) {
        continue;
      }
      final existing = existingBySourceRoleId[sourceRoleId];
      final sourcePreview = _sourcePreviewForPromptTerms(promptTerms);
      next.add(
        ScriptRolePromptReplacement(
          sourceRoleId: sourceRoleId,
          displayLabel:
              role.displayName.trim().isEmpty ? sourceRoleId : role.displayName,
          sourcePreview: sourcePreview.trim().isEmpty
              ? existing?.sourcePreview ?? ''
              : sourcePreview,
          targetCharacterId: existing?.targetCharacterId,
          targetIdentityPrompt: existing?.targetIdentityPrompt ?? '',
          rules: _promptReplacementRulesFromAiTerms(
            terms: promptTerms,
            existingRules: existing?.rules ?? const [],
            ruleIdFor: (term) =>
                _rolePromptReplacementRuleId(sourceRoleId, term),
          ),
        ),
      );
      appliedSourceRoleIds.add(sourceRoleId);
    }

    for (final existing in existingReplacements) {
      final sourceRoleId = existing.sourceRoleId.trim();
      if (appliedSourceRoleIds.contains(sourceRoleId)) {
        continue;
      }
      final preserved = _rolePromptReplacementWithOnlyUserState(existing);
      if (preserved != null) {
        next.add(preserved);
      }
    }
    return List.unmodifiable(next);
  }

  List<ScriptScenePromptReplacement> _scenePromptReplacementsFromAi({
    required List<ScriptScenePromptReplacement> existingReplacements,
    required List<ScriptAiExtractedPromptTerm> sceneTerms,
  }) {
    final promptTerms = _nonEmptyPromptTerms(sceneTerms);
    final existingAiReplacement =
        _existingAiManagedScenePromptReplacement(existingReplacements);
    if (promptTerms.isEmpty) {
      return List.unmodifiable([
        for (final replacement in existingReplacements)
          if (_scenePromptReplacementWithOnlyUserState(replacement)
              case final preserved?)
            preserved,
      ]);
    }

    final refreshedAiReplacement = ScriptScenePromptReplacement(
      id: _sceneAiPromptReplacementId,
      label: existingAiReplacement == null ||
              existingAiReplacement.label.trim().isEmpty
          ? 'Scene'
          : existingAiReplacement.label,
      rules: _promptReplacementRulesFromAiTerms(
        terms: promptTerms,
        existingRules: existingAiReplacement?.rules ?? const [],
        ruleIdFor: _scenePromptReplacementRuleId,
      ),
    );

    final next = <ScriptScenePromptReplacement>[];
    var addedAiReplacement = false;
    for (final replacement in existingReplacements) {
      if (_isAiManagedScenePromptReplacement(replacement)) {
        if (!addedAiReplacement) {
          next.add(refreshedAiReplacement);
          addedAiReplacement = true;
        }
        continue;
      }
      final preserved = _scenePromptReplacementWithOnlyUserState(replacement);
      if (preserved != null) {
        next.add(preserved);
      }
    }
    if (!addedAiReplacement) {
      next.add(refreshedAiReplacement);
    }
    return List.unmodifiable(next);
  }

  static const _sceneAiPromptReplacementId = 'scene-ai';

  ScriptScenePromptReplacement? _existingAiManagedScenePromptReplacement(
    List<ScriptScenePromptReplacement> replacements,
  ) {
    for (final replacement in replacements) {
      if (_isAiManagedScenePromptReplacement(replacement)) {
        return replacement;
      }
    }
    return null;
  }

  bool _isAiManagedScenePromptReplacement(
    ScriptScenePromptReplacement replacement,
  ) {
    return replacement.id.trim() == _sceneAiPromptReplacementId;
  }

  List<ScriptPromptReplacementRule> _promptReplacementRulesFromAiTerms({
    required List<ScriptAiExtractedPromptTerm> terms,
    required List<ScriptPromptReplacementRule> existingRules,
    required String Function(ScriptAiExtractedPromptTerm term) ruleIdFor,
  }) {
    final aiRulesById = <String, ScriptPromptReplacementRule>{};
    final aiRuleIdsByTermKey = <String, String>{};
    final aiTermsByKey = <String, ScriptPromptReplacementTerm>{};
    for (final term in terms) {
      final ruleId = ruleIdFor(term);
      if (ruleId.trim().isEmpty || aiRulesById.containsKey(ruleId)) {
        continue;
      }
      final replacementTerm = _promptReplacementTermFromAi(term);
      aiRulesById[ruleId] = ScriptPromptReplacementRule(
        id: ruleId,
        sourceTerms: List.unmodifiable([replacementTerm]),
      );
      for (final key in _promptReplacementTermKeys(
        id: replacementTerm.id,
        text: replacementTerm.text,
        category: replacementTerm.category,
      )) {
        aiRuleIdsByTermKey.putIfAbsent(key, () => ruleId);
        aiTermsByKey.putIfAbsent(key, () => replacementTerm);
      }
    }

    final existingRulesById = <String, ScriptPromptReplacementRule>{};
    for (final rule in existingRules) {
      if (!existingRulesById.containsKey(rule.id)) {
        existingRulesById[rule.id] = rule;
      }
    }

    final groupedRulesByClaimedRuleId = <String, ScriptPromptReplacementRule>{};
    final singleRulesByClaimedRuleId = <String, ScriptPromptReplacementRule>{};
    for (final rule in existingRules) {
      if (rule.sourceTerms.length == 1) {
        final claimedRuleId = _aiRuleIdForPromptReplacementTerm(
          rule.sourceTerms.single,
          aiRuleIdsByTermKey,
        );
        if (claimedRuleId != null) {
          singleRulesByClaimedRuleId.putIfAbsent(claimedRuleId, () => rule);
        }
        continue;
      }
      if (rule.sourceTerms.length < 2) {
        continue;
      }
      for (final term in rule.sourceTerms) {
        final claimedRuleId = _aiRuleIdForPromptReplacementTerm(
          term,
          aiRuleIdsByTermKey,
        );
        if (claimedRuleId != null) {
          groupedRulesByClaimedRuleId[claimedRuleId] = rule;
        }
      }
    }

    final next = <ScriptPromptReplacementRule>[];
    final appliedRuleIds = <String>{};
    final appliedExistingRuleIds = <String>{};
    final emittedGroupedRuleIds = <String>{};
    for (final term in terms) {
      final ruleId = ruleIdFor(term);
      if (ruleId.trim().isEmpty) {
        continue;
      }
      final groupedRule = groupedRulesByClaimedRuleId[ruleId];
      if (groupedRule != null) {
        appliedRuleIds.add(ruleId);
        if (emittedGroupedRuleIds.add(groupedRule.id)) {
          next.add(
            _promptReplacementRuleWithRefreshedSourceTerms(
              groupedRule,
              aiTermsByKey,
            ),
          );
          for (final groupedTerm in groupedRule.sourceTerms) {
            final claimedRuleId = _aiRuleIdForPromptReplacementTerm(
              groupedTerm,
              aiRuleIdsByTermKey,
            );
            if (claimedRuleId != null) {
              appliedRuleIds.add(claimedRuleId);
            }
          }
        }
        continue;
      }
      if (!appliedRuleIds.add(ruleId)) {
        continue;
      }
      final aiRule = aiRulesById[ruleId];
      if (aiRule == null) {
        continue;
      }
      final existing =
          existingRulesById[ruleId] ?? singleRulesByClaimedRuleId[ruleId];
      if (existing != null) {
        appliedExistingRuleIds.add(existing.id);
      }
      next.add(
        existing == null
            ? aiRule
            : existing.copyWith(sourceTerms: aiRule.sourceTerms),
      );
    }

    for (final existing in existingRules) {
      if (appliedRuleIds.contains(existing.id) ||
          appliedExistingRuleIds.contains(existing.id) ||
          emittedGroupedRuleIds.contains(existing.id)) {
        continue;
      }
      if (_isUserAuthoredPromptReplacementRule(existing)) {
        next.add(existing);
      }
    }
    return List.unmodifiable(next);
  }

  ScriptPromptReplacementRule _promptReplacementRuleWithRefreshedSourceTerms(
    ScriptPromptReplacementRule rule,
    Map<String, ScriptPromptReplacementTerm> aiTermsByKey,
  ) {
    return rule.copyWith(
      sourceTerms: List.unmodifiable([
        for (final term in rule.sourceTerms)
          _promptReplacementTermWithRefreshedAiMetadata(term, aiTermsByKey),
      ]),
    );
  }

  ScriptPromptReplacementTerm _promptReplacementTermWithRefreshedAiMetadata(
    ScriptPromptReplacementTerm term,
    Map<String, ScriptPromptReplacementTerm> aiTermsByKey,
  ) {
    for (final key in _promptReplacementTermKeys(
      id: term.id,
      text: term.text,
      category: term.category,
    )) {
      final aiTerm = aiTermsByKey[key];
      if (aiTerm != null) {
        return aiTerm;
      }
    }
    return term;
  }

  String? _aiRuleIdForPromptReplacementTerm(
    ScriptPromptReplacementTerm term,
    Map<String, String> aiRuleIdsByTermKey,
  ) {
    for (final key in _promptReplacementTermKeys(
      id: term.id,
      text: term.text,
      category: term.category,
    )) {
      final ruleId = aiRuleIdsByTermKey[key];
      if (ruleId != null) {
        return ruleId;
      }
    }
    return null;
  }

  List<String> _promptReplacementTermKeys({
    required String id,
    required String text,
    required PromptTagCategory category,
  }) {
    final keys = <String>[];
    final idKey = id.trim();
    if (idKey.isNotEmpty) {
      keys.add('id:$idKey');
    }
    final strictKey = _promptReplacementStrictTermKey(text, category);
    if (strictKey.isNotEmpty) {
      keys.add('text:$strictKey');
    }
    final compatibleKey = _promptReplacementCompatibleTermKey(text, category);
    if (compatibleKey.isNotEmpty && compatibleKey != strictKey) {
      keys.add('compat:$compatibleKey');
    }
    return keys;
  }

  String _promptReplacementStrictTermKey(
    String text,
    PromptTagCategory category,
  ) {
    final normalized = PromptTagProcessor.normalizeMatchKey(text);
    if (normalized.isEmpty) {
      return '';
    }
    return '${category.name}\u001f$normalized';
  }

  String _promptReplacementCompatibleTermKey(
    String text,
    PromptTagCategory category,
  ) {
    final normalized = PromptTagProcessor.normalizeMatchKey(text);
    if (normalized.isEmpty) {
      return '';
    }
    final categoryKey = switch (category) {
      PromptTagCategory.clothing ||
      PromptTagCategory.accessory ||
      PromptTagCategory.clothingState ||
      PromptTagCategory.upperClothing ||
      PromptTagCategory.lowerClothing =>
        'legacy-clothing-compatible',
      _ => category.name,
    };
    return '$categoryKey\u001f$normalized';
  }

  String _promptTermStrictKey(
    String text,
    PromptTagCategory category,
  ) {
    final normalized = PromptTagProcessor.normalizeMatchKey(text);
    if (normalized.isEmpty) {
      return '';
    }
    return '${category.name}\u001f$normalized';
  }

  String _promptTermMergeKey(
    Map<String, ScriptAiExtractedPromptTerm> byKey,
    String text,
    PromptTagCategory category,
  ) {
    final normalized = PromptTagProcessor.normalizeMatchKey(text);
    if (normalized.isEmpty) {
      return '';
    }
    final strictKey = '${category.name}\u001f$normalized';
    if (byKey.containsKey(strictKey)) {
      return strictKey;
    }
    if (_isRefinedClothingCategory(category)) {
      final legacyKey = '${PromptTagCategory.clothing.name}\u001f$normalized';
      return byKey.containsKey(legacyKey) ? legacyKey : '';
    }
    if (category == PromptTagCategory.clothing) {
      final refinedKeys = [
        PromptTagCategory.accessory,
        PromptTagCategory.clothingState,
      ]
          .map((refined) => '${refined.name}\u001f$normalized')
          .where(byKey.containsKey)
          .toList();
      return refinedKeys.length == 1 ? refinedKeys.single : '';
    }
    return '';
  }

  ScriptAiExtractedPromptTerm _preferredPromptTerm(
    ScriptAiExtractedPromptTerm left,
    ScriptAiExtractedPromptTerm right,
  ) {
    final preferred = _promptTermCategoryPreference(right.category) >=
            _promptTermCategoryPreference(left.category)
        ? right
        : left;
    final fallback = identical(preferred, right) ? left : right;
    return ScriptAiExtractedPromptTerm(
      id: preferred.id.trim().isNotEmpty ? preferred.id : fallback.id,
      text: preferred.text.trim().isNotEmpty ? preferred.text : fallback.text,
      category: preferred.category,
      sourcePhrase: preferred.sourcePhrase.trim().isNotEmpty
          ? preferred.sourcePhrase
          : fallback.sourcePhrase,
      sourceLocation: preferred.sourceLocation.trim().isNotEmpty
          ? preferred.sourceLocation
          : fallback.sourceLocation,
      frameIndexes: List.unmodifiable(
        ({...left.frameIndexes, ...right.frameIndexes}.toList()..sort()),
      ),
    );
  }

  int _promptTermCategoryPreference(PromptTagCategory category) {
    return switch (category) {
      PromptTagCategory.accessory || PromptTagCategory.clothingState => 1,
      PromptTagCategory.clothing => 0,
      _ => 0,
    };
  }

  bool _isRefinedClothingCategory(PromptTagCategory category) {
    return category == PromptTagCategory.accessory ||
        category == PromptTagCategory.clothingState;
  }

  ScriptPromptReplacementTerm _promptReplacementTermFromAi(
    ScriptAiExtractedPromptTerm term,
  ) {
    return ScriptPromptReplacementTerm(
      id: term.id.trim().isEmpty
          ? 'term-${_safePromptTermTextId(term.text)}'
          : term.id.trim(),
      text: term.text.trim(),
      category: term.category,
      sourcePhrase: term.sourcePhrase.trim(),
      sourceLocation: term.sourceLocation.trim(),
      frameIndexes: List.unmodifiable(term.frameIndexes),
    );
  }

  ScriptRolePromptReplacement? _rolePromptReplacementWithOnlyUserState(
    ScriptRolePromptReplacement replacement,
  ) {
    final userRules = [
      for (final rule in replacement.rules)
        if (_isUserAuthoredPromptReplacementRule(rule)) rule,
    ];
    final hasUserTarget =
        replacement.targetCharacterId?.trim().isNotEmpty == true ||
            replacement.targetIdentityPrompt.trim().isNotEmpty;
    if (!hasUserTarget && userRules.isEmpty) {
      return null;
    }
    return replacement.copyWith(rules: List.unmodifiable(userRules));
  }

  ScriptScenePromptReplacement? _scenePromptReplacementWithOnlyUserState(
    ScriptScenePromptReplacement replacement,
  ) {
    final userRules = [
      for (final rule in replacement.rules)
        if (_isUserAuthoredPromptReplacementRule(rule)) rule,
    ];
    if (userRules.isEmpty) {
      return null;
    }
    return replacement.copyWith(rules: List.unmodifiable(userRules));
  }

  bool _isUserAuthoredPromptReplacementRule(
    ScriptPromptReplacementRule rule,
  ) {
    return rule.sourceTerms.length > 1 ||
        rule.targetPrompt.trim().isNotEmpty ||
        rule.manualPhrase.trim().isNotEmpty ||
        rule.action != ScriptPromptReplacementAction.none ||
        rule.matchMode != ScriptPromptReplacementMatchMode.any ||
        rule.excludedTermIds.isNotEmpty ||
        rule.anchorTermId.trim().isNotEmpty;
  }

  List<ScriptAiExtractedPromptTerm> _nonEmptyPromptTerms(
    List<ScriptAiExtractedPromptTerm> terms,
  ) {
    final byKey = <String, ScriptAiExtractedPromptTerm>{};
    final order = <String>[];
    for (final term in terms) {
      if (term.text.trim().isEmpty) {
        continue;
      }
      final strictKey = _promptTermStrictKey(term.text, term.category);
      if (strictKey.isEmpty) {
        continue;
      }
      final existingKey = _promptTermMergeKey(
        byKey,
        term.text,
        term.category,
      );
      if (existingKey.isEmpty) {
        byKey[strictKey] = term;
        order.add(strictKey);
        continue;
      }
      final merged = _preferredPromptTerm(byKey[existingKey]!, term);
      final mergedKey = _promptTermStrictKey(merged.text, merged.category);
      if (mergedKey.isNotEmpty && mergedKey != existingKey) {
        byKey.remove(existingKey);
        final index = order.indexOf(existingKey);
        if (index >= 0) {
          order[index] = mergedKey;
        } else if (!order.contains(mergedKey)) {
          order.add(mergedKey);
        }
      }
      byKey[mergedKey.isEmpty ? existingKey : mergedKey] = merged;
    }
    return List.unmodifiable([
      for (final key in order) byKey[key]!,
    ]);
  }

  String _rolePromptReplacementRuleId(
    String sourceRoleId,
    ScriptAiExtractedPromptTerm term,
  ) {
    final termId = term.id.trim();
    if (termId.isNotEmpty) {
      return 'role-$sourceRoleId-$termId';
    }
    return 'role-$sourceRoleId-term-${_safePromptTermTextId(term.text)}';
  }

  String _scenePromptReplacementRuleId(ScriptAiExtractedPromptTerm term) {
    final termId = term.id.trim();
    if (termId.isNotEmpty) {
      return 'scene-$termId';
    }
    return 'scene-term-${_safePromptTermTextId(term.text)}';
  }

  String _sourcePreviewForPromptTerms(
    List<ScriptAiExtractedPromptTerm> terms,
  ) {
    final seen = <String>{};
    final parts = <String>[];
    for (final term in terms) {
      final text = term.text.trim();
      if (text.isEmpty || !seen.add(text)) {
        continue;
      }
      parts.add(text);
    }
    return parts.join(', ');
  }

  RoleAssembly _assemblyWithAiRoleExtraction({
    required RoleAssembly assembly,
    required ScriptAiExtractedRole role,
    required Set<String> usedStageIds,
    required ScriptAiRoleStageLabeler stageLabelFor,
  }) {
    final nextStages = _aiRoleExtractionStages(
      role: role,
      usedStageIds: usedStageIds,
      existingStageIds: {for (final stage in assembly.stages) stage.id},
      stageLabelFor: stageLabelFor,
    );
    if (nextStages.isEmpty) {
      return assembly;
    }
    final hasUserAuthoredStages = assembly.stages.any(_isUserAuthoredStage);
    final mergedStages = !hasUserAuthoredStages
        ? nextStages
        : _mergeAiRoleExtractionStages(
            existingStages: assembly.stages,
            aiStages: nextStages,
          );
    return assembly.copyWith(
      displayLabel: role.displayName.trim().isEmpty
          ? assembly.displayLabel
          : role.displayName,
      sourceName: role.displayName.trim().isEmpty
          ? assembly.sourceName
          : role.displayName,
      sourceAppearances: _roleAssemblySourceAppearancesFromAi(role),
      stages: List.unmodifiable(mergedStages),
    );
  }

  List<RoleAssemblyStage> _aiRoleExtractionStages({
    required ScriptAiExtractedRole role,
    required Set<String> usedStageIds,
    required ScriptAiRoleStageLabeler stageLabelFor,
    Set<String> existingStageIds = const {},
  }) {
    final stages = <RoleAssemblyStage>[];
    final producedStageIds = <String>{};
    for (final (index, stage) in role.stages.indexed) {
      final baseId = stage.stageId.trim().isEmpty
          ? 'ai-role-${_safeIdSegment(role.sourceRoleId)}-${index + 1}'
          : stage.stageId.trim();
      final stageId = existingStageIds.contains(baseId) &&
              !producedStageIds.contains(baseId)
          ? baseId
          : _uniqueAiRoleStageId(baseId, {
              ...usedStageIds,
              ...producedStageIds,
            });
      producedStageIds.add(stageId);
      usedStageIds.add(stageId);
      stages.add(
        _roleAssemblyStageFromAiRoleExtraction(
          role: role,
          stage: stage,
          index: index,
          stageId: stageId,
          stageLabelFor: stageLabelFor,
        ),
      );
    }
    return List.unmodifiable(stages);
  }

  List<RoleAssemblyStage> _mergeAiRoleExtractionStages({
    required List<RoleAssemblyStage> existingStages,
    required List<RoleAssemblyStage> aiStages,
  }) {
    if (existingStages.length == 1 &&
        aiStages.isNotEmpty &&
        _isLocalDefaultRoleStage(existingStages.single)) {
      return [
        _stageWithAiRoleExtraction(existingStages.single, aiStages.first),
        ...aiStages.skip(1),
      ];
    }
    if (existingStages.length == 1 && aiStages.length == 1) {
      return [
        _stageWithAiRoleExtraction(existingStages.single, aiStages.single),
      ];
    }
    final existingStagesById = {
      for (final stage in existingStages) stage.id: stage,
    };
    final usedExistingStageIds = <String>{};
    final mergedStages = <RoleAssemblyStage>[];
    for (final aiStage in aiStages) {
      final existingStage = existingStagesById[aiStage.id];
      if (existingStage == null) {
        mergedStages.add(aiStage);
        continue;
      }
      usedExistingStageIds.add(existingStage.id);
      mergedStages.add(_stageWithAiRoleExtraction(existingStage, aiStage));
    }
    for (final stage in existingStages) {
      if (usedExistingStageIds.contains(stage.id)) {
        continue;
      }
      if (_isUserAuthoredStage(stage) && mergedStages.isNotEmpty) {
        final targetIndex = _bestAiStageIndexForUserStage(stage, mergedStages);
        mergedStages[targetIndex] = _stageWithUserStateOverlay(
          mergedStages[targetIndex],
          stage,
        );
        continue;
      }
    }
    return List.unmodifiable(mergedStages);
  }

  RoleAssemblyStage _roleAssemblyStageFromAiRoleExtraction({
    required ScriptAiExtractedRole role,
    required ScriptAiExtractedStage stage,
    required int index,
    required String stageId,
    required ScriptAiRoleStageLabeler stageLabelFor,
  }) {
    final parts = RecastPromptParts(
      identity: stage.identity,
      upperBody: stage.upperBody,
      lowerBody: stage.lowerBody,
      upperClothing: stage.upperClothing,
      lowerClothing: stage.lowerClothing,
    );
    final cleanSummary = _summaryFromPromptParts(parts);
    final sourceSummary = [
      ...stage.evidenceTerms,
      if (stage.evidenceTerms.isEmpty) ...role.evidenceTerms,
    ].where((term) => term.trim().isNotEmpty).join(', ');
    return RoleAssemblyStage(
      id: stageId,
      label: stageLabelFor(stage, index),
      frameIndexes: List.unmodifiable(stage.frameIndexes),
      sourceSummary: cleanSummary.trim().isEmpty ? sourceSummary : cleanSummary,
      sourceParts: parts,
      omittedParts: _omittedPartsFromAiMissingFields(stage.missingFields),
    );
  }

  bool _isUserAuthoredAssembly(RoleAssembly assembly) {
    return assembly.stages.any(_isUserAuthoredStage);
  }

  bool _shouldKeepUnmatchedExistingAssembly(
    RoleAssembly assembly,
    Set<String> coveredSourceRoleIds,
  ) {
    if (coveredSourceRoleIds.contains(assembly.sourceRoleId.trim())) {
      return false;
    }
    return _isUserAuthoredAssembly(assembly);
  }

  bool _isUserAuthoredStage(RoleAssemblyStage stage) {
    return stage.targetCharacterId != null ||
        stage.targetUpperOutfitId != null ||
        stage.targetLowerOutfitId != null ||
        !stage.manualParts.isEmpty;
  }

  bool _shouldCreateAiRoleAssembly(ScriptAiExtractedRole role) {
    final sourceRoleId = role.sourceRoleId.trim();
    if (sourceRoleId.isEmpty) {
      return false;
    }
    return role.stages.isNotEmpty;
  }

  List<RoleAssemblySourceAppearance> _roleAssemblySourceAppearancesFromAi(
    ScriptAiExtractedRole role,
  ) {
    return List.unmodifiable([
      for (final appearance in role.appearances)
        RoleAssemblySourceAppearance(
          sourceId: appearance.sourceId,
          sourceKind: appearance.sourceKind,
          frameIndexes: List.unmodifiable(appearance.frameIndexes),
        ),
    ]);
  }

  String _uniqueAiRoleStageId(String baseId, Set<String> usedStageIds) {
    if (usedStageIds.add(baseId)) {
      return baseId;
    }
    var suffix = 2;
    while (true) {
      final candidate = '$baseId-$suffix';
      if (usedStageIds.add(candidate)) {
        return candidate;
      }
      suffix += 1;
    }
  }

  int _bestAiStageIndexForUserStage(
    RoleAssemblyStage userStage,
    List<RoleAssemblyStage> aiStages,
  ) {
    if (aiStages.length == 1) {
      return 0;
    }
    var bestIndex = 0;
    var bestScore = -1;
    final userFrames = userStage.frameIndexes.toSet();
    for (final (index, aiStage) in aiStages.indexed) {
      final aiFrames = aiStage.frameIndexes.toSet();
      final frameScore = userFrames.where(aiFrames.contains).length * 1000;
      final partScore = _promptPartOverlapScore(
        userStage.sourceParts,
        aiStage.sourceParts,
      );
      final score = frameScore + partScore;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  int _promptPartOverlapScore(RecastPromptParts left, RecastPromptParts right) {
    return _tagOverlapScore(left.identity, right.identity) +
        _tagOverlapScore(left.upperBody, right.upperBody) +
        _tagOverlapScore(left.lowerBody, right.lowerBody) +
        _tagOverlapScore(left.upperClothing, right.upperClothing) +
        _tagOverlapScore(left.lowerClothing, right.lowerClothing);
  }

  int _tagOverlapScore(String left, String right) {
    final rightTags = PromptTagProcessor.splitWorkshopTags(right)
        .map(PromptTagProcessor.cleanTagDisplay)
        .map(PromptTagProcessor.normalizeMatchKey)
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (rightTags.isEmpty) {
      return 0;
    }
    return PromptTagProcessor.splitWorkshopTags(left)
        .map(PromptTagProcessor.cleanTagDisplay)
        .map(PromptTagProcessor.normalizeMatchKey)
        .where(rightTags.contains)
        .length;
  }

  RoleAssemblyStage _stageWithUserStateOverlay(
    RoleAssemblyStage target,
    RoleAssemblyStage source,
  ) {
    return target.copyWith(
      targetCharacterId: target.targetCharacterId ?? source.targetCharacterId,
      targetUpperOutfitId:
          target.targetUpperOutfitId ?? source.targetUpperOutfitId,
      targetLowerOutfitId:
          target.targetLowerOutfitId ?? source.targetLowerOutfitId,
      omittedParts: {...target.omittedParts, ...source.omittedParts},
      preservedParts: {...target.preservedParts, ...source.preservedParts},
      manualParts: _mergeManualPromptParts(
        target.manualParts,
        source.manualParts,
      ),
    );
  }

  RecastPromptParts _mergeManualPromptParts(
    RecastPromptParts target,
    RecastPromptParts source,
  ) {
    return RecastPromptParts(
      identity:
          target.identity.trim().isNotEmpty ? target.identity : source.identity,
      upperBody: target.upperBody.trim().isNotEmpty
          ? target.upperBody
          : source.upperBody,
      lowerBody: target.lowerBody.trim().isNotEmpty
          ? target.lowerBody
          : source.lowerBody,
      upperClothing: target.upperClothing.trim().isNotEmpty
          ? target.upperClothing
          : source.upperClothing,
      lowerClothing: target.lowerClothing.trim().isNotEmpty
          ? target.lowerClothing
          : source.lowerClothing,
    );
  }

  bool _isLocalDefaultRoleStage(RoleAssemblyStage stage) {
    final id = stage.id.trim().toLowerCase();
    return RegExp(r'^slot-\d+-stage-\d+$').hasMatch(id);
  }

  RoleAssemblyStage _stageWithAiRoleExtraction(
    RoleAssemblyStage existing,
    RoleAssemblyStage aiStage,
  ) {
    return existing.copyWith(
      label: aiStage.label,
      frameIndexes: aiStage.frameIndexes,
      sourceSummary: aiStage.sourceSummary,
      sourceParts: aiStage.sourceParts,
      omittedParts: aiStage.omittedParts,
    );
  }

  RecastMapping _mappingWithoutStaleLocalDefaultStages(RecastMapping mapping) {
    var changed = false;
    var nextAssemblies = [
      for (final assembly in mapping.roleAssemblies)
        () {
          final nextStages = [
            for (final stage in assembly.stages)
              if (!_isStaleLocalDefaultStage(assembly, stage)) stage,
          ];
          changed = changed || nextStages.length != assembly.stages.length;
          return assembly.copyWith(stages: List.unmodifiable(nextStages));
        }(),
    ];
    if (nextAssemblies.any(_hasMaterializedRoleAssembly)) {
      final prunedAssemblies = [
        for (final assembly in nextAssemblies)
          if (!_isEmptyAutomaticSlotAssembly(assembly)) assembly,
      ];
      changed = changed || prunedAssemblies.length != nextAssemblies.length;
      nextAssemblies = prunedAssemblies;
    }
    if (!changed) {
      return mapping;
    }
    return mapping.copyWith(roleAssemblies: List.unmodifiable(nextAssemblies));
  }

  bool _hasMaterializedRoleAssembly(RoleAssembly assembly) {
    return assembly.stages.isNotEmpty;
  }

  bool _isEmptyAutomaticSlotAssembly(RoleAssembly assembly) {
    return RegExp(r'^slot-\d+$').hasMatch(assembly.sourceRoleId.trim()) &&
        assembly.sourceName.trim().isEmpty &&
        assembly.sourceAppearances.isEmpty &&
        assembly.stages.isEmpty;
  }

  bool _isStaleLocalDefaultStage(
    RoleAssembly assembly,
    RoleAssemblyStage stage,
  ) {
    if (_isUserAuthoredStage(stage)) {
      return false;
    }
    if (!_isAutomaticStage(stage)) {
      return false;
    }
    return RegExp(
      '^${RegExp.escape(assembly.sourceRoleId)}-stage-\\d+\$',
    ).hasMatch(stage.id.trim());
  }

  bool _isAutomaticStage(RoleAssemblyStage stage) {
    return stage.targetCharacterId == null &&
        stage.targetUpperOutfitId == null &&
        stage.targetLowerOutfitId == null &&
        stage.omittedParts.isEmpty &&
        stage.preservedParts.isEmpty &&
        stage.sourceSummary.trim().isEmpty &&
        stage.sourceParts.isEmpty &&
        stage.manualParts.isEmpty;
  }

  Set<RecastPromptPart> _omittedPartsFromAiMissingFields(
    List<String> missingFields,
  ) {
    final omitted = <RecastPromptPart>{};
    for (final field in missingFields) {
      switch (field.trim()) {
        case 'missing_identity':
          omitted.add(RecastPromptPart.identity);
        case 'missing_upper_body':
          omitted.add(RecastPromptPart.upperBody);
        case 'missing_lower_body':
          omitted.add(RecastPromptPart.lowerBody);
        case 'missing_upper_clothing':
          omitted.add(RecastPromptPart.upperClothing);
        case 'missing_lower_clothing':
          omitted.add(RecastPromptPart.lowerClothing);
      }
    }
    return Set.unmodifiable(omitted);
  }

  bool _roleAssemblySourceAppearancesEqual(
    List<RoleAssemblySourceAppearance> left,
    List<RoleAssemblySourceAppearance> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftAppearance = left[index];
      final rightAppearance = right[index];
      if (leftAppearance.sourceId != rightAppearance.sourceId ||
          leftAppearance.sourceKind != rightAppearance.sourceKind ||
          !_listEquals(
            leftAppearance.frameIndexes,
            rightAppearance.frameIndexes,
          )) {
        return false;
      }
    }
    return true;
  }

  bool _roleAssemblyStagesEqual(
    List<RoleAssemblyStage> left,
    List<RoleAssemblyStage> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftStage = left[index];
      final rightStage = right[index];
      if (leftStage.id != rightStage.id ||
          leftStage.label != rightStage.label ||
          leftStage.sourceSummary != rightStage.sourceSummary ||
          !_promptPartsEqual(leftStage.sourceParts, rightStage.sourceParts) ||
          leftStage.targetCharacterId != rightStage.targetCharacterId ||
          leftStage.targetUpperOutfitId != rightStage.targetUpperOutfitId ||
          leftStage.targetLowerOutfitId != rightStage.targetLowerOutfitId ||
          !_setEquals(leftStage.omittedParts, rightStage.omittedParts) ||
          !_setEquals(leftStage.preservedParts, rightStage.preservedParts) ||
          !_listEquals(leftStage.frameIndexes, rightStage.frameIndexes) ||
          !_promptPartsEqual(leftStage.manualParts, rightStage.manualParts)) {
        return false;
      }
    }
    return true;
  }

  bool _rolePromptReplacementsEqual(
    List<ScriptRolePromptReplacement> left,
    List<ScriptRolePromptReplacement> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftReplacement = left[index];
      final rightReplacement = right[index];
      if (leftReplacement.sourceRoleId != rightReplacement.sourceRoleId ||
          leftReplacement.displayLabel != rightReplacement.displayLabel ||
          leftReplacement.sourcePreview != rightReplacement.sourcePreview ||
          leftReplacement.targetCharacterId !=
              rightReplacement.targetCharacterId ||
          leftReplacement.targetIdentityPrompt !=
              rightReplacement.targetIdentityPrompt ||
          !_promptReplacementRulesEqual(
            leftReplacement.rules,
            rightReplacement.rules,
          )) {
        return false;
      }
    }
    return true;
  }

  bool _scenePromptReplacementsEqual(
    List<ScriptScenePromptReplacement> left,
    List<ScriptScenePromptReplacement> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftReplacement = left[index];
      final rightReplacement = right[index];
      if (leftReplacement.id != rightReplacement.id ||
          leftReplacement.label != rightReplacement.label ||
          !_promptReplacementRulesEqual(
            leftReplacement.rules,
            rightReplacement.rules,
          )) {
        return false;
      }
    }
    return true;
  }

  bool _promptReplacementRulesEqual(
    List<ScriptPromptReplacementRule> left,
    List<ScriptPromptReplacementRule> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftRule = left[index];
      final rightRule = right[index];
      if (leftRule.id != rightRule.id ||
          !_promptReplacementTermsEqual(
            leftRule.sourceTerms,
            rightRule.sourceTerms,
          ) ||
          !_listEquals(leftRule.excludedTermIds, rightRule.excludedTermIds) ||
          leftRule.action != rightRule.action ||
          leftRule.matchMode != rightRule.matchMode ||
          leftRule.targetPrompt != rightRule.targetPrompt ||
          leftRule.manualPhrase != rightRule.manualPhrase ||
          leftRule.anchorTermId != rightRule.anchorTermId) {
        return false;
      }
    }
    return true;
  }

  bool _promptReplacementTermsEqual(
    List<ScriptPromptReplacementTerm> left,
    List<ScriptPromptReplacementTerm> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final leftTerm = left[index];
      final rightTerm = right[index];
      if (leftTerm.id != rightTerm.id ||
          leftTerm.text != rightTerm.text ||
          leftTerm.category != rightTerm.category ||
          leftTerm.sourcePhrase != rightTerm.sourcePhrase ||
          leftTerm.sourceLocation != rightTerm.sourceLocation ||
          !_listEquals(leftTerm.frameIndexes, rightTerm.frameIndexes)) {
        return false;
      }
    }
    return true;
  }

  bool _promptPartsEqual(RecastPromptParts left, RecastPromptParts right) {
    return left.identity == right.identity &&
        left.upperBody == right.upperBody &&
        left.lowerBody == right.lowerBody &&
        left.upperClothing == right.upperClothing &&
        left.lowerClothing == right.lowerClothing;
  }

  String _safeIdSegment(String value) {
    return value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _safePromptTermTextId(String value) {
    final safe = _safeIdSegment(value.toLowerCase());
    if (safe.isNotEmpty) {
      return safe;
    }
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return 'text-${hash.toRadixString(16)}';
  }

  String _summaryFromPromptParts(RecastPromptParts parts) {
    return [
      parts.upperClothing,
      parts.lowerClothing,
      parts.upperBody,
      parts.lowerBody,
    ].where((part) => part.trim().isNotEmpty).join(', ');
  }

  bool _listEquals<T>(List<T> left, List<T> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  bool _setEquals<T>(Set<T> left, Set<T> right) {
    if (left.length != right.length) {
      return false;
    }
    return left.containsAll(right);
  }

  Set<String> _coveredSourceRoleIds(List<ScriptAiExtractedRole> roles) {
    final result = <String>{};
    for (final role in roles) {
      final roleId = role.sourceRoleId.trim();
      for (final appearance in role.appearances) {
        final sourceId = appearance.sourceId.trim();
        if (sourceId.isEmpty) {
          continue;
        }
        final sourceKind = appearance.sourceKind.trim();
        if ((sourceKind.isEmpty || sourceKind == 'slot') &&
            sourceId != roleId) {
          result.add(sourceId);
        }
      }
    }
    return Set.unmodifiable(result);
  }
}
