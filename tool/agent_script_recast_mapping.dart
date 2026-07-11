import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/workspace/workspace_json_codecs.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';

Future<void> main(List<String> args) async {
  final exitCode = await runAgentScriptRecastMapping(args);
  if (exitCode != 0) {
    // Keep main usable from `dart run`; tests call the runner directly.
    exit(exitCode);
  }
}

Future<int> runAgentScriptRecastMapping(List<String> args) async {
  try {
    final options = _Options.parse(args);
    final cacheFile = options.cacheFile;
    final original = await _readCache(cacheFile);
    final patch = await _readPatch(options.patchFile);
    _validatePatchTarget(
      cache: original,
      patch: patch,
      requestedScriptId: options.scriptId,
    );

    final updated = _cacheWithAppliedPatch(original, patch);
    _validateAiExtractionUnchanged(original, updated);

    stdout.writeln(
      [
        'script=${updated.scriptId}',
        'role_groups=${updated.mapping.rolePromptReplacements.length}',
        'scene_groups=${updated.mapping.scenePromptReplacements.length}',
        if (options.dryRun) 'dry_run=true',
      ].join(' '),
    );

    if (options.dryRun) {
      return 0;
    }

    final backupFile = await _backupCache(
      cacheFile: cacheFile,
      backupDir: options.backupDir,
    );
    await _writeCache(cacheFile, updated);
    stdout.writeln('backup=${backupFile.path}');
    stdout.writeln('updated=${cacheFile.path}');
    return 0;
  } catch (error) {
    stderr.writeln(error);
    return 1;
  }
}

RecastScriptCache _cacheWithAppliedPatch(
  RecastScriptCache cache,
  _MappingPatch patch,
) {
  final mapping = cache.mapping.copyWith(
    rolePromptReplacements: _upsertRoleReplacements(
      current: cache.mapping.rolePromptReplacements,
      incoming: patch.rolePromptReplacements,
    ),
    scenePromptReplacements: _upsertSceneReplacements(
      current: cache.mapping.scenePromptReplacements,
      incoming: patch.scenePromptReplacements,
    ),
  );
  return RecastScriptCache(
    scriptId: cache.scriptId,
    scriptName: cache.scriptName,
    sourceRootPath: cache.sourceRootPath,
    sourceFingerprint: cache.sourceFingerprint,
    sourceContentFingerprint: cache.sourceContentFingerprint,
    updatedAt: DateTime.now().toUtc(),
    roleCandidates: cache.roleCandidates,
    mapping: mapping,
    aiRoleExtraction: cache.aiRoleExtraction,
    aiRoleExtractionChunks: cache.aiRoleExtractionChunks,
    aiRoleExtractionDraftCollapsed: cache.aiRoleExtractionDraftCollapsed,
    scriptBlockWords: cache.scriptBlockWords,
    knowledgeSnapshot: cache.knowledgeSnapshot,
    exhibitionCategoryNames: cache.exhibitionCategoryNames,
    scriptSnapshot: cache.scriptSnapshot,
  );
}

List<ScriptRolePromptReplacement> _upsertRoleReplacements({
  required List<ScriptRolePromptReplacement> current,
  required List<ScriptRolePromptReplacement> incoming,
}) {
  if (incoming.isEmpty) {
    return current;
  }
  final incomingByRoleId = {
    for (final replacement in incoming)
      replacement.sourceRoleId.trim(): replacement,
  }..remove('');
  var changed = false;
  final next = <ScriptRolePromptReplacement>[];
  for (final replacement in current) {
    final sourceRoleId = replacement.sourceRoleId.trim();
    final incomingReplacement = incomingByRoleId.remove(sourceRoleId);
    if (incomingReplacement == null) {
      next.add(replacement);
      continue;
    }
    next.add(incomingReplacement);
    changed = true;
  }
  if (incomingByRoleId.isNotEmpty) {
    next.addAll(incomingByRoleId.values);
    changed = true;
  }
  return changed ? List.unmodifiable(next) : current;
}

List<ScriptScenePromptReplacement> _upsertSceneReplacements({
  required List<ScriptScenePromptReplacement> current,
  required List<ScriptScenePromptReplacement> incoming,
}) {
  if (incoming.isEmpty) {
    return current;
  }
  final incomingById = {
    for (final replacement in incoming) replacement.id.trim(): replacement,
  }..remove('');
  var changed = false;
  final next = <ScriptScenePromptReplacement>[];
  for (final replacement in current) {
    final id = replacement.id.trim();
    final incomingReplacement = incomingById.remove(id);
    if (incomingReplacement == null) {
      next.add(replacement);
      continue;
    }
    next.add(incomingReplacement);
    changed = true;
  }
  if (incomingById.isNotEmpty) {
    next.addAll(incomingById.values);
    changed = true;
  }
  return changed ? List.unmodifiable(next) : current;
}

void _validatePatchTarget({
  required RecastScriptCache cache,
  required _MappingPatch patch,
  required String? requestedScriptId,
}) {
  final patchScriptId = patch.scriptId.trim();
  if (patchScriptId.isEmpty) {
    throw const FormatException('Patch must include scriptId.');
  }
  if (patchScriptId != cache.scriptId) {
    throw FormatException(
      'Patch scriptId "$patchScriptId" does not match cache '
      'scriptId "${cache.scriptId}".',
    );
  }
  final requested = requestedScriptId?.trim() ?? '';
  if (requested.isNotEmpty && requested != cache.scriptId) {
    throw FormatException(
      'Requested scriptId "$requested" does not match cache '
      'scriptId "${cache.scriptId}".',
    );
  }
}

void _validateAiExtractionUnchanged(
  RecastScriptCache before,
  RecastScriptCache after,
) {
  final beforeJson = jsonEncode(before.aiRoleExtraction.toJson());
  final afterJson = jsonEncode(after.aiRoleExtraction.toJson());
  if (beforeJson != afterJson) {
    throw StateError('Refusing to write: aiRoleExtraction changed.');
  }
}

Future<RecastScriptCache> _readCache(File file) async {
  if (!await file.exists()) {
    throw FileSystemException('Cache file does not exist', file.path);
  }
  final decoded = jsonDecode(await file.readAsString(encoding: utf8));
  if (decoded is! Map) {
    throw FormatException(
        'Cache file must contain a JSON object: ${file.path}');
  }
  final compacted = RecastCacheJsonCodec.compact(
    Map<String, dynamic>.from(decoded),
  );
  return RecastScriptCache.fromJson(compacted.value);
}

Future<void> _writeCache(File file, RecastScriptCache cache) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(
      RecastCacheJsonCodec.compact(cache.toJson()).value,
    ),
    encoding: utf8,
  );
}

Future<_MappingPatch> _readPatch(File file) async {
  if (!await file.exists()) {
    throw FileSystemException('Patch file does not exist', file.path);
  }
  final decoded = jsonDecode(await file.readAsString(encoding: utf8));
  if (decoded is! Map) {
    throw FormatException(
        'Patch file must contain a JSON object: ${file.path}');
  }
  return _MappingPatch.fromJson(Map<String, dynamic>.from(decoded));
}

Future<File> _backupCache({
  required File cacheFile,
  Directory? backupDir,
}) async {
  final targetDir = backupDir ?? _defaultBackupDir();
  await targetDir.create(recursive: true);
  final backupFile = File(
    _joinPath(
      targetDir.path,
      '${_timestamp()}-${_safeFileName(cacheFile.path)}',
    ),
  );
  return cacheFile.copy(backupFile.path);
}

Directory _defaultBackupDir() {
  return Directory(
    _joinPath(
      Directory.current.path,
      'build',
      'script_recast_agent_mapping_backups',
      _timestamp(),
    ),
  );
}

String _timestamp() {
  return DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-');
}

String _safeFileName(String path) {
  final normalized = path.replaceAll('\\', '/').split('/').last;
  return normalized
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _joinPath(String first, String second, [String? third, String? fourth]) {
  return [
    first,
    second,
    if (third != null) third,
    if (fourth != null) fourth,
  ].join(Platform.pathSeparator);
}

class _MappingPatch {
  final String scriptId;
  final List<ScriptRolePromptReplacement> rolePromptReplacements;
  final List<ScriptScenePromptReplacement> scenePromptReplacements;

  const _MappingPatch({
    required this.scriptId,
    required this.rolePromptReplacements,
    required this.scenePromptReplacements,
  });

  factory _MappingPatch.fromJson(Map<String, dynamic> json) {
    return _MappingPatch(
      scriptId: json['scriptId'] as String? ?? '',
      rolePromptReplacements: [
        for (final value in json['rolePromptReplacements'] as List? ?? const [])
          ScriptRolePromptReplacement.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
      ],
      scenePromptReplacements: [
        for (final value
            in json['scenePromptReplacements'] as List? ?? const [])
          ScriptScenePromptReplacement.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
      ],
    );
  }
}

class _Options {
  final File cacheFile;
  final File patchFile;
  final Directory? backupDir;
  final String? scriptId;
  final bool dryRun;

  const _Options({
    required this.cacheFile,
    required this.patchFile,
    required this.backupDir,
    required this.scriptId,
    required this.dryRun,
  });

  factory _Options.parse(List<String> args) {
    if (args.isEmpty || args.first != 'apply') {
      throw const FormatException(
        'Usage: apply --patch <file> '
        '(--cache-file <file> | --workspace <dir> --script-id <id>) '
        '[--backup-dir <dir>] [--dry-run]',
      );
    }
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 1; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) {
        throw FormatException('Unexpected positional argument: $arg');
      }
      final key = arg.substring(2);
      if (key == 'dry-run') {
        flags.add(key);
        continue;
      }
      if (index + 1 >= args.length) {
        throw FormatException('Missing value for --$key');
      }
      values[key] = args[++index];
    }

    final patchPath = values['patch']?.trim() ?? '';
    if (patchPath.isEmpty) {
      throw const FormatException('Missing --patch <file>.');
    }

    final cacheFilePath = values['cache-file']?.trim() ?? '';
    final workspacePath = values['workspace']?.trim() ?? '';
    final scriptId = values['script-id']?.trim();
    if (cacheFilePath.isNotEmpty && workspacePath.isNotEmpty) {
      throw const FormatException(
        'Use either --cache-file or --workspace, not both.',
      );
    }
    if (cacheFilePath.isEmpty && workspacePath.isEmpty) {
      throw const FormatException(
        'Missing cache target. Use --cache-file or --workspace.',
      );
    }
    if (workspacePath.isNotEmpty && (scriptId == null || scriptId.isEmpty)) {
      throw const FormatException('--workspace requires --script-id.');
    }

    return _Options(
      cacheFile: cacheFilePath.isNotEmpty
          ? File(cacheFilePath)
          : _cacheFileForWorkspace(
              workspace: Directory(workspacePath),
              scriptId: scriptId!,
            ),
      patchFile: File(patchPath),
      backupDir: (values['backup-dir']?.trim().isNotEmpty ?? false)
          ? Directory(values['backup-dir']!.trim())
          : null,
      scriptId: scriptId,
      dryRun: flags.contains('dry-run'),
    );
  }
}

File _cacheFileForWorkspace({
  required Directory workspace,
  required String scriptId,
}) {
  final safeId = safeWorkspaceEntityId(prefix: 'script', id: scriptId);
  return File(_joinPath(
    workspace.path,
    WorkspacePaths.scriptRecastCacheFile(safeId)
        .replaceAll('/', Platform.pathSeparator),
  ));
}
