import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/tools/generation_prompt_sanitizer.dart';
import 'package:novel_studio/data/studio/tools/nai_metadata_parser.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

class TokenizerScriptDraftSource {
  final String fileName;
  final String path;
  final TokenizerScriptSourceKind kind;
  final dynamic payload;
  final DateTime? modifiedAt;

  const TokenizerScriptDraftSource({
    required this.fileName,
    required this.path,
    required this.kind,
    required this.payload,
    this.modifiedAt,
  });
}

class TokenizerScriptDirectoryScanResult {
  final List<TokenizerScriptDraftSource> sources;
  final List<TokenizerScriptScanFailure> failures;
  final int totalFilesSeen;
  final int supportedFilesSeen;
  final int jsonCount;
  final int imageCount;

  const TokenizerScriptDirectoryScanResult({
    required this.sources,
    required this.failures,
    required this.totalFilesSeen,
    required this.supportedFilesSeen,
    required this.jsonCount,
    required this.imageCount,
  });

  int get failureCount => failures.length;

  List<String> get warnings => [
        if (failureCount > 0) '$failureCount files could not be scanned.',
      ];
}

class TokenizerScriptScanFailure {
  final String fileName;
  final String path;
  final String error;

  const TokenizerScriptScanFailure({
    required this.fileName,
    required this.path,
    required this.error,
  });
}

class PromptWorkshopTagPreview {
  final String text;
  final String translation;
  final TranslationSource translationSource;
  final String bucket;
  final WorkshopTagWarning warning;
  final List<String> suggestedParts;

  const PromptWorkshopTagPreview({
    required this.text,
    required this.translation,
    required this.translationSource,
    required this.bucket,
    this.warning = WorkshopTagWarning.none,
    this.suggestedParts = const [],
  });
}

class PromptWorkshopPreview {
  final List<PromptWorkshopTagPreview> tags;

  const PromptWorkshopPreview({required this.tags});

  List<String> get missingTranslations => [
        for (final tag in tags)
          if (tag.translationSource == TranslationSource.miss) tag.text,
      ];
}

class TokenizerScriptService {
  final WorkspaceService workspaceService;
  final TranslationCache translationCache;

  TokenizerScriptService({
    required this.workspaceService,
    TranslationCache? translationCache,
  }) : translationCache = translationCache ?? TranslationCache();

  Future<List<TokenizerScript>> loadScripts() async {
    final scripts = await workspaceService.loadTokenizerScripts();
    final deduped = _dedupeScriptsBySourceFolder(scripts);
    if (deduped.length != scripts.length) {
      await workspaceService.saveTokenizerScripts(deduped);
    }
    return [
      for (final script in deduped) await _refreshSourceExistence(script),
    ];
  }

  Future<void> saveScript(TokenizerScript script) async {
    final scripts = await loadScripts();
    final next = [
      for (final existing in scripts)
        if (!_sameScriptIdentity(existing, script)) existing,
      script.copyWith(updatedAt: DateTime.now()),
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    await workspaceService.saveTokenizerScripts(next);
  }

  Future<void> removeScript(String scriptId) async {
    final normalizedId = scriptId.trim();
    if (normalizedId.isEmpty) return;
    final scripts = await workspaceService.loadTokenizerScripts();
    await workspaceService.saveTokenizerScripts(
      scripts
          .where((script) => script.scriptId != normalizedId)
          .toList(growable: false),
    );
  }

  Future<TokenizerScript> addImageAttachmentVersion(
    TokenizerScript script, {
    required List<String> imagePaths,
    DateTime? createdAt,
    String? versionLabel,
  }) async {
    final sortedPaths = imagePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList()
      ..sort(
        (left, right) => _naturalCompare(
          _fileNameFromPath(left),
          _fileNameFromPath(right),
        ),
      );
    if (sortedPaths.isEmpty) return script;

    final now = createdAt ?? DateTime.now();
    final versionId = _id('script-image-version', now);
    final resolvedVersionLabel = versionLabel?.trim().isNotEmpty == true
        ? versionLabel!.trim()
        : _nextImageAttachmentVersionLabel(script);
    final matches = _matchImagePathsToSourceFiles(
      sourceFiles: script.sourceFiles,
      imagePaths: sortedPaths,
    );
    final tasksBySourceFileId = {
      for (final task in script.imageTasks) task.sourceFile.fileId: task,
    };

    final attachments = <TokenizerScriptImageAttachment>[];
    for (final (index, path) in sortedPaths.indexed) {
      final source = matches[path];
      final task = source == null ? null : tasksBySourceFileId[source.fileId];
      final metadata = await _metadataForImageAttachment(
        imagePath: path,
        sourceFile: source,
      );
      final prompt = _firstNonEmpty([
            metadata?.prompt,
            task?.originalPrompt,
            task?.parsedPrompt,
            task?.finalPrompt,
          ]) ??
          '';
      final payload = metadata?.payload ??
          _payloadForImageTask(task) ??
          (prompt.isEmpty ? const <String, dynamic>{} : {'input': prompt});
      attachments.add(
        TokenizerScriptImageAttachment(
          attachmentId: _id(
            'script-image',
            now.add(Duration(microseconds: index)),
          ),
          imagePath: path,
          label: 'Frame ${index + 1}',
          versionId: versionId,
          versionLabel: resolvedVersionLabel,
          frameIndex: index + 1,
          sourceFileName: metadata?.sourceFileName ?? source?.fileName,
          prompt: prompt,
          payload: payload,
          createdAt: now.add(Duration(microseconds: index)),
        ),
      );
    }

    return script.copyWith(
      updatedAt: now,
      imageAttachments: [...script.imageAttachments, ...attachments],
    );
  }

  TokenizerScript renameImageAttachment(
    TokenizerScript script, {
    required String attachmentId,
    required String label,
  }) {
    final normalizedId = attachmentId.trim();
    final normalizedLabel = label.trim();
    if (normalizedId.isEmpty || normalizedLabel.isEmpty) return script;
    return script.copyWith(
      updatedAt: DateTime.now(),
      imageAttachments: [
        for (final attachment in script.imageAttachments)
          attachment.attachmentId == normalizedId
              ? attachment.copyWith(label: normalizedLabel)
              : attachment,
      ],
    );
  }

  TokenizerScript removeImageAttachment(
    TokenizerScript script, {
    required String attachmentId,
  }) {
    final normalizedId = attachmentId.trim();
    if (normalizedId.isEmpty) return script;
    final attachments = script.imageAttachments
        .where((attachment) => attachment.attachmentId != normalizedId)
        .toList(growable: false);
    if (attachments.length == script.imageAttachments.length) return script;
    return script.copyWith(
      updatedAt: DateTime.now(),
      imageAttachments: attachments,
    );
  }

  Future<TokenizerScript> createDemoDraft() async {
    final script = createDraftFromSources(
      name: '模拟分词剧本',
      sourceFolder: 'demo://tokenizer-script',
      sources: _demoSources(),
    );
    await saveScript(script);
    return script;
  }

  TokenizerScript createDraftFromSources({
    required String name,
    required String sourceFolder,
    required List<TokenizerScriptDraftSource> sources,
    TokenizerScriptSourceMode sourceMode = TokenizerScriptSourceMode.auto,
  }) {
    final now = DateTime.now();
    final scriptId = _scriptIdForSourceFolder(sourceFolder, now);
    final sortedSources = _pairedDraftSources(sources);
    final tasks = <TokenizerImageTask>[];
    final identitiesByKey = <String, _IdentityAccumulator>{};

    for (final (index, source) in sortedSources.indexed) {
      tasks.add(
        _taskFromSource(
          scriptId: scriptId,
          index: index,
          source: source.source,
          defaultImagePath: source.defaultImagePath,
          identitiesByKey: identitiesByKey,
        ),
      );
    }

    final needsReview = tasks.any(
      (task) => task.reviewStatus == TokenizerTaskReviewStatus.needsReview,
    );
    return TokenizerScript(
      scriptId: scriptId,
      name: name,
      sourceFolder: sourceFolder,
      sourceMode: sourceMode,
      createdAt: now,
      updatedAt: now,
      status: needsReview
          ? TokenizerScriptStatus.needsReview
          : TokenizerScriptStatus.ready,
      sourceFiles: tasks.map((task) => task.sourceFile).toList(),
      sampleFileIds:
          tasks.take(3).map((task) => task.sourceFile.fileId).toList(),
      characterIdentities:
          identitiesByKey.values.map((entry) => entry.toIdentity()).toList(),
      styleStages: const [],
      knowledgeCandidates: const [
        TokenizerKnowledgeCandidate(
          candidateId: 'pending-artist-rule',
          type: 'artist',
          label: '[画师串] 候选合并规则',
          evidence: '多个 artist:* tag 会统一进入单个画师串占位符。',
        ),
      ],
      imageTasks: tasks,
      pipelineExportConfig: const {'handoff': 'oneImageOneTask'},
      knowledgeSnapshot: const {
        'rulePriority': ['confirmedKnowledge', 'scriptRules', 'systemRules'],
      },
    );
  }

  Future<TokenizerScript> sendToProductionQueue(
    TokenizerScript script, {
    String scope = 'allReady',
    List<String> taskIds = const [],
  }) async {
    final tasks = _tasksForScope(script, scope, taskIds);
    final now = DateTime.now();
    final queueId = _id('tokenizer-queue', now);
    final existingPlans = await workspaceService.loadBatchPlans();
    final plan = BatchPlan(
      id: queueId,
      name: '${script.name} 分词任务',
      items: [
        for (final task in tasks)
          {
            'taskId': task.taskId,
            'title': task.sourceFile.fileName,
            'prompt': _productionPromptForTask(task),
            'sourceFile': task.sourceFile.toJson(),
            'resolution': task.resolution,
            'coords': task.coords,
            'paramsOverride': task.generationParams,
            'placeholderMappings': [
              for (final mapping in task.placeholderMappings) mapping.toJson(),
            ],
            'artistPlaceholder': script.globalArtistPlaceholder,
            'warnings': task.warnings,
          },
      ],
      createdAt: now,
      updatedAt: now,
    );
    await workspaceService.saveBatchPlans([...existingPlans, plan]);

    final updated = script.copyWith(
      status: TokenizerScriptStatus.sent,
      updatedAt: now,
      sendRecords: [
        ...script.sendRecords,
        TokenizerSendRecord(
          recordId: _id('send', now),
          sentAt: now,
          scope: scope,
          taskCount: tasks.length,
          queueId: queueId,
        ),
      ],
    );
    await saveScript(updated);
    return updated;
  }

  Map<String, dynamic> exportScriptDocument(
    TokenizerScript script, {
    bool includeSourceFiles = false,
  }) {
    final scriptJson = _sanitizeScriptJson(
      script.toJson(),
      includeSourceFiles: includeSourceFiles,
    );
    return {
      'documentType': 'naiTokenizerScript',
      'documentVersion': 1,
      'includeSourceFiles': includeSourceFiles,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'script': scriptJson,
    };
  }

  TokenizerScript importScriptDocument(Map<String, dynamic> document) {
    final rawScript = document['script'];
    if (rawScript is! Map) {
      throw const FormatException(
        'Tokenizer script document is missing script.',
      );
    }
    return TokenizerScript.fromJson(_map(rawScript));
  }

  TokenizerScript confirmReviewItems(
    TokenizerScript script, {
    List<String> taskIds = const [],
    List<String> candidateIds = const [],
  }) {
    final taskIdSet = taskIds.toSet();
    final candidateIdSet = candidateIds.toSet();
    final imageTasks = [
      for (final task in script.imageTasks)
        taskIdSet.contains(task.taskId)
            ? _copyTask(task, reviewStatus: TokenizerTaskReviewStatus.confirmed)
            : task,
    ];
    final candidates = [
      for (final candidate in script.knowledgeCandidates)
        candidateIdSet.contains(candidate.candidateId)
            ? _copyCandidate(candidate, confirmed: true)
            : candidate,
    ];
    return script.copyWith(
      status: _statusForReviewTasks(imageTasks),
      imageTasks: imageTasks,
      knowledgeCandidates: candidates,
    );
  }

  PromptWorkshopPreview buildPromptWorkshopPreview(
    TokenizerImageTask task, {
    bool splitSpace = false,
  }) {
    final sourceText = task.originalPrompt?.trim().isNotEmpty == true
        ? task.originalPrompt!
        : task.finalPrompt;
    final tags = PromptTagProcessor.analyzeWorkshopTags(
      sourceText,
      splitSpace: splitSpace,
    );
    return PromptWorkshopPreview(
      tags: [for (final tag in tags) _workshopTagPreview(tag)],
    );
  }

  PromptWorkshopTagPreview _workshopTagPreview(WorkshopTagAnalysis tag) {
    final translation = translationCache.translate(tag.text);
    return PromptWorkshopTagPreview(
      text: tag.text,
      translation: translation.text,
      translationSource: translation.source,
      bucket: PromptTagProcessor.heuristicBucket(tag.text),
      warning: tag.warning,
      suggestedParts: tag.suggestedParts,
    );
  }

  TokenizerScript renameCharacterIdentity(
    TokenizerScript script, {
    required String identityId,
    required String displayName,
  }) {
    final identity = script.characterIdentities
        .where((item) => item.identityId == identityId)
        .firstOrNull;
    if (identity == null) return script;
    final oldPlaceholder = identity.placeholder;
    final newPlaceholder = '[$displayName]';
    return script.copyWith(
      characterIdentities: [
        for (final item in script.characterIdentities)
          item.identityId == identityId
              ? _copyIdentity(
                  item,
                  displayName: displayName,
                  placeholder: newPlaceholder,
                )
              : item,
      ],
      imageTasks: [
        for (final task in script.imageTasks)
          _replaceTaskPlaceholder(
            task,
            oldPlaceholder: oldPlaceholder,
            newPlaceholder: newPlaceholder,
            ownerIdentityId: identityId,
            markAdjusted: true,
          ),
      ],
      knowledgeCandidates: [
        ...script.knowledgeCandidates,
        TokenizerKnowledgeCandidate(
          candidateId: _id('confirmed-alias', DateTime.now()),
          type: 'characterAlias',
          label: displayName,
          evidence: oldPlaceholder,
          confirmed: true,
        ),
      ],
    );
  }

  TokenizerScript updateTaskPlaceholderMapping(
    TokenizerScript script, {
    required String taskId,
    required String oldPlaceholder,
    required String newPlaceholder,
    required String category,
    required List<String> originalTags,
  }) {
    return script.copyWith(
      imageTasks: [
        for (final task in script.imageTasks)
          task.taskId == taskId
              ? _copyTask(
                  _replaceTaskPlaceholder(
                    task,
                    oldPlaceholder: oldPlaceholder,
                    newPlaceholder: newPlaceholder,
                    markAdjusted: false,
                  ),
                  reviewStatus: TokenizerTaskReviewStatus.adjusted,
                  placeholderMappings: [
                    for (final mapping in task.placeholderMappings)
                      mapping.placeholder == oldPlaceholder
                          ? TokenizerPlaceholderMapping(
                              placeholder: newPlaceholder,
                              originalTags: originalTags,
                              category: category,
                              ownerIdentityId: mapping.ownerIdentityId,
                              source: 'user',
                            )
                          : mapping,
                  ],
                )
              : task,
      ],
    );
  }

  TokenizerScript addStyleStage(
    TokenizerScript script, {
    required String identityId,
    required String name,
    required List<String> taskIds,
    List<String> evidenceTags = const [],
  }) {
    final now = DateTime.now();
    final stage = TokenizerStyleStage(
      stageId: _id('style-stage', now),
      identityId: identityId,
      name: name,
      taskIds: taskIds,
      evidenceTags: evidenceTags,
    );
    final taskIdSet = taskIds.toSet();
    return script.copyWith(
      status: TokenizerScriptStatus.needsReview,
      styleStages: [...script.styleStages, stage],
      characterIdentities: [
        for (final identity in script.characterIdentities)
          identity.identityId == identityId
              ? _copyIdentity(
                  identity,
                  styleStages: [...identity.styleStages, stage.stageId],
                )
              : identity,
      ],
      imageTasks: [
        for (final task in script.imageTasks)
          taskIdSet.contains(task.taskId)
              ? _copyTask(
                  task,
                  reviewStatus: TokenizerTaskReviewStatus.needsReview,
                  styleStageRefs: [...task.styleStageRefs, stage.stageId],
                )
              : task,
      ],
      knowledgeCandidates: [
        ...script.knowledgeCandidates,
        TokenizerKnowledgeCandidate(
          candidateId: _id('pending-style-stage', now),
          type: 'styleStage',
          label: name,
          evidence: evidenceTags.join(', '),
        ),
      ],
    );
  }

  static TokenizerScriptStatus _statusForReviewTasks(
    List<TokenizerImageTask> tasks,
  ) {
    if (tasks.any(
      (task) => task.reviewStatus == TokenizerTaskReviewStatus.needsReview,
    )) {
      return TokenizerScriptStatus.needsReview;
    }
    if (tasks.any(
      (task) => task.reviewStatus == TokenizerTaskReviewStatus.auto,
    )) {
      return TokenizerScriptStatus.parsed;
    }
    return TokenizerScriptStatus.ready;
  }

  static TokenizerCharacterIdentity _copyIdentity(
    TokenizerCharacterIdentity identity, {
    String? displayName,
    String? placeholder,
    List<String>? styleStages,
  }) {
    return TokenizerCharacterIdentity(
      identityId: identity.identityId,
      displayName: displayName ?? identity.displayName,
      placeholder: placeholder ?? identity.placeholder,
      explicitNames: identity.explicitNames,
      evidenceTags: identity.evidenceTags,
      slotsSeen: identity.slotsSeen,
      parts: identity.parts,
      styleStages: styleStages ?? identity.styleStages,
    );
  }

  static TokenizerKnowledgeCandidate _copyCandidate(
    TokenizerKnowledgeCandidate candidate, {
    bool? confirmed,
  }) {
    return TokenizerKnowledgeCandidate(
      candidateId: candidate.candidateId,
      type: candidate.type,
      label: candidate.label,
      evidence: candidate.evidence,
      confirmed: confirmed ?? candidate.confirmed,
    );
  }

  static TokenizerImageTask _copyTask(
    TokenizerImageTask task, {
    String? finalPrompt,
    TokenizerTaskReviewStatus? reviewStatus,
    List<TokenizerPlaceholderMapping>? placeholderMappings,
    List<String>? styleStageRefs,
  }) {
    return TokenizerImageTask(
      taskId: task.taskId,
      sourceFile: task.sourceFile,
      parseStatus: task.parseStatus,
      originalPrompt: task.originalPrompt,
      promptMode: task.promptMode,
      parsedPrompt: task.parsedPrompt,
      finalPrompt: finalPrompt ?? task.finalPrompt,
      artistEvidence: task.artistEvidence,
      characterSlotMatches: task.characterSlotMatches,
      resolution: task.resolution,
      coords: task.coords,
      generationParams: task.generationParams,
      confidence: task.confidence,
      warnings: task.warnings,
      reviewStatus: reviewStatus ?? task.reviewStatus,
      placeholderMappings: placeholderMappings ?? task.placeholderMappings,
      styleStageRefs: styleStageRefs ?? task.styleStageRefs,
      details: task.details,
    );
  }

  static TokenizerImageTask _replaceTaskPlaceholder(
    TokenizerImageTask task, {
    required String oldPlaceholder,
    required String newPlaceholder,
    String? ownerIdentityId,
    bool markAdjusted = false,
  }) {
    final oldBase = _placeholderBase(oldPlaceholder);
    final newBase = _placeholderBase(newPlaceholder);
    final updatedMappings = [
      for (final mapping in task.placeholderMappings)
        mapping.placeholder == oldPlaceholder ||
                ownerIdentityId != null &&
                    mapping.ownerIdentityId == ownerIdentityId ||
                oldBase != null && mapping.placeholder.startsWith('[$oldBase')
            ? TokenizerPlaceholderMapping(
                placeholder: oldBase == null || newBase == null
                    ? newPlaceholder
                    : mapping.placeholder.replaceFirst(
                        '[$oldBase',
                        '[$newBase',
                      ),
                originalTags: mapping.originalTags,
                category: mapping.category,
                ownerIdentityId: ownerIdentityId ?? mapping.ownerIdentityId,
                source: 'user',
              )
            : mapping,
    ];
    final updatedPrompt = oldBase == null || newBase == null
        ? task.finalPrompt.replaceAll(oldPlaceholder, newPlaceholder)
        : task.finalPrompt.replaceAll('[$oldBase', '[$newBase');
    return _copyTask(
      task,
      finalPrompt: updatedPrompt,
      reviewStatus:
          markAdjusted ? TokenizerTaskReviewStatus.adjusted : task.reviewStatus,
      placeholderMappings: updatedMappings,
    );
  }

  static String? _placeholderBase(String placeholder) {
    if (!placeholder.startsWith('[') || !placeholder.endsWith(']')) {
      return null;
    }
    return placeholder.substring(1, placeholder.length - 1);
  }

  TokenizerImageTask _taskFromSource({
    required String scriptId,
    required int index,
    required TokenizerScriptDraftSource source,
    required String defaultImagePath,
    required Map<String, _IdentityAccumulator> identitiesByKey,
  }) {
    final fileId = '$scriptId-source-${index + 1}';
    final sourceFile = TokenizerSourceFile(
      fileId: fileId,
      fileName: source.fileName,
      path: source.path,
      kind: source.kind,
      defaultImagePath: defaultImagePath,
      modifiedAt: source.modifiedAt,
      exists: true,
    );

    try {
      final parsed = NaiMetadataParser.parse(_payloadForParsing(source));
      final prompt = parsed.prompt?.trim() ?? '';
      final charPrompts = parsed.charCaptions.isEmpty
          ? _characterPromptsFromPrompt(prompt)
          : parsed.charCaptions;
      final combinedPrompt = [
        prompt,
        ...charPrompts,
      ].where((part) => part.trim().isNotEmpty).join(', ');
      final bucket = PromptTagProcessor.heuristicSplit(combinedPrompt);
      final artistEvidence = _artistTags([prompt, ...charPrompts]);
      final warnings = <String>[];
      if (artistEvidence.isEmpty) {
        warnings.add('画师串识别失败，需要校验。');
      }

      final mappings = <TokenizerPlaceholderMapping>[];
      if (artistEvidence.isNotEmpty) {
        mappings.add(
          const TokenizerPlaceholderMapping(
            placeholder: TokenizerScript.artistPlaceholder,
            originalTags: [],
            category: 'artist',
            source: 'system',
          ),
        );
      }

      final characterMatches = <String>[];
      final detailCharacters = <String, TokenizerCharacterDetails>{};
      var characterIndex = 0;
      for (final charPrompt in charPrompts) {
        final tags = _splitTags(charPrompt);
        final explicitName = _explicitCharacterName(tags);
        final displayName = explicitName ?? '角色${_letter(characterIndex)}';
        final key = _normalizeIdentityKey(displayName);
        final identityId = 'identity-${key.hashCode.abs()}';
        final accumulator = identitiesByKey.putIfAbsent(
          key,
          () => _IdentityAccumulator(
            identityId: identityId,
            displayName: displayName,
            explicitNames: explicitName == null ? const [] : [explicitName],
          ),
        );
        accumulator.slotsSeen.add(
          '${source.fileName} char${characterIndex + 1}',
        );
        accumulator.evidenceTags.addAll(tags.take(4));
        final placeholder = accumulator.placeholder;
        characterMatches.add('$placeholder char${characterIndex + 1}');
        final details = _classifyCharacterTags(tags);
        detailCharacters[placeholder] = details;
        mappings.add(
          TokenizerPlaceholderMapping(
            placeholder: placeholder,
            originalTags: details.identityTags,
            category: 'characterIdentity',
            ownerIdentityId: identityId,
            source: explicitName == null ? 'systemImplicit' : 'systemExplicit',
          ),
        );
        for (final entry in _partMappings(placeholder, identityId, details)) {
          mappings.add(entry);
        }
        characterIndex++;
      }

      final finalPrompt = _buildFinalPrompt(
        prompt: combinedPrompt,
        artistEvidence: artistEvidence,
        mappings: mappings,
      );
      final confidence = artistEvidence.isEmpty ? 0.62 : 0.86;
      final reviewStatus = warnings.isEmpty
          ? TokenizerTaskReviewStatus.auto
          : TokenizerTaskReviewStatus.needsReview;

      return TokenizerImageTask(
        taskId: '$scriptId-task-${index + 1}',
        sourceFile: sourceFile,
        parseStatus: 'parsed',
        originalPrompt: prompt.isEmpty ? null : prompt,
        promptMode: _promptMode(prompt),
        parsedPrompt: combinedPrompt,
        finalPrompt: finalPrompt,
        artistEvidence: artistEvidence,
        characterSlotMatches: characterMatches,
        resolution: parsed.resolution,
        coords: parsed.coords,
        generationParams: _generationParams(parsed),
        confidence: confidence,
        warnings: warnings,
        reviewStatus: reviewStatus,
        placeholderMappings: mappings,
        details: TokenizerParseDetails(
          artistStack: artistEvidence,
          characters: detailCharacters,
          sceneTags: bucket.scene,
          naturalLanguageSegments:
              _promptMode(prompt) == TokenizerScriptPromptMode.naturalLanguage
                  ? [prompt]
                  : const [],
          warnings: warnings,
        ),
      );
    } catch (error) {
      return TokenizerImageTask(
        taskId: '$scriptId-task-${index + 1}',
        sourceFile: sourceFile,
        parseStatus: 'failed',
        promptMode: TokenizerScriptPromptMode.tag,
        parsedPrompt: '',
        finalPrompt: '',
        artistEvidence: const [],
        characterSlotMatches: const [],
        confidence: 0,
        warnings: ['解析失败：$error'],
        reviewStatus: TokenizerTaskReviewStatus.failed,
        details: TokenizerParseDetails(warnings: ['解析失败：$error']),
      );
    }
  }

  List<TokenizerScriptDraftSource> _demoSources() {
    return const [
      TokenizerScriptDraftSource(
        fileName: '001_shamare.json',
        path: 'demo://001_shamare.json',
        kind: TokenizerScriptSourceKind.json,
        payload: {
          'Description': 'artist:demo_a, masterpiece, classroom',
          'width': 1024,
          'height': 1536,
          'v4_prompt': {
            'caption': {
              'char_captions': [
                {
                  'char_caption':
                      'shamare (arknights), white hair, red eyes, black dress, holding book',
                  'coords': {'x': 0.34, 'y': 0.52},
                },
              ],
            },
          },
          'steps': 28,
          'scale': 5.5,
          'seed': 123456,
        },
      ),
      TokenizerScriptDraftSource(
        fileName: '002_shamare_alt.json',
        path: 'demo://002_shamare_alt.json',
        kind: TokenizerScriptSourceKind.json,
        payload: {
          'Description': 'artist:demo_a, artist:demo_b, library, warm light',
          'resolution': '1216x832',
          'v4_prompt': {
            'caption': {
              'char_captions': [
                {
                  'char_caption':
                      'shamare (arknights), white hair, red eyes, white shirt, skirt, boots',
                },
              ],
            },
          },
          'sampler': 'k_euler',
        },
      ),
      TokenizerScriptDraftSource(
        fileName: '003_needs_review.json',
        path: 'demo://003_needs_review.json',
        kind: TokenizerScriptSourceKind.json,
        payload: {
          'Description':
              '1girl, white hair, red eyes, black dress, reaching toward viewer',
          'width': 832,
          'height': 1216,
        },
      ),
    ];
  }

  List<TokenizerImageTask> _tasksForScope(
    TokenizerScript script,
    String scope,
    List<String> taskIds,
  ) {
    if (scope == 'selected' || scope == 'current') {
      final selectedIds = taskIds.toSet();
      return script.imageTasks
          .where(
            (task) =>
                selectedIds.contains(task.taskId) &&
                task.reviewStatus != TokenizerTaskReviewStatus.failed,
          )
          .toList(growable: false);
    }
    if (scope == 'confirmed') {
      return script.imageTasks
          .where(
            (task) =>
                task.reviewStatus == TokenizerTaskReviewStatus.confirmed ||
                task.reviewStatus == TokenizerTaskReviewStatus.adjusted,
          )
          .toList(growable: false);
    }
    return script.imageTasks
        .where((task) => task.reviewStatus != TokenizerTaskReviewStatus.failed)
        .toList(growable: false);
  }

  static String _productionPromptForTask(TokenizerImageTask task) {
    final originalPrompt = task.originalPrompt?.trim();
    if (originalPrompt != null && originalPrompt.isNotEmpty) {
      return sanitizeGenerationPrompt(originalPrompt);
    }
    final parsedPrompt = task.parsedPrompt.trim();
    if (parsedPrompt.isNotEmpty) {
      return sanitizeGenerationPrompt(parsedPrompt);
    }
    return sanitizeGenerationPrompt(task.finalPrompt);
  }

  static Map<String, dynamic> _sanitizeScriptJson(
    Map<String, dynamic> json, {
    required bool includeSourceFiles,
  }) {
    final sanitized = _sanitizeJson(json) as Map<String, dynamic>;
    if (!includeSourceFiles) {
      sanitized['sourceFolder'] = '';
      sanitized['sourceFiles'] = const <Map<String, dynamic>>[];
      sanitized['sampleFileIds'] = const <String>[];
      final tasks = sanitized['imageTasks'];
      if (tasks is List) {
        sanitized['imageTasks'] = [
          for (final task in tasks)
            if (task is Map) _withoutPackedSourceFile(_map(task)),
        ];
      }
    }
    return sanitized;
  }

  static Map<String, dynamic> _withoutPackedSourceFile(
    Map<String, dynamic> task,
  ) {
    final sourceFile = _map(task['sourceFile']);
    task['sourceFile'] = {
      'fileId': _string(sourceFile['fileId'], ''),
      'fileName': _string(sourceFile['fileName'], ''),
      'path': '',
      'kind': _string(sourceFile['kind'], TokenizerScriptSourceKind.json.name),
      'exists': false,
    };
    return task;
  }

  static dynamic _sanitizeJson(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_isSensitiveKey(key)) continue;
        result[key] = _sanitizeJson(entry.value);
      }
      return result;
    }
    if (value is List) {
      return value.map(_sanitizeJson).toList(growable: false);
    }
    if (value is String && _isSensitiveValue(value)) {
      return '[stripped]';
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('apikey') ||
        normalized.contains('authorization') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized.contains('cookie');
  }

  static bool _isSensitiveValue(String value) {
    return RegExp(r'\bsk-[A-Za-z0-9_-]{6,}\b').hasMatch(value) ||
        RegExp(
          r'\bBearer\s+[A-Za-z0-9._-]{6,}\b',
          caseSensitive: false,
        ).hasMatch(value);
  }

  static List<String> _artistTags(List<String> prompts) {
    final result = <String>{};
    for (final prompt in prompts) {
      for (final tag in _splitTags(prompt)) {
        if (tag.toLowerCase().contains('artist:')) {
          result.add(tag);
        }
      }
    }
    return result.toList(growable: false);
  }

  static List<String> _characterPromptsFromPrompt(String prompt) {
    final tags = _splitTags(prompt);
    final explicit = _explicitCharacterName(tags);
    if (explicit != null) return [prompt];
    return const [];
  }

  static List<String> _splitTags(String prompt) {
    return prompt
        .split(RegExp(r'[,，\n]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  static String? _explicitCharacterName(List<String> tags) {
    for (final tag in tags) {
      final normalized = tag.toLowerCase();
      if (normalized.contains('artist:')) continue;
      if (normalized.contains('(') && normalized.contains(')')) {
        return tag;
      }
    }
    return null;
  }

  static TokenizerCharacterDetails _classifyCharacterTags(List<String> tags) {
    final identity = <String>[];
    final upperBody = <String>[];
    final upperClothing = <String>[];
    final lowerBody = <String>[];
    final lowerClothing = <String>[];
    final action = <String>[];
    final untouched = <String>[];
    for (final tag in tags) {
      final key = tag.toLowerCase();
      if (key.contains('(') && key.contains(')')) {
        identity.add(tag);
      } else if (_containsAny(key, const [
        'hair',
        'eyes',
        'hat',
        'ornament',
        'ribbon',
      ])) {
        upperBody.add(tag);
      } else if (_containsAny(key, const [
        'dress',
        'shirt',
        'jacket',
        'coat',
        'cape',
        'uniform',
      ])) {
        upperClothing.add(tag);
      } else if (_containsAny(key, const ['legs', 'thigh', 'skin'])) {
        lowerBody.add(tag);
      } else if (_containsAny(key, const [
        'skirt',
        'pants',
        'boots',
        'shoes',
        'socks',
        'thighhighs',
      ])) {
        lowerClothing.add(tag);
      } else if (_containsAny(key, const [
        'holding',
        'reaching',
        'looking',
        'running',
        'walking',
      ])) {
        action.add(tag);
      } else {
        untouched.add(tag);
      }
    }
    return TokenizerCharacterDetails(
      identityTags: identity,
      upperBodyTags: upperBody,
      upperClothingTags: upperClothing,
      lowerBodyTags: lowerBody,
      lowerClothingTags: lowerClothing,
      actionTags: action,
      untouchedTags: untouched,
    );
  }

  static List<TokenizerPlaceholderMapping> _partMappings(
    String characterPlaceholder,
    String identityId,
    TokenizerCharacterDetails details,
  ) {
    final base = characterPlaceholder.substring(
      1,
      characterPlaceholder.length - 1,
    );
    final result = <TokenizerPlaceholderMapping>[];
    void add(String suffix, List<String> tags, String category) {
      if (tags.isEmpty) return;
      result.add(
        TokenizerPlaceholderMapping(
          placeholder: '[$base$suffix]',
          originalTags: tags,
          category: category,
          ownerIdentityId: identityId,
          source: 'system',
        ),
      );
    }

    add('上身', details.upperBodyTags, 'upperBody');
    add('上装', details.upperClothingTags, 'upperClothing');
    add('下身', details.lowerBodyTags, 'lowerBody');
    add('下装', details.lowerClothingTags, 'lowerClothing');
    return result;
  }

  static String _buildFinalPrompt({
    required String prompt,
    required List<String> artistEvidence,
    required List<TokenizerPlaceholderMapping> mappings,
  }) {
    var result = prompt;
    for (final tag in artistEvidence) {
      result = result.replaceAll(tag, TokenizerScript.artistPlaceholder);
    }
    for (final mapping in mappings) {
      if (mapping.category == 'artist') continue;
      for (final tag in mapping.originalTags) {
        result = result.replaceAll(tag, mapping.placeholder);
      }
    }
    return _dedupePromptTags(result);
  }

  static String _dedupePromptTags(String prompt) {
    final seen = <String>{};
    final tags = <String>[];
    for (final tag in _splitTags(prompt)) {
      if (seen.add(tag)) tags.add(tag);
    }
    return tags.join(', ');
  }

  static TokenizerScriptPromptMode _promptMode(String prompt) {
    if (prompt.contains('，') || prompt.contains('。')) {
      return TokenizerScriptPromptMode.naturalLanguage;
    }
    return TokenizerScriptPromptMode.tag;
  }

  static Map<String, dynamic> _generationParams(NaiMetadataParseResult parsed) {
    final result = <String, dynamic>{};
    for (final key in const ['steps', 'scale', 'sampler', 'seed']) {
      final value = parsed.parameters[key];
      if (value != null) result[key] = value;
    }
    for (final key in const ['v4_prompt', 'v4_negative_prompt']) {
      final value = parsed.parameters[key];
      if (value is Map) {
        result[key] = value.cast<String, dynamic>();
      }
    }
    if (parsed.width != null) result['width'] = parsed.width;
    if (parsed.height != null) result['height'] = parsed.height;
    return result;
  }

  static bool _containsAny(String value, List<String> patterns) {
    return patterns.any(value.contains);
  }

  static String _normalizeIdentityKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[_\s]+'), ' ')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .trim();
  }

  static String _letter(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  static String _id(String prefix, DateTime time) {
    return '$prefix-${time.microsecondsSinceEpoch}';
  }

  static String _scriptIdForSourceFolder(String sourceFolder, DateTime now) {
    final identity = _sourceFolderIdentity(sourceFolder);
    if (identity == null) return _id('script', now);
    return stableIdFromText(
      prefix: 'script',
      text: identity,
      label: _fileNameFromPath(identity),
    );
  }

  static bool _sameScriptIdentity(
    TokenizerScript existing,
    TokenizerScript script,
  ) {
    if (existing.scriptId == script.scriptId) return true;
    final existingFolder = _sourceFolderIdentity(existing.sourceFolder);
    final scriptFolder = _sourceFolderIdentity(script.sourceFolder);
    return existingFolder != null && existingFolder == scriptFolder;
  }

  static List<TokenizerScript> _dedupeScriptsBySourceFolder(
    List<TokenizerScript> scripts,
  ) {
    final bySourceFolder = <String, TokenizerScript>{};
    final unkeyed = <TokenizerScript>[];
    for (final script in scripts) {
      final sourceFolder = _sourceFolderIdentity(script.sourceFolder);
      if (sourceFolder == null) {
        unkeyed.add(script);
        continue;
      }
      final existing = bySourceFolder[sourceFolder];
      bySourceFolder[sourceFolder] =
          existing == null ? script : _newerScript(existing, script);
    }
    return [...unkeyed, ...bySourceFolder.values]
      ..sort((left, right) => _compareScriptRecency(right, left));
  }

  static TokenizerScript _newerScript(
    TokenizerScript left,
    TokenizerScript right,
  ) {
    return _compareScriptRecency(left, right) >= 0 ? left : right;
  }

  static int _compareScriptRecency(
    TokenizerScript left,
    TokenizerScript right,
  ) {
    final updated = left.updatedAt.compareTo(right.updatedAt);
    if (updated != 0) return updated;
    final created = left.createdAt.compareTo(right.createdAt);
    if (created != 0) return created;
    return left.scriptId.compareTo(right.scriptId);
  }

  static String? _sourceFolderIdentity(String value) {
    final normalized = value
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  static List<_TokenizerPairedDraftSource> _pairedDraftSources(
    List<TokenizerScriptDraftSource> sources,
  ) {
    final sortedSources = [...sources]
      ..sort((left, right) => _naturalCompare(left.fileName, right.fileName));
    final jsonSources = sortedSources
        .where((source) => source.kind == TokenizerScriptSourceKind.json)
        .toList(growable: false);
    final imageSources = sortedSources
        .where((source) => source.kind == TokenizerScriptSourceKind.image)
        .toList(growable: false);
    final usedJson = <TokenizerScriptDraftSource>{};
    final usedImages = <TokenizerScriptDraftSource>{};
    final paired = <_TokenizerPairedDraftSource>[];

    for (final json in jsonSources) {
      final image = _firstMatchingImage(
        imageSources,
        usedImages,
        (candidate) =>
            _sourceStem(candidate.fileName) == _sourceStem(json.fileName),
      );
      if (image == null) continue;
      usedJson.add(json);
      usedImages.add(image);
      paired.add(_pairedJsonSource(json, image));
    }

    _pairBySequenceKey(
      jsonSources: jsonSources,
      imageSources: imageSources,
      usedJson: usedJson,
      usedImages: usedImages,
      paired: paired,
    );

    final remainingJson = [
      for (final source in jsonSources)
        if (!usedJson.contains(source)) source,
    ];
    final remainingImages = [
      for (final source in imageSources)
        if (!usedImages.contains(source)) source,
    ];
    if (remainingJson.isNotEmpty &&
        remainingJson.length == remainingImages.length) {
      for (final (index, json) in remainingJson.indexed) {
        final image = remainingImages[index];
        usedJson.add(json);
        usedImages.add(image);
        paired.add(_pairedJsonSource(json, image));
      }
    }

    for (final source in jsonSources) {
      if (usedJson.contains(source)) continue;
      paired.add(_pairedJsonSource(source, null));
    }
    for (final source in imageSources) {
      if (usedImages.contains(source)) continue;
      paired.add(
        _TokenizerPairedDraftSource(
          source: source,
          defaultImagePath: source.path,
        ),
      );
    }

    paired.sort(
      (left, right) =>
          _naturalCompare(left.source.fileName, right.source.fileName),
    );
    return List.unmodifiable(paired);
  }

  static Map<String, TokenizerSourceFile> _matchImagePathsToSourceFiles({
    required List<TokenizerSourceFile> sourceFiles,
    required List<String> imagePaths,
  }) {
    final sortedSources = [...sourceFiles]
      ..sort((left, right) => _naturalCompare(left.fileName, right.fileName));
    final sortedImages = [...imagePaths]..sort(
        (left, right) =>
            _naturalCompare(_fileNameFromPath(left), _fileNameFromPath(right)),
      );
    final usedSources = <TokenizerSourceFile>{};
    final usedImages = <String>{};
    final result = <String, TokenizerSourceFile>{};

    for (final source in sortedSources) {
      final image = _firstMatchingImagePath(
        sortedImages,
        usedImages,
        (candidate) =>
            _sourceStem(_fileNameFromPath(candidate)) ==
            _sourceStem(source.fileName),
      );
      if (image == null) continue;
      usedSources.add(source);
      usedImages.add(image);
      result[image] = source;
    }

    _pairImagePathsBySequenceKey(
      sourceFiles: sortedSources,
      imagePaths: sortedImages,
      usedSources: usedSources,
      usedImages: usedImages,
      result: result,
    );

    final remainingSources = [
      for (final source in sortedSources)
        if (!usedSources.contains(source)) source,
    ];
    final remainingImages = [
      for (final path in sortedImages)
        if (!usedImages.contains(path)) path,
    ];
    if (remainingSources.isNotEmpty &&
        remainingSources.length == remainingImages.length) {
      for (final (index, source) in remainingSources.indexed) {
        final image = remainingImages[index];
        result[image] = source;
      }
    }
    return result;
  }

  String _nextImageAttachmentVersionLabel(TokenizerScript script) {
    final existingVersionIds = {
      for (final attachment in script.imageAttachments)
        if (attachment.versionId.trim().isNotEmpty) attachment.versionId.trim(),
    };
    return '导入图片 ${existingVersionIds.length + 1}';
  }

  Future<_ImageAttachmentMetadata?> _metadataForImageAttachment({
    required String imagePath,
    required TokenizerSourceFile? sourceFile,
  }) async {
    final jsonPath = await _jsonPathForImageAttachment(
      imagePath: imagePath,
      sourceFile: sourceFile,
    );
    if (jsonPath != null) {
      final metadata = await _metadataFromJsonFile(jsonPath);
      if (metadata != null) return metadata;
    }

    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      return null;
    }
    final payload = await _imageMetadataPayload(imageFile);
    final parsed = NaiMetadataParser.parse(payload);
    return _metadataFromParsed(
      parsed,
      sourceFileName: _fileNameFromPath(imagePath),
    );
  }

  Future<String?> _jsonPathForImageAttachment({
    required String imagePath,
    required TokenizerSourceFile? sourceFile,
  }) async {
    final sourcePath = sourceFile?.path.trim();
    if (sourcePath != null && sourcePath.toLowerCase().endsWith('.json')) {
      final file = File(sourcePath);
      if (await file.exists()) return sourcePath;
    }
    final sameStemPath = _replaceExtension(imagePath, '.json');
    if (sameStemPath != null && await File(sameStemPath).exists()) {
      return sameStemPath;
    }
    return null;
  }

  Future<_ImageAttachmentMetadata?> _metadataFromJsonFile(String path) async {
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      final parsed = NaiMetadataParser.parse(decoded);
      return _metadataFromParsed(
        parsed,
        sourceFileName: _fileNameFromPath(path),
      );
    } catch (_) {
      return null;
    }
  }

  _ImageAttachmentMetadata _metadataFromParsed(
    NaiMetadataParseResult parsed, {
    required String sourceFileName,
  }) {
    final prompt = _firstNonEmpty([
      parsed.prompt,
      ...parsed.charCaptions,
      parsed.rawContent,
    ]);
    return _ImageAttachmentMetadata(
      prompt: prompt,
      payload: _payloadForParsedMetadata(parsed, prompt: prompt),
      sourceFileName: sourceFileName,
    );
  }

  Map<String, dynamic> _payloadForParsedMetadata(
    NaiMetadataParseResult parsed, {
    required String? prompt,
  }) {
    final payload = <String, dynamic>{};
    final cleanedPrompt = prompt?.trim();
    if (cleanedPrompt != null && cleanedPrompt.isNotEmpty) {
      payload['input'] = cleanedPrompt;
    }
    final negativePrompt = parsed.negativePrompt?.trim();
    if (negativePrompt != null && negativePrompt.isNotEmpty) {
      payload['uc'] = negativePrompt;
    }
    final parameters = _generationParams(parsed);
    if (parameters.isNotEmpty) {
      payload['parameters'] = parameters;
    }
    return Map.unmodifiable(payload);
  }

  Map<String, dynamic>? _payloadForImageTask(TokenizerImageTask? task) {
    if (task == null) return null;
    final prompt = _firstNonEmpty([
      task.originalPrompt,
      task.parsedPrompt,
      task.finalPrompt,
    ]);
    final payload = <String, dynamic>{};
    if (prompt != null) {
      payload['input'] = prompt;
    }
    if (task.generationParams.isNotEmpty) {
      payload['parameters'] = Map.unmodifiable(task.generationParams);
    }
    return payload.isEmpty ? null : Map.unmodifiable(payload);
  }

  static String? _firstMatchingImagePath(
    List<String> imagePaths,
    Set<String> usedImages,
    bool Function(String imagePath) matches,
  ) {
    for (final imagePath in imagePaths) {
      if (usedImages.contains(imagePath)) continue;
      if (matches(imagePath)) return imagePath;
    }
    return null;
  }

  static void _pairImagePathsBySequenceKey({
    required List<TokenizerSourceFile> sourceFiles,
    required List<String> imagePaths,
    required Set<TokenizerSourceFile> usedSources,
    required Set<String> usedImages,
    required Map<String, TokenizerSourceFile> result,
  }) {
    final sourcesByKey = <String, List<TokenizerSourceFile>>{};
    final imagesByKey = <String, List<String>>{};
    for (final source in sourceFiles) {
      if (usedSources.contains(source)) continue;
      final key = _sequenceKey(source.fileName);
      if (key == null) continue;
      (sourcesByKey[key] ??= []).add(source);
    }
    for (final imagePath in imagePaths) {
      if (usedImages.contains(imagePath)) continue;
      final key = _sequenceKey(_fileNameFromPath(imagePath));
      if (key == null) continue;
      (imagesByKey[key] ??= []).add(imagePath);
    }
    final keys = sourcesByKey.keys.toList()..sort(_naturalCompare);
    for (final key in keys) {
      final sourceGroup = sourcesByKey[key] ?? const [];
      final imageGroup = imagesByKey[key] ?? const [];
      if (sourceGroup.isEmpty || sourceGroup.length != imageGroup.length) {
        continue;
      }
      for (final (index, source) in sourceGroup.indexed) {
        final image = imageGroup[index];
        usedSources.add(source);
        usedImages.add(image);
        result[image] = source;
      }
    }
  }

  static _TokenizerPairedDraftSource _pairedJsonSource(
    TokenizerScriptDraftSource json,
    TokenizerScriptDraftSource? image,
  ) {
    return _TokenizerPairedDraftSource(
      source: json,
      defaultImagePath: image?.path ?? '',
    );
  }

  static TokenizerScriptDraftSource? _firstMatchingImage(
    List<TokenizerScriptDraftSource> images,
    Set<TokenizerScriptDraftSource> usedImages,
    bool Function(TokenizerScriptDraftSource image) matches,
  ) {
    for (final image in images) {
      if (usedImages.contains(image)) continue;
      if (matches(image)) return image;
    }
    return null;
  }

  static void _pairBySequenceKey({
    required List<TokenizerScriptDraftSource> jsonSources,
    required List<TokenizerScriptDraftSource> imageSources,
    required Set<TokenizerScriptDraftSource> usedJson,
    required Set<TokenizerScriptDraftSource> usedImages,
    required List<_TokenizerPairedDraftSource> paired,
  }) {
    final jsonByKey = <String, List<TokenizerScriptDraftSource>>{};
    final imagesByKey = <String, List<TokenizerScriptDraftSource>>{};
    for (final json in jsonSources) {
      if (usedJson.contains(json)) continue;
      final key = _sequenceKey(json.fileName);
      if (key == null) continue;
      (jsonByKey[key] ??= []).add(json);
    }
    for (final image in imageSources) {
      if (usedImages.contains(image)) continue;
      final key = _sequenceKey(image.fileName);
      if (key == null) continue;
      (imagesByKey[key] ??= []).add(image);
    }
    final keys = jsonByKey.keys.toList()..sort(_naturalCompare);
    for (final key in keys) {
      final jsonGroup = jsonByKey[key] ?? const [];
      final imageGroup = imagesByKey[key] ?? const [];
      if (jsonGroup.isEmpty || jsonGroup.length != imageGroup.length) {
        continue;
      }
      for (final (index, json) in jsonGroup.indexed) {
        final image = imageGroup[index];
        usedJson.add(json);
        usedImages.add(image);
        paired.add(_pairedJsonSource(json, image));
      }
    }
  }

  static String _sourceStem(String fileName) =>
      _basenameWithoutExtension(fileName).toLowerCase();

  static String _fileNameFromPath(String path) {
    return path.replaceAll('\\', '/').split('/').last;
  }

  static String? _sequenceKey(String fileName) {
    final matches = RegExp(r'\d+').allMatches(_sourceStem(fileName)).toList();
    if (matches.isEmpty) return null;
    final digits = matches.last.group(0)!.replaceFirst(RegExp(r'^0+'), '');
    return digits.isEmpty ? '0' : digits;
  }

  static String _basenameWithoutExtension(String fileName) {
    final normalized = fileName.replaceAll('\\', '/').split('/').last;
    final dot = normalized.lastIndexOf('.');
    return dot <= 0 ? normalized : normalized.substring(0, dot);
  }

  static String? _replaceExtension(String path, String extension) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0) return null;
    return '${path.substring(0, dot)}$extension';
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static int _naturalCompare(String left, String right) {
    final leftParts = _naturalParts(left);
    final rightParts = _naturalParts(right);
    final count = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < count; index++) {
      final leftPart = leftParts[index];
      final rightPart = rightParts[index];
      if (leftPart is int && rightPart is int) {
        final result = leftPart.compareTo(rightPart);
        if (result != 0) return result;
        continue;
      }
      final result = leftPart.toString().compareTo(rightPart.toString());
      if (result != 0) return result;
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  static List<Object> _naturalParts(String value) {
    final result = <Object>[];
    for (final match in RegExp(r'\d+|\D+').allMatches(value.toLowerCase())) {
      final part = match.group(0)!;
      result.add(int.tryParse(part) ?? part);
    }
    return result;
  }

  Future<List<TokenizerScriptDraftSource>> sourcesFromDirectory(
    Directory directory,
  ) async {
    return (await scanDirectory(directory)).sources;
  }

  Future<TokenizerScriptDirectoryScanResult> scanDirectory(
    Directory directory, {
    bool recursive = true,
  }) async {
    final sources = <TokenizerScriptDraftSource>[];
    final failures = <TokenizerScriptScanFailure>[];
    var totalFilesSeen = 0;
    var supportedFilesSeen = 0;
    var jsonCount = 0;
    var imageCount = 0;

    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      totalFilesSeen++;
      final kind = _sourceKindForPath(entity.path);
      if (kind == null) continue;
      supportedFilesSeen++;
      final stat = await entity.stat();
      try {
        final payload = kind == TokenizerScriptSourceKind.json
            ? jsonDecode(await entity.readAsString())
            : await _imageMetadataPayload(entity);
        sources.add(
          TokenizerScriptDraftSource(
            fileName: entity.uri.pathSegments.last,
            path: entity.path,
            kind: kind,
            payload: payload,
            modifiedAt: stat.modified,
          ),
        );
        if (kind == TokenizerScriptSourceKind.json) {
          jsonCount++;
        } else {
          imageCount++;
        }
      } catch (error) {
        failures.add(
          TokenizerScriptScanFailure(
            fileName: entity.uri.pathSegments.last,
            path: entity.path,
            error: error.toString(),
          ),
        );
      }
    }
    sources.sort(
      (left, right) => _naturalCompare(left.fileName, right.fileName),
    );
    failures.sort(
      (left, right) => _naturalCompare(left.fileName, right.fileName),
    );
    return TokenizerScriptDirectoryScanResult(
      sources: sources,
      failures: failures,
      totalFilesSeen: totalFilesSeen,
      supportedFilesSeen: supportedFilesSeen,
      jsonCount: jsonCount,
      imageCount: imageCount,
    );
  }

  static TokenizerScriptSourceKind? _sourceKindForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.json')) {
      return TokenizerScriptSourceKind.json;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return TokenizerScriptSourceKind.image;
    }
    return null;
  }

  dynamic _payloadForParsing(TokenizerScriptDraftSource source) {
    if (source.kind != TokenizerScriptSourceKind.image) {
      return source.payload;
    }
    if (source.payload is Map) {
      final metadata = _map(source.payload);
      return _decodedImageMetadata(metadata) ??
          (metadata.isEmpty ? {'Source': source.fileName} : metadata);
    }
    if (source.payload is! Uint8List) {
      return source.payload;
    }
    final bytes = source.payload as Uint8List;
    if (!source.fileName.toLowerCase().endsWith('.png')) {
      return {'Source': source.fileName};
    }
    final metadata = _extractPngTextChunks(bytes);
    if (metadata.isEmpty) {
      return {'Source': source.fileName};
    }
    return _decodedImageMetadata(metadata) ?? metadata;
  }

  static Future<Map<String, dynamic>> _imageMetadataPayload(File file) async {
    final fileName = file.uri.pathSegments.last;
    if (!file.path.toLowerCase().endsWith('.png')) {
      return {'Source': fileName};
    }
    final metadata = _extractPngTextChunks(await file.readAsBytes());
    return metadata.isEmpty ? {'Source': fileName} : metadata;
  }

  static Map<String, dynamic>? _decodedImageMetadata(
    Map<String, dynamic> metadata,
  ) {
    for (final key in const ['Comment', 'Description', 'fullContent']) {
      final value = metadata[key];
      if (value is! String) continue;
      final decoded = _tryDecodeMap(value);
      if (decoded != null) return decoded;
    }
    return null;
  }

  static Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? _map(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic> _extractPngTextChunks(Uint8List bytes) {
    final metadata = <String, dynamic>{};
    if (bytes.length < 8) return metadata;
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0, Endian.big);
      final typeStart = offset + 4;
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      final nextOffset = dataEnd + 4;
      if (dataEnd > bytes.length || nextOffset > bytes.length) break;
      final name = ascii.decode(
        bytes.sublist(typeStart, dataStart),
        allowInvalid: true,
      );
      final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
      final entry = switch (name) {
        'tEXt' => _parseTextChunk(data),
        'iTXt' => _parseInternationalTextChunk(data),
        'zTXt' => _parseCompressedTextChunk(data),
        _ => null,
      };
      if (entry != null) {
        metadata[entry.key] = entry.value;
      }
      offset = nextOffset;
    }
    return metadata;
  }

  static MapEntry<String, String>? _parseTextChunk(Uint8List data) {
    final separator = data.indexOf(0);
    if (separator <= 0) return null;
    return MapEntry(
      utf8.decode(data.sublist(0, separator), allowMalformed: true),
      utf8.decode(data.sublist(separator + 1), allowMalformed: true),
    );
  }

  static MapEntry<String, String>? _parseCompressedTextChunk(Uint8List data) {
    final separator = data.indexOf(0);
    if (separator <= 0 || separator + 2 > data.length) return null;
    if (data[separator + 1] != 0) return null;
    final inflated = ZLibCodec().decode(data.sublist(separator + 2));
    return MapEntry(
      utf8.decode(data.sublist(0, separator), allowMalformed: true),
      utf8.decode(inflated, allowMalformed: true),
    );
  }

  static MapEntry<String, String>? _parseInternationalTextChunk(
    Uint8List data,
  ) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0 || keywordEnd + 5 > data.length) return null;
    final keyword = utf8.decode(
      data.sublist(0, keywordEnd),
      allowMalformed: true,
    );
    var cursor = keywordEnd + 1;
    final compressionFlag = data[cursor++];
    final compressionMethod = data[cursor++];
    if (compressionFlag != 0 && compressionMethod != 0) return null;

    final languageEnd = data.indexOf(0, cursor);
    if (languageEnd < 0) return null;
    cursor = languageEnd + 1;
    final translatedEnd = data.indexOf(0, cursor);
    if (translatedEnd < 0) return null;
    cursor = translatedEnd + 1;

    final textBytes = data.sublist(cursor);
    final text = compressionFlag == 0
        ? utf8.decode(textBytes, allowMalformed: true)
        : utf8.decode(ZLibCodec().decode(textBytes), allowMalformed: true);
    return MapEntry(keyword, text);
  }

  Future<TokenizerScript> _refreshSourceExistence(
    TokenizerScript script,
  ) async {
    final existsByFileId = <String, bool>{};
    for (final sourceFile in script.sourceFiles) {
      existsByFileId[sourceFile.fileId] = await _sourcePathExists(sourceFile);
    }

    final sourceFiles = [
      for (final sourceFile in script.sourceFiles)
        _sourceFileWithExists(
          sourceFile,
          existsByFileId[sourceFile.fileId] ?? sourceFile.exists,
        ),
    ];
    final tasks = [
      for (final task in script.imageTasks)
        _taskWithSourceFile(
          task,
          _sourceFileWithExists(
            task.sourceFile,
            existsByFileId[task.sourceFile.fileId] ??
                await _sourcePathExists(task.sourceFile),
          ),
        ),
    ];
    return script.copyWith(sourceFiles: sourceFiles, imageTasks: tasks);
  }

  Future<bool> _sourcePathExists(TokenizerSourceFile sourceFile) async {
    if (sourceFile.path.trim().isEmpty ||
        sourceFile.path.startsWith('demo://')) {
      return sourceFile.exists;
    }
    return File(sourceFile.path).exists();
  }

  static TokenizerSourceFile _sourceFileWithExists(
    TokenizerSourceFile sourceFile,
    bool exists,
  ) {
    return TokenizerSourceFile(
      fileId: sourceFile.fileId,
      fileName: sourceFile.fileName,
      path: sourceFile.path,
      kind: sourceFile.kind,
      defaultImagePath: sourceFile.defaultImagePath,
      modifiedAt: sourceFile.modifiedAt,
      hash: sourceFile.hash,
      exists: exists,
    );
  }

  static TokenizerImageTask _taskWithSourceFile(
    TokenizerImageTask task,
    TokenizerSourceFile sourceFile,
  ) {
    return TokenizerImageTask(
      taskId: task.taskId,
      sourceFile: sourceFile,
      parseStatus: task.parseStatus,
      originalPrompt: task.originalPrompt,
      promptMode: task.promptMode,
      parsedPrompt: task.parsedPrompt,
      finalPrompt: task.finalPrompt,
      artistEvidence: task.artistEvidence,
      characterSlotMatches: task.characterSlotMatches,
      resolution: task.resolution,
      coords: task.coords,
      generationParams: task.generationParams,
      confidence: task.confidence,
      warnings: task.warnings,
      reviewStatus: task.reviewStatus,
      placeholderMappings: task.placeholderMappings,
      styleStageRefs: task.styleStageRefs,
      details: task.details,
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

String _string(dynamic value, String fallback) {
  if (value is String && value.trim().isNotEmpty) return value;
  return fallback;
}

class _TokenizerPairedDraftSource {
  final TokenizerScriptDraftSource source;
  final String defaultImagePath;

  const _TokenizerPairedDraftSource({
    required this.source,
    required this.defaultImagePath,
  });
}

class _ImageAttachmentMetadata {
  final String? prompt;
  final Map<String, dynamic> payload;
  final String sourceFileName;

  const _ImageAttachmentMetadata({
    required this.prompt,
    required this.payload,
    required this.sourceFileName,
  });
}

class _IdentityAccumulator {
  final String identityId;
  final String displayName;
  final List<String> explicitNames;
  final Set<String> evidenceTags = {};
  final Set<String> slotsSeen = {};

  _IdentityAccumulator({
    required this.identityId,
    required this.displayName,
    required this.explicitNames,
  });

  String get placeholder => '[$displayName]';

  TokenizerCharacterIdentity toIdentity() {
    return TokenizerCharacterIdentity(
      identityId: identityId,
      displayName: displayName,
      placeholder: placeholder,
      explicitNames: explicitNames,
      evidenceTags: evidenceTags.toList(growable: false),
      slotsSeen: slotsSeen.toList(growable: false),
    );
  }
}
