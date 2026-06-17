import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

class ScriptAiRoleExtractionMerger {
  const ScriptAiRoleExtractionMerger();

  ScriptAiRoleExtraction merge(List<ScriptAiRoleExtraction> extractions) {
    final readyExtractions = extractions
        .where((extraction) =>
            extraction.status == ScriptAiRoleExtractionStatus.ready)
        .toList(growable: false);
    final failureAttention = extractions
        .where((extraction) =>
            extraction.status == ScriptAiRoleExtractionStatus.failed)
        .expand((extraction) => extraction.attentionItems)
        .toList(growable: false);

    if (readyExtractions.isEmpty) {
      return ScriptAiRoleExtraction.failure(
        message: 'No ready AI role extractions to merge.',
        rawResponse: '',
      );
    }

    final roles = _mergeRoles(readyExtractions);
    final attentionItems = [
      ...failureAttention,
      for (final extraction in readyExtractions) ...extraction.attentionItems,
    ];

    return ScriptAiRoleExtraction(
      schemaVersion: 1,
      status: ScriptAiRoleExtractionStatus.ready,
      confidence: _averageConfidence(readyExtractions),
      roles: roles,
      artistChains: _mergeArtistChains(readyExtractions),
      strongFilterKeywords: _mergeStrongFilterKeywords(readyExtractions),
      attentionItems: List.unmodifiable(attentionItems),
      unassignedTerms: List.unmodifiable([
        for (final extraction in readyExtractions)
          ...extraction.unassignedTerms,
      ]),
    ).collapseEquivalentStages();
  }

  List<ScriptAiExtractedRole> _mergeRoles(
    List<ScriptAiRoleExtraction> extractions,
  ) {
    final slotAccumulators = <String, _RoleAccumulator>{};
    final crossSlotAccumulators = <String, _RoleAccumulator>{};
    final globalAccumulators = <_RoleAccumulator>[];
    final usedGlobalIds = <String>{};

    for (final extraction in extractions) {
      for (final role in extraction.roles) {
        if (_isSlotRole(role.sourceRoleId)) {
          slotAccumulators
              .putIfAbsent(role.sourceRoleId, () => _RoleAccumulator(role))
              .add(role);
        } else if (_isCrossSlotRole(role)) {
          final sourceRoleId = role.sourceRoleId.trim().isEmpty
              ? 'role-${crossSlotAccumulators.length}'
              : role.sourceRoleId;
          crossSlotAccumulators
              .putIfAbsent(
                sourceRoleId,
                () => _RoleAccumulator(role, sourceRoleId: sourceRoleId),
              )
              .add(role);
        } else {
          final sourceRoleId = _uniqueId(role.sourceRoleId, usedGlobalIds);
          globalAccumulators.add(
              _RoleAccumulator(role, sourceRoleId: sourceRoleId)..add(role));
        }
      }
    }

    return List.unmodifiable([
      for (final accumulator in slotAccumulators.values) accumulator.build(),
      for (final accumulator in crossSlotAccumulators.values)
        accumulator.build(),
      for (final accumulator in globalAccumulators) accumulator.build(),
    ]);
  }

  List<ScriptAiArtistChainEvidence> _mergeArtistChains(
    List<ScriptAiRoleExtraction> extractions,
  ) {
    final accumulators = <String, _ArtistChainAccumulator>{};
    for (final extraction in extractions) {
      for (final chain in extraction.artistChains) {
        final key = _artistChainKey(chain);
        accumulators
            .putIfAbsent(key, () => _ArtistChainAccumulator(chain))
            .add(chain);
      }
    }
    return List.unmodifiable([
      for (final accumulator in accumulators.values) accumulator.build(),
    ]);
  }

  List<ScriptAiStrongFilterKeyword> _mergeStrongFilterKeywords(
    List<ScriptAiRoleExtraction> extractions,
  ) {
    final accumulators = <String, _StrongFilterAccumulator>{};
    for (final extraction in extractions) {
      for (final keyword in extraction.strongFilterKeywords) {
        final key = _tagKey(keyword.term);
        if (key.isEmpty) continue;
        accumulators
            .putIfAbsent(key, () => _StrongFilterAccumulator(keyword))
            .add(keyword);
      }
    }
    return List.unmodifiable([
      for (final accumulator in accumulators.values) accumulator.build(),
    ]);
  }
}

class _RoleAccumulator {
  final String sourceRoleId;
  final String sourceKind;
  String displayName;
  String roleReason;
  String canonicalName;
  String franchise;
  String mergeWithRoleId;
  double confidence;
  var _confidenceCount = 0;
  final List<int> frameIndexes = [];
  final List<String> evidenceTerms = [];
  final List<String> warnings = [];
  final List<String> rawIdentityTags = [];
  final List<String> variantTags = [];
  final List<ScriptAiRoleAppearance> appearances = [];
  final List<ScriptAiExtractedStage> stages = [];
  final List<ScriptAiUnassignedTerm> unassignedTerms = [];
  final Set<String> _evidenceKeys = {};
  final Set<String> _warningKeys = {};
  final Set<String> _rawIdentityKeys = {};
  final Set<String> _variantKeys = {};
  final Set<String> _appearanceKeys = {};
  final Set<String> _emittedStageIds = {};

  _RoleAccumulator(
    ScriptAiExtractedRole role, {
    String? sourceRoleId,
  })  : sourceRoleId = sourceRoleId ?? role.sourceRoleId,
        sourceKind = role.sourceKind,
        displayName = role.displayName,
        roleReason = role.roleReason,
        canonicalName = role.canonicalName,
        franchise = role.franchise,
        mergeWithRoleId = role.mergeWithRoleId,
        confidence = 0;

  void add(ScriptAiExtractedRole role) {
    if (displayName.trim().isEmpty && role.displayName.trim().isNotEmpty) {
      displayName = role.displayName;
    }
    if (roleReason.trim().isEmpty && role.roleReason.trim().isNotEmpty) {
      roleReason = role.roleReason;
    }
    if (canonicalName.trim().isEmpty && role.canonicalName.trim().isNotEmpty) {
      canonicalName = role.canonicalName;
    }
    if (franchise.trim().isEmpty && role.franchise.trim().isNotEmpty) {
      franchise = role.franchise;
    }
    if (mergeWithRoleId.trim().isEmpty &&
        role.mergeWithRoleId.trim().isNotEmpty) {
      mergeWithRoleId = role.mergeWithRoleId;
    }
    confidence += role.confidence;
    _confidenceCount += 1;
    _addInts(frameIndexes, role.frameIndexes);
    _addStrings(evidenceTerms, _evidenceKeys, role.evidenceTerms);
    _addStrings(warnings, _warningKeys, role.warnings);
    _addStrings(rawIdentityTags, _rawIdentityKeys, role.rawIdentityTags);
    _addStrings(variantTags, _variantKeys, role.variantTags);
    _addAppearances(appearances, _appearanceKeys, role.appearances);
    unassignedTerms.addAll(role.unassignedTerms);
    for (final stage in role.stages) {
      stages.add(_copyStageWithId(stage, _uniqueStageId(stage.stageId)));
    }
  }

  ScriptAiExtractedRole build() {
    return ScriptAiExtractedRole(
      sourceRoleId: sourceRoleId,
      sourceKind: sourceKind,
      displayName: displayName,
      roleReason: roleReason,
      canonicalName: canonicalName,
      franchise: franchise,
      rawIdentityTags: List.unmodifiable(rawIdentityTags),
      variantTags: List.unmodifiable(variantTags),
      mergeWithRoleId: mergeWithRoleId,
      confidence: _confidenceCount == 0 ? 0 : confidence / _confidenceCount,
      frameIndexes: List.unmodifiable(frameIndexes),
      appearances: List.unmodifiable(appearances),
      evidenceTerms: List.unmodifiable(evidenceTerms),
      warnings: List.unmodifiable(warnings),
      stages: List.unmodifiable(stages),
      unassignedTerms: List.unmodifiable(unassignedTerms),
    );
  }

  String _uniqueStageId(String stageId) {
    final baseId = stageId.trim().isEmpty ? 'stage' : stageId;
    return _uniqueId(baseId, _emittedStageIds);
  }
}

class _ArtistChainAccumulator {
  String label;
  double confidence;
  final List<String> terms = [];
  final List<int> frameIndexes = [];
  final List<String> evidenceTerms = [];
  final Set<String> _termKeys = {};
  final Set<String> _evidenceKeys = {};

  _ArtistChainAccumulator(ScriptAiArtistChainEvidence chain)
      : label = chain.label,
        confidence = 0;

  void add(ScriptAiArtistChainEvidence chain) {
    if (label.trim().isEmpty && chain.label.trim().isNotEmpty) {
      label = chain.label;
    }
    if (chain.confidence > confidence) {
      confidence = chain.confidence;
    }
    _addStrings(terms, _termKeys, chain.terms);
    _addInts(frameIndexes, chain.frameIndexes);
    _addStrings(evidenceTerms, _evidenceKeys, chain.evidenceTerms);
  }

  ScriptAiArtistChainEvidence build() {
    return ScriptAiArtistChainEvidence(
      label: label,
      terms: List.unmodifiable(terms),
      frameIndexes: List.unmodifiable(frameIndexes),
      confidence: confidence,
      evidenceTerms: List.unmodifiable(evidenceTerms),
    );
  }
}

class _StrongFilterAccumulator {
  final String term;
  final String reason;
  final List<int> frameIndexes = [];

  _StrongFilterAccumulator(ScriptAiStrongFilterKeyword keyword)
      : term = keyword.term,
        reason = keyword.reason;

  void add(ScriptAiStrongFilterKeyword keyword) {
    _addInts(frameIndexes, keyword.frameIndexes);
  }

  ScriptAiStrongFilterKeyword build() {
    return ScriptAiStrongFilterKeyword(
      term: term,
      frameIndexes: List.unmodifiable(frameIndexes),
      reason: reason,
    );
  }
}

double _averageConfidence(List<ScriptAiRoleExtraction> extractions) {
  if (extractions.isEmpty) return 0;
  final total = extractions.fold<double>(
    0,
    (sum, extraction) => sum + extraction.confidence,
  );
  return total / extractions.length;
}

bool _isSlotRole(String sourceRoleId) => sourceRoleId.startsWith('slot-');

bool _isCrossSlotRole(ScriptAiExtractedRole role) {
  return role.sourceKind.trim() == 'cross_slot' ||
      role.appearances.isNotEmpty ||
      role.sourceRoleId.startsWith('role-');
}

String _uniqueId(String sourceRoleId, Set<String> usedIds) {
  final baseId = sourceRoleId.trim().isEmpty ? 'global' : sourceRoleId;
  if (usedIds.add(baseId)) {
    return baseId;
  }
  for (var suffix = 2;; suffix += 1) {
    final candidate = '$baseId-$suffix';
    if (usedIds.add(candidate)) {
      return candidate;
    }
  }
}

String _artistChainKey(ScriptAiArtistChainEvidence chain) {
  final termKeys =
      chain.terms.map(_tagKey).where((key) => key.isNotEmpty).toList()..sort();
  if (termKeys.isNotEmpty) return termKeys.join('|');
  final labelKey = _tagKey(chain.label);
  if (labelKey.isNotEmpty) return labelKey;
  return 'empty:${chain.label}:${chain.terms.join('|')}';
}

String _tagKey(String term) => PromptTagProcessor.normalizeMatchKey(term);

void _addInts(List<int> target, Iterable<int> values) {
  final seen = target.toSet();
  for (final value in values) {
    if (seen.add(value)) {
      target.add(value);
    }
  }
  target.sort();
}

void _addStrings(
  List<String> target,
  Set<String> seen,
  Iterable<String> values,
) {
  for (final value in values) {
    final key = _tagKey(value);
    if (key.isEmpty || !seen.add(key)) continue;
    target.add(value);
  }
}

void _addAppearances(
  List<ScriptAiRoleAppearance> target,
  Set<String> seen,
  Iterable<ScriptAiRoleAppearance> values,
) {
  for (final value in values) {
    final key = [
      value.sourceId.trim(),
      value.sourceKind.trim(),
      value.frameIndexes.join(','),
    ].join('|');
    if (key == '||' || !seen.add(key)) continue;
    target.add(value);
  }
}

ScriptAiExtractedStage _copyStageWithId(
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
