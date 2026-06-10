import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';

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
    if (!extraction.isReady || extraction.roles.isEmpty) {
      return ScriptAiRoleAssemblyApplicationResult(
        mapping: mapping,
        changed: false,
      );
    }

    final normalizedExtraction = extraction.collapseEquivalentStages();
    final rolesBySourceId = <String, ScriptAiExtractedRole>{
      for (final role in normalizedExtraction.roles)
        if (role.sourceRoleId.trim().isNotEmpty) role.sourceRoleId: role,
    };
    final usedStageIds = <String>{
      for (final assembly in mapping.roleAssemblies)
        for (final stage in assembly.stages)
          if (_isUserAuthoredStage(stage)) stage.id,
    };
    var changed = false;
    final nextAssemblies = <RoleAssembly>[];
    final appliedRoleIds = <String>{};

    for (final assembly in mapping.roleAssemblies) {
      final role = rolesBySourceId[assembly.sourceRoleId];
      if (role == null) {
        if (_isUserAuthoredAssembly(assembly)) {
          nextAssemblies.add(assembly);
        } else {
          changed = true;
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
        changed = true;
      }
      nextAssemblies.add(nextAssembly);
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
      changed = true;
      nextAssemblies.add(
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

    if (!changed) {
      return ScriptAiRoleAssemblyApplicationResult(
        mapping: mapping,
        changed: false,
      );
    }
    return ScriptAiRoleAssemblyApplicationResult(
      mapping: _mappingWithoutStaleLocalDefaultStages(
        mapping.copyWith(roleAssemblies: List.unmodifiable(nextAssemblies)),
      ),
      changed: true,
    );
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
      if (_isUserAuthoredStage(stage) &&
          _isAiGeneratedRoleStage(stage) &&
          mergedStages.isNotEmpty) {
        final targetIndex = _bestAiStageIndexForUserStage(stage, mergedStages);
        mergedStages[targetIndex] = _stageWithUserStateOverlay(
          mergedStages[targetIndex],
          stage,
        );
        continue;
      }
      if (_shouldKeepUnmatchedExistingRoleStage(stage)) {
        mergedStages.add(stage);
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
      identity: target.identity.trim().isNotEmpty
          ? target.identity
          : source.identity,
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

  bool _shouldKeepUnmatchedExistingRoleStage(RoleAssemblyStage stage) {
    if (!_isUserAuthoredStage(stage)) {
      return false;
    }
    return !_isAiGeneratedRoleStage(stage);
  }

  bool _isAiGeneratedRoleStage(RoleAssemblyStage stage) {
    final id = stage.id.trim().toLowerCase();
    final label = stage.label.trim().toLowerCase();
    return _isLocalDefaultRoleStage(stage) ||
        RegExp(r'^(stage|base-role)-\d+(-\d+)?$').hasMatch(id) ||
        id.startsWith('ai-role-') ||
        RegExp(r'^stage\s+\d+$').hasMatch(label) ||
        label.startsWith('ai ');
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
    return RegExp(
      '^${RegExp.escape(assembly.sourceRoleId)}-stage-\\d+\$',
    ).hasMatch(stage.id.trim());
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
}

