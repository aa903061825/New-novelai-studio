import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';

const scriptRoleReplacementSharedLayerId = 'shared';
const scriptRoleReplacementPendingLayerId = 'pending';

String scriptRoleReplacementStageLayerId(String stageId) => 'stage:$stageId';

class ScriptRoleReplacementLayerAssignment {
  final String ruleId;
  final ScriptRoleReplacementRuleLayerKind kind;
  final String stageId;
  final bool isManual;
  final bool hasStaleOverride;

  const ScriptRoleReplacementLayerAssignment({
    required this.ruleId,
    required this.kind,
    this.stageId = '',
    this.isManual = false,
    this.hasStaleOverride = false,
  });

  String get layerId {
    switch (kind) {
      case ScriptRoleReplacementRuleLayerKind.shared:
        return scriptRoleReplacementSharedLayerId;
      case ScriptRoleReplacementRuleLayerKind.stage:
        return scriptRoleReplacementStageLayerId(stageId);
      case ScriptRoleReplacementRuleLayerKind.pending:
        return scriptRoleReplacementPendingLayerId;
    }
  }
}

class ScriptRoleReplacementLayer {
  final String id;
  final String label;
  final ScriptRoleReplacementRuleLayerKind kind;
  final String stageId;
  final List<int> frameIndexes;
  final List<String> ruleIds;
  final int mappedRuleCount;

  const ScriptRoleReplacementLayer({
    required this.id,
    required this.label,
    required this.kind,
    this.stageId = '',
    this.frameIndexes = const [],
    this.ruleIds = const [],
    this.mappedRuleCount = 0,
  });
}

class ScriptRoleReplacementLayerResult {
  final List<ScriptRoleReplacementLayer> layers;
  final Map<String, ScriptRoleReplacementLayerAssignment> assignmentsByRuleId;

  const ScriptRoleReplacementLayerResult({
    this.layers = const [],
    this.assignmentsByRuleId = const {},
  });

  ScriptRoleReplacementLayerAssignment? assignmentForRule(String ruleId) {
    return assignmentsByRuleId[ruleId];
  }
}

class ScriptRoleReplacementLayerService {
  const ScriptRoleReplacementLayerService();

  ScriptRoleReplacementLayerResult resolve({
    required ScriptRolePromptReplacement replacement,
    RoleAssembly? assembly,
  }) {
    final stages = assembly?.stages ?? const <RoleAssemblyStage>[];
    final stageById = {
      for (final stage in stages) stage.id: stage,
    };
    final overrideByRuleId = <String, ScriptRoleReplacementRuleLayerOverride>{
      for (final override in replacement.layerOverrides)
        override.ruleId: override,
    };
    final assignments = <String, ScriptRoleReplacementLayerAssignment>{};

    for (final rule in replacement.rules) {
      final override = overrideByRuleId[rule.id];
      if (override != null) {
        assignments[rule.id] = _manualAssignment(
          override,
          stageById: stageById,
        );
        continue;
      }
      assignments[rule.id] = _automaticAssignment(
        rule,
        stages: stages,
      );
    }

    final layerSpecs = <({
      String id,
      String label,
      ScriptRoleReplacementRuleLayerKind kind,
      String stageId,
      List<int> frameIndexes,
    })>[
      (
        id: scriptRoleReplacementSharedLayerId,
        label: '共享',
        kind: ScriptRoleReplacementRuleLayerKind.shared,
        stageId: '',
        frameIndexes: const <int>[],
      ),
      for (final stage in stages)
        (
          id: scriptRoleReplacementStageLayerId(stage.id),
          label: stage.label,
          kind: ScriptRoleReplacementRuleLayerKind.stage,
          stageId: stage.id,
          frameIndexes: _normalizedFrameIndexes(stage.frameIndexes),
        ),
      (
        id: scriptRoleReplacementPendingLayerId,
        label: '待确认',
        kind: ScriptRoleReplacementRuleLayerKind.pending,
        stageId: '',
        frameIndexes: const <int>[],
      ),
    ];

    final layers = <ScriptRoleReplacementLayer>[
      for (final spec in layerSpecs)
        ScriptRoleReplacementLayer(
          id: spec.id,
          label: spec.label,
          kind: spec.kind,
          stageId: spec.stageId,
          frameIndexes: spec.frameIndexes,
          ruleIds: [
            for (final rule in replacement.rules)
              if (assignments[rule.id]?.layerId == spec.id) rule.id,
          ],
          mappedRuleCount: replacement.rules.where((rule) {
            return assignments[rule.id]?.layerId == spec.id && rule.hasEffect;
          }).length,
        ),
    ];

    return ScriptRoleReplacementLayerResult(
      layers: List.unmodifiable(layers),
      assignmentsByRuleId: Map.unmodifiable(assignments),
    );
  }

  ScriptRoleReplacementLayerAssignment _manualAssignment(
    ScriptRoleReplacementRuleLayerOverride override, {
    required Map<String, RoleAssemblyStage> stageById,
  }) {
    switch (override.kind) {
      case ScriptRoleReplacementRuleLayerKind.shared:
        return ScriptRoleReplacementLayerAssignment(
          ruleId: override.ruleId,
          kind: ScriptRoleReplacementRuleLayerKind.shared,
          isManual: true,
        );
      case ScriptRoleReplacementRuleLayerKind.pending:
        return ScriptRoleReplacementLayerAssignment(
          ruleId: override.ruleId,
          kind: ScriptRoleReplacementRuleLayerKind.pending,
          isManual: true,
        );
      case ScriptRoleReplacementRuleLayerKind.stage:
        if (stageById.containsKey(override.stageId)) {
          return ScriptRoleReplacementLayerAssignment(
            ruleId: override.ruleId,
            kind: ScriptRoleReplacementRuleLayerKind.stage,
            stageId: override.stageId,
            isManual: true,
          );
        }
        return ScriptRoleReplacementLayerAssignment(
          ruleId: override.ruleId,
          kind: ScriptRoleReplacementRuleLayerKind.pending,
          isManual: true,
          hasStaleOverride: true,
        );
    }
  }

  ScriptRoleReplacementLayerAssignment _automaticAssignment(
    ScriptPromptReplacementRule rule, {
    required List<RoleAssemblyStage> stages,
  }) {
    final excludedIds = rule.excludedTermIds.toSet();
    final terms = [
      for (final term in rule.sourceTerms)
        if (!excludedIds.contains(term.id)) term,
    ];
    if (terms.isEmpty) {
      return _pending(rule.id);
    }
    if (terms.every((term) => term.category == PromptTagCategory.character)) {
      return _shared(rule.id);
    }
    if (stages.isEmpty) {
      return _pending(rule.id);
    }

    final evidenceByTerm = <String, List<int>>{
      for (final term in terms) term.id: _evidenceFrames(term),
    };
    final hasAnyEvidence =
        evidenceByTerm.values.any((frameIndexes) => frameIndexes.isNotEmpty);
    if (!hasAnyEvidence && stages.length == 1) {
      return _stage(rule.id, stages.single.id);
    }
    if (evidenceByTerm.values.any((frames) => frames.isEmpty)) {
      return _pending(rule.id);
    }

    final stageIdsByFrame = <int, Set<String>>{};
    for (final stage in stages) {
      for (final frameIndex in stage.frameIndexes) {
        stageIdsByFrame.putIfAbsent(frameIndex, () => <String>{}).add(stage.id);
      }
    }

    final hitStageIdsByTerm = <String, Set<String>>{};
    for (final entry in evidenceByTerm.entries) {
      final hitStageIds = <String>{};
      for (final frameIndex in entry.value) {
        final containingStages =
            stageIdsByFrame[frameIndex] ?? const <String>{};
        if (containingStages.length != 1) {
          return _pending(rule.id);
        }
        hitStageIds.add(containingStages.single);
      }
      hitStageIdsByTerm[entry.key] = hitStageIds;
    }

    final allStageIds = stages.map((stage) => stage.id).toSet();
    if (stages.length > 1 &&
        hitStageIdsByTerm.values.every(
          (stageIds) =>
              stageIds.length == allStageIds.length &&
              stageIds.containsAll(allStageIds),
        )) {
      return _shared(rule.id);
    }

    String? uniqueStageId;
    for (final stageIds in hitStageIdsByTerm.values) {
      if (stageIds.length != 1) {
        return _pending(rule.id);
      }
      final stageId = stageIds.single;
      if (uniqueStageId != null && uniqueStageId != stageId) {
        return _pending(rule.id);
      }
      uniqueStageId = stageId;
    }
    return uniqueStageId == null
        ? _pending(rule.id)
        : _stage(rule.id, uniqueStageId);
  }

  ScriptRoleReplacementLayerAssignment _shared(String ruleId) {
    return ScriptRoleReplacementLayerAssignment(
      ruleId: ruleId,
      kind: ScriptRoleReplacementRuleLayerKind.shared,
    );
  }

  ScriptRoleReplacementLayerAssignment _stage(String ruleId, String stageId) {
    return ScriptRoleReplacementLayerAssignment(
      ruleId: ruleId,
      kind: ScriptRoleReplacementRuleLayerKind.stage,
      stageId: stageId,
    );
  }

  ScriptRoleReplacementLayerAssignment _pending(String ruleId) {
    return ScriptRoleReplacementLayerAssignment(
      ruleId: ruleId,
      kind: ScriptRoleReplacementRuleLayerKind.pending,
    );
  }

  List<int> _evidenceFrames(ScriptPromptReplacementTerm term) {
    if (term.sourceOccurrences.isNotEmpty) {
      return _normalizedFrameIndexes(
        term.sourceOccurrences.map((occurrence) => occurrence.frameIndex),
      );
    }
    return _normalizedFrameIndexes(term.frameIndexes);
  }
}

List<int> _normalizedFrameIndexes(Iterable<int> values) {
  final normalized = values.where((value) => value >= 0).toSet().toList()
    ..sort();
  return List.unmodifiable(normalized);
}
