import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_assembly_application.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final cacheDir = Directory(options.cacheDir);
  if (!await cacheDir.exists()) {
    throw StateError('Cache directory does not exist: ${cacheDir.path}');
  }
  if (options.apply && options.backupDir == null) {
    throw StateError('--backup-dir is required with --apply.');
  }

  final backupDir =
      options.backupDir == null ? null : Directory(options.backupDir!);
  if (options.apply) {
    await backupDir!.create(recursive: true);
  }

  final files = await cacheDir
      .list(followLinks: false)
      .where((entry) => entry is File && entry.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));

  final rows = <Map<String, Object?>>[];
  var matchedFiles = 0;
  var changedFiles = 0;
  var mergedRoleCount = 0;
  var staleReplacementGroupsRemoved = 0;
  var staleAssembliesRemoved = 0;

  for (final file in files) {
    final decoded = jsonDecode(await file.readAsString(encoding: utf8));
    if (decoded is! Map) {
      continue;
    }
    final cache = Map<String, dynamic>.from(decoded);
    if (!_isUnderSourceRoot(cache['sourceRootPath'], options.sourceRoot)) {
      continue;
    }
    matchedFiles += 1;

    final aiJson = cache['aiRoleExtraction'];
    final mappingJson = cache['mapping'];
    if (aiJson is! Map || mappingJson is! Map) {
      continue;
    }
    final extraction = ScriptAiRoleExtraction.fromJson(
      Map<String, dynamic>.from(aiJson),
    );
    if (!extraction.isReady || extraction.roles.isEmpty) {
      continue;
    }

    final duplicateGroupsBefore = _duplicateCanonicalGroups(extraction.roles);
    final staleAliasesBefore = _staleSameCharacterAliases(
      extraction.roles,
      Map<String, dynamic>.from(mappingJson),
    );
    if (duplicateGroupsBefore.isEmpty && staleAliasesBefore.isEmpty) {
      continue;
    }

    final beforeSnapshot = _canonicalJson(cache['scriptSnapshot']);
    final beforeSourceFingerprint = cache['sourceFingerprint'];
    final beforeSourceContentFingerprint = cache['sourceContentFingerprint'];
    final beforeRoleCount = extraction.roles.length;
    final beforeReplacementCount = _listLength(
      mappingJson['rolePromptReplacements'],
    );
    final beforeAssemblyCount = _listLength(mappingJson['roleAssemblies']);

    final collapsed = extraction.collapseEquivalentStages();
    cache['aiRoleExtraction'] = collapsed.toJson();
    final mapping = RecastMapping.fromJson(
      Map<String, dynamic>.from(mappingJson),
    );
    final application = const ScriptAiRoleAssemblyApplication().apply(
      mapping: mapping,
      extraction: collapsed,
      stageLabelFor: (stage, index) {
        final label = stage.label.trim();
        return label.isEmpty ? '阶段 ${index + 1}' : label;
      },
    );
    cache['mapping'] = application.mapping.toJson();

    if (_canonicalJson(cache['scriptSnapshot']) != beforeSnapshot ||
        cache['sourceFingerprint'] != beforeSourceFingerprint ||
        cache['sourceContentFingerprint'] != beforeSourceContentFingerprint) {
      throw StateError(
        'Source snapshot/fingerprint changed unexpectedly: ${file.path}',
      );
    }

    final afterExtraction = ScriptAiRoleExtraction.fromJson(
      Map<String, dynamic>.from(cache['aiRoleExtraction'] as Map),
    );
    final afterMapping = Map<String, dynamic>.from(cache['mapping'] as Map);
    final duplicateGroupsAfter = _duplicateCanonicalGroups(
      afterExtraction.roles,
    );
    final staleAliasesAfter = _staleSameCharacterAliases(
      afterExtraction.roles,
      afterMapping,
    );
    final duplicateStageLabelsAfter = _duplicateStageLabelGroups(
      afterExtraction.roles,
    );
    if (duplicateGroupsAfter.isNotEmpty ||
        staleAliasesAfter.isNotEmpty ||
        duplicateStageLabelsAfter.isNotEmpty) {
      throw StateError(
        'Same-character reconciliation incomplete for ${file.path}: '
        'duplicates=$duplicateGroupsAfter stale=$staleAliasesAfter '
        'duplicate_stage_labels=$duplicateStageLabelsAfter',
      );
    }

    final afterRoleCount = afterExtraction.roles.length;
    final afterReplacementCount = _listLength(
      afterMapping['rolePromptReplacements'],
    );
    final afterAssemblyCount = _listLength(afterMapping['roleAssemblies']);
    final changed = _canonicalJson(decoded) != _canonicalJson(cache);
    if (changed) {
      changedFiles += 1;
      mergedRoleCount += beforeRoleCount - afterRoleCount;
      staleReplacementGroupsRemoved +=
          beforeReplacementCount - afterReplacementCount;
      staleAssembliesRemoved += beforeAssemblyCount - afterAssemblyCount;
      if (options.apply) {
        await file.copy(
          _joinPath(backupDir!.path, file.uri.pathSegments.last),
        );
        await file.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(cache)}\n',
          encoding: utf8,
          flush: true,
        );
      }
    }

    rows.add({
      'file_name': file.uri.pathSegments.last,
      'script_id': cache['scriptId'],
      'script_name': cache['scriptName'],
      'changed': changed,
      'duplicate_groups_before': duplicateGroupsBefore,
      'stale_aliases_before': staleAliasesBefore,
      'role_count_before': beforeRoleCount,
      'role_count_after': afterRoleCount,
      'replacement_group_count_before': beforeReplacementCount,
      'replacement_group_count_after': afterReplacementCount,
      'assembly_count_before': beforeAssemblyCount,
      'assembly_count_after': afterAssemblyCount,
      'source_snapshot_unchanged': true,
    });
  }

  final report = <String, Object?>{
    'cache_dir': cacheDir.path,
    'source_root': options.sourceRoot,
    'apply': options.apply,
    'backup_dir': options.apply ? backupDir!.path : '',
    'files_scanned': files.length,
    'files_matched': matchedFiles,
    'files_changed': changedFiles,
    'roles_merged': mergedRoleCount,
    'stale_replacement_groups_removed': staleReplacementGroupsRemoved,
    'stale_assemblies_removed': staleAssembliesRemoved,
    'rows': rows,
  };
  if (options.reportPath != null) {
    final reportFile = File(options.reportPath!);
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      encoding: utf8,
      flush: true,
    );
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

List<Map<String, Object?>> _duplicateCanonicalGroups(
  List<ScriptAiExtractedRole> roles,
) {
  final byName = <String, List<ScriptAiExtractedRole>>{};
  for (final role in roles) {
    final name = _normalizedName(role.canonicalName);
    if (name.isEmpty) {
      continue;
    }
    byName.putIfAbsent(name, () => []).add(role);
  }
  return [
    for (final entry in byName.entries)
      if (entry.value.length > 1)
        {
          'canonical_name': entry.key,
          'source_role_ids': [
            for (final role in entry.value) role.sourceRoleId,
          ],
          'display_names': [
            for (final role in entry.value) role.displayName,
          ],
        },
  ];
}

List<Map<String, Object?>> _duplicateStageLabelGroups(
  List<ScriptAiExtractedRole> roles,
) {
  final result = <Map<String, Object?>>[];
  for (final role in roles) {
    final stagesByLabel = <String, List<ScriptAiExtractedStage>>{};
    for (final stage in role.stages) {
      final key = stage.label
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\s/|,，、;；:：]+'), '');
      if (key.isEmpty) {
        continue;
      }
      stagesByLabel.putIfAbsent(key, () => []).add(stage);
    }
    for (final entry in stagesByLabel.entries) {
      if (entry.value.length <= 1) {
        continue;
      }
      result.add({
        'source_role_id': role.sourceRoleId,
        'label': entry.value.first.label,
        'stage_ids': [for (final stage in entry.value) stage.stageId],
      });
    }
  }
  return result;
}

List<Map<String, Object?>> _staleSameCharacterAliases(
  List<ScriptAiExtractedRole> roles,
  Map<String, dynamic> mapping,
) {
  final roleIds = {
    for (final role in roles) role.sourceRoleId.trim(),
  };
  final rolesByAlias = _rolesByUniqueAlias(roles);
  final result = <Map<String, Object?>>[];

  void inspect(Object? groups, String section) {
    if (groups is! List) {
      return;
    }
    for (final value in groups) {
      if (value is! Map) {
        continue;
      }
      final sourceRoleId = '${value['sourceRoleId'] ?? ''}'.trim();
      if (sourceRoleId.isEmpty || roleIds.contains(sourceRoleId)) {
        continue;
      }
      final targetRole = rolesByAlias[_sourceRoleAlias(sourceRoleId)];
      if (targetRole == null) {
        continue;
      }
      result.add({
        'section': section,
        'stale_source_role_id': sourceRoleId,
        'surviving_source_role_id': targetRole.sourceRoleId,
      });
    }
  }

  inspect(mapping['rolePromptReplacements'], 'rolePromptReplacements');
  inspect(mapping['roleAssemblies'], 'roleAssemblies');
  return result;
}

Map<String, ScriptAiExtractedRole> _rolesByUniqueAlias(
  List<ScriptAiExtractedRole> roles,
) {
  final candidates = <String, List<ScriptAiExtractedRole>>{};
  for (final role in roles) {
    for (final alias in _aliasesForRole(role)) {
      candidates.putIfAbsent(alias, () => []).add(role);
    }
  }
  return {
    for (final entry in candidates.entries)
      if (entry.value.length == 1) entry.key: entry.value.single,
  };
}

Set<String> _aliasesForRole(ScriptAiExtractedRole role) {
  final aliases = <String>{};

  void add(String value, {bool sourceRoleId = false}) {
    final alias =
        sourceRoleId ? _sourceRoleAlias(value) : _identityAlias(value);
    if (alias.isNotEmpty) {
      aliases.add(alias);
    }
  }

  add(role.sourceRoleId, sourceRoleId: true);
  add(role.canonicalName);
  add(role.displayName.split('/').first);
  for (final tag in role.rawIdentityTags) {
    add(tag);
  }
  for (final term in role.promptTerms) {
    if (term.category == PromptTagCategory.character) {
      add(term.text);
    }
  }
  for (final stage in role.stages) {
    for (final term in PromptTagProcessor.splitWorkshopTags(stage.identity)) {
      add(PromptTagProcessor.cleanTagDisplay(term));
    }
  }
  return aliases;
}

String _sourceRoleAlias(String value) {
  return _identityAlias(value).replaceFirst(RegExp(r'^role-'), '');
}

String _identityAlias(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _normalizedName(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isUnderSourceRoot(Object? value, String sourceRoot) {
  final path = _normalizedPath('$value');
  final root = _normalizedPath(sourceRoot);
  return path == root || path.startsWith('$root/');
}

String _normalizedPath(String value) {
  return value
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+'), '/')
      .toLowerCase();
}

int _listLength(Object? value) => value is List ? value.length : 0;

String _canonicalJson(Object? value) {
  Object? normalize(Object? current) {
    if (current is Map) {
      final keys = current.keys.map((key) => '$key').toList()..sort();
      return {
        for (final key in keys) key: normalize(current[key]),
      };
    }
    if (current is List) {
      return [for (final item in current) normalize(item)];
    }
    return current;
  }

  return jsonEncode(normalize(value));
}

String _joinPath(String directory, String fileName) {
  return '$directory${Platform.pathSeparator}$fileName';
}

class _Options {
  final String cacheDir;
  final String sourceRoot;
  final bool apply;
  final String? backupDir;
  final String? reportPath;

  const _Options({
    required this.cacheDir,
    required this.sourceRoot,
    required this.apply,
    required this.backupDir,
    required this.reportPath,
  });

  factory _Options.parse(List<String> args) {
    var cacheDir = _defaultCacheDir();
    String? sourceRoot;
    var apply = false;
    String? backupDir;
    String? reportPath;
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--apply') {
        apply = true;
      } else if (arg == '--cache-dir' && index + 1 < args.length) {
        cacheDir = args[++index];
      } else if (arg.startsWith('--cache-dir=')) {
        cacheDir = arg.substring('--cache-dir='.length);
      } else if (arg == '--source-root' && index + 1 < args.length) {
        sourceRoot = args[++index];
      } else if (arg.startsWith('--source-root=')) {
        sourceRoot = arg.substring('--source-root='.length);
      } else if (arg == '--backup-dir' && index + 1 < args.length) {
        backupDir = args[++index];
      } else if (arg.startsWith('--backup-dir=')) {
        backupDir = arg.substring('--backup-dir='.length);
      } else if (arg == '--report' && index + 1 < args.length) {
        reportPath = args[++index];
      } else if (arg.startsWith('--report=')) {
        reportPath = arg.substring('--report='.length);
      } else {
        throw StateError('Unknown argument: $arg');
      }
    }
    if (sourceRoot == null || sourceRoot.trim().isEmpty) {
      throw StateError('--source-root is required.');
    }
    return _Options(
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      apply: apply,
      backupDir: backupDir,
      reportPath: reportPath,
    );
  }
}

String _defaultCacheDir() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.trim().isEmpty) {
    throw StateError('APPDATA is unavailable; pass --cache-dir.');
  }
  return _joinPath(
    _joinPath(
      _joinPath(
        _joinPath(appData, 'Novel Studio'),
        'Novel Studio',
      ),
      'novel_studio',
    ),
    _joinPath('script_recast', 'cache'),
  );
}
