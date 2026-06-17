import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';

enum RecastRoleImportance { protagonist, supporting, temporary }

enum RecastRoleCandidateStatus { suggested, confirmed, rejected }

class RecastRoleCandidate {
  final String id;
  final String displayName;
  final RecastRoleImportance importance;
  final List<String> aliases;
  final List<String> evidenceTags;
  final List<int> frameIndexes;
  final double confidence;
  final String? mappedCharacterId;
  final RecastRoleCandidateStatus status;
  final bool confirmed;

  const RecastRoleCandidate({
    required this.id,
    required this.displayName,
    required this.importance,
    this.aliases = const [],
    this.evidenceTags = const [],
    this.frameIndexes = const [],
    this.confidence = 0,
    this.mappedCharacterId,
    RecastRoleCandidateStatus? status,
    bool confirmed = false,
  })  : status = status ??
            (confirmed
                ? RecastRoleCandidateStatus.confirmed
                : RecastRoleCandidateStatus.suggested),
        confirmed = confirmed || status == RecastRoleCandidateStatus.confirmed;

  factory RecastRoleCandidate.fromJson(Map<String, dynamic> json) {
    final status = _candidateStatusFromJson(json);
    return RecastRoleCandidate(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      importance: RecastRoleImportance.values.firstWhere(
        (value) => value.name == json['importance'],
        orElse: () => RecastRoleImportance.temporary,
      ),
      aliases: _stringList(json['aliases']),
      evidenceTags: _stringList(json['evidenceTags']),
      frameIndexes: _intList(json['frameIndexes']),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      mappedCharacterId: json['mappedCharacterId'] as String?,
      status: status,
      confirmed: status == RecastRoleCandidateStatus.confirmed,
    );
  }

  RecastRoleCandidate confirm({String? mappedCharacterId}) {
    return copyWith(
      mappedCharacterId: mappedCharacterId ?? this.mappedCharacterId,
      status: RecastRoleCandidateStatus.confirmed,
      confirmed: true,
    );
  }

  RecastRoleCandidate reject() {
    return copyWith(
      status: RecastRoleCandidateStatus.rejected,
      confirmed: false,
    );
  }

  RecastRoleCandidate rename(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty || trimmed == this.displayName) {
      return this;
    }
    return copyWith(
      displayName: trimmed,
      aliases: _uniqueStrings([...aliases, this.displayName]),
    );
  }

  RecastRoleCandidate mergeWith(
    RecastRoleCandidate other, {
    String? displayName,
  }) {
    final importance = _higherImportance(this.importance, other.importance);
    return copyWith(
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : this.displayName,
      importance: importance,
      aliases: _uniqueStrings([
        ...aliases,
        other.displayName,
        ...other.aliases,
      ]..removeWhere((alias) => alias == this.displayName)),
      evidenceTags: _uniqueStrings([...evidenceTags, ...other.evidenceTags]),
      frameIndexes: _sortedUniqueInts([...frameIndexes, ...other.frameIndexes]),
      confidence: confidence > other.confidence ? confidence : other.confidence,
    );
  }

  RecastRoleCandidate copyWith({
    String? id,
    String? displayName,
    RecastRoleImportance? importance,
    List<String>? aliases,
    List<String>? evidenceTags,
    List<int>? frameIndexes,
    double? confidence,
    Object? mappedCharacterId = _unset,
    RecastRoleCandidateStatus? status,
    bool? confirmed,
  }) {
    final nextStatus = status ?? this.status;
    return RecastRoleCandidate(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      importance: importance ?? this.importance,
      aliases: aliases ?? this.aliases,
      evidenceTags: evidenceTags ?? this.evidenceTags,
      frameIndexes: frameIndexes ?? this.frameIndexes,
      confidence: confidence ?? this.confidence,
      mappedCharacterId: identical(mappedCharacterId, _unset)
          ? this.mappedCharacterId
          : mappedCharacterId as String?,
      status: nextStatus,
      confirmed: confirmed ?? nextStatus == RecastRoleCandidateStatus.confirmed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'importance': importance.name,
        if (aliases.isNotEmpty) 'aliases': aliases,
        if (evidenceTags.isNotEmpty) 'evidenceTags': evidenceTags,
        if (frameIndexes.isNotEmpty) 'frameIndexes': frameIndexes,
        'confidence': confidence,
        if (mappedCharacterId != null) 'mappedCharacterId': mappedCharacterId,
        'status': status.name,
        'confirmed': confirmed,
      };
}

class RecastScriptCache {
  final String scriptId;
  final String scriptName;
  final String sourceRootPath;
  final String sourceFingerprint;
  final String sourceContentFingerprint;
  final DateTime updatedAt;
  final List<RecastRoleCandidate> roleCandidates;
  final RecastMapping mapping;
  final ScriptAiRoleExtraction aiRoleExtraction;
  final List<ScriptAiRoleExtraction> aiRoleExtractionChunks;
  final bool aiRoleExtractionDraftCollapsed;
  final String scriptBlockWords;
  final Map<String, dynamic> knowledgeSnapshot;
  final Map<String, dynamic> scriptSnapshot;

  const RecastScriptCache({
    required this.scriptId,
    required this.scriptName,
    required this.sourceRootPath,
    required this.sourceFingerprint,
    this.sourceContentFingerprint = '',
    required this.updatedAt,
    this.roleCandidates = const [],
    required this.mapping,
    this.aiRoleExtraction = const ScriptAiRoleExtraction(),
    this.aiRoleExtractionChunks = const [],
    this.aiRoleExtractionDraftCollapsed = false,
    this.scriptBlockWords = '',
    this.knowledgeSnapshot = const {},
    this.scriptSnapshot = const {},
  });

  factory RecastScriptCache.fromJson(Map<String, dynamic> json) {
    return RecastScriptCache(
      scriptId: json['scriptId'] as String? ?? '',
      scriptName: json['scriptName'] as String? ?? '',
      sourceRootPath: json['sourceRootPath'] as String? ?? '',
      sourceFingerprint: json['sourceFingerprint'] as String? ?? '',
      sourceContentFingerprint:
          json['sourceContentFingerprint'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      roleCandidates: [
        for (final value in json['roleCandidates'] as List? ?? const [])
          RecastRoleCandidate.fromJson(Map<String, dynamic>.from(value as Map)),
      ],
      mapping: RecastMapping.fromJson(
        Map<String, dynamic>.from(json['mapping'] as Map? ?? const {}),
      ),
      aiRoleExtraction: json['aiRoleExtraction'] is! Map
          ? const ScriptAiRoleExtraction()
          : ScriptAiRoleExtraction.fromJson(
              Map<String, dynamic>.from(json['aiRoleExtraction'] as Map),
            ),
      aiRoleExtractionChunks: [
        for (final value in json['aiRoleExtractionChunks'] as List? ?? const [])
          ScriptAiRoleExtraction.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
      ],
      aiRoleExtractionDraftCollapsed:
          json['aiRoleExtractionDraftCollapsed'] == true,
      scriptBlockWords: json['scriptBlockWords'] as String? ?? '',
      knowledgeSnapshot:
          Map<String, dynamic>.from(json['knowledgeSnapshot'] as Map? ?? {}),
      scriptSnapshot:
          Map<String, dynamic>.from(json['scriptSnapshot'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'scriptId': scriptId,
        'scriptName': scriptName,
        'sourceRootPath': sourceRootPath,
        'sourceFingerprint': sourceFingerprint,
        if (sourceContentFingerprint.trim().isNotEmpty)
          'sourceContentFingerprint': sourceContentFingerprint,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'mapping': mapping.toJson(),
        if (aiRoleExtraction.status != ScriptAiRoleExtractionStatus.idle)
          'aiRoleExtraction': aiRoleExtraction.toJson(),
        if (aiRoleExtractionChunks.isNotEmpty)
          'aiRoleExtractionChunks':
              aiRoleExtractionChunks.map((entry) => entry.toJson()).toList(),
        if (aiRoleExtractionDraftCollapsed)
          'aiRoleExtractionDraftCollapsed': true,
        if (scriptBlockWords.trim().isNotEmpty)
          'scriptBlockWords': scriptBlockWords,
        if (scriptSnapshot.isNotEmpty)
          'scriptSnapshot': stableJsonValue(scriptSnapshot),
      };
}

List<RecastRoleCandidate> confirmedKnowledgeCandidatesFromBase(
  Map<String, dynamic> knowledgeBase,
) {
  final scripts = knowledgeBase['scripts'];
  if (scripts is! Map) {
    return const [];
  }
  final candidates = <RecastRoleCandidate>[];
  for (final scriptEntry in scripts.entries) {
    final scriptId = scriptEntry.key.toString();
    final snapshot = scriptEntry.value;
    if (snapshot is! Map) {
      continue;
    }
    final roles = snapshot['roles'];
    if (roles is! List) {
      continue;
    }
    for (final role in roles) {
      if (role is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(role);
      final displayName = (map['displayName'] as String? ?? '').trim();
      if (displayName.isEmpty) {
        continue;
      }
      candidates.add(
        RecastRoleCandidate(
          id: map['candidateId'] as String? ?? '$scriptId-$displayName',
          displayName: displayName,
          importance: _importanceFromName(map['importance'] as String?),
          aliases: _stringList(map['aliases']),
          evidenceTags: _stringList(map['evidenceTags']),
          frameIndexes: _intList(map['frameIndexes']),
          confidence: 1,
          mappedCharacterId: map['mappedCharacterId'] as String?,
          status: RecastRoleCandidateStatus.confirmed,
          confirmed: true,
        ),
      );
    }
  }
  return List.unmodifiable(candidates);
}

const Object _unset = Object();

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

List<int> _intList(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is num) item.toInt(),
  ];
}

RecastRoleCandidateStatus _candidateStatusFromJson(
  Map<String, dynamic> json,
) {
  final statusName = json['status'];
  if (statusName is String) {
    for (final status in RecastRoleCandidateStatus.values) {
      if (status.name == statusName) {
        return status;
      }
    }
  }
  if (json['confirmed'] == true) {
    return RecastRoleCandidateStatus.confirmed;
  }
  return RecastRoleCandidateStatus.suggested;
}

RecastRoleImportance _higherImportance(
  RecastRoleImportance left,
  RecastRoleImportance right,
) {
  int rank(RecastRoleImportance importance) {
    return switch (importance) {
      RecastRoleImportance.protagonist => 0,
      RecastRoleImportance.supporting => 1,
      RecastRoleImportance.temporary => 2,
    };
  }

  return rank(left) <= rank(right) ? left : right;
}

RecastRoleImportance _importanceFromName(String? name) {
  for (final importance in RecastRoleImportance.values) {
    if (importance.name == name) {
      return importance;
    }
  }
  return RecastRoleImportance.temporary;
}

List<String> _uniqueStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) {
      continue;
    }
    result.add(trimmed);
  }
  return List.unmodifiable(result);
}

List<int> _sortedUniqueInts(Iterable<int> values) {
  final result = values.toSet().toList()..sort();
  return List.unmodifiable(result);
}
