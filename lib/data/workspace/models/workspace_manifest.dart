const Object _copyUnset = Object();

class WorkspaceManifest {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String name;
  final String? currentPromptConfigId;
  final List<WorkspaceMigrationEntry> migrations;

  WorkspaceManifest({
    required this.schemaVersion,
    required this.name,
    this.currentPromptConfigId,
    this.migrations = const [],
  });

  factory WorkspaceManifest.empty({String name = 'Novel Studio'}) {
    return WorkspaceManifest(
      schemaVersion: currentSchemaVersion,
      name: name,
    );
  }

  factory WorkspaceManifest.fromJson(Map<String, dynamic> json) {
    return WorkspaceManifest(
      schemaVersion: json['schemaVersion'] ?? currentSchemaVersion,
      name: json['name'] ?? 'Novel Studio',
      currentPromptConfigId: json['currentPromptConfigId'],
      migrations: _list(json['migrations'], 'migrations')
          .map((entry) => WorkspaceMigrationEntry.fromJson(entry))
          .toList(growable: false),
    );
  }

  WorkspaceManifest copyWith({
    Object? currentPromptConfigId = _copyUnset,
    List<WorkspaceMigrationEntry>? migrations,
  }) {
    return WorkspaceManifest(
      schemaVersion: schemaVersion,
      name: name,
      currentPromptConfigId: identical(currentPromptConfigId, _copyUnset)
          ? this.currentPromptConfigId
          : currentPromptConfigId as String?,
      migrations: migrations ?? this.migrations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'name': name,
      if (currentPromptConfigId != null)
        'currentPromptConfigId': currentPromptConfigId,
      'migrations': migrations.map((entry) => entry.toJson()).toList(),
    };
  }
}

class WorkspaceMigrationEntry {
  final String sourceType;
  final String sourcePath;
  final DateTime importedAt;
  final int importerVersion;
  final Map<String, int> counts;

  WorkspaceMigrationEntry({
    required this.sourceType,
    required this.sourcePath,
    required this.importedAt,
    required this.importerVersion,
    this.counts = const {},
  });

  factory WorkspaceMigrationEntry.fromJson(dynamic json) {
    final map = _map(json, 'migration entry');
    final countsJson = _map(map['counts'], 'migration counts');

    return WorkspaceMigrationEntry(
      sourceType: map['sourceType'] ?? '',
      sourcePath: map['sourcePath'] ?? '',
      importedAt: _dateTime(map['importedAt'], 'migration importedAt'),
      importerVersion: map['importerVersion'] ?? 0,
      counts: countsJson.map((key, value) {
        return MapEntry(
            key, value is int ? value : int.tryParse('$value') ?? 0);
      }),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceType': sourceType,
      'sourcePath': sourcePath,
      'importedAt': importedAt.toUtc().toIso8601String(),
      'importerVersion': importerVersion,
      'counts': counts,
    };
  }
}

Map<String, dynamic> _map(dynamic value, String fieldName) {
  if (value == null) return <String, dynamic>{};
  if (value is! Map) {
    throw FormatException('$fieldName must be a JSON object.');
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$fieldName must use string keys.');
    }
    result[key] = entry.value;
  }
  return result;
}

List<dynamic> _list(dynamic value, String fieldName) {
  if (value == null) return <dynamic>[];
  if (value is List) return value;
  throw FormatException('$fieldName must be a JSON array.');
}

DateTime _dateTime(dynamic value, String fieldName) {
  if (value == null) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  if (value is! String) {
    throw FormatException('$fieldName must be an ISO-8601 date string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$fieldName must be an ISO-8601 date string.');
  }
  return parsed.toUtc();
}
