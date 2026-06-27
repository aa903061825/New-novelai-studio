import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/tools/nai_metadata_parser.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final cacheDir = Directory(options.cacheDir);
  if (!await cacheDir.exists()) {
    throw StateError('Cache directory does not exist: ${cacheDir.path}');
  }

  final backupDir =
      options.backupDir == null ? null : Directory(options.backupDir!);
  if (!options.dryRun && backupDir != null) {
    await backupDir.create(recursive: true);
  }

  final files = await cacheDir
      .list()
      .where((entry) => entry is File && entry.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));

  var changedFiles = 0;
  var changedExtractions = 0;
  var changedMappings = 0;
  var scannedCacheFiles = 0;
  var readyCaches = 0;
  var failedCaches = 0;
  var nonReadyCaches = 0;
  var roleCount = 0;
  var stageCount = 0;
  var mergedStageCount = 0;
  var slotlessBaseRoleAppearanceCount = 0;
  final scriptKeys = <String>{};
  final residuals = <_ResidualHit>[];
  final cacheIssues = <_CacheIssue>[];
  var repairedScriptSnapshots = 0;
  var unrepairedScriptSnapshots = 0;

  for (final file in files) {
    final rawText = await file.readAsString(encoding: utf8);
    final decoded = jsonDecode(rawText);
    if (decoded is! Map) {
      continue;
    }
    final json = Map<String, dynamic>.from(decoded);
    if (!_looksLikeRecastCache(json)) {
      continue;
    }
    scannedCacheFiles += 1;
    final scriptKey = _scriptKey(json);
    if (scriptKey.isNotEmpty) {
      scriptKeys.add(scriptKey);
    }
    var changed = false;
    Map<String, dynamic>? normalizedAi;

    if (_scriptSnapshotNeedsRepair(json)) {
      final parsedScript = await _parsedJsonScriptForMissingSnapshot(json);
      if (parsedScript != null) {
        final nextFingerprint = _sourceFingerprint(parsedScript);
        final nextSnapshot = parsedScript.toJson();
        final snapshotChanged = json['scriptId'] != parsedScript.id ||
            json['scriptName'] != parsedScript.name ||
            json['sourceRootPath'] != parsedScript.rootPath ||
            json['sourceFingerprint'] != nextFingerprint ||
            _jsonText(json['scriptSnapshot']) != _jsonText(nextSnapshot);
        if (snapshotChanged) {
          json['scriptId'] = parsedScript.id;
          json['scriptName'] = parsedScript.name;
          json['sourceRootPath'] = parsedScript.rootPath;
          json['sourceFingerprint'] = nextFingerprint;
          json['scriptSnapshot'] = nextSnapshot;
          changed = true;
          repairedScriptSnapshots += 1;
        }
      } else {
        unrepairedScriptSnapshots += 1;
        cacheIssues.add(
          _CacheIssue(
            fileName: file.uri.pathSegments.last,
            status: 'unrepaired_script_snapshot',
            reason: await _scriptSnapshotRepairFailureReason(json),
          ),
        );
      }
    }

    final ai = json['aiRoleExtraction'];
    if (ai is Map) {
      final before = ScriptAiRoleExtraction.fromJson(
        Map<String, dynamic>.from(ai),
      );
      final normalized = _normalizedExtraction(
        ai,
        scriptSnapshot: json['scriptSnapshot'],
      );
      normalizedAi = normalized;
      final after = ScriptAiRoleExtraction.fromJson(normalized);
      if (after.isReady) {
        readyCaches += 1;
        roleCount += after.roles.length;
        stageCount += after.roles.fold<int>(
          0,
          (sum, role) => sum + role.stages.length,
        );
        mergedStageCount += _positiveDelta(
          before.roles.fold<int>(0, (sum, role) => sum + role.stages.length),
          after.roles.fold<int>(0, (sum, role) => sum + role.stages.length),
        );
        slotlessBaseRoleAppearanceCount += _slotlessBaseAppearanceCount(after);
      } else if (after.isFailed) {
        failedCaches += 1;
        cacheIssues.add(
          _CacheIssue(
            fileName: file.uri.pathSegments.last,
            status: 'failed',
            reason: _attentionSummary(after),
          ),
        );
      } else {
        nonReadyCaches += 1;
        cacheIssues.add(
          _CacheIssue(
            fileName: file.uri.pathSegments.last,
            status: after.status.name,
            reason: _attentionSummary(after),
          ),
        );
      }
      if (_jsonText(normalized) != _jsonText(ai)) {
        json['aiRoleExtraction'] = normalized;
        changed = true;
        changedExtractions += 1;
      }
      residuals.addAll(_residualHits(file, normalized, 'aiRoleExtraction'));
    }

    final mapping = json['mapping'];
    if (mapping is Map && normalizedAi != null) {
      final normalized = _normalizedMapping(mapping, normalizedAi);
      if (_jsonText(normalized) != _jsonText(mapping)) {
        json['mapping'] = normalized;
        changed = true;
        changedMappings += 1;
      }
      residuals.addAll(_mappingResidualHits(file, normalized));
    }

    final chunks = json['aiRoleExtractionChunks'];
    if (chunks is List) {
      final nextChunks = <Object?>[];
      var chunksChanged = false;
      for (final (index, chunk) in chunks.indexed) {
        if (chunk is Map) {
          final normalized = _normalizedExtraction(chunk);
          if (_jsonText(normalized) != _jsonText(chunk)) {
            chunksChanged = true;
            changedExtractions += 1;
          }
          residuals.addAll(
            _residualHits(
              file,
              normalized,
              'aiRoleExtractionChunks[$index]',
            ),
          );
          nextChunks.add(normalized);
        } else {
          nextChunks.add(chunk);
        }
      }
      if (chunksChanged) {
        json['aiRoleExtractionChunks'] = nextChunks;
        changed = true;
      }
    }

    if (!changed) {
      continue;
    }
    changedFiles += 1;
    json['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    stdout.writeln('NORMALIZE ${file.uri.pathSegments.last}');
    if (options.dryRun) {
      continue;
    }
    if (backupDir != null) {
      await file.copy(_joinPath([backupDir.path, file.uri.pathSegments.last]));
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      encoding: utf8,
    );
  }

  stdout.writeln(
    'Scanned $scannedCacheFiles cache files; changed_files=$changedFiles; '
    'changed_extractions=$changedExtractions; '
    'changed_mappings=$changedMappings; residual_hits=${residuals.length}',
  );
  stdout.writeln(
    'Stats: scripts=${scriptKeys.length}; caches=$scannedCacheFiles; '
    'ready_caches=$readyCaches; failed_caches=$failedCaches; '
    'non_ready_caches=$nonReadyCaches; roles=$roleCount; '
    'stages=$stageCount; merged_stages=$mergedStageCount; '
    'slotless_base_role_appearances=$slotlessBaseRoleAppearanceCount; '
    'repaired_script_snapshots=$repairedScriptSnapshots; '
    'unrepaired_script_snapshots=$unrepairedScriptSnapshots; '
    'residual_issues=${residuals.length + cacheIssues.length}',
  );
  for (final hit in residuals.take(options.maxResidualPrint)) {
    stdout.writeln(
      'RESIDUAL ${hit.fileName} ${hit.section} ${hit.roleId} '
      '${hit.stageId} ${hit.field}: ${hit.value}',
    );
  }
  if (residuals.length > options.maxResidualPrint) {
    stdout.writeln(
      'RESIDUAL ... ${residuals.length - options.maxResidualPrint} more',
    );
  }
  for (final issue in cacheIssues.take(options.maxResidualPrint)) {
    stdout.writeln(
      'CACHE_ISSUE ${issue.fileName} ${issue.status}: ${issue.reason}',
    );
  }
  if (cacheIssues.length > options.maxResidualPrint) {
    stdout.writeln(
      'CACHE_ISSUE ... ${cacheIssues.length - options.maxResidualPrint} more',
    );
  }
  if (options.auditReportPath != null) {
    final report = File(options.auditReportPath!);
    await report.parent.create(recursive: true);
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'cache_dir': cacheDir.path,
        'dry_run': options.dryRun,
        'script_count': scriptKeys.length,
        'cache_count': scannedCacheFiles,
        'ready_caches': readyCaches,
        'failed_caches': failedCaches,
        'non_ready_caches': nonReadyCaches,
        'role_count': roleCount,
        'stage_count': stageCount,
        'merged_stage_count': mergedStageCount,
        'slotless_base_role_appearance_count': slotlessBaseRoleAppearanceCount,
        'changed_files': changedFiles,
        'changed_extractions': changedExtractions,
        'changed_mappings': changedMappings,
        'repaired_script_snapshots': repairedScriptSnapshots,
        'unrepaired_script_snapshots': unrepairedScriptSnapshots,
        'residual_issue_count': residuals.length + cacheIssues.length,
        'residual_hits': [for (final hit in residuals) hit.toJson()],
        'cache_issues': [for (final issue in cacheIssues) issue.toJson()],
      }),
      encoding: utf8,
    );
    stdout.writeln('Audit report: ${report.path}');
  }
}

bool _looksLikeRecastCache(Map<String, dynamic> json) {
  return json.containsKey('scriptId') ||
      json.containsKey('mapping') ||
      json.containsKey('aiRoleExtraction') ||
      json.containsKey('scriptSnapshot');
}

Map<String, dynamic> _normalizedExtraction(
  Map<dynamic, dynamic> value, {
  Object? scriptSnapshot,
}) {
  final extraction = ScriptAiRoleExtraction.fromJson(
    Map<String, dynamic>.from(value),
  ).collapseEquivalentStages();
  final evidence = _scriptSnapshotEvidence(scriptSnapshot);
  if (evidence == null) {
    return extraction.toJson();
  }
  return _extractionWithFrameEvidence(extraction, evidence).toJson();
}

_ScriptSnapshotEvidence? _scriptSnapshotEvidence(Object? value) {
  if (value is! Map) {
    return null;
  }
  final frames = value['frames'];
  if (frames is! List || frames.isEmpty) {
    return null;
  }
  final byFrameIndex = <int, _FramePromptEvidence>{};
  for (final frame in frames) {
    if (frame is! Map) {
      continue;
    }
    final index = _intFrom(frame['index']);
    final parsed = frame['parsed'];
    if (index == null || parsed is! Map) {
      continue;
    }
    byFrameIndex[index] = _FramePromptEvidence(
      baseCaption: _stringFrom(parsed['baseCaption']),
      charCaptions: [
        for (final caption in _dynamicList(parsed['charCaptions']))
          if (caption is String) caption,
      ],
    );
  }
  if (byFrameIndex.isEmpty) {
    return null;
  }
  return _ScriptSnapshotEvidence(Map.unmodifiable(byFrameIndex));
}

ScriptAiRoleExtraction _extractionWithFrameEvidence(
  ScriptAiRoleExtraction extraction,
  _ScriptSnapshotEvidence evidence,
) {
  var changed = false;
  final roles = [
    for (final role in extraction.roles)
      _roleWithFrameEvidence(
        role,
        evidence,
        onChanged: () => changed = true,
      ),
  ];
  if (!changed) {
    return extraction;
  }
  return ScriptAiRoleExtraction(
    schemaVersion: extraction.schemaVersion,
    status: extraction.status,
    chunkId: extraction.chunkId,
    confidence: extraction.confidence,
    roles: List.unmodifiable(roles),
    artistChains: extraction.artistChains,
    strongFilterKeywords: extraction.strongFilterKeywords,
    attentionItems: extraction.attentionItems,
    unassignedTerms: extraction.unassignedTerms,
    evidenceRequests: extraction.evidenceRequests,
    sceneTerms: extraction.sceneTerms,
    termCacheSuggestions: extraction.termCacheSuggestions,
    rawResponse: extraction.rawResponse,
  );
}

ScriptAiExtractedRole _roleWithFrameEvidence(
  ScriptAiExtractedRole role,
  _ScriptSnapshotEvidence evidence, {
  required void Function() onChanged,
}) {
  if (role.stages.isEmpty || role.appearances.isEmpty) {
    return role;
  }
  final captionsByFrame = _roleCaptionsByFrame(role, evidence);
  if (captionsByFrame.isEmpty) {
    return role;
  }
  var changed = false;
  final nextPromptTerms = _promptTermsWithFrameEvidence(
    role: role,
    captionsByFrame: captionsByFrame,
  );
  if (_jsonText([
        for (final term in nextPromptTerms) term.toJson(),
      ]) !=
      _jsonText([
        for (final term in role.promptTerms) term.toJson(),
      ])) {
    changed = true;
  }
  final stages = <ScriptAiExtractedStage>[];
  for (final stage in role.stages) {
    final splitStages = _stagesSplitByFrameEvidence(
      stage,
      captionsByFrame,
    );
    if (splitStages.length != 1 ||
        _jsonText(splitStages.single.toJson()) != _jsonText(stage.toJson())) {
      changed = true;
    }
    stages.addAll(splitStages);
  }
  if (!changed) {
    return role;
  }
  onChanged();
  final usedStageIds = <String>{};
  final uniqueStages = <ScriptAiExtractedStage>[];
  for (final (index, stage) in stages.indexed) {
    final fallback = 'stage-${index + 1}';
    final rawId = stage.stageId.trim().isEmpty ? fallback : stage.stageId;
    uniqueStages
        .add(_aiStageWithStageId(stage, _uniqueStageId(rawId, usedStageIds)));
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
    warnings: _mergedToolStrings(
      role.warnings,
      const ['frame_evidence_stage_normalized'],
    ),
    stages: List.unmodifiable(uniqueStages),
    unassignedTerms: role.unassignedTerms,
    promptTerms: nextPromptTerms,
  );
}

List<ScriptAiExtractedPromptTerm> _promptTermsWithFrameEvidence({
  required ScriptAiExtractedRole role,
  required Map<int, List<String>> captionsByFrame,
}) {
  final termsByKey = <String, ScriptAiExtractedPromptTerm>{};
  final order = <String>[];

  void addTerm(ScriptAiExtractedPromptTerm term) {
    final text = term.text.trim();
    if (text.isEmpty) {
      return;
    }
    final category = term.category;
    final key = '${category.name}\u001f${_normalizedEvidenceText(text)}';
    final existing = termsByKey[key];
    if (existing == null) {
      termsByKey[key] = term;
      order.add(key);
      return;
    }
    termsByKey[key] = ScriptAiExtractedPromptTerm(
      id: existing.id.trim().isNotEmpty ? existing.id : term.id,
      text: existing.text.trim().isNotEmpty ? existing.text : term.text,
      category: existing.category,
      sourcePhrase: existing.sourcePhrase.trim().isNotEmpty
          ? existing.sourcePhrase
          : term.sourcePhrase,
      sourceLocation: existing.sourceLocation.trim().isNotEmpty
          ? existing.sourceLocation
          : term.sourceLocation,
      frameIndexes: _mergedToolInts(
        existing.frameIndexes,
        term.frameIndexes,
      ),
    );
  }

  for (final term in role.promptTerms) {
    addTerm(term);
  }

  return List.unmodifiable([
    for (final key in order) termsByKey[key]!,
  ]);
}

Map<int, List<String>> _roleCaptionsByFrame(
  ScriptAiExtractedRole role,
  _ScriptSnapshotEvidence evidence,
) {
  final result = <int, List<String>>{};

  void addCaption(int frameIndex, String caption) {
    final trimmed = caption.trim();
    if (trimmed.isEmpty) {
      return;
    }
    result.putIfAbsent(frameIndex, () => <String>[]).add(trimmed);
  }

  for (final appearance in role.appearances) {
    final slot = _slotIndexFromSourceId(appearance.sourceId);
    for (final frameIndex in appearance.frameIndexes) {
      final frame = evidence.byFrameIndex[frameIndex];
      if (frame == null) {
        continue;
      }
      if (slot != null) {
        if (slot >= 0 && slot < frame.charCaptions.length) {
          addCaption(frameIndex, frame.charCaptions[slot]);
        }
        continue;
      }
      if (_isBaseAppearance(appearance)) {
        addCaption(frameIndex, frame.baseCaption);
      }
    }
  }
  final frozen = <int, List<String>>{};
  for (final entry in result.entries) {
    frozen[entry.key] = List.unmodifiable(entry.value);
  }
  return Map.unmodifiable(frozen);
}

int? _slotIndexFromSourceId(String sourceId) {
  final match =
      RegExp(r'^slot-(\d+)$', caseSensitive: false).firstMatch(sourceId.trim());
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

bool _isBaseAppearance(ScriptAiRoleAppearance appearance) {
  final sourceId = appearance.sourceId.trim().toLowerCase();
  final sourceKind = appearance.sourceKind.trim().toLowerCase();
  return sourceId == 'base' ||
      sourceId == 'global' ||
      sourceKind == 'base' ||
      sourceKind == 'global';
}

List<ScriptAiExtractedStage> _stagesSplitByFrameEvidence(
  ScriptAiExtractedStage stage,
  Map<int, List<String>> captionsByFrame,
) {
  final stageFrames = stage.frameIndexes.toList()..sort();
  if (stageFrames.length < 2) {
    return [stage];
  }
  final fieldTerms = _StageEvidenceTerms.fromStage(stage);
  if (!fieldTerms.hasStableTerms) {
    return [stage];
  }

  final groups = <String, _StageEvidenceGroup>{};
  var omittedAnyTerm = false;
  for (final frameIndex in stageFrames) {
    final captions = captionsByFrame[frameIndex] ?? const <String>[];
    final frameTerms = fieldTerms.termsForCaptions(captions);
    omittedAnyTerm = omittedAnyTerm || frameTerms.omittedAnyTerm;
    final key = frameTerms.key;
    groups
        .putIfAbsent(key, () => _StageEvidenceGroup(frameTerms))
        .frameIndexes
        .add(frameIndex);
  }

  if (!omittedAnyTerm || groups.length < 2) {
    return [stage];
  }

  final result = <ScriptAiExtractedStage>[];
  var splitIndex = 0;
  for (final group in groups.values) {
    splitIndex += 1;
    final suffix = splitIndex == 1 ? '' : '-evidence-$splitIndex';
    result.add(
      ScriptAiExtractedStage(
        stageId: '${stage.stageId}$suffix',
        label: splitIndex == 1 ? stage.label : '${stage.label} $splitIndex',
        appearanceGroupId: stage.appearanceGroupId,
        mergeWithStageIds: stage.mergeWithStageIds,
        fieldReasons: stage.fieldReasons,
        confidence: stage.confidence,
        frameIndexes: List.unmodifiable(group.frameIndexes),
        identity: stage.identity,
        upperBody: group.terms.upperBody.join(', '),
        lowerBody: group.terms.lowerBody.join(', '),
        upperClothing: group.terms.upperClothing.join(', '),
        lowerClothing: group.terms.lowerClothing.join(', '),
        nonRole: stage.nonRole,
        nonRoleMaterialized: stage.nonRoleMaterialized,
        evidenceTerms: stage.evidenceTerms,
        missingFields: stage.missingFields,
        warnings: _mergedToolStrings(
          stage.warnings,
          const ['frame_evidence_stage_split'],
        ),
      ),
    );
  }
  return List.unmodifiable(result);
}

ScriptAiExtractedStage _aiStageWithStageId(
  ScriptAiExtractedStage stage,
  String stageId,
) {
  if (stage.stageId == stageId) {
    return stage;
  }
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

class _ScriptSnapshotEvidence {
  final Map<int, _FramePromptEvidence> byFrameIndex;

  const _ScriptSnapshotEvidence(this.byFrameIndex);
}

class _FramePromptEvidence {
  final String baseCaption;
  final List<String> charCaptions;

  const _FramePromptEvidence({
    required this.baseCaption,
    required this.charCaptions,
  });
}

class _StageEvidenceTerms {
  final List<String> upperBody;
  final List<String> lowerBody;
  final List<String> upperClothing;
  final List<String> lowerClothing;

  const _StageEvidenceTerms({
    required this.upperBody,
    required this.lowerBody,
    required this.upperClothing,
    required this.lowerClothing,
  });

  factory _StageEvidenceTerms.fromStage(ScriptAiExtractedStage stage) {
    return _StageEvidenceTerms(
      upperBody: _toolCommaTerms(stage.upperBody),
      lowerBody: _toolCommaTerms(stage.lowerBody),
      upperClothing: _toolCommaTerms(stage.upperClothing),
      lowerClothing: _toolCommaTerms(stage.lowerClothing),
    );
  }

  bool get hasStableTerms =>
      upperBody.isNotEmpty ||
      lowerBody.isNotEmpty ||
      upperClothing.isNotEmpty ||
      lowerClothing.isNotEmpty;

  _StageEvidenceTermsForFrame termsForCaptions(List<String> captions) {
    final caption = _normalizedEvidenceText(captions.join(', '));
    final upperBodyTerms = _termsSupportedForFrame(
      upperBody,
      caption,
      field: _EvidenceField.body,
    );
    final lowerBodyTerms = _termsSupportedForFrame(
      lowerBody,
      caption,
      field: _EvidenceField.body,
    );
    final upperClothingTerms = _termsSupportedForFrame(
      upperClothing,
      caption,
      field: _EvidenceField.clothing,
    );
    final lowerClothingTerms = _termsSupportedForFrame(
      lowerClothing,
      caption,
      field: _EvidenceField.clothing,
    );
    return _StageEvidenceTermsForFrame(
      upperBody: upperBodyTerms.terms,
      lowerBody: lowerBodyTerms.terms,
      upperClothing: upperClothingTerms.terms,
      lowerClothing: lowerClothingTerms.terms,
      omittedAnyTerm: upperBodyTerms.omittedAnyTerm ||
          lowerBodyTerms.omittedAnyTerm ||
          upperClothingTerms.omittedAnyTerm ||
          lowerClothingTerms.omittedAnyTerm,
    );
  }
}

class _StageEvidenceTermsForFrame {
  final List<String> upperBody;
  final List<String> lowerBody;
  final List<String> upperClothing;
  final List<String> lowerClothing;
  final bool omittedAnyTerm;

  const _StageEvidenceTermsForFrame({
    required this.upperBody,
    required this.lowerBody,
    required this.upperClothing,
    required this.lowerClothing,
    required this.omittedAnyTerm,
  });

  String get key => [
        upperBody.join('\u001e'),
        lowerBody.join('\u001e'),
        upperClothing.join('\u001e'),
        lowerClothing.join('\u001e'),
      ].join('\u001f');
}

class _StageEvidenceGroup {
  final _StageEvidenceTermsForFrame terms;
  final List<int> frameIndexes = <int>[];

  _StageEvidenceGroup(this.terms);
}

enum _EvidenceField { body, clothing }

class _SupportedTerms {
  final List<String> terms;
  final bool omittedAnyTerm;

  const _SupportedTerms({
    required this.terms,
    required this.omittedAnyTerm,
  });
}

_SupportedTerms _termsSupportedForFrame(
  List<String> terms,
  String caption, {
  required _EvidenceField field,
}) {
  var omittedAnyTerm = false;
  final supported = <String>[];
  for (final term in terms) {
    final normalizedTerm = _normalizedEvidenceText(term);
    if (normalizedTerm.isEmpty || caption.contains(normalizedTerm)) {
      supported.add(term);
      continue;
    }
    final contradicted = field == _EvidenceField.clothing
        ? _captionContradictsClothingTerm(caption)
        : _captionContradictsBodyTerm(caption, normalizedTerm);
    if (contradicted) {
      omittedAnyTerm = true;
      continue;
    }
    supported.add(term);
  }
  return _SupportedTerms(
    terms: List.unmodifiable(supported),
    omittedAnyTerm: omittedAnyTerm,
  );
}

bool _captionContradictsClothingTerm(String normalizedCaption) {
  return RegExp(
    r'(^|[^a-z0-9])('
    r'nude|naked|completly nude|completely nude|topless|no clothes|'
    r'unclothed'
    r')([^a-z0-9]|$)',
  ).hasMatch(normalizedCaption);
}

bool _captionContradictsBodyTerm(String normalizedCaption, String term) {
  if (term.contains('large breasts')) {
    return normalizedCaption.contains('small breasts');
  }
  if (term.contains('small breasts')) {
    return normalizedCaption.contains('large breasts');
  }
  return false;
}

String _normalizedEvidenceText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _toolCommaTerms(String value) {
  return [
    for (final term in value.split(RegExp(r'[,|]+')))
      if (term.trim().isNotEmpty) term.trim(),
  ];
}

List<String> _mergedToolStrings(List<String> left, List<String> right) {
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

List<int> _mergedToolInts(List<int> left, List<int> right) {
  final values = {...left, ...right}.toList()..sort();
  return List.unmodifiable(values);
}

List<dynamic> _dynamicList(Object? value) {
  return value is List ? value : const [];
}

String _stringFrom(Object? value) {
  return value is String ? value : '';
}

int? _intFrom(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool _scriptSnapshotNeedsRepair(Map<String, dynamic> cacheJson) {
  final snapshot = cacheJson['scriptSnapshot'];
  if (snapshot is Map) {
    final frames = snapshot['frames'];
    return frames is! List ||
        frames.isEmpty ||
        _scriptSnapshotLooksLikePixivSkeleton(frames) ||
        _scriptSnapshotMissingJsonPreviewImages(cacheJson, frames);
  }
  return true;
}

bool _scriptSnapshotMissingJsonPreviewImages(
  Map<String, dynamic> cacheJson,
  List<dynamic> frames,
) {
  for (final frame in frames) {
    if (frame is! Map) {
      continue;
    }
    final fileName = _stringFrom(frame['fileName']);
    if (!fileName.toLowerCase().endsWith('.json')) {
      continue;
    }
    if (_stringFrom(frame['sourceImagePath']).trim().isNotEmpty) {
      continue;
    }
    final sourcePath = _stringFrom(frame['sourcePath']);
    final jsonFile = sourcePath.trim().isNotEmpty
        ? File(sourcePath)
        : File(_joinPath([
            _stringFrom(cacheJson['sourceRootPath']),
            fileName,
          ]));
    if (_matchingImageForJsonFile(jsonFile) != null) {
      return true;
    }
  }
  return false;
}

bool _scriptSnapshotLooksLikePixivSkeleton(List<dynamic> frames) {
  for (final frame in frames) {
    if (frame is! Map) {
      continue;
    }
    final parsed = frame['parsed'];
    if (parsed is! Map) {
      continue;
    }
    final sourcePayload = parsed['sourcePayload'];
    if (sourcePayload is! Map) {
      continue;
    }
    if (sourcePayload['source_kind'] == 'pixiv_image_set_frame') {
      return true;
    }
  }
  return false;
}

Future<Script?> _parsedJsonScriptForMissingSnapshot(
  Map<String, dynamic> cacheJson,
) async {
  final sourceRootPath = cacheJson['sourceRootPath'];
  if (sourceRootPath is! String || sourceRootPath.trim().isEmpty) {
    return null;
  }
  final sourceDir = Directory(sourceRootPath);
  if (!await sourceDir.exists()) {
    return null;
  }
  final pngScript = await _parsePngMetadataScriptDirectory(
    sourceDir,
    cacheJson,
  );
  if (pngScript != null) {
    return pngScript;
  }

  final script = await _parseJsonScriptDirectory(sourceDir);
  if (script.frames.isEmpty) {
    final pixivScript = await _parsePixivImageSetDirectory(
      sourceDir,
      cacheJson,
    );
    if (pixivScript != null) {
      return pixivScript;
    }
  }
  return script;
}

Future<String> _scriptSnapshotRepairFailureReason(
  Map<String, dynamic> cacheJson,
) async {
  final sourceRootPath = cacheJson['sourceRootPath'];
  if (sourceRootPath is! String || sourceRootPath.trim().isEmpty) {
    return 'missing sourceRootPath; cannot rebuild scriptSnapshot frames';
  }
  final sourceDir = Directory(sourceRootPath);
  if (!await sourceDir.exists()) {
    return 'sourceRootPath does not exist: $sourceRootPath';
  }
  final jsonFiles = <String>[];
  final pngFiles = <String>[];
  await for (final entity in sourceDir.list(followLinks: false)) {
    if (entity is File && _fileName(entity).toLowerCase().endsWith('.json')) {
      jsonFiles.add(_fileName(entity));
    }
    if (entity is File && _fileName(entity).toLowerCase().endsWith('.png')) {
      pngFiles.add(_fileName(entity));
    }
  }
  if (jsonFiles.isEmpty && pngFiles.isEmpty) {
    return 'sourceRootPath exists but contains no JSON script frames or PNG images';
  }
  if (jsonFiles.isEmpty) {
    return 'sourceRootPath has ${pngFiles.length} PNG images but none contain '
        'prompt-bearing PNG text metadata';
  }
  if (pngFiles.isEmpty) {
    return 'sourceRootPath has ${jsonFiles.length} JSON files but none contain '
        'prompt-bearing script metadata';
  }
  return 'sourceRootPath has ${jsonFiles.length} JSON files but none contain '
      'prompt-bearing script metadata; ${pngFiles.length} PNG images also did '
      'not provide usable prompt metadata';
}

Future<Script> _parseJsonScriptDirectory(Directory directory) async {
  final files = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File && _fileName(entity).toLowerCase().endsWith('.json')) {
      files.add(entity);
    }
  }
  files.sort(
      (left, right) => _naturalCompare(_fileName(left), _fileName(right)));

  final frames = <ScriptFrame>[];
  for (final file in files) {
    final frame = await _parseJsonScriptFrame(file, frames.length + 1);
    if (frame != null) {
      frames.add(frame);
    }
  }
  return Script(
    id: _scriptIdForDirectory(directory),
    name: _directoryName(directory),
    rootPath: directory.path,
    frames: List.unmodifiable(frames),
    detectedSchema: _voteSchema(frames),
    parseWarnings: frames.isEmpty
        ? const [
            'No prompt-bearing JSON script frames found in this directory.'
          ]
        : frames.expand((frame) => frame.warnings).toList(growable: false),
    meta: {
      'frameCount': frames.length,
    },
  );
}

Future<Script?> _parsePixivImageSetDirectory(
  Directory directory,
  Map<String, dynamic> cacheJson,
) async {
  final infoFile = File(_joinPath([directory.path, 'info.json']));
  if (!await infoFile.exists()) {
    return null;
  }
  final imageFiles = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    if (RegExp(r'^p\d+\.png$', caseSensitive: false)
        .hasMatch(_fileName(entity))) {
      imageFiles.add(entity);
    }
  }
  if (imageFiles.isEmpty) {
    return null;
  }
  imageFiles.sort(
    (left, right) => _naturalCompare(_fileName(left), _fileName(right)),
  );

  final slotCount = _slotCaptionCountForCache(cacheJson);
  final frames = <ScriptFrame>[];
  for (final (index, imageFile) in imageFiles.indexed) {
    final stat = await imageFile.stat();
    final sourcePayload = _pixivImageFramePayload(
      imageFile: imageFile,
      infoFile: infoFile,
      pageIndex: index,
      slotCount: slotCount,
      fileStat: stat,
    );
    final rawJson = jsonEncode(sourcePayload);
    frames.add(
      ScriptFrame(
        index: index + 1,
        fileName: _fileName(imageFile),
        sourcePath: imageFile.path,
        sourceImagePath: imageFile.path,
        rawJson: rawJson,
        parsed: ParsedFrame(
          charCaptions: List.unmodifiable(List.filled(slotCount, '')),
          negativeCharCaptions: List.unmodifiable(List.filled(slotCount, '')),
          sourcePayload: Map.unmodifiable(sourcePayload),
        ),
        detectedSchema:
            slotCount > 0 ? ScriptSchema.v4Slotted : ScriptSchema.unknown,
        parseStatus: ScriptFrameParseStatus.parsed,
        warnings: const [
          'Rebuilt from Pixiv image-set files; original prompt metadata is unavailable.',
        ],
      ),
    );
  }

  return Script(
    id: _cacheString(cacheJson, 'scriptId') ?? _scriptIdForDirectory(directory),
    name: _cacheString(cacheJson, 'scriptName') ?? _directoryName(directory),
    rootPath: directory.path,
    frames: List.unmodifiable(frames),
    detectedSchema:
        slotCount > 0 ? ScriptSchema.v4Slotted : ScriptSchema.unknown,
    parseWarnings: const [
      'Rebuilt from Pixiv image-set files; original prompt metadata is unavailable.',
    ],
    meta: {
      'frameCount': frames.length,
      'sourceKind': 'pixiv_image_set',
    },
  );
}

Future<Script?> _parsePngMetadataScriptDirectory(
  Directory directory,
  Map<String, dynamic> cacheJson,
) async {
  final imageFiles = await _scriptPngFiles(directory);
  if (imageFiles.isEmpty) {
    return null;
  }

  final slotCount = _slotCaptionCountForCache(cacheJson);
  final frames = <ScriptFrame>[];
  var promptMetadataFrames = 0;
  final skippedMetadataFiles = <String>[];
  for (final imageFile in imageFiles) {
    final frame = await _parsePngMetadataScriptFrame(
      imageFile,
      frames.length + 1,
      slotCount,
    );
    if (frame != null) {
      frames.add(frame);
      promptMetadataFrames += 1;
    } else {
      skippedMetadataFiles.add(_fileName(imageFile));
    }
  }

  if (promptMetadataFrames == 0) {
    return null;
  }

  final parseWarnings = <String>[
    'Rebuilt from PNG prompt metadata text chunks.',
    if (skippedMetadataFiles.isNotEmpty)
      'Skipped ${skippedMetadataFiles.length} PNG images because prompt '
          'metadata was missing or unreadable: '
          '${skippedMetadataFiles.join(', ')}.',
  ];
  return Script(
    id: _cacheString(cacheJson, 'scriptId') ?? _scriptIdForDirectory(directory),
    name: _cacheString(cacheJson, 'scriptName') ?? _directoryName(directory),
    rootPath: directory.path,
    frames: List.unmodifiable(frames),
    detectedSchema: _voteSchema(frames),
    parseWarnings: List.unmodifiable(parseWarnings),
    meta: {
      'frameCount': frames.length,
      'sourceKind': 'png_metadata',
      'promptMetadataFrameCount': promptMetadataFrames,
      'skippedMetadataFrameCount': skippedMetadataFiles.length,
      if (skippedMetadataFiles.isNotEmpty)
        'skippedMetadataFiles': List.unmodifiable(skippedMetadataFiles),
    },
  );
}

Future<List<File>> _scriptPngFiles(Directory directory) async {
  final allPngFiles = <File>[];
  final numberedPngFiles = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final fileName = _fileName(entity);
    if (!fileName.toLowerCase().endsWith('.png')) {
      continue;
    }
    allPngFiles.add(entity);
    if (RegExp(r'^p\d+\.png$', caseSensitive: false).hasMatch(fileName)) {
      numberedPngFiles.add(entity);
    }
  }
  final files = numberedPngFiles.isNotEmpty ? numberedPngFiles : allPngFiles;
  files.sort(
    (left, right) => _naturalCompare(_fileName(left), _fileName(right)),
  );
  return List.unmodifiable(files);
}

Future<ScriptFrame?> _parsePngMetadataScriptFrame(
  File file,
  int index,
  int slotCount,
) async {
  try {
    final bytes = await file.readAsBytes();
    var metadataPayload = _extractPngTextChunks(bytes);
    var metadata = metadataPayload.isEmpty
        ? null
        : NaiMetadataParser.parseMap(metadataPayload);
    var rawContent = jsonEncode(metadataPayload);
    if (metadata == null || !_hasPromptMetadata(metadata)) {
      final stealthMetadata = _extractStealthPngMetadata(bytes);
      if (stealthMetadata == null || stealthMetadata.trim().isEmpty) {
        return null;
      }
      metadata = NaiMetadataParser.parseString(stealthMetadata);
      metadataPayload = _sourcePayloadFromMetadata(metadata);
      rawContent = stealthMetadata;
    }
    if (!_hasPromptMetadata(metadata)) {
      return null;
    }
    final sourcePayload = <String, dynamic>{
      ..._sourcePayloadFromMetadata(metadata),
      'source_kind': 'png_metadata_frame',
      'source_image_path': file.path,
    };
    final parsed = ParsedFrame(
      baseCaption: metadata.prompt ?? '',
      charCaptions: List.unmodifiable(metadata.charCaptions),
      negativeBase: metadata.negativePrompt ?? '',
      negativeCharCaptions: List.unmodifiable(metadata.negativeCharCaptions),
      coords: List.unmodifiable(
        metadata.coords.map(
          (coord) => RecastPoint(
            x: coord['x']!.toDouble(),
            y: coord['y']!.toDouble(),
          ),
        ),
      ),
      generationParams: Map.unmodifiable(metadata.parameters),
      sourcePayload: Map.unmodifiable(sourcePayload),
    );
    return ScriptFrame(
      index: index,
      fileName: _fileName(file),
      sourcePath: file.path,
      sourceImagePath: file.path,
      rawJson:
          rawContent.trim().isEmpty ? jsonEncode(sourcePayload) : rawContent,
      parsed: parsed,
      detectedSchema: _detectFrameSchema(parsed),
      parseStatus: ScriptFrameParseStatus.parsed,
    );
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

Map<String, dynamic> _extractPngTextChunks(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) {
    return const {};
  }
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) {
      return const {};
    }
  }

  final metadata = <String, dynamic>{};
  var cursor = signature.length;
  while (cursor + 8 <= bytes.length) {
    final chunkLength = _pngUint32(bytes, cursor);
    cursor += 4;
    final typeStart = cursor;
    final typeEnd = typeStart + 4;
    if (typeEnd > bytes.length) {
      break;
    }
    final type = utf8.decode(
      Uint8List.sublistView(bytes, typeStart, typeEnd),
      allowMalformed: true,
    );
    cursor = typeEnd;
    final dataStart = cursor;
    final dataEnd = dataStart + chunkLength;
    if (dataEnd + 4 > bytes.length) {
      break;
    }
    final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
    switch (type) {
      case 'tEXt':
        final entry = _parsePngTextChunk(data);
        if (entry != null) {
          metadata[entry.key] = entry.value;
        }
        break;
      case 'zTXt':
        final entry = _parsePngCompressedTextChunk(data);
        if (entry != null) {
          metadata[entry.key] = entry.value;
        }
        break;
      case 'iTXt':
        final entry = _parsePngInternationalTextChunk(data);
        if (entry != null) {
          metadata[entry.key] = entry.value;
        }
        break;
    }
    cursor = dataEnd + 4;
    if (type == 'IEND') {
      break;
    }
  }
  return metadata;
}

String? _extractStealthPngMetadata(Uint8List bytes) {
  final image = img.decodePng(bytes);
  if (image == null) {
    return null;
  }
  final reader = _AlphaBitReader(image);
  final headerBytes = reader.readBytes('stealth_pngcomp'.length);
  final header = utf8.decode(headerBytes, allowMalformed: true);
  if (header != 'stealth_pngcomp' && header != 'stealth_pnginfo') {
    return null;
  }
  final compressed = header == 'stealth_pngcomp';

  final bitLengthBytes = reader.readBytes(4);
  if (bitLengthBytes.length < 4) {
    return null;
  }
  final bitLength =
      ByteData.sublistView(Uint8List.fromList(bitLengthBytes)).getInt32(0);
  if (bitLength <= 0) {
    return null;
  }

  final dataLength = (bitLength / 8).ceil();
  if (dataLength > reader.remainingByteCapacity) {
    return null;
  }
  final compressedData = reader.readBytes(dataLength);
  if (compressedData.length < dataLength) {
    return null;
  }
  try {
    final data = Uint8List.fromList(compressedData);
    final decodedData = compressed ? GZipCodec().decode(data) : data;
    return utf8.decode(decodedData);
  } on FormatException {
    return null;
  } catch (_) {
    return null;
  }
}

class _AlphaBitReader {
  final img.Image image;
  var _x = 0;
  var _y = 0;
  var _bitsRead = 0;

  _AlphaBitReader(this.image);

  int get _totalBits => image.width * image.height;

  int get remainingByteCapacity => (_totalBits - _bitsRead) ~/ 8;

  List<int> readBytes(int length) {
    final bytes = <int>[];
    for (var index = 0; index < length; index += 1) {
      var value = 0;
      for (var bit = 0; bit < 8; bit += 1) {
        final nextBit = _readBit();
        if (nextBit == null) {
          return bytes;
        }
        value = (value << 1) | nextBit;
      }
      bytes.add(value);
    }
    return bytes;
  }

  int? _readBit() {
    if (_x >= image.width) {
      return null;
    }
    final pixel = image.getPixel(_x, _y);
    final bit = pixel.a.toInt() & 1;
    _bitsRead += 1;
    _y += 1;
    if (_y >= image.height) {
      _y = 0;
      _x += 1;
    }
    return bit;
  }
}

int _pngUint32(Uint8List bytes, int offset) {
  return bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
}

MapEntry<String, String>? _parsePngTextChunk(Uint8List data) {
  final separator = data.indexOf(0);
  if (separator <= 0) {
    return null;
  }
  return MapEntry(
    utf8.decode(
      Uint8List.sublistView(data, 0, separator),
      allowMalformed: true,
    ),
    utf8.decode(
      Uint8List.sublistView(data, separator + 1),
      allowMalformed: true,
    ),
  );
}

MapEntry<String, String>? _parsePngCompressedTextChunk(Uint8List data) {
  final separator = data.indexOf(0);
  if (separator <= 0 || separator + 2 > data.length) {
    return null;
  }
  final compressionMethod = data[separator + 1];
  if (compressionMethod != 0) {
    return null;
  }
  final inflated = ZLibCodec().decode(
    Uint8List.sublistView(data, separator + 2),
  );
  return MapEntry(
    utf8.decode(
      Uint8List.sublistView(data, 0, separator),
      allowMalformed: true,
    ),
    utf8.decode(inflated, allowMalformed: true),
  );
}

MapEntry<String, String>? _parsePngInternationalTextChunk(Uint8List data) {
  final keywordEnd = data.indexOf(0);
  if (keywordEnd <= 0 || keywordEnd + 5 > data.length) {
    return null;
  }
  final keyword = utf8.decode(
    Uint8List.sublistView(data, 0, keywordEnd),
    allowMalformed: true,
  );
  var cursor = keywordEnd + 1;
  final compressionFlag = data[cursor];
  cursor += 1;
  final compressionMethod = data[cursor];
  cursor += 1;
  if (compressionFlag != 0 && compressionMethod != 0) {
    return null;
  }

  final languageEnd = data.indexOf(0, cursor);
  if (languageEnd < 0) {
    return null;
  }
  cursor = languageEnd + 1;
  final translatedEnd = data.indexOf(0, cursor);
  if (translatedEnd < 0) {
    return null;
  }
  cursor = translatedEnd + 1;

  final textBytes = Uint8List.sublistView(data, cursor);
  final text = compressionFlag == 0
      ? utf8.decode(textBytes, allowMalformed: true)
      : utf8.decode(ZLibCodec().decode(textBytes), allowMalformed: true);
  return MapEntry(keyword, text);
}

Map<String, dynamic> _pixivImageFramePayload({
  required File imageFile,
  required File infoFile,
  required int pageIndex,
  required int slotCount,
  required FileStat fileStat,
}) {
  final charCaptions = [
    for (var index = 0; index < slotCount; index += 1)
      {
        'char_caption': '',
      },
  ];
  return {
    'source_kind': 'pixiv_image_set_frame',
    'source_image_path': imageFile.path,
    'info_path': infoFile.path,
    'page_index': pageIndex,
    'image_size_bytes': fileStat.size,
    'image_modified_millis': fileStat.modified.millisecondsSinceEpoch,
    'Comment': {
      'v4_prompt': {
        'caption': {
          'base_caption': '',
          'char_captions': charCaptions,
        },
      },
      'v4_negative_prompt': {
        'caption': {
          'base_caption': '',
          'char_captions': charCaptions,
        },
      },
    },
  };
}

int _slotCaptionCountForCache(Map<String, dynamic> cacheJson) {
  var maxSlot = -1;

  void visitSource(Object? sourceId) {
    if (sourceId is! String) {
      return;
    }
    final match = RegExp(r'^slot-(\d+)$', caseSensitive: false)
        .firstMatch(sourceId.trim());
    if (match == null) {
      return;
    }
    final slot = int.tryParse(match.group(1)!);
    if (slot != null && slot > maxSlot) {
      maxSlot = slot;
    }
  }

  void visitAppearanceMap(Map<dynamic, dynamic> appearance) {
    visitSource(appearance['source_id']);
    visitSource(appearance['sourceId']);
  }

  final ai = cacheJson['aiRoleExtraction'];
  if (ai is Map) {
    for (final role in _mapList(ai['roles'])) {
      visitSource(role['source_role_id']);
      visitSource(role['sourceRoleId']);
      for (final appearance in _mapList(role['appearances'])) {
        visitAppearanceMap(appearance);
      }
    }
  }

  final mapping = cacheJson['mapping'];
  if (mapping is Map) {
    for (final assembly in _mapList(
      mapping['role_assemblies'] ?? mapping['roleAssemblies'],
    )) {
      visitSource(assembly['source_role_id']);
      visitSource(assembly['sourceRoleId']);
      for (final appearance in _mapList(
        assembly['source_appearances'] ?? assembly['sourceAppearances'],
      )) {
        visitAppearanceMap(appearance);
      }
    }
  }

  return maxSlot < 0 ? 0 : maxSlot + 1;
}

List<Map<dynamic, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final entry in value)
      if (entry is Map) entry,
  ];
}

String? _cacheString(Map<String, dynamic> cacheJson, String key) {
  final value = cacheJson[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

Future<ScriptFrame?> _parseJsonScriptFrame(File file, int index) async {
  var rawJson = '';
  try {
    rawJson = await file.readAsString(encoding: utf8);
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      return _keepJsonParseErrors(file)
          ? _jsonErrorFrame(
              file: file,
              index: index,
              rawJson: rawJson,
              warning: 'Frame JSON root must be an object.',
            )
          : null;
    }
    final sourcePayload = _stringKeyMap(decoded);
    final metadata = NaiMetadataParser.parseMap(sourcePayload);
    if (!_hasPromptMetadata(metadata)) {
      return null;
    }
    final parsed = ParsedFrame(
      baseCaption: metadata.prompt ?? '',
      charCaptions: List.unmodifiable(metadata.charCaptions),
      negativeBase: metadata.negativePrompt ?? '',
      negativeCharCaptions: List.unmodifiable(metadata.negativeCharCaptions),
      coords: List.unmodifiable(
        metadata.coords.map(
          (coord) => RecastPoint(
            x: coord['x']!.toDouble(),
            y: coord['y']!.toDouble(),
          ),
        ),
      ),
      generationParams: Map.unmodifiable(metadata.parameters),
      sourcePayload: Map.unmodifiable(sourcePayload),
    );
    return ScriptFrame(
      index: index,
      fileName: _fileName(file),
      sourcePath: file.path,
      sourceImagePath: _matchingImageForJsonFile(file)?.path ?? '',
      rawJson: rawJson,
      parsed: parsed,
      detectedSchema: _detectFrameSchema(parsed),
      parseStatus: ScriptFrameParseStatus.parsed,
    );
  } on FormatException catch (error) {
    return _keepJsonParseErrors(file)
        ? _jsonErrorFrame(
            file: file,
            index: index,
            rawJson: rawJson,
            warning: 'Malformed JSON or text encoding: ${error.message}',
          )
        : null;
  } on FileSystemException catch (error) {
    return _keepJsonParseErrors(file)
        ? _jsonErrorFrame(
            file: file,
            index: index,
            rawJson: rawJson,
            warning: 'Could not read frame: ${error.message}',
          )
        : null;
  } catch (error) {
    return _keepJsonParseErrors(file)
        ? _jsonErrorFrame(
            file: file,
            index: index,
            rawJson: rawJson,
            warning: 'Could not parse frame: $error',
          )
        : null;
  }
}

File? _matchingImageForJsonFile(File jsonFile) {
  final directory = jsonFile.parent;
  final stem = _fileStem(_fileName(jsonFile));
  for (final candidate in _matchingImageCandidates(directory, stem)) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }
  return null;
}

List<File> _matchingImageCandidates(Directory directory, String stem) {
  const extensions = ['.png', '.webp', '.jpg', '.jpeg'];
  return [
    for (final extension in extensions)
      File(_joinPath([directory.path, '$stem$extension'])),
    for (final extension in extensions)
      File(_joinPath([directory.path, 'PNG', '$stem$extension'])),
    for (final extension in extensions)
      File(_joinPath([directory.path, 'png', '$stem$extension'])),
    for (final extension in extensions)
      File(_joinPath([directory.path, 'images', '$stem$extension'])),
  ];
}

String _fileStem(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  return dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
}

ScriptFrame _jsonErrorFrame({
  required File file,
  required int index,
  required String rawJson,
  required String warning,
}) {
  return ScriptFrame(
    index: index,
    fileName: _fileName(file),
    sourcePath: file.path,
    rawJson: rawJson,
    parsed: const ParsedFrame(),
    detectedSchema: ScriptSchema.unknown,
    parseStatus: ScriptFrameParseStatus.error,
    warnings: [warning],
  );
}

ScriptSchema _detectFrameSchema(ParsedFrame parsed) {
  if (parsed.charCaptions.isNotEmpty) {
    final base = parsed.baseCaption.toLowerCase();
    final hasInlineCharacter = parsed.charCaptions.any((caption) {
      final anchor = caption.split(',').first.trim().toLowerCase();
      return anchor.isNotEmpty && base.contains(anchor);
    });
    return hasInlineCharacter ? ScriptSchema.v4Partial : ScriptSchema.v4Slotted;
  }
  if (parsed.baseCaption.trim().isNotEmpty) {
    return ScriptSchema.baseInline;
  }
  return ScriptSchema.unknown;
}

ScriptSchema _voteSchema(List<ScriptFrame> frames) {
  final votes = <ScriptSchema, int>{
    for (final schema in ScriptSchema.values) schema: 0,
  };
  for (final frame in frames) {
    if (frame.parseStatus == ScriptFrameParseStatus.parsed) {
      votes[frame.detectedSchema] = votes[frame.detectedSchema]! + 1;
    }
  }
  final ranked = [
    ScriptSchema.v4Partial,
    ScriptSchema.v4Slotted,
    ScriptSchema.baseInline,
    ScriptSchema.unknown,
  ];
  ranked.sort((a, b) {
    final byVotes = votes[b]!.compareTo(votes[a]!);
    if (byVotes != 0) {
      return byVotes;
    }
    return ranked.indexOf(a).compareTo(ranked.indexOf(b));
  });
  return votes[ranked.first] == 0 ? ScriptSchema.unknown : ranked.first;
}

bool _hasPromptMetadata(NaiMetadataParseResult metadata) {
  return metadata.prompt?.trim().isNotEmpty == true ||
      metadata.charCaptions.any((caption) => caption.trim().isNotEmpty);
}

Map<String, dynamic> _sourcePayloadFromMetadata(
  NaiMetadataParseResult metadata,
) {
  final payload = <String, dynamic>{};
  final prompt = metadata.prompt?.trim();
  if (prompt != null && prompt.isNotEmpty) {
    payload['Description'] = prompt;
  }
  final source = metadata.source?.trim();
  if (source != null && source.isNotEmpty) {
    payload['Source'] = source;
  }
  final comment = <String, dynamic>{
    ...metadata.parameters,
  };
  final negativePrompt = metadata.negativePrompt?.trim();
  if (negativePrompt != null && negativePrompt.isNotEmpty) {
    comment.putIfAbsent('uc', () => negativePrompt);
  }
  if (comment.isNotEmpty) {
    payload['Comment'] = comment;
  }
  if (metadata.width != null) {
    payload['width'] = metadata.width;
  }
  if (metadata.height != null) {
    payload['height'] = metadata.height;
  }
  return payload;
}

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}

bool _keepJsonParseErrors(File file) => RegExp(
      r'^(?:nai_|p)(\d+)\.json$',
      caseSensitive: false,
    ).hasMatch(_fileName(file));

String _scriptIdForDirectory(Directory directory) {
  final path = directory.absolute.path;
  final normalizedPath = path.replaceAll('\\', '/');
  final parts = normalizedPath
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  final label = parts.isEmpty ? 'script' : parts.last;
  return stableIdFromText(prefix: 'script', text: normalizedPath, label: label);
}

String _directoryName(Directory directory) {
  final normalized = directory.path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty);
  return parts.isEmpty ? directory.path : parts.last;
}

String _fileName(File file) {
  final normalized = file.path.replaceAll('\\', '/');
  return normalized.split('/').last;
}

String _normalizePath(String path) {
  return path.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
}

int _naturalCompare(String left, String right) {
  final leftParts = _naturalSortParts(left);
  final rightParts = _naturalSortParts(right);
  final sharedLength = leftParts.length < rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < sharedLength; index += 1) {
    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    final comparison = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftPart.toLowerCase().compareTo(rightPart.toLowerCase());
    if (comparison != 0) {
      return comparison;
    }
  }
  return leftParts.length.compareTo(rightParts.length);
}

List<String> _naturalSortParts(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(value)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}

String _sourceFingerprint(Script script) {
  final parts = [
    script.id,
    _normalizePath(script.rootPath),
    for (final frame in script.frames)
      '${frame.index}:${frame.fileName}:${_normalizePath(frame.sourcePath)}:'
          '${_stableContentHash(frame.rawJson)}',
  ];
  return parts.join('|');
}

String _stableContentHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Map<String, dynamic> _normalizedMapping(
  Map<dynamic, dynamic> value,
  Map<String, dynamic> extractionJson,
) {
  final extraction = ScriptAiRoleExtraction.fromJson(extractionJson);
  if (!extraction.isReady || extraction.roles.isEmpty) {
    return Map<String, dynamic>.from(value);
  }
  final mapping = RecastMapping.fromJson(Map<String, dynamic>.from(value));
  final rolesById = <String, ScriptAiExtractedRole>{
    for (final role in extraction.roles)
      if (role.sourceRoleId.trim().isNotEmpty) role.sourceRoleId.trim(): role,
  };
  var changed = false;
  final nextAssemblies = <RoleAssembly>[];
  final appliedRoleIds = <String>{};
  for (final assembly in mapping.roleAssemblies) {
    final role = rolesById[assembly.sourceRoleId.trim()];
    if (role == null) {
      if (_isUserAuthoredAssembly(assembly)) {
        nextAssemblies.add(assembly);
      } else {
        changed = true;
      }
      continue;
    }
    appliedRoleIds.add(role.sourceRoleId.trim());
    final nextAssembly = _assemblyWithNormalizedAiRole(assembly, role);
    if (_jsonText(nextAssembly.toJson()) != _jsonText(assembly.toJson())) {
      changed = true;
    }
    nextAssemblies.add(nextAssembly);
  }
  for (final role in extraction.roles) {
    final sourceRoleId = role.sourceRoleId.trim();
    if (sourceRoleId.isEmpty ||
        appliedRoleIds.contains(sourceRoleId) ||
        role.stages.isEmpty) {
      continue;
    }
    nextAssemblies.add(
      RoleAssembly(
        sourceRoleId: sourceRoleId,
        displayLabel:
            role.displayName.trim().isEmpty ? sourceRoleId : role.displayName,
        sourceName: role.displayName,
        sourceAppearances: _sourceAppearancesFromAiRole(role),
        stages: _roleAssemblyStagesFromAiRole(role, const []),
      ),
    );
    changed = true;
    appliedRoleIds.add(sourceRoleId);
  }
  final nextRolePromptReplacements = _rolePromptReplacementsWithAiTerms(
    mapping.rolePromptReplacements,
    extraction.roles,
  );
  if (_jsonText([
        for (final replacement in nextRolePromptReplacements)
          replacement.toJson(),
      ]) !=
      _jsonText([
        for (final replacement in mapping.rolePromptReplacements)
          replacement.toJson(),
      ])) {
    changed = true;
  }
  if (!changed) {
    return Map<String, dynamic>.from(value);
  }
  return mapping
      .copyWith(
        roleAssemblies: List.unmodifiable(nextAssemblies),
        rolePromptReplacements: nextRolePromptReplacements,
      )
      .toJson();
}

List<ScriptRolePromptReplacement> _rolePromptReplacementsWithAiTerms(
  List<ScriptRolePromptReplacement> existingReplacements,
  List<ScriptAiExtractedRole> roles,
) {
  final existingByRoleId = <String, ScriptRolePromptReplacement>{
    for (final replacement in existingReplacements)
      if (replacement.sourceRoleId.trim().isNotEmpty)
        replacement.sourceRoleId.trim(): replacement,
  };
  final next = <ScriptRolePromptReplacement>[];
  final appliedRoleIds = <String>{};
  for (final role in roles) {
    final sourceRoleId = role.sourceRoleId.trim();
    if (sourceRoleId.isEmpty || role.promptTerms.isEmpty) {
      continue;
    }
    final existing = existingByRoleId[sourceRoleId];
    next.add(
      _rolePromptReplacementWithAiTerms(
        role: role,
        existing: existing,
      ),
    );
    appliedRoleIds.add(sourceRoleId);
  }
  for (final replacement in existingReplacements) {
    if (!appliedRoleIds.contains(replacement.sourceRoleId.trim())) {
      next.add(replacement);
    }
  }
  return List.unmodifiable(next);
}

@visibleForTesting
List<ScriptRolePromptReplacement> rolePromptReplacementsWithAiTermsForTesting({
  required List<ScriptRolePromptReplacement> existingReplacements,
  required List<ScriptAiExtractedRole> roles,
}) {
  return _rolePromptReplacementsWithAiTerms(existingReplacements, roles);
}

ScriptRolePromptReplacement _rolePromptReplacementWithAiTerms({
  required ScriptAiExtractedRole role,
  required ScriptRolePromptReplacement? existing,
}) {
  final rules = <ScriptPromptReplacementRule>[];
  final existingRulesByTermKey = <String, ScriptPromptReplacementRule>{};
  final emittedRuleIds = <String>{};
  for (final rule in existing?.rules ?? const <ScriptPromptReplacementRule>[]) {
    for (final term in rule.sourceTerms) {
      for (final key in _promptReplacementLookupKeys(
        term.text,
        term.category,
      )) {
        existingRulesByTermKey.putIfAbsent(key, () => rule);
      }
    }
  }

  for (final term in role.promptTerms) {
    final text = term.text.trim();
    if (text.isEmpty) {
      continue;
    }
    ScriptPromptReplacementRule? existingRule;
    for (final key in _promptReplacementLookupKeys(text, term.category)) {
      existingRule = existingRulesByTermKey[key];
      if (existingRule != null) {
        break;
      }
    }
    if (existingRule != null) {
      if (emittedRuleIds.add(existingRule.id)) {
        rules.add(
          existingRule.copyWith(
            sourceTerms: [_promptReplacementTermFromAi(term)],
          ),
        );
      }
      continue;
    }
    final replacementTerm = _promptReplacementTermFromAi(term);
    final ruleId =
        'role-${_safeIdSegment(role.sourceRoleId)}-${replacementTerm.id}';
    if (!emittedRuleIds.add(ruleId)) {
      continue;
    }
    rules.add(
      ScriptPromptReplacementRule(
        id: ruleId,
        sourceTerms: [replacementTerm],
      ),
    );
  }

  for (final rule in existing?.rules ?? const <ScriptPromptReplacementRule>[]) {
    if (!emittedRuleIds.add(rule.id)) {
      continue;
    }
    rules.add(rule);
  }

  final preview = _promptReplacementSourcePreview(role.promptTerms);
  return ScriptRolePromptReplacement(
    sourceRoleId: role.sourceRoleId,
    displayLabel: existing?.displayLabel.trim().isNotEmpty == true
        ? existing!.displayLabel
        : role.displayName.trim().isEmpty
            ? role.sourceRoleId
            : role.displayName,
    sourcePreview:
        preview.trim().isEmpty ? existing?.sourcePreview ?? '' : preview,
    targetCharacterId: existing?.targetCharacterId,
    targetIdentityPrompt: existing?.targetIdentityPrompt ?? '',
    rules: List.unmodifiable(rules),
  );
}

ScriptPromptReplacementTerm _promptReplacementTermFromAi(
  ScriptAiExtractedPromptTerm term,
) {
  return ScriptPromptReplacementTerm(
    id: term.id.trim().isEmpty
        ? 'term-${_safeIdSegment(term.text)}'
        : term.id.trim(),
    text: term.text.trim(),
    category: term.category,
    sourcePhrase: term.sourcePhrase.trim(),
    sourceLocation: term.sourceLocation.trim(),
    frameIndexes: List.unmodifiable(term.frameIndexes),
  );
}

String _promptReplacementSourcePreview(
  List<ScriptAiExtractedPromptTerm> terms,
) {
  final seen = <String>{};
  final parts = <String>[];
  for (final term in terms) {
    final text = term.text.trim();
    final key = _normalizedEvidenceText(text);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    parts.add(text);
  }
  return parts.join(', ');
}

String _promptReplacementTermKey(String text, PromptTagCategory category) {
  return '${category.name}\u001f${_normalizedEvidenceText(text)}';
}

List<String> _promptReplacementLookupKeys(
  String text,
  PromptTagCategory category,
) {
  final strictKey = _promptReplacementTermKey(text, category);
  if (strictKey.isEmpty) {
    return const [];
  }
  final compatibleKey = _promptReplacementCompatibleTermKey(text, category);
  if (compatibleKey.isEmpty || compatibleKey == strictKey) {
    return [strictKey];
  }
  return [strictKey, compatibleKey];
}

String _promptReplacementCompatibleTermKey(
  String text,
  PromptTagCategory category,
) {
  final normalized = _normalizedEvidenceText(text);
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

RoleAssembly _assemblyWithNormalizedAiRole(
  RoleAssembly assembly,
  ScriptAiExtractedRole role,
) {
  final aiStages = _roleAssemblyStagesFromAiRole(role, assembly.stages);
  final mergedStages = _mergeAiRoleStages(
    existingStages: assembly.stages,
    aiStages: aiStages,
  );
  return assembly.copyWith(
    displayLabel: role.displayName.trim().isEmpty
        ? assembly.displayLabel
        : role.displayName,
    sourceName: role.displayName.trim().isEmpty
        ? assembly.sourceName
        : role.displayName,
    sourceAppearances: _sourceAppearancesFromAiRole(role),
    stages: List.unmodifiable(mergedStages),
  );
}

List<RoleAssemblySourceAppearance> _sourceAppearancesFromAiRole(
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

List<RoleAssemblyStage> _roleAssemblyStagesFromAiRole(
  ScriptAiExtractedRole role,
  List<RoleAssemblyStage> existingStages,
) {
  final stages = <RoleAssemblyStage>[];
  final producedIds = <String>{};
  final existingIds = {for (final stage in existingStages) stage.id};
  for (final (index, stage) in role.stages.indexed) {
    final rawBaseId = stage.stageId.trim().isEmpty
        ? 'ai-role-${_safeIdSegment(role.sourceRoleId)}-${index + 1}'
        : stage.stageId.trim();
    final baseId = existingIds.contains(rawBaseId) && producedIds.add(rawBaseId)
        ? rawBaseId
        : _uniqueStageId(rawBaseId, producedIds);
    producedIds.add(baseId);
    final parts = RecastPromptParts(
      identity: stage.identity,
      upperBody: stage.upperBody,
      lowerBody: stage.lowerBody,
      upperClothing: stage.upperClothing,
      lowerClothing: stage.lowerClothing,
    );
    stages.add(
      RoleAssemblyStage(
        id: baseId,
        label: stage.label.trim().isEmpty ? 'Stage ${index + 1}' : stage.label,
        frameIndexes: List.unmodifiable(stage.frameIndexes),
        sourceSummary: _summaryFromPromptParts(parts),
        sourceParts: parts,
        omittedParts: _omittedPartsFromAiMissingFields(stage.missingFields),
      ),
    );
  }
  return List.unmodifiable(stages);
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

List<RoleAssemblyStage> _mergeAiRoleStages({
  required List<RoleAssemblyStage> existingStages,
  required List<RoleAssemblyStage> aiStages,
}) {
  if (existingStages.isEmpty) {
    return aiStages;
  }
  final existingById = {
    for (final stage in existingStages) stage.id: stage,
  };
  final usedExistingIds = <String>{};
  final result = <RoleAssemblyStage>[];
  for (final aiStage in aiStages) {
    final existingStage = existingById[aiStage.id];
    if (existingStage == null) {
      final userStage = _bestUserStateStageForAiStage(
        aiStage,
        existingStages,
      );
      result.add(
        userStage == null
            ? aiStage
            : _stageWithUserStateOverlay(aiStage, userStage),
      );
      continue;
    }
    usedExistingIds.add(existingStage.id);
    result.add(_stageWithAiSource(existingStage, aiStage));
  }
  for (final stage in existingStages) {
    if (usedExistingIds.contains(stage.id)) {
      continue;
    }
    if (_isUserAuthoredStage(stage) &&
        _isAiGeneratedRoleStage(stage) &&
        result.isNotEmpty) {
      final targetIndex = _bestAiStageIndexForUserStage(stage, result);
      result[targetIndex] = _stageWithUserStateOverlay(
        result[targetIndex],
        stage,
      );
      continue;
    }
    if (_shouldKeepUnmatchedExistingRoleStage(stage)) {
      result.add(stage);
    }
  }
  return List.unmodifiable(result);
}

RoleAssemblyStage? _bestUserStateStageForAiStage(
  RoleAssemblyStage aiStage,
  List<RoleAssemblyStage> existingStages,
) {
  RoleAssemblyStage? bestStage;
  var bestScore = -1;
  for (final stage in existingStages) {
    if (!_isUserAuthoredStage(stage)) {
      continue;
    }
    final sharedFrames =
        stage.frameIndexes.toSet().intersection(aiStage.frameIndexes.toSet());
    final score = sharedFrames.length * 1000 +
        _promptPartOverlapScore(stage.sourceParts, aiStage.sourceParts);
    if (score > bestScore) {
      bestScore = score;
      bestStage = stage;
    }
  }
  return bestScore <= 0 ? null : bestStage;
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
    final score = userFrames.where(aiFrames.contains).length * 1000 +
        _promptPartOverlapScore(userStage.sourceParts, aiStage.sourceParts);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }
  return bestIndex;
}

int _promptPartOverlapScore(
  RecastPromptParts left,
  RecastPromptParts right,
) {
  return _tagOverlapScore(left.identity, right.identity) +
      _tagOverlapScore(left.upperBody, right.upperBody) +
      _tagOverlapScore(left.lowerBody, right.lowerBody) +
      _tagOverlapScore(left.upperClothing, right.upperClothing) +
      _tagOverlapScore(left.lowerClothing, right.lowerClothing);
}

int _tagOverlapScore(String left, String right) {
  final rightTags = right
      .split(',')
      .map((tag) => tag.trim().toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toSet();
  if (rightTags.isEmpty) {
    return 0;
  }
  return left
      .split(',')
      .map((tag) => tag.trim().toLowerCase())
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

RoleAssemblyStage _stageWithAiSource(
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

bool _shouldKeepUnmatchedExistingRoleStage(RoleAssemblyStage stage) {
  if (!_isUserAuthoredStage(stage)) {
    return false;
  }
  return !_isAiGeneratedRoleStage(stage);
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

bool _isAiGeneratedRoleStage(RoleAssemblyStage stage) {
  final id = stage.id.trim().toLowerCase();
  final label = stage.label.trim().toLowerCase();
  return RegExp(r'^slot-\d+-stage-\d+(-\d+)?$').hasMatch(id) ||
      RegExp(r'^(stage|base-role)-\d+(-\d+)?$').hasMatch(id) ||
      id.startsWith('ai-role-') ||
      RegExp(r'^stage\s+\d+$').hasMatch(label) ||
      label.startsWith('ai ');
}

Set<RecastPromptPart> _omittedPartsFromAiMissingFields(
  List<String> missingFields,
) {
  final fields = missingFields.map((field) => field.trim()).toSet();
  return Set.unmodifiable({
    if (fields.contains('missing_identity')) RecastPromptPart.identity,
    if (fields.contains('missing_upper_body')) RecastPromptPart.upperBody,
    if (fields.contains('missing_lower_body')) RecastPromptPart.lowerBody,
    if (fields.contains('missing_upper_clothing'))
      RecastPromptPart.upperClothing,
    if (fields.contains('missing_lower_clothing'))
      RecastPromptPart.lowerClothing,
  });
}

String _summaryFromPromptParts(RecastPromptParts parts) {
  return [
    parts.identity,
    parts.upperBody,
    parts.lowerBody,
    parts.upperClothing,
    parts.lowerClothing,
  ].where((value) => value.trim().isNotEmpty).join(', ');
}

String _safeIdSegment(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9_-]+'),
        '-',
      );
  return normalized.replaceAll(RegExp(r'-+'), '-').replaceAll(
        RegExp(r'^-|-$'),
        '',
      );
}

List<_ResidualHit> _residualHits(
  File file,
  Map<String, dynamic> extractionJson,
  String section,
) {
  final extraction = ScriptAiRoleExtraction.fromJson(extractionJson);
  final hits = <_ResidualHit>[];
  for (final role in extraction.roles) {
    for (final stage in role.stages) {
      for (final field in [
        ('upper_body', stage.upperBody),
        ('lower_body', stage.lowerBody),
        ('upper_clothing', stage.upperClothing),
        ('lower_clothing', stage.lowerClothing),
      ]) {
        if (!_transientRoleFieldPattern.hasMatch(
          _normalizedTransientAuditText(field.$2),
        )) {
          continue;
        }
        hits.add(
          _ResidualHit(
            fileName: file.uri.pathSegments.last,
            section: section,
            roleId: role.sourceRoleId,
            stageId: stage.stageId,
            field: field.$1,
            value: field.$2,
          ),
        );
      }
    }
  }
  return hits;
}

List<_ResidualHit> _mappingResidualHits(
  File file,
  Map<String, dynamic> mappingJson,
) {
  final mapping = RecastMapping.fromJson(mappingJson);
  final hits = <_ResidualHit>[];
  for (final assembly in mapping.roleAssemblies) {
    for (final stage in assembly.stages) {
      for (final field in [
        ('sourceParts.upperBody', stage.sourceParts.upperBody),
        ('sourceParts.lowerBody', stage.sourceParts.lowerBody),
        ('sourceParts.upperClothing', stage.sourceParts.upperClothing),
        ('sourceParts.lowerClothing', stage.sourceParts.lowerClothing),
      ]) {
        if (!_transientRoleFieldPattern.hasMatch(
          _normalizedTransientAuditText(field.$2),
        )) {
          continue;
        }
        hits.add(
          _ResidualHit(
            fileName: file.uri.pathSegments.last,
            section: 'mapping',
            roleId: assembly.sourceRoleId,
            stageId: stage.id,
            field: field.$1,
            value: field.$2,
          ),
        );
      }
    }
  }
  return hits;
}

final _transientRoleFieldPattern = RegExp(
  r'(^|[^a-z0-9])('
  r'starting to take off|taking off|take off|undressing|undress|'
  r'undressing another clothes|undressing another|'
  r'removing|remove|pulling|pulled|pull|lifting|lifted|lift|'
  r'adjusting clothes|adjusting|dress tug|clothes tug|tug|'
  r'skirt flip|flipping|flip|'
  r'wet|sweaty|sweat|stained|stain|torn|ripped|damaged|open|'
  r'slipping|falling off|exposed|revealing|'
  r'covering ass|covering eyes|covering nipples|covering|'
  r'hand between breasts|hand over own mouth|'
  r'panties aside|panties around one leg|no panties|around one leg|aside|'
  r'smile|smiling|closed eyes|open mouth|winking|wink|blush|crying|'
  r'tears|angry|embarrassed|ahegao|tongue out|drooling|'
  r'looking at viewer|looking back|looking away|'
  r'kneeling|sitting|standing|lying|squatting|bending|bent over|'
  r'spread legs|legs spread|arms up|hands up|raised arms|walking|'
  r'running|jumping|crawling|straddling|riding|touching|grabbing|'
  r'holding|fingering|fingering through clothes|through clothes|'
  r'pov|close-up|close up|from behind|side view|dutch angle|camera|'
  r'sex|intercourse|masturbat(?:e|ing|ion)|penetrat(?:e|ing|ion)|'
  r'cum|semen|orgasm|ejaculat(?:e|ing|ion)|saliva|pussy juice'
  r')([^a-z0-9]|$)',
);

String _normalizedTransientAuditText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _scriptKey(Map<String, dynamic> json) {
  for (final key in ['scriptId', 'script_id', 'sourceRootPath', 'scriptName']) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  final snapshot = json['scriptSnapshot'];
  if (snapshot is Map) {
    for (final key in ['id', 'rootPath', 'name']) {
      final value = snapshot[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }
  return '';
}

int _positiveDelta(int before, int after) {
  final delta = before - after;
  return delta > 0 ? delta : 0;
}

int _slotlessBaseAppearanceCount(ScriptAiRoleExtraction extraction) {
  var count = 0;
  for (final role in extraction.roles) {
    for (final appearance in role.appearances) {
      final sourceId = appearance.sourceId.trim().toLowerCase();
      final sourceKind = appearance.sourceKind.trim().toLowerCase();
      if (sourceId == 'base' ||
          sourceId.startsWith('base-') ||
          sourceKind == 'base' ||
          sourceKind == 'global') {
        count += appearance.frameIndexes.isEmpty
            ? 1
            : appearance.frameIndexes.length;
      }
    }
  }
  return count;
}

String _attentionSummary(ScriptAiRoleExtraction extraction) {
  final messages = [
    for (final item in extraction.attentionItems)
      if (item.message.trim().isNotEmpty) item.message.trim(),
  ];
  if (messages.isNotEmpty) {
    return messages.take(3).join(' | ');
  }
  return extraction.rawResponse.trim().isEmpty
      ? 'no failure reason recorded'
      : extraction.rawResponse.trim();
}

String _jsonText(Object? value) => jsonEncode(value);

String _joinPath(List<String> parts) => parts.join(Platform.pathSeparator);

class _ResidualHit {
  final String fileName;
  final String section;
  final String roleId;
  final String stageId;
  final String field;
  final String value;

  const _ResidualHit({
    required this.fileName,
    required this.section,
    required this.roleId,
    required this.stageId,
    required this.field,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'file_name': fileName,
        'section': section,
        'role_id': roleId,
        'stage_id': stageId,
        'field': field,
        'value': value,
      };
}

class _CacheIssue {
  final String fileName;
  final String status;
  final String reason;

  const _CacheIssue({
    required this.fileName,
    required this.status,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'file_name': fileName,
        'status': status,
        'reason': reason,
      };
}

class _Options {
  final String cacheDir;
  final bool dryRun;
  final String? backupDir;
  final String? auditReportPath;
  final int maxResidualPrint;

  const _Options({
    required this.cacheDir,
    required this.dryRun,
    required this.backupDir,
    required this.auditReportPath,
    required this.maxResidualPrint,
  });

  factory _Options.parse(List<String> args) {
    var cacheDir = _defaultCacheDir();
    var dryRun = false;
    String? backupDir;
    String? auditReportPath;
    var maxResidualPrint = 40;
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--cache-dir' && index + 1 < args.length) {
        cacheDir = args[++index];
      } else if (arg.startsWith('--cache-dir=')) {
        cacheDir = arg.substring('--cache-dir='.length);
      } else if (arg == '--backup-dir' && index + 1 < args.length) {
        backupDir = args[++index];
      } else if (arg.startsWith('--backup-dir=')) {
        backupDir = arg.substring('--backup-dir='.length);
      } else if (arg == '--audit-report' && index + 1 < args.length) {
        auditReportPath = args[++index];
      } else if (arg.startsWith('--audit-report=')) {
        auditReportPath = arg.substring('--audit-report='.length);
      } else if (arg == '--max-residual-print' && index + 1 < args.length) {
        maxResidualPrint = int.tryParse(args[++index]) ?? maxResidualPrint;
      } else if (arg.startsWith('--max-residual-print=')) {
        maxResidualPrint = int.tryParse(
              arg.substring('--max-residual-print='.length),
            ) ??
            maxResidualPrint;
      } else {
        throw StateError('Unknown argument: $arg');
      }
    }
    return _Options(
      cacheDir: cacheDir,
      dryRun: dryRun,
      backupDir: backupDir,
      auditReportPath: auditReportPath,
      maxResidualPrint: maxResidualPrint,
    );
  }
}

String _defaultCacheDir() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.trim().isEmpty) {
    throw StateError('APPDATA is not set; pass --cache-dir explicitly.');
  }
  return _joinPath([
    appData,
    'Novel Studio',
    'Novel Studio',
    'novel_studio',
    'script_recast',
    'cache',
  ]);
}
