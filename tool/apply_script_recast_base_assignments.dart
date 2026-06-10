import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final assignmentFiles = await Directory(options.assignmentsDir)
      .list(recursive: true)
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
  assignmentFiles.sort((a, b) => a.path.compareTo(b.path));

  final byScript = <String, List<Map<String, dynamic>>>{};
  for (final file in assignmentFiles) {
    final decoded = jsonDecode(await file.readAsString(encoding: utf8));
    final documents = decoded is List ? decoded : [decoded];
    for (final document in documents) {
      if (document is! Map) continue;
      final map = Map<String, dynamic>.from(document);
      final scriptId = _string(map['script_id'] ?? map['scriptId']).trim();
      if (scriptId.isEmpty) {
        stderr.writeln('SKIP ${file.path}: missing script_id');
        continue;
      }
      byScript.putIfAbsent(scriptId, () => []).add(map);
    }
  }

  final cacheDir = Directory(options.cacheDir);
  final cacheFiles = await cacheDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
  final cacheByScript = <String, File>{};
  for (final file in cacheFiles) {
    final cache = jsonDecode(await file.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    cacheByScript[_string(cache['scriptId'])] = file;
  }

  var changedScripts = 0;
  for (final entry in byScript.entries) {
    final scriptId = entry.key;
    final file = cacheByScript[scriptId];
    if (file == null) {
      stderr.writeln('SKIP $scriptId: cache file not found');
      continue;
    }
    final cache = jsonDecode(await file.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    final summary = _applyDocuments(cache, entry.value);
    if (summary.changed) {
      changedScripts += 1;
      cache['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      if (!options.dryRun) {
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(cache),
          encoding: utf8,
        );
      }
    }
    stdout.writeln(
      '${options.dryRun ? "DRY " : ""}APPLY $scriptId: '
      'changed=${summary.changed} assigned_frames=${summary.assignedFrames} '
      'created_roles=${summary.createdRoles} created_stages=${summary.createdStages} '
      'warnings=${summary.warnings.length}',
    );
    for (final warning in summary.warnings) {
      stderr.writeln('  WARN $scriptId: $warning');
    }
  }

  stdout.writeln(
    '${options.dryRun ? "DRY " : ""}DONE scripts=${byScript.length} '
    'changed_scripts=$changedScripts',
  );
}

_ApplySummary _applyDocuments(
  Map<String, dynamic> cache,
  List<Map<String, dynamic>> documents,
) {
  final extraction = _map(cache['aiRoleExtraction']);
  final roles = _list(extraction['roles']);
  var changed = false;
  var assignedFrames = 0;
  var createdRoles = 0;
  var createdStages = 0;
  final warnings = <String>[];

  for (final document in documents) {
    final assignments = _list(document['assignments']);
    for (final rawAssignment in assignments) {
      final assignment = _map(rawAssignment);
      final frames =
          _intList(assignment['frames'] ?? assignment['frame_indexes']);
      if (frames.isEmpty) {
        continue;
      }

      var role = _findRole(roles, assignment);
      if (role == null) {
        if (assignment['create_role'] != true) {
          warnings.add(
            'role not found for frames ${frames.join(",")}; set create_role=true to create one',
          );
          continue;
        }
        role = _newRole(assignment, frames);
        roles.add(role);
        createdRoles += 1;
        changed = true;
      }

      final roleFrames = _mergeInts(_intList(role['frame_indexes']), frames);
      if (!_sameInts(roleFrames, _intList(role['frame_indexes']))) {
        role['frame_indexes'] = roleFrames;
        changed = true;
      }

      final appearances = _list(role['appearances']);
      var baseAppearance = appearances.cast<Map?>().firstWhere(
            (appearance) =>
                appearance != null &&
                (_isBaseSource(_string(appearance['source_id'])) ||
                    _isBaseSource(_string(appearance['source_kind']))),
            orElse: () => null,
          );
      if (baseAppearance == null) {
        baseAppearance = <String, dynamic>{
          'source_id': 'base',
          'source_kind': 'base',
          'frame_indexes': <int>[],
        };
        appearances.add(baseAppearance);
        role['appearances'] = appearances;
        changed = true;
      }
      final appearanceFrames = _mergeInts(
        _intList(baseAppearance['frame_indexes']),
        frames,
      );
      if (!_sameInts(
          appearanceFrames, _intList(baseAppearance['frame_indexes']))) {
        baseAppearance['frame_indexes'] = appearanceFrames;
        changed = true;
      }

      final stages = _list(role['stages']);
      var stage = _findStage(stages, assignment);
      if (stage == null && assignment['stage'] is Map) {
        stage = _minorSupplementMergeTarget(
          stages: stages,
          assignment: assignment,
          role: role,
        );
        if (stage == null) {
          stage = _newStage(
            assignment: assignment,
            role: role,
            frames: frames,
            existingStages: stages,
          );
          stages.add(stage);
          role['stages'] = stages;
          createdStages += 1;
          changed = true;
        }
      }
      if (stage == null && stages.length == 1) {
        stage = Map<String, dynamic>.from(stages.single as Map);
        stages[0] = stage;
        role['stages'] = stages;
      }
      if (stage == null) {
        warnings.add(
          'no stage selected for ${_string(role['source_role_id'])} frames ${frames.join(",")}',
        );
        continue;
      }

      final stageFrames = _mergeInts(_intList(stage['frame_indexes']), frames);
      if (!_sameInts(stageFrames, _intList(stage['frame_indexes']))) {
        stage['frame_indexes'] = stageFrames;
        assignedFrames += frames.length;
        changed = true;
      }
    }
  }

  return _ApplySummary(
    changed: changed,
    assignedFrames: assignedFrames,
    createdRoles: createdRoles,
    createdStages: createdStages,
    warnings: warnings,
  );
}

Map<String, dynamic>? _minorSupplementMergeTarget({
  required List<dynamic> stages,
  required Map<String, dynamic> assignment,
  required Map<String, dynamic> role,
}) {
  if (stages.isEmpty || assignment['create_role'] == true) {
    return null;
  }
  final supplement = _map(assignment['stage']);
  if (_string(supplement['identity']).trim().isNotEmpty) {
    return null;
  }
  final roleFieldKeys = const [
    'upper_body',
    'lower_body',
    'upper_clothing',
    'lower_clothing',
  ];
  final nonEmptyRoleFields = [
    for (final key in roleFieldKeys)
      if (_string(supplement[key]).trim().isNotEmpty) key,
  ];
  if (nonEmptyRoleFields.isEmpty || nonEmptyRoleFields.length > 2) {
    return null;
  }

  final fallbackIdentity = _roleFallbackIdentity(role);
  for (var index = 0; index < stages.length; index += 1) {
    final candidate = _map(stages[index]);
    if (_string(candidate['identity']).trim().isEmpty) {
      continue;
    }
    if (fallbackIdentity.isNotEmpty &&
        _string(candidate['identity']).trim() != fallbackIdentity) {
      continue;
    }
    for (final key in nonEmptyRoleFields) {
      candidate[key] = _mergedPromptField(
        _string(candidate[key]),
        _string(supplement[key]),
      );
    }
    stages[index] = candidate;
    return candidate;
  }
  return null;
}

String _mergedPromptField(String left, String right) {
  final terms = <String>[];
  final seen = <String>{};
  for (final value in [left, right]) {
    for (final term in value.split(',')) {
      final clean = term.trim();
      if (clean.isEmpty) continue;
      final key = clean.toLowerCase();
      if (seen.add(key)) {
        terms.add(clean);
      }
    }
  }
  return terms.join(', ');
}

Map<String, dynamic>? _findRole(
  List<dynamic> roles,
  Map<String, dynamic> assignment,
) {
  final sourceRoleId =
      _string(assignment['source_role_id'] ?? assignment['role_source_role_id'])
          .trim();
  final displayName =
      _string(assignment['display_name'] ?? assignment['role_display_name'])
          .trim()
          .toLowerCase();
  for (var index = 0; index < roles.length; index += 1) {
    final role = _map(roles[index]);
    final roleSourceId = _string(role['source_role_id']).trim();
    final roleDisplayName = _string(role['display_name']).trim().toLowerCase();
    if (sourceRoleId.isNotEmpty && roleSourceId == sourceRoleId) {
      roles[index] = role;
      return role;
    }
    if (sourceRoleId.isEmpty &&
        displayName.isNotEmpty &&
        roleDisplayName == displayName) {
      roles[index] = role;
      return role;
    }
  }
  return null;
}

Map<String, dynamic>? _findStage(
  List<dynamic> stages,
  Map<String, dynamic> assignment,
) {
  final stageId = _string(assignment['stage_id']).trim();
  if (stageId.isEmpty) {
    return null;
  }
  for (var index = 0; index < stages.length; index += 1) {
    final stage = _map(stages[index]);
    if (_string(stage['stage_id']).trim() == stageId) {
      stages[index] = stage;
      return stage;
    }
  }
  return null;
}

Map<String, dynamic> _newRole(
  Map<String, dynamic> assignment,
  List<int> frames,
) {
  final role = _map(assignment['role']);
  final sourceRoleId = _string(
    assignment['source_role_id'] ??
        role['source_role_id'] ??
        'global-${DateTime.now().microsecondsSinceEpoch}',
  );
  final displayName = _string(
    assignment['display_name'] ?? role['display_name'] ?? sourceRoleId,
  );
  return {
    'source_role_id': sourceRoleId,
    'source_kind': _string(role['source_kind']).trim().isEmpty
        ? 'global'
        : _string(role['source_kind']),
    'display_name': displayName,
    'confidence': _double(role['confidence'], fallback: 0.7),
    'frame_indexes': frames,
    'appearances': [
      {
        'source_id': 'base',
        'source_kind': 'base',
        'frame_indexes': frames,
      },
    ],
    'evidence_terms': _stringList(role['evidence_terms']),
    'warnings': _stringList(role['warnings']),
    'stages': <dynamic>[],
    'unassigned_terms': <dynamic>[],
  };
}

Map<String, dynamic> _newStage({
  required Map<String, dynamic> assignment,
  required Map<String, dynamic> role,
  required List<int> frames,
  required List<dynamic> existingStages,
}) {
  final stage = _map(assignment['stage']);
  final roleId = _string(role['source_role_id']).trim();
  final stageId = _string(stage['stage_id']).trim().isEmpty
      ? _uniqueStageId(existingStages, 'base-${_safeSegment(roleId)}')
      : _string(stage['stage_id']).trim();
  return {
    'stage_id': stageId,
    'label': _string(stage['label']).trim().isEmpty
        ? 'Base ${existingStages.length + 1}'
        : _string(stage['label']).trim(),
    'confidence': _double(stage['confidence'], fallback: 0.7),
    'frame_indexes': frames,
    'identity': _string(stage['identity']).trim().isEmpty
        ? _roleFallbackIdentity(role)
        : _string(stage['identity']),
    'upper_body': _string(stage['upper_body']),
    'lower_body': _string(stage['lower_body']),
    'upper_clothing': _string(stage['upper_clothing']),
    'lower_clothing': _string(stage['lower_clothing']),
    'non_role': _string(stage['non_role']),
    if (_string(stage['non_role']).trim().isNotEmpty)
      'non_role_materialized': true,
    'evidence_terms': _stringList(stage['evidence_terms']),
    'missing_fields': _stringList(stage['missing_fields']),
    'warnings': _stringList(stage['warnings']),
  };
}

String _roleFallbackIdentity(Map<String, dynamic> role) {
  for (final stage in _list(role['stages'])) {
    final identity = _string(_map(stage)['identity']).trim();
    if (identity.isNotEmpty) {
      return identity;
    }
  }
  final displayName = _string(role['display_name']).trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }
  return _string(role['source_role_id']).trim();
}

String _uniqueStageId(List<dynamic> stages, String base) {
  final used = {
    for (final stage in stages) _string(_map(stage)['stage_id']),
  };
  if (!used.contains(base)) {
    return base;
  }
  var suffix = 2;
  while (used.contains('$base-$suffix')) {
    suffix += 1;
  }
  return '$base-$suffix';
}

String _safeSegment(String value) {
  final clean = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return clean.isEmpty ? 'role' : clean;
}

bool _isBaseSource(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'base' ||
      normalized == 'global' ||
      normalized.startsWith('base-') ||
      normalized.startsWith('global-');
}

List<int> _mergeInts(List<int> left, List<int> right) {
  return ({...left, ...right}.toList()..sort());
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) => value is List ? value : <dynamic>[];

String _string(Object? value) => value?.toString() ?? '';

double _double(Object? value, {required double fallback}) {
  if (value is num) return value.toDouble();
  return double.tryParse(_string(value)) ?? fallback;
}

List<String> _stringList(Object? value) {
  return [for (final item in _list(value)) _string(item)];
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value)) ?? 0;
}

List<int> _intList(Object? value) {
  final result = <int>[];
  for (final item in _list(value)) {
    result.add(_int(item));
  }
  result.sort();
  return List.unmodifiable(result);
}

class _ApplySummary {
  final bool changed;
  final int assignedFrames;
  final int createdRoles;
  final int createdStages;
  final List<String> warnings;

  const _ApplySummary({
    required this.changed,
    required this.assignedFrames,
    required this.createdRoles,
    required this.createdStages,
    required this.warnings,
  });
}

class _Options {
  final String cacheDir;
  final String assignmentsDir;
  final bool dryRun;

  const _Options({
    required this.cacheDir,
    required this.assignmentsDir,
    required this.dryRun,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) continue;
      final equals = arg.indexOf('=');
      if (equals > 0) {
        values[arg.substring(2, equals)] = arg.substring(equals + 1);
        continue;
      }
      final key = arg.substring(2);
      if (index + 1 < args.length && !args[index + 1].startsWith('--')) {
        values[key] = args[index + 1];
        index += 1;
      } else {
        flags.add(key);
      }
    }
    final assignmentsDir = values['assignments-dir'];
    if (assignmentsDir == null || assignmentsDir.trim().isEmpty) {
      throw StateError('Missing --assignments-dir');
    }
    final appData = Platform.environment['APPDATA'] ?? '';
    final cacheDir = values['cache-dir'] ??
        [
          appData,
          'org.exception0x0194',
          'nai3_autodraw',
          'novel_studio',
          'script_recast',
          'cache',
        ].join(Platform.pathSeparator);
    return _Options(
      cacheDir: cacheDir,
      assignmentsDir: assignmentsDir,
      dryRun: flags.contains('dry-run'),
    );
  }
}
