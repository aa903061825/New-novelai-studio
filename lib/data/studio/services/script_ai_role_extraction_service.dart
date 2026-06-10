import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_evidence_builder.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_client.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_merger.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_parser.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';

export 'package:nai_casrand/data/studio/services/script_ai_role_extraction_client.dart'
    show ScriptAiRoleExtractionStreamDelta;

const _maxEvidenceRequestGroupsPerChunk = 3;
const _maxFramesPerEvidenceRequestGroup = 12;
const _maxTotalFollowUpFramesPerChunk = 24;

typedef ScriptAiRoleExtractionRequestStarted = void Function(
  Map<String, dynamic> requestPreview,
);

typedef ScriptAiRoleExtractionChunkCompleted = Future<void> Function(
  ScriptAiRoleExtraction extraction,
  Map<String, dynamic> requestPreview,
);

class ScriptAiRoleExtractionServiceRequest {
  final String baseUrl;
  final String token;
  final String model;
  final String proxy;
  final Script script;
  final List<ScriptAiRoleExtraction> completedChunkExtractions;
  final ScriptAiRoleExtractionRequestStarted? onRequestStarted;
  final ScriptAiRoleExtractionStreamUpdate? onStreamDelta;
  final ScriptAiRoleExtractionChunkCompleted? onChunkCompleted;

  const ScriptAiRoleExtractionServiceRequest({
    required this.baseUrl,
    required this.token,
    required this.model,
    this.proxy = '',
    required this.script,
    this.completedChunkExtractions = const [],
    this.onRequestStarted,
    this.onStreamDelta,
    this.onChunkCompleted,
  });
}

class ScriptAiRoleExtractionServiceResult {
  final ScriptAiRoleExtraction extraction;
  final Map<String, dynamic> requestPreview;
  final int aiRequestCount;
  final String reasoningContent;

  const ScriptAiRoleExtractionServiceResult({
    required this.extraction,
    required this.requestPreview,
    required this.aiRequestCount,
    this.reasoningContent = '',
  });
}

class _FollowUpResolution {
  final ScriptAiRoleExtraction extraction;
  final Map<String, dynamic> requestPreview;
  final int aiRequestCount;

  const _FollowUpResolution({
    required this.extraction,
    required this.requestPreview,
    required this.aiRequestCount,
  });
}

class _EvidenceSourceRef {
  final String sourceId;
  final int? slotIndex;

  const _EvidenceSourceRef({
    required this.sourceId,
    required this.slotIndex,
  });
}

class _PromptWeightIndex {
  final Map<String, List<_PromptWeightEntry>> _entriesByKey;

  const _PromptWeightIndex._(this._entriesByKey);

  factory _PromptWeightIndex.fromScript(Script script) {
    final entries = <String, List<_PromptWeightEntry>>{};

    void addCaption({
      required String sourceId,
      required int frameIndex,
      required String caption,
    }) {
      final rawCaption = caption.trim();
      if (rawCaption.isEmpty) {
        return;
      }
      for (final tag in PromptTagProcessor.analyzeWorkshopTags(rawCaption)) {
        final display = tag.displayText.trim();
        final key = PromptTagProcessor.normalizeMatchKey(display);
        if (display.isEmpty || key.isEmpty) {
          continue;
        }
        entries.putIfAbsent(key, () => <_PromptWeightEntry>[]).add(
              _PromptWeightEntry(
                sourceId: sourceId,
                frameIndex: frameIndex,
                weight: tag.weight ?? 1,
              ),
            );
      }
    }

    for (final frame in script.frames) {
      if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
        continue;
      }
      addCaption(
        sourceId: 'base',
        frameIndex: frame.index,
        caption: frame.parsed.baseCaption,
      );
      for (final (slotIndex, caption) in frame.parsed.charCaptions.indexed) {
        addCaption(
          sourceId: 'slot-$slotIndex',
          frameIndex: frame.index,
          caption: caption,
        );
      }
      addCaption(
        sourceId: 'negative-base',
        frameIndex: frame.index,
        caption: frame.parsed.negativeBase,
      );
      for (final (slotIndex, caption)
          in frame.parsed.negativeCharCaptions.indexed) {
        addCaption(
          sourceId: 'negative-slot-$slotIndex',
          frameIndex: frame.index,
          caption: caption,
        );
      }
    }

    return _PromptWeightIndex._({
      for (final entry in entries.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }

  String restoreField(
    String text, {
    required String sourceRoleId,
    required String sourceKind,
    required List<int> frameIndexes,
    List<String> sourceIds = const [],
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _entriesByKey.isEmpty) {
      return trimmed;
    }
    final tags = <String>[];
    for (final tag in PromptTagProcessor.analyzeWorkshopTags(trimmed)) {
      final display = tag.displayText.trim();
      final key = PromptTagProcessor.normalizeMatchKey(display);
      if (display.isEmpty || key.isEmpty) {
        continue;
      }
      final weight = tag.weight ??
          _weightFor(
            key,
            sourceRoleId: sourceRoleId,
            sourceKind: sourceKind,
            frameIndexes: frameIndexes,
            sourceIds: sourceIds,
          );
      tags.add(_weightedDisplayTag(display, weight));
    }
    return tags.join(', ');
  }

  double? _weightFor(
    String key, {
    required String sourceRoleId,
    required String sourceKind,
    required List<int> frameIndexes,
    required List<String> sourceIds,
  }) {
    var candidates = _entriesByKey[key] ?? const <_PromptWeightEntry>[];
    if (candidates.isEmpty) {
      return null;
    }

    final sourceIdSet = sourceIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final roleSourceId = sourceRoleId.trim();
    if (sourceIdSet.isNotEmpty) {
      final sourceMatches = candidates
          .where((entry) => sourceIdSet.contains(entry.sourceId))
          .toList();
      if (sourceMatches.isNotEmpty) {
        candidates = sourceMatches;
      }
    } else if (roleSourceId.isNotEmpty) {
      final roleMatches =
          candidates.where((entry) => entry.sourceId == roleSourceId).toList();
      if (roleMatches.isNotEmpty) {
        candidates = roleMatches;
      }
    } else if (sourceKind.trim().toLowerCase() == 'global') {
      final baseMatches =
          candidates.where((entry) => entry.sourceId == 'base').toList();
      if (baseMatches.isNotEmpty) {
        candidates = baseMatches;
      }
    }

    final frameSet = frameIndexes.toSet();
    if (frameSet.isNotEmpty) {
      final frameMatches = candidates
          .where((entry) => frameSet.contains(entry.frameIndex))
          .toList();
      if (frameMatches.isNotEmpty) {
        candidates = frameMatches;
      }
    }

    final first = candidates.first.weight;
    final consistent =
        candidates.every((entry) => (entry.weight - first).abs() < 0.000001);
    return consistent ? first : null;
  }

  String _weightedDisplayTag(String display, double? weight) {
    if (weight == null || (weight - 1).abs() < 0.000001) {
      return display;
    }
    return PromptTagProcessor.formatInlineWeightTag(display, weight);
  }
}

class _PromptWeightEntry {
  final String sourceId;
  final int frameIndex;
  final double weight;

  const _PromptWeightEntry({
    required this.sourceId,
    required this.frameIndex,
    required this.weight,
  });
}

abstract interface class ScriptAiRoleExtractionService {
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  });
}

class DefaultScriptAiRoleExtractionService
    implements ScriptAiRoleExtractionService {
  final ScriptAiRoleEvidenceBuilder builder;
  final ScriptAiRoleExtractionClient client;
  final ScriptAiRoleExtractionParser parser;
  final ScriptAiRoleExtractionMerger merger;
  final List<Duration> retryDelays;

  const DefaultScriptAiRoleExtractionService({
    this.builder = const ScriptAiRoleEvidenceBuilder(),
    required this.client,
    this.parser = const ScriptAiRoleExtractionParser(),
    this.merger = const ScriptAiRoleExtractionMerger(),
    this.retryDelays = const [
      Duration(milliseconds: 300),
      Duration(milliseconds: 900),
    ],
  });

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    final chunks = builder.buildChunks(script: request.script);
    final promptWeightIndex = _PromptWeightIndex.fromScript(request.script);
    if (chunks.isEmpty) {
      final requestPreview = _emptyRequestPreview(request.script);
      return ScriptAiRoleExtractionServiceResult(
        extraction: ScriptAiRoleExtraction.failure(
          message: 'No parsed script frames available for AI role extraction.',
          rawResponse: '',
        ),
        requestPreview: requestPreview,
        aiRequestCount: 0,
      );
    }

    final chunkExtractions = <ScriptAiRoleExtraction>[];
    final completedByChunkId = _completedExtractionsByChunkId(
      request.completedChunkExtractions,
    );
    final reasoningParts = <String>[];
    Map<String, dynamic>? lastRequestPreview;
    var aiRequestCount = 0;

    for (final chunk in chunks) {
      final chunkId = chunk['chunk_id']?.toString().trim() ?? '';
      final completed = completedByChunkId[chunkId];
      if (completed != null) {
        chunkExtractions.add(
          _normalizeExtraction(
            _extractionWithChunkId(completed, chunkId),
            promptWeightIndex,
          ),
        );
        lastRequestPreview = chunk;
        continue;
      }

      aiRequestCount += 1;
      final clientRequest = ScriptAiRoleExtractionClientRequest(
        baseUrl: request.baseUrl,
        token: request.token,
        model: request.model,
        proxy: request.proxy,
        requestJson: chunk,
        onStreamDelta: request.onStreamDelta,
      );
      request.onRequestStarted?.call(chunk);
      try {
        final result = await _extractWithRetry(clientRequest);
        _addReasoningPart(
          reasoningParts,
          title: chunk['chunk_id']?.toString() ?? 'chunk-$aiRequestCount',
          content: result.reasoningContent,
        );
        final extraction = _normalizeExtraction(
          parser.parse(result.rawJson),
          promptWeightIndex,
        );
        if (extraction.isFailed) {
          return ScriptAiRoleExtractionServiceResult(
            extraction: extraction,
            requestPreview: chunk,
            aiRequestCount: aiRequestCount,
            reasoningContent: _joinReasoning(reasoningParts),
          );
        }
        if (extraction.isNeedsMoreEvidence) {
          final followUpResult = await _resolveFollowUp(
            serviceRequest: request,
            chunk: chunk,
            firstExtraction: extraction,
            reasoningParts: reasoningParts,
            promptWeightIndex: promptWeightIndex,
          );
          aiRequestCount += followUpResult.aiRequestCount;
          if (followUpResult.extraction.isFailed) {
            return ScriptAiRoleExtractionServiceResult(
              extraction: followUpResult.extraction,
              requestPreview: followUpResult.requestPreview,
              aiRequestCount: aiRequestCount,
              reasoningContent: _joinReasoning(reasoningParts),
            );
          }
          final checkpoint = _normalizeExtraction(
            _extractionWithChunkId(followUpResult.extraction, chunkId),
            promptWeightIndex,
          );
          chunkExtractions.add(checkpoint);
          await _notifyChunkCompleted(
            request: request,
            extraction: checkpoint,
            requestPreview: followUpResult.requestPreview,
          );
          lastRequestPreview = followUpResult.requestPreview;
          continue;
        }
        final checkpoint = _extractionWithChunkId(extraction, chunkId);
        chunkExtractions.add(checkpoint);
        await _notifyChunkCompleted(
          request: request,
          extraction: checkpoint,
          requestPreview: chunk,
        );
        lastRequestPreview = chunk;
      } catch (error) {
        return ScriptAiRoleExtractionServiceResult(
          extraction: ScriptAiRoleExtraction.failure(
            message: error.toString(),
            rawResponse: '',
          ),
          requestPreview: chunk,
          aiRequestCount: aiRequestCount,
          reasoningContent: _joinReasoning(reasoningParts),
        );
      }
    }

    if (chunkExtractions.length == 1) {
      return ScriptAiRoleExtractionServiceResult(
        extraction: _normalizeExtraction(
          chunkExtractions.single,
          promptWeightIndex,
        ),
        requestPreview: lastRequestPreview ?? chunks.single,
        aiRequestCount: aiRequestCount,
        reasoningContent: _joinReasoning(reasoningParts),
      );
    }

    final mergeRequest = _mergeRequest(
      script: request.script,
      chunks: chunks,
      extractions: chunkExtractions,
    );
    aiRequestCount += 1;
    late final ScriptAiRoleExtraction mergeFailure;
    final clientMergeRequest = ScriptAiRoleExtractionClientRequest(
      baseUrl: request.baseUrl,
      token: request.token,
      model: request.model,
      proxy: request.proxy,
      requestJson: mergeRequest,
      onStreamDelta: request.onStreamDelta,
    );
    request.onRequestStarted?.call(mergeRequest);

    try {
      final result = await _extractWithRetry(clientMergeRequest);
      _addReasoningPart(
        reasoningParts,
        title: 'merge_extractions',
        content: result.reasoningContent,
      );
      final merged = parser.parse(result.rawJson);
      if (merged.isReady) {
        return ScriptAiRoleExtractionServiceResult(
          extraction: _normalizeExtraction(merged, promptWeightIndex),
          requestPreview: mergeRequest,
          aiRequestCount: aiRequestCount,
          reasoningContent: _joinReasoning(reasoningParts),
        );
      }
      mergeFailure = _mergeFallbackExtraction(merged);
    } catch (error) {
      mergeFailure = _mergeFallbackErrorExtraction(error);
    }

    return ScriptAiRoleExtractionServiceResult(
      extraction: _normalizeExtraction(
        merger.merge([
          ...chunkExtractions,
          mergeFailure,
        ]),
        promptWeightIndex,
      ),
      requestPreview: mergeRequest,
      aiRequestCount: aiRequestCount,
      reasoningContent: _joinReasoning(reasoningParts),
    );
  }

  Map<String, ScriptAiRoleExtraction> _completedExtractionsByChunkId(
    List<ScriptAiRoleExtraction> extractions,
  ) {
    final result = <String, ScriptAiRoleExtraction>{};
    for (final extraction in extractions) {
      final chunkId = extraction.chunkId?.trim();
      if (chunkId == null || chunkId.isEmpty || !extraction.isReady) {
        continue;
      }
      result[chunkId] = extraction;
    }
    return result;
  }

  Future<void> _notifyChunkCompleted({
    required ScriptAiRoleExtractionServiceRequest request,
    required ScriptAiRoleExtraction extraction,
    required Map<String, dynamic> requestPreview,
  }) async {
    final callback = request.onChunkCompleted;
    final chunkId = extraction.chunkId?.trim();
    if (callback == null ||
        chunkId == null ||
        chunkId.isEmpty ||
        !extraction.isReady) {
      return;
    }
    await callback(extraction, requestPreview);
  }

  ScriptAiRoleExtraction _extractionWithChunkId(
    ScriptAiRoleExtraction extraction,
    String chunkId,
  ) {
    if (extraction.chunkId == chunkId) {
      return extraction;
    }
    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: chunkId,
      confidence: extraction.confidence,
      roles: extraction.roles,
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      rawResponse: extraction.rawResponse,
    );
  }

  void _addReasoningPart(
    List<String> parts, {
    required String title,
    required String content,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }
    parts.add('[$title]\n$trimmed');
  }

  String _joinReasoning(List<String> parts) => parts.join('\n\n');

  ScriptAiRoleExtraction _mergeFallbackErrorExtraction(Object error) {
    return ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.failed,
      attentionItems: [
        ScriptAiExtractionAttentionItem(
          id: 'ai-role-extraction-merge-request-failed',
          kind: 'merge_request_failed',
          message: error.toString(),
          blocking: false,
        ),
      ],
    );
  }

  ScriptAiRoleExtraction _mergeFallbackExtraction(
    ScriptAiRoleExtraction extraction,
  ) {
    final attentionItems = extraction.attentionItems.isEmpty
        ? const [
            ScriptAiExtractionAttentionItem(
              id: 'ai-role-extraction-merge-unusable',
              kind: 'merge_request_failed',
              message: '合并请求没有返回可用的角色字段，已使用分块结果降级合并。',
              blocking: false,
            ),
          ]
        : [
            for (final item in extraction.attentionItems)
              ScriptAiExtractionAttentionItem(
                id: item.id,
                kind: item.kind,
                message: item.message,
                sourceRoleId: item.sourceRoleId,
                frameIndexes: item.frameIndexes,
                blocking: false,
              ),
          ];
    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: ScriptAiRoleExtractionStatus.failed,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      rawResponse: extraction.rawResponse,
      attentionItems: List.unmodifiable(attentionItems),
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
    );
  }

  Future<ScriptAiRoleExtractionClientResult> _extractWithRetry(
    ScriptAiRoleExtractionClientRequest request,
  ) async {
    final attempts = retryDelays.length + 1;
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        return await client.extractRoles(request);
      } catch (error) {
        lastError = error;
        if (attempt >= attempts) {
          break;
        }
        final delay = retryDelays[attempt - 1];
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
    }
    throw ScriptAiRoleExtractionClientException(
      _contextualFailureMessage(
        request: request,
        attempts: attempts,
        error: lastError,
      ),
    );
  }

  String _contextualFailureMessage({
    required ScriptAiRoleExtractionClientRequest request,
    required int attempts,
    required Object? error,
  }) {
    final requestJson = request.requestJson;
    final kind = requestJson['request_kind']?.toString().trim();
    final chunkId = requestJson['chunk_id']?.toString().trim();
    final retryCount = attempts - 1;
    return [
      'AI 角色字段请求失败',
      if (kind != null && kind.isNotEmpty) '请求类型：$kind',
      if (chunkId != null && chunkId.isNotEmpty) 'Chunk：$chunkId',
      '地址：${_displayEndpoint(request.baseUrl)}',
      retryCount <= 0 ? '未自动重连' : '已自动重连 $retryCount 次',
      if (error != null) '最后错误：$error',
    ].join('；');
  }

  String _displayEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      return '未配置';
    }
    if (trimmed.endsWith('/v1/chat/completions')) return trimmed;
    if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
    return '$trimmed/v1/chat/completions';
  }

  ScriptAiRoleExtraction _normalizeExtraction(
    ScriptAiRoleExtraction extraction,
    _PromptWeightIndex promptWeightIndex,
  ) {
    return _normalizeOutfitStageVariants(
      _extractionWithRestoredPromptWeights(extraction, promptWeightIndex),
    ).collapseEquivalentStages();
  }

  ScriptAiRoleExtraction _extractionWithRestoredPromptWeights(
    ScriptAiRoleExtraction extraction,
    _PromptWeightIndex promptWeightIndex,
  ) {
    if (!extraction.isReady || extraction.roles.isEmpty) {
      return extraction;
    }
    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      roles: List.unmodifiable([
        for (final role in extraction.roles)
          _roleWithRestoredPromptWeights(role, promptWeightIndex),
      ]),
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      rawResponse: extraction.rawResponse,
    );
  }

  ScriptAiExtractedRole _roleWithRestoredPromptWeights(
    ScriptAiExtractedRole role,
    _PromptWeightIndex promptWeightIndex,
  ) {
    if (role.stages.isEmpty) {
      return role;
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
      warnings: role.warnings,
      stages: List.unmodifiable([
        for (final stage in role.stages)
          _stageWithRestoredPromptWeights(
            stage,
            promptWeightIndex,
            sourceRoleId: role.sourceRoleId,
            sourceKind: role.sourceKind,
            sourceIds: _appearanceSourceIdsForStage(role, stage),
          ),
      ]),
      unassignedTerms: role.unassignedTerms,
    );
  }

  ScriptAiExtractedStage _stageWithRestoredPromptWeights(
    ScriptAiExtractedStage stage,
    _PromptWeightIndex promptWeightIndex, {
    required String sourceRoleId,
    required String sourceKind,
    required List<String> sourceIds,
  }) {
    return ScriptAiExtractedStage(
      stageId: stage.stageId,
      label: stage.label,
      appearanceGroupId: stage.appearanceGroupId,
      mergeWithStageIds: stage.mergeWithStageIds,
      fieldReasons: stage.fieldReasons,
      confidence: stage.confidence,
      frameIndexes: stage.frameIndexes,
      identity: promptWeightIndex.restoreField(
        stage.identity,
        sourceRoleId: sourceRoleId,
        sourceKind: sourceKind,
        frameIndexes: stage.frameIndexes,
        sourceIds: sourceIds,
      ),
      upperBody: promptWeightIndex.restoreField(
        stage.upperBody,
        sourceRoleId: sourceRoleId,
        sourceKind: sourceKind,
        frameIndexes: stage.frameIndexes,
        sourceIds: sourceIds,
      ),
      lowerBody: promptWeightIndex.restoreField(
        stage.lowerBody,
        sourceRoleId: sourceRoleId,
        sourceKind: sourceKind,
        frameIndexes: stage.frameIndexes,
        sourceIds: sourceIds,
      ),
      upperClothing: promptWeightIndex.restoreField(
        stage.upperClothing,
        sourceRoleId: sourceRoleId,
        sourceKind: sourceKind,
        frameIndexes: stage.frameIndexes,
        sourceIds: sourceIds,
      ),
      lowerClothing: promptWeightIndex.restoreField(
        stage.lowerClothing,
        sourceRoleId: sourceRoleId,
        sourceKind: sourceKind,
        frameIndexes: stage.frameIndexes,
        sourceIds: sourceIds,
      ),
      nonRole: '',
      nonRoleMaterialized: false,
      evidenceTerms: stage.evidenceTerms,
      missingFields: stage.missingFields,
      warnings: stage.warnings,
    );
  }

  List<String> _appearanceSourceIdsForStage(
    ScriptAiExtractedRole role,
    ScriptAiExtractedStage stage,
  ) {
    if (role.appearances.isEmpty) {
      return const [];
    }
    final stageFrames = stage.frameIndexes.toSet();
    final sourceIds = <String>[];
    final seen = <String>{};
    for (final appearance in role.appearances) {
      final sourceId = appearance.sourceId.trim();
      if (sourceId.isEmpty) {
        continue;
      }
      final appearanceFrames = appearance.frameIndexes.toSet();
      final appliesToStage = stageFrames.isEmpty ||
          appearanceFrames.isEmpty ||
          appearanceFrames.any(stageFrames.contains);
      if (!appliesToStage || !seen.add(sourceId)) {
        continue;
      }
      sourceIds.add(sourceId);
    }
    return List.unmodifiable(sourceIds);
  }

  ScriptAiRoleExtraction _normalizeOutfitStageVariants(
    ScriptAiRoleExtraction extraction,
  ) {
    if (!extraction.isReady || extraction.roles.isEmpty) {
      return extraction;
    }
    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: extraction.status,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      roles: List.unmodifiable([
        for (final role in extraction.roles) _roleWithMergedStageVariants(role),
      ]),
      artistChains: extraction.artistChains,
      strongFilterKeywords: extraction.strongFilterKeywords,
      attentionItems: extraction.attentionItems,
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      rawResponse: extraction.rawResponse,
    );
  }

  ScriptAiExtractedRole _roleWithMergedStageVariants(
    ScriptAiExtractedRole role,
  ) {
    final stages = role.stages;
    if (stages.length < 2) return role;
    final mergedStages = <ScriptAiExtractedStage>[];
    for (final stage in stages) {
      final index = mergedStages.indexWhere(
        (current) => _shouldMergeOutfitStageVariant(current, stage),
      );
      if (index < 0) {
        mergedStages.add(stage);
        continue;
      }
      mergedStages[index] = _mergeOutfitStageVariant(
        mergedStages[index],
        stage,
      );
    }
    final mergedChanged = mergedStages.length != stages.length;
    if (!mergedChanged) {
      return role;
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
      warnings: mergedChanged
          ? _mergeStringList(role.warnings, const [
              'outfit_state_variant_merged',
            ])
          : role.warnings,
      stages: List.unmodifiable(mergedStages),
      unassignedTerms: role.unassignedTerms,
    );
  }

  String _roleFieldDisplayTag(String raw, String clean) {
    final cleanTag = clean.trim();
    final trimmedRaw = raw.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    final match =
        RegExp(r'^([-+]?\d*\.?\d+)::.*(?:::\s*)?$').firstMatch(trimmedRaw);
    if (match == null || cleanTag.isEmpty) {
      return cleanTag;
    }
    final weight = double.tryParse(match.group(1) ?? '');
    return weight == null
        ? cleanTag
        : PromptTagProcessor.formatInlineWeightTag(cleanTag, weight);
  }

  bool _shouldMergeOutfitStageVariant(
    ScriptAiExtractedStage left,
    ScriptAiExtractedStage right,
  ) {
    return _hasSameExtractedFields(left, right);
  }

  bool _hasSameExtractedFields(
    ScriptAiExtractedStage left,
    ScriptAiExtractedStage right,
  ) {
    return _hasSameTagText(left.identity, right.identity) &&
        _hasSameTagText(left.upperBody, right.upperBody) &&
        _hasSameTagText(left.lowerBody, right.lowerBody) &&
        _hasSameTagText(left.upperClothing, right.upperClothing) &&
        _hasSameTagText(left.lowerClothing, right.lowerClothing);
  }

  bool _hasSameTagText(String left, String right) {
    final leftTags = _normalizedTagSet(left);
    final rightTags = _normalizedTagSet(right);
    return leftTags.length == rightTags.length &&
        leftTags.containsAll(rightTags);
  }

  Set<String> _normalizedTagSet(String value) => _normalizedTags(value).toSet();

  List<String> _normalizedTags(String value) {
    return PromptTagProcessor.splitWorkshopTags(value)
        .map(PromptTagProcessor.cleanTagDisplay)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .map(PromptTagProcessor.normalizeMatchKey)
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  ScriptAiExtractedStage _mergeOutfitStageVariant(
    ScriptAiExtractedStage left,
    ScriptAiExtractedStage right,
  ) {
    final identity = _mergeTagText(left.identity, right.identity);
    final upperBody = _mergeTagText(left.upperBody, right.upperBody);
    final lowerBody = _mergeTagText(left.lowerBody, right.lowerBody);
    final upperClothing =
        _mergeTagText(left.upperClothing, right.upperClothing);
    final lowerClothing =
        _mergeTagText(left.lowerClothing, right.lowerClothing);
    return ScriptAiExtractedStage(
      stageId: left.stageId.trim().isEmpty ? right.stageId : left.stageId,
      label: left.label.trim().isEmpty ? right.label : left.label,
      appearanceGroupId: left.appearanceGroupId.trim().isEmpty
          ? right.appearanceGroupId
          : left.appearanceGroupId,
      mergeWithStageIds: _mergeStringList(
        left.mergeWithStageIds,
        right.mergeWithStageIds,
      ),
      fieldReasons: _mergeStringMap(left.fieldReasons, right.fieldReasons),
      confidence: left.confidence > right.confidence
          ? left.confidence
          : right.confidence,
      frameIndexes: _mergeIntList(left.frameIndexes, right.frameIndexes),
      identity: identity,
      upperBody: upperBody,
      lowerBody: lowerBody,
      upperClothing: upperClothing,
      lowerClothing: lowerClothing,
      nonRole: '',
      nonRoleMaterialized: false,
      evidenceTerms: _mergeStringList(left.evidenceTerms, right.evidenceTerms),
      missingFields: _mergedMissingFields(
        missingFields:
            _mergeStringList(left.missingFields, right.missingFields),
        identity: identity,
        upperBody: upperBody,
        lowerBody: lowerBody,
        upperClothing: upperClothing,
        lowerClothing: lowerClothing,
      ),
      warnings: _mergeStringList(
        [
          ...left.warnings,
          'outfit_state_variant_merged',
        ],
        right.warnings,
      ),
    );
  }

  String _mergeTagText(String left, String right) {
    final seen = <String>{};
    final tags = <String>[];
    for (final value in [left, right]) {
      for (final tag in PromptTagProcessor.splitWorkshopTags(value)) {
        final clean = PromptTagProcessor.cleanTagDisplay(tag).trim();
        final key = PromptTagProcessor.normalizeMatchKey(clean);
        if (key.isEmpty || !seen.add(key)) {
          continue;
        }
        tags.add(_roleFieldDisplayTag(tag, clean));
      }
    }
    return tags.join(', ');
  }

  List<int> _mergeIntList(List<int> left, List<int> right) {
    final values = {...left, ...right}.toList()..sort();
    return List.unmodifiable(values);
  }

  List<String> _mergeStringList(List<String> left, List<String> right) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in [...left, ...right]) {
      final trimmed = value.trim();
      final key = PromptTagProcessor.normalizeMatchKey(trimmed);
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      result.add(trimmed);
    }
    return List.unmodifiable(result);
  }

  Map<String, String> _mergeStringMap(
    Map<String, String> left,
    Map<String, String> right,
  ) {
    return Map.unmodifiable({
      ...right,
      ...left,
    });
  }

  List<String> _mergedMissingFields({
    required List<String> missingFields,
    required String identity,
    required String upperBody,
    required String lowerBody,
    required String upperClothing,
    required String lowerClothing,
  }) {
    return [
      for (final field in missingFields)
        if (!_fieldFilled(
          field: field,
          identity: identity,
          upperBody: upperBody,
          lowerBody: lowerBody,
          upperClothing: upperClothing,
          lowerClothing: lowerClothing,
        ))
          field,
    ];
  }

  bool _fieldFilled({
    required String field,
    required String identity,
    required String upperBody,
    required String lowerBody,
    required String upperClothing,
    required String lowerClothing,
  }) {
    return switch (field.trim()) {
      'missing_identity' || 'identity' => identity.trim().isNotEmpty,
      'missing_upper_body' || 'upper_body' => upperBody.trim().isNotEmpty,
      'missing_lower_body' || 'lower_body' => lowerBody.trim().isNotEmpty,
      'missing_upper_clothing' ||
      'upper_clothing' =>
        upperClothing.trim().isNotEmpty,
      'missing_lower_clothing' ||
      'lower_clothing' =>
        lowerClothing.trim().isNotEmpty,
      _ => false,
    };
  }

  Future<_FollowUpResolution> _resolveFollowUp({
    required ScriptAiRoleExtractionServiceRequest serviceRequest,
    required Map<String, dynamic> chunk,
    required ScriptAiRoleExtraction firstExtraction,
    required List<String> reasoningParts,
    required _PromptWeightIndex promptWeightIndex,
  }) async {
    final invalidItems = _invalidEvidenceRequestItems(firstExtraction);
    final followUpRequest = _evidenceFollowUpRequest(
      script: serviceRequest.script,
      chunk: chunk,
      extraction: firstExtraction,
    );
    final evidence = (followUpRequest['evidence'] as List?) ?? const [];
    if (evidence.isEmpty) {
      return _FollowUpResolution(
        extraction: _failedEvidenceRequestExtraction(
          extraction: firstExtraction,
          attentionItems: invalidItems,
        ),
        requestPreview: chunk,
        aiRequestCount: 0,
      );
    }

    serviceRequest.onRequestStarted?.call(followUpRequest);
    final clientRequest = ScriptAiRoleExtractionClientRequest(
      baseUrl: serviceRequest.baseUrl,
      token: serviceRequest.token,
      model: serviceRequest.model,
      proxy: serviceRequest.proxy,
      requestJson: followUpRequest,
      onStreamDelta: serviceRequest.onStreamDelta,
    );
    late final ScriptAiRoleExtractionClientResult result;
    try {
      result = await _extractWithRetry(clientRequest);
    } catch (error) {
      return _FollowUpResolution(
        extraction: ScriptAiRoleExtraction.failure(
          message: error.toString(),
          rawResponse: '',
        ),
        requestPreview: followUpRequest,
        aiRequestCount: 1,
      );
    }
    _addReasoningPart(
      reasoningParts,
      title: '${chunk['chunk_id'] ?? 'chunk'} evidence_followup',
      content: result.reasoningContent,
    );
    final followUpExtraction = _normalizeExtraction(
      parser.parse(result.rawJson),
      promptWeightIndex,
    );
    if (followUpExtraction.isNeedsMoreEvidence) {
      return _FollowUpResolution(
        extraction: ScriptAiRoleExtraction(
          schemaVersion: followUpExtraction.schemaVersion,
          status: ScriptAiRoleExtractionStatus.failed,
          chunkId: followUpExtraction.chunkId,
          confidence: followUpExtraction.confidence,
          attentionItems: [
            ...followUpExtraction.attentionItems,
            const ScriptAiExtractionAttentionItem(
              id: 'ai-role-extraction-followup-limit-reached',
              kind: 'followup_limit_reached',
              message:
                  'AI requested more evidence after the single allowed follow-up round.',
              blocking: true,
            ),
          ],
          unassignedTerms: followUpExtraction.unassignedTerms,
          evidenceRequests: followUpExtraction.evidenceRequests,
          rawResponse: followUpExtraction.rawResponse,
        ),
        requestPreview: followUpRequest,
        aiRequestCount: 1,
      );
    }
    if (invalidItems.isEmpty || !followUpExtraction.isReady) {
      return _FollowUpResolution(
        extraction: followUpExtraction,
        requestPreview: followUpRequest,
        aiRequestCount: 1,
      );
    }
    return _FollowUpResolution(
      extraction: ScriptAiRoleExtraction(
        schemaVersion: followUpExtraction.schemaVersion,
        status: followUpExtraction.status,
        chunkId: followUpExtraction.chunkId,
        confidence: followUpExtraction.confidence,
        roles: followUpExtraction.roles,
        artistChains: followUpExtraction.artistChains,
        strongFilterKeywords: followUpExtraction.strongFilterKeywords,
        attentionItems: [
          ...followUpExtraction.attentionItems,
          ...invalidItems,
        ],
        unassignedTerms: followUpExtraction.unassignedTerms,
        evidenceRequests: followUpExtraction.evidenceRequests,
        rawResponse: followUpExtraction.rawResponse,
      ),
      requestPreview: followUpRequest,
      aiRequestCount: 1,
    );
  }

  Map<String, dynamic> _evidenceFollowUpRequest({
    required Script script,
    required Map<String, dynamic> chunk,
    required ScriptAiRoleExtraction extraction,
  }) {
    final chunkMap = (chunk['chunk'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final startFrameIndex =
        _intValue(chunkMap['start_frame_index'], fallback: 0);
    final endFrameIndex = _intValue(chunkMap['end_frame_index'], fallback: 0);
    final framesByIndex = {
      for (final frame in script.frames)
        if (frame.parseStatus == ScriptFrameParseStatus.parsed)
          frame.index: frame,
    };

    final evidenceRows = <Map<String, dynamic>>[];
    final seenRows = <String>{};
    var usedGroups = 0;

    for (final request in extraction.evidenceRequests) {
      if (usedGroups >= _maxEvidenceRequestGroupsPerChunk) break;
      final source = _parseEvidenceSource(request.sourceId);
      if (source == null) {
        continue;
      }
      usedGroups += 1;
      var usedFramesInGroup = 0;
      for (final frameIndex in request.frameIndexes) {
        if (usedFramesInGroup >= _maxFramesPerEvidenceRequestGroup) break;
        if (evidenceRows.length >= _maxTotalFollowUpFramesPerChunk) break;
        if (startFrameIndex > 0 && frameIndex < startFrameIndex) continue;
        if (endFrameIndex > 0 && frameIndex > endFrameIndex) continue;
        final frame = framesByIndex[frameIndex];
        if (frame == null) continue;
        if (!_hasEvidenceForSource(frame: frame, source: source)) continue;
        final key = '${request.sourceId}:$frameIndex';
        if (!seenRows.add(key)) continue;
        evidenceRows.add(
          _evidenceRowForFrame(
            frame: frame,
            source: source,
          ),
        );
        usedFramesInGroup += 1;
      }
    }

    return {
      'schema_version': 2,
      'request_kind': 'evidence_followup',
      'chunk_id': chunk['chunk_id'],
      'script': _scriptSummary(script),
      'chunk': chunk['chunk'],
      'evidence': evidenceRows,
    };
  }

  bool _hasEvidenceForSource({
    required ScriptFrame frame,
    required _EvidenceSourceRef source,
  }) {
    final parsed = frame.parsed;
    if (source.sourceId == 'base') {
      return parsed.baseCaption.trim().isNotEmpty;
    }
    if (source.sourceId == 'negative-base') {
      return parsed.negativeBase.trim().isNotEmpty;
    }
    final slotIndex = source.slotIndex;
    if (slotIndex == null) {
      return false;
    }
    if (source.sourceId.startsWith('negative-slot-')) {
      return _listValue(parsed.negativeCharCaptions, slotIndex)
          .trim()
          .isNotEmpty;
    }
    return _listValue(parsed.charCaptions, slotIndex).trim().isNotEmpty;
  }

  Map<String, dynamic> _evidenceRowForFrame({
    required ScriptFrame frame,
    required _EvidenceSourceRef source,
  }) {
    final slotIndex = source.slotIndex;
    final parsed = frame.parsed;
    return {
      'frame_index': frame.index,
      'source_id': source.sourceId,
      'base_caption': parsed.baseCaption,
      'char_caption':
          slotIndex == null ? '' : _listValue(parsed.charCaptions, slotIndex),
      'negative_base': parsed.negativeBase,
      'negative_char_caption': slotIndex == null
          ? ''
          : _listValue(parsed.negativeCharCaptions, slotIndex),
    };
  }

  List<ScriptAiExtractionAttentionItem> _invalidEvidenceRequestItems(
    ScriptAiRoleExtraction extraction,
  ) {
    final items = <ScriptAiExtractionAttentionItem>[];
    for (final request in extraction.evidenceRequests) {
      if (_parseEvidenceSource(request.sourceId) != null) {
        continue;
      }
      items.add(
        ScriptAiExtractionAttentionItem(
          id: request.id.trim().isEmpty
              ? 'invalid-evidence-request-${items.length + 1}'
              : request.id,
          kind: 'invalid_evidence_request',
          message: 'Ignored unsupported evidence source "${request.sourceId}".',
          frameIndexes: request.frameIndexes,
          blocking: false,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  ScriptAiRoleExtraction _failedEvidenceRequestExtraction({
    required ScriptAiRoleExtraction extraction,
    required List<ScriptAiExtractionAttentionItem> attentionItems,
  }) {
    return ScriptAiRoleExtraction(
      schemaVersion: extraction.schemaVersion,
      status: ScriptAiRoleExtractionStatus.failed,
      chunkId: extraction.chunkId,
      confidence: extraction.confidence,
      attentionItems: [
        ...extraction.attentionItems,
        ...attentionItems,
        const ScriptAiExtractionAttentionItem(
          id: 'ai-role-extraction-no-valid-followup-evidence',
          kind: 'invalid_evidence_request',
          message:
              'AI requested follow-up evidence, but no valid frame evidence could be served.',
          blocking: true,
        ),
      ],
      unassignedTerms: extraction.unassignedTerms,
      evidenceRequests: extraction.evidenceRequests,
      rawResponse: extraction.rawResponse,
    );
  }

  _EvidenceSourceRef? _parseEvidenceSource(String sourceId) {
    final normalized = sourceId.trim();
    if (normalized == 'base' || normalized == 'negative-base') {
      return _EvidenceSourceRef(sourceId: normalized, slotIndex: null);
    }
    final slotMatch =
        RegExp(r'^(negative-)?slot-(\d+)$').firstMatch(normalized);
    if (slotMatch == null) {
      return null;
    }
    return _EvidenceSourceRef(
      sourceId: normalized,
      slotIndex: int.tryParse(slotMatch.group(2) ?? ''),
    );
  }

  String _listValue(List<String> values, int index) {
    if (index < 0 || index >= values.length) return '';
    return values[index];
  }

  int _intValue(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) return num.tryParse(value)?.toInt() ?? fallback;
    return fallback;
  }

  Map<String, dynamic> _mergeRequest({
    required Script script,
    required List<Map<String, dynamic>> chunks,
    required List<ScriptAiRoleExtraction> extractions,
  }) {
    return {
      'schema_version': 1,
      'request_kind': 'merge_extractions',
      'script': _scriptSummary(script),
      'chunks': [
        for (final chunk in chunks)
          {
            'chunk_id': chunk['chunk_id'],
            'chunk': chunk['chunk'],
          },
      ],
      'frame_prompts': _framePromptsFromChunks(chunks),
      'extractions': [
        for (final extraction in extractions) extraction.toJson(),
      ],
    };
  }

  List<Map<String, dynamic>> _framePromptsFromChunks(
    List<Map<String, dynamic>> chunks,
  ) {
    final framePrompts = <Map<String, dynamic>>[];
    for (final chunk in chunks) {
      final prompts = chunk['frame_prompts'];
      if (prompts is! List) {
        continue;
      }
      for (final prompt in prompts) {
        if (prompt is Map<String, dynamic>) {
          framePrompts.add(prompt);
        } else if (prompt is Map) {
          framePrompts.add(prompt.cast<String, dynamic>());
        }
      }
    }
    return List.unmodifiable(framePrompts);
  }

  Map<String, dynamic> _emptyRequestPreview(Script script) {
    return {
      'schema_version': 1,
      'request_kind': 'chunk_extract_v2',
      'script': _scriptSummary(script),
      'chunks': const [],
    };
  }

  Map<String, dynamic> _scriptSummary(Script script) {
    return {
      'id': script.id,
      'name': script.name,
      'detected_schema': script.detectedSchema.name,
      'frame_count': script.frames
          .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
          .length,
    };
  }
}
