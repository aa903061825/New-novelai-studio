import 'dart:convert';

enum ProductionTaskType { scriptRecastFrame, manualSingleFrame }

enum ProductionTaskStatus { queued, running, completed, failed, skipped }

class ProductionTaskSource {
  final String? scriptId;
  final String? scriptName;
  final String? scriptPath;
  final String? recastRunId;
  final String? mappingConfigFingerprint;
  final int? frameIndex;
  final String? sourceFileName;

  const ProductionTaskSource({
    this.scriptId,
    this.scriptName,
    this.scriptPath,
    this.recastRunId,
    this.mappingConfigFingerprint,
    this.frameIndex,
    this.sourceFileName,
  });

  factory ProductionTaskSource.fromJson(dynamic json) {
    if (json == null) {
      return const ProductionTaskSource();
    }
    final map = _asMap(json, 'production task source');
    return ProductionTaskSource(
      scriptId: _optionalString(map['scriptId'], 'source.scriptId'),
      scriptName: _optionalString(map['scriptName'], 'source.scriptName'),
      scriptPath: _optionalString(map['scriptPath'], 'source.scriptPath'),
      recastRunId: _optionalString(map['recastRunId'], 'source.recastRunId'),
      mappingConfigFingerprint: _optionalString(
        map['mappingConfigFingerprint'],
        'source.mappingConfigFingerprint',
      ),
      frameIndex: _optionalInt(map['frameIndex'], 'source.frameIndex'),
      sourceFileName:
          _optionalString(map['sourceFileName'], 'source.sourceFileName'),
    );
  }

  Map<String, dynamic> toJson() => {
        if (scriptId != null) 'scriptId': scriptId,
        if (scriptName != null) 'scriptName': scriptName,
        if (scriptPath != null) 'scriptPath': scriptPath,
        if (recastRunId != null) 'recastRunId': recastRunId,
        if (mappingConfigFingerprint != null)
          'mappingConfigFingerprint': mappingConfigFingerprint,
        if (frameIndex != null) 'frameIndex': frameIndex,
        if (sourceFileName != null) 'sourceFileName': sourceFileName,
      };
}

class ProductionTask {
  final String id;
  final String planId;
  final ProductionTaskType taskType;
  final String title;
  final ProductionTaskSource source;
  final Map<String, dynamic> payload;
  final String payloadFingerprint;
  final String? suggestedFileName;
  final ProductionTaskStatus status;
  final int attempts;
  final String? outputImagePath;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? rating;
  final DateTime? ratedAt;

  ProductionTask({
    required this.id,
    required this.planId,
    required this.taskType,
    required this.title,
    required Map<String, dynamic> payload,
    String? payloadFingerprint,
    this.source = const ProductionTaskSource(),
    this.suggestedFileName,
    this.status = ProductionTaskStatus.queued,
    this.attempts = 0,
    this.outputImagePath,
    this.error,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.rating,
    this.ratedAt,
  })  : payload = _immutableMap(payload),
        payloadFingerprint =
            payloadFingerprint ?? fingerprintJson(_canonicalJson(payload));

  factory ProductionTask.scriptRecastFrame({
    required String id,
    required String planId,
    required String title,
    required String scriptId,
    String? scriptName,
    String? scriptPath,
    required String recastRunId,
    String? mappingConfigFingerprint,
    required int frameIndex,
    required String sourceFileName,
    required Map<String, dynamic> payload,
    String? payloadFingerprint,
    String? suggestedFileName,
    ProductionTaskStatus status = ProductionTaskStatus.queued,
    int attempts = 0,
    String? outputImagePath,
    String? error,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? rating,
    DateTime? ratedAt,
  }) {
    return ProductionTask(
      id: id,
      planId: planId,
      taskType: ProductionTaskType.scriptRecastFrame,
      title: title,
      source: ProductionTaskSource(
        scriptId: scriptId,
        scriptName: scriptName,
        scriptPath: scriptPath,
        recastRunId: recastRunId,
        mappingConfigFingerprint: mappingConfigFingerprint,
        frameIndex: frameIndex,
        sourceFileName: sourceFileName,
      ),
      payload: payload,
      payloadFingerprint: payloadFingerprint,
      suggestedFileName: suggestedFileName,
      status: status,
      attempts: attempts,
      outputImagePath: outputImagePath,
      error: error,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      rating: rating,
      ratedAt: ratedAt,
    );
  }

  factory ProductionTask.manualSingleFrame({
    required String id,
    required String planId,
    required String title,
    required Map<String, dynamic> payload,
    String? suggestedFileName,
    ProductionTaskStatus status = ProductionTaskStatus.queued,
    int attempts = 0,
    String? outputImagePath,
    String? error,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? rating,
    DateTime? ratedAt,
  }) {
    return ProductionTask(
      id: id,
      planId: planId,
      taskType: ProductionTaskType.manualSingleFrame,
      title: title,
      payload: payload,
      suggestedFileName: suggestedFileName,
      status: status,
      attempts: attempts,
      outputImagePath: outputImagePath,
      error: error,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      rating: rating,
      ratedAt: ratedAt,
    );
  }

  ProductionTask copyWith({
    String? id,
    String? planId,
    ProductionTaskType? taskType,
    String? title,
    ProductionTaskSource? source,
    Map<String, dynamic>? payload,
    String? payloadFingerprint,
    String? suggestedFileName,
    ProductionTaskStatus? status,
    int? attempts,
    String? outputImagePath,
    String? error,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? rating,
    DateTime? ratedAt,
    bool clearOutputImagePath = false,
    bool clearError = false,
    bool clearStartedAt = false,
    bool clearCompletedAt = false,
    bool clearRating = false,
    bool clearRatedAt = false,
  }) {
    return ProductionTask(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      taskType: taskType ?? this.taskType,
      title: title ?? this.title,
      source: source ?? this.source,
      payload: payload ?? this.payload,
      payloadFingerprint: payloadFingerprint ?? this.payloadFingerprint,
      suggestedFileName: suggestedFileName ?? this.suggestedFileName,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      outputImagePath:
          clearOutputImagePath ? null : outputImagePath ?? this.outputImagePath,
      error: clearError ? null : error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      rating: clearRating ? null : rating ?? this.rating,
      ratedAt: clearRatedAt ? null : ratedAt ?? this.ratedAt,
    );
  }

  factory ProductionTask.fromJson(dynamic json) {
    final map = _asMap(json, 'production task');
    final payload = _dynamicMap(map['payload'], 'productionTask.payload');
    return ProductionTask(
      id: _string(map['id'], 'productionTask.id'),
      planId: _string(map['planId'], 'productionTask.planId'),
      taskType: _taskType(map['taskType']),
      title: _string(map['title'], 'productionTask.title'),
      source: ProductionTaskSource.fromJson(map['source']),
      payload: payload,
      payloadFingerprint: _optionalString(
        map['payloadFingerprint'],
        'productionTask.payloadFingerprint',
      ),
      suggestedFileName: _optionalString(
        map['suggestedFileName'],
        'productionTask.suggestedFileName',
      ),
      status: _taskStatus(map['status']),
      attempts: _intValue(map['attempts'], 'productionTask.attempts'),
      outputImagePath: _optionalString(
        map['outputImagePath'],
        'productionTask.outputImagePath',
      ),
      error: _optionalString(map['error'], 'productionTask.error'),
      createdAt: _dateTime(map['createdAt'], 'productionTask.createdAt'),
      updatedAt: _dateTime(map['updatedAt'], 'productionTask.updatedAt'),
      startedAt: _optionalDateTime(
        map['startedAt'],
        'productionTask.startedAt',
      ),
      completedAt: _optionalDateTime(
        map['completedAt'],
        'productionTask.completedAt',
      ),
      rating: _optionalInt(map['rating'], 'productionTask.rating'),
      ratedAt: _optionalDateTime(
        map['ratedAt'],
        'productionTask.ratedAt',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'planId': planId,
        'taskType': taskType.name,
        'title': title,
        'source': source.toJson(),
        'payload': payload,
        'payloadFingerprint': payloadFingerprint,
        if (suggestedFileName != null) 'suggestedFileName': suggestedFileName,
        'status': status.name,
        'attempts': attempts,
        if (outputImagePath != null) 'outputImagePath': outputImagePath,
        if (error != null) 'error': error,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (startedAt != null)
          'startedAt': startedAt!.toUtc().toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        if (rating != null) 'rating': rating,
        if (ratedAt != null) 'ratedAt': ratedAt!.toUtc().toIso8601String(),
      };
}

class ProductionPlanExecutionSettings {
  final String model;
  final String sampler;
  final int? steps;
  final double? scale;
  final int? width;
  final int? height;
  final int? seed;
  final bool useOriginalModel;
  final bool useOriginalSize;
  final bool useOriginalSampler;
  final bool useOriginalSteps;
  final bool useOriginalScale;
  final bool useOriginalSeed;
  final int requestIntervalSeconds;
  final int requestIntervalRandomRangeSeconds;
  final int retryCount;
  final bool retryIndefinitely;
  final String outputDirectory;

  const ProductionPlanExecutionSettings({
    this.model = '',
    this.sampler = '',
    this.steps,
    this.scale,
    this.width,
    this.height,
    this.seed = -1,
    this.useOriginalModel = false,
    this.useOriginalSize = false,
    this.useOriginalSampler = false,
    this.useOriginalSteps = false,
    this.useOriginalScale = false,
    this.useOriginalSeed = false,
    this.requestIntervalSeconds = 0,
    this.requestIntervalRandomRangeSeconds = 0,
    this.retryCount = 1,
    this.retryIndefinitely = false,
    this.outputDirectory = '',
  });

  factory ProductionPlanExecutionSettings.fromJson(dynamic json) {
    final map = _asMap(json, 'production plan execution settings');
    return ProductionPlanExecutionSettings(
      model: _optionalString(
            map['model'],
            'productionPlan.executionSettings.model',
          ) ??
          '',
      sampler: _optionalString(
            map['sampler'],
            'productionPlan.executionSettings.sampler',
          ) ??
          '',
      steps: _optionalInt(
        map['steps'],
        'productionPlan.executionSettings.steps',
      ),
      scale: _optionalDouble(
        map['scale'],
        'productionPlan.executionSettings.scale',
      ),
      width: _optionalInt(
        map['width'],
        'productionPlan.executionSettings.width',
      ),
      height: _optionalInt(
        map['height'],
        'productionPlan.executionSettings.height',
      ),
      seed: _optionalInt(
            map['seed'],
            'productionPlan.executionSettings.seed',
          ) ??
          -1,
      useOriginalModel: _boolValue(
        map['useOriginalModel'],
        'productionPlan.executionSettings.useOriginalModel',
      ),
      useOriginalSize: _boolValue(
        map['useOriginalSize'],
        'productionPlan.executionSettings.useOriginalSize',
      ),
      useOriginalSampler: _boolValue(
        map['useOriginalSampler'],
        'productionPlan.executionSettings.useOriginalSampler',
      ),
      useOriginalSteps: _boolValue(
        map['useOriginalSteps'],
        'productionPlan.executionSettings.useOriginalSteps',
      ),
      useOriginalScale: _boolValue(
        map['useOriginalScale'],
        'productionPlan.executionSettings.useOriginalScale',
      ),
      useOriginalSeed: _boolValue(
        map['useOriginalSeed'],
        'productionPlan.executionSettings.useOriginalSeed',
      ),
      requestIntervalSeconds: _optionalInt(
            map['requestIntervalSeconds'],
            'productionPlan.executionSettings.requestIntervalSeconds',
          ) ??
          0,
      requestIntervalRandomRangeSeconds: _optionalInt(
            map['requestIntervalRandomRangeSeconds'],
            'productionPlan.executionSettings.requestIntervalRandomRangeSeconds',
          ) ??
          0,
      retryCount: _optionalInt(
            map['retryCount'],
            'productionPlan.executionSettings.retryCount',
          ) ??
          1,
      retryIndefinitely: _boolValue(
        map['retryIndefinitely'],
        'productionPlan.executionSettings.retryIndefinitely',
      ),
      outputDirectory: _optionalString(
            map['outputDirectory'],
            'productionPlan.executionSettings.outputDirectory',
          ) ??
          '',
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'sampler': sampler,
        'steps': steps,
        'scale': scale,
        'width': width,
        'height': height,
        'seed': seed,
        'useOriginalModel': useOriginalModel,
        'useOriginalSize': useOriginalSize,
        'useOriginalSampler': useOriginalSampler,
        'useOriginalSteps': useOriginalSteps,
        'useOriginalScale': useOriginalScale,
        'useOriginalSeed': useOriginalSeed,
        'requestIntervalSeconds': requestIntervalSeconds,
        'requestIntervalRandomRangeSeconds': requestIntervalRandomRangeSeconds,
        'retryCount': retryCount,
        'retryIndefinitely': retryIndefinitely,
        'outputDirectory': outputDirectory,
      };
}

class ProductionPlan {
  final String id;
  final String name;
  final List<ProductionTask> tasks;
  final String planFingerprint;
  final ProductionPlanExecutionSettings? executionSettings;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductionPlan({
    required this.id,
    required this.name,
    required List<ProductionTask> tasks,
    String? planFingerprint,
    this.executionSettings,
    required this.createdAt,
    required this.updatedAt,
  })  : tasks = List.unmodifiable(tasks),
        planFingerprint = planFingerprint ?? _fingerprintTaskSequence(tasks);

  factory ProductionPlan.fromJson(dynamic json) {
    final map = _asMap(json, 'production plan');
    final tasks = _asList(map['tasks'], 'productionPlan.tasks')
        .map(ProductionTask.fromJson)
        .toList(growable: false);
    return ProductionPlan(
      id: _string(map['id'], 'productionPlan.id'),
      name: _string(map['name'], 'productionPlan.name'),
      tasks: tasks,
      planFingerprint: _optionalString(
        map['planFingerprint'],
        'productionPlan.planFingerprint',
      ),
      executionSettings: map['executionSettings'] == null
          ? null
          : ProductionPlanExecutionSettings.fromJson(
              map['executionSettings'],
            ),
      createdAt: _dateTime(map['createdAt'], 'productionPlan.createdAt'),
      updatedAt: _dateTime(map['updatedAt'], 'productionPlan.updatedAt'),
    );
  }

  ProductionPlan copyWith({
    String? id,
    String? name,
    List<ProductionTask>? tasks,
    String? planFingerprint,
    ProductionPlanExecutionSettings? executionSettings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductionPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      tasks: tasks ?? this.tasks,
      planFingerprint: planFingerprint,
      executionSettings: executionSettings ?? this.executionSettings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
        'planFingerprint': planFingerprint,
        if (executionSettings != null)
          'executionSettings': executionSettings!.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

String fingerprintJson(String canonicalJson) {
  var hash = _fnv64Offset;
  for (final byte in utf8.encode(canonicalJson)) {
    hash ^= BigInt.from(byte);
    hash = (hash * _fnv64Prime) & _fnv64Mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

final BigInt _fnv64Offset = BigInt.parse('cbf29ce484222325', radix: 16);
final BigInt _fnv64Prime = BigInt.parse('100000001b3', radix: 16);
final BigInt _fnv64Mask = BigInt.parse('ffffffffffffffff', radix: 16);

String _fingerprintTaskSequence(List<ProductionTask> tasks) {
  return fingerprintJson(jsonEncode(tasks
      .map((task) => {
            'id': task.id,
            'payloadFingerprint': task.payloadFingerprint,
          })
      .toList(growable: false)));
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => left.key.toString().compareTo(
            right.key.toString(),
          ));
    return {
      for (final entry in entries)
        entry.key.toString(): _canonicalValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> _immutableMap(Map<String, dynamic> value) {
  final mapped = <String, dynamic>{
    for (final entry in value.entries) entry.key: _immutableValue(entry.value),
  };
  return Map<String, dynamic>.unmodifiable(mapped);
}

Object? _immutableValue(Object? value) {
  if (value is Map) {
    final mapped = <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _immutableValue(entry.value),
    };
    return Map<String, dynamic>.unmodifiable(mapped);
  }
  if (value is List) {
    return List.unmodifiable(value.map(_immutableValue));
  }
  return value;
}

Map<String, dynamic> _asMap(dynamic value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be a JSON object.');
  }
  return value.map((key, child) {
    if (key is! String) {
      throw FormatException('$field keys must be strings.');
    }
    return MapEntry(key, child);
  });
}

List<dynamic> _asList(dynamic value, String field) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw FormatException('$field must be a JSON array.');
  }
  return value;
}

Map<String, dynamic> _dynamicMap(dynamic value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be a JSON object.');
  }
  return _immutableMap(_asMap(value, field));
}

String _string(dynamic value, String field) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$field is missing.');
}

String? _optionalString(dynamic value, String field) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('$field must be a string.');
}

int _intValue(dynamic value, String field) {
  if (value is int) {
    return value;
  }
  if (value == null) {
    return 0;
  }
  throw FormatException('$field must be an integer.');
}

int? _optionalInt(dynamic value, String field) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$field must be an integer.');
}

double? _optionalDouble(dynamic value, String field) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('$field must be a number.');
}

bool _boolValue(dynamic value, String field) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$field must be a boolean.');
}

DateTime _dateTime(dynamic value, String field) {
  if (value is String && value.isNotEmpty) {
    return DateTime.parse(value);
  }
  throw FormatException('$field is missing.');
}

DateTime? _optionalDateTime(dynamic value, String field) {
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.parse(value);
  }
  throw FormatException('$field must be a timestamp.');
}

ProductionTaskType _taskType(dynamic value) {
  final name = _string(value, 'productionTask.taskType');
  return ProductionTaskType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => throw FormatException('Unknown production task type $name.'),
  );
}

ProductionTaskStatus _taskStatus(dynamic value) {
  if (value == null) {
    return ProductionTaskStatus.queued;
  }
  final name = _string(value, 'productionTask.status');
  return ProductionTaskStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () =>
        throw FormatException('Unknown production task status $name.'),
  );
}
