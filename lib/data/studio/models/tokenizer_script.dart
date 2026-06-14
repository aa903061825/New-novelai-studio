enum TokenizerScriptSourceMode { auto, image, json }

enum TokenizerScriptStatus {
  scanning,
  parsed,
  needsReview,
  ready,
  sent,
  archived,
}

enum TokenizerScriptSourceKind { image, json }

enum TokenizerScriptPromptMode { tag, naturalLanguage, mixed }

enum TokenizerTaskReviewStatus {
  auto,
  needsReview,
  confirmed,
  adjusted,
  failed
}

class TokenizerScript {
  static const artistPlaceholder = '[画师串]';

  final String scriptId;
  final String name;
  final String sourceFolder;
  final TokenizerScriptSourceMode sourceMode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TokenizerScriptStatus status;
  final List<TokenizerSourceFile> sourceFiles;
  final List<String> sampleFileIds;
  final String globalArtistPlaceholder;
  final List<TokenizerCharacterIdentity> characterIdentities;
  final List<TokenizerStyleStage> styleStages;
  final List<TokenizerKnowledgeCandidate> knowledgeCandidates;
  final List<TokenizerImageTask> imageTasks;
  final List<TokenizerScriptImageAttachment> imageAttachments;
  final List<String> categoryNames;
  final Map<String, String> exhibitionVersionLabels;
  final String? exhibitionCoverItemId;
  final Map<String, dynamic> pipelineExportConfig;
  final Map<String, dynamic> legacyExportConfig;
  final Map<String, dynamic> knowledgeSnapshot;
  final Map<String, dynamic> exportPolicy;
  final List<TokenizerSendRecord> sendRecords;

  const TokenizerScript({
    required this.scriptId,
    required this.name,
    required this.sourceFolder,
    required this.sourceMode,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.sourceFiles,
    required this.sampleFileIds,
    this.globalArtistPlaceholder = artistPlaceholder,
    required this.characterIdentities,
    required this.styleStages,
    required this.knowledgeCandidates,
    required this.imageTasks,
    this.imageAttachments = const [],
    this.categoryNames = const [],
    this.exhibitionVersionLabels = const {},
    this.exhibitionCoverItemId,
    this.pipelineExportConfig = const {},
    this.legacyExportConfig = const {},
    this.knowledgeSnapshot = const {},
    this.exportPolicy = const {'includeSourceFiles': false},
    this.sendRecords = const [],
  });

  int get parsedCount => imageTasks
      .where((task) => task.reviewStatus != TokenizerTaskReviewStatus.failed)
      .length;

  int get needsReviewCount => imageTasks
      .where(
          (task) => task.reviewStatus == TokenizerTaskReviewStatus.needsReview)
      .length;

  int get confirmedCount => imageTasks
      .where((task) =>
          task.reviewStatus == TokenizerTaskReviewStatus.confirmed ||
          task.reviewStatus == TokenizerTaskReviewStatus.adjusted)
      .length;

  bool get hasArtistStack =>
      imageTasks.any((task) => task.artistEvidence.isNotEmpty);

  TokenizerScript copyWith({
    String? scriptId,
    String? name,
    String? sourceFolder,
    TokenizerScriptSourceMode? sourceMode,
    DateTime? createdAt,
    DateTime? updatedAt,
    TokenizerScriptStatus? status,
    List<TokenizerSourceFile>? sourceFiles,
    List<String>? sampleFileIds,
    String? globalArtistPlaceholder,
    List<TokenizerCharacterIdentity>? characterIdentities,
    List<TokenizerStyleStage>? styleStages,
    List<TokenizerKnowledgeCandidate>? knowledgeCandidates,
    List<TokenizerImageTask>? imageTasks,
    List<TokenizerScriptImageAttachment>? imageAttachments,
    List<String>? categoryNames,
    Map<String, String>? exhibitionVersionLabels,
    String? exhibitionCoverItemId,
    Map<String, dynamic>? pipelineExportConfig,
    Map<String, dynamic>? legacyExportConfig,
    Map<String, dynamic>? knowledgeSnapshot,
    Map<String, dynamic>? exportPolicy,
    List<TokenizerSendRecord>? sendRecords,
  }) {
    return TokenizerScript(
      scriptId: scriptId ?? this.scriptId,
      name: name ?? this.name,
      sourceFolder: sourceFolder ?? this.sourceFolder,
      sourceMode: sourceMode ?? this.sourceMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      sourceFiles: sourceFiles ?? this.sourceFiles,
      sampleFileIds: sampleFileIds ?? this.sampleFileIds,
      globalArtistPlaceholder:
          globalArtistPlaceholder ?? this.globalArtistPlaceholder,
      characterIdentities: characterIdentities ?? this.characterIdentities,
      styleStages: styleStages ?? this.styleStages,
      knowledgeCandidates: knowledgeCandidates ?? this.knowledgeCandidates,
      imageTasks: imageTasks ?? this.imageTasks,
      imageAttachments: imageAttachments ?? this.imageAttachments,
      categoryNames: categoryNames ?? this.categoryNames,
      exhibitionVersionLabels:
          exhibitionVersionLabels ?? this.exhibitionVersionLabels,
      exhibitionCoverItemId:
          exhibitionCoverItemId ?? this.exhibitionCoverItemId,
      pipelineExportConfig: pipelineExportConfig ?? this.pipelineExportConfig,
      legacyExportConfig: legacyExportConfig ?? this.legacyExportConfig,
      knowledgeSnapshot: knowledgeSnapshot ?? this.knowledgeSnapshot,
      exportPolicy: exportPolicy ?? this.exportPolicy,
      sendRecords: sendRecords ?? this.sendRecords,
    );
  }

  factory TokenizerScript.fromJson(Map<String, dynamic> json) {
    return TokenizerScript(
      scriptId: _string(json['scriptId'], 'script'),
      name: _string(json['name'], '未命名剧本'),
      sourceFolder: _string(json['sourceFolder'], ''),
      sourceMode: _enumValue(
        TokenizerScriptSourceMode.values,
        json['sourceMode'],
        TokenizerScriptSourceMode.auto,
      ),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      status: _enumValue(
        TokenizerScriptStatus.values,
        json['status'],
        TokenizerScriptStatus.needsReview,
      ),
      sourceFiles: _list(json['sourceFiles'], TokenizerSourceFile.fromJson),
      sampleFileIds: _stringList(json['sampleFileIds']),
      globalArtistPlaceholder: _string(
        json['globalArtistPlaceholder'],
        artistPlaceholder,
      ),
      characterIdentities: _list(
        json['characterIdentities'],
        TokenizerCharacterIdentity.fromJson,
      ),
      styleStages: _list(json['styleStages'], TokenizerStyleStage.fromJson),
      knowledgeCandidates: _list(
        json['knowledgeCandidates'],
        TokenizerKnowledgeCandidate.fromJson,
      ),
      imageTasks: _list(json['imageTasks'], TokenizerImageTask.fromJson),
      imageAttachments: _list(
        json['imageAttachments'],
        TokenizerScriptImageAttachment.fromJson,
      ),
      categoryNames: _stringList(json['categoryNames']),
      exhibitionVersionLabels: _stringMap(json['exhibitionVersionLabels']),
      exhibitionCoverItemId: _nullableString(json['exhibitionCoverItemId']),
      pipelineExportConfig: _map(json['pipelineExportConfig']),
      legacyExportConfig: _map(json['legacyExportConfig']),
      knowledgeSnapshot: _map(json['knowledgeSnapshot']),
      exportPolicy: _map(json['exportPolicy']),
      sendRecords: _list(json['sendRecords'], TokenizerSendRecord.fromJson),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scriptId': scriptId,
      'name': name,
      'sourceFolder': sourceFolder,
      'sourceMode': sourceMode.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status.name,
      'sourceFiles': sourceFiles.map((file) => file.toJson()).toList(),
      'sampleFileIds': sampleFileIds,
      'globalArtistPlaceholder': globalArtistPlaceholder,
      'characterIdentities':
          characterIdentities.map((identity) => identity.toJson()).toList(),
      'styleStages': styleStages.map((stage) => stage.toJson()).toList(),
      'knowledgeCandidates':
          knowledgeCandidates.map((candidate) => candidate.toJson()).toList(),
      'imageTasks': imageTasks.map((task) => task.toJson()).toList(),
      'imageAttachments':
          imageAttachments.map((attachment) => attachment.toJson()).toList(),
      if (categoryNames.isNotEmpty) 'categoryNames': categoryNames,
      if (exhibitionVersionLabels.isNotEmpty)
        'exhibitionVersionLabels': exhibitionVersionLabels,
      if (exhibitionCoverItemId?.trim().isNotEmpty == true)
        'exhibitionCoverItemId': exhibitionCoverItemId!.trim(),
      'pipelineExportConfig': pipelineExportConfig,
      'legacyExportConfig': legacyExportConfig,
      'knowledgeSnapshot': knowledgeSnapshot,
      'exportPolicy': exportPolicy,
      'sendRecords': sendRecords.map((record) => record.toJson()).toList(),
    };
  }
}

class TokenizerSourceFile {
  final String fileId;
  final String fileName;
  final String path;
  final TokenizerScriptSourceKind kind;
  final String defaultImagePath;
  final DateTime? modifiedAt;
  final String? hash;
  final bool exists;

  const TokenizerSourceFile({
    required this.fileId,
    required this.fileName,
    required this.path,
    required this.kind,
    this.defaultImagePath = '',
    this.modifiedAt,
    this.hash,
    this.exists = true,
  });

  factory TokenizerSourceFile.fromJson(Map<String, dynamic> json) {
    return TokenizerSourceFile(
      fileId: _string(json['fileId'], ''),
      fileName: _string(json['fileName'], ''),
      path: _string(json['path'], ''),
      kind: _enumValue(
        TokenizerScriptSourceKind.values,
        json['kind'],
        TokenizerScriptSourceKind.json,
      ),
      defaultImagePath: _string(json['defaultImagePath'], ''),
      modifiedAt: _optionalDate(json['modifiedAt']),
      hash: json['hash'] as String?,
      exists: json['exists'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'fileName': fileName,
        'path': path,
        'kind': kind.name,
        if (defaultImagePath.isNotEmpty) 'defaultImagePath': defaultImagePath,
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
        if (hash != null) 'hash': hash,
        'exists': exists,
      };
}

class TokenizerScriptImageAttachment {
  final String attachmentId;
  final String imagePath;
  final String label;
  final String versionId;
  final String versionLabel;
  final int? frameIndex;
  final String? sourceFileName;
  final String prompt;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const TokenizerScriptImageAttachment({
    required this.attachmentId,
    required this.imagePath,
    required this.label,
    this.versionId = '',
    this.versionLabel = '',
    this.frameIndex,
    this.sourceFileName,
    this.prompt = '',
    this.payload = const {},
    required this.createdAt,
  });

  TokenizerScriptImageAttachment copyWith({
    String? attachmentId,
    String? imagePath,
    String? label,
    String? versionId,
    String? versionLabel,
    int? frameIndex,
    String? sourceFileName,
    String? prompt,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
  }) {
    return TokenizerScriptImageAttachment(
      attachmentId: attachmentId ?? this.attachmentId,
      imagePath: imagePath ?? this.imagePath,
      label: label ?? this.label,
      versionId: versionId ?? this.versionId,
      versionLabel: versionLabel ?? this.versionLabel,
      frameIndex: frameIndex ?? this.frameIndex,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      prompt: prompt ?? this.prompt,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory TokenizerScriptImageAttachment.fromJson(Map<String, dynamic> json) {
    return TokenizerScriptImageAttachment(
      attachmentId: _string(json['attachmentId'], ''),
      imagePath: _string(json['imagePath'], ''),
      label: _string(json['label'], 'Image'),
      versionId: _string(json['versionId'], ''),
      versionLabel: _string(json['versionLabel'], ''),
      frameIndex: _optionalInt(json['frameIndex']),
      sourceFileName: json['sourceFileName'] as String?,
      prompt: _string(json['prompt'], ''),
      payload: _map(json['payload']),
      createdAt: _date(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'attachmentId': attachmentId,
        'imagePath': imagePath,
        'label': label,
        if (versionId.isNotEmpty) 'versionId': versionId,
        if (versionLabel.isNotEmpty) 'versionLabel': versionLabel,
        if (frameIndex != null) 'frameIndex': frameIndex,
        if (sourceFileName != null) 'sourceFileName': sourceFileName,
        if (prompt.isNotEmpty) 'prompt': prompt,
        if (payload.isNotEmpty) 'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };
}

class TokenizerImageTask {
  final String taskId;
  final TokenizerSourceFile sourceFile;
  final String parseStatus;
  final String? originalPrompt;
  final TokenizerScriptPromptMode promptMode;
  final String parsedPrompt;
  final String finalPrompt;
  final List<String> artistEvidence;
  final List<String> characterSlotMatches;
  final String? resolution;
  final List<Map<String, num>> coords;
  final Map<String, dynamic> generationParams;
  final double confidence;
  final List<String> warnings;
  final TokenizerTaskReviewStatus reviewStatus;
  final List<TokenizerPlaceholderMapping> placeholderMappings;
  final List<String> styleStageRefs;
  final TokenizerParseDetails details;

  const TokenizerImageTask({
    required this.taskId,
    required this.sourceFile,
    required this.parseStatus,
    this.originalPrompt,
    required this.promptMode,
    required this.parsedPrompt,
    required this.finalPrompt,
    required this.artistEvidence,
    required this.characterSlotMatches,
    this.resolution,
    this.coords = const [],
    this.generationParams = const {},
    required this.confidence,
    this.warnings = const [],
    required this.reviewStatus,
    this.placeholderMappings = const [],
    this.styleStageRefs = const [],
    required this.details,
  });

  factory TokenizerImageTask.fromJson(Map<String, dynamic> json) {
    return TokenizerImageTask(
      taskId: _string(json['taskId'], ''),
      sourceFile: TokenizerSourceFile.fromJson(_map(json['sourceFile'])),
      parseStatus: _string(json['parseStatus'], 'parsed'),
      originalPrompt: json['originalPrompt'] as String?,
      promptMode: _enumValue(
        TokenizerScriptPromptMode.values,
        json['promptMode'],
        TokenizerScriptPromptMode.tag,
      ),
      parsedPrompt: _string(json['parsedPrompt'], ''),
      finalPrompt: _string(json['finalPrompt'], ''),
      artistEvidence: _stringList(json['artistEvidence']),
      characterSlotMatches: _stringList(json['characterSlotMatches']),
      resolution: json['resolution'] as String?,
      coords: _coordList(json['coords']),
      generationParams: _map(json['generationParams']),
      confidence: _double(json['confidence'], 0),
      warnings: _stringList(json['warnings']),
      reviewStatus: _enumValue(
        TokenizerTaskReviewStatus.values,
        json['reviewStatus'],
        TokenizerTaskReviewStatus.needsReview,
      ),
      placeholderMappings: _list(
        json['placeholderMappings'],
        TokenizerPlaceholderMapping.fromJson,
      ),
      styleStageRefs: _stringList(json['styleStageRefs']),
      details: TokenizerParseDetails.fromJson(_map(json['details'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'sourceFile': sourceFile.toJson(),
        'parseStatus': parseStatus,
        if (originalPrompt != null) 'originalPrompt': originalPrompt,
        'promptMode': promptMode.name,
        'parsedPrompt': parsedPrompt,
        'finalPrompt': finalPrompt,
        'artistEvidence': artistEvidence,
        'characterSlotMatches': characterSlotMatches,
        if (resolution != null) 'resolution': resolution,
        'coords': coords,
        'generationParams': generationParams,
        'confidence': confidence,
        'warnings': warnings,
        'reviewStatus': reviewStatus.name,
        'placeholderMappings':
            placeholderMappings.map((mapping) => mapping.toJson()).toList(),
        'styleStageRefs': styleStageRefs,
        'details': details.toJson(),
      };
}

class TokenizerPlaceholderMapping {
  final String placeholder;
  final List<String> originalTags;
  final String category;
  final String? ownerIdentityId;
  final String source;

  const TokenizerPlaceholderMapping({
    required this.placeholder,
    required this.originalTags,
    required this.category,
    this.ownerIdentityId,
    required this.source,
  });

  factory TokenizerPlaceholderMapping.fromJson(Map<String, dynamic> json) {
    return TokenizerPlaceholderMapping(
      placeholder: _string(json['placeholder'], ''),
      originalTags: _stringList(json['originalTags']),
      category: _string(json['category'], ''),
      ownerIdentityId: json['ownerIdentityId'] as String?,
      source: _string(json['source'], 'system'),
    );
  }

  Map<String, dynamic> toJson() => {
        'placeholder': placeholder,
        'originalTags': originalTags,
        'category': category,
        if (ownerIdentityId != null) 'ownerIdentityId': ownerIdentityId,
        'source': source,
      };
}

class TokenizerCharacterIdentity {
  final String identityId;
  final String displayName;
  final String placeholder;
  final List<String> explicitNames;
  final List<String> evidenceTags;
  final List<String> slotsSeen;
  final Map<String, List<String>> parts;
  final List<String> styleStages;

  const TokenizerCharacterIdentity({
    required this.identityId,
    required this.displayName,
    required this.placeholder,
    this.explicitNames = const [],
    this.evidenceTags = const [],
    this.slotsSeen = const [],
    this.parts = const {},
    this.styleStages = const [],
  });

  factory TokenizerCharacterIdentity.fromJson(Map<String, dynamic> json) {
    return TokenizerCharacterIdentity(
      identityId: _string(json['identityId'], ''),
      displayName: _string(json['displayName'], ''),
      placeholder: _string(json['placeholder'], ''),
      explicitNames: _stringList(json['explicitNames']),
      evidenceTags: _stringList(json['evidenceTags']),
      slotsSeen: _stringList(json['slotsSeen']),
      parts: _stringListMap(json['parts']),
      styleStages: _stringList(json['styleStages']),
    );
  }

  Map<String, dynamic> toJson() => {
        'identityId': identityId,
        'displayName': displayName,
        'placeholder': placeholder,
        'explicitNames': explicitNames,
        'evidenceTags': evidenceTags,
        'slotsSeen': slotsSeen,
        'parts': parts,
        'styleStages': styleStages,
      };
}

class TokenizerStyleStage {
  final String stageId;
  final String identityId;
  final String name;
  final List<String> taskIds;
  final List<String> evidenceTags;

  const TokenizerStyleStage({
    required this.stageId,
    required this.identityId,
    required this.name,
    this.taskIds = const [],
    this.evidenceTags = const [],
  });

  factory TokenizerStyleStage.fromJson(Map<String, dynamic> json) {
    return TokenizerStyleStage(
      stageId: _string(json['stageId'], ''),
      identityId: _string(json['identityId'], ''),
      name: _string(json['name'], ''),
      taskIds: _stringList(json['taskIds']),
      evidenceTags: _stringList(json['evidenceTags']),
    );
  }

  Map<String, dynamic> toJson() => {
        'stageId': stageId,
        'identityId': identityId,
        'name': name,
        'taskIds': taskIds,
        'evidenceTags': evidenceTags,
      };
}

class TokenizerKnowledgeCandidate {
  final String candidateId;
  final String type;
  final String label;
  final String evidence;
  final bool confirmed;

  const TokenizerKnowledgeCandidate({
    required this.candidateId,
    required this.type,
    required this.label,
    required this.evidence,
    this.confirmed = false,
  });

  factory TokenizerKnowledgeCandidate.fromJson(Map<String, dynamic> json) {
    return TokenizerKnowledgeCandidate(
      candidateId: _string(json['candidateId'], ''),
      type: _string(json['type'], ''),
      label: _string(json['label'], ''),
      evidence: _string(json['evidence'], ''),
      confirmed: json['confirmed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'type': type,
        'label': label,
        'evidence': evidence,
        'confirmed': confirmed,
      };
}

class TokenizerSendRecord {
  final String recordId;
  final DateTime sentAt;
  final String scope;
  final int taskCount;
  final String queueId;

  const TokenizerSendRecord({
    required this.recordId,
    required this.sentAt,
    required this.scope,
    required this.taskCount,
    required this.queueId,
  });

  factory TokenizerSendRecord.fromJson(Map<String, dynamic> json) {
    return TokenizerSendRecord(
      recordId: _string(json['recordId'], ''),
      sentAt: _date(json['sentAt']),
      scope: _string(json['scope'], 'allReady'),
      taskCount: _int(json['taskCount'], 0),
      queueId: _string(json['queueId'], ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'sentAt': sentAt.toIso8601String(),
        'scope': scope,
        'taskCount': taskCount,
        'queueId': queueId,
      };
}

class TokenizerParseDetails {
  final List<String> artistStack;
  final Map<String, TokenizerCharacterDetails> characters;
  final List<String> sceneTags;
  final List<String> naturalLanguageSegments;
  final List<String> warnings;

  const TokenizerParseDetails({
    this.artistStack = const [],
    this.characters = const {},
    this.sceneTags = const [],
    this.naturalLanguageSegments = const [],
    this.warnings = const [],
  });

  factory TokenizerParseDetails.fromJson(Map<String, dynamic> json) {
    final rawCharacters = json['characters'];
    return TokenizerParseDetails(
      artistStack: _stringList(json['artistStack']),
      characters: rawCharacters is Map
          ? rawCharacters.map(
              (key, value) => MapEntry(
                key.toString(),
                TokenizerCharacterDetails.fromJson(_map(value)),
              ),
            )
          : const {},
      sceneTags: _stringList(json['sceneTags']),
      naturalLanguageSegments: _stringList(json['naturalLanguageSegments']),
      warnings: _stringList(json['warnings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'artistStack': artistStack,
        'characters': characters.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'sceneTags': sceneTags,
        'naturalLanguageSegments': naturalLanguageSegments,
        'warnings': warnings,
      };
}

class TokenizerCharacterDetails {
  final List<String> identityTags;
  final List<String> upperBodyTags;
  final List<String> upperClothingTags;
  final List<String> lowerBodyTags;
  final List<String> lowerClothingTags;
  final List<String> actionTags;
  final List<String> untouchedTags;

  const TokenizerCharacterDetails({
    this.identityTags = const [],
    this.upperBodyTags = const [],
    this.upperClothingTags = const [],
    this.lowerBodyTags = const [],
    this.lowerClothingTags = const [],
    this.actionTags = const [],
    this.untouchedTags = const [],
  });

  factory TokenizerCharacterDetails.fromJson(Map<String, dynamic> json) {
    return TokenizerCharacterDetails(
      identityTags: _stringList(json['identityTags']),
      upperBodyTags: _stringList(json['upperBodyTags']),
      upperClothingTags: _stringList(json['upperClothingTags']),
      lowerBodyTags: _stringList(json['lowerBodyTags']),
      lowerClothingTags: _stringList(json['lowerClothingTags']),
      actionTags: _stringList(json['actionTags']),
      untouchedTags: _stringList(json['untouchedTags']),
    );
  }

  Map<String, dynamic> toJson() => {
        'identityTags': identityTags,
        'upperBodyTags': upperBodyTags,
        'upperClothingTags': upperClothingTags,
        'lowerBodyTags': lowerBodyTags,
        'lowerClothingTags': lowerClothingTags,
        'actionTags': actionTags,
        'untouchedTags': untouchedTags,
      };
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return const [];
  return value.map((entry) => fromJson(_map(entry))).toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((entry) => entry.toString()).toList(growable: false);
}

Map<String, String> _stringMap(dynamic value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key.toString().trim().isNotEmpty &&
          entry.value.toString().trim().isNotEmpty)
        entry.key.toString(): entry.value.toString(),
  };
}

Map<String, List<String>> _stringListMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map(
    (key, value) => MapEntry(key.toString(), _stringList(value)),
  );
}

List<Map<String, num>> _coordList(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map)
        {
          for (final entry in item.entries)
            if (entry.value is num) entry.key.toString(): entry.value as num,
        },
  ];
}

T _enumValue<T extends Enum>(List<T> values, dynamic value, T fallback) {
  final name = value?.toString();
  for (final item in values) {
    if (item.name == name) return item;
  }
  return fallback;
}

String _string(dynamic value, String fallback) {
  if (value is String && value.trim().isNotEmpty) return value;
  return fallback;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _int(dynamic value, int fallback) {
  return _optionalInt(value) ?? fallback;
}

int? _optionalInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _double(dynamic value, double fallback) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

DateTime _date(dynamic value) {
  return _optionalDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _optionalDate(dynamic value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
