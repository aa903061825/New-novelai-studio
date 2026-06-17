import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/workbench_document.dart';

enum StudioGalleryOperation {
  generate,
  imageToImage,
  enhance,
  upscale,
  inpaint,
  directorTool,
}

class StudioGalleryLineage {
  final StudioGalleryOperation operation;
  final String? sourceRecordId;
  final String? sourceImagePath;
  final Map<String, dynamic> parameters;

  const StudioGalleryLineage({
    required this.operation,
    this.sourceRecordId,
    this.sourceImagePath,
    this.parameters = const {},
  });

  factory StudioGalleryLineage.fromJson(Map<String, dynamic> json) {
    return StudioGalleryLineage(
      operation: _galleryOperationFromJson(json['operation']),
      sourceRecordId: json['sourceRecordId'] as String?,
      sourceImagePath: json['sourceImagePath'] as String?,
      parameters: _dynamicMap(json['parameters']),
    );
  }

  static StudioGalleryLineage? fromJsonOrNull(dynamic json) {
    if (json == null) return null;
    if (json is! Map) {
      throw const FormatException('Gallery lineage must be an object.');
    }
    return StudioGalleryLineage.fromJson(json.cast<String, dynamic>());
  }

  Map<String, dynamic> toJson() => {
        'operation': operation.name,
        if (sourceRecordId != null) 'sourceRecordId': sourceRecordId,
        if (sourceImagePath != null) 'sourceImagePath': sourceImagePath,
        if (parameters.isNotEmpty) 'parameters': parameters,
      };
}

class StudioGalleryRecord {
  static const currentVersion = 1;

  final String id;
  final DateTime createdAt;
  final String title;
  final String? imagePath;
  final String info;
  final Map<String, dynamic> additionalInfo;
  final StudioRecastProvenance? provenance;
  final StudioGalleryLineage? lineage;
  final WorkbenchDocument document;

  const StudioGalleryRecord({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.imagePath,
    required this.info,
    required this.additionalInfo,
    this.provenance,
    this.lineage,
    required this.document,
  });

  factory StudioGalleryRecord.fromJson(Map<String, dynamic> json) {
    final documentJson = json['document'];
    if (documentJson is! Map) {
      throw const FormatException('Gallery record document is missing.');
    }

    final additionalInfo = _dynamicMap(json['additionalInfo']);
    return StudioGalleryRecord(
      id: _stringValue(json['id'], 'id'),
      createdAt: DateTime.parse(_stringValue(json['createdAt'], 'createdAt')),
      title: json['title'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
      info: json['info'] as String? ?? '',
      additionalInfo: additionalInfo,
      provenance: StudioRecastProvenance.fromJsonOrNull(
        json['provenance'] ?? additionalInfo['provenance'],
      ),
      lineage: StudioGalleryLineage.fromJsonOrNull(
        json['lineage'] ?? additionalInfo['lineage'],
      ),
      document: WorkbenchDocument.fromJson(
        documentJson.cast<String, dynamic>(),
      ),
    );
  }

  factory StudioGalleryRecord.fromPayloadConfig({
    required PayloadConfig config,
    required String id,
    required DateTime createdAt,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> additionalInfo = const {},
    StudioRecastProvenance? provenance,
    StudioGalleryLineage? lineage,
  }) {
    final document = WorkbenchDocument.fromPayloadConfig(config);
    return StudioGalleryRecord(
      id: id,
      createdAt: createdAt,
      title: title ?? _defaultTitle(config),
      imagePath: imagePath,
      info: info ?? config.overridePrompt,
      additionalInfo: _withProvenance(additionalInfo, provenance),
      provenance: provenance,
      lineage: lineage,
      document: document,
    );
  }

  factory StudioGalleryRecord.fromRecastPayload({
    required Map<String, dynamic> payload,
    required String id,
    required DateTime createdAt,
    required String title,
    required String imagePath,
    required String info,
    required StudioRecastProvenance provenance,
    Map<String, dynamic> additionalInfo = const {},
    StudioGalleryLineage? lineage,
  }) {
    return StudioGalleryRecord(
      id: id,
      createdAt: createdAt,
      title: title,
      imagePath: imagePath,
      info: info,
      additionalInfo: _withProvenance(additionalInfo, provenance),
      provenance: provenance,
      lineage: lineage,
      document: documentFromNaiPayload(payload),
    );
  }

  static WorkbenchDocument documentFromNaiPayload(
    Map<String, dynamic> payload,
  ) {
    return WorkbenchDocument.fromPayloadJson(
      _workbenchPayloadFromNaiPayload(payload),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': currentVersion,
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'title': title,
      if (imagePath != null) 'imagePath': imagePath,
      'info': info,
      'additionalInfo': additionalInfo,
      if (provenance != null) 'provenance': provenance!.toJson(),
      if (lineage != null) 'lineage': lineage!.toJson(),
      'document': document.toJson(),
    };
  }

  void restoreTo(PayloadConfig target) {
    document.applyTo(target);
  }
}

class StudioRecastProvenance {
  final String? scriptId;
  final String? scriptName;
  final String? scriptPath;
  final String? recastRunId;
  final String productionPlanId;
  final String productionPlanFingerprint;
  final String taskId;
  final int? frameIndex;
  final String? sourceFileName;
  final String payloadFingerprint;
  final String mappingConfigFingerprint;
  final String outputImagePath;

  const StudioRecastProvenance({
    this.scriptId,
    this.scriptName,
    this.scriptPath,
    this.recastRunId,
    required this.productionPlanId,
    required this.productionPlanFingerprint,
    required this.taskId,
    this.frameIndex,
    this.sourceFileName,
    required this.payloadFingerprint,
    required this.mappingConfigFingerprint,
    required this.outputImagePath,
  });

  factory StudioRecastProvenance.fromProductionTask({
    required ProductionPlan plan,
    required ProductionTask task,
    required String outputImagePath,
  }) {
    return StudioRecastProvenance(
      scriptId: task.source.scriptId,
      scriptName: task.source.scriptName,
      scriptPath: task.source.scriptPath,
      recastRunId: task.source.recastRunId,
      productionPlanId: plan.id,
      productionPlanFingerprint: plan.planFingerprint,
      taskId: task.id,
      frameIndex: task.source.frameIndex,
      sourceFileName: task.source.sourceFileName,
      payloadFingerprint: task.payloadFingerprint,
      mappingConfigFingerprint:
          task.source.mappingConfigFingerprint ?? plan.planFingerprint,
      outputImagePath: outputImagePath,
    );
  }

  static StudioRecastProvenance? fromJsonOrNull(dynamic json) {
    if (json == null) return null;
    if (json is! Map) {
      throw const FormatException('Gallery provenance must be an object.');
    }
    final map = json.cast<String, dynamic>();
    return StudioRecastProvenance(
      scriptId: map['scriptId'] as String?,
      scriptName: map['scriptName'] as String?,
      scriptPath: map['scriptPath'] as String?,
      recastRunId: map['recastRunId'] as String?,
      productionPlanId: _stringValue(
        map['productionPlanId'],
        'provenance.productionPlanId',
      ),
      productionPlanFingerprint: _stringValue(
        map['productionPlanFingerprint'],
        'provenance.productionPlanFingerprint',
      ),
      taskId: _stringValue(map['taskId'], 'provenance.taskId'),
      frameIndex: map['frameIndex'] as int?,
      sourceFileName: map['sourceFileName'] as String?,
      payloadFingerprint: _stringValue(
        map['payloadFingerprint'],
        'provenance.payloadFingerprint',
      ),
      mappingConfigFingerprint: _stringValue(
        map['mappingConfigFingerprint'],
        'provenance.mappingConfigFingerprint',
      ),
      outputImagePath: _stringValue(
        map['outputImagePath'],
        'provenance.outputImagePath',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (scriptId != null) 'scriptId': scriptId,
        if (scriptName != null) 'scriptName': scriptName,
        if (scriptPath != null) 'scriptPath': scriptPath,
        if (recastRunId != null) 'recastRunId': recastRunId,
        'productionPlanId': productionPlanId,
        'productionPlanFingerprint': productionPlanFingerprint,
        'taskId': taskId,
        if (frameIndex != null) 'frameIndex': frameIndex,
        if (sourceFileName != null) 'sourceFileName': sourceFileName,
        'payloadFingerprint': payloadFingerprint,
        'mappingConfigFingerprint': mappingConfigFingerprint,
        'outputImagePath': outputImagePath,
      };
}

String _defaultTitle(PayloadConfig config) {
  final prompt = config.overridePrompt.trim();
  if (prompt.isEmpty) {
    return '未命名记录';
  }
  if (prompt.length <= 32) {
    return prompt;
  }
  return '${prompt.substring(0, 32)}...';
}

String _stringValue(dynamic value, String field) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Gallery record $field is missing.');
}

Map<String, dynamic> _dynamicMap(dynamic value) {
  if (value == null) {
    return const {};
  }
  if (value is! Map) {
    throw const FormatException('Gallery record metadata must be an object.');
  }
  return Map.unmodifiable(value.cast<String, dynamic>());
}

Map<String, dynamic> _withProvenance(
  Map<String, dynamic> additionalInfo,
  StudioRecastProvenance? provenance,
) {
  return Map.unmodifiable({
    ...additionalInfo,
    if (provenance != null) 'provenance': provenance.toJson(),
  });
}

StudioGalleryOperation _galleryOperationFromJson(dynamic value) {
  if (value is String) {
    for (final operation in StudioGalleryOperation.values) {
      if (operation.name == value) {
        return operation;
      }
    }
  }
  return StudioGalleryOperation.generate;
}

Map<String, dynamic> _workbenchPayloadFromNaiPayload(
  Map<String, dynamic> payload,
) {
  final input = payload['input'] as String? ?? '';
  final parameters = payload['parameters'];
  final paramConfig = payload['param_config'];
  final parameterMap = parameters is Map
      ? parameters.cast<String, dynamic>()
      : paramConfig is Map
          ? paramConfig.cast<String, dynamic>()
          : const <String, dynamic>{};
  final promptConfig = payload['prompt_config'];
  final characterConfig = payload['character_config'];
  final savedConfig = payload['saved_config'];
  final v4PromptRows = _v4PromptRowsFromParameters(parameterMap);
  return {
    'prompt_config': promptConfig is Map
        ? promptConfig.cast<String, dynamic>()
        : _promptConfigJson(v4PromptRows),
    'character_config': characterConfig is List ? characterConfig : <Object>[],
    'saved_config': savedConfig is List ? savedConfig : <Object>[],
    'param_config': parameterMap,
    'override_prompt': input,
    'use_override_prompt': true,
    'use_character_prompt_with_override': false,
  };
}

Map<String, dynamic> _promptConfigJson(List<String> rows) {
  return {
    'selectionMethod': 'all',
    'shuffled': false,
    'prob': 0.0,
    'num': 1,
    'randomBracketsUpper': 0,
    'randomBracketsLower': 0,
    'type': 'str',
    'comment': 'Recast v4 prompt',
    'filter': '',
    'strs': rows,
    'prompts': <Object>[],
    'enabled': true,
  };
}

List<String> _v4PromptRowsFromParameters(Map<String, dynamic> parameters) {
  final prompt = parameters['v4_prompt'];
  if (prompt is! Map) return const [];
  final captionJson = prompt['caption'];
  if (captionJson is! Map) return const [];
  final caption = captionJson.cast<dynamic, dynamic>();
  final rows = <String>[
    if (_optionalString(caption['base_caption']) case final base?) base,
    if (_optionalString(caption['baseCaption']) case final base?) base,
    if (_optionalString(caption['prompt']) case final base?) base,
  ];
  final charCaptions = caption['char_captions'];
  if (charCaptions is List) {
    for (final entry in charCaptions) {
      if (entry is! Map) continue;
      final charCaption = _optionalString(entry['char_caption']);
      if (charCaption != null) rows.add(charCaption);
    }
  }
  return List.unmodifiable(rows);
}

String? _optionalString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}
