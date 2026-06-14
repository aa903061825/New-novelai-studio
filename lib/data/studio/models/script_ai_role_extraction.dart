enum ScriptAiRoleExtractionStatus { idle, ready, failed, needsMoreEvidence }

class ScriptAiEvidenceRequest {
  final String id;
  final String sourceId;
  final List<int> frameIndexes;
  final List<String> wantedFields;
  final String reason;

  const ScriptAiEvidenceRequest({
    this.id = '',
    this.sourceId = '',
    this.frameIndexes = const [],
    this.wantedFields = const [],
    this.reason = '',
  });

  factory ScriptAiEvidenceRequest.fromJson(Map<String, dynamic> json) {
    return ScriptAiEvidenceRequest(
      id: _stringValue(json['id']),
      sourceId: _stringValue(json['source_id']),
      frameIndexes: _intList(json['frame_indexes']),
      wantedFields: _stringList(json['wanted_fields']),
      reason: _stringValue(json['reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_id': sourceId,
        'frame_indexes': frameIndexes,
        'wanted_fields': wantedFields,
        'reason': reason,
      };
}

class ScriptAiRoleExtraction {
  final int schemaVersion;
  final ScriptAiRoleExtractionStatus status;
  final String? chunkId;
  final double confidence;
  final List<ScriptAiExtractedRole> roles;
  final List<ScriptAiArtistChainEvidence> artistChains;
  final List<ScriptAiStrongFilterKeyword> strongFilterKeywords;
  final List<ScriptAiExtractionAttentionItem> attentionItems;
  final List<ScriptAiUnassignedTerm> unassignedTerms;
  final List<ScriptAiEvidenceRequest> evidenceRequests;
  final String rawResponse;

  const ScriptAiRoleExtraction({
    this.schemaVersion = 1,
    this.status = ScriptAiRoleExtractionStatus.idle,
    this.chunkId,
    this.confidence = 0,
    this.roles = const [],
    this.artistChains = const [],
    this.strongFilterKeywords = const [],
    this.attentionItems = const [],
    this.unassignedTerms = const [],
    this.evidenceRequests = const [],
    this.rawResponse = '',
  });

  factory ScriptAiRoleExtraction.failure({
    required String message,
    required String rawResponse,
  }) {
    return ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.failed,
      rawResponse: rawResponse,
      attentionItems: [
        ScriptAiExtractionAttentionItem(
          id: 'ai-role-extraction-parse-failure',
          kind: 'parse_failure',
          message: message,
          blocking: true,
        ),
      ],
    );
  }

  factory ScriptAiRoleExtraction.fromJson(Map<String, dynamic> json) {
    return ScriptAiRoleExtraction(
      schemaVersion: _intValue(json['schema_version'], fallback: 1),
      status: _statusValue(json['status']),
      chunkId: _optionalStringValue(json['chunk_id']),
      confidence: _doubleValue(json['confidence']),
      roles: _mapList(json['roles'])
          .map(ScriptAiExtractedRole.fromJson)
          .toList(growable: false),
      artistChains: _mapList(json['artist_chains'])
          .map(ScriptAiArtistChainEvidence.fromJson)
          .toList(growable: false),
      strongFilterKeywords: _mapList(json['strong_filter_keywords'])
          .map(ScriptAiStrongFilterKeyword.fromJson)
          .toList(growable: false),
      attentionItems: _mapList(json['attention_items'])
          .map(ScriptAiExtractionAttentionItem.fromJson)
          .toList(growable: false),
      unassignedTerms: _mapList(json['unassigned_terms'])
          .map(ScriptAiUnassignedTerm.fromJson)
          .toList(growable: false),
      evidenceRequests: _mapList(json['evidence_requests'])
          .map(ScriptAiEvidenceRequest.fromJson)
          .toList(growable: false),
      rawResponse: _stringValue(json['raw_response']),
    );
  }

  bool get isReady => status == ScriptAiRoleExtractionStatus.ready;

  bool get isFailed => status == ScriptAiRoleExtractionStatus.failed;

  bool get isNeedsMoreEvidence =>
      status == ScriptAiRoleExtractionStatus.needsMoreEvidence;

  ScriptAiRoleExtraction collapseEquivalentStages() {
    var changed = false;
    final collapsedRoles = [
      for (final role in roles)
        role._collapseEquivalentStages(onChanged: () => changed = true),
    ];
    final nextRoles = _mergeCanonicalRoles(
      collapsedRoles,
      onChanged: () => changed = true,
    );
    final splitRoles = _splitGenericMultiSourceRoles(
      nextRoles,
      onChanged: () => changed = true,
    );
    final coveredRoles = [
      for (final role in splitRoles)
        _roleWithStagesCoveringAppearances(
          role,
          onChanged: () => changed = true,
        ),
    ];
    final canonicalRoles = [
      for (final role in coveredRoles)
        _roleWithCanonicalIdentityFields(
          role,
          onChanged: () => changed = true,
        ),
    ];
    if (!changed) {
      return this;
    }
    return ScriptAiRoleExtraction(
      schemaVersion: schemaVersion,
      status: status,
      chunkId: chunkId,
      confidence: confidence,
      roles: List.unmodifiable(canonicalRoles),
      artistChains: artistChains,
      strongFilterKeywords: strongFilterKeywords,
      attentionItems: attentionItems,
      unassignedTerms: unassignedTerms,
      evidenceRequests: evidenceRequests,
      rawResponse: rawResponse,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'status': _statusJsonValue(status),
        if (_hasText(chunkId)) 'chunk_id': chunkId,
        'confidence': confidence,
        'roles': roles.map((role) => role.toJson()).toList(),
        'artist_chains': artistChains.map((chain) => chain.toJson()).toList(),
        'strong_filter_keywords':
            strongFilterKeywords.map((keyword) => keyword.toJson()).toList(),
        'attention_items': attentionItems.map((item) => item.toJson()).toList(),
        'unassigned_terms':
            unassignedTerms.map((term) => term.toJson()).toList(),
        if (evidenceRequests.isNotEmpty)
          'evidence_requests':
              evidenceRequests.map((request) => request.toJson()).toList(),
        if (rawResponse.trim().isNotEmpty) 'raw_response': rawResponse,
      };
}

class ScriptAiRoleAppearance {
  final String sourceId;
  final String sourceKind;
  final List<int> frameIndexes;

  const ScriptAiRoleAppearance({
    this.sourceId = '',
    this.sourceKind = '',
    this.frameIndexes = const [],
  });

  factory ScriptAiRoleAppearance.fromJson(Map<String, dynamic> json) {
    return ScriptAiRoleAppearance(
      sourceId: _stringValue(json['source_id']),
      sourceKind: _stringValue(json['source_kind']),
      frameIndexes: _intList(json['frame_indexes']),
    );
  }

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'source_kind': sourceKind,
        'frame_indexes': frameIndexes,
      };
}

class ScriptAiExtractedRole {
  final String sourceRoleId;
  final String sourceKind;
  final String displayName;
  final String roleReason;
  final String canonicalName;
  final String franchise;
  final List<String> rawIdentityTags;
  final List<String> variantTags;
  final String mergeWithRoleId;
  final double confidence;
  final List<int> frameIndexes;
  final List<ScriptAiRoleAppearance> appearances;
  final List<String> evidenceTerms;
  final List<String> warnings;
  final List<ScriptAiExtractedStage> stages;
  final List<ScriptAiUnassignedTerm> unassignedTerms;

  const ScriptAiExtractedRole({
    this.sourceRoleId = '',
    this.sourceKind = '',
    this.displayName = '',
    this.roleReason = '',
    this.canonicalName = '',
    this.franchise = '',
    this.rawIdentityTags = const [],
    this.variantTags = const [],
    this.mergeWithRoleId = '',
    this.confidence = 0,
    this.frameIndexes = const [],
    this.appearances = const [],
    this.evidenceTerms = const [],
    this.warnings = const [],
    this.stages = const [],
    this.unassignedTerms = const [],
  });

  factory ScriptAiExtractedRole.fromJson(Map<String, dynamic> json) {
    return ScriptAiExtractedRole(
      sourceRoleId: _stringValue(json['source_role_id']),
      sourceKind: _stringValue(json['source_kind']),
      displayName: _stringValue(json['display_name']),
      roleReason: _stringValue(json['role_reason'] ?? json['roleReason']),
      canonicalName:
          _stringValue(json['canonical_name'] ?? json['canonicalName']),
      franchise: _stringValue(
        json['franchise'] ??
            json['source'] ??
            json['franchise_source'] ??
            json['franchiseSource'],
      ),
      rawIdentityTags: _stringList(
        json['raw_identity_tags'] ?? json['rawIdentityTags'],
      ),
      variantTags: _stringList(json['variant_tags'] ?? json['variantTags']),
      mergeWithRoleId: _stringValue(
        json['merge_with_role_id'] ?? json['mergeWithRoleId'],
      ),
      confidence: _doubleValue(json['confidence']),
      frameIndexes: _intList(json['frame_indexes']),
      appearances: _mapList(json['appearances'])
          .map(ScriptAiRoleAppearance.fromJson)
          .toList(growable: false),
      evidenceTerms: _stringList(json['evidence_terms']),
      warnings: _stringList(json['warnings']),
      stages: _mapList(json['stages'])
          .map(ScriptAiExtractedStage.fromJson)
          .toList(growable: false),
      unassignedTerms: _mapList(json['unassigned_terms'])
          .map(ScriptAiUnassignedTerm.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'source_role_id': sourceRoleId,
        'source_kind': sourceKind,
        'display_name': displayName,
        'role_reason': roleReason,
        'canonical_name': canonicalName,
        'franchise': franchise,
        'raw_identity_tags': rawIdentityTags,
        'variant_tags': variantTags,
        'merge_with_role_id': mergeWithRoleId,
        'confidence': confidence,
        'frame_indexes': frameIndexes,
        'appearances':
            appearances.map((appearance) => appearance.toJson()).toList(),
        'evidence_terms': evidenceTerms,
        'warnings': warnings,
        'stages': stages.map((stage) => stage.toJson()).toList(),
        'unassigned_terms':
            unassignedTerms.map((term) => term.toJson()).toList(),
      };

  ScriptAiExtractedRole _collapseEquivalentStages({
    required void Function() onChanged,
  }) {
    var changed = false;
    void markChanged() {
      changed = true;
      onChanged();
    }

    final collapsed = <ScriptAiExtractedStage>[];
    final indexesByKey = <String, int>{};
    final replacementStateKeys = <String>[];
    for (final stage in stages) {
      final replacementStateKey = _stageReplacementStateKey(stage);
      final stableStage = _stageWithTransientTermsDemoted(
        stage,
        onChanged: markChanged,
      );
      final key = _stageRoleFieldKey(
        stableStage,
        replacementStateKey: replacementStateKey,
      );
      final existingIndex = indexesByKey[key] ??
          _compatibleStageIndex(
            collapsed,
            stableStage,
            replacementStateKey: replacementStateKey,
            replacementStateKeys: replacementStateKeys,
          );
      if (existingIndex == null) {
        indexesByKey[key] = collapsed.length;
        collapsed.add(stableStage);
        replacementStateKeys.add(replacementStateKey);
        continue;
      }
      markChanged();
      collapsed[existingIndex] = _mergeEquivalentStages(
        collapsed[existingIndex],
        stableStage,
      );
    }
    final uniqueStages = <ScriptAiExtractedStage>[];
    final usedStageIds = <String>{};
    for (final (index, stage) in collapsed.indexed) {
      final rawBaseId = stage.stageId.trim().isEmpty
          ? 'stage-${index + 1}'
          : stage.stageId.trim();
      final stageId = _uniqueStageId(rawBaseId, usedStageIds);
      if (stageId != stage.stageId) {
        markChanged();
        uniqueStages.add(_stageWithStageId(stage, stageId));
      } else {
        uniqueStages.add(stage);
      }
    }
    if (!changed && collapsed.length == stages.length) {
      return this;
    }
    return ScriptAiExtractedRole(
      sourceRoleId: sourceRoleId,
      sourceKind: sourceKind,
      displayName: displayName,
      roleReason: roleReason,
      canonicalName: canonicalName,
      franchise: franchise,
      rawIdentityTags: rawIdentityTags,
      variantTags: variantTags,
      mergeWithRoleId: mergeWithRoleId,
      confidence: confidence,
      frameIndexes: frameIndexes,
      appearances: appearances,
      evidenceTerms: evidenceTerms,
      warnings: warnings,
      stages: List.unmodifiable(uniqueStages),
      unassignedTerms: unassignedTerms,
    );
  }
}

class ScriptAiExtractedStage {
  final String stageId;
  final String label;
  final String appearanceGroupId;
  final List<String> mergeWithStageIds;
  final Map<String, String> fieldReasons;
  final double confidence;
  final List<int> frameIndexes;
  final String identity;
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;
  final String nonRole;
  final bool nonRoleMaterialized;
  final List<String> evidenceTerms;
  final List<String> missingFields;
  final List<String> warnings;

  const ScriptAiExtractedStage({
    this.stageId = '',
    this.label = '',
    this.appearanceGroupId = '',
    this.mergeWithStageIds = const [],
    this.fieldReasons = const {},
    this.confidence = 0,
    this.frameIndexes = const [],
    this.identity = '',
    this.upperBody = '',
    this.lowerBody = '',
    this.upperClothing = '',
    this.lowerClothing = '',
    this.nonRole = '',
    this.nonRoleMaterialized = false,
    this.evidenceTerms = const [],
    this.missingFields = const [],
    this.warnings = const [],
  });

  factory ScriptAiExtractedStage.fromJson(Map<String, dynamic> json) {
    final hasNonRole = json.containsKey('non_role') ||
        json.containsKey('nonRole') ||
        json.containsKey('non_role_materialized') ||
        json.containsKey('nonRoleMaterialized');
    return ScriptAiExtractedStage(
      stageId: _stringValue(json['stage_id']),
      label: _stringValue(json['label']),
      appearanceGroupId: _stringValue(
        json['appearance_group_id'] ?? json['appearanceGroupId'],
      ),
      mergeWithStageIds: _stringList(
        json['merge_with_stage_ids'] ?? json['mergeWithStageIds'],
      ),
      fieldReasons: _stringMap(
        json['field_reasons'] ?? json['fieldReasons'],
      ),
      confidence: _doubleValue(json['confidence']),
      frameIndexes: _intList(json['frame_indexes']),
      identity: _stringValue(json['identity']),
      upperBody: _stringValue(json['upper_body']),
      lowerBody: _stringValue(json['lower_body']),
      upperClothing: _stringValue(json['upper_clothing']),
      lowerClothing: _stringValue(json['lower_clothing']),
      nonRole: _stringValue(json['non_role'] ?? json['nonRole']),
      nonRoleMaterialized: _boolValue(
        json['non_role_materialized'] ?? json['nonRoleMaterialized'],
        fallback: hasNonRole,
      ),
      evidenceTerms: _stringList(json['evidence_terms']),
      missingFields: _stringList(json['missing_fields']),
      warnings: _stringList(json['warnings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'stage_id': stageId,
        'label': label,
        'appearance_group_id': appearanceGroupId,
        'merge_with_stage_ids': mergeWithStageIds,
        'field_reasons': fieldReasons,
        'confidence': confidence,
        'frame_indexes': frameIndexes,
        'identity': identity,
        'upper_body': upperBody,
        'lower_body': lowerBody,
        'upper_clothing': upperClothing,
        'lower_clothing': lowerClothing,
        if (nonRoleMaterialized || nonRole.trim().isNotEmpty)
          'non_role': nonRole,
        if (nonRoleMaterialized) 'non_role_materialized': true,
        'evidence_terms': evidenceTerms,
        'missing_fields': missingFields,
        'warnings': warnings,
      };
}

List<ScriptAiExtractedRole> _mergeCanonicalRoles(
  List<ScriptAiExtractedRole> roles, {
  required void Function() onChanged,
}) {
  final result = <ScriptAiExtractedRole>[];
  final indexesByCanonicalKey = <String, int>{};
  final indexesBySourceRoleId = <String, int>{};

  for (final role in roles) {
    final sourceRoleId = role.sourceRoleId.trim();
    final canonicalKey = _canonicalRoleKey(role);
    final explicitMergeId = role.mergeWithRoleId.trim();
    final existingIndex = explicitMergeId.isNotEmpty
        ? indexesBySourceRoleId[explicitMergeId]
        : canonicalKey.isEmpty
            ? null
            : indexesByCanonicalKey[canonicalKey];
    if (existingIndex == null) {
      final nextIndex = result.length;
      result.add(role);
      if (sourceRoleId.isNotEmpty) {
        indexesBySourceRoleId[sourceRoleId] = nextIndex;
      }
      if (canonicalKey.isNotEmpty) {
        indexesByCanonicalKey[canonicalKey] = nextIndex;
      }
      continue;
    }

    onChanged();
    final merged = _mergeEquivalentRoles(result[existingIndex], role);
    result[existingIndex] = merged;
    if (sourceRoleId.isNotEmpty) {
      indexesBySourceRoleId[sourceRoleId] = existingIndex;
    }
    final mergedCanonicalKey = _canonicalRoleKey(merged);
    if (mergedCanonicalKey.isNotEmpty) {
      indexesByCanonicalKey[mergedCanonicalKey] = existingIndex;
    }
  }
  return List.unmodifiable(result);
}

List<ScriptAiExtractedRole> _splitGenericMultiSourceRoles(
  List<ScriptAiExtractedRole> roles, {
  required void Function() onChanged,
}) {
  final usedRoleIds = {
    for (final role in roles)
      if (role.sourceRoleId.trim().isNotEmpty) role.sourceRoleId.trim(),
  };
  final result = <ScriptAiExtractedRole>[];
  for (final role in roles) {
    if (!_shouldSplitGenericMultiSourceRole(role)) {
      result.add(role);
      continue;
    }
    onChanged();
    final appearances = _mergedAppearances(role.appearances, const []);
    for (final appearance in appearances) {
      final sourceId = appearance.sourceId.trim();
      final nextRoleId = _uniqueRoleId(
        '${role.sourceRoleId}-${_safeIdSegment(sourceId)}',
        usedRoleIds,
      );
      result.add(
        ScriptAiExtractedRole(
          sourceRoleId: nextRoleId,
          sourceKind: appearance.sourceKind.trim().isEmpty
              ? role.sourceKind
              : appearance.sourceKind,
          displayName: role.displayName,
          roleReason: role.roleReason,
          canonicalName: role.canonicalName,
          franchise: role.franchise,
          rawIdentityTags: role.rawIdentityTags,
          variantTags: role.variantTags,
          mergeWithRoleId: '',
          confidence: role.confidence,
          frameIndexes: List.unmodifiable(appearance.frameIndexes),
          appearances: [appearance],
          evidenceTerms: role.evidenceTerms,
          warnings: _mergedStrings(
            role.warnings,
            const ['generic_multi_source_role_split'],
          ),
          stages: _stagesForSourceAppearance(role, appearance),
          unassignedTerms: role.unassignedTerms,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

bool _shouldSplitGenericMultiSourceRole(ScriptAiExtractedRole role) {
  if (_canonicalRoleKey(role).isNotEmpty || role.mergeWithRoleId.isNotEmpty) {
    return false;
  }
  final sourceKeys = {
    for (final appearance in role.appearances)
      if (appearance.sourceId.trim().isNotEmpty)
        '${appearance.sourceKind.trim()}\u001f${appearance.sourceId.trim()}',
  };
  if (sourceKeys.length < 2) {
    return false;
  }
  return _isGenericRoleLabel(role.displayName);
}

bool _isGenericRoleLabel(String value) {
  return _genericIdentityTerms.contains(_normalizedCanonicalText(value));
}

const _genericIdentityTerms = {
  'boy',
  'girl',
  'male',
  'female',
  'man',
  'woman',
  'child',
  'loli',
};

List<ScriptAiExtractedStage> _stagesForSourceAppearance(
  ScriptAiExtractedRole role,
  ScriptAiRoleAppearance appearance,
) {
  final appearanceFrames = appearance.frameIndexes.toSet();
  if (appearanceFrames.isEmpty) {
    return role.stages;
  }
  final stages = <ScriptAiExtractedStage>[];
  for (final stage in role.stages) {
    final frames = stage.frameIndexes
        .where(appearanceFrames.contains)
        .toList(growable: false)
      ..sort();
    if (frames.isEmpty) {
      continue;
    }
    stages.add(_stageWithFrameIndexes(stage, frames));
  }
  final covered = {
    for (final stage in stages) ...stage.frameIndexes,
  };
  final missing = appearance.frameIndexes
      .where((frame) => !covered.contains(frame))
      .toList(growable: false);
  if (missing.isEmpty) {
    return List.unmodifiable(stages);
  }
  if (stages.isEmpty && role.stages.isNotEmpty) {
    return [
      _stageWithFrameIndexes(role.stages.first, appearance.frameIndexes),
    ];
  }
  if (stages.isEmpty) {
    return const [];
  }
  final nextStages = stages.toList(growable: true);
  for (final frame in missing) {
    final index = _nearestStageIndexForFrame(nextStages, frame);
    nextStages[index] = _stageWithFrameIndexes(
      nextStages[index],
      _mergedInts(nextStages[index].frameIndexes, [frame]),
    );
  }
  return List.unmodifiable(nextStages);
}

ScriptAiExtractedRole _roleWithStagesCoveringAppearances(
  ScriptAiExtractedRole role, {
  required void Function() onChanged,
}) {
  if (role.appearances.isEmpty || role.stages.isEmpty) {
    return role;
  }
  final appearanceFrames = {
    for (final appearance in role.appearances) ...appearance.frameIndexes,
  };
  if (appearanceFrames.isEmpty) {
    return role;
  }
  final coveredFrames = {
    for (final stage in role.stages) ...stage.frameIndexes,
  };
  final missing = appearanceFrames.difference(coveredFrames).toList()..sort();
  if (missing.isEmpty) {
    return role;
  }
  onChanged();
  final stages = role.stages.toList(growable: true);
  for (final frame in missing) {
    final index = _nearestStageIndexForFrame(stages, frame);
    stages[index] = _stageWithFrameIndexes(
      stages[index],
      _mergedInts(stages[index].frameIndexes, [frame]),
    );
  }
  return ScriptAiExtractedRole(
    sourceRoleId: role.sourceRoleId,
    sourceKind: role.sourceKind,
    displayName: role.displayName,
    roleReason: role.roleReason,
    canonicalName: role.canonicalName,
    franchise: role.franchise,
    rawIdentityTags: role.rawIdentityTags,
    variantTags: role.variantTags,
    mergeWithRoleId: role.mergeWithRoleId,
    confidence: role.confidence,
    frameIndexes: role.frameIndexes,
    appearances: role.appearances,
    evidenceTerms: role.evidenceTerms,
    warnings: _mergedStrings(
      role.warnings,
      const ['appearance_frame_coverage_completed'],
    ),
    stages: List.unmodifiable(stages),
    unassignedTerms: role.unassignedTerms,
  );
}

ScriptAiExtractedRole _roleWithCanonicalIdentityFields(
  ScriptAiExtractedRole role, {
  required void Function() onChanged,
}) {
  final identity = _canonicalIdentityForRole(role);
  if (identity == null) {
    return role;
  }
  final rawIdentityTags = _rawIdentityTagsForRole(role);
  final variantTags = _variantTagsForRole(role);
  final changed = role.canonicalName.trim() != identity.name ||
      role.franchise.trim() != identity.franchise ||
      !_stringListsEqual(role.rawIdentityTags, rawIdentityTags) ||
      !_stringListsEqual(role.variantTags, variantTags);
  if (!changed) {
    return role;
  }
  onChanged();
  return ScriptAiExtractedRole(
    sourceRoleId: role.sourceRoleId,
    sourceKind: role.sourceKind,
    displayName: role.displayName,
    roleReason: role.roleReason,
    canonicalName: identity.name,
    franchise: identity.franchise,
    rawIdentityTags: rawIdentityTags,
    variantTags: variantTags,
    mergeWithRoleId: role.mergeWithRoleId,
    confidence: role.confidence,
    frameIndexes: role.frameIndexes,
    appearances: role.appearances,
    evidenceTerms: role.evidenceTerms,
    warnings: role.warnings,
    stages: role.stages,
    unassignedTerms: role.unassignedTerms,
  );
}

int _nearestStageIndexForFrame(List<ScriptAiExtractedStage> stages, int frame) {
  var bestIndex = 0;
  var bestDistance = 1 << 30;
  for (final (index, stage) in stages.indexed) {
    final distance = stage.frameIndexes.isEmpty
        ? bestDistance
        : stage.frameIndexes
            .map((value) => (value - frame).abs())
            .reduce((left, right) => left < right ? left : right);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = index;
    }
  }
  return bestIndex;
}

String _safeIdSegment(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9_-]+'),
        '-',
      );
  final clean = normalized
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return clean.isEmpty ? 'source' : clean;
}

String _uniqueRoleId(String baseId, Set<String> used) {
  final cleanBase = baseId.trim().isEmpty ? 'role' : baseId.trim();
  if (used.add(cleanBase)) {
    return cleanBase;
  }
  var suffix = 2;
  while (true) {
    final candidate = '$cleanBase-$suffix';
    if (used.add(candidate)) {
      return candidate;
    }
    suffix += 1;
  }
}

ScriptAiExtractedRole _mergeEquivalentRoles(
  ScriptAiExtractedRole left,
  ScriptAiExtractedRole right,
) {
  var stagesChanged = false;
  final mergedStages = ScriptAiExtractedRole(
    sourceRoleId: left.sourceRoleId,
    stages: [...left.stages, ...right.stages],
  )._collapseEquivalentStages(onChanged: () => stagesChanged = true).stages;
  final canonical = _canonicalIdentityForRole(left) ??
      _canonicalIdentityForRole(right) ??
      const _CanonicalIdentity(name: '', franchise: '', variants: []);
  final rawIdentityTags = _mergedStrings(
    _rawIdentityTagsForRole(left),
    _rawIdentityTagsForRole(right),
  );
  final variantTags = _mergedStrings(
    _variantTagsForRole(left),
    _variantTagsForRole(right),
  );
  return ScriptAiExtractedRole(
    sourceRoleId: left.sourceRoleId,
    sourceKind: _mergedSourceKind(left, right),
    displayName:
        left.displayName.trim().isEmpty ? right.displayName : left.displayName,
    roleReason: _mergedStrings(
      [left.roleReason],
      [right.roleReason],
    ).join(' | '),
    canonicalName: left.canonicalName.trim().isNotEmpty
        ? left.canonicalName
        : canonical.name,
    franchise:
        left.franchise.trim().isNotEmpty ? left.franchise : canonical.franchise,
    rawIdentityTags: rawIdentityTags,
    variantTags: variantTags,
    mergeWithRoleId: left.mergeWithRoleId,
    confidence: left.confidence >= right.confidence
        ? left.confidence
        : right.confidence,
    frameIndexes: _mergedInts(left.frameIndexes, right.frameIndexes),
    appearances: _mergedAppearances(left.appearances, right.appearances),
    evidenceTerms: _mergedStrings(left.evidenceTerms, right.evidenceTerms),
    warnings: _mergedStrings(
      left.warnings,
      [
        ...right.warnings,
        if (!stagesChanged) 'canonical_role_variant_merged',
      ],
    ),
    stages: mergedStages,
    unassignedTerms: List.unmodifiable([
      ...left.unassignedTerms,
      ...right.unassignedTerms,
    ]),
  );
}

String _mergedSourceKind(
  ScriptAiExtractedRole left,
  ScriptAiExtractedRole right,
) {
  final leftKind = left.sourceKind.trim();
  final rightKind = right.sourceKind.trim();
  if (leftKind == 'cross_slot' || rightKind == 'cross_slot') {
    return 'cross_slot';
  }
  if (left.sourceRoleId.trim().isNotEmpty &&
      right.sourceRoleId.trim().isNotEmpty &&
      left.sourceRoleId.trim() != right.sourceRoleId.trim()) {
    return 'cross_slot';
  }
  return leftKind.isEmpty ? rightKind : leftKind;
}

List<ScriptAiRoleAppearance> _mergedAppearances(
  List<ScriptAiRoleAppearance> left,
  List<ScriptAiRoleAppearance> right,
) {
  final byKey = <String, ScriptAiRoleAppearance>{};
  for (final appearance in [...left, ...right]) {
    final sourceId = appearance.sourceId.trim();
    final sourceKind = appearance.sourceKind.trim();
    final key = '$sourceKind\u001f$sourceId';
    if (sourceId.isEmpty && sourceKind.isEmpty) {
      continue;
    }
    final existing = byKey[key];
    byKey[key] = existing == null
        ? appearance
        : ScriptAiRoleAppearance(
            sourceId: existing.sourceId,
            sourceKind: existing.sourceKind,
            frameIndexes: _mergedInts(
              existing.frameIndexes,
              appearance.frameIndexes,
            ),
          );
  }
  return List.unmodifiable(byKey.values);
}

ScriptAiExtractedStage _stageWithTransientTermsDemoted(
  ScriptAiExtractedStage stage, {
  required void Function() onChanged,
}) {
  final stableFields = _normalizedStageStableFields(stage);
  final stableEvidenceTerms = _stableEvidenceTerms(stage.evidenceTerms);
  final clearsNonRole =
      stage.nonRole.trim().isNotEmpty || stage.nonRoleMaterialized;
  if (!stableFields.changed &&
      _stringListsEqual(stableEvidenceTerms, stage.evidenceTerms) &&
      !clearsNonRole) {
    return stage;
  }
  onChanged();
  return ScriptAiExtractedStage(
    stageId: stage.stageId,
    label: stage.label,
    appearanceGroupId: stage.appearanceGroupId,
    mergeWithStageIds: stage.mergeWithStageIds,
    fieldReasons: stage.fieldReasons,
    confidence: stage.confidence,
    frameIndexes: stage.frameIndexes,
    identity: stage.identity,
    upperBody: stableFields.upperBody,
    lowerBody: stableFields.lowerBody,
    upperClothing: stableFields.upperClothing,
    lowerClothing: stableFields.lowerClothing,
    nonRole: '',
    nonRoleMaterialized: false,
    evidenceTerms: stableEvidenceTerms,
    missingFields: stage.missingFields,
    warnings: stage.warnings,
  );
}

_NormalizedStageStableFields _normalizedStageStableFields(
  ScriptAiExtractedStage stage,
) {
  final upperBody = <String>[];
  final lowerBody = <String>[];
  final upperClothing = <String>[];
  final lowerClothing = <String>[];

  void addTerms(String field, String value) {
    for (final term in _commaTerms(value)) {
      if (_isTransientRoleFieldTerm(term)) {
        continue;
      }
      switch (field) {
        case 'upperBody':
          upperBody.add(term);
          break;
        case 'lowerBody':
          lowerBody.add(term);
          break;
        case 'upperClothing':
          if (_isLowerClothingFieldTerm(term)) {
            lowerClothing.add(term);
          } else {
            upperClothing.add(term);
          }
          break;
        case 'lowerClothing':
          lowerClothing.add(term);
          break;
      }
    }
  }

  addTerms('upperBody', stage.upperBody);
  addTerms('lowerBody', stage.lowerBody);
  addTerms('upperClothing', stage.upperClothing);
  addTerms('lowerClothing', stage.lowerClothing);

  final normalized = _NormalizedStageStableFields(
    upperBody: _mergedStrings(upperBody, const []).join(', '),
    lowerBody: _mergedStrings(lowerBody, const []).join(', '),
    upperClothing: _mergedStrings(upperClothing, const []).join(', '),
    lowerClothing: _mergedStrings(lowerClothing, const []).join(', '),
  );
  return normalized.copyWith(
    changed: normalized.upperBody !=
            _normalizedPromptFieldText(stage.upperBody) ||
        normalized.lowerBody != _normalizedPromptFieldText(stage.lowerBody) ||
        normalized.upperClothing !=
            _normalizedPromptFieldText(stage.upperClothing) ||
        normalized.lowerClothing !=
            _normalizedPromptFieldText(stage.lowerClothing),
  );
}

class _NormalizedStageStableFields {
  final String upperBody;
  final String lowerBody;
  final String upperClothing;
  final String lowerClothing;
  final bool changed;

  const _NormalizedStageStableFields({
    required this.upperBody,
    required this.lowerBody,
    required this.upperClothing,
    required this.lowerClothing,
    this.changed = false,
  });

  _NormalizedStageStableFields copyWith({
    bool? changed,
  }) {
    return _NormalizedStageStableFields(
      upperBody: upperBody,
      lowerBody: lowerBody,
      upperClothing: upperClothing,
      lowerClothing: lowerClothing,
      changed: changed ?? this.changed,
    );
  }
}

List<String> _stableEvidenceTerms(List<String> values) {
  return _mergedStrings(
    [
      for (final term in values)
        if (!_isTransientRoleFieldTerm(term)) term.trim(),
    ],
    const [],
  );
}

String _stageRoleFieldKey(
  ScriptAiExtractedStage stage, {
  String replacementStateKey = '',
}) {
  return [
    _normalizedPromptFieldKey(stage.identity),
    replacementStateKey,
    _normalizedStablePromptFieldKey(stage.upperBody),
    _normalizedStablePromptFieldKey(stage.lowerBody),
    _normalizedStablePromptFieldKey(stage.upperClothing),
    _normalizedStablePromptFieldKey(stage.lowerClothing),
  ].join('\u001f');
}

String _stageReplacementStateKey(ScriptAiExtractedStage stage) {
  final text = _normalizedReplacementStateText(stage);
  final upperClothingKey = _normalizedStablePromptFieldKey(stage.upperClothing);
  final lowerClothingKey = _normalizedStablePromptFieldKey(stage.lowerClothing);
  if (_hasTowelState(text)) {
    return [
      'towel',
      if (upperClothingKey.isNotEmpty) 'upper:$upperClothingKey',
      if (lowerClothingKey.isNotEmpty) 'lower:$lowerClothingKey',
    ].join('|');
  }
  if (_hasToplessState(text)) {
    return [
      'topless',
      if (lowerClothingKey.isNotEmpty) 'lower:$lowerClothingKey',
    ].join('|');
  }
  if (_hasBottomlessState(text)) {
    return [
      'bottomless',
      if (upperClothingKey.isNotEmpty) 'upper:$upperClothingKey',
    ].join('|');
  }
  if (_hasNudeState(text)) {
    return [
      'nude',
      if (upperClothingKey.isNotEmpty) 'upper:$upperClothingKey',
      if (lowerClothingKey.isNotEmpty) 'lower:$lowerClothingKey',
    ].join('|');
  }
  return '';
}

String _normalizedReplacementStateText(ScriptAiExtractedStage stage) {
  return [
    stage.label,
    ...stage.evidenceTerms,
    stage.upperBody,
    stage.lowerBody,
    stage.upperClothing,
    stage.lowerClothing,
  ]
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _hasTowelState(String text) {
  return RegExp(
        r'(^|[^a-z0-9])(towel|bath towel|towel wrap|wrapped in towel)'
        r'([^a-z0-9]|$)',
      ).hasMatch(text) ||
      text.contains('\u6d74\u5dfe');
}

bool _hasToplessState(String text) {
  return RegExp(r'(^|[^a-z0-9])topless([^a-z0-9]|$)').hasMatch(text) ||
      text.contains('\u4e0a\u8eab\u88f8\u4f53');
}

bool _hasBottomlessState(String text) {
  return RegExp(r'(^|[^a-z0-9])bottomless([^a-z0-9]|$)').hasMatch(text) ||
      text.contains('\u4e0b\u8eab\u88f8\u4f53');
}

bool _hasNudeState(String text) {
  return RegExp(
        r'(^|[^a-z0-9])('
        r'nude|naked|fully nude|completely nude|completly nude|no clothes|'
        r'without clothes|unclothed'
        r')([^a-z0-9]|$)',
      ).hasMatch(text) ||
      text.contains('\u5168\u88f8') ||
      text.contains('\u88f8\u4f53');
}

String _normalizedPromptFieldText(String value) {
  return _mergedStrings(_commaTerms(value), const []).join(', ');
}

int? _compatibleStageIndex(
  List<ScriptAiExtractedStage> stages,
  ScriptAiExtractedStage stage, {
  required String replacementStateKey,
  required List<String> replacementStateKeys,
}) {
  for (final (index, candidate) in stages.indexed) {
    if (_roleStagesCompatible(
      candidate,
      stage,
      leftReplacementStateKey: replacementStateKeys[index],
      rightReplacementStateKey: replacementStateKey,
    )) {
      return index;
    }
  }
  return null;
}

bool _roleStagesCompatible(
  ScriptAiExtractedStage left,
  ScriptAiExtractedStage right, {
  String leftReplacementStateKey = '',
  String rightReplacementStateKey = '',
}) {
  return _replacementStatesCompatible(
        leftReplacementStateKey,
        rightReplacementStateKey,
      ) &&
      _promptFieldsCompatible(left.identity, right.identity) &&
      _stablePromptFieldsCompatible(left.upperBody, right.upperBody) &&
      _stablePromptFieldsCompatible(left.lowerBody, right.lowerBody) &&
      _stableClothingFieldsCompatible(
        left.upperClothing,
        right.upperClothing,
      ) &&
      _stableClothingFieldsCompatible(
        left.lowerClothing,
        right.lowerClothing,
      );
}

bool _replacementStatesCompatible(String left, String right) {
  if (left.isEmpty && right.isEmpty) {
    return true;
  }
  return left == right;
}

bool _promptFieldsCompatible(String left, String right) {
  if (_promptTermSetsCompatible(
    _commaTerms(left).map(_normalizedRoleTerm).toList(),
    _commaTerms(right).map(_normalizedRoleTerm).toList(),
  )) {
    return true;
  }
  final leftKeys = _canonicalIdentityKeysFromText(left);
  final rightKeys = _canonicalIdentityKeysFromText(right);
  return leftKeys.isNotEmpty &&
      rightKeys.isNotEmpty &&
      leftKeys.any(rightKeys.contains);
}

bool _stablePromptFieldsCompatible(String left, String right) {
  return _promptTermSetsCompatible(
    _commaTerms(left)
        .where((term) => !_isTransientRoleFieldTerm(term))
        .map(_normalizedRoleTerm)
        .toList(),
    _commaTerms(right)
        .where((term) => !_isTransientRoleFieldTerm(term))
        .map(_normalizedRoleTerm)
        .toList(),
  );
}

bool _stableClothingFieldsCompatible(String left, String right) {
  final leftTerms = _commaTerms(left)
      .where((term) => !_isTransientRoleFieldTerm(term))
      .map(_normalizedRoleTerm)
      .toList();
  final rightTerms = _commaTerms(right)
      .where((term) => !_isTransientRoleFieldTerm(term))
      .map(_normalizedRoleTerm)
      .toList();
  if (!_promptTermSetsCompatible(leftTerms, rightTerms)) {
    return false;
  }
  if (leftTerms.isEmpty || rightTerms.isEmpty) {
    return true;
  }
  final leftCore = leftTerms.where(_isCoreClothingReplacementTerm).toSet();
  final rightCore = rightTerms.where(_isCoreClothingReplacementTerm).toSet();
  if (leftCore.isEmpty || rightCore.isEmpty) {
    return true;
  }
  return leftCore.length == rightCore.length && leftCore.containsAll(rightCore);
}

bool _isCoreClothingReplacementTerm(String term) {
  final normalized = term
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return RegExp(
    r'(^|[^a-z0-9])('
    r'shirt|tank top|camisole|blouse|bra|bikini|swimsuit|leotard|'
    r'uniform|dress|jacket|coat|hoodie|robe|towel|overalls?|coveralls?|'
    r'apron|skirt|pants|shorts|trousers|panties|underwear|briefs|'
    r'stockings?|socks?|shoes?|boots?|sandals?|heels?|loafers?'
    r')([^a-z0-9]|$)',
  ).hasMatch(normalized);
}

bool _promptTermSetsCompatible(List<String> left, List<String> right) {
  if (left.isEmpty || right.isEmpty) {
    return true;
  }
  final leftTerms = left.toSet();
  final rightTerms = right.toSet();
  return leftTerms.every(rightTerms.contains) ||
      rightTerms.every(leftTerms.contains);
}

String _normalizedPromptFieldKey(String value) {
  final terms = _commaTerms(value).map(_normalizedRoleTerm).toList()..sort();
  return terms.join('\u001e');
}

String _normalizedStablePromptFieldKey(String value) {
  final terms = _commaTerms(value)
      .where((term) => !_isTransientRoleFieldTerm(term))
      .map(_normalizedRoleTerm)
      .toList()
    ..sort();
  return terms.join('\u001e');
}

String _normalizedRoleTerm(String term) {
  final normalized = term.trim().toLowerCase();
  return normalized
      .replaceFirst(RegExp(r'^(wearing|wears|with)\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _canonicalRoleKey(ScriptAiExtractedRole role) {
  final identity = _canonicalIdentityForRole(role);
  if (identity == null) {
    return '';
  }
  return _canonicalIdentityKey(identity.name, identity.franchise);
}

_CanonicalIdentity? _canonicalIdentityForRole(ScriptAiExtractedRole role) {
  final explicitName = role.canonicalName.trim();
  final explicitFranchise = role.franchise.trim();
  if (explicitName.isNotEmpty &&
      explicitFranchise.isNotEmpty &&
      !_isNonCharacterIdentityTag(explicitName) &&
      !_isNonCharacterIdentityTag(explicitFranchise)) {
    return _CanonicalIdentity(
      name: explicitName,
      franchise: explicitFranchise,
      variants: role.variantTags,
    );
  }
  for (final tag in _rawIdentityTagsForRole(role)) {
    final identity = _canonicalIdentityFromTag(tag);
    if (identity != null) {
      return identity;
    }
  }
  return null;
}

List<String> _rawIdentityTagsForRole(ScriptAiExtractedRole role) {
  return _mergedStrings(role.rawIdentityTags, [
    if (_canonicalIdentityFromTag(role.displayName) != null) role.displayName,
    for (final stage in role.stages)
      for (final term in _commaTerms(stage.identity))
        if (_canonicalIdentityFromTag(term) != null) term,
  ]);
}

List<String> _variantTagsForRole(ScriptAiExtractedRole role) {
  return _mergedStrings(role.variantTags, [
    for (final tag in _rawIdentityTagsForRole(role))
      ...?_canonicalIdentityFromTag(tag)?.variants,
  ]);
}

Set<String> _canonicalIdentityKeysFromText(String value) {
  return {
    for (final term in _commaTerms(value))
      if (_canonicalIdentityFromTag(term) case final identity?)
        _canonicalIdentityKey(identity.name, identity.franchise),
  };
}

String _canonicalIdentityKey(String name, String franchise) {
  final normalizedName = _normalizedCanonicalText(name);
  final normalizedFranchise = _normalizedCanonicalText(franchise);
  if (normalizedName.isEmpty || normalizedFranchise.isEmpty) {
    return '';
  }
  return '$normalizedName\u001f$normalizedFranchise';
}

String _normalizedCanonicalText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

_CanonicalIdentity? _canonicalIdentityFromTag(String tag) {
  final normalized = tag.trim();
  if (normalized.isEmpty || _isNonCharacterIdentityTag(normalized)) {
    return null;
  }
  final matches = RegExp(r'\(([^()]*)\)').allMatches(normalized).toList();
  if (matches.isEmpty) {
    return null;
  }
  final firstParen = matches.first.start;
  final rawName = normalized
      .substring(0, firstParen)
      .replaceAll(RegExp(r'[_\s]+$'), '')
      .trim();
  if (rawName.isEmpty || _isNonCharacterIdentityTag(rawName)) {
    return null;
  }
  final parentheticals = [
    for (final match in matches) match.group(1)?.trim() ?? '',
  ].where((value) => value.isNotEmpty).toList(growable: false);
  if (parentheticals.isEmpty) {
    return null;
  }
  final franchise = parentheticals.last;
  if (franchise.isEmpty || _isNonCharacterIdentityTag(franchise)) {
    return null;
  }
  return _CanonicalIdentity(
    name: rawName,
    franchise: franchise,
    variants: List.unmodifiable(parentheticals.take(parentheticals.length - 1)),
  );
}

bool _isNonCharacterIdentityTag(String tag) {
  final normalized = tag.trim().toLowerCase();
  return normalized.startsWith('artist:') ||
      normalized.startsWith('copyright:') ||
      normalized == 'copyright' ||
      normalized == 'official art' ||
      normalized == 'official style';
}

class _CanonicalIdentity {
  final String name;
  final String franchise;
  final List<String> variants;

  const _CanonicalIdentity({
    required this.name,
    required this.franchise,
    required this.variants,
  });
}

ScriptAiExtractedStage _mergeEquivalentStages(
  ScriptAiExtractedStage left,
  ScriptAiExtractedStage right,
) {
  return ScriptAiExtractedStage(
    stageId: left.stageId,
    label: left.label,
    appearanceGroupId: left.appearanceGroupId.isNotEmpty
        ? left.appearanceGroupId
        : right.appearanceGroupId,
    mergeWithStageIds: _mergedStrings(
      left.mergeWithStageIds,
      right.mergeWithStageIds,
    ),
    fieldReasons: _mergedStringMap(left.fieldReasons, right.fieldReasons),
    confidence: left.confidence >= right.confidence
        ? left.confidence
        : right.confidence,
    frameIndexes: _mergedInts(left.frameIndexes, right.frameIndexes),
    identity: _mergedStrings(
      _commaTerms(left.identity),
      _commaTerms(right.identity),
    ).join(', '),
    upperBody: _preferredStablePromptText(left.upperBody, right.upperBody),
    lowerBody: _preferredStablePromptText(left.lowerBody, right.lowerBody),
    upperClothing:
        _preferredStablePromptText(left.upperClothing, right.upperClothing),
    lowerClothing:
        _preferredStablePromptText(left.lowerClothing, right.lowerClothing),
    nonRole: _mergedStrings(
      _commaTerms(left.nonRole),
      _commaTerms(right.nonRole),
    ).join(', '),
    nonRoleMaterialized: left.nonRoleMaterialized || right.nonRoleMaterialized,
    evidenceTerms: _stableEvidenceTerms(
      _mergedStrings(left.evidenceTerms, right.evidenceTerms),
    ),
    missingFields: _mergedStrings(left.missingFields, right.missingFields),
    warnings: _mergedStrings(left.warnings, right.warnings),
  );
}

ScriptAiExtractedStage _stageWithFrameIndexes(
  ScriptAiExtractedStage stage,
  List<int> frameIndexes,
) {
  return ScriptAiExtractedStage(
    stageId: stage.stageId,
    label: stage.label,
    appearanceGroupId: stage.appearanceGroupId,
    mergeWithStageIds: stage.mergeWithStageIds,
    fieldReasons: stage.fieldReasons,
    confidence: stage.confidence,
    frameIndexes: List.unmodifiable(frameIndexes),
    identity: stage.identity,
    upperBody: stage.upperBody,
    lowerBody: stage.lowerBody,
    upperClothing: stage.upperClothing,
    lowerClothing: stage.lowerClothing,
    nonRole: stage.nonRole,
    nonRoleMaterialized: stage.nonRoleMaterialized,
    evidenceTerms: stage.evidenceTerms,
    missingFields: stage.missingFields,
    warnings: stage.warnings,
  );
}

ScriptAiExtractedStage _stageWithStageId(
  ScriptAiExtractedStage stage,
  String stageId,
) {
  return ScriptAiExtractedStage(
    stageId: stageId,
    label: stage.label,
    appearanceGroupId: stage.appearanceGroupId,
    mergeWithStageIds: stage.mergeWithStageIds,
    fieldReasons: stage.fieldReasons,
    confidence: stage.confidence,
    frameIndexes: stage.frameIndexes,
    identity: stage.identity,
    upperBody: stage.upperBody,
    lowerBody: stage.lowerBody,
    upperClothing: stage.upperClothing,
    lowerClothing: stage.lowerClothing,
    nonRole: stage.nonRole,
    nonRoleMaterialized: stage.nonRoleMaterialized,
    evidenceTerms: stage.evidenceTerms,
    missingFields: stage.missingFields,
    warnings: stage.warnings,
  );
}

String _uniqueStageId(String baseId, Set<String> used) {
  if (used.add(baseId)) {
    return baseId;
  }
  var suffix = 2;
  while (true) {
    final candidate = '$baseId-$suffix';
    if (used.add(candidate)) {
      return candidate;
    }
    suffix += 1;
  }
}

String _preferredStablePromptText(String left, String right) {
  final leftStable = _stablePromptFieldText(left);
  final rightStable = _stablePromptFieldText(right);
  if (_commaTerms(rightStable).length > _commaTerms(leftStable).length) {
    return rightStable;
  }
  if (leftStable.isNotEmpty) {
    return leftStable;
  }
  return rightStable;
}

String _stablePromptFieldText(String value) {
  return _commaTerms(value)
      .where((term) => !_isTransientRoleFieldTerm(term))
      .join(', ');
}

bool _isTransientRoleFieldTerm(String term) {
  final normalized = term
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return RegExp(
    r'(^|[^a-z0-9])('
    r'starting to take off|taking off|take off|undressing|undress|'
    r'undressing another clothes|undressing another|'
    r'removing|remove|pulling|pulled|pull|lifting|lifted|lift|'
    r'adjusting clothes|adjusting|dress tug|clothes tug|tug|'
    r'skirt flip|flipping|flip|'
    r'wet|sweaty|sweat|stained|stain|torn|ripped|damaged|open|'
    r'slipping|falling off|exposed|revealing|'
    r'nude|naked|topless|completly nude|completely nude|'
    r'covering ass|covering eyes|covering nipples|covering|'
    r'hand between breasts|hand over own mouth|arm around shoulder|'
    r'panties aside|panties around one leg|no panties|around one leg|aside|'
    r'smile|smiling|closed eyes|open mouth|winking|wink|blush|crying|'
    r'tears|angry|embarrassed|ahegao|tongue out|drool|drooling|'
    r'empty eyes|wavy mouth|mouth drool|'
    r'facial|penis on face|kissing penis|breasts out|bare shoulders|'
    r'looking at viewer|looking back|looking away|'
    r'kneeling|sitting|standing|lying|squatting|bending|bent over|'
    r'spread legs|legs spread|arms up|hands up|raised arms|walking|'
    r'running|jumping|crawling|straddling|riding|touching|grabbing|'
    r'holding|fingering|fingering through clothes|through clothes|'
    r'pov|close-up|close up|from behind|side view|dutch angle|camera|'
    r'sex|intercourse|masturbat(?:e|ing|ion)|penetrat(?:e|ing|ion)|'
    r'cum|semen|orgasm|ejaculat(?:e|ing|ion)|saliva|pussy juice|'
    r'often present|sometimes present|occasionally present|'
    r'in some frames|in some early frames|in some later frames|'
    r'only in some|some compromised frames|when visible|if visible|'
    r'when tagged|if tagged|depending frame|depending on frame|'
    r'not consistently tagged|not always tagged|varies by frame'
    r')([^a-z0-9]|$)',
  ).hasMatch(normalized);
}

bool _isLowerClothingFieldTerm(String term) {
  final normalized = term
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return RegExp(
    r'(^|[^a-z0-9])('
    r'panties|underwear|briefs|boxers|skirt|pants|shorts|trousers|'
    r'leggings|stockings?|socks?|thighhighs?|garter|legwear|'
    r'shoes?|boots?|sandals?|heels?|loafers?|barefoot'
    r')([^a-z0-9]|$)',
  ).hasMatch(normalized);
}

List<int> _mergedInts(List<int> left, List<int> right) {
  return List.unmodifiable(({...left, ...right}.toList()..sort()));
}

List<String> _mergedStrings(List<String> left, List<String> right) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in [...left, ...right]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return List.unmodifiable(result);
}

bool _stringListsEqual(List<String> left, List<String> right) {
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

Map<String, String> _mergedStringMap(
  Map<String, String> left,
  Map<String, String> right,
) {
  return Map.unmodifiable({
    ...right,
    ...left,
  });
}

List<String> _commaTerms(String value) {
  return [
    for (final term in value.split(RegExp(r'[,|]+')))
      if (term.trim().isNotEmpty) term.trim(),
  ];
}

class ScriptAiArtistChainEvidence {
  final String label;
  final List<String> terms;
  final List<int> frameIndexes;
  final double confidence;
  final List<String> evidenceTerms;

  const ScriptAiArtistChainEvidence({
    this.label = '',
    this.terms = const [],
    this.frameIndexes = const [],
    this.confidence = 0,
    this.evidenceTerms = const [],
  });

  factory ScriptAiArtistChainEvidence.fromJson(Map<String, dynamic> json) {
    return ScriptAiArtistChainEvidence(
      label: _stringValue(json['label']),
      terms: _stringList(json['terms']),
      frameIndexes: _intList(json['frame_indexes']),
      confidence: _doubleValue(json['confidence']),
      evidenceTerms: _stringList(json['evidence_terms']),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'terms': terms,
        'frame_indexes': frameIndexes,
        'confidence': confidence,
        'evidence_terms': evidenceTerms,
      };
}

class ScriptAiStrongFilterKeyword {
  final String term;
  final List<int> frameIndexes;
  final String reason;

  const ScriptAiStrongFilterKeyword({
    this.term = '',
    this.frameIndexes = const [],
    this.reason = '',
  });

  factory ScriptAiStrongFilterKeyword.fromJson(Map<String, dynamic> json) {
    return ScriptAiStrongFilterKeyword(
      term: _stringValue(json['term']),
      frameIndexes: _intList(json['frame_indexes']),
      reason: _stringValue(json['reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'term': term,
        'frame_indexes': frameIndexes,
        'reason': reason,
      };
}

class ScriptAiExtractionAttentionItem {
  final String id;
  final String kind;
  final String message;
  final String? sourceRoleId;
  final List<int> frameIndexes;
  final bool blocking;

  const ScriptAiExtractionAttentionItem({
    this.id = '',
    this.kind = '',
    this.message = '',
    this.sourceRoleId,
    this.frameIndexes = const [],
    this.blocking = false,
  });

  factory ScriptAiExtractionAttentionItem.fromJson(Map<String, dynamic> json) {
    return ScriptAiExtractionAttentionItem(
      id: _stringValue(json['id']),
      kind: _stringValue(json['kind']),
      message: _stringValue(json['message']),
      sourceRoleId: _optionalStringValue(json['source_role_id']),
      frameIndexes: _intList(json['frame_indexes']),
      blocking: _boolValue(json['blocking']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'message': message,
        if (_hasText(sourceRoleId)) 'source_role_id': sourceRoleId,
        'frame_indexes': frameIndexes,
        'blocking': blocking,
      };
}

class ScriptAiUnassignedTerm {
  final String term;
  final List<int> frameIndexes;
  final String reason;

  const ScriptAiUnassignedTerm({
    this.term = '',
    this.frameIndexes = const [],
    this.reason = '',
  });

  factory ScriptAiUnassignedTerm.fromJson(Map<String, dynamic> json) {
    return ScriptAiUnassignedTerm(
      term: _stringValue(json['term']),
      frameIndexes: _intList(json['frame_indexes']),
      reason: _stringValue(json['reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'term': term,
        'frame_indexes': frameIndexes,
        'reason': reason,
      };
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList(growable: false);
}

String _stringValue(Object? value) {
  return value is String ? value : '';
}

String? _optionalStringValue(Object? value) {
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value;
}

bool _hasText(String? value) {
  return value != null && value.trim().isNotEmpty;
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt() ?? fallback;
  return fallback;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable({
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  });
}

List<int> _intList(Object? value) {
  if (value is! List) return const [];
  return value.map(_intOrNull).whereType<int>().toList(growable: false);
}

int? _intOrNull(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt();
  return null;
}

ScriptAiRoleExtractionStatus _statusValue(Object? value) {
  if (value is! String) return ScriptAiRoleExtractionStatus.idle;
  final normalized = value.trim();
  if (normalized == 'needs_more_evidence' ||
      normalized == 'needsMoreEvidence') {
    return ScriptAiRoleExtractionStatus.needsMoreEvidence;
  }
  for (final status in ScriptAiRoleExtractionStatus.values) {
    if (status.name == normalized) return status;
  }
  return ScriptAiRoleExtractionStatus.idle;
}

String _statusJsonValue(ScriptAiRoleExtractionStatus status) {
  return switch (status) {
    ScriptAiRoleExtractionStatus.needsMoreEvidence => 'needs_more_evidence',
    _ => status.name,
  };
}
